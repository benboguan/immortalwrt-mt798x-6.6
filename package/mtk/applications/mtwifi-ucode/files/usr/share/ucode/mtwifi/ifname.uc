'use strict';

// SPDX-License-Identifier: GPL-2.0
/*
 * mtwifi ucode support - VAP interface name allocation
 *
 * Copyright (C) 2023 hanwckf <hanwckf@vip.qq.com>
 * Copyright (C) 2025-2026 nanchuci <nanchuci023@gmail.com>
 *
 * MTK 驱动自己创建 VAP（ra0/ra1/... 与 apcli0），netifd 只需要知道
 * 每个 UCI wifi-iface 对应哪个接口名。这里对应旧 shell 处理器里的
 * mtwifi_vif_ap_set_data() / mtwifi_vif_sta_set_data()。
 */

import * as fs from 'fs';
import { log, trim } from 'mtwifi.common';

/* 与 mtwifi.sh 里的 MTWIFI_MAX_AP_IDX / MTWIFI_MAX_APCLI_IDX 一致 */
export const MAX_AP_IDX = 15;
export const MAX_APCLI_IDX = 0;

function iface_keys(payload) {
	return sort(keys(payload.interfaces ?? {}));
};

/* ifname 是否属于该 dev（按其 ifname 前缀判断） */
function belongs_to(ifname, dev) {
	if (ifname == null || dev == null)
		return false;

	for (let p in [ dev.main_ifname, dev.ext_ifname, dev.apcli_ifname, dev.wds_ifname, dev.mesh_ifname ]) {
		if (p != null && length(p) > 0 && substr(ifname, 0, length(p)) == p)
			return true;
	}

	return false;
};

/*
 * 为 payload.interfaces 里的每个 vif 分配 config.ifname。
 *
 * - ap  : <ext_ifname><idx>   （ext_ifname 来自 L1 profile，如 ra / rai / rax）
 * - sta : <apcli_ifname><idx> （如 apcli / apclii / apclix）
 *
 * 用户显式配置的 ifname 会被保留（此时仍占用一个下标，和旧 shell 行为一致）。
 * 返回实际生效的接口名数组。
 */
export function assign(payload, dev) {
	let ap_idx = 0;
	let apcli_idx = 0;
	let active = [];

	if (!dev) {
		log('no L1 profile entry, cannot assign VIF names');
		return active;
	}

	for (let k in iface_keys(payload)) {
		let v = payload.interfaces[k];
		if (!v || !v.config)
			continue;

		let mode = v.config.mode;
		let ifname = v.config.ifname;

		if (mode == 'ap') {
			if (ap_idx <= MAX_AP_IDX && !ifname)
				ifname = `${dev.ext_ifname}${ap_idx}`;
			ap_idx++;
		} else if (mode == 'sta') {
			if (apcli_idx <= MAX_APCLI_IDX && !ifname)
				ifname = `${dev.apcli_ifname}${apcli_idx}`;
			apcli_idx++;
		}

		if (!ifname) {
			log(`no ifname for vif ${v.name} (mode ${mode}); skipped`);
			continue;
		}

		v.config.ifname = ifname;
		push(active, ifname);
	}

	return active;
};

/*
 * hostapd 的 WPS external registrar 需要 “驱动接口名 -> UCI section 名” 的映射，
 * 对应旧的 /var/run/mtwifi-iface-wps 文件。返回 { <ifname>: <section> }。
 */
export function wps_map(payload) {
	let map = {};

	for (let k in iface_keys(payload)) {
		let v = payload.interfaces[k];
		if (v?.config?.ifname && v.name)
			map[v.config.ifname] = v.name;
	}

	return map;
};

/* 读回已有的映射文件 */
export function read_wps_map(path) {
	let map = {};
	let f = fs.open(path, 'r');

	if (!f)
		return map;

	let text = f.read('all') ?? '';
	f.close();

	for (let line in split(text, '\n')) {
		let m = match(trim(line), /^(\S+)\s+(\S+)$/);

		if (m)
			map[m[1]] = m[2];
	}

	return map;
};

function save_wps_map(map, path) {
	let lines = [];

	for (let ifname in sort(keys(map)))
		push(lines, `${ifname} ${map[ifname]}`);

	let text = length(lines) ? join('\n', lines) + '\n' : '';
	let f = fs.open(path, 'w');

	if (!f) {
		log(`failed to write ${path}`);
		return false;
	}

	f.write(text);
	f.close();

	return true;
};

/*
 * 更新映射：先删掉属于该 radio 的旧条目，再加入当前 vif。
 * 对应 mtwifi_cfg 里的 update_iface_wps()。
 */
export function write_wps_map(payload, dev, path) {
	let map = read_wps_map(path);

	if (dev)
		for (let ifname in keys(map))
			if (belongs_to(ifname, dev))
				delete map[ifname];

	for (let ifname, section in wps_map(payload))
		map[ifname] = section;

	return save_wps_map(map, path);
};

/* teardown：只删掉该 radio 的条目，保留其它 radio 的映射 */
export function remove_wps_map(dev, path) {
	let map = read_wps_map(path);

	if (dev)
		for (let ifname in keys(map))
			if (belongs_to(ifname, dev))
				delete map[ifname];

	return save_wps_map(map, path);
};

/* 当前 vif 列表里是否有某个 mode */
export function has_mode(payload, mode) {
	for (let k in iface_keys(payload))
		if (payload.interfaces[k]?.config?.mode == mode)
			return true;

	return false;
};
