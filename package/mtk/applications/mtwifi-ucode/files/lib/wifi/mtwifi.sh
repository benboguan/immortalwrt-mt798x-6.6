#!/bin/sh
#
# Copyright (C) 2026, nanchuci <nanchuci023@gmail.com>
#
# /sbin/wifi 通过 `include /lib/wifi` 只 source *.sh，
# 因此这里保留一个极薄的 shell 包装，真正的探测逻辑在 mtwifi.uc。
#

append DRIVERS "mtwifi"

detect_mtwifi() {
	[ -f /etc/wireless/l1profile.dat ] || return 0
	[ -x /usr/bin/ucode ] || return 0

	ucode /lib/wifi/mtwifi.uc | uci -q batch
}
