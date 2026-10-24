'use strict';

// SPDX-License-Identifier: GPL-2.0
/*
 * mtwifi ucode support - MTK .dat file reader/writer
 *
 * Copyright (C) 2025-2026 nanchuci <nanchuci023@gmail.com>
 *
 * 这是一个纯 ucode 的 datconf-lua 替代实现。行为和 libkvcutil 保持一致：
 *
 *   - 以 CRLF / CR / LF 切分，默认行尾取自文件首个行尾
 *   - 以 '#' 开头或没有 '=' 的行视为 “invalid”，原样保留
 *   - 合法行的 key / value 两侧空白被去掉，但 SSID* / ApCliSsid 的
 *     value 不去空白（对应 libdatconf.c 的 dat_nostrip_list）
 *   - 写回时：invalid 行原样写出，合法行统一写成 "key=value"（无空格），
 *     新增的 key 追加到文件末尾
 *
 * 与 datconf-lua 的差异：datconf 的 close(true) 会把整个文件重写一遍
 * （因此会顺带规格化所有行的空白），这里只在确实有 key 变化时才写回，
 * 且未变化的行保持原样，对 flash 更友好。
 */

import * as fs from 'fs';
import { log, trim } from 'mtwifi.common';

/* libdatconf.c: dat_nostrip_list，SSID 允许包含空格 */
const nostrip_keys = {
	SSID: true, SSID1: true, SSID2: true, SSID3: true, SSID4: true,
	SSID5: true, SSID6: true, SSID7: true, SSID8: true, SSID9: true,
	SSID10: true, SSID11: true, SSID12: true, SSID13: true, SSID14: true,
	SSID15: true, SSID16: true, ApCliSsid: true,
};

function ltrim(s) {
	return replace(s, /^\s+/, '');
};

function rtrim(s) {
	return replace(s, /\s+$/, '');
};

function detect_eol(data) {
	if (match(data, /\r\n/))
		return '\r\n';
	if (match(data, /\r/))
		return '\r';
	return '\n';
};

/*
 * 打开一个 .dat 文件。
 * 返回 dobject：
 *   path        文件路径
 *   items       有序行表（写回用）
 *   index       key -> items 下标（首次出现）
 *   data        key -> value 字典（重复 key 以最后一次为准，和 Lua table 一致）
 *   eol         行尾
 *   trailing    文件是否以行尾结束
 *   changed     是否需要写回
 * 文件不存在时返回 null（调用者负责报错）。
 */
export function open(path) {
	let data;

	try {
		data = fs.readfile(path);
	} catch (e) {
		log(`failed to open ${path}: ${e}`);
		return null;
	}

	let dobj = {
		path,
		items: [],
		index: {},
		data: {},
		eol: data ? detect_eol(data) : '\n',
		trailing: data ? (match(data, /(\r\n|\r|\n)$/) != null) : true,
		changed: false,
	};

	if (!data)
		return dobj;

	let lines = split(data, /\r\n|\r|\n/);

	/* 结尾有行尾时会多切出一个空串，丢掉它 */
	if (dobj.trailing && length(lines) > 0)
		lines = slice(lines, 0, length(lines) - 1);

	for (let line in lines) {
		let item = {
			raw: line,
			invalid: true,
			key: null,
			value: null,
		};

		if (length(ltrim(line)) > 0 && substr(ltrim(line), 0, 1) != '#') {
			let sep = index(line, '=');
			if (sep >= 0) {
				let key = rtrim(substr(line, 0, sep));
				let rest = substr(line, sep + 1);
				let value = nostrip_keys[rtrim(key)] ? rest : rtrim(ltrim(rest));

				item.invalid = false;
				item.key = key;
				item.value = value;

				if (dobj.index[key] == null)
					dobj.index[key] = length(dobj.items);
				dobj.data[key] = value;
			}
		}

		push(dobj.items, item);
	}

	return dobj;
};

