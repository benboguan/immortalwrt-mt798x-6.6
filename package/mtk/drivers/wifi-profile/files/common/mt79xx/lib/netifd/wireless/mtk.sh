#!/bin/sh
#
# Copyright (c) 2013-2015 D-Team Technology Co.,Ltd. ShenZhen
# Copyright (c) 2005-2015, lintel <lintel.huang@gmail.com>
# Copyright (c) 2013, Hoowa <hoowa.sun@gmail.com>
# Copyright (c) 2015-2017, GuoGuo <gch981213@gmail.com>
# Copyright (c) 2020,2023, jjm2473 <jjm2473@gmail.com>
# Copyright (c) 2022-2025, nanchuci <nanchuci023@gmail.com>
#
# 	netifd config script for MT7615/MT7915/MT798X/MT799X DBDC mode.
#
# 	嘿，对着屏幕的哥们,为了表示对原作者辛苦工作的尊重，任何引用跟借用都不允许你抹去所有作者的信息,请保留这段话。
#
. /lib/netifd/netifd-wireless.sh
. /lib/functions/system.sh

init_wireless_driver "$@"

#Default configurations
L1_PROFILE="/etc/wireless/l1profile.dat"
MTWIFI_PROFILE_DIR="/etc/wireless/mediatek/"
MTWIFI_BAND_PROFILE_PATH=""
MTWIFI_PROFILE_PATH=""
MTWIFI_CMD_PATH=""
MTWIFI_CMD_OPATH=""
APCLI_IF=""
WIFI_OP_LOCK="/tmp/mt_wifi.lock"
MTWIFI_IFPREFIX=""
MTWIFI_DEF_BAND=""
MTWIFI_FORCE_HT=0
MTWIFI_WDS_MAX_BSSID=4
MTWIFI_DEF_MAX_BSSID=16
hostname=$(uci -q get system.@system[0].hostname)

# 预加载变量
[ -f "$L1_PROFILE" ] && {
	CHIP=$(awk -F= '/^INDEX0=/ {print $2}' "$L1_PROFILE")
	SKU=$(awk -F/ '/INDEX0_init_path=/ {print $NF; exit}' "$L1_PROFILE" | cut -d. -f2)
} || {
	echo "Error: Required l1_config file not found at $L1_PROFILE" >&2
	exit 1
}

mt_cmd() {
	[ -n "$MTWIFI_CMD_PATH" ] && echo "$@" >> "$MTWIFI_CMD_PATH"
}

drv_mtk_cleanup() {
	return
}

# 简化锁机制
mtk_try_lock() {
	local timeout=3  # 减少超时时间
	while [ $timeout -gt 0 ]; do
		if lock -n $WIFI_OP_LOCK; then
			return 0
		fi
		sleep 1
		timeout=$((timeout - 1))
	done
	echo "Warning: WiFi operation is locked, operation may be delayed"
	return 1
}

#读取device相关设置项并写入json
drv_mtk_init_device_config() {
	config_add_string path phy band hwmode htmode channel country twt
	config_add_boolean whnat mlr legacy_rates noscan vendor_vht vht_1024 doth dfs short_preamble txburst ldpc
	config_add_int txpower beacon_int mu_beamformer maxassoc
}

#读取iface相关设置项并写入json
drv_mtk_init_iface_config() {
	config_add_boolean disabled wmm hidden isolate mlo wds mwds wps_pushbutton
	config_add_string mode ifname encryption pin key key1 key2 key3 key4 password time_zone
	config_add_string 'ssid:string' macfilter bssid kicklow assocthres 'macaddr:macaddr' wdsphymode
	config_add_string nasid mobility_domain r1_key_holder auth_secret acct_secret own_ip_addr
	config_add_boolean ieee80211k rrm_neighbor_report bss_transition wnm_notify proxy_arp ieee80211r ft_over_ds ft_psk_generate_local
	config_add_int r0_key_lifetime reassociation_deadline wdsmode wpa_group_rekey frag rts dtim_period time_advertisement
	config_add_int 'auth_port:port' acct_port own_radius_port 'port:port' ocv
	config_add_int ieee80211w ieee80211w_max_timeout ieee80211w_retry_timeout
	config_add_array 'maclist:list(macaddr)' auth_server acct_server r0kh r1kh
	config_add_boolean mumimo_dl mumimo_ul ofdma_dl ofdma_ul amsdu autoba uapsd rsn_preauth disassoc_low_ack
}

get_wep_key_type() {
	case "${#1}" in
		10|26|32) echo 0 ;;
		*)        echo 1 ;;
	esac
}

