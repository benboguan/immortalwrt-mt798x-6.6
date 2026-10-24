#!/usr/bin/ucode
'use strict';

// SPDX-License-Identifier: GPL-2.0
/*
 * mtwifi netifd wireless driver handler (ucode)
 *
 * Copyright (C) 2026 nanchuci <nanchuci023@gmail.com>
 *
 * 用法（由 lib/netifd/wireless.uc 调用）：
 *   ./mtwifi.sh <type> dump
 *   ./mtwifi.sh <type> setup    <radioN> <payload-json>
 *   ./mtwifi.sh <type> teardown <radioN> <payload-json>
 * 因此 ARGV[1] = 操作，ARGV[2] = 设备段名，ARGV[3] = JSON。
 *
 * 与官方 mac80211.sh(ucode) 的关系见 README：
 *  - dump/选项表：官方 schema + MTK 私有选项
 *  - BSS/hostapd 配置：复用官方 wifi.ap / wifi.iface
 *  - STA 配置：复用官方 wifi.supplicant.generate()，挂载走 wpa_cli
 *  - hostapd/wpa_supplicant 进程与 MTK .dat/L1 profile 由 mtwifi.* 模块处理
 */

import * as fs from 'fs';
import * as uci from 'uci';
import { validate } from 'wifi.validate';
import * as netifd from 'wifi.netifd';
import { find_phy } from 'wifi.utils';

import * as l1dat from 'mtwifi.l1dat';
import * as cfg from 'mtwifi.cfg';
import * as ifname from 'mtwifi.ifname';
import * as mt_hostapd from 'mtwifi.hostapd';
import * as mt_supplicant from 'mtwifi.supplicant';
import { log, trim, exists, shell_quote, sleep, readfile } from 'mtwifi.common';

global.radio = ARGV[2];

const REINSTALL_LOCK = '/tmp/mtwifi_reloading.lock';
const IFACE_WPS_FILE = '/var/run/mtwifi-iface-wps';
const KINDS = [ 'device', 'iface', 'vlan', 'station' ];
const TYPE = { array: 1, string: 3, number: 5, boolean: 7 };

const SCHEMA_PATH = {
	device: '/usr/share/schema/wireless.wifi-device.json',
	iface: '/usr/share/schema/wireless.wifi-iface.json',
	vlan: '/usr/share/schema/wireless.wifi-vlan.json',
	station: '/usr/share/schema/wireless.wifi-station.json',
};

/*
 * MTK 私有选项（官方 schema 里没有的）。
 * 官方 schema 已有的键以 schema 为准，这里只补差集。
 */
const EXTRA = {
	device: [
		[ 'devname', TYPE.string ],
		[ 'dbdc_main', TYPE.boolean ],
		[ 'whnat', TYPE.boolean ],
		[ 'twt', TYPE.number ],
		[ 'dfs', TYPE.boolean ],
		[ 'zw_dfs', TYPE.boolean ],
		[ 'vendor_vht', TYPE.boolean ],
		[ 'vht_1024', TYPE.boolean ],
		[ 'he_ldpc', TYPE.boolean ],
		[ 'map_mode', TYPE.number ],
		[ 'obss_interval', TYPE.number ],
		[ 'eht_bw320_offset', TYPE.number ],
	],
	iface: [
		[ 'mldgroup', TYPE.number ],
		[ 'mwds', TYPE.boolean ],
		[ 'disable_eht', TYPE.boolean ],
		[ 'amsdu', TYPE.boolean ],
		[ 'autoba', TYPE.boolean ],
		[ 'reliable_11r', TYPE.boolean ],
		[ 'mumimo_dl', TYPE.boolean ],
		[ 'mumimo_ul', TYPE.boolean ],
		[ 'ofdma_dl', TYPE.boolean ],
		[ 'ofdma_ul', TYPE.boolean ],
		[ 'frag', TYPE.number ],
		[ 'rts', TYPE.number ],
		[ 'kicklow', TYPE.number ],
		[ 'assocthres', TYPE.number ],
	],
	vlan: [],
	station: [],
};

/* ------------------------------------------------------------------ */
/* dump：输出本驱动的选项表                                            */
/* ------------------------------------------------------------------ */

