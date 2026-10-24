'use strict';

// SPDX-License-Identifier: GPL-2.0
/*
 * mtwifi ucode support - hostapd 配置生成与进程管理
 *
 * Copyright (C) 2024 Felix Fietkau <nbd@nbd.name>
 * Copyright (C) 2026 nanchuci <nanchuci023@gmail.com>
 *
 * 设备级（radio）配置生成来自官方 wifi-scripts 的
 * usr/share/ucode/wifi/hostapd.uc:generate() 逻辑（原 shell 版是
 * netifd/wireless/mac80211.sh 的 mac80211_hostapd_setup_base），
 * 并按 MTK 驱动的既有行为做了三处调整：
 *
 *   1. 频道为 auto 时写 hw_mode=any（MTK hostapd 有
 *      WPA_DRIVER_FLAGS_SUPPORT_HW_MODE_ANY 补丁），而非官方 ucode 的
 *      hw_mode=g/a + channel=0；
 *   2. 6G EHT320 使用 MTK hostapd 的 eht_oper_chwidth=9 +
 *      eht_bw320_offset 约定（官方 ucode 用 7）；
 *   3. BSS 段复用官方 wifi.ap.generate()，但为每个 BSS 注入
 *      use_driver_iface_addr=1（MTK 驱动自己派生 BSS MAC）。
 *
 * hostapd 进程由本模块直接以 `hostapd -B -P <pidfile> <conf>` 启动，
 * 而不是走官方 ucode 的 `ubus call hostapd config_set`：本仓库的
 * hostapd 只提供旧的 ubus API（config_add/config_remove），
 * 详见 README 的“与 25.12 官方框架的差异”一节。
 */

import * as fs from 'fs';
import {
	append, append_raw, append_vars, comment, dump_config, flush_config, set_default
} from 'wifi.common';
import * as ap from 'wifi.ap';
import * as netifd from 'wifi.netifd';
import { device_capabilities } from 'mtwifi.caps';
import { log, trim, readfile, writefile, exists, shell_quote, sleep } from 'mtwifi.common';

const HOSTAPD = '/usr/sbin/hostapd';
const HOSTAPD_CLI = '/usr/sbin/hostapd_cli';
const WPS_ER_SCRIPT = '/usr/share/ucode/mtwifi/wps-er.uc';
const CTRL_DIR = '/var/run/hostapd';

const DEFAULT_HT_CAPAB = {
	ldpc: 1, greenfield: 0, short_gi_20: 1, short_gi_40: 1, tx_stbc: 1,
	rx_stbc: 3, max_amsdu: 1, dsss_cck_40: 1, intolerant_40: 1,
};

const DEFAULT_VHT_CAPAB = {
	rxldpc: 1, short_gi_80: 1, short_gi_160: 1, tx_stbc_2by1: 1,
	su_beamformer: 1, su_beamformee: 1, mu_beamformer: 1, mu_beamformee: 1,
	vht_txop_ps: 1, htc_vht: 1, beamformee_antennas: 5, beamformer_antennas: 4,
	rx_antenna_pattern: 1, tx_antenna_pattern: 1, vht_max_a_mpdu_len_exp: 7,
	vht_max_mpdu: 11454, vht_link_adapt: 3, vht160: 2,
};

const DEFAULT_HE_CAPAB = {
	he_su_beamformer: 1, he_su_beamformee: 1, he_mu_beamformer: 1, he_ldpc: 1,
	he_twt_required: 0, he_twt_responder: 0, he_spr_sr_control: 3, he_spr_psr_enabled: 0,
	he_spr_non_srg_obss_pd_max_offset: 0, he_bss_color: 128,
	he_bss_color_enabled: 1, he_default_pe_duration: 4, he_rts_threshold: 1023,
	he_mu_edca_qos_info_param_count: 0, he_mu_edca_qos_info_q_ack: 0,
	he_mu_edca_qos_info_queue_request: 0, he_mu_edca_qos_info_txop_request: 0,
	he_mu_edca_ac_be_aifsn: 8, he_mu_edca_ac_be_aci: 0, he_mu_edca_ac_be_ecwmin: 9,
	he_mu_edca_ac_be_ecwmax: 10, he_mu_edca_ac_be_timer: 255,
	he_mu_edca_ac_bk_aifsn: 15, he_mu_edca_ac_bk_aci: 1, he_mu_edca_ac_bk_ecwmin: 9,
	he_mu_edca_ac_bk_ecwmax: 10, he_mu_edca_ac_bk_timer: 255,
	he_mu_edca_ac_vi_ecwmin: 5, he_mu_edca_ac_vi_ecwmax: 7, he_mu_edca_ac_vi_aifsn: 5,
	he_mu_edca_ac_vi_aci: 2, he_mu_edca_ac_vi_timer: 255,
	he_mu_edca_ac_vo_aifsn: 5, he_mu_edca_ac_vo_aci: 3, he_mu_edca_ac_vo_ecwmin: 5,
	he_mu_edca_ac_vo_ecwmax: 7, he_mu_edca_ac_vo_timer: 255,
};

