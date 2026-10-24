'use strict';

// SPDX-License-Identifier: GPL-2.0
/*
 * mtwifi ucode support - apcli (STA) 侧的 wpa_supplicant 管理
 *
 * Copyright (C) 2026 nanchuci <nanchuci023@gmail.com>
 *
 * 本仓库的 wpad 只提供旧的 ctrl_iface API，既不支持 interface_add 的
 * `create` 参数，自动创建 STA 接口时也会错选 AP iftype 被 MTK 驱动拒绝。
 * 因此 STA 接口的创建交给 `iw phy <phy> interface add <ifname> type
 * station`，之后再用 `wpa_cli interface_add`（不带 create）把它挂到
 * wpa_supplicant 上。network={} 配置完全由官方 wifi.supplicant.generate()
 * 生成，本模块负责后处理、接口创建、挂载和 teardown。
 * 沿用 MTK 既有的 `wpa_cli interface_add` 方式（本仓库的 wpad
 * 只提供旧的 ubus API），并额外挂一个 scan action 脚本记录扫描状态。
 */

import * as fs from 'fs';
import * as supplicant from 'wifi.supplicant';
import { log, trim, readfile, shell_quote, sleep, read_pipe } from 'mtwifi.common';

const IW = '/usr/sbin/iw';
const WPA_CTRL_DIR = '/var/run/wpa_supplicant';
const WPA_CLI = '/usr/sbin/wpa_cli';
const SCAN_ACTION = '/usr/share/ucode/mtwifi/scan-action.uc';

/*
 * 与 generate() 输出重复或需要强制覆盖的全局字段前缀。凡是命中这里的行，
 * 都会从原 .conf 里删掉，由我们自己重新生成。
 */
const GLOBAL_DEDUP = [
	/^\s*ctrl_interface\s*=/,
	/^\s*update_config\s*=/,
	/^\s*bss_expiration_scan_count\s*=/,
	/^\s*autoscan\s*=/,
	/^\s*sae_pwe\s*=/,
	/^\s*dpp_config_processing\s*=/,
	/^\s*device_name\s*=/,
	/^\s*device_type\s*=/,
	/^\s*manufacturer\s*=/,
	/^\s*model_name\s*=/,
	/^\s*model_number\s*=/,
	/^\s*serial_number\s*=/,
	/^\s*config_methods\s*=/,
	/^\s*wps_cred_processing\s*=/,
	/^\s*wps_cred_add_sae\s*=/,
	/^\s*ignore_old_scan_res\s*=/,
	/^\s*pmf\s*=/,
];

/* 旧 wpad (< 2.10) 不认识的字段，保留会导致整个 network block 被丢弃 */
const DROP_LEGACY = [
	/^\s*rsn_overriding\s*=/,
];

function global_cli(cmd) {
	return trim(read_pipe(`${WPA_CLI} -p ${WPA_CTRL_DIR}/ -i global ${cmd}`) ?? '');
};

function iface_cli(ifname, cmd) {
	return trim(read_pipe(`${WPA_CLI} -p ${WPA_CTRL_DIR}/ -i ${shell_quote(ifname)} ${cmd}`) ?? '');
};

function wait_for(path, tries) {
	for (let i = 0; i < tries; i++) {
		if (fs.stat(path))
			return true;
		sleep(0.1);
	}

	return false;
};

/* interface_name 列表（wpa_cli interface 输出是以空格分隔的接口名） */
function iface_list() {
	return filter(split(global_cli('interface'), /\s+/), (v) => length(v));
};

function scan_action_stop(ifname) {
	let pidfile = `/var/run/action-${ifname}-scan.pid`;

	if (fs.stat(pidfile)) {
		let pid = trim(readfile(pidfile) ?? '');

		if (length(pid))
			system(`kill -TERM ${+pid} 2>/dev/null`);

		fs.unlink(pidfile);
	}
};

function scan_action_start(ifname) {
	let pidfile = `/var/run/action-${ifname}-scan.pid`;
	let ctrl = `${WPA_CTRL_DIR}/${ifname}`;

	if (!fs.stat(SCAN_ACTION))
		return;

	if (!wait_for(ctrl, 30)) {
		log(`ctrl socket for ${ifname} not ready, skip scan action`);
		return;
	}

	scan_action_stop(ifname);
	system(`${WPA_CLI} -p ${WPA_CTRL_DIR}/ -i ${shell_quote(ifname)} -a ${shell_quote(SCAN_ACTION)} -B -P ${shell_quote(pidfile)}`);
	log(`scan action attached to ${ifname}`);
};