mtk_ap_vif_pre_config() {
	local name="$1"

	json_select config
	json_get_vars disabled encryption auth_secret acct_secret auth_server auth_port acct_server \
		acct_port key key1 key2 key3 key4 wmm own_ip_addr own_radius_port macaddr wpa_group_rekey \
		bssid ssid mode wps_pushbutton pin isolate hidden disassoc_low_ack kicklow assocthres rsn_preauth \
		ieee80211k rrm_neighbor_report bss_transition time_advertisement time_zone wnm_notify proxy_arp ieee80211r \
		ieee80211w macfilter nasid mobility_domain r1_key_holder r0_key_lifetime reassociation_deadline r0kh r1kh \
		ft_over_ds ft_psk_generate_local frag rts dtim_period mumimo_dl mumimo_ul ofdma_dl ofdma_ul amsdu autoba \
		uapsd ocv mwds mlo ieee80211w_max_timeout ieee80211w_retry_timeout
	json_get_values maclist maclist
	json_select ..

	[[ "$disabled" = "1" ]] && return
	[ $ApBssidNum -gt $MTWIFI_DEF_MAX_BSSID ] && return 

	echo "Generating ap config for interface ra${MTWIFI_IFPREFIX}${ApBssidNum}"
	local ifname="ra${MTWIFI_IFPREFIX}${ApBssidNum}"

	# 计算配置索引（从MacAddress开始使用索引1）
	local config_index=$((ApBssidNum + 1))

	# 快速接口配置
	json_add_object data
	json_add_string ifname "$ifname"
	json_close_object

	#MAC过滤方式和自定义MAC地址相关设定 由于编号问题......扔在这了...... - 使用索引0
	ra_maclist="${maclist// /;};"
	case "$macfilter" in
		allow) echo "AccessPolicy${ApBssidNum}=1;AccessControlList${ApBssidNum}=${ra_maclist}" >> $MTWIFI_PROFILE_PATH ;;
		deny)  echo "AccessPolicy${ApBssidNum}=2;AccessControlList${ApBssidNum}=${ra_maclist}" >> $MTWIFI_PROFILE_PATH ;;
	esac

	# 批量配置生成
	{
		[ "$ApBssidNum" = "0" ] && echo "MacAddress=${macaddr}" || echo "MacAddress${config_index}=${macaddr}"
		[ "$mlo" = "1" ] && echo "MldAddr${config_index}=${macaddr}"
		echo "SSID${config_index}=${ssid}"
	} >> $MTWIFI_PROFILE_PATH

	Apmlo="${Apmlo}${mlo:-0};"

	# 快速加密配置
	case "$encryption" in
		wpa*|psk*|WPA*|sae*|*SAE*|owe*|*8021x*|*eap*|Mixed|mixed)
			local enc crypto
			case "$encryption" in
				Mixed|mixed|psk+psk2|psk-mixed*) enc=WPAPSKWPA2PSK ;;
				psk2*) enc=WPA2PSK ;;
				psk*) enc=WPAPSK ;;
				SAE*|psk3|sae) enc=WPA3PSK ;;
				psk2+psk3|psk3-mixed*|sae-mixed*) enc=WPA2PSKWPA3PSK ;;
				SAE*|psk3|sae-ext) enc=WPA3PSK-EXT ;;
				SAE*|psk3|sae_sae-ext) enc=WPA3PSKWPA3PSK-EXT ;;
				psk2+psk3|sae-ext-mixed*) enc=WPA2PSKWPA3PSKWPA3PSK-EXT ;;
				8021x*|eap|wpa) enc=WPA ;;
				8021x*|eap2|wpa2) enc=WPA2 ;;
				8021x*|eap+eap2|wpa-mixed) enc=WPA1WPA2 ;;
				8021x*|wpa3) enc=WPA3 ;;
				8021x*|wpa3-mixed*) enc=WPA3WPA2 ;;
				8021x*|eap192*|wpa3-192*) enc=WPA3-192 ;;
				OWE*|owe) enc=OWE ;;
			esac
			crypto="AES"
			case "$encryption" in
				*tkipaes*|*tkip+ccmp*|*tkip+aes*|*aes+tkip*|*ccmp+tkip*) crypto="TKIPAES" ;;
				*gcmp256*) crypto="GCMP256" ;;
				*ccmp256*) crypto="CCMP256" ;;
				*aes+gcmp256*|*ccmp128+gcmp256*) crypto="AES_GCMP256" ;;
				*gcmp*|*gcmp128*) crypto="GCMP128" ;;
				*aes*|*ccmp*|*ccmp128*) crypto="AES" ;;
				*tkip*) crypto="TKIP" ;;
			esac

			if [ "$encryption" = "wpa3-192" -o "$encryption" = "sae-ext" ]; then
				ApAuthMode="${ApAuthMode}${enc};"
				ApEncrypType="${ApEncrypType}GCMP256;"
			elif [ "$encryption" = "sae_sae-ext" -o "$encryption" = "sae-ext-mixed" ]; then
				ApAuthMode="${ApAuthMode}${enc};"
				ApEncrypType="${ApEncrypType}AES_GCMP256;"
			else
				ApAuthMode="${ApAuthMode}${enc};"
				ApEncrypType="${ApEncrypType}${crypto};"
			fi
			ApDefKId="${ApDefKId}2;"
			echo "WPAPSK${config_index}=${key}" >> $MTWIFI_PROFILE_PATH
			;;
		WEP|wep|wep-open|wep-shared)
			[ "$encryption" = "wep-shared" ] && ApAuthMode="${ApAuthMode}SHARED;" || ApAuthMode="${ApAuthMode}OPEN;"
			ApEncrypType="${ApEncrypType}WEP;"

			K1Tp=$(get_wep_key_type "$key1")
			K2Tp=$(get_wep_key_type "$key2")
			K3Tp=$(get_wep_key_type "$key3")
			K4Tp=$(get_wep_key_type "$key4")

			[ $K1Tp -eq 1 ] && key1=$(echo $key1 | cut -d ':' -f 2-)
			[ $K2Tp -eq 1 ] && key2=$(echo $key2 | cut -d ':' -f 2-)
			[ $K3Tp -eq 1 ] && key3=$(echo $key3 | cut -d ':' -f 2-)
			[ $K4Tp -eq 1 ] && key4=$(echo $key4 | cut -d ':' -f 2-)

			echo "Key1Str${config_index}=${key1}" >> $MTWIFI_PROFILE_PATH
			echo "Key2Str${config_index}=${key2}" >> $MTWIFI_PROFILE_PATH
			echo "Key3Str${config_index}=${key3}" >> $MTWIFI_PROFILE_PATH
			echo "Key4Str${config_index}=${key4}" >> $MTWIFI_PROFILE_PATH
			ApDefKId="${ApDefKId}${key};"
			;;
		none|open)
			ApAuthMode="${ApAuthMode}OPEN;"
			ApEncrypType="${ApEncrypType}NONE;"
			ApDefKId="${ApDefKId}1;"
			;;
	esac

	# 批量配置累加
	ApRekeyMethod="${ApRekeyMethod}$([ "$encryption" = "open" -o "$encryption" = "owe" ] && echo "DISABLE;" || echo "TIME;")"

	if [ "$encryption" = "wpa" -o "$encryption" = "wpa-mixed" -o "$encryption" = "wpa2" -o "$encryption" = "wpa3" \
		-o "$encryption" = "wpa3-mixed" -o "$encryption" = "wpa3-192" ]; then
		{
			echo "NasId${config_index}=${nasid}"
			echo "RADIUS_Key${config_index}=${auth_secret:-0}"
			echo "RADIUS_Acct_Key${config_index}=${acct_secret:-0}"
		} >> $MTWIFI_PROFILE_PATH
		ApRADIUSPort="${ApRADIUSPort}${auth_port:-1812};"
		ApRADIUSAcctServer="${ApRADIUSAcctServer}${acct_server:-0};"
		ApRADIUSAcctPort="${ApRADIUSAcctPort}${acct_port:-1813};"
		Apown_ip_addr="${Apown_ip_addr}${own_ip_addr};"
		Apown_radius_port="${Apown_radius_port}${own_radius_port};"
		ApPreAuth="${ApPreAuth}${rsn_preauth:-0};"
	else
		echo "FtR0khId${config_index}=${nasid}" >> $MTWIFI_PROFILE_PATH
	fi

	ApK1Tp="${ApK1Tp}${K1Tp:-0};"
	ApK2Tp="${ApK2Tp}${K2Tp:-0};"
	ApK3Tp="${ApK3Tp}${K3Tp:-0};"
	ApK4Tp="${ApK4Tp}${K4Tp:-0};"
	ApMWDS="${ApMWDS}${mwds:-0};"
	ApHideESSID="${ApHideESSID}${hidden:-0};"
	ApWmmCapable="${ApWmmCapable}${wmm:-1};"
	ApRADIUSServer="${ApRADIUSServer}${auth_server:-0};"
	ApNoForwarding="${ApNoForwarding}${isolate:-0};"
	ApRekeyInterval="${ApRekeyInterval}${wpa_group_rekey:-3600};"
	ApRRMEnable="${ApRRMEnable}${ieee80211k:-0};"
	ApRRMNeighbor="${ApRRMNeighbor}${rrm_neighbor_report:-0};"
	ApWNMEnable="${ApWNMEnable}${bss_transition:-0};"
	ApWNMNotifyEnable="${ApWNMNotifyEnable}${wnm_notify:-0};"
	ApTimeadvertisement="${ApTimeadvertisement}${time_advertisement:-0};"
	ApTimezone="${ApTimezone}${time_zone};"
	ApARP="${ApARP}${proxy_arp:-0};"
	ApFtSupport="${ApFtSupport}${ieee80211r:-0};"
	ApFtOtd="${ApFtOtd}${ft_over_ds:-0};"
	ApFtOnly="${ApFtOnly}${ft_psk_generate_local:-0};"
	ApFrag="${ApFrag}${frag:-2346};"
	ApRts="${ApRts}${rts:-2347};"
	ApDtim="${ApDtim}${dtim_period:-1};"
	Apmumimodl="${Apmumimodl}${mumimo_dl:-0};"
	Apmumimoul="${Apmumimoul}${mumimo_ul:-0};"
	Apofdmadl="${Apofdmadl}${ofdma_dl:-1};"
	Apofdmaul="${Apofdmaul}${ofdma_ul:-1};"
	Apamsdu="${Apamsdu}${amsdu:-1};"
	Apautoba="${Apautoba}${autoba:-1};"
	Apuapsd="${Apuapsd}${uapsd:-1};"
	
	{
		echo "FtMdId${config_index}=${mobility_domain:-4f57}"
		echo "FtR1khId${config_index}=${r1_key_holder:-00004f577274}" 
		echo "R0KeyLifeTime${config_index}=${r0_key_lifetime:-10000}"
		echo "AssocDeadLine${config_index}=${reassociation_deadline:-100}"
	} >> $MTWIFI_PROFILE_PATH

	mt_cmd "ip link set $ifname up"
	mt_cmd "echo 'Interface $ifname now up.'"

	# PMF配置
	if [ "$ieee80211w" = "1" ] || [ "$encryption" = "sae-mixed" ]; then
		ApPMFMFPC="${ApPMFMFPC}1;"
		ApPMFMFPR="${ApPMFMFPR}0;"
	elif [ "$ieee80211w" = "2" ] || [ "$encryption" = "sae" -o "$encryption" = "owe" -o "$encryption" = "sae_sae-ext" \
		-o "$encryption" = "sae-ext-mixed" -o "$encryption" = "wpa3-mixed" -o "$encryption" = "wpa3-192" ]; then
		ApPMFMFPC="${ApPMFMFPC}1;"
		ApPMFMFPR="${ApPMFMFPR}1;"
	else
		ApPMFMFPC="${ApPMFMFPC}0;"
		ApPMFMFPR="${ApPMFMFPR}0;"
	fi

	if [ "$ieee80211w" != "0" ]; then
		Apw_max_timeout="${Apw_max_timeout}${ieee80211w_max_timeout:-1000};"
		Apw_retry_timeout="${Apw_retry_timeout}${ieee80211w_retry_timeout:-200};"
		Apocv="${Apocv}${ocv:-0};"
	fi

	# WPS配置
	if [ "$wps_pushbutton" = "1" ] && [ "$encryption" != "none" ]; then
		mt_cmd echo "Enable WPS PIN for ${ifname}."
		ApWscConfMode="${ApWscConfMode}7;"
		ApWscConfStatus="${ApWscConfStatus}1;"
		pin="${pin:-}"
		pin_length=${#pin}
		if [ "$pin_length" -lt 4 ]; then
			ApWsc4digitPinCode="${ApWsc4digitPinCode}1;"
		else
			ApWsc4digitPinCode="${ApWsc4digitPinCode}0;"
		fi
		ApWscVendorPinCode="${ApWscVendorPinCode}${pin};"
	elif [ "$wps_pushbutton" = "2" ] && [ "$encryption" != "none" ]; then
		mt_cmd echo "Enable WPS PBC for ${ifname}."
		ApWscConfMode="${ApWscConfMode}7;"
		ApWscConfStatus="${ApWscConfStatus}2;"
	else
		mt_cmd echo "Disabled WPS for ${ifname}."
		ApWscConfMode="${ApWscConfMode}0;"
		ApWscConfStatus="${ApWscConfStatus}1;"
	fi

	mt_cmd echo "Other settings for ${ifname}."
	[ -n "$disassoc_low_ack" ] && [ "$disassoc_low_ack" != "0" ] && {
		mt_cmd "iwpriv $ifname set KickStaRssiLow=$kicklow"
		mt_cmd "iwpriv $ifname set AssocReqRssiThres=$assocthres"
	}

	# PMF(802.11W) should be disabled if you want your device to support both iPhone and Android STAs
	[ -n "$ieee80211r" ] && [ "$ieee80211r" != "0" ] && {
		mt_cmd "iwpriv $ifname set ftenable=1"
		mt_cmd "iwpriv $ifname set PMFMFPC=0"
		mt_cmd "iwpriv $ifname set PMFMFPR=0"
	}
	ApBssidNum=$((ApBssidNum + 1))
}