const DEFAULT_EHT_CAPAB = {
	eht_su_beamformer: 1, eht_su_beamformee: 1, eht_mu_beamformer: 1,
};

const LOG_OPTIONS = [
	'log_mlme', 'log_iapp', 'log_driver', 'log_wpa',
	'log_radius', 'log_8021x', 'log_80211',
];

/* ------------------------------------------------------------------ */
/* 路径与公共小工具                                                    */
/* ------------------------------------------------------------------ */

export function suffix_of(radio) {
	if (radio == null || +radio < 0)
		return '';

	return '.' + int(radio);
};

export function conf_path(phy, suffix) {
	return `/var/run/hostapd-${phy}${suffix ?? ''}.conf`;
};

export function pid_path(phy, suffix) {
	return `/var/run/hostapd-${phy}${suffix ?? ''}.pid`;
};

function apply_defaults(config, defaults) {
	for (let key, value in defaults)
		set_default(config, key, value);
};

function rand_bss_color() {
	let f = fs.open('/dev/urandom', 'r');
	let byte = 0;

	if (f) {
		byte = ord(f.read(1) ?? '\0');
		f.close();
	}

	return (byte % 63) + 1;
};

/* ------------------------------------------------------------------ */
/* 设备段生成                                                          */
/* ------------------------------------------------------------------ */

function set_device_defaults(config) {
	if (config.hw_mode in [ '11a', '11b', '11g', '11ad' ])
		config.hw_mode = substr(config.hw_mode, 2);
	else if (config.hw_mode == null)
		config.hw_mode = (+config.channel > 14) ? 'a' : 'g';

	if (config.band == '2g') {
		config.hw_mode = 'g';
	} else if (config.band in [ '5g', '6g' ]) {
		config.hw_mode = 'a';
	} else if (config.band == '60g') {
		config.hw_mode = 'ad';
	} else {
		switch (config.hw_mode) {
		case 'a':
			config.band = '5g';
			break;
		case 'ad':
			config.band = '60g';
			break;
		default:
			config.band = '2g';
			break;
		}
	}
};

function device_log_append(config) {
	let log_mask = 0;

	for (let k in LOG_OPTIONS) {
		log_mask <<= 1;
		log_mask |= config[k] ? 1 : 0;
	}

	append('logger_syslog', log_mask);
	append('logger_syslog_level', config.log_level);
	append('logger_stdout', log_mask);
	append('logger_stdout_level', config.log_level);
};

function device_country_code(config) {
	let country = config.country_code ?? config.country;

	if (!country)
		return;

	append('country_code', country);
	append('country3', config.country3);

	if (config.country_ie ?? true) {
		append('ieee80211d', 1);
		append_vars(config, [ 'local_pwr_constraint', 'spectrum_mgmt_required' ]);
	}

	if (config.hw_mode == 'a' && config.band == '5g' && (config.ieee80211h ?? config.doth))
		append('ieee80211h', 1);
};