function schema_properties(kind) {
	let text = readfile(SCHEMA_PATH[kind]);

	if (!text) {
		log(`cannot read ${SCHEMA_PATH[kind]}: wifi-scripts 的 ucode 覆盖层未安装？`);
		return {};
	}

	let data;

	try {
		data = json(text);
	} catch (e) {
		log(`failed to parse ${SCHEMA_PATH[kind]}: ${e}`);
		return {};
	}

	return data?.properties ?? {};
};

function dump_option(props, key) {
	let schema = props[key];
	let ref = (schema.type == 'alias') ? schema.default : key;
	let type = props[ref]?.type;

	if (!type || TYPE[type] == null) {
		log(`dropping unsupported option ${key} (type ${type})`);
		return null;
	}

	return [ key, TYPE[type] ];
};

function dump_options() {
	let dump = { name: 'mtwifi' };

	for (let kind in KINDS) {
		let props = schema_properties(kind);
		let seen = {};
		let list = [];

		for (let key in props) {
			let opt = dump_option(props, key);

			if (opt) {
				seen[opt[0]] = true;
				push(list, opt);
			}
		}

		for (let opt in EXTRA[kind])
			if (!seen[opt[0]])
				push(list, opt);

		dump[kind] = list;
	}

	printf('%J\n', dump);

	return 0;
};

/* ------------------------------------------------------------------ */
/* payload 辅助                                                        */
/* ------------------------------------------------------------------ */

function vif_keys(payload) {
	return sort(keys(payload.interfaces ?? {}));
};

function for_each_vif(payload, mode, cb) {
	for (let k in vif_keys(payload)) {
		let v = payload.interfaces[k];

		if (v?.config && (!mode || v.config.mode == mode))
			cb(k, v);
	}
};

function find_radio_section(devname) {
	let config = uci.cursor().get_all('wireless') ?? {};

	for (let name, section in config)
		if (section['.type'] == 'wifi-device' && section.devname == devname)
			return name;

	return null;
};

/*
 * devname 解析：
 *  1. 新配置：wifi-device 段里的 devname 选项
 *  2. 旧配置：段名直接就是 L1 profile 里的 devname
 */
function resolve_devname(l1, payload, section) {
	let devname = payload.config?.devname;

	if (devname)
		return devname;

	if (l1 && l1[l1dat.DEV_RINDEX][section])
		return section;

	return null;
};

/* MTK 私有键在 validate() 之前摘掉，避免官方 schema 报 “not present” */
function validate_kind(kind, config, extras) {
	let saved = {};

	for (let opt in extras) {
		let key = opt[0];

		if (config[key] != null) {
			saved[key] = config[key];
			delete config[key];
		}
	}

	validate(kind, config);

	for (let key, value in saved)
		config[key] = value;
};

function sanitize_device(config) {
	let cell_density = config.cell_density != null ? +config.cell_density : null;

	if (cell_density != null) {
		let clamped = min(max(cell_density, 0), 3);

		if (clamped != cell_density) {
			log(`cell_density ${cell_density} out of range, clamped to ${clamped}`);
			config.cell_density = clamped;
		}
	}
};

function validate_device(config) {
	let saved = {};

	for (let key in [ 'htmode', 'require_mode' ]) {
		let value = config[key];

		if (value == null)
			continue;

		saved[key] = value;

		if (key == 'htmode' && wildcard(value, 'EHT320-*'))
			config.htmode = 'EHT320';
		else if (key == 'require_mode' && value == 'be')
			delete config.require_mode;
	}

	validate_kind('device', config, EXTRA.device);

	for (let key, value in saved)
		config[key] = value;
};

function validate_ifaces(payload) {
	for_each_vif(payload, null, (k, v) => validate_kind('iface', v.config, EXTRA.iface));
};

/* ------------------------------------------------------------------ */
/* phy 解析                                                            */
/* ------------------------------------------------------------------ */

function phy_of_ifname(ifname) {
	if (!ifname)
		return null;

	let link = fs.readlink(`/sys/class/net/${ifname}/phy80211`);

	if (link)
		return fs.basename(link);

	let name = trim(readfile(`/sys/class/net/${ifname}/phy80211/name`) ?? '');

	return length(name) ? name : null;
};

function resolve_phy(config, dev) {
	let phy = find_phy(config, true);

	if (phy)
		return phy;

	phy = phy_of_ifname(dev?.main_ifname);

	if (!phy) {
		log(`cannot resolve phy for ${dev?.main_ifname ?? 'unknown'}, falling back to interface name`);
		phy = dev?.main_ifname;
	}

	return phy;
};

