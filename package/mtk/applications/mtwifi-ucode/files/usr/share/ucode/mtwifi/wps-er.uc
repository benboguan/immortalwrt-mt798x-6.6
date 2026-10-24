#!/usr/bin/env ucode
'use strict';

// SPDX-License-Identifier: GPL-2.0
/*
 * mtwifi ucode support - hostapd WPS external registrar action handler
 *
 * Copyright (C) 2026 nanchuci <nanchuci023@gmail.com>
 *
 * Port of files/mtwifi-cfg/hostapd_wps_er_action.lua to ucode.
 *
 * 由 hostapd_cli 调用，参数为 <驱动接口名> <事件名>：
 *   hostapd_cli ... -a "wps-er.uc ra0 WPS-NEW-AP-SETTINGS"
 * 把 hostapd 写下的 WPS 配置（/var/run/hostapd-<iface>.conf 里的
 * "# WPS configuration - START/END" 段）翻译回 UCI wireless 配置，
 * 然后触发 network reload。
 */

import * as fs from 'fs';
import * as uci from 'uci';
import * as ubus from 'ubus';
import { log, readfile, sleep, trim } from 'mtwifi.common';

const IFACE_WPS_FILE = '/var/run/mtwifi-iface-wps';

/* 与 Lua 一致：脚本一开始就打开 cursor，并在整个脚本里复用同一个 */
let ctx = uci.cursor();

/* ucode 的 ARGV 不含脚本名自己，与 Lua 的 arg[1]/arg[2] 等价 */
let iface = ARGV[0];
let event = ARGV[1];

/* 与 Lua 顶部的局部变量一一对应 */
let wps_state;
let ssid;
let ssid2;
let wpa;
let wpa_key_mgmt = [];
let ieee80211w;
let sae_pwe;
let sae_require_mfp;
let wpa_pairwise = [];
let wpa_passphrase;
let wpa_psk;
let auth_algs;

/* 当前 UCI section 名，由下面两张表查得 */
let section;

/*
 * iface 是驱动接口名（ra0/ra1/rai0/rai1/apcli0/...），UCI section 名是
 * default_MT7992_1_1 或 wifinetN 这种，两者没有推导关系。
 * mtwifi 会生成 /var/run/mtwifi-iface-wps 供这里查询。
 */
function section_from_file(iface) {
	let data = readfile(IFACE_WPS_FILE);

	if (data == null)
		return null;

	let map = {};

	for (let line in split(data, '\n')) {
		/*
		 * 对应 Lua 的 line:match("^(%S+)%s+(%S+)$")。
		 * ucode 的 match() 与 Lua 一样：m[0] 是整个匹配，m[1]/m[2] 才是捕获组。
		 */
		let m = match(line, /^(\S+)\s+(\S+)$/);

		if (m)
			map[m[1]] = m[2];
	}

	return map[iface];
};

/*
 * 回退方案：/var/run/mtwifi-iface-wps 里查不到时直接问 ubus。
 * network.wireless status 的结构是
 *   { <radio 名>: { interfaces: [ { section, ifname, config, ... } ] } }
 */
function section_from_ubus(iface) {
	let conn;

	try {
		conn = ubus.connect();
	} catch (e) {
		log(`ubus connect failed: ${e}`);
		return null;
	}

	if (!conn)
		return null;

	let status;

	try {
		status = conn.call('network.wireless', 'status');
	} catch (e) {
		log(`ubus call network.wireless status failed: ${e}`);
		return null;
	}

	for (let radio, rinfo in (status ?? {})) {
		for (let entry in (rinfo?.interfaces ?? [])) {
			if (entry?.ifname == iface && entry?.section)
				return entry.section;
		}
	}

	return null;
};

/*
 * 对应 Lua 的 parse_config() 里的
 *   for match in (line.."="):gmatch("(.-)=") do ... end
 * 即：先补一个 "="，再按 "=" 切分并保留所有（含空的）字段。
 * 因此 Lua 的 result[1]/result[2] 就是这里的 [0]/[1]。
 */