mtk_wds_vif_pre_config() {
	local name="$1"

	json_select config
	json_get_vars disabled encryption key key1 wds bssid wdsmode wdsphymode macaddr
	json_select ..

	[[ "$disabled" = "1" ]] && return
	[ $WDSBssidNum -gt $MTWIFI_WDS_MAX_BSSID ] && return

	echo "Generating WDS config for interface wds${MTWIFI_IFPREFIX}${WDSBssidNum}"
	local ifname="wds${MTWIFI_IFPREFIX}${WDSBssidNum}"

	json_add_object data
	json_add_string ifname "$ifname"
	json_close_object

	case "$encryption" in
		psk*|psk2*|psk3*|sae*|*SAE*)
			local enc crypto
			case "$encryption" in
				psk2*) enc=WPA2PSK ;;
				psk*) enc=WPAPSK ;;
				SAE*|psk3*|sae) enc=WPA3PSK ;;
			esac
			crypto="AES"
			case "$encryption" in
				*tkipaes*|*tkip+ccmp*|*tkip+aes*|*aes+tkip*|*ccmp+tkip*) crypto="TKIPAES" ;;
				*gcmp256*) crypto="GCMP256" ;;
				*ccmp256*) crypto="CCMP256" ;;
				*gcmp*|*gcmp128*) crypto="GCMP128" ;;
				*aes*|*ccmp*|*ccmp128*) crypto="AES" ;;
				*tkip*) crypto="TKIP" ;;
			esac
			WDSAuthMode="${WDSAuthMode}${enc};"
			WDSEncType="${WDSEncType}${crypto};"
			WDSDefKeyID="${WDSDefKeyID}2;"
			;;
		WEP|wep|wep-open|wep-shared)
			[ "$encryption" == "wep-shared" ] && WDSAuthMode="${WDSAuthMode}SHARED;" || WDSAuthMode="${WDSAuthMode}OPEN;"
			WDSEncType="${WDSEncType}WEP;"
			WDSK1Tp=$(get_wep_key_type "$key1")
			[ $WDSK1Tp -eq 1 ] && key1=$(echo $key1 | cut -d ':' -f 2-)
			WDSDefKeyID="${WDSDefKeyID}1;"
			;;
		none|open)
			WDSAuthMode="${WDSAuthMode}OPEN;"
			WDSEncType="${WDSEncType}NONE;"
			WDSDefKeyID="${WDSDefKeyID}1;"
			;;
	esac
	if [ "$encryption" == "wep-open" -o "$encryption" == "wep-shared" ]; then
		echo "Wds${WDSBssidNum}Key=${key1}" >> $MTWIFI_PROFILE_PATH #WDS Key
	else
		echo "Wds${WDSBssidNum}Key=${key}" >> $MTWIFI_PROFILE_PATH #WDS Key
	fi

	WWDSEnable="${WWDSEnable}$([ "$wdsmode" != "0" -o "$wds" == "1" ] && echo "1;" || echo "0;")"
	WDS_Enable="${WDS_Enable}${wdsmode:-0};"
	WDSPhyMode="${WDSPhyMode}${wdsphymode:-HE};"
	WDSList="${WDSList}$(echo $bssid | tr 'A-Z' 'a-z');"
	WWdsMac="${WWdsMac}${macaddr};"

	mt_cmd "ip link set $ifname up"
	mt_cmd echo "WDS interface $ifname now up."
	WDSBssidNum=$((WDSBssidNum + 1))
}

