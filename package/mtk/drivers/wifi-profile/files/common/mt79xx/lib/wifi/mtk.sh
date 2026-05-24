#!/bin/sh
#
# Copyright (c) 2014 OpenWrt
# Copyright (c) 2013-2015 D-Team Technology Co.,Ltd. ShenZhen
# Copyright (c) 2005-2015, lintel <lintel.huang@gmail.com>
# Copyright (c) 2013, Hoowa <hoowa.sun@gmail.com>
# Copyright (c) 2015-2017, GuoGuo <gch981213@gmail.com>
# Copyright (c) 2022-2025, nanchuci <nanchuci023@gmail.com>
#
# 	Detect script for MT7615/MT7915/MT798X/MT799X DBDC mode
#
# 	嘿，对着屏幕的哥们,为了表示对原作者辛苦工作的尊重，任何引用跟借用都不允许你抹去所有作者的信息,请保留这段话。
#

append DRIVERS "mtk"

. /lib/functions.sh
. /lib/functions/system.sh

board=$(board_name)

mtk_get_first_if_mac() {
	local wlan_mac="" factory_part mac_offset=4
	
	case $board in
	*)
		factory_part=$(find_mtd_part factory)
		[ -z "$factory_part" ] && factory_part=$(find_mtd_part Factory)
		
		[ -n "$factory_part" ] && {
			wlan_mac=$(dd bs=1 skip=$mac_offset count=6 if=$factory_part 2>/dev/null | \
				hexdump -v -e '/1 "%02x"' 2>/dev/null | \
				sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/')
			
			[ "$wlan_mac" = "ff:ff:ff:ff:ff:ff" -o "$wlan_mac" = "00:00:00:00:00:00" ] && wlan_mac=""
		}
		;;
	esac

	echo "$wlan_mac"
}

is_11be_dbdc_dev() {
	[ -f "/etc/wireless/l1profile.dat" ] || return 1
	grep -q "INDEX0.*MT799[023]" /etc/wireless/l1profile.dat
}

generate_mac_suffix() {
	local base_mac="$1"
	echo "$base_mac" | awk -F ":" '{print $5$6}' | tr '[:lower:]' '[:upper:]'
}

detect_mtk() {
	local base_mac vendor_vht vht_1024 hostname phyname mac_suffix
	
	is_11be_dbdc_dev || return 0

	[ -d /sys/module/mt_wifi ] || return 0

	config_load wireless
	hostname=$(uci -q get system.@system[-1].hostname 2>/dev/null)

	base_mac=$(mtk_get_first_if_mac)
	[ -z "$base_mac" ] && base_mac=$(cat /sys/class/net/eth0/address 2>/dev/null)
	[ -z "$base_mac" ] && return 0
	mac_suffix=$(generate_mac_suffix "$base_mac")

	for phyname in ra0 rai0; do
		config_get type "$phyname" type
		[ "$type" = "mtk" ] && continue

		case $phyname in
			ra0)
				band="2g"
				hwmode="11g"
				noscan="1"
				vendor_vht="1"
				htmode="EHT40"
				[ -z "$hostname" ] && {
					ssid="OpenWRT-2.4G-${mac_suffix}"
				} || {
					ssid="$hostname-2.4G"
				}
				;;
			rai0)
				band="5g"
				hwmode="11a"
				noscan="1"
				vendor_vht="1"
				vht_1024="1"
				htmode="EHT160"
				[ -z "$hostname" ] && {
					ssid="OpenWRT-5G-${mac_suffix}"
				} || {
					ssid="$hostname-5G"
				}
				;;
			*) continue ;;
		esac

		uci -q batch <<-EOF
			set wireless.${phyname}=wifi-device
			set wireless.${phyname}.type=mtk
			set wireless.${phyname}.hwmode=$hwmode
			set wireless.${phyname}.band=$band
			set wireless.${phyname}.channel=auto
			set wireless.${phyname}.country=CN
			set wireless.${phyname}.txburst=1
			set wireless.${phyname}.txpower=100
			set wireless.${phyname}.htmode=$htmode
			set wireless.${phyname}.noscan=${noscan:-0}
			set wireless.${phyname}.mu_beamformer=1
			set wireless.${phyname}.vendor_vht=${vendor_vht}
			set wireless.${phyname}.vht_1024=${vht_1024:-0}
			set wireless.${phyname}.serialize=1

			set wireless.default_${phyname}=wifi-iface
			set wireless.default_${phyname}.device=${phyname}
			set wireless.default_${phyname}.network=lan
			set wireless.default_${phyname}.mode=ap
			set wireless.default_${phyname}.ieee80211k=0
			set wireless.default_${phyname}.ieee80211v=0
			set wireless.default_${phyname}.ieee80211r=0
			set wireless.default_${phyname}.ieee80211w=0
			set wireless.default_${phyname}.ssid=${ssid}
			set wireless.default_${phyname}.encryption=none
			set wireless.default_${phyname}.disassoc_low_ack=0
			set wireless.default_${phyname}.disabled=0
EOF
	done

	uci -q commit wireless

	return 0
}