function split_eq(line) {
	let data = line + '=';
	let out = [];
	let start = 0;
	let len = length(data);

	for (let i = 0; i < len; i++) {
		if (substr(data, i, 1) == '=') {
			push(out, substr(data, start, i - start));
			start = i + 1;
		}
	}

	return out;
};

/*
 * 对应 Lua 里的 (s.." "):gmatch("(.-) ")：按空格切分，空格本身不计入结果，
 * 末尾补的空格保证空串得到 { "" }，与 Lua 完全一致。
 */
function split_space(s) {
	let data = (s ?? '') + ' ';
	let out = [];
	let start = 0;
	let len = length(data);

	for (let i = 0; i < len; i++) {
		if (substr(data, i, 1) == ' ') {
			push(out, substr(data, start, i - start));
			start = i + 1;
		}
	}

	return out;
};

function parse_config(line) {
	if (line == null || line == '')
		return;

	let result = split_eq(line);

	if (result[0] == 'wps_state') {
		wps_state = result[1];
	}
	else if (result[0] == 'ssid2') {
		ssid2 = result[1];
	}
	else if (result[0] == 'ssid') {
		ssid = result[1];
	}
	else if (result[0] == 'wpa') {
		wpa = result[1];
	}
	else if (result[0] == 'wpa_key_mgmt') {
		for (let item in split_space(result[1]))
			push(wpa_key_mgmt, item);
		wpa_key_mgmt = sort(wpa_key_mgmt);
	}
	else if (result[0] == 'ieee80211w') {
		ieee80211w = result[1];
	}
	else if (result[0] == 'sae_pwe') {
		sae_pwe = result[1];
	}
	else if (result[0] == 'sae_require_mfp') {
		sae_require_mfp = result[1];
	}
	else if (result[0] == 'wpa_pairwise') {
		for (let item in split_space(result[1]))
			push(wpa_pairwise, item);
		wpa_pairwise = sort(wpa_pairwise);
	}
	else if (result[0] == 'wpa_passphrase') {
		wpa_passphrase = result[1];
	}
	else if (result[0] == 'wpa_psk') {
		wpa_psk = result[1];
	}
	else if (result[0] == 'auth_algs') {
		auth_algs = result[1];
	}
};

section = section_from_file(iface) ?? section_from_ubus(iface);

if (!section)
	exit(0);

/* 下面三个小包装只是让 translate_config() 贴近原 Lua 的 x:set/x:delete 写法 */
function set(opt, val) {
	ctx.set('wireless', section, opt, val);
};

function del(opt) {
	ctx.delete('wireless', section, opt);
};

function set_key() {
	if (wpa_passphrase != null)
		ctx.set('wireless', section, 'key', wpa_passphrase);
	else if (wpa_psk != null)
		ctx.set('wireless', section, 'key', wpa_psk);
};

/*
 * 原 Lua translate_config() 的完整 if/else if 链，逐条照搬（包括重复的
 * 和实际不可达的分支），只是把 wpa_key_mgmt[1]/wpa_pairwise[1] 这类
 * Lua 的 1 基下标整体平移成 ucode 的 0 基下标。
 *
 * 注意：Lua 的 `if x then` 对空字符串也成立，而 ucode 把空字符串当作假，
 * 因此凡是照搬 Lua 的 `if x then`/`elseif x then` 判决的地方都写成
 * `x != null`，保证连 "x=" 这种空值输入的行为也一致。
 */
