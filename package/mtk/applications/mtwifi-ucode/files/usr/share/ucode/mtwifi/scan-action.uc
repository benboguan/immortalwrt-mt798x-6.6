#!/usr/bin/env ucode
'use strict';

// SPDX-License-Identifier: GPL-2.0
/*
 * mtwifi ucode support - wpa_supplicant scan action script
 *
 * Copyright (C) 2026 nanchuci <nanchuci023@gmail.com>
 *
 * Port of files/mtwifi-cfg/supplicant_scan_action.sh to ucode.
 *
 * 由 wpa_supplicant/wpa_cli 调用，参数为 <接口名> <事件名>：
 *   wpa_cli -a "scan-action.uc ra0 CTRL-EVENT-SCAN-STARTED"
 * 把扫描进度写到 /var/run/scan_state-<iface>，供 mtwifi 查询。
 */

import { writefile } from 'mtwifi.common';

/* 与 shell 里的 case 分支一一对应 */
const SCAN_STATES = {
	'CTRL-EVENT-SCAN-STARTED': 'start',
	'CTRL-EVENT-SCAN-FAILED': 'failed',
	'CTRL-EVENT-SCAN-RESULTS': 'done',
};

/* ucode 的 ARGV 不含脚本名自己，与 shell 的 $1/$2 等价 */
let iface = ARGV[0];
let event = ARGV[1] ?? '';
let state = SCAN_STATES[event];

/* 未知事件（以及缺少参数）直接忽略，与原 shell 的 case 一致 */
if (iface && state != null) {
	/* echo 会带一个换行，这里保持一致 */
	writefile(`/var/run/scan_state-${iface}`, `${state}\n`);
}

exit(0);