function device_cell_density_append(config) {
	let cd = +config.cell_density;

	switch (config.hw_mode) {
	case 'b':
		if (cd == 1) {
			config.supported_rates ??= [ 5500, 11000 ];
			config.basic_rates ??= [ 5500, 11000 ];
		} else if (cd > 2) {
			config.supported_rates ??= [ 11000 ];
			config.basic_rates ??= [ 11000 ];
		}
		break;

	case 'g':
		if (cd in [ 0, 1 ]) {
			if (!config.legacy_rates) {
				config.supported_rates ??= [ 6000, 9000, 12000, 18000, 24000, 36000, 48000, 54000 ];
				config.basic_rates ??= [ 6000, 12000, 24000 ];
			} else if (cd == 1) {
				config.supported_rates ??= [ 5500, 6000, 9000, 11000, 12000, 18000, 24000, 36000, 48000, 54000 ];
				config.basic_rates ??= [ 5500, 11000 ];
			}
		} else if (cd == 2 || (cd > 3 && config.legacy_rates)) {
			if (!config.legacy_rates) {
				config.supported_rates ??= [ 12000, 18000, 24000, 36000, 48000, 54000 ];
				config.basic_rates ??= [ 12000, 24000 ];
			} else {
				config.supported_rates ??= [ 11000, 12000, 18000, 24000, 36000, 48000, 54000 ];
				config.basic_rates ??= [ 11000 ];
			}
		} else if (cd > 2) {
			config.supported_rates ??= [ 24000, 36000, 48000, 54000 ];
			config.basic_rates ??= [ 24000 ];
		}
		break;

	case 'a':
		switch (cd) {
		case 1:
			config.supported_rates ??= [ 6000, 9000, 12000, 18000, 24000, 36000, 48000, 54000 ];
			config.basic_rates ??= [ 6000, 12000, 24000 ];
			break;
		case 2:
			config.supported_rates ??= [ 12000, 18000, 24000, 36000, 48000, 54000 ];
			config.basic_rates ??= [ 12000, 24000 ];
			break;
		case 3:
			config.supported_rates ??= [ 24000, 36000, 48000, 54000 ];
			config.basic_rates ??= [ 24000 ];
			break;
		}
		break;
	}
};

function device_rates(config) {
	/*
	 * 2.4G 必须包含 CCK 速率（1/2/5.5/11 Mbps）。
	 * 上层 device_cell_density_append() 只给了 OFDM 速率
	 * （6000/9000/...），缺少 CCK，hostapd 会报：
	 *   No rates remaining in supported/basic rate sets (0,0).
	 *   Failed to prepare rates table.
	 * 并拒绝启动 ra0。
	 */
	if (config.hw_mode == 'g') {
		let cc = [ 1000, 2000, 5500, 11000 ];

		if (!config.supported_rates)
			config.supported_rates = [];
		if (!config.basic_rates)
			config.basic_rates = [];

		for (let r in cc) {
			if (index(config.supported_rates, r) < 0)
				push(config.supported_rates, r);
			if (index(config.basic_rates, r) < 0)
				push(config.basic_rates, r);
		}
	}

	for (let key in [ 'supported_rates', 'basic_rates' ])
		if (config[key])
			config[key] = map(config[key], (x) => +x / 100);

	append_vars(config, [ 'beacon_rate', 'supported_rates', 'basic_rates' ]);
};

/* MTK：6G EHT320 的 center/width 约定与官方 ucode 不同 */
function device_eht320(config) {
	let eht_center_seg0_map = [ [ 61, 31 ], [ 125, 95 ], [ 189, 159 ], [ 221, 191 ] ];
	let idx = 0;

	for (let k, pair in eht_center_seg0_map)
		if (config.channel <= pair[0]) {
			idx = pair[1];
			break;
		}

	/* 与 shell 版一致：EHT320-1 不能用于 193 以上，EHT320-2 不能用于 29 以下 */
	if ((config.htmode == 'EHT320-1' && config.channel >= 193) ||
	    (config.htmode == 'EHT320-2' && config.channel <= 29))
		return false;

	if (config.htmode == 'EHT320-2' && config.channel <= 189) {
		if (config.channel > idx)
			idx += 32;
		else
			idx -= 32;
	}

	config.vht_oper_chwidth = 2;
	config.vht_oper_centr_freq_seg0_idx = (config.channel > idx) ? idx + 16 : idx - 16;
	config.eht_oper_chwidth = 9;
	config.eht_oper_centr_freq_seg0_idx = idx;
	config.op_class = 137;

	switch (config.htmode) {
	case 'EHT320-1':
	case 'EHT320-2':
		config.eht_bw320_offset = 1;
		break;
	case 'EHT320':
		config.eht_bw320_offset = 0;
		break;
	}

	return true;
};