/* ------------------------------------------------------------------ */
/* setup                                                               */
/* ------------------------------------------------------------------ */

/*
 * reinstall_cfgs 变化时需要重载驱动模块。
 * 与旧实现一致：DBDC 卡要把同 chip 的其它 radio 一起 down/up，
 * 并用 /tmp/mtwifi_reloading.lock 防止嵌套重载。
 */
function handle_reinstall(l1, devname, dev, payload) {
	if (exists(REINSTALL_LOCK)) {
		log('reinstall in progress, skip nested reinstall');
		return;
	}

	if (!exists('/sys/module/mt_wifi')) {
		log('mtwifi module is built-in, please reboot the device!');
		return;
	}

	let lock = fs.open(REINSTALL_LOCK, 'w');

	if (lock) {
		lock.write('' + time());
		lock.close();
	}

	let siblings = [];

	for (let k, j in l1[l1dat.DEV_RINDEX])
		if (j.INDEX == dev.INDEX && j.mainidx == dev.mainidx)
			push(siblings, k);

	for (let k in siblings)
		cfg.driver_down(k);

	let reloaded = cfg.reinstall();

	fs.unlink(REINSTALL_LOCK);

	if (!reloaded) {
		/* 模块无法卸载（被占用），不要再把 sibling 拉起来，
		 * 否则两个 radio 会反复互相 teardown，ubus 永远 up=false */
		log('driver reload failed; leaving siblings stopped, reboot if needed');
		return;
	}

	for (let k in siblings) {
		if (k == devname)
			continue;
		let section = find_radio_section(k);

		if (section)
			system(`/sbin/wifi up ${shell_quote(section)}`);
		else
			log(`no wireless section for ${k}, not reloading`);
	}
};