mtk_sta_vif_pre_config() {
	local name="$1"
	hwmode=${hwmode##11}

	json_select config
	json_get_vars disabled band encryption key key1 key2 key3 key4 ssid mode bssid \
		ieee80211w ieee80211w_max_timeout ieee80211w_retry_timeout macaddr mumimo_dl \
		mumimo_ul ofdma_dl ofdma_ul ocv mwds mlo
	json_select ..

	[ $stacount -gt 1 ] && return
	[[ "$disabled" = "1" ]] && return

	json_add_object data
	json_add_string ifname "$APCLI_IF"
	json_close_object

	case "$encryption" in
		psk*|sae*|*SAE*|owe*|Mixed|mixed)
			local enc crypto
			case "$encryption" in
				Mixed|mixed|psk+psk2|psk-mixed*) enc=WPAPSKWPA2PSK ;;
				psk2*) enc=WPA2PSK ;;
				psk*) enc=WPAPSK ;;
				SAE*|psk3*|sae) enc=WPA3PSK ;;
				SAE*|psk2+psk3|sae-mixed*) enc=WPA2PSKWPA3PSK ;;
				SAE*|psk3|sae-ext) enc=WPA3PSK-EXT ;;
				SAE*|psk3|sae_sae-ext) enc=WPA3PSKWPA3PSK-EXT ;;
				psk2+psk3|sae-ext-mixed*) enc=WPA2PSKWPA3PSKWPA3PSK-EXT ;;
				OWE*|owe) enc=OWE ;;
			esac
			crypto="AES"
			case "$encryption" in
				*tkipaes*|*tkip+ccmp*|*tkip+aes*|*aes+tkip*|*ccmp+tkip*) crypto="TKIPAES" ;;
				*gcmp256*) crypto="GCMP256" ;;
				*ccmp256*) crypto="CCMP256" ;;
				*aes+gcmp256*|*ccmp128+gcmp256*) crypto="AES_GCMP256" ;;
				*gcmp*|*gcmp128*) crypto="GCMP128" ;;
				*aes*|*ccmp*|*ccmp128*) crypto="AES" ;;
				*tkip*) crypto="TKIP" ;;
			esac
			if [ "$encryption" == "sae-ext" ]; then
				ApCliAuthMode="${enc}"
				ApCliEncrypType="GCMP256"
			elif [ "$encryption" == "sae_sae-ext" -o "$encryption" == "sae-ext-mixed" ]; then
				ApCliAuthMode="${enc}"
				ApCliEncrypType="AES_GCMP256"
			else
				ApCliAuthMode="${enc}"
				ApCliEncrypType="${crypto}"
			fi
			ApCliDefKId="2"
			[ -n "$key" ] && ApCliWPAPSK="${key}"
			;;
		WEP|wep|wep-open|wep-shared)
			[ "$encryption" = "wep-shared" ] && ApCliAuthMode="SHARED" || ApCliAuthMode="OPEN"
			ApCliEncrypType="WEP"
			K1Tp=$(get_wep_key_type "$key1")
			K2Tp=$(get_wep_key_type "$key2")
			K3Tp=$(get_wep_key_type "$key3")
			K4Tp=$(get_wep_key_type "$key4")

			[ $K1Tp -eq 1 ] && key1=$(echo $key1 | cut -d ':' -f 2-)
			[ $K2Tp -eq 1 ] && key2=$(echo $key2 | cut -d ':' -f 2-)
			[ $K3Tp -eq 1 ] && key3=$(echo $key3 | cut -d ':' -f 2-)
			[ $K4Tp -eq 1 ] && key4=$(echo $key4 | cut -d ':' -f 2-)
			ApCliDefKId="${key}"
			;;
		none|open)
			ApCliAuthMode="OPEN"
			ApCliEncrypType="NONE"
			ApCliDefKId="1"
			;;
	esac
	ApCliK1Tp="${K1Tp:-0}"
	ApCliK2Tp="${K2Tp:-0}"
	ApCliK3Tp="${K3Tp:-0}"
	ApCliK4Tp="${K4Tp:-0}"

	mt_cmd ip link set $APCLI_IF up
	mt_cmd echo "Interface $APCLI_IF now up."
	mt_cmd "iwpriv $APCLI_IF set ApCliEnable=1"
	mt_cmd "iwpriv $APCLI_IF set ApCliAutoConnect=3"
	mt_cmd "iwpriv $APCLI_IF set ApCliAuthMode=${ApCliAuthMode}"
	mt_cmd "iwpriv $APCLI_IF set ApCliEncrypType=${ApCliEncrypType}"
	if [[ "${ApCliEncrypType}" = "WEP" ]]; then
		mt_cmd iwpriv $APCLI_IF set ApCliDefaultKeyID=${ApCliDefKId}
		# mt_cmd iwpriv $APCLI_IF set ApCliKey1Type=1 # 0:hex, 1:ascii
		mt_cmd iwpriv $APCLI_IF set ApCliKey1Str=${key1##*:}
		# mt_cmd iwpriv $APCLI_IF set ApCliKey2Type=1
		mt_cmd iwpriv $APCLI_IF set ApCliKey2Str=${key2##*:}
		# mt_cmd iwpriv $APCLI_IF set ApCliKey3Type=1
		mt_cmd iwpriv $APCLI_IF set ApCliKey3Str=${key3##*:}
		# mt_cmd iwpriv $APCLI_IF set ApCliKey4Type=1
		mt_cmd iwpriv $APCLI_IF set ApCliKey4Str=${key4##*:}
	elif ! [[ "${ApCliEncrypType}" = "NONE" ]]; then
		mt_cmd iwpriv $APCLI_IF set ApCliWPAPSK=${key}
	fi

	[ -n "$bssid" ] && {
		mt_cmd "iwpriv $APCLI_IF set ApCliBssid=$(echo $bssid | tr 'A-Z' 'a-z')"
		MACRepeaterEn=1
	}
	mt_cmd "iwpriv $APCLI_IF set ApCliSsid=${ssid}"

	if [[ "$mlo" = "1" ]]; then
		ApcliMloDisable=0
		ApcliMldAddr=${macaddr}
	else
		ApcliMloDisable=1
	fi

	if [[ "$ieee80211w" = "1" ]] || [ "$encryption" == "sae-mixed" ]; then
		ApCliPMFMFPC="${ApCliPMFMFPC:-1}"
		ApCliPMFMFPR="${ApCliPMFMFPR:-0}"
	elif [[ "$ieee80211w" = "2" ]] || [ "$encryption" == "sae" -o "$encryption" == "owe" \
		-o "$encryption" == "sae_sae-ext" -o "$encryption" == "sae-ext-mixed" ]; then
		ApCliPMFMFPC="${ApCliPMFMFPC:-1}"
		ApCliPMFMFPR="${ApCliPMFMFPR:-1}"
	else
		ApCliPMFMFPC="${ApCliPMFMFPC:-0}"
		ApCliPMFMFPR="${ApCliPMFMFPR:-0}"
	fi

	if [ "$ieee80211w" != "0" ]; then
		ApCliSAQueryTimer="${ieee80211w_max_timeout:-1000}"
		ApCliSAQueryConfirmTimer="${ieee80211w_retry_timeout:-200}"
		ApCliOCVSupport="${ocv:-0}"
	fi

	if [ "$hwmode" == "a" -o "$band" == "5g" ]; then
		echo "ApCliMacAddress1=${macaddr}" >> $MTWIFI_PROFILE_PATH
	else
		echo "ApCliMacAddress=${macaddr}" >> $MTWIFI_PROFILE_PATH
	fi

	ApCliMWDS="${mwds:-0}"
	ApCliPpMuMimoDlEnable="${mumimo_dl:-0}"
	ApCliPpMuMimoUlEnable="${mumimo_ul:-0}"
	ApCliPpOfdmaDlEnable="${ofdma_dl:-1}"
	ApCliPpOfdmaUlEnable="${ofdma_ul:-1}"
	ApCliEnable="1"
	ApCliSsid="${ssid}"
	ApCliBssid="$(echo $bssid | tr 'A-Z' 'a-z')"
	stacount=$((stacount + 1))
}

mtk_vif_post_config() {
	local name="$1"
	json_select config
	json_get_vars disabled
	json_select ..

	json_select data
	json_get_vars ifname
	json_select ..

	[ "$disabled" = "1" -o -z "$ifname" ] && return
	logger -t "mtk" "wireless_add_vif $name $ifname"
	wireless_add_vif "$name" "$ifname"
}

mtk_vif_down() {
	local phy_name=${1}
	case "$phy_name" in
		rai0)
			for vif in ra0 ra1 ra2 ra3 ra4 ra5 ra6 ra7 ra8 ra9 ra10 \
				ra11 ra12 ra13 ra14 ra15 wds0 wds1 wds2 wds3 apcli0; do
				[ -d "/sys/class/net/$vif" ] && ip link set $vif down 2>/dev/null
			done
		;;
		ra0)
			for vif in rai0 rai1 rai2 rai3 rai4 rai5 rai6 rai7 rai8 rai9 rai10 \
				rai11 rai12 rai13 rai14 rai15 wdsi0 wdsi1 wdsi2 wdsi3 apclii0; do
				[ -d "/sys/class/net/$vif" ] && ip link set $vif down 2>/dev/null
			done
		;;
	esac
}

drv_mtk_teardown() {
	local phy_name=${1}
	case "$phy_name" in
		ra0)
			for vif in ra0 ra1 ra2 ra3 ra4 ra5 ra6 ra7 ra8 ra9 ra10 \
				ra11 ra12 ra13 ra14 ra15 wds0 wds1 wds2 wds3 apcli0; do
				[ -d "/sys/class/net/$vif" ] && ip link set $vif down 2>/dev/null
			done
		;;
		rai0)
			for vif in rai0 rai1 rai2 rai3 rai4 rai5 rai6 rai7 rai8 rai9 rai10 \
				rai11 rai12 rai13 rai14 rai15 wdsi0 wdsi1 wdsi2 wdsi3 apclii0; do
				[ -d "/sys/class/net/$vif" ] && ip link set $vif down 2>/dev/null
			done
		;;
	esac
}