function device_htmode_append(config, caps) {
	let htmode = config.htmode ?? 'NOHT';

	config.channel_offset = (config.band == '6g') ? 1 : 0;

	/* 802.11n */
	config.ieee80211n = 0;
	if (config.band != '6g') {
		if (htmode in [ 'VHT20', 'HT20', 'HE20', 'EHT20' ]) {
			config.ieee80211n = 1;
			config.ht_capab = '';
		}
		if (htmode in [ 'HT40', 'HT40+', 'HT40-', 'VHT40', 'VHT80', 'VHT160',
				'HE40', 'HE80', 'HE160', 'EHT40', 'EHT80', 'EHT160' ]) {
			config.ieee80211n = 1;
			if (!config.channel) {
				config.ht_capab = '[HT40+]';
			} else if (config.hw_mode == 'a') {
				config.ht_capab = ((int(config.channel / 4) + config.channel_offset) % 2)
					? '[HT40+]' : '[HT40-]';
			} else {
				switch (htmode) {
				case 'HT40+':
				case 'HT40-':
					config.ht_capab = '[' + htmode + ']';
					break;
				default:
					config.ht_capab = (config.channel < 7) ? '[HT40+]' : '[HT40-]';
					break;
				}
			}
		}

		if (config.ieee80211n) {
			apply_defaults(config, DEFAULT_HT_CAPAB);

			let ht = caps.ht_capa;

			if (ht & 0x1 && config.ldpc)
				config.ht_capab += '[LDPC]';
			if (ht & 0x10 && config.greenfield)
				config.ht_capab += '[GF]';
			if (ht & 0x20 && config.short_gi_20)
				config.ht_capab += '[SHORT-GI-20]';
			if (ht & 0x40 && config.short_gi_40)
				config.ht_capab += '[SHORT-GI-40]';
			if (ht & 0x80 && config.tx_stbc)
				config.ht_capab += '[TX-STBC]';
			if (ht & 0x800 && config.max_amsdu)
				config.ht_capab += '[MAX-AMSDU-7935]';
			if (ht & 0x1000 && config.dsss_cck_40)
				config.ht_capab += '[DSSS_CCK-40]';
			if (ht & 0x4000 && config.intolerant_40)
				config.ht_capab += '[40-INTOLERANT]';

			let rx_stbc = [ '', '[RX-STBC1]', '[RX-STBC12]', '[RX-STBC123]' ];
			config.ht_capab += rx_stbc[min(config.rx_stbc, (ht >> 8) & 3)];

			append_vars(config, [ 'ieee80211n', 'ht_coex', 'ht_capab' ]);

			/* 与 shell 版一致：开启 ht_coex 时补 obss_interval */
			if (config.ht_coex) {
				set_default(config, 'obss_interval', 300);
				append_vars(config, [ 'obss_interval' ]);
			}
		}
	}

	/* 802.11ac */
	config.ieee80211ac = 1;
	config.vht_oper_centr_freq_seg0_idx = 0;
	config.vht_oper_chwidth = 0;

	switch (htmode) {
	case 'VHT20':
	case 'HE20':
	case 'EHT20':
		break;

	case 'VHT40':
	case 'HE40':
	case 'EHT40':
		config.vht_oper_centr_freq_seg0_idx =
			config.channel + (((int(config.channel / 4) + config.channel_offset) % 2) ? 2 : -2);
		break;

	case 'VHT80':
	case 'HE80':
	case 'EHT80':
		let delta = [ -6, 6, 2, -2 ];
		config.vht_oper_centr_freq_seg0_idx =
			config.channel + delta[(int(config.channel / 4) + config.channel_offset) % 4];
		config.vht_oper_chwidth = 1;
		break;

	case 'VHT160':
	case 'HE160':
	case 'EHT160':
		let vht_oper_centr_freq_seg0_idx_map = [ [ 64, 50 ], [ 128, 114 ], [ 177, 163 ] ];
		if (config.band == '6g')
			vht_oper_centr_freq_seg0_idx_map = [
				[ 29, 15 ], [ 61, 47 ], [ 93, 79 ], [ 125, 111 ],
				[ 157, 143 ], [ 189, 175 ], [ 221, 207 ]
			];
		for (let k, pair in vht_oper_centr_freq_seg0_idx_map)
			if (config.channel >= (pair[0] - 28) &&
			    config.channel <= pair[0]) {
				config.vht_oper_centr_freq_seg0_idx = pair[1];
				break;
			}
		config.vht_oper_chwidth = 2;
		break;

	default:
		config.ieee80211ac = 0;
		break;
	}

	/* 256-QAM */
	if (config.vendor_vht)
		append_vars(config, [ 'vendor_vht' ]);

	config.eht_oper_chwidth = config.vht_oper_chwidth;
	config.eht_oper_centr_freq_seg0_idx = config.vht_oper_centr_freq_seg0_idx;

	if (config.band == '6g') {
		config.ieee80211ac = 0;

		if (wildcard(htmode, 'EHT320*')) {
			if (!device_eht320(config)) {
				log('Could not set the center freq with this EHT setting');
				return false;
			}
			append_vars(config, [ 'op_class' ]);
		} else {
			switch (htmode) {
			case 'HE20':
			case 'EHT20':
				config.op_class = 131;
				break;

			case 'HE40':
			case 'HE80':
			case 'HE160':
			case 'EHT40':
			case 'EHT80':
			case 'EHT160':
				config.op_class = 132 + config.eht_oper_chwidth;
				break;
			}

			append_vars(config, [ 'op_class' ]);
		}

		config.stationary_ap = true;
		append_vars(config, [ 'he_6ghz_reg_pwr_type' ]);
	}

	if (config.ieee80211ac && config.hw_mode == 'a') {
		if (config.vht_oper_chwidth < 2) {
			config.vht160 = 0;
			config.short_gi_160 = 0;
		}

		set_default(config, 'tx_queue_data2_burst', '2.0');
		apply_defaults(config, DEFAULT_VHT_CAPAB);

		let vht = caps.vht_capa;

		config.vht_capab = '';
		if (vht & 0x10 && config.rxldpc)
			config.vht_capab += '[RXLDPC]';
		if (vht & 0x20 && config.short_gi_80)
			config.vht_capab += '[SHORT-GI-80]';
		if (vht & 0x40 && config.short_gi_160)
			config.vht_capab += '[SHORT-GI-160]';
		if (vht & 0x80 && config.tx_stbc_2by1)
			config.vht_capab += '[TX-STBC-2BY1]';
		if (vht & 0x800 && config.su_beamformer)
			config.vht_capab += '[SU-BEAMFORMER]';
		if (vht & 0x1000 && config.su_beamformee)
			config.vht_capab += '[SU-BEAMFORMEE]';
		if (vht & 0x80000 && config.mu_beamformer)
			config.vht_capab += '[MU-BEAMFORMER]';
		if (vht & 0x100000 && config.mu_beamformee)
			config.vht_capab += '[MU-BEAMFORMEE]';
		if (vht & 0x200000 && config.vht_txop_ps)
			config.vht_capab += '[VHT-TXOP-PS]';
		if (vht & 0x400000 && config.htc_vht)
			config.vht_capab += '[HTC-VHT]';
		if (vht & 0x10000000 && config.rx_antenna_pattern)
			config.vht_capab += '[RX-ANTENNA-PATTERN]';
		if (vht & 0x20000000 && config.tx_antenna_pattern)
			config.vht_capab += '[TX-ANTENNA-PATTERN]';

		let rx_stbc = [ '', '[RX-STBC-1]', '[RX-STBC-12]', '[RX-STBC-123]', '[RX-STBC-1234]' ];
		config.vht_capab += rx_stbc[min(config.rx_stbc, (vht >> 8) & 7)];

		if (vht & 0x800 && config.su_beamformer) {
			let ant = min(((vht >> 16) & 3) + 1, config.beamformer_antennas);
			if (ant > 1)
				config.vht_capab += '[SOUNDING-DIMENSION-' + ant + ']';
		}
		if (vht & 0x1000 && config.su_beamformee) {
			let ant = min(((vht >> 13) & 7) + 1, config.beamformee_antennas);
			if (ant > 1)
				config.vht_capab += '[BF-ANTENNA-' + ant + ']';
		}

		if ((vht & 0xc) == 8 && config.vht160 >= 2)
			config.vht_capab += '[VHT160-80PLUS80]';
		else if (((vht & 0xc) == 4 || (vht & 0xc) == 8) && config.vht160 >= 1)
			config.vht_capab += '[VHT160]';

		if ((vht & 3) > 1 && config.vht_max_mpdu >= 11454)
			config.vht_capab += '[MAX-MPDU-11454]';
		else if ((vht & 3) && config.vht_max_mpdu >= 7991)
			config.vht_capab += '[MAX-MPDU-7991]';

		let max_a_mpdu_len_exp = (vht >> 20) & 0x38;
		for (let exp = 7; exp > 0; exp--)
			if (max_a_mpdu_len_exp >= (0x8 * exp) && exp <= config.vht_max_a_mpdu_len_exp) {
				config.vht_capab += '[MAX-A-MPDU-LEN-EXP' + exp + ']';
				break;
			}

		let vht_link_adapt = vht & 0xC000000;
		if (vht_link_adapt >= 0xC000000 && config.vht_link_adapt > 3)
			config.vht_capab += '[VHT-LINK-ADAPT-3]';
		if (vht_link_adapt >= 0x8000000 && config.vht_link_adapt > 2)
			config.vht_capab += '[VHT-LINK-ADAPT-2]';

		append_vars(config, [
			'ieee80211ac', 'vht_oper_chwidth', 'vht_oper_centr_freq_seg0_idx', 'vht_capab'
		]);
	}

	/* 802.11ax */
	if (wildcard(htmode, 'HE*') || wildcard(htmode, 'EHT*')) {
		apply_defaults(config, DEFAULT_HE_CAPAB);

		config.ieee80211ax = true;

		if (config.hw_mode == 'a') {
			config.he_oper_chwidth ??= config.vht_oper_chwidth;
			config.he_oper_centr_freq_seg0_idx ??= config.vht_oper_centr_freq_seg0_idx;
		}

		if (config.he_bss_color_enabled) {
			if (!(config.he_bss_color > 0 && config.he_bss_color <= 64))
				config.he_bss_color = rand_bss_color();

			if (config.he_spr_non_srg_obss_pd_max_offset > 0)
				config.he_spr_sr_control |= 1 << 2;
			if (!config.he_spr_psr_enabled)
				config.he_spr_sr_control |= 1;

			append_vars(config, [
				'he_bss_color', 'he_spr_non_srg_obss_pd_max_offset', 'he_spr_sr_control'
			]);
		} else {
			append('he_bss_color_disabled', 1);
		}

		if (!(caps.he_phy_cap[3] & 0x80))
			config.he_su_beamformer = false;
		if (!(caps.he_phy_cap[4] & 0x1))
			config.he_su_beamformee = false;
		if (!(caps.he_phy_cap[4] & 0x2))
			config.he_mu_beamformer = false;
		if (!(caps.he_phy_cap[7] & 0x1))
			config.he_spr_psr_enabled = false;
		if (!(caps.he_mac_cap[0] & 0x4))
			config.he_twt_responder = false;
		if (!config.he_twt_responder)
			config.he_twt_required = false;
		if (!config.ldpc)
			config.he_ldpc = false;

		append_vars(config, [
			'ieee80211ax', 'he_oper_chwidth', 'he_oper_centr_freq_seg0_idx',
			'he_su_beamformer', 'he_su_beamformee', 'he_mu_beamformer',
			'he_twt_required', 'he_twt_responder', 'he_ldpc',
			'he_default_pe_duration', 'he_rts_threshold', 'he_mu_edca_qos_info_param_count',
			'he_mu_edca_qos_info_q_ack', 'he_mu_edca_qos_info_queue_request',
			'he_mu_edca_qos_info_txop_request', 'he_mu_edca_ac_be_aifsn',
			'he_mu_edca_ac_be_aci', 'he_mu_edca_ac_be_ecwmin', 'he_mu_edca_ac_be_ecwmax',
			'he_mu_edca_ac_be_timer', 'he_mu_edca_ac_bk_aifsn', 'he_mu_edca_ac_bk_aci',
			'he_mu_edca_ac_bk_ecwmin', 'he_mu_edca_ac_bk_ecwmax', 'he_mu_edca_ac_bk_timer',
			'he_mu_edca_ac_vi_ecwmin', 'he_mu_edca_ac_vi_ecwmax', 'he_mu_edca_ac_vi_aifsn',
			'he_mu_edca_ac_vi_aci', 'he_mu_edca_ac_vi_timer', 'he_mu_edca_ac_vo_aifsn',
			'he_mu_edca_ac_vo_aci', 'he_mu_edca_ac_vo_ecwmin', 'he_mu_edca_ac_vo_ecwmax',
			'he_mu_edca_ac_vo_timer',
		]);
	}

	/* 802.11be */
	if (wildcard(htmode, 'EHT*')) {
		apply_defaults(config, DEFAULT_EHT_CAPAB);

		config.ieee80211be = true;

		/* if (!(caps.eht_phy_cap[0] & 0x20))
			config.eht_su_beamformer = false;
		if (!(caps.eht_phy_cap[0] & 0x40))
			config.eht_su_beamformee = false;
		if (!(caps.eht_phy_cap[7] & 0x70))
			config.eht_mu_beamformer = false; */

		append_vars(config, [
			'ieee80211be', 'eht_su_beamformer', 'eht_su_beamformee',
			'eht_mu_beamformer',
		]);

		if (config.hw_mode == 'a')
			append_vars(config, [ 'eht_oper_chwidth', 'eht_oper_centr_freq_seg0_idx',
				'eht_bw320_offset' ]);
	}

	append_vars(config, [ 'tx_queue_data2_burst', 'stationary_ap' ]);

	return true;
};

