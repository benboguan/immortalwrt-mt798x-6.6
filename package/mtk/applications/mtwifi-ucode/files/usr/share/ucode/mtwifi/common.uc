'use strict';

// SPDX-License-Identifier: GPL-2.0
/*
 * mtwifi ucode support - common helpers
 *
 * Copyright (C) 2026 nanchuci <nanchuci023@gmail.com>
 *
 * Port of files/mtwifi-cfg/mtwifi_utils.lua to ucode.
 */

import * as fs from 'fs';

const LOG_FILE = '/tmp/mtwifi.log';

/*
 * shell 参数转义（等价于把参数用单引号包起来）。
 * 用于拼接 mwctl / ip / logger 等命令行。
 * 不使用 /g 正则标志，改用 split/join 做全局替换。
 */
export function shell_quote(s) {
	if (s == null)
		return "''";

	return "'" + join("'\\''", split('' + s, "'")) + "'";
};

/*
 * 与 shell 的 log_msg()/logger -t 等价。
 * 注意：netifd 的 handler "dump" 操作会解析 stdout 中的 JSON 行，
 * 所以 dump 路径里不要调用 log()；这里统一走 stderr。
 */
export function log(msg) {
	warn(`mtwifi: ${msg}\n`);
};

/*
 * 同时写 syslog 与 stderr：netifd 会把 handler 的 stdout/stderr 收进
 * log_prefix 标记的日志里，所以 warn() 已经足够，syslog 走 logger 命令。
 */
export function log_syslog(msg) {
	warn(`mtwifi: ${msg}\n`);
	system(`logger -t mtwifi ${shell_quote(msg)}`);
};

export function trim(s) {
	if (s == null)
		return null;

	return replace(replace('' + s, /^\s+/, ''), /\s+$/, '');
};

export function rtrim(s) {
	if (s == null)
		return null;

	return replace('' + s, /\s+$/, '');
};

export function exists(path) {
	return fs.stat(path) != null;
};

export function readfile(path) {
	try {
		return fs.readfile(path);
	} catch (e) {
		return null;
	}
};

export function writefile(path, data) {
	try {
		return fs.writefile(path, data);
	} catch (e) {
		log(`failed to write ${path}: ${e}`);
		return null;
	}
};

export function glob(pattern) {
	try {
		return fs.glob(pattern) ?? [];
	} catch (e) {
		return [];
	}
};

/* 与 mtwifi_utils.read_pipe 等价的、带重试的管道读取 */
export function read_pipe(cmd) {
	let retry = 10;
	let txt = null;

	while (retry-- > 0) {
		let p = fs.popen(cmd);
		if (!p)
			break;
		try {
			txt = p.read('all');
		} catch (e) {
			txt = null;
		}
		p.close();
		if (txt != null)
			break;
	}

	return txt;
};

/* 与 mtwifi_utils.sleep 等价的毫秒级 sleep（ucode 无 sleep 原语） */
export function sleep(sec) {
	let s = int(sec + 0.999);

	if (s < 1)
		s = 1;
	system(`sleep ${s}`);
};

/* 与 mtwifi_utils.log2file 等价 */
export function timestr() {
	let t = localtime();

	return sprintf('%02d:%02d:%02d', t.hour, t.min, t.sec);
};

export function log2file(str) {
	let f = fs.open(LOG_FILE, 'a');
	if (!f)
		return;

	f.write(sprintf('%s %s\n', timestr(), str));
	f.close();
};

/* 把 object 转成可读字符串，替代原来 require("inspect") 的调试输出 */
export function dump(obj) {
	return sprintf('%.J', obj);
};

export function basename(path) {
	return fs.basename(path);
};

export function dirname(path) {
	return fs.dirname(path);
};