function normalize_band(band) {
	if (band == null)
		return null;
	band = lc(`${band}`);
	return band == '2.4g' ? '2g' : band;
};

/* 依次从 iface_data.config / iface_data / data.config 里取值 */
function pick_global(iface_data, data, key) {
	if (iface_data?.config?.[key] != null)
		return iface_data.config[key];
	if (iface_data?.[key] != null)
		return iface_data[key];
	if (data?.config?.[key] != null)
		return data.config[key];
	return null;
};

function is_map_mode(data) {
	let m = data?.config?.map_mode;
	return m != null && m != '' && m != '0' && m != 0;
};

/*
 * 按 SDK Lua 的逻辑，生成旧 wpad 路径下需要的全局字段列表。
 */
function build_global(iface_data, data) {
	let out = [];
	let map = is_map_mode(data);

	/* 基础固定项 */
	push(out, `ctrl_interface=${WPA_CTRL_DIR}`);
	push(out, 'update_config=1');
	push(out, 'bss_expiration_scan_count=1');

	/* DPP */
	let dpp = pick_global(iface_data, data, 'dpp_config_processing');
	if (dpp != null && dpp != '')
		push(out, `dpp_config_processing=${dpp}`);

	/* WPS 设备信息（缺省走 SDK 默认值） */
	let v;

	v = pick_global(iface_data, data, 'wps_device_name');
	push(out, `device_name=${v != null && v != '' ? v : 'Wireless station'}`);

	v = pick_global(iface_data, data, 'wps_device_type');
	push(out, `device_type=${v != null && v != '' ? v : '6-0050F204-1'}`);

	v = pick_global(iface_data, data, 'wps_manufacturer');
	push(out, `manufacturer=${v != null && v != '' ? v : 'MediaTek Inc.'}`);

	push(out, 'model_name=MediaTek Wireless Access Point');
	push(out, 'model_number=MT7988');
	push(out, 'serial_number=12345678');
	push(out, 'config_methods=display virtual_push_button keypad physical_push_button');

	/* WPS 凭据处理：UCI 优先，MAP 场景下默认 1 */
	v = pick_global(iface_data, data, 'wps_cred_processing');
	if (v != null && v != '')
		push(out, `wps_cred_processing=${v}`);
	else if (map)
		push(out, 'wps_cred_processing=1');

	v = pick_global(iface_data, data, 'wps_cred_add_sae');
	if (v != null && v != '')
		push(out, `wps_cred_add_sae=${v}`);
	else if (map)
		push(out, 'wps_cred_add_sae=1');

	/* MAP：忽略旧扫描结果 */
	v = pick_global(iface_data, data, 'ignore_old_scan_res');
	if (v != null && v != '')
		push(out, `ignore_old_scan_res=${v}`);
	else if (map)
		push(out, 'ignore_old_scan_res=1');

	/* PMF：UCI 优先；MAP 时 6g 强制 2，其它频段 1 */
	v = pick_global(iface_data, data, 'pmf');
	if (v != null && v != '') {
		push(out, `pmf=${v}`);
	} else if (map) {
		let band = normalize_band(data?.config?.band);
		push(out, `pmf=${band == '6g' ? 2 : 1}`);
	}

	/* autoscan：UCI 显式 0 表示关闭 */
	v = pick_global(iface_data, data, 'autoscan_interval');
	if (v == null)
		push(out, 'autoscan=periodic:30');
	else if (v != '' && v != '0' && v != 0)
		push(out, `autoscan=periodic:${v}`);

	/* sae_pwe 在 network 块内旧 wpad 不认，放到全局位置 */
	push(out, 'sae_pwe=2');

	return out;
};

/*
 * 对 generate() 产生的 .conf 做后处理：
 *   1. 在顶部插入旧 wpad 路径下缺失的全局字段（GLOBAL_CONF）；
 *   2. 去掉与新全局字段重名的项（GLOBAL_DEDUP）；
 *   3. 去掉旧 wpad 不认识的字段（DROP_LEGACY）。
 */
function fixup_conf(path, iface_data, data) {
	if (!path || !fs.stat(path))
		return;

	let lines = split(trim(fs.readfile(path) ?? ''), '\n');
	let out = [];

	/* 顶部插入全局字段：for...in 遍历数组直接拿元素值 */
	for (let line in build_global(iface_data, data))
		push(out, line);

	for (let line in lines) {
		let drop = false;

		/* DROP_LEGACY / GLOBAL_DEDUP 是正则数组，同样直接拿正则 */
		for (let re in DROP_LEGACY)
			if (match(line, re)) { drop = true; break; }

		if (!drop)
			for (let re in GLOBAL_DEDUP)
				if (match(line, re)) { drop = true; break; }

		if (!drop)
			push(out, line);
	}

	fs.writefile(path, join('\n', out) + '\n');
}

