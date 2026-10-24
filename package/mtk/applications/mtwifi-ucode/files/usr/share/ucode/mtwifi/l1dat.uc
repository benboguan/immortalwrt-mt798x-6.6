'use strict';

// SPDX-License-Identifier: GPL-2.0
/*
 * mtwifi ucode support - L1 profile (/etc/wireless/l1profile.dat) parser
 *
 * Copyright (C) 2023 hanwckf <hanwckf@vip.qq.com>
 * Copyright (C) 2025-2026 nanchuci <nanchuci023@gmail.com>
 *
 * Port of files/l1util/l1dat_parser.lua to ucode.
 *
 * 解析结果 devs 的结构与原 Lua 版一致：
 *   devs[1..n]                    每个 INDEX# 段一个表
 *   devs.ifname_ridx[ifname]      接口名 -> 所属 dev 表（DBDC 按 ; 拆开）
 *   devs.devname_ridx[devname]    devname(INDEX_mainidx[_subidx]) -> dev 表
 * 额外提供 list()/by_idx()/dbdc_idx() 等 l1util 需要的辅助函数。
 */

import * as fs from 'fs';
import { trim } from 'mtwifi.common';
import { cfg2list, token_get, load_profile } from 'mtwifi.dat';

export const L1_DAT_PATH = '/etc/wireless/l1profile.dat';

export const IF_RINDEX = 'ifname_ridx';
export const DEV_RINDEX = 'devname_ridx';

export const MAX_NUM_APCLI = 1;
export const MAX_NUM_WDS = 4;
export const MAX_NUM_MESH = 1;
export const MAX_NUM_EXTIF = 16;
export const MAX_NUM_DBDC_BAND = 2;

/* 与 l1dat_parser.lua 的 l1cfg_options 保持一致 */
const l1cfg_options = {
	ext_ifname: '',
	apcli_ifname: 'apcli',
	wds_ifname: 'wds',
	mesh_ifname: 'mesh',
};

/* profile 里不参与 ";" 拆分的元数据键 */
const meta_keys = {
	INDEX: true,
	EEPROM_offset: true,
	EEPROM_size: true,
	mainidx: true,
};

function band_count_of(dev) {
	let base = dev?.main_ifname ?? '';
	if (!length(base))
		return 1;

	return max(length(split(base, ';')), 1);
};

function expand_profile_path(dev) {
	let pp = dev.profile_path;
	if (pp == null || index(pp, ';') >= 0)
		return;

	let band_num = band_count_of(dev);
	if (band_num <= 1)
		return;

	let phys = load_profile(pp);
	if (!phys)
		return;

	let list = [];
	let found = false;

	for (let i = 0; i < band_num; i++) {
		let bn = phys[`BN${i}_profile_path`];
		if (bn != null && length(bn) > 0) {
			found = true;
			list[i] = bn;
		} else {
			list[i] = '';
		}
	}

	if (found)
		dev.profile_path = join(';', list);
};

function add_default_value(devs) {
	for (let k, v in devs) {
		if (type(v) != 'object' || k == IF_RINDEX || k == DEV_RINDEX)
			continue;

		for (let opt, def in l1cfg_options) {
			if (v[opt] != null)
				continue;

			if (opt == 'ext_ifname')
				v[opt] = `${v.main_ifname}_`;
			else
				v[opt] = `${def}${k}_`;
		}
	}

	return devs;
};