#接口启动
drv_mtk_setup() {
	json_select config
	json_get_vars main_if phy_name mode hwmode htmode band #device所有配置项

	json_get_vars \
			channel:0 \
			country:CN \
			noscan:1 \
			ldpc:1 \
			txburst:1 \
			disabled:0 \
			doth:0 \
			whnat:1 \
			mlr:1 \
			legacy_rates:0 \
			short_preamble:1 \
			maxassoc:128 \
			beacon_int:100 \
			greenfield:0 \
			short_gi_20:1 \
			short_gi_40:1 \
			tx_stbc:1 \
			rx_stbc:3 \
			max_amsdu:1 \
			vendor_vht:1 \
			vht_1024:1 \
			dsss_cck_40:1
			
	json_get_vars \
			dfs:0 \
			rxldpc:1 \
			short_gi_80:1 \
			short_gi_160:1 \
			tx_stbc_2by1:1 \
			su_beamformer:1 \
			su_beamformee:1 \
			mu_beamformer:1 \
			mu_beamformee:1 \
			vht_txop_ps:1 \
			htc_vht:1 \
			beamformee_antennas:5 \
			beamformer_antennas:4 \
			rx_antenna_pattern:1 \
			tx_antenna_pattern:1 \
			vht_max_a_mpdu_len_exp:7 \
			vht_max_mpdu:11454 \
			rx_stbc:4 \
			vht_link_adapt:3 \
			vht160:2

	# 802.11ax
	json_get_vars \
			twt:0 \
			he_su_beamformer:1 \
			he_su_beamformee:1 \
			he_mu_beamformer:1 \
			he_twt_required:0 \
			he_twt_responder \
			he_spr_sr_control:3 \
			he_spr_psr_enabled:0 \
			he_spr_non_srg_obss_pd_max_offset:0 \
			he_bss_color \
			he_bss_color_enabled:1

	# 802.11be
	json_get_vars \
			pp_bitmap \
			pp_mode \
			twt:0 \
			eht_su_beamformer:1 \
			eht_su_beamformee:1 \
			eht_mu_beamformer:1

	json_select ..

	local phy_name=${1}
	wireless_set_data phy=${phy_name}
	case "$phy_name" in
		ra0)
			WirelessMode=22
			APCLI_IF="apcli0"
			MTWIFI_IFPREFIX=""
			MTWIFI_DEF_BAND="2g"
			if [ ${CHIP} = "MT7992" ]; then
				case ${SKU} in
					5040) HT_RxStream=2; HT_TxStream=2 ;;
					6500) HT_RxStream=3; HT_TxStream=3 ;;
					7200) HT_RxStream=4; HT_TxStream=4 ;;
				esac
				MTWIFI_BAND_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7992.${SKU}.1.dat"
				MTWIFI_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7992.${SKU}.b0.dat"
				MTWIFI_CMD_PATH="${MTWIFI_PROFILE_DIR}mt7992.${SKU}.cmd_b0.sh"
				MTWIFI_CMD_OPATH="${MTWIFI_PROFILE_DIR}mt7992.${SKU}.cmd_b1.sh"
			elif [ ${CHIP} = "MT7990" ]; then
				MTWIFI_BAND_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7990.1.dat"
				MTWIFI_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7990.b0.dat"
				MTWIFI_CMD_PATH="${MTWIFI_PROFILE_DIR}mt7990.cmd_b0.sh"
				MTWIFI_CMD_OPATH="${MTWIFI_PROFILE_DIR}mt7990.cmd_b1.sh"
			elif [ ${CHIP} = "MT7993" ]; then
				MTWIFI_BAND_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7993.1.dat"
				MTWIFI_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7993.b0.dat"
				MTWIFI_CMD_PATH="${MTWIFI_PROFILE_DIR}mt7993.cmd_b0.sh"
				MTWIFI_CMD_OPATH="${MTWIFI_PROFILE_DIR}mt7993.cmd_b1.sh"
			fi
		;;
		rai0)
			WirelessMode=23
			APCLI_IF="apclii0"
			MTWIFI_IFPREFIX="i"
			MTWIFI_DEF_BAND="5g"
			if [ ${CHIP} = "MT7992" ]; then
				case ${SKU} in
					5040) HT_RxStream=3; HT_TxStream=3 ;;
					6500|7200) HT_RxStream=4; HT_TxStream=4 ;;
				esac
				MTWIFI_BAND_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7992.${SKU}.1.dat"
				MTWIFI_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7992.${SKU}.b1.dat"
				MTWIFI_CMD_PATH="${MTWIFI_PROFILE_DIR}mt7992.${SKU}.cmd_b1.sh"
				MTWIFI_CMD_OPATH="${MTWIFI_PROFILE_DIR}mt7992.${SKU}.cmd_b0.sh"
			elif [ ${CHIP} = "MT7990" ]; then
				MTWIFI_BAND_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7990.1.dat"
				MTWIFI_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7990.b1.dat"
				MTWIFI_CMD_PATH="${MTWIFI_PROFILE_DIR}mt7990.cmd_b1.sh"
				MTWIFI_CMD_OPATH="${MTWIFI_PROFILE_DIR}mt7990.cmd_b0.sh"
			elif [ ${CHIP} = "MT7993" ]; then
				MTWIFI_BAND_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7993.1.dat"
				MTWIFI_PROFILE_PATH="${MTWIFI_PROFILE_DIR}mt7993.b1.dat"
				MTWIFI_CMD_PATH="${MTWIFI_PROFILE_DIR}mt7993.cmd_b1.sh"
				MTWIFI_CMD_OPATH="${MTWIFI_PROFILE_DIR}mt7993.cmd_b0.sh"
			fi
		;;
		*)
			echo "Unknown phy:$phy_name"
			return 1
		;;
	esac

#检查配置文件目录是否存在，否则创建目录
	[ ! -d $MTWIFI_PROFILE_DIR ] && mkdir $MTWIFI_PROFILE_DIR
	echo > $MTWIFI_CMD_PATH

	ITxBfEn=1
	HT_HTC=1
	case "$band" in
		5g)
			case "$htmode" in
				EHT160|EHT80|EHT40|EHT20) WirelessMode=23; HT_BAWinSize=1024 ;;
				HE160|HE80|HE40|HE20) WirelessMode=17; HT_BAWinSize=256 ;;
				VHT160|VHT80|VHT40|VHT20) WirelessMode=14; HT_BAWinSize=64 ;;
				HT40|HT20) WirelessMode=8; HT_BAWinSize=64 ;;
				*) WirelessMode=2; HT_BAWinSize=64 ;;
			esac
			;;
		2g)
			case "$htmode" in
				EHT40|EHT20) WirelessMode=22; HT_BAWinSize=1024 ;;
				HE40|HE20) WirelessMode=16; HT_BAWinSize=256 ;;
				HT40|HT20) WirelessMode=9; HT_BAWinSize=64 ;;
				*) WirelessMode=0; HT_BAWinSize=64 ;;
			esac
			;;
		*)
			echo "Error: Unknown wireless band '$band'. Using default: ${MTWIFI_DEF_BAND:-2g}"
			band=${MTWIFI_DEF_BAND:-2g}
			;;
	esac

#HT默认模式设定
	HT_BW=1  #允许HT40
	HT_CE=1  #允许HT20/40共存
	HT_DisallowTKIP=0 #是否允许TKIP加密
	HT_GI=1 #HT_SHORT_GI
	VHT_SGI=1 #VHT_SHORT_GI
	#HT_MIMOPSMode用于省电模式设置
	#HT_MIMOPSMode=3

#HT/VHT/HE默认模式设定
	VHT_BW=1 #允许VHT
	VHT_DisallowNonVHT=0 #是否禁止非VHT客户端连接，VHT80 only

	[ "$short_gi_20" == "0" -o "$short_gi_40" == "0" ] && HT_GI=0
	[ "$short_gi_80" == "0" -o "$short_gi_160" == "0" ] && VHT_SGI=0

	case "$htmode" in
		HT20|VHT20|HE20|EHT20) HT_BW=0; VHT_BW=0; EHT_ApBw=0 ;;
		HT40|VHT40|HE40|EHT40) HT_BW=1; VHT_BW=0; EHT_ApBw=1 ;;
		VHT80|HE80|EHT80) HT_BW=1; VHT_BW=1; EHT_ApBw=2 ;;
		VHT160|HE160|EHT160) HT_BW=1; VHT_BW=2; EHT_ApBw=3 ;;
		VHT80_80|HE80_80|EHT80_80) HT_BW=1; VHT_BW=3; EHT_ApBw=0 ;;
		EHT320) HT_BW=1; VHT_BW=2; EHT_ApBw=4 ;;
		*) echo "Unknown HT Mode." ;;
	esac

#仅HT20以外才需要设置的参数
	[ "$htmode" != "HT20" ] && {
#强制HT40/VHT80
		[[ "$noscan" = "1" ]] && HT_CE=0 && MTWIFI_FORCE_HT=1
#HT HTC
		HT_HTC=1
	}

#WHNAT无线硬件加速
	WHNAT=${whnat:-1}
	sed -i "s/WHNAT=.*/WHNAT=${WHNAT}/g" $MTWIFI_BAND_PROFILE_PATH

#TxPower功率设置
	[ "${txpower}" -lt "100" ] && PERCENTAGEenable=1 || PERCENTAGEenable=0

#BG保护功能设置
	# BGProtection=$([ "$legacy_rates" = "0" ] && echo 2 || echo 1)

#igmp_snooping功能设置
	igmp_snooping="$(uci -q get network.@device[0].igmp_snooping)"