/* kvc_get()：返回首次出现的值 */
export function get(dobj, key) {
	if (!dobj || dobj.index[key] == null)
		return null;

	return dobj.items[dobj.index[key]].value;
};

/* kvc_get_all() 的字典视图；直接返回内部表，调用者可当普通对象用 */
export function getall(dobj) {
	return dobj ? dobj.data : {};
};

/* kvc_set()：更新首次出现的 key，不存在则追加 */
export function set(dobj, key, value) {
	if (!dobj || key == null || value == null)
		return false;

	value = '' + value;

	if (dobj.index[key] != null) {
		let item = dobj.items[dobj.index[key]];
		if (item.value == value)
			return true;
		item.value = value;
	} else {
		dobj.index[key] = length(dobj.items);
		push(dobj.items, { raw: null, invalid: false, key, value });
	}

	dobj.data[key] = value;
	dobj.changed = true;

	return true;
};

/* datobj:merge(cfgs) */
export function merge(dobj, dict) {
	if (!dobj || !dict)
		return false;

	for (let key, value in dict)
		set(dobj, key, value);

	return true;
};

/*
 * datobj:close(true)：写回文件。
 * 只有 changed 时才真正落盘，并 sync 一次（与 save_profile 一致）。
 */
export function close(dobj) {
	if (!dobj)
		return false;

	if (!dobj.changed)
		return true;

	let out = [];

	for (let item in dobj.items)
		push(out, item.invalid ? item.raw : `${item.key}=${item.value}`);

	let text = join(dobj.eol, out);
	if (dobj.trailing)
		text += dobj.eol;

	try {
		fs.writefile(dobj.path, text);
	} catch (e) {
		log(`failed to save ${dobj.path}: ${e}`);
		return false;
	}

	dobj.changed = false;
	system('sync');

	return true;
};

/*
 * ==== 以下为 mtwifi_utils.lua 里的 token 操作 ====
 * .dat 里多个 VAP/Band 共用一行，用 ';' 分隔（例如
 * "SSID=foo;bar" 表示 band1=foo, band2=bar）。
 */

/* __cfg2list：按 ';' 切分成列表 */
export function cfg2list(str) {
	if (str == null)
		return [];

	return filter(split('' + str, ';'), (v) => length(v) > 0) ?? [];
};

/* token_get：n 从 1 开始，越界返回默认值 */
export function token_get(str, n, def) {
	if (str == null)
		return def;

	n = +n;
	let list = cfg2list(str);

	return list[n - 1] ?? def;
};

/* token_set：n 从 1 开始，中间空位用 v 补齐（与 Lua 版一致） */
export function token_set(str, n, value) {
	if (value == null)
		return str;

	n = +n;
	let list = cfg2list(str);
	let t = type(value);

	if (t != 'string' && t != 'int' && t != 'double')
		return str;

	value = '' + value;

	if (length(list) < n) {
		for (let i = length(list); i < n; i++)
			list[i] = value;	/* 中间空位补 value */
	} else {
		list[n - 1] = value;
	}

	let out = join(';', list);

	/* 去掉头尾与重复的分号，和 Lua 版 gsub 等价 */
	out = replace(out, /^;+/, '');
	out = replace(out, /;+$/, '');
	out = replace(out, /;+/, ';');

	return out;
};

/*
 * 读取 profile（等价于 mtwifi_utils.load_profile），
 * 返回 key -> value 的字典；文件不存在返回 null。
 */
export function load_profile(path) {
	let dobj = open(path);
	if (!dobj)
		return null;

	return dobj.data;
};

/*
 * 保存 profile（等价于 save_profile）：合并到已有文件并写回。
 */
export function save_profile(cfgs, path) {
	if (!cfgs) {
		log('configuration was empty, nothing saved');
		return false;
	}

	let dobj = open(path);
	if (!dobj)
		return false;

	merge(dobj, cfgs);

	return close(dobj);
};