function setup_reverse_index(devs) {
	let ridx = IF_RINDEX;
	let dridx = DEV_RINDEX;

	devs[ridx] = {};
	devs[dridx] = {};

	for (let k, dev in devs) {
		if (k == IF_RINDEX || k == DEV_RINDEX)
			continue;
		if (type(dev) != 'object')
			continue;

		let band_num = band_count_of(dev);
		let dbdc_if = [];

		dbdc_if[band_num - 1] = token_get(dev.main_ifname, band_num, null);

		if (band_num > 1 && dbdc_if[band_num - 1] != null) {
			/* 多 band：main_ifname = "ra0;rai0;rax0" 这类 */
			for (let i = 1; i < band_num; i++)
				dbdc_if[i - 1] = token_get(dev.main_ifname, i, null);

			for (let i = 1; i <= band_num; i++) {
				let ifname = dbdc_if[i - 1];

				if (ifname == null)
					continue;

				let idev = devs[ridx][ifname] = {};

				idev.subidx = i;

				for (let k, v in dev) {
					if (meta_keys[k])
						idev[k] = v;
					else
						idev[k] = token_get(v, i, '');
				}

				let devname = `${dev.INDEX}_${dev.mainidx}_${idev.subidx}`;

				devs[dridx][devname] = idev;
			}

			let ext_if = [], apcli_if = [], wds_if = [], mesh_if = [];

			for (let i = 1; i <= band_num; i++) {
				ext_if[i - 1] = token_get(dev.ext_ifname, i, null);
				apcli_if[i - 1] = token_get(dev.apcli_ifname, i, null);
				wds_if[i - 1] = token_get(dev.wds_ifname, i, null);
				mesh_if[i - 1] = token_get(dev.mesh_ifname, i, null);
			}

			for (let i = 1; i <= MAX_NUM_EXTIF - 1; i++)	/* ext ifname 下标从 0 起 */
				for (let j = 1; j <= band_num; j++)
					if (ext_if[j - 1] != null)
						devs[ridx][`${ext_if[j - 1]}${i}`] = devs[ridx][dbdc_if[j - 1]];

			for (let i = 0; i <= MAX_NUM_APCLI - 1; i++)
				for (let j = 1; j <= band_num; j++)
					if (apcli_if[j - 1] != null)
						devs[ridx][`${apcli_if[j - 1]}${i}`] = devs[ridx][dbdc_if[j - 1]];

			for (let i = 0; i <= MAX_NUM_WDS - 1; i++)
				for (let j = 1; j <= band_num; j++)
					if (wds_if[j - 1] != null)
						devs[ridx][`${wds_if[j - 1]}${i}`] = devs[ridx][dbdc_if[j - 1]];

			for (let i = 0; i <= MAX_NUM_MESH - 1; i++)
				for (let j = 1; j <= band_num; j++)
					if (mesh_if[j - 1] != null)
						devs[ridx][`${mesh_if[j - 1]}${i}`] = devs[ridx][dbdc_if[j - 1]];
		} else {
			/* 单 band 卡 */
			devs[ridx][dev.main_ifname] = dev;

			let devname = dev.subidx != null
				? `${dev.INDEX}_${dev.mainidx}_${dev.subidx}`
				: `${dev.INDEX}_${dev.mainidx}`;

			devs[dridx][devname] = dev;

			for (let i = 1; i <= MAX_NUM_EXTIF - 1; i++)
				devs[ridx][`${dev.ext_ifname}${i}`] = dev;

			for (let i = 0; i <= MAX_NUM_APCLI - 1; i++)
				devs[ridx][`${dev.apcli_ifname}${i}`] = dev;

			for (let i = 0; i <= MAX_NUM_WDS - 1; i++)
				devs[ridx][`${dev.wds_ifname}${i}`] = dev;

			for (let i = 0; i <= MAX_NUM_MESH - 1; i++)
				devs[ridx][`${dev.mesh_ifname}${i}`] = dev;
		}
	}

	return devs;
};

/*
 * 载入 L1 profile。
 * 与原 Lua 版差异：非 INDEX* 键（原版会因 tonumber(nil) 报错）直接忽略；
 * 文件不存在时返回 null 而不是空表，便于调用者区分“没文件”和“空文件”。
 */
export function load(path) {
	path = path ?? L1_DAT_PATH;

	let text;

	try {
		text = fs.readfile(path);
	} catch (e) {
		return null;
	}

	let devs = {};
	let chipset_num = {};

	if (text != null) {
		for (let line in split(text, '\n')) {
			line = trim(line);
			if (!length(line) || substr(line, 0, 1) == '#')
				continue;

			let sep = index(line, '=');
			if (sep < 0)
				continue;

			let key = trim(substr(line, 0, sep));
			let val = trim(substr(line, sep + 1));
			let m = match(key, /^INDEX(\d+)_(.+)$/);

			if (m) {
				let idx = +m[1] + 1;
				devs[idx] ??= {};
				devs[idx][m[2]] = val;
				continue;
			}

			m = match(key, /^INDEX(\d+)$/);
			if (m) {
				let idx = +m[1] + 1;
				devs[idx] ??= {};
				devs[idx].INDEX = val;

				chipset_num[val] = (chipset_num[val] ?? 0) + 1;
				devs[idx].mainidx = chipset_num[val];
			}
		}
	}

	add_default_value(devs);

	for (let k, dev in devs) {
		if (k == IF_RINDEX || k == DEV_RINDEX || type(dev) != 'object')
			continue;
		expand_profile_path(dev);
	}

	setup_reverse_index(devs);

	return devs;
};