#处理CountryRegion:指定信道
	[ "${country}" == "DB" ] && countryregion_a=7 && countryregion=5
	[ "${country}" == "AE" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "AL" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "DZ" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "AR" ] && countryregion_a=3 && countryregion=1
	[ "${country}" == "AM" ] && countryregion_a=2 && countryregion=1
	[ "${country}" == "AU" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "AT" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "AZ" ] && countryregion_a=2 && countryregion=1
	[ "${country}" == "BH" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "BY" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "BE" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "BZ" ] && countryregion_a=4 && countryregion=1
	[ "${country}" == "BO" ] && countryregion_a=4 && countryregion=1
	[ "${country}" == "BR" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "BN" ] && countryregion_a=4 && countryregion=1
	[ "${country}" == "BG" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "CA" ] && countryregion_a=0 && countryregion=0
	[ "${country}" == "CL" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "CN" ] && countryregion_a=0 && countryregion=1 && RDRegion=SRRC
	[ "${country}" == "CO" ] && countryregion_a=0 && countryregion=0
	[ "${country}" == "CR" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "HR" ] && countryregion_a=2 && countryregion=1
	[ "${country}" == "CY" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "CZ" ] && countryregion_a=2 && countryregion=1
	[ "${country}" == "DK" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "DO" ] && countryregion_a=0 && countryregion=0
	[ "${country}" == "EC" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "EG" ] && countryregion_a=2 && countryregion=1
	[ "${country}" == "SV" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "EE" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "FI" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "FR" ] && countryregion_a=2 && countryregion=1
	[ "${country}" == "GE" ] && countryregion_a=2 && countryregion=1
	[ "${country}" == "DE" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "GR" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "GT" ] && countryregion_a=0 && countryregion=0
	[ "${country}" == "HN" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "HK" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "HU" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "IS" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "IN" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "ID" ] && countryregion_a=4 && countryregion=1
	[ "${country}" == "IR" ] && countryregion_a=4 && countryregion=1
	[ "${country}" == "IE" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "IL" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "IT" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "JP" ] && countryregion_a=9 && countryregion=1 && RDRegion=JAP
	[ "${country}" == "JO" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "KZ" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "KP" ] && countryregion_a=5 && countryregion=1
	[ "${country}" == "KR" ] && countryregion_a=5 && countryregion=1 && RDRegion=KR
	[ "${country}" == "KW" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "LV" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "LB" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "LI" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "LT" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "LU" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "MO" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "MK" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "MY" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "MX" ] && countryregion_a=0 && countryregion=0
	[ "${country}" == "MC" ] && countryregion_a=2 && countryregion=1
	[ "${country}" == "MA" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "NL" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "NZ" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "NO" ] && countryregion_a=0 && countryregion=0
	[ "${country}" == "OM" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "PK" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "PA" ] && countryregion_a=0 && countryregion=0
	[ "${country}" == "PE" ] && countryregion_a=4 && countryregion=1
	[ "${country}" == "PH" ] && countryregion_a=4 && countryregion=1
	[ "${country}" == "PL" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "PT" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "PR" ] && countryregion_a=0 && countryregion=0
	[ "${country}" == "QA" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "RO" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "RU" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "SA" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "SG" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "SK" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "SI" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "ZA" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "ES" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "SE" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "CH" ] && countryregion_a=1 && countryregion=1
	[ "${country}" == "SY" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "TW" ] && countryregion_a=3 && countryregion=0
	[ "${country}" == "TH" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "TT" ] && countryregion_a=2 && countryregion=1
	[ "${country}" == "TN" ] && countryregion_a=2 && countryregion=1
	[ "${country}" == "TR" ] && countryregion_a=2 && countryregion=1
	[ "${country}" == "UA" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "AE" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "GB" ] && countryregion_a=1 && countryregion=1
	# [ "${country}" == "US" ] && countryregion_a=26 && countryregion=1 && RDRegion=FCC
	[ "${country}" == "UY" ] && countryregion_a=5 && countryregion=1
	[ "${country}" == "UZ" ] && countryregion_a=1 && countryregion=0
	[ "${country}" == "VE" ] && countryregion_a=5 && countryregion=1
	[ "${country}" == "VN" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "YE" ] && countryregion_a=0 && countryregion=1
	[ "${country}" == "ZW" ] && countryregion_a=0 && countryregion=1
	# [ "${country}" == "00" ] && countryregion_a=26 && countryregion=5 && RDRegion=CE

#其它相关
	case "$band" in
		5g)
			EXTCHA=1
			case "$channel" in
				40|48|56|64|104|112|120|128|136|144|153|161|169|177) EXTCHA=0;;
			esac
			[ "${channel}" == "auto" -o "${channel}" == "0" ] && {
				AutoChannelSelect=3
				channel=0
			}
			[ "${country}" == "US" ] && {
				countryregion_a=26 && RDRegion=FCC
				ACSSKIP="100;104;108;112;116;120;124;128;132;136;140;144;169;173;177"
			}
			[ "${country}" == "00" ] && {
				countryregion_a=26 && RDRegion=CE
				ACSSKIP="100;104;108;112;116;120;124;128;132;136;140;144;169;173;177"
			}
			PPEnable=1
			vht_1024=${vht_1024:-1}
			HT_MpduDensity=3
			# ACSSKIP="100;104;108;112;116;120;124;128;132;136;140;144;169;173;177"
		;;
		2g)
			EXTCHA=$((channel < 7 ? 1 : 0))
			[ "${channel}" == "auto" -o "${channel}" == "0" ] && {
				AutoChannelSelect=3
				channel=0
				EXTCHA=1
			}
			[ "${country}" == "US" ] && {
				countryregion=1 && RDRegion=FCC
				ACSSKIP="14"
			}
			[ "${country}" == "00" ] && {
				countryregion=5 && RDRegion=CE
				ACSSKIP="14"
			}
			PPEnable=0
			vht_1024=
			HT_MpduDensity=4
			# ACSSKIP="14"
		;;
	esac

#设备配置文件生成
	cat > $MTWIFI_PROFILE_PATH <<EOF