function generate_device(config, caps) {
	let auto_channel = (config.channel == null || config.channel == '' ||
			    config.channel == 'auto' || +config.channel == 0);

	config.channel = auto_channel ? 0 : +config.channel;
	config.chanlist ??= length(config.channels ?? []) ? join(' ', config.channels) : null;

	append('driver', 'nl80211');

	set_device_defaults(config);
	device_log_append(config);
	device_country_code(config);
	device_cell_density_append(config);
	device_rates(config);

	/* beacon */
	append_vars(config, [ 'beacon_int', 'beacon_rate', 'rnr_beacon' ]);

	/* wpa_supplicant co-exist */
	append_vars(config, [ 'noscan' ]);

	/* airtime */
	if (config.airtime_mode)
		append_vars(config, [ 'airtime_mode' ]);

	/* assoc/thresholds */
	append_vars(config, [ 'rssi_reject_assoc_rssi', 'rssi_reject_assoc_timeout',
		'rssi_ignore_probe_request', 'iface_max_num_sta' ]);

	/* ACS / radar */
	if (!caps.features.radar_background || config.band != '5g')
		delete config.enable_background_radar;
	else
		set_default(config, 'enable_background_radar', false);

	append_vars(config, [ 'acs_chan_bias', 'acs_exclude_dfs', 'enable_background_radar' ]);

	/* TX power */
	append_vars(config, [ 'min_tx_power' ]);

	/* hw mode / channel */
	if (auto_channel)
		append('hw_mode', 'any');
	else
		append_vars(config, [ 'hw_mode', 'channel' ]);

	append_vars(config, [ 'rts_threshold', 'chanlist' ]);

	if (config.hw_mode in [ 'a', 'g' ] && config.require_mode in [ 'n', 'ac', 'ax', 'be' ]) {
		let require_mode = { n: 'require_ht', ac: 'require_vht', ax: 'require_he', be: 'require_eht' };
		let key = require_mode[config.require_mode];

		if (key && (config.require_mode != 'be' || config.ieee80211be))
			append(key, 1);

		config.legacy_rates = false;
	}

	if (!device_htmode_append(config, caps))
		return false;

	if (config.ieee80211ax || config.ieee80211be) {
		if (config.mbssid)
			append_vars(config, [ 'mbssid' ]);
	}

	/* 6G power mode */
	if (config.band != '6g')
		append_vars(config, [ 'reg_power_type' ]);

	/* raw options */
	for (let raw in config.hostapd_options ?? [])
		append_raw(raw);

	return true;
};