/*
 * 带缓存版本：handler 在一次 setup 里会多次查询 L1 profile。
 */
let cache_path;
let cache_data;

export function load_cached(path) {
	path = path ?? L1_DAT_PATH;

	if (cache_path != path || cache_data == null) {
		cache_data = load(path);
		cache_path = path;
	}

	return cache_data;
};

export function flush_cache() {
	cache_path = null;
	cache_data = null;
};

function devname_of(dev, idx) {
	/* devname = INDEX_mainidx[_subidx] */
	return dev.subidx != null
		? `${dev.INDEX}_${dev.mainidx}_${dev.subidx}`
		: `${dev.INDEX}_${dev.mainidx}`;
};

/* l1util list：按 devname 排序输出（含 ax7800 特例） */
export function list(devs) {
	let ret = [];

	for (let devname, dev in devs[DEV_RINDEX]) {
		/* 跳过 ax7800 项目的 MT7986-2.4G */
		if (dev.profile_path != null && match(dev.profile_path, /ax7800/) &&
		    dev.INDEX == 'MT7986' && dev.subidx == 1)
			continue;

		push(ret, devname);
	}

	return sort(ret);
};

export function ifname_by_idx(devs, idx) {
	idx = +idx;

	let count = 0;

	for (let k, dev in devs) {
		if (k == IF_RINDEX || k == DEV_RINDEX)
			continue;
		if (type(dev) != 'object')
			continue;

		let band_num = band_count_of(dev);

		if (band_num <= 1) {
			count += 1;

			if (count == idx)
				return dev.main_ifname;

			continue;
		}

		if (count + band_num >= idx) {
			let token_num = idx - count;

			return token_get(dev.main_ifname, token_num, null);
		}

		count += band_num;
	}

	return null;
};

export function ifname_to_datpath(devs, ifname) {
	if (!ifname)
		return null;

	return devs[IF_RINDEX][ifname]?.profile_path;
};

export function ifname_to_zone(devs, ifname) {
	if (!ifname)
		return null;

	return devs[IF_RINDEX][ifname]?.nvram_zone;
};

export function zone_to_ifname(devs, zone) {
	if (!zone)
		return null;

	let zone_dev;

	for (let _, dev in devs[DEV_RINDEX])
		if (dev.nvram_zone == zone)
			zone_dev = dev;

	if (!zone_dev)
		return null;

	return {
		main_ifname: zone_dev.main_ifname,
		ext_ifname: zone_dev.ext_ifname,
		apcli_ifname: zone_dev.apcli_ifname,
		wds_ifname: zone_dev.wds_ifname,
		mesh_ifname: zone_dev.mesh_ifname,
	};
};

export function dbdc_idx(devs, ifname) {
	if (!ifname || !devs[IF_RINDEX][ifname])
		return null;

	return devs[IF_RINDEX][ifname].subidx ?? 0;
};

/* l1dat_parser.get_value_by_idx 的等价实现 */
export function get_value_by_idx(devs, devidx, mainidx, subidx, key) {
	if (devidx == null || mainidx == null || !key)
		return null;

	let dev_ridx = devs[DEV_RINDEX];
	let sidx = subidx ?? 1;
	let devname1 = `${devidx}_${mainidx}`;
	let devname2 = `${devidx}_${mainidx}_${sidx}`;

	return dev_ridx[devname2]?.[key] ?? dev_ridx[devname1]?.[key];
};

/*
 * 便捷封装：把 dev 表里 ";" 分隔的字段按 band 取值。
 * subidx 从 1 开始（DBDC 卡 subidx=1 是第一个 band）。
 */
export function band_value(dev, key, subidx) {
	if (!dev)
		return null;

	let v = dev[key];
	if (type(v) != 'string' || index(v, ';') < 0)
		return v;

	return token_get(v, subidx ?? dev.subidx ?? 1, '');
};

export function band_list(dev, key) {
	if (!dev || type(dev[key]) != 'string')
		return [];

	return cfg2list(dev[key]);
};

export { devname_of };