#The word of "Default" must not be removed
Default
AckPolicy=0;0;0;0
APACM=0;0;0;0
APAifsn=3;7;1;1
ApCliPMFSHA256=0
APCwmax=6;10;4;3
APCwmin=4;4;3;2
ApCliMuOfdmaDlEnable=1
ApCliMuOfdmaUlEnable=1
ApCliMuMimoDlEnable=0
ApCliMuMimoUlEnable=0
APTxop=0;0;94;47
AutoChannelSelect=${AutoChannelSelect:-0}
AutoChannelSkipList=${ACSSKIP}
AutoProvisionEn=0
BandSteering=${bandsteering:-0}
BasicRate=15
BcnProt=0
BeaconPeriod=${beacon_int:-100}
BFBACKOFFenable=0
BgndScanSkipCh=
BGProtection=${legacy_rates:-0}
BndStrgBssIdx=
BSSACM=0;0;0;0
BSSAifsn=3;7;2;2
BSSCwmax=10;10;4;3
BSSCwmin=4;4;3;2
BssidNum=4
WdsNum=0
BSSTxop=0;0;94;47
BW_Enable=0
BW_Guarantee_Rate=
BW_Maximum_Rate=
BW_Priority=
BW_Root=0
CalCacheApply=0
CarrierDetect=0
Channel=${channel:-0}
ChannelGrp=0:0:0:0
CountryCode=${country:-CN}
CountryRegion=${countryregion:-1}
CountryRegionABand=${countryregion_a:-0}
CP_SUPPORT=2
CSPeriod=6
DBDC_MODE=0
WirelessMode=${WirelessMode}
ApCliWirelessMode=${WirelessMode}
DebugFlags=0
DfsCalibration=0
DfsEnable=${dfs:-0}
DfsFalseAlarmPrevent=1
DfsZeroWait=0
DfsZeroWaitCacTime=255
Band4DfsEnable=0
DfsDedicatedZeroWait=0
DfsZeroWaitDefault=0
DfsNopExpireSetChPolicy=0
DisableOLBC=0
DppEnable=0
DLSCapable=0
DscpPriMapBss=
DscpPriMapEnable=1
E2pAccessMode=2
EAPifname=br-lan
EDCCAEnable=1
EthConvertMode=dongle
EtherTrafficBand=0
Ethifname=
ETxBfEnCond=1
FineAGC=0
FixedTxMode=
ForceRoamSupport=
FreqDelta=0
GreenAP=0
G_BAND_256QAM=${vendor_vht:-1}
AMSDU_NUM=5
HT_BADecline=0
HT_BAWinSize=${HT_BAWinSize:-1024}
HT_BSSCoexistence=${HT_CE:-1}
HT_BW=${HT_BW:-1}
HT_DisallowTKIP=${HT_DisallowTKIP:-0}
HT_EXTCHA=${EXTCHA:-1}
HT_GI=${HT_GI:-1}
HT_HTC=${HT_HTC:-1}
HT_LDPC=${ldpc:-1}
HT_LinkAdapt=0
HT_MCS=33
HT_MpduDensity=${HT_MpduDensity:-3}
HT_OpMode=${greenfield:-0}
HT_PROTECT=1
HT_RDG=0
HT_RxStream=${HT_RxStream:-4}
HT_STBC=${tx_stbc:-1}
HT_TxStream=${HT_TxStream:-4}
IcapMode=0
idle_timeout_interval=0
IEEE80211H=${doth:-0}
SeamlessCSA=0
IEEE8021X=0
IgmpSnEnable=${igmp_snooping:-0}
IsICAPFW=
ITxBfEn=${ITxBfEn:-0}
LinkTestSupport=0
MACRepeaterOuiMode=2
MeshAuthMode=
MeshAutoLink=0
MeshDefaultkey=0
MeshEncrypType=
MeshId=
MeshWEPKEY=
MeshWPAKEY=
MapEnable=0
MapAccept3Addr=1
MAP_Turnkey=0
MAP_Ext=0
MboSupport=1
MUTxRxEnable=${mu_beamformer:-1}
NoForwardingBTNBSSID=0
NoForwardingMBCast=0
NonTxBSSIndex=0
OCE_FD_FRAME=
OCE_FILS_CACHE=0
OCE_FILS_DhcpServer=
OCE_FILS_DhcpServerPort=
OCE_FILS_HLP=0
OCE_FILS_REALMS=
OCE_RNR_SUPPORT=
OCE_SUPPORT=0
PcieAspm=0
PERCENTAGEenable=${PERCENTAGEenable:-0}
PhyRateLimit=0
PktAggregate=1
PMFSHA256=0
PMKCachePeriod=10
PowerUpCckOfdm=0:0:0:0:0:0:0
PowerUpHT20=0:0:0:0:0:0:0
PowerUpHT40=0:0:0:0:0:0:0
PowerUpVHT160=0:0:0:0:0:0:0
PowerUpVHT20=0:0:0:0:0:0:0
PowerUpVHT40=0:0:0:0:0:0:0
PowerUpVHT80=0:0:0:0:0:0:0
PreAntSwitch=
PreAuthifname=br-lan
QoSMgmtCapa=0
RadioLinkSelection=0
RadioOn=1
RDRegion=${RDRegion}
RED_Enable=1
RegDomain=Global
ScsEnable=0
SCSEnable=1
session_timeout_interval=0
radius_acct_authentic=1
acct_interim_interval=0
acct_enable=1
ShortSlot=1
SkuTableIdx=0
SKUenable=0
SREnable=1
SRDPDEnable=0
SRMode=0
SRSDEnable=1
PPEnable=${PPEnable:-0}
SSID=
StationKeepAlive=0
StreamMode=0
StreamModeMac0=
StreamModeMac1=
StreamModeMac2=
StreamModeMac3=
TGnWifiTest=0
ThermalRecal=0
CCKTxStream=4
TWTInfoFrame=1
TxBurst=${txburst:-1}
TxPower=${txpower:-100}
TxPreamble=${short_preamble:-1}
VHT_BW=${VHT_BW:-2}
VHT_BW_SIGNAL=0
VHT_DisallowNonVHT=${VHT_DisallowNonVHT:-0}
VHT_LDPC=${ldpc:-1}
VHT_DisallowNonVHT=0
VHT_Sec80_Channel=0
VHT_SGI=${VHT_SGI:-1}
VHT_STBC=${tx_stbc:-1}
VLANID=0
VLANPriority=0
VLANTag=1
VOW_Airtime_Ctrl_En=
VOW_Airtime_Fairness_En=1
VOW_BW_Ctrl=0
VOW_Group_Backlog=
VOW_Group_DWRR_Max_Wait_Time=
VOW_Group_DWRR_Quantum=
VOW_Group_Max_Airtime_Bucket_Size=
VOW_Group_Max_Rate=
VOW_Group_Max_Rate_Bucket_Size=
VOW_Group_Max_Ratio=
VOW_Group_Max_Wait_Time=
VOW_Group_Min_Airtime_Bucket_Size=
VOW_Group_Min_Rate=
VOW_Group_Min_Rate_Bucket_Size=
VOW_Group_Min_Ratio=
VOW_Rate_Ctrl_En=
VOW_Refill_Period=
VOW_RX_En=1
VOW_Sta_BE_DWRR_Quantum=
VOW_Sta_BK_DWRR_Quantum=
VOW_Sta_DWRR_Max_Wait_Time=
VOW_Sta_VI_DWRR_Quantum=
VOW_Sta_VO_DWRR_Quantum=
VOW_WATF_Enable=
VOW_WATF_MAC_LV0=
VOW_WATF_MAC_LV1=
VOW_WATF_MAC_LV2=
VOW_WATF_MAC_LV3=
VOW_WATF_Q_LV0=
VOW_WATF_Q_LV1=
VOW_WATF_Q_LV2=
VOW_WATF_Q_LV3=
VOW_WMM_Search_Rule_Band0=
VOW_WMM_Search_Rule_Band1=
WapiAsCertPath=
WapiAsIpAddr=
WapiAsPort=
Wapiifname=
WapiPsk1=
WapiPsk10=
WapiPsk11=
WapiPsk12=
WapiPsk13=
WapiPsk14=
WapiPsk15=
WapiPsk16=
WapiPsk2=
WapiPsk3=
WapiPsk4=
WapiPsk5=
WapiPsk6=
WapiPsk7=
WapiPsk8=
WapiPsk9=
WapiPskType=
WapiUserCertPath=
WCNTest=0
WdsTxMcs=33
WHNAT=${whnat:-1}
WiFiTest=0
WscModelName=${hostname}
TxCmdMode=1
MapMode=0
MuOfdmaDlEnable=1
MuOfdmaUlEnable=1
MuMimoDlEnable=1
MuMimoUlEnable=1
EHT_ApBw=${EHT_ApBw:-3}
EHT_ApNsepPriAccess=1
EHT_ApOmCtrl=1
EHT_ApTxopSharing=0
EHT_ApRestrictedTwt=${twt:-0}
MlmeMultiQEnable=1
RROSupport=1
BSSColorValue=255
TxRate=0
SaeGroups=19
Dot11vMbssid=0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0
ApCliPweMethod=0
PweMethod=0
OcacEnable=0
EHT_ApcliT2lmNegoSupport=1
EHT_ApEmlsr_mr=1
EHT_ApT2lmNegoSupport=1
EHT_ApEmlsr_mr_OMN=0
EHT_ApEmlsr_mr_trans_to=0
DfsSlaveEn=0
TidMapping=255
MLREnable=${mlr:-1}
MLRVersion=2
Single_RNR=1
HeLdpc=${ldpc:-1}
TWTSupport=${twt:-0}
Vht1024QamSupport=${vht_1024}
FgiFltf=0
WscV2Support=1
EOF

#接口配置生成
#AP模式
#统一设置的内容:
	ApBssidNum=0
	ApAuthMode=""
	ApEncrypType=""
	ApRADIUSServer=""
	ApRADIUSPort=""
	ApRADIUSAcctServer=""
	ApRADIUSAcctPort=""
	Apown_ip_addr=""
	Apown_radius_port=""
	ApPreAuth=""
	ApRekeyMethod=""
	ApDefKId=""
	ApK1Tp=""
	ApK2Tp=""
	ApK3Tp=""
	ApK4Tp=""
	ApMWDS=""
	ApHideESSID=""
	ApWmmCapable=""
	ApRRMEnable=""
	ApRRMNeighbor=""
	ApFtSupport=""
	ApNoForwarding=""
	ApRekeyInterval=""
	ApPMFMFPC=""
	ApPMFMFPR=""
	ApWNMEnable=""
	ApTimeadvertisement=""
	ApTimezone=""
	ApWNMNotifyEnable=""
	ApARP=""
	ApFtOtd=""
	ApFtOnly=""
	ApFtRic=""
	ApFrag=""
	ApRts=""
	ApDtim=""
	Apmumimodl=""
	Apmumimoul=""
	Apofdmadl=""
	Apofdmaul=""
	Apamsdu=""
	Apautoba=""
	Apuapsd=""
	Apw_max_timeout=""
	Apw_retry_timeout=""
	Apocv=""
	Apmlo=""
	ApWscConfMode=""
	ApWscConfStatus=""
	ApWsc4digitPinCode=""
	ApWscVendorPinCode=""
	for_each_interface "ap" mtk_ap_vif_pre_config