/* ------------------------------------------------------------------ */
/* BSS 段：复用官方 wifi.ap.generate()                                 */
/* ------------------------------------------------------------------ */

function iface_auth_algs(config) {
	let enc = config.encryption ?? 'none';

	if (!wildcard(enc, '*wep*'))
		return 1;

	return wildcard(enc, '*shared*') || wildcard(enc, '*mixed*') ? 3 : 1;
};

/*
 * 与官方 hostapd.uc:setup_interface() 相同：第一个参数是
 * data.interfaces 的内部下标（"01"…），用于 netifd.set_vlan()。
 */
function setup_interface(interface, data, config, caps, idx) {
	config = { ...config, fixup: null };
	config.idx = idx;

	/* MTK：BSS MAC 由驱动从 .dat 派生，hostapd 不能用配置里的 bssid */
	if (config.macaddr != null || config.default_macaddr != null || config.random_macaddr != null)
		log(`ignoring configured macaddr for ${config.ifname}, MTK driver derives BSS MAC`);

	config.macaddr = null;
	config.default_macaddr = null;
	config.random_macaddr = null;

	/* MTK：使用驱动接口地址，并保持与旧 shell 相同的 auth_algs */
	config.auth_algs ??= iface_auth_algs(config);

	let bss_options = [];

	for (let opt in config.hostapd_bss_options ?? [])
		push(bss_options, opt);

	push(bss_options, 'use_driver_iface_addr=1');
	config.hostapd_bss_options = bss_options;

	ap.generate(interface, data, config, config.vlans ?? {}, config.stas ?? {}, caps.features);
};