/*
 * 找同一个 radio 上的 AP 接口名。setup() 的 data 里包含该 radio
 * 上所有接口，非 sta 的就是 AP。
 */
function find_ap_ifname(data) {
	let ks = keys(data.interfaces ?? {});

	for (let i = 0; i < length(ks); i++) {
		let iface_data = data.interfaces[ks[i]];
		let mode = iface_data?.config?.mode;

		if ((mode == 'ap' || mode == 'ap-wds') && iface_data.config.ifname)
			return iface_data.config.ifname;
	}

	return null;
};

/*
 * 等 AP 接口进入 operstate=up，最多等 tries * 0.2 秒。
 * netifd 触发 setup() 的时机几乎和 hostapd 启动同时，此时 phy 上的
 * AP BSS 还在半初始化，直接创建 STA 接口会被 MTK 驱动误处理，导致
 * AP 接口 MAC 归零、连带打坏整个 phy。
 */
function wait_ap_ready(data, tries) {
	let ap_ifname = find_ap_ifname(data);

	if (!ap_ifname)
		return false;

	for (let i = 0; i < tries; i++) {
		let state = trim(readfile(`/sys/class/net/${ap_ifname}/operstate`) ?? '');

		if (state == 'up')
			return true;

		sleep(0.2);
	}

	log(`AP ${ap_ifname} not up after ${tries * 0.2}s, proceeding anyway`);
	return false;
};

/*
 * 让 MTK 驱动创建 STA 内核接口。
 *
 * 不用 wpa_supplicant 自己创建的原因：
 *   - 本仓库 wpad 不支持 interface_add 的 create 参数；
 *   - 即使不带 create，它也会把 iftype 选成 AP，phy 上已经有一个 AP BSS，
 *     MTK 驱动会以 -19 拒绝。
 */
function ensure_sta_iface(ifname, phy) {
	if (fs.stat(`/sys/class/net/${ifname}`))
		return true;

	if (!phy) {
		log(`no phy for ${ifname}, cannot create STA interface`);
		return false;
	}

	log(`creating STA interface ${ifname} on ${phy}`);
	system(`${IW} phy ${shell_quote(phy)} interface add ${shell_quote(ifname)} type station 2>/dev/null`);

	if (!wait_for(`/sys/class/net/${ifname}`, 30)) {
		log(`failed to create ${ifname} on ${phy}`);
		return false;
	}

	return true;
};

/* 删内核 STA 接口。仅靠 wpa_cli interface_remove 只解除管理，
 * 内核接口不会消失，`iw dev` 里会残留。 */
function remove_sta_iface(ifname) {
	if (!fs.stat(`/sys/class/net/${ifname}`))
		return;

	/* 从任何网桥里摘掉 apcli */
	if (fs.stat(`/sys/class/net/${ifname}/master`))
		system(`ip link set ${shell_quote(ifname)} nomaster 2>/dev/null`);

	system(`ip link set ${shell_quote(ifname)} down 2>/dev/null`);
	system(`${IW} dev ${shell_quote(ifname)} del 2>/dev/null`);

	for (let i = 0; i < 30 && fs.stat(`/sys/class/net/${ifname}`); i++)
		sleep(0.1);
};

/*
 * 为 payload 里所有 sta 模式 vif 生成配置并挂到 wpa_supplicant 上。
 * 返回实际挂载的接口名列表。
 */