#For DBDC profile merging......
	#BssidNum=${ApBssidNum:-1}
	#sed -i "s/BssidNum=.*/BssidNum=${BssidNum}/g" $MTWIFI_PROFILE_PATH
	{
		echo "ApMWDS=${ApMWDS%?}"
		echo "HideSSID=${ApHideESSID%?}"
		echo "WmmCapable=${ApWmmCapable%?}"
		echo "AuthMode=${ApAuthMode%?}"
		echo "EncrypType=${ApEncrypType%?}"
		echo "RADIUS_Server=${ApRADIUSServer%?}"
		echo "own_ip_addr=${Apown_ip_addr%?}"
		echo "own_radius_port=${Apown_radius_port%?}"
		echo "RADIUS_Port=${ApRADIUSPort%?}"
		echo "RADIUS_Acct_Server=${ApRADIUSAcctServer%?}"
		echo "RADIUS_Acct_Port=${ApRADIUSAcctPort%?}"
		echo "PreAuth=${ApPreAuth%?}"
		echo "DefaultKeyID=${ApDefKId%?}"
		echo "Key1Type=${ApK1Tp%?}"
		echo "Key2Type=${ApK2Tp%?}"
		echo "Key3Type=${ApK3Tp%?}"
		echo "Key4Type=${ApK4Tp%?}"
		echo "RekeyMethod=${ApRekeyMethod%?}"
		echo "WNMEnable=${ApWNMEnable%?}"
		echo "WNMNotifyEnable=${ApWNMNotifyEnable%?}"
		echo "Timeadvertisement=${ApTimeadvertisement%?}"
		echo "Timezone=${ApTimezone%?}"
		echo "ProxyARPEnable=${ApARP%?}"
		echo "RRMEnable=${ApRRMEnable%?}"
		echo "RRMNeighbor=${ApRRMNeighbor%?}"
		echo "FtSupport=${ApFtSupport%?}"
		echo "FtOtd=${ApFtOtd%?}"
		echo "FtOnly=${ApFtOnly%?}"
		echo "PpMuMimoDlEnable=${Apmumimodl%?}"
		echo "PpMuMimoUlEnable=${Apmumimoul%?}"
		echo "PpOfdmaDlEnable=${Apofdmadl%?}"
		echo "PpOfdmaUlEnable=${Apofdmaul%?}"
		echo "HT_AMSDU=${Apamsdu%?}"
		echo "HT_AutoBA=${Apautoba%?}"
		echo "APSDCapable=${Apuapsd%?}"
		echo "SAQueryTimer=${Apw_max_timeout%?}"
		echo "SAQueryConfirmTimer=${Apw_retry_timeout%?}"
		echo "OCVSupport=${Apocv%?}"
		echo "MldGroup=${Apmlo%?}"
		echo "PMFMFPC=${ApPMFMFPC%?}"
		echo "PMFMFPR=${ApPMFMFPR%?}"
		echo "NoForwarding=${ApNoForwarding%?}"
		echo "RekeyInterval=${ApRekeyInterval%?}"
		echo "FragThreshold=${ApFrag%?}"
		echo "RTSThreshold=${ApRts%?}"
		echo "DtimPeriod=${ApDtim%?}"
		echo "WscConfMode=${ApWscConfMode%?}"
		echo "WscConfStatus=${ApWscConfStatus%?}"
		echo "Wsc4digitPinCode=${ApWsc4digitPinCode%?}"
		echo "WscVendorPinCode=${ApWscVendorPinCode%?}"
	} >> $MTWIFI_PROFILE_PATH

#WDS接口
	WDSBssidNum=0
	WWDSEnable=""
	WWdsMac=""
	WDS_Enable=""
	WDSList=""
	WDSAuthMode=""
	WDSEncType=""
	WDSDefKeyID=""
	WDSPhyMode=""
	for_each_interface "wds" mtk_wds_vif_pre_config

#For WDS profile merging......
	WdsNum=${WDSBssidNum:-0}
	sed -i "s/WdsNum=.*/WdsNum=${WdsNum}/g" $MTWIFI_PROFILE_PATH
	{
		echo "WDSEnable=${WWDSEnable%?}"
		echo "WdsEnable=${WDS_Enable%?}"
		echo "WdsMac=${WWdsMac%?}"
		echo "WdsList=${WDSList%?}"
		echo "WdsAuthMode=${WDSAuthMode%?}"
		echo "WdsEncrypType=${WDSEncType%?}"
		echo "WdsDefaultKeyID=${WDSDefKeyID%?}"
		echo "WdsPhyMode=${WDSPhyMode%?}"
	} >> $MTWIFI_PROFILE_PATH

#STA模式
	stacount=0
	MACRepeaterEn=""
	ApCliAuthMode=""
	ApCliEncrypType=""
	ApCliSsid=""
	ApCliBssid=""
	ApCliDefKId=""
	ApCliWPAPSK=""
	ApCliKey1Str=""
	ApCliKey2Str=""
	ApCliKey3Str=""
	ApCliKey4Str=""
	ApCliK1Tp=""
	ApCliK2Tp=""
	ApCliK3Tp=""
	ApCliK4Tp=""
	ApcliMloDisable=""
	ApcliMldAddr=""
	ApCliPMFMFPC=""
	ApCliPMFMFPC=""
	ApCliMWDS=""
	ApCliPpMuMimoDlEnable=""
	ApCliPpMuMimoUlEnable=""
	ApCliPpOfdmaDlEnable=""
	ApCliPpOfdmaUlEnable=""
	ApCliSAQueryTimer=""
	ApCliSAQueryConfirmTimer=""
	ApCliOCVSupport=""
	for_each_interface "sta" mtk_sta_vif_pre_config

#For STA profile merging......
	{
		echo "ApCliEnable=${ApCliEnable:-0}"
		echo "MACRepeaterEn=${MACRepeaterEn:-0}"
		echo "ApCliSsid=${ApCliSsid}"
		echo "ApCliBssid=${ApCliBssid}"
		echo "ApCliMWDS=${ApCliMWDS:-0}"
		echo "ApCliAuthMode=${ApCliAuthMode:-OPEN}"
		echo "ApCliEncrypType=${ApCliEncrypType:-NONE}"
		echo "ApCliDefaultKeyID=${ApCliDefKId}"
		echo "ApCliWPAPSK=${ApCliWPAPSK}"
		echo "ApCliKey1Str=${ApCliKey1Str}"
		echo "ApCliKey2Str=${ApCliKey2Str}"
		echo "ApCliKey3Str=${ApCliKey3Str}"
		echo "ApCliKey4Str=${ApCliKey4Str}"
		echo "ApCliKey1Type=${ApCliK1Tp:-0}"
		echo "ApCliKey2Type=${ApCliK2Tp:-0}"
		echo "ApCliKey3Type=${ApCliK3Tp:-0}"
		echo "ApCliKey4Type=${ApCliK4Tp:-0}"
		echo "ApcliMloDisable=${ApcliMloDisable:-1}"
		echo "ApcliMldAddr=${ApcliMldAddr}"
		echo "ApCliPMFMFPC=${ApCliPMFMFPC:-0}"
		echo "ApCliPMFMFPR=${ApCliPMFMFPR:-0}"
		echo "ApCliPpMuMimoDlEnable=${ApCliMuMimoDlEnable:-0}"
		echo "ApCliPpMuMimoUlEnable=${ApCliMuMimoUlEnable:-0}"
		echo "ApCliPpOfdmaDlEnable=${ApCliMuOfdmaDlEnable:-1}"
		echo "ApCliPpOfdmaUlEnable=${ApCliMuOfdmaUlEnable:-1}"
		echo "ApCliSAQueryTimer=${ApCliSAQueryTimer:-1000}"
		echo "ApCliSAQueryConfirmTimer=${ApCliSAQueryConfirmTimer:-200}"
		echo "ApCliOCVSupport=${ApCliOCVSupport:-0}"
	} >> $MTWIFI_PROFILE_PATH

#接口上线
#加锁
	echo "MTK Interfaces Pending..."
	
	if mtk_try_lock; then
		echo "Reloading WiFi with optimized settings..."
		drv_mtk_teardown $phy_name
		mtk_vif_down $phy_name
#Start root device
		[ "$phy_name" == "rai0" ] && ip link set ra0 up
#restore interfaces
		if [[ "$phy_name" = "ra0" ]]; then
			[ -f "$MTWIFI_CMD_OPATH" ] && sh $MTWIFI_CMD_OPATH
			[ -f "$MTWIFI_CMD_PATH" ] && sh $MTWIFI_CMD_PATH
		else
			[ -f "$MTWIFI_CMD_PATH" ] && sh $MTWIFI_CMD_PATH
			[ -f "$MTWIFI_CMD_OPATH" ] && sh $MTWIFI_CMD_OPATH
		fi
	else
		echo "Wait other process reload wifi"
		lock $WIFI_OP_LOCK
	fi

#AP模式
	for_each_interface "ap" mtk_vif_post_config
#WDS接口
	for_each_interface "wds" mtk_vif_post_config
#STA模式
	for_each_interface "sta" mtk_vif_post_config

#重启HWNAT - 只在必要时重启
	[ -d /sys/module/mtkhnat ] && {
		# 检查whnat是否改变
		local old_whnat=$(grep "WHNAT=" $MTWIFI_BAND_PROFILE_PATH 2>/dev/null | head -1 | cut -d= -f2)
		if [ "$old_whnat" != "$whnat" ]; then
			echo "WHNAT changed, restarting turboacc"
			/etc/init.d/turboacc restart
		else
			echo "WHNAT unchanged, skipping turboacc restart"
		fi
	}

#设置无线上线
	wireless_set_up

#解锁
	lock -u $WIFI_OP_LOCK
	echo "WiFi reload completed successfully"
}

add_driver mtk