/* ------------------------------------------------------------------ */
/* hostapd 进程管理                                                    */
/* ------------------------------------------------------------------ */

function kill_pidfile(pidfile) {
	let pid = trim(readfile(pidfile) ?? '');

	if (length(pid)) {
		system(`kill ${+pid} 2>/dev/null`);
		sleep(0.2);
	}

	fs.unlink(pidfile);
};

function read_pid(pidfile) {
	for (let i = 0; i < 5; i++) { /* 5s */
		let pid = trim(readfile(pidfile) ?? '');

		if (length(pid) && +pid > 0)
			return +pid;

		sleep(1);
	}

	return null;
};

function conf_ifnames(conf) {
	let text = readfile(conf);
	let ifnames = [];

	if (!text)
		return ifnames;

	for (let line in split(text, '\n')) {
		let m = match(line, /^interface=(.*)$/) ?? match(line, /^bss=(.*)$/);

		if (m && length(trim(m[1])))
			push(ifnames, trim(m[1]));
	}

	return ifnames;
};

function wps_er_start(ifnames) {
	for (let ifname in ifnames) {
		let ctrl = `${CTRL_DIR}/${ifname}`;
		let pidfile = `/var/run/action-${ifname}-wps-er.pid`;
		let i;

		for (i = 0; i < 10; i++) {
			if (fs.stat(ctrl))
				break;
			sleep(1);
		}

		if (i == 10) {
			log(`ctrl socket ${ctrl} not ready, skip WPS ER for ${ifname}`);
			continue;
		}

		kill_pidfile(pidfile);
		system(`${HOSTAPD_CLI} -i ${shell_quote(ifname)} -a ${shell_quote(WPS_ER_SCRIPT)} -B -P ${shell_quote(pidfile)}`);
		log(`WPS ER attached to ${ifname}`);
	}
};