function setup() {
	let payload = json(ARGV[3]);

	if (type(payload) != 'object') {
		log('invalid payload');
		netifd.set_retry(false);
		return 1;
	}

	let l1 = l1dat.load_cached();

	if (!l1) {
		log(`no L1 profile (${l1dat.L1_DAT_PATH})`);
		netifd.setup_failed('NO_L1_PROFILE');
		return 1;
	}

	let devname = resolve_devname(l1, payload, ARGV[2]);
	let dev = devname ? l1[l1dat.DEV_RINDEX][devname] : null;

	if (!dev) {
		log(`unknown device ${ARGV[2]} (devname ${devname})`);
		netifd.setup_failed('UNKNOWN_DEVICE');
		return 1;
	}

	/* validate() 会把 country 改名为 country_code，先把原值留住 */
	let country = payload.config.country;

	/* 1. VAP 接口名分配并告知 netifd */
	ifname.assign(payload, dev);

	for (let k in vif_keys(payload)) {
		let v = payload.interfaces[k];

		if (v?.config?.ifname)
			netifd.set_vif(k, v.config.ifname);
	}

	ifname.write_wps_map(payload, dev, IFACE_WPS_FILE);

	/* 2. 生成 MTK .dat */
	let ret = cfg.write_dat(devname, payload);

	/*
	 * .dat 生成失败不致命：旧 shell 处理器在 `mtwifi_cfg setup` 失败后
	 * 依然会继续生成 hostapd 配置（此时驱动沿用旧 .dat）。
	 * 只有 REINSTALL_LOCK 占用（重载过程中的嵌套 setup）等预期情况会走到这里。
	 */
	if (!ret.ok)
		log(`warning: .dat generation for ${devname} did not complete, continuing`);

	/*
	 * 首次 setup（本次开机以来该 radio 从未启动过）时跳过 reinstall：
	 * write_dat() 从无到有必然报 reinstall=true，但此时驱动还没有真正
	 * 加载过 radio，rmmod 会失败；handle_reinstall 的 down/up 流程又会
	 * 把同 chip 的另一个 radio 一起拉下来，导致两个 radio 无限互相
	 * teardown，ubus 永远 up=false。
	 *
	 * 首次 setup 让 hwifi_start 自己读新的 .dat 就够了，无需 reload。
	 */
	if (ret.reinstall) {
		let first_marker = `/tmp/mtwifi-${devname}.first-setup`;

		if (exists(first_marker))
			handle_reinstall(l1, devname, dev, payload);
		else {
			log(`first setup for ${devname}, skipping reinstall`);
			fs.writefile(first_marker, '');
		}
	}

	/* 3. 驱动级设置（hairpin / mgmt_rx / service_misc / cfg80211 tool） */
	cfg.driver_up(devname, payload, match(dev.profile_path ?? '', /dbdc/) != null);

	/* 4. 官方 schema 校验：别名解析 + 默认值 */
	sanitize_device(payload.config);
	validate_device(payload.config);
	payload.config.country ??= country;
	validate_ifaces(payload);

	/* 5. phy / 后缀 */
	let phy = resolve_phy(payload.config, dev);

	if (!phy) {
		log(`no phy for ${devname}`);
		netifd.setup_failed('NO_PHY');
		return 1;
	}

	let suffix = mt_hostapd.suffix_of(payload.config.radio);
	let has_ap = ifname.has_mode(payload, 'ap');
	let has_sta = ifname.has_mode(payload, 'sta');

	payload.phy = phy;
	payload.phy_suffix = suffix;
	payload.vif_phy_suffix = suffix;

	/*
	 * 官方 ucode mac80211.sh 在存在 sta/adhoc/mesh vif 时会写
	 * ap_start_disabled=true（让 AP BSS 以 start_disabled 启动，等 STA
	 * 侧定型后再由 wpad 的 ubus 流程 enable）。这里**故意不跟随**：
	 * 我们的 hostapd 是直接 `hostapd -B -P` 起进程的，没有 wpad 的
	 * enable 流程，AP 一旦 disabled 就会一直不工作。
	 * 因此只保留 UCI 里的 start_disabled（与旧 shell 处理器一致）。
	 * 如果以后换用官方 wifi.hostapd（ubus config_set）流程，
	 * 把下面一行改成 `has_sta || explicit_start_disabled` 即可。
	 */
	let explicit_start_disabled = false;

	for_each_vif(payload, 'ap', (k, v) => {
		if (v.config.start_disabled)
			explicit_start_disabled = true;
	});

	payload.ap_start_disabled = explicit_start_disabled;

	if (has_sta)
		log(`${devname}: STA vif present, keep AP BSSes enabled (no wpad enable flow)`);

	if (!payload.config.ifname_prefix)
		payload.ifname_prefix = `${phy}${suffix}-`;

	netifd.set_data({ phy, radio: payload.config.radio, devname, suffix });

	log(`setup ${devname} (${ARGV[2]}) phy ${phy}${suffix} ap ${has_ap} sta ${has_sta}`);

	/* 6. STA / AP */
	/* 先清理 STA 残留，无论 has_sta。teardown 是幂等的 */
	mt_supplicant.teardown(dev?.apcli_ifname);

	if (has_ap && !mt_hostapd.setup(payload))
		return 1;

	if (has_sta)
		mt_supplicant.setup(payload);

	netifd.set_up();

	return 0;
};

/* ------------------------------------------------------------------ */
/* teardown                                                            */
/* ------------------------------------------------------------------ */

function teardown() {
	let payload = json(ARGV[3]) ?? {};
	let l1 = l1dat.load_cached();

	if (ARGV[2] == '#mlo')
		return 0;

	let devname = payload.data?.devname ?? resolve_devname(l1, payload, ARGV[2]);
	let dev = (l1 && devname) ? l1[l1dat.DEV_RINDEX][devname] : null;
	let phy = payload.data?.phy ?? phy_of_ifname(dev?.main_ifname);
	let radio = payload.data?.radio ?? payload.config?.radio;

	log(`teardown ${ARGV[2]} (devname ${devname}, phy ${phy})`);

	mt_supplicant.teardown(dev?.apcli_ifname);

	if (phy)
		mt_hostapd.teardown(phy, radio);

	cfg.driver_down(devname, payload);

	/* 只清掉本 radio 的 WPS 映射，保留其它 radio */
	ifname.remove_wps_map(dev, IFACE_WPS_FILE);

	return 0;
};

/* ------------------------------------------------------------------ */

let ret = 1;

switch (ARGV[1]) {
case 'dump':
	ret = dump_options();
	break;

case 'setup':
	ret = setup();
	break;

case 'teardown':
	ret = teardown();
	break;
}

exit(ret);