function translate_config() {
	if (auth_algs == null ||
	    auth_algs != '1') {
		/* TODO log here（与原 Lua 一致：只返回，不打印） */
		return;
	}

	if (wpa == null &&
	    length(wpa_key_mgmt) == 0 &&
	    length(wpa_pairwise) == 0) {
		set('encryption', 'none');
		del('key');
		del('ieee80211w');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '1' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-PSK' &&
	         length(wpa_pairwise) == 2 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         wpa_pairwise[1] == 'TKIP') {
		set('encryption', 'psk+tkip+ccmp');
		set_key();
		del('ieee80211w');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '1' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-PSK' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'CCMP') {
		set('encryption', 'psk+ccmp');
		set_key();
		del('ieee80211w');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '1' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-PSK' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'TKIP') {
		set('encryption', 'psk+tkip');
		set_key();
		del('ieee80211w');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-PSK' &&
	         length(wpa_pairwise) == 2 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         wpa_pairwise[1] == 'TKIP') {
		set('encryption', 'psk2+tkip+ccmp');
		set_key();
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-PSK' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'CCMP') {
		set('encryption', 'psk2+ccmp');
		set_key();
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-PSK' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'TKIP') {
		set('encryption', 'psk2+tkip');
		set_key();
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '3' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-PSK' &&
	         length(wpa_pairwise) == 2 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         wpa_pairwise[1] == 'TKIP') {
		set('encryption', 'psk-mixed+tkip+ccmp');
		set_key();
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '3' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-PSK' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'CCMP') {
		set('encryption', 'psk-mixed+ccmp');
		set_key();
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '3' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-PSK' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'TKIP') {
		set('encryption', 'psk-mixed+tkip');
		set_key();
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'SAE' &&
	         length(wpa_pairwise) == 2 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         wpa_pairwise[1] == 'GCMP-256' &&
	         ieee80211w == '2') {
		set('encryption', 'sae');  /* sae+ccmp+gcmp256 */
		set_key();
		set('ieee80211w', '2');
		if (sae_pwe != null)
			set('sae_pwe', sae_pwe);
		else
			del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'SAE' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         ieee80211w == '2') {
		set('encryption', 'sae+ccmp');
		set_key();
		set('ieee80211w', '2');
		if (sae_pwe != null)
			set('sae_pwe', sae_pwe);
		else
			del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'SAE' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'GCMP-256' &&
	         ieee80211w == '2') {
		set('encryption', 'sae+gcmp256');
		set_key();
		set('ieee80211w', '2');
		if (sae_pwe != null)
			set('sae_pwe', sae_pwe);
		else
			del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'SAE-EXT' &&
	         length(wpa_pairwise) == 2 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         wpa_pairwise[1] == 'GCMP-256' &&
	         ieee80211w == '2') {
		set('encryption', 'sae-ext');
		set_key();
		set('ieee80211w', '2');
		if (sae_pwe != null)
			set('sae_pwe', sae_pwe);
		else
			del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'SAE' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         ieee80211w == '2') {
		/* 原 Lua 中这一段与前面 SAE/CCMP 的分支重复（不可达） */
		set('encryption', 'sae+ccmp');
		set_key();
		set('ieee80211w', '2');
		if (sae_pwe != null)
			set('sae_pwe', sae_pwe);
		else
			del('sae_pwe');
		/* 原 Lua 这里把 sae_pwe 的处理又写了一遍，原样保留 */
		if (sae_pwe != null)
			set('sae_pwe', sae_pwe);
		else
			del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'SAE' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'GCMP-256' &&
	         ieee80211w == '2') {
		/* 原 Lua 中与前面 SAE/GCMP-256 的分支重复（不可达） */
		set('encryption', 'sae+gcmp256');
		set_key();
		set('ieee80211w', '2');
		if (sae_pwe != null)
			set('sae_pwe', sae_pwe);
		else
			del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'SAE-EXT' &&
	         length(wpa_pairwise) == 2 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         wpa_pairwise[1] == 'GCMP-256' &&
	         ieee80211w == '2') {
		/* 原 Lua 中与前面 SAE-EXT 两两 pairwise 的分支重复（不可达） */
		set('encryption', 'sae-ext');
		set_key();
		set('ieee80211w', '2');
		if (sae_pwe != null)
			set('sae_pwe', sae_pwe);
		else
			del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'SAE-EXT' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         ieee80211w == '2') {
		set('encryption', 'sae-ext+ccmp');
		set_key();
		set('ieee80211w', '2');
		if (sae_pwe != null)
			set('sae_pwe', sae_pwe);
		else
			del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'SAE-EXT' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'GCMP-256' &&
	         ieee80211w == '2') {
		set('encryption', 'sae-ext+gcmp256');
		set_key();
		set('ieee80211w', '2');
		if (sae_pwe != null)
			set('sae_pwe', sae_pwe);
		else
			del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 2 &&
	         wpa_key_mgmt[0] == 'SAE' &&
	         wpa_key_mgmt[1] == 'WPA-PSK' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         ieee80211w == '1') {
		set('encryption', 'sae-mixed');
		set_key();
		set('ieee80211w', '1');
		if (sae_pwe != null)
			set('sae_pwe', sae_pwe);
		else
			del('sae_pwe');
		if (sae_require_mfp != null)
			set('sae_require_mfp', sae_require_mfp);
		else
			del('sae_require_mfp');
	}
	else if (wpa == '1' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-EAP' &&
	         length(wpa_pairwise) == 2 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         wpa_pairwise[1] == 'TKIP') {
		set('encryption', 'wpa+tkip+ccmp');
		del('ieee80211w');
		del('sae_pwe');
	}
	else if (wpa == '1' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-EAP' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'CCMP') {
		set('encryption', 'wpa+ccmp');
		del('ieee80211w');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '1' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-EAP' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'TKIP') {
		set('encryption', 'wpa+tkip');
		del('ieee80211w');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-EAP' &&
	         length(wpa_pairwise) == 2 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         wpa_pairwise[1] == 'TKIP') {
		set('encryption', 'wpa2+tkip+ccmp');
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-EAP' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'CCMP') {
		set('encryption', 'wpa2+ccmp');
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-EAP' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'TKIP') {
		set('encryption', 'wpa2+tkip');
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '3' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-EAP' &&
	         length(wpa_pairwise) == 2 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         wpa_pairwise[1] == 'TKIP') {
		set('encryption', 'wpa-mixed+tkip+ccmp');
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '3' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-EAP' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'CCMP') {
		set('encryption', 'wpa-mixed+ccmp');
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '3' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-EAP' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'TKIP') {
		set('encryption', 'wpa-mixed+tkip');
		if (ieee80211w != null)
			set('ieee80211w', ieee80211w);
		else
			set('ieee80211w', '0');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-EAP-SHA256' &&
	         /*
	          * 原 Lua 为
	          *   (wpa_pairwise[0] == "CCMP" or wpa_pairwise[1] == "CCMP")
	          * Lua 数组从 1 开始，[0] 恒为 nil，所以那里实际只看 Lua 的
	          * [1]（即 ucode 的 [0]）。两者等价（数组已排序，CCMP 一定在
	          * 首位），这里保留原来的两段判断。
	          */
	         (wpa_pairwise[0] == 'CCMP' ||
	          wpa_pairwise[1] == 'CCMP') &&
	         ieee80211w == '2') {
		set('encryption', 'wpa3');
		set('ieee80211w', '2');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 1 &&
	         wpa_key_mgmt[0] == 'WPA-EAP-SUITE-B-192' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'GCMP-256' &&
	         ieee80211w == '2') {
		set('encryption', 'wpa3-192');
		set('ieee80211w', '2');
		del('sae_pwe');
		del('sae_require_mfp');
	}
	else if (wpa == '2' &&
	         length(wpa_key_mgmt) == 2 &&
	         wpa_key_mgmt[0] == 'WPA-EAP' &&
	         wpa_key_mgmt[1] == 'WPA-EAP-SUITE-B-192' &&
	         length(wpa_pairwise) == 1 &&
	         wpa_pairwise[0] == 'CCMP' &&
	         ieee80211w == '1') {
		set('encryption', 'wpa3-mixed');
		set('ieee80211w', '1');
		del('sae_pwe');
		del('sae_require_mfp');
	}

	if (ssid != null) {
		set('ssid', ssid);
	}

	set('wps_state', '2');
	ctx.commit('wireless');

	system("(sleep 1; ubus call network reload) >/dev/null 2>&1 &");
};