function wps_er_stop(ifnames) {
	for (let ifname in ifnames) {
		let pidfile = `/var/run/action-${ifname}-wps-er.pid`;

		if (fs.stat(pidfile))
			kill_pidfile(pidfile);
	}
};

/*
 * 生成配置并启动 hostapd。
 * 返回 true 表示无需 AP（没有 ap 模式的 vif，或已经由别处处理）。
 */
export function setup(data) {
	let suffix = data.vif_phy_suffix ?? '';
	let file = conf_path(data.phy, suffix);
	let pidfile = pid_path(data.phy, suffix);
	let config = data.config;

	/* 先绑定解析出来的 phy，device_capabilities() 要用它查 nl80211 */
	config.phy = data.phy;
	config.country_code ??= config.country;

	let caps = device_capabilities(config);
	let has_ap = false;
	let idx = 0;

	flush_config();

	if (fs.stat(file))
		fs.rename(file, file + '.prev');

	if (!generate_device(config, caps))
		return false;

	for (let k in sort(keys(data.interfaces ?? {}))) {
		let iface_data = data.interfaces[k];

		if (iface_data?.config?.mode != 'ap')
			continue;

		if (iface_data.config.owe_transition)
			log(`OWE transition is not supported on mtwifi, ignoring for ${iface_data.config.ifname}`);

		iface_data.config.network_bridge = iface_data.bridge;
		iface_data.config.network_ifname = iface_data['bridge-ifname'];

		setup_interface(k, data, iface_data.config, caps, idx++);
		has_ap = true;
	}

	dump_config(file);

	if (!has_ap) {
		log(`no AP interface configured for ${data.phy}`);
		fs.unlink(file);
		return true;
	}


	kill_pidfile(pidfile);

	let ret = system(`${HOSTAPD} -B -P ${shell_quote(pidfile)} ${shell_quote(file)}`);

	if (ret != 0)
		log(`hostapd returned ${ret} for ${file}`);

	let pid = read_pid(pidfile);

	if (!pid) {
		log(`hostapd did not start for ${data.phy}`);
		netifd.setup_failed('HOSTAPD_START_FAILED');
		return false;
	}

	netifd.add_process(HOSTAPD, pid, true, true);
	log(`hostapd started for ${data.phy} (pid ${pid})`);

	wps_er_start(conf_ifnames(file));

	return true;
};

export function teardown(phy, radio) {
	let suffix = suffix_of(radio);
	let file = conf_path(phy, suffix);

	wps_er_stop(conf_ifnames(file));
	kill_pidfile(pid_path(phy, suffix));
	fs.unlink(file);

	log(`hostapd stopped for ${phy}${suffix}`);
};

export { generate_device, iface_auth_algs, conf_ifnames };