export function setup(data) {
	let active = [];

	if (!wait_for(`${WPA_CTRL_DIR}/global`, 30)) {
		log('wpa_supplicant global socket not ready, skip STA interfaces');
		return active;
	}

	/* phy 来自 wifi-device 段的 `option phy`，如 phy1 */
	let phy = data?.config?.phy ?? data?.phy ?? null;

	/* 先等同 radio 的 AP 接口 up，再创建 STA 接口。
	 * netifd 触发 setup() 时 hostapd 可能还在初始化 rai0，
	 * 此时创建 STA 会打坏 AP。最多等 30 秒。 */
	wait_ap_ready(data, 150);

	for (let k in sort(keys(data.interfaces ?? {}))) {
		let iface_data = data.interfaces[k];

		if (iface_data?.config?.mode != 'sta')
			continue;

		let ifname = iface_data.config.ifname;

		if (!ifname) {
			log(`skip sta ${iface_data.name}: no ifname`);
			continue;
		}

		let config_list = [];

		/*
		 * 官方 wifi.supplicant.generate() 对「sta + 桥接」会直接
		 * netifd.setup_failed('BRIDGE_NOT_ALLOWED') 并返回 1：这条限制是给
		 * mac80211/wpad 的（wpad 自己在关联后做 STA 侧桥接）。MTK 的 apcli 由
		 * netifd 的通用机制入桥，而且 PG 7.3 的 mWDS-STA 示例本身就是
		 * `option mode 'sta'` + `option network 'lan'`，所以这里临时摘掉 bridge
		 * 再生成配置。返回的 config 我们只取 conf 文件路径（entry.config），
		 * bridge / 4addr 字段不使用。
		 */
		let gen_iface = {};

		for (let gk, gv in iface_data)
			gen_iface[gk] = gv;

		gen_iface.bridge = null;

		let entry = supplicant.generate(config_list, data, gen_iface);

		if (type(entry) != 'object') {
			log(`failed to generate supplicant config for ${ifname}`);
			continue;
		}

		/* 补全局字段 + 兼容旧 wpad 过滤（原逻辑的扩展） */
		fixup_conf(entry.config, iface_data, data);

		/* 先让驱动把 STA 内核接口创建出来（wpad 自己不会创建） */
		if (!ensure_sta_iface(ifname, phy))
			continue;

		/*
		 * 旧 wpad 没有 ubus 的 macaddr 参数，如果 UCI 里显式配了 macaddr
		 * 且不是 default_macaddr，需要在 attach 之前手动设置接口地址。
		 */
		let cfg = iface_data.config;
		if (!cfg.default_macaddr && cfg.macaddr) {
			system(`ip link set ${shell_quote(ifname)} down 2>/dev/null`);
			system(`ip link set ${shell_quote(ifname)} address ${shell_quote(cfg.macaddr)} 2>/dev/null`);
		}

		if (index(iface_list(), ifname) >= 0) {
			log(`interface ${ifname} already in supplicant, removing first`);
			global_cli(`interface_remove ${shell_quote(ifname)}`);
			sleep(1);
		}

		/* 不带 create：本 wpad 不支持；driver 传空串走默认 driver */
		let ret = global_cli(
			`interface_add ${shell_quote(ifname)} ${shell_quote(entry.config)} ` +
			`'' '' '' ''`
		);

		log(`interface_add ${ifname}: ${ret}`);

		if (substr(ret, 0, 2) != 'OK' && !fs.stat(`/sys/class/net/${ifname}`)) {
			log(`interface_add ${ifname} failed and interface not created`);
			continue;
		}

		if (substr(ret, 0, 2) != 'OK')
			log(`interface_add ${ifname} returned FAIL but interface exists, continuing`);

		system(`ip link set ${shell_quote(ifname)} up`);
		scan_action_start(ifname);
		push(active, ifname);
	}

	return active;
};

/*
 * 清掉属于该 radio 的 apcli 接口（按 L1 profile 的 apcli 前缀匹配）。
 */
export function teardown(apcli_prefix) {
	if (!apcli_prefix)
		return;

	/* 合并 wpa_supplicant 已知的 + 内核里存在的 apcli 接口 */
	let targets = {};

	for (let ifname in iface_list())
		if (substr(ifname, 0, length(apcli_prefix)) == apcli_prefix)
			targets[ifname] = true;

	for (let p in fs.glob(`/sys/class/net/${apcli_prefix}*`)) {
		let ifname = fs.basename(p);

		/* 只取 <prefix><digits>，避免 apcli 前缀误伤 apclii0 */
		if (substr(ifname, 0, length(apcli_prefix)) != apcli_prefix)
			continue;
		if (!match(substr(ifname, length(apcli_prefix)), /^[0-9]+$/))
			continue;

		targets[ifname] = true;
	}

	/* 遍历 object 的键，ucode 里 for...in 对 object 给键名 */
	for (let ifname in targets) {
		log(`teardown: cleaning ${ifname}`);

		scan_action_stop(ifname);

		if (index(iface_list(), ifname) >= 0)
			global_cli(`interface_remove ${shell_quote(ifname)}`);

		remove_sta_iface(ifname);

		fs.unlink(`${WPA_CTRL_DIR}/wpa-supplicant-${ifname}.conf`);
		fs.unlink(`/var/run/scan_state-${ifname}`);
		fs.unlink(`${WPA_CTRL_DIR}/wpa_supplicant-${ifname}.conf`);
	}
};

export { iface_cli, global_cli, iface_list };