/* 只处理 WPS-NEW-AP-SETTINGS 事件，其余直接退出（对应 Lua 的 return） */
if (event != 'WPS-NEW-AP-SETTINGS')
	exit(0);

/* 等 1s，让配置写入完成 */
sleep(1);

/*
 * 新版的 handler 用 <phy><.radio> 命名 hostapd 配置文件
 * （例如 /var/run/hostapd-phy0.conf），文件名和驱动接口名不再对应，
 * 因此先按老名字猜两个路径，猜不中再扫描 /var/run/hostapd-*.conf，
 * 找第一个含 interface=<iface> 或 bss=<iface> 的文件。
 * handler 会留下 <file>.prev，需要跳过。
 */
function find_conf_by_content(iface) {
	let files;

	try {
		files = fs.glob('/var/run/hostapd-*.conf');
	} catch (e) {
		return null;
	}

	/* glob 不保证顺序，排序后取“第一个”才是确定的 */
	for (let path in sort(files ?? [])) {
		if (match(path, /\.prev$/) != null)
			continue;

		let data = readfile(path);

		if (data == null)
			continue;

		for (let line in split(data, '\n')) {
			let m = match(trim(line), /^interface=(.*)$/) ??
			        match(trim(line), /^bss=(.*)$/);

			if (m && m[1] == iface)
				return path;
		}
	}

	return null;
};

/* 与 Lua 一致：在 /var/run 与 /var/run/hostapd 下各找一个能打开的文件 */
let conf_data = null;

for (let path in [ `/var/run/hostapd-${iface}.conf`,
                   `/var/run/hostapd/hostapd-${iface}.conf` ]) {
	conf_data = readfile(path);

	if (conf_data != null)
		break;
}

/* 老命名没命中时，按文件内容再找一次 */
if (conf_data == null) {
	let path = find_conf_by_content(iface);

	if (path != null)
		conf_data = readfile(path);
}

if (conf_data == null)
	exit(0);

let lines = split(conf_data, '\n');

function reset_parsed() {
	wps_state = null;
	ssid = null;
	ssid2 = null;
	wpa = null;
	wpa_key_mgmt = [];
	ieee80211w = null;
	sae_pwe = null;
	sae_require_mfp = null;
	wpa_pairwise = [];
	wpa_passphrase = null;
	wpa_psk = null;
	auth_algs = null;
};

/*
 * 在 lines[from, to) 范围内解析第一个 "# WPS configuration - START/END" 块。
 * 返回 true 表示找到了完整的块。
 */
function parse_wps_block(lines, from, to) {
	let started = false;

	for (let i = from; i < to; i++) {
		let line = lines[i];

		if (line == '# WPS configuration - START') {
			started = true;
			/* 与原 Lua 一样：START 标记行本身也会走一次 parse_config() */
			parse_config(line);
			continue;
		}

		if (line == '# WPS configuration - END')
			return started;

		if (started)
			parse_config(line);
	}

	return false;
};

/*
 * 找出 iface 所属 BSS 段的行范围 [start, end)。
 * hostapd conf 用 "interface=<ifname>" 起主 BSS、"bss=<ifname>" 起扩展 BSS，
 * 一个 phy 的 conf 里可能有多个 BSS，所以要先定位到自己的那一段，
 * 否则会读到别的 BSS 的 WPS 配置（旧实现只有单 BSS 时才对）。
 */
function bss_range(lines, iface) {
	let start = -1;

	for (let i = 0; i < length(lines); i++) {
		let m = match(trim(lines[i]), /^interface=(.*)$/) ??
		        match(trim(lines[i]), /^bss=(.*)$/);

		if (!m)
			continue;

		if (start >= 0)
			return [ start, i ];

		if (m[1] == iface)
			start = i;
	}

	return start >= 0 ? [ start, length(lines) ] : null;
};

let range = bss_range(lines, iface);
let parsed = false;

if (range) {
	reset_parsed();
	parsed = parse_wps_block(lines, range[0], range[1]);
}

/* 兜底：conf 里没有对应的 BSS 段或段内没有 WPS 块时，沿用旧行为（整文件第一个块） */
if (!parsed) {
	reset_parsed();
	parse_wps_block(lines, 0, length(lines));
}

translate_config();
