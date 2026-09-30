#!/bin/sh
#
# Copyright (c) 2023, hanwckf <hanwckf@vip.qq.com>
# Copyright (c) 2026, nanchuci <nanchuci023@gmail.com>
#

. /lib/netifd/netifd-wireless.sh
. /lib/netifd/hostapd.sh
. /lib/functions.sh
. /lib/functions/system.sh

init_wireless_driver "$@"

LOCK_FILE="/tmp/mtwifi.lock"

MTWIFI_MAX_AP_IDX=15
MTWIFI_MAX_APCLI_IDX=0
MTWIFI_CFG_IFNAME_KEY="mtwifi_ifname"

WPA_CTRL_DIR="/var/run/wpa_supplicant"
WPA_CLI="/usr/sbin/wpa_cli"
SCAN_ACTION_SCRIPT="/lib/wifi/supplicant_scan_action.sh"

drv_mtwifi_init_device_config() {
	hostapd_common_add_device_config

	config_add_int txpower beacon_int cell_density obss_interval
	config_add_int min_tx_power num_global_macaddr
	config_add_int beamformer_antennas beamformee_antennas
	config_add_int vht_max_a_mpdu_len_exp vht_max_mpdu vht_link_adapt vht160
	config_add_int rx_stbc tx_stbc he_bss_color he_spr_non_srg_obss_pd_max_offset

	config_add_boolean mu_beamformer dbdc_main whnat legacy_rates noscan
	config_add_boolean vendor_vht vht_1024 doth dfs zw_dfs short_preamble tx_burst ldpc
	config_add_boolean ht_coex acs_exclude_dfs background_radar
	config_add_boolean rxldpc short_gi_80 short_gi_160 tx_stbc_2by1
	config_add_boolean su_beamformer su_beamformee mu_beamformee
	config_add_boolean he_su_beamformer he_su_beamformee he_mu_beamformer
	config_add_boolean vht_txop_ps htc_vht rx_antenna_pattern tx_antenna_pattern
	config_add_boolean he_spr_sr_control he_spr_psr_enabled he_bss_color_enabled he_twt_required
	config_add_boolean greenfield short_gi_20 short_gi_40 max_amsdu dsss_cck_40

	config_add_string distance country twt path phy
	config_add_string 'macaddr:macaddr'

	config_add_array channels scan_list ht_capab
}

drv_mtwifi_init_iface_config() {
	hostapd_common_add_bss_config

	config_add_string 'ssid:string' macfilter bssid kicklow assocthres 'macaddr:macaddr' pin nasid mobility_domain
	config_add_string r1_key_holder auth_secret acct_secret ownip multi_ap
	config_add_string wds_bridge ifname mldgroup

	config_add_boolean mumimo_dl mumimo_ul ofdma_dl ofdma_ul amsdu autoba uapsd rsn_preauth disassoc_low_ack
	config_add_boolean mlo mwds wmm hidden isolate ieee80211k rrm_neighbor_report bss_transition wnm_notify wds
	config_add_boolean proxy_arp ieee80211r ft_over_ds hairpin
	config_add_boolean powersave enable

	config_add_int wpa_group_rekey frag rts dtim_period ocv r0_key_lifetime reassociation_deadline
	config_add_int 'auth_port:port' acct_port own_radius_port wps_pushbutton
	config_add_int ieee80211w ieee80211w_max_timeout ieee80211w_retry_timeout
	config_add_int maxassoc start_disabled

	config_add_array 'maclist:list(macaddr)' auth_server acct_server r0kh r1kh
}

drv_mtwifi_cleanup() {
	hostapd_common_cleanup
}

mtwifi_vif_ap_config() {
	local name="$1"
	local ifname=""
	local disabled=""

	json_select config
	json_get_var disabled disabled
	json_select ..

	[ "$disabled" = "1" ] && return

	json_get_var ifname $MTWIFI_CFG_IFNAME_KEY

	if [ -n "$ifname" ]; then
		logger -t "netifd-mtwifi" "add $ifname to vifidx $name"
		wireless_add_vif "$name" "$ifname"
	fi
}

mtwifi_vif_sta_config() {
	local name="$1"
	local ifname=""
	local disabled=""

	json_select config
	json_get_var disabled disabled
	json_select ..

	[ "$disabled" = "1" ] && return

	json_get_var ifname $MTWIFI_CFG_IFNAME_KEY

	if [ -n "$ifname" ]; then
		logger -t "netifd-mtwifi" "add $ifname to vifidx $name"
		wireless_add_vif "$name" "$ifname"
	fi
}

mtwifi_vif_ap_set_data() {
	local ifname=""

	if [ $AP_IDX -le $MTWIFI_MAX_AP_IDX ]; then
		ifname="${MTWIFI_AP_IF_PREFIX}${AP_IDX}"
		AP_IDX=$((AP_IDX+1))
	fi

	json_add_string "$MTWIFI_CFG_IFNAME_KEY" "$ifname"
}

mtwifi_vif_sta_set_data() {
	local ifname=""

	if [ $APCLI_IDX -le $MTWIFI_MAX_APCLI_IDX ]; then
		ifname="${MTWIFI_APCLI_IF_PREFIX}${APCLI_IDX}"
		APCLI_IDX=$((APCLI_IDX+1))
	fi

	json_add_string "$MTWIFI_CFG_IFNAME_KEY" "$ifname"
}

#
# ---- 判断接口类型 ----
#

mtwifi_check_ap() {
	has_ap=1
}

mtwifi_check_sta() {
	has_sta=1
}

#
# ---- 从 mac80211.sh 拷过来的 hostapd 配置生成函数 ----
#

mac80211_add_capabilities() {
	local __var="$1"; shift
	local __mask="$1"; shift
	local __out= oifs

	oifs="$IFS"
	IFS=:
	for capab in "$@"; do
		set -- $capab

		[ "$(($4))" -gt 0 ] || continue
		[ "$(($__mask & $2))" -eq "$((${3:-$2}))" ] || continue
		__out="$__out[$1]"
	done
	IFS="$oifs"

	export -n -- "$__var=$__out"
}

mac80211_add_he_capabilities() {
	local __out= oifs

	oifs="$IFS"
	IFS=:
	for capab in "$@"; do
		set -- $capab
		[ "$(($4))" -gt 0 ] || continue
		[ -n "$2" ] || { eval "$1=0"; continue; }
		[ "$(((0x$2) & $3))" -gt 0 ] || {
			eval "$1=0"
			continue
		}
		append base_cfg "$1=1" "$N"
	done
	IFS="$oifs"
}

mac80211_hostapd_setup_base() {
	local phy="$1"

	json_select config

	[ "$auto_channel" -gt 0 ] && json_get_vars acs_exclude_dfs
	[ -n "$acs_exclude_dfs" ] && [ "$acs_exclude_dfs" -gt 0 ] &&
		append base_cfg "acs_exclude_dfs=1" "$N"

	json_get_vars noscan ht_coex min_tx_power:0 tx_burst obss_interval vendor_vht vht_1024
	json_get_values ht_capab_list ht_capab
	json_get_values channel_list channels

	[ "$auto_channel" = 0 ] && [ -z "$channel_list" ] && \
		channel_list="$channel"

	[ "$min_tx_power" -gt 0 ] && append base_cfg "min_tx_power=$min_tx_power" "$N"

	set_default noscan 0

	[ "$noscan" -gt 0 ] && hostapd_noscan=1
	[ "$tx_burst" = 0 ] && tx_burst=

	chan_ofs=0
	[ "$band" = "6g" ] && chan_ofs=1

	if [ "$band" != "6g" ]; then
		ieee80211n=1
		ht_capab=
		case "$htmode" in
			HT*) append base_cfg "require_ht=1" "$N" ;;
			VHT20|HT20|HE20|EHT20) ;;
			HT40*|VHT40|VHT80|VHT160|HE40*|HE80|HE160|EHT40*|EHT80|EHT160)
				case "$hwmode" in
					a)
						case "$(( (($channel / 4) + $chan_ofs) % 2 ))" in
							1) ht_capab="[HT40+]";;
							0) ht_capab="[HT40-]";;
						esac
						case "$htmode" in
							HT40-|HE40-|EHT40-)
								if [ "$auto_channel" -gt 0 ]; then
									ht_capab="[HT40-]"
								fi
								;;
						esac
						;;
					*)
						case "$htmode" in
							HT40+|HE40+|EHT40+)
								if [ "$channel" -gt 9 ]; then
									echo "Could not set the center freq with this HT mode setting"
									return 1
								else
									ht_capab="[HT40+]"
								fi
								;;
							HT40-|HE40-|EHT40-)
								if [ "$channel" -lt 5 -a "$auto_channel" -eq 0 ]; then
									echo "Could not set the center freq with this HT mode setting"
									return 1
								else
									ht_capab="[HT40-]"
								fi
								;;
							*)
								if [ "$channel" -lt 7 -o "$auto_channel" -gt 0 ]; then
									ht_capab="[HT40+]"
								else
									ht_capab="[HT40-]"
								fi
								;;
						esac
						;;
				esac
				[ "$auto_channel" -gt 0 ] && ht_capab="[HT40+]"
				;;
			*) ieee80211n= ;;
		esac

		[ -n "$ieee80211n" ] && {
			append base_cfg "ieee80211n=1" "$N"

			set_default ht_coex 0
			append base_cfg "ht_coex=$ht_coex" "$N"

			json_get_vars \
				ldpc:1 \
				greenfield:0 \
				short_gi_20:1 \
				short_gi_40:1 \
				tx_stbc:1 \
				rx_stbc:3 \
				max_amsdu:1 \
				dsss_cck_40:1 \
				intolerant_40:1

			[ "$ht_coex" -eq 1 ] && {
				set_default obss_interval 300
				append base_cfg "obss_interval=$obss_interval" "$N"
			}

			ht_cap_mask=0
			for cap in $(iw phy "$phy" info | grep -E '^\s*Capabilities:' | cut -d: -f2); do
				ht_cap_mask="$(($ht_cap_mask | $cap))"
			done

			cap_rx_stbc=$((($ht_cap_mask >> 8) & 3))
			[ "$rx_stbc" -lt "$cap_rx_stbc" ] && cap_rx_stbc="$rx_stbc"
			ht_cap_mask="$(( ($ht_cap_mask & ~(0x300)) | ($cap_rx_stbc << 8) ))"

			mac80211_add_capabilities ht_capab_flags $ht_cap_mask \
				LDPC:0x1::$ldpc \
				GF:0x10::$greenfield \
				SHORT-GI-20:0x20::$short_gi_20 \
				SHORT-GI-40:0x40::$short_gi_40 \
				TX-STBC:0x80::$tx_stbc \
				RX-STBC1:0x300:0x100:1 \
				RX-STBC12:0x300:0x200:1 \
				RX-STBC123:0x300:0x300:1 \
				MAX-AMSDU-7935:0x800::$max_amsdu \
				DSSS_CCK-40:0x1000::$dsss_cck_40 \
				40-INTOLERANT:0x4000::$intolerant_40

			ht_capab="$ht_capab$ht_capab_flags"
			[ -n "$ht_capab" ] && append base_cfg "ht_capab=$ht_capab" "$N"
		}
	fi

	# 802.11ac
	enable_ac=0
	vht_oper_chwidth=0
	vht_center_seg0=

	idx="$channel"
	case "$htmode" in
		VHT*) append base_cfg "require_vht=1" "$N" ;;
		VHT20|HE20|EHT20) enable_ac=1; vht_center_seg0=$idx;;
		VHT40|HE40|EHT40)
			case "$(( (($channel / 4) + $chan_ofs) % 2 ))" in
				1) idx=$(($channel + 2));;
				0) idx=$(($channel - 2));;
			esac
			enable_ac=1
			vht_center_seg0=$idx
		;;
		VHT80|HE80|EHT80)
			case "$(( (($channel / 4) + $chan_ofs) % 4 ))" in
				1) idx=$(($channel + 6));;
				2) idx=$(($channel + 2));;
				3) idx=$(($channel - 2));;
				0) idx=$(($channel - 6));;
			esac
			enable_ac=1
			vht_oper_chwidth=1
			vht_center_seg0=$idx
		;;
		VHT160|HE160|EHT160)
			if [ "$band" = "6g" ]; then
				case "$channel" in
					1|5|9|13|17|21|25|29) idx=15;;
					33|37|41|45|49|53|57|61) idx=47;;
					65|69|73|77|81|85|89|93) idx=79;;
					97|101|105|109|113|117|121|125) idx=111;;
					129|133|137|141|145|149|153|157) idx=143;;
					161|165|169|173|177|181|185|189) idx=175;;
					193|197|201|205|209|213|217|221) idx=207;;
				esac
			else
				case "$channel" in
					36|40|44|48|52|56|60|64) idx=50;;
					100|104|108|112|116|120|124|128) idx=114;;
					149|153|157|161|165|169|173|177) idx=163;;
				esac
			fi
			enable_ac=1
			vht_oper_chwidth=2
			vht_center_seg0=$idx
		;;
	esac
	[ "$band" = "5g" ] && {
		json_get_vars background_radar:0

		[ "$background_radar" -eq 1 ] && append base_cfg "enable_background_radar=1" "$N"
	}

	[ "$band" = "6g" ] && {
		op_class=
		case "$htmode" in
			HE20|EHT20) op_class=131;;
			EHT320*)
				case "$channel" in
					1|5|9|13|17|21|25|29| \
					33|37|41|45|49|53|57|61) idx=31;;
					65|69|73|77|81|85|89|93 |\
					97|101|105|109|113|117|121|125) idx=95;;
					129|133|137|141|145|149|153|157| \
					161|165|169|173|177|181|185|189) idx=159;;
					193|197|201|205|209|213|217|221) idx=191;;
				esac
				if [[ "$htmode" = "EHT320-1" && "$channel" -ge "193" ]] ||
				   [[ "$htmode" = "EHT320-2" && "$channel" -le "29" ]]; then
					echo "Could not set the center freq with this EHT setting"
					return 1
				elif [[ "$htmode" = "EHT320-2" && "$channel" -le "189" ]]; then
					if [ "$channel" -gt $idx ]; then
						idx=$(($idx + 32))
					else
						idx=$(($idx - 32))
					fi
				fi
				vht_oper_chwidth=2
				if [ "$channel" -gt $idx ]; then
					vht_center_seg0=$(($idx + 16))
				else
					vht_center_seg0=$(($idx - 16))
				fi
				eht_oper_chwidth=9
				eht_oper_centr_freq_seg0_idx=$idx

				case $htmode in
					EHT320-1) eht_bw320_offset=1;;
					EHT320-2) eht_bw320_offset=2;;
					EHT320) eht_bw320_offset=0;;
				esac

				op_class=137
			;;
			HE*|EHT*) op_class=$((132 + $vht_oper_chwidth));;
		esac
		[ -n "$op_class" ] && append base_cfg "op_class=$op_class" "$N"
	}

	[ "$hwmode" = "a" ] || enable_ac=0
	[ "$band" = "6g" ] && enable_ac=0

	if [ "$enable_ac" != "0" -o "$vendor_vht" = "1" ]; then
		json_get_vars \
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

		set_default tx_burst 2.0
		append base_cfg "ieee80211ac=1" "$N"
		vht_cap=0
		for cap in $(iw phy "$phy" info | awk -F "[()]" '/VHT Capabilities/ { print $2 }'); do
			vht_cap="$(($vht_cap | $cap))"
		done

		append base_cfg "vht_oper_chwidth=$vht_oper_chwidth" "$N"
		append base_cfg "vht_oper_centr_freq_seg0_idx=$vht_center_seg0" "$N"

		cap_rx_stbc=$((($vht_cap >> 8) & 7))
		[ "$rx_stbc" -lt "$cap_rx_stbc" ] && cap_rx_stbc="$rx_stbc"
		vht_cap="$(( ($vht_cap & ~(0x700)) | ($cap_rx_stbc << 8) ))"

		[ "$vht_oper_chwidth" -lt 2 ] && {
			vht160=0
			short_gi_160=0
		}

		mac80211_add_capabilities vht_capab $vht_cap \
			RXLDPC:0x10::$rxldpc \
			SHORT-GI-80:0x20::$short_gi_80 \
			SHORT-GI-160:0x40::$short_gi_160 \
			TX-STBC-2BY1:0x80::$tx_stbc_2by1 \
			SU-BEAMFORMER:0x800::$su_beamformer \
			SU-BEAMFORMEE:0x1000::$su_beamformee \
			MU-BEAMFORMER:0x80000::$mu_beamformer \
			MU-BEAMFORMEE:0x100000::$mu_beamformee \
			VHT-TXOP-PS:0x200000::$vht_txop_ps \
			HTC-VHT:0x400000::$htc_vht \
			RX-ANTENNA-PATTERN:0x10000000::$rx_antenna_pattern \
			TX-ANTENNA-PATTERN:0x20000000::$tx_antenna_pattern \
			RX-STBC-1:0x700:0x100:1 \
			RX-STBC-12:0x700:0x200:1 \
			RX-STBC-123:0x700:0x300:1 \
			RX-STBC-1234:0x700:0x400:1

		[ "$(($vht_cap & 0x800))" -gt 0 -a "$su_beamformer" -gt 0 ] && {
			cap_ant="$(( ( ($vht_cap >> 16) & 3 ) + 1 ))"
			[ "$cap_ant" -gt "$beamformer_antennas" ] && cap_ant="$beamformer_antennas"
			[ "$cap_ant" -gt 1 ] && vht_capab="$vht_capab[SOUNDING-DIMENSION-$cap_ant]"
		}

		[ "$(($vht_cap & 0x1000))" -gt 0 -a "$su_beamformee" -gt 0 ] && {
			cap_ant="$(( ( ($vht_cap >> 13) & 7 ) + 1 ))"
			[ "$cap_ant" -gt "$beamformee_antennas" ] && cap_ant="$beamformee_antennas"
			[ "$cap_ant" -gt 1 ] && vht_capab="$vht_capab[BF-ANTENNA-$cap_ant]"
		}

		# supported Channel widths
		vht160_hw=0
		[ "$(($vht_cap & 12))" -eq 4 -a 1 -le "$vht160" ] && \
			vht160_hw=1
		[ "$(($vht_cap & 12))" -eq 8 -a 2 -le "$vht160" ] && \
			vht160_hw=2
		[ "$vht160_hw" = 1 ] && vht_capab="$vht_capab[VHT160]"
		[ "$vht160_hw" = 2 ] && vht_capab="$vht_capab[VHT160-80PLUS80]"

		# maximum MPDU length
		vht_max_mpdu_hw=3895
		[ "$(($vht_cap & 3))" -ge 1 -a 7991 -le "$vht_max_mpdu" ] && \
			vht_max_mpdu_hw=7991
		[ "$(($vht_cap & 3))" -ge 2 -a 11454 -le "$vht_max_mpdu" ] && \
			vht_max_mpdu_hw=11454
		[ "$vht_max_mpdu_hw" != 3895 ] && \
			vht_capab="$vht_capab[MAX-MPDU-$vht_max_mpdu_hw]"

		# maximum A-MPDU length exponent
		vht_max_a_mpdu_len_exp_hw=0
		[ "$(($vht_cap & 58720256))" -ge 8388608 -a 1 -le "$vht_max_a_mpdu_len_exp" ] && \
			vht_max_a_mpdu_len_exp_hw=1
		[ "$(($vht_cap & 58720256))" -ge 16777216 -a 2 -le "$vht_max_a_mpdu_len_exp" ] && \
			vht_max_a_mpdu_len_exp_hw=2
		[ "$(($vht_cap & 58720256))" -ge 25165824 -a 3 -le "$vht_max_a_mpdu_len_exp" ] && \
			vht_max_a_mpdu_len_exp_hw=3
		[ "$(($vht_cap & 58720256))" -ge 33554432 -a 4 -le "$vht_max_a_mpdu_len_exp" ] && \
			vht_max_a_mpdu_len_exp_hw=4
		[ "$(($vht_cap & 58720256))" -ge 41943040 -a 5 -le "$vht_max_a_mpdu_len_exp" ] && \
			vht_max_a_mpdu_len_exp_hw=5
		[ "$(($vht_cap & 58720256))" -ge 50331648 -a 6 -le "$vht_max_a_mpdu_len_exp" ] && \
			vht_max_a_mpdu_len_exp_hw=6
		[ "$(($vht_cap & 58720256))" -ge 58720256 -a 7 -le "$vht_max_a_mpdu_len_exp" ] && \
			vht_max_a_mpdu_len_exp_hw=7
		vht_capab="$vht_capab[MAX-A-MPDU-LEN-EXP$vht_max_a_mpdu_len_exp_hw]"

		# whether or not the STA supports link adaptation using VHT variant
		vht_link_adapt_hw=0
		[ "$(($vht_cap & 201326592))" -ge 134217728 -a 2 -le "$vht_link_adapt" ] && \
			vht_link_adapt_hw=2
		[ "$(($vht_cap & 201326592))" -ge 201326592 -a 3 -le "$vht_link_adapt" ] && \
			vht_link_adapt_hw=3
		[ "$vht_link_adapt_hw" != 0 ] && \
			vht_capab="$vht_capab[VHT-LINK-ADAPT-$vht_link_adapt_hw]"

		[ -n "$vht_capab" ] && append base_cfg "vht_capab=$vht_capab" "$N"
	fi

	# 802.11ax / 802.11be
	enable_ax=0
	enable_be=0
	case "$htmode" in
		HE*) enable_ax=1 ;;
		EHT*) enable_ax=1; enable_be=1 ;;
	esac

	if [ "$enable_ax" != "0" -o "$vht_1024" = "1" ]; then
		json_get_vars \
			ldpc:1 \
			twt:0 \
			he_su_beamformer:1 \
			he_su_beamformee:1 \
			he_mu_beamformer:1 \
			he_twt_required:0 \
			he_spr_sr_control:3 \
			he_spr_psr_enabled:0 \
			he_spr_non_srg_obss_pd_max_offset:0 \
			he_bss_color:128 \
			he_bss_color_enabled:1

		he_phy_cap=$(iw phy "$phy" info | sed -n '/HE Iftypes: .*AP/,$p' | awk -F "[()]" '/HE PHY Capabilities/ { print $2 }' | head -1)
		he_phy_cap=${he_phy_cap:2}
		he_mac_cap=$(iw phy "$phy" info | sed -n '/HE Iftypes: .*AP/,$p' | awk -F "[()]" '/HE MAC Capabilities/ { print $2 }' | head -1)
		he_mac_cap=${he_mac_cap:2}

		append base_cfg "ieee80211ax=1" "$N"
		#append base_cfg "he_ldpc=$ldpc" "$N"
		[ "$hwmode" = "a" ] && {
			append base_cfg "he_oper_chwidth=$vht_oper_chwidth" "$N"
			append base_cfg "he_oper_centr_freq_seg0_idx=$vht_center_seg0" "$N"
		}

		mac80211_add_he_capabilities \
			he_su_beamformer:${he_phy_cap:6:2}:0x80:$he_su_beamformer \
			he_su_beamformee:${he_phy_cap:8:2}:0x1:$he_su_beamformee \
			he_mu_beamformer:${he_phy_cap:8:2}:0x2:${mu_beamformer:-$he_mu_beamformer} \
			he_spr_psr_enabled:${he_phy_cap:14:2}:0x1:$he_spr_psr_enabled \
			he_twt_required:${he_mac_cap:0:2}:0x6:$he_twt_required

		[ "$twt" -gt 0 ] && {
			append base_cfg "he_twt_responder=1" "$N"
		} || append base_cfg "he_twt_responder=0" "$N"

		if [ "$he_bss_color_enabled" -gt 0 ]; then
			if !([ -n "$he_bss_color" ] && [ "$he_bss_color" -gt 0 ] && [ "$he_bss_color" -le 64 ]); then
				rand=$(head -n 1 /dev/urandom | tr -dc 0-9 | head -c 2 | sed 's/^0*//')
				he_bss_color=$((rand % 63 + 1))
			fi
			append base_cfg "he_bss_color=$he_bss_color" "$N"
			[ "$he_spr_non_srg_obss_pd_max_offset" -gt 0 ] && { \
				append base_cfg "he_spr_non_srg_obss_pd_max_offset=$he_spr_non_srg_obss_pd_max_offset" "$N"
				he_spr_sr_control=$((he_spr_sr_control | (1 << 2)))
			}
			[ "$he_spr_psr_enabled" -gt 0 ] || he_spr_sr_control=$((he_spr_sr_control | (1 << 0)))
			append base_cfg "he_spr_sr_control=$he_spr_sr_control" "$N"
		else
			append base_cfg "he_bss_color_disabled=1" "$N"
		fi

		append base_cfg "he_default_pe_duration=4" "$N"
		append base_cfg "he_rts_threshold=1023" "$N"
		append base_cfg "he_mu_edca_qos_info_param_count=0" "$N"
		append base_cfg "he_mu_edca_qos_info_q_ack=0" "$N"
		append base_cfg "he_mu_edca_qos_info_queue_request=0" "$N"
		append base_cfg "he_mu_edca_qos_info_txop_request=0" "$N"
		append base_cfg "he_mu_edca_ac_be_aifsn=8" "$N"
		append base_cfg "he_mu_edca_ac_be_aci=0" "$N"
		append base_cfg "he_mu_edca_ac_be_ecwmin=9" "$N"
		append base_cfg "he_mu_edca_ac_be_ecwmax=10" "$N"
		append base_cfg "he_mu_edca_ac_be_timer=255" "$N"
		append base_cfg "he_mu_edca_ac_bk_aifsn=15" "$N"
		append base_cfg "he_mu_edca_ac_bk_aci=1" "$N"
		append base_cfg "he_mu_edca_ac_bk_ecwmin=9" "$N"
		append base_cfg "he_mu_edca_ac_bk_ecwmax=10" "$N"
		append base_cfg "he_mu_edca_ac_bk_timer=255" "$N"
		append base_cfg "he_mu_edca_ac_vi_ecwmin=5" "$N"
		append base_cfg "he_mu_edca_ac_vi_ecwmax=7" "$N"
		append base_cfg "he_mu_edca_ac_vi_aifsn=5" "$N"
		append base_cfg "he_mu_edca_ac_vi_aci=2" "$N"
		append base_cfg "he_mu_edca_ac_vi_timer=255" "$N"
		append base_cfg "he_mu_edca_ac_vo_aifsn=5" "$N"
		append base_cfg "he_mu_edca_ac_vo_aci=3" "$N"
		append base_cfg "he_mu_edca_ac_vo_ecwmin=5" "$N"
		append base_cfg "he_mu_edca_ac_vo_ecwmax=7" "$N"
		append base_cfg "he_mu_edca_ac_vo_timer=255" "$N"
	fi

	if [ "$enable_be" != "0" ]; then
		append base_cfg "ieee80211be=1" "$N"
		append base_cfg "eht_su_beamformer=1" "$N"
		append base_cfg "eht_su_beamformee=1" "$N"
		append base_cfg "eht_mu_beamformer=$mu_beamformer" "$N"
		[ "$hwmode" = "a" ] && {
			case $htmode in
				EHT320*)
					append base_cfg "eht_oper_chwidth=$eht_oper_chwidth" "$N"
					append base_cfg "eht_oper_centr_freq_seg0_idx=$eht_oper_centr_freq_seg0_idx" "$N"
					append base_cfg "eht_bw320_offset=$eht_bw320_offset" "$N"
				;;
				*)
					append base_cfg "eht_oper_chwidth=$vht_oper_chwidth" "$N"
					append base_cfg "eht_oper_centr_freq_seg0_idx=$vht_center_seg0" "$N"
				;;
			esac
		}
	fi

	hostapd_prepare_device_config "$hostapd_conf_file" nl80211
	cat >> "$hostapd_conf_file" <<EOF
${channel:+channel=$channel}
${channel_list:+chanlist=$channel_list}
${hostapd_noscan:+noscan=1}
${tx_burst:+tx_queue_data2_burst=$tx_burst}
#num_global_macaddr=$num_global_macaddr
$base_cfg

EOF
	json_select ..
	radio_md5sum=$(md5sum $hostapd_conf_file | cut -d" " -f1)
}

mac80211_hostapd_setup_bss() {
	local phy="$1"
	local ifname="$2"
	local macaddr="$3"
	local type="$4"

	hostapd_cfg=
	append hostapd_cfg "$type=$ifname" "$N"

	hostapd_set_bss_options hostapd_cfg "$phy" "$vif" || return 1
	json_get_vars wds wds_bridge dtim_period:2 start_disabled

	set_default wds 0
	set_default start_disabled 0

	[ "$wds" -gt 0 ] && {
		append hostapd_cfg "wds_sta=1" "$N"
		[ -n "$wds_bridge" ] && append hostapd_cfg "wds_bridge=$wds_bridge" "$N"
	}
	[ "$staidx" -gt 0 -o "$start_disabled" -eq 1 ] && append hostapd_cfg "start_disabled=1" "$N"

	cat >> "$hostapd_conf_file"  <<EOF
$hostapd_cfg
#bssid=$macaddr
use_driver_iface_addr=1
${default_macaddr:+#default_macaddr}
${random_macaddr:+#random_macaddr}
${dtim_period:+dtim_period=$dtim_period}
EOF
}

mac80211_generate_mac() {
	# 不生成 MAC，交给 MTK 驱动派生
	echo ""
}

mac80211_prepare_vif() {
	# MTK: mtwifi_ifname 与 config 同级（写在 interfaces.$vif 层），
	# 必须在 json_select config 之前读取
	local mtwifi_ifname
	json_get_var mtwifi_ifname "$MTWIFI_CFG_IFNAME_KEY"

	json_select config

	json_get_vars ifname mode ssid wds powersave macaddr enable wpa_psk_file vlan_file

	# MTK: config 里没有 ifname 时，用驱动分配的接口名
	[ -z "$ifname" ] && ifname="$mtwifi_ifname"

	[ -n "$ifname" ] || {
		local prefix;

		case "$mode" in
		ap)
			case "$band" in
				2g) prefix=ra;;
				5g) prefix=rai;;
				6g) prefix=rax;;
			esac
		;;
		#sta)
		#	case "$band" in
		#		2g) prefix=apcli;;
		#		5g) prefix=apclii;;
		#		6g) prefix=apclix;;
		#	esac
		#;;
		adhoc) prefix=ibss;;
		monitor) prefix=mon;;
		esac

		mac80211_set_ifname "$prefix"
	}

	append active_ifnames "$ifname"
	set_default wds 0
	set_default extsta 0
	set_default powersave 0
	json_add_string _ifname "$ifname"

	default_macaddr=
	random_macaddr=
	if [ -z "$macaddr" ]; then
		default_macaddr=1
		macidx="$(($macidx + 1))"
	elif [ "$macaddr" = 'random' ]; then
		macaddr="$(macaddr_random)"
		random_macaddr=1
	fi
	json_add_string _macaddr "$macaddr"
	json_add_string _default_macaddr "$default_macaddr"
	json_select ..

	[ "$mode" == "ap" ] && {
		json_select config
		wireless_vif_parse_encryption
		json_select ..

		[ -z "$wpa_psk_file" ] && hostapd_set_psk "$ifname"
		[ -z "$vlan_file" ] && hostapd_set_vlan "$ifname"
	}

	json_select config

	case "$mode" in
		ap)
			if [ -n "$hostapd_ctrl" ]; then
				type=bss
			else
				type=interface
			fi

			mac80211_hostapd_setup_bss "$phy" "$ifname" "$macaddr" "$type" || return

			[ -n "$hostapd_ctrl" ] || {
				ap_ifname="${ifname}"
				hostapd_ctrl="${hostapd_ctrl:-/var/run/hostapd/$ifname}"
			}
		;;
	esac

	json_select ..
}

mac80211_set_ifname() {
	local prefix="$1"
	eval "ifname=\"$prefix\${idx_$prefix:-0}\"; idx_$prefix=\$((\${idx_$prefix:-0} + 1))"
}

#
# ---- hostapd spawn / kill / WPS ER ----
#

mtwifi_hostapd_start() {
	local phy="$1"
	local conf_file="/var/run/hostapd-$phy.conf"
	local pid_file="/var/run/hostapd-$phy.pid"

	[ -f "$conf_file" ] || return

	# 把 OpenWrt 风格的 sae_password_file 内联成 MTK 风格的 sae_password
	if grep -q '^sae_password_file=' "$conf_file" 2>/dev/null; then
		local sae_file="$(sed -n 's/^sae_password_file=//p' "$conf_file" | head -1)"
		if [ -f "$sae_file" ]; then
			sed -i '/^sae_password_file=/d' "$conf_file"
			while IFS= read -r line; do
				[ -n "$line" ] && echo "sae_password=$line" >> "$conf_file"
			done < "$sae_file"
			logger -t "netifd-mtwifi" "inlined sae_password_file from $sae_file"
		fi
	fi

	if [ -f "$pid_file" ]; then
		local oldpid="$(cat "$pid_file" 2>/dev/null)"
		[ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null && kill "$oldpid" 2>/dev/null
		rm -f "$pid_file"
	fi

	/usr/sbin/hostapd -B -P "$pid_file" "$conf_file"
	logger -t "netifd-mtwifi" "hostapd started for $phy"
}

mtwifi_hostapd_wps_er_start() {
	local phy="$1"
	local conf_file="/var/run/hostapd-$phy.conf"
	local ifnames=""

	[ -f "$conf_file" ] || return

	ifnames="$(sed -n -e 's/^interface=//p' -e 's/^bss=//p' "$conf_file")"
	for ifname in $ifnames; do
		local wps_er_pid="/var/run/action-$ifname-wps-er.pid"
		local wps_er_script="/lib/wifi/hostapd_wps_er_action.lua"
		exec 1000>&-
		/usr/sbin/hostapd_cli -i "$ifname" -a "$wps_er_script" -B -P "$wps_er_pid"
	done
}

mtwifi_hostapd_wps_er_stop() {
	local phy="$1"
	local conf_file="/var/run/hostapd-$phy.conf"

	[ -f "$conf_file" ] || return

	local ifnames="$(sed -n -e 's/^interface=//p' -e 's/^bss=//p' "$conf_file")"
	for ifname in $ifnames; do
		local wps_er_pid="/var/run/action-$ifname-wps-er.pid"
		[ -f "$wps_er_pid" ] && kill -TERM "$(cat "$wps_er_pid")" 2>/dev/null
		rm -f "$wps_er_pid"
	done
}

mtwifi_hostapd_stop() {
	local phy="$1"
	local pid_file="/var/run/hostapd-$phy.pid"
	local conf_file="/var/run/hostapd-$phy.conf"

	if [ -f "$pid_file" ]; then
		local pid="$(cat "$pid_file" 2>/dev/null)"
		[ -n "$pid" ] && kill "$pid" 2>/dev/null
		rm -f "$pid_file"
	fi
	rm -f "$conf_file"
}

#
# ---- wpa_supplicant (STA / apcli) ----
#

mtwifi_wpas_conf() {
	local ifname="$1"
	local conf="$2"

	json_select config

	json_get_vars ssid bssid key encryption ieee80211w sae_pwe sae_groups
	json_get_vars identity password ca_cert client_cert priv_key priv_key_pwd eap_type auth phase1

	json_select ..

	: > "$conf"

	cat >> "$conf" <<EOF
ctrl_interface=/var/run/wpa_supplicant/
update_config=1
bss_expiration_scan_count=1

device_name=Wireless station
device_type=6-0050F204-1
manufacturer=MediaTek Inc.
model_name=MediaTek Wireless Access Point
model_number=MT7988
serial_number=12345678
config_methods=display virtual_push_button keypad physical_push_button

sae_pwe=${sae_pwe:-2}
autoscan=periodic:30

network={
	ssid="$ssid"
	scan_ssid=1
EOF

	[ -n "$bssid" ]      && echo "	bssid=$bssid"           >> "$conf"
	[ -n "$sae_groups" ] && echo "	sae_groups=$sae_groups" >> "$conf"

	case "$encryption" in
	""|none)
		echo "	key_mgmt=NONE" >> "$conf"
		;;

	psk2|psk2+ccmp)
		cat >> "$conf" <<EOF
	key_mgmt=WPA-PSK
	proto=RSN
	pairwise=CCMP
	psk="$key"
EOF
		;;
	psk2+tkip)
		cat >> "$conf" <<EOF
	key_mgmt=WPA-PSK
	proto=RSN
	pairwise=TKIP
	psk="$key"
EOF
		;;
	psk2+tkip+ccmp)
		cat >> "$conf" <<EOF
	key_mgmt=WPA-PSK
	proto=RSN
	pairwise=CCMP TKIP
	psk="$key"
EOF
		;;

	sae|sae+ccmp)
		cat >> "$conf" <<EOF
	key_mgmt=SAE
	proto=RSN
	pairwise=CCMP
	ieee80211w=2
	sae_password="$key"
EOF
		;;
	sae+gcmp256)
		cat >> "$conf" <<EOF
	key_mgmt=SAE
	proto=RSN
	pairwise=GCMP-256
	group=GCMP-256
	group_mgmt=BIP-GMAC-256
	ieee80211w=2
	sae_password="$key"
EOF
		;;
	sae-mixed)
		cat >> "$conf" <<EOF
	key_mgmt=SAE WPA-PSK
	proto=RSN
	pairwise=CCMP
	ieee80211w=1
	psk="$key"
EOF
		;;

	owe|owe+ccmp)
		cat >> "$conf" <<EOF
	key_mgmt=OWE
	proto=RSN
	pairwise=CCMP
EOF
		;;

	wpa2|wpa2+ccmp|wpa3)
		echo "	key_mgmt=WPA-EAP" >> "$conf"
		echo "	proto=RSN"        >> "$conf"
		echo "	pairwise=CCMP"    >> "$conf"
		[ -n "$identity"     ] && echo "	identity=\"$identity\"" >> "$conf"
		[ -n "$password"     ] && echo "	password=\"$password\"" >> "$conf"
		[ -n "$ca_cert"      ] && echo "	ca_cert=\"$ca_cert\""   >> "$conf"
		[ -n "$client_cert"  ] && echo "	client_cert=\"$client_cert\"" >> "$conf"
		[ -n "$priv_key"     ] && echo "	private_key=\"$priv_key\""    >> "$conf"
		[ -n "$priv_key_pwd" ] && echo "	private_key_passwd=\"$priv_key_pwd\"" >> "$conf"
		[ -n "$eap_type"     ] && echo "	eap=$(echo "$eap_type" | tr a-z A-Z)" >> "$conf"
		[ -n "$phase1"       ] && echo "	phase1=\"$phase1\""     >> "$conf"
		[ -n "$auth"         ] && echo "	phase2=\"auth=$auth\"" >> "$conf"
		;;

	*)
		logger -t "netifd-mtwifi" "unsupported encryption '$encryption' for $ifname, fallback NONE"
		echo "	key_mgmt=NONE" >> "$conf"
		;;
	esac

	# 非 SAE 系才允许 UCI 覆盖 PMF，避免破坏 SAE 硬编码的 ieee80211w=2
	case "$encryption" in
	sae|sae+ccmp|sae+gcmp|sae+gcmp256|sae+ccmp256|sae-mixed|sae-ext*)
		;;
	*)
		case "$ieee80211w" in
		1|2) echo "	ieee80211w=$ieee80211w" >> "$conf" ;;
		esac
		;;
	esac

	echo "}" >> "$conf"
}

mtwifi_supplicant_setup_vif() {
	local name="$1"
	local mtwifi_ifname=""
	local conf=""
	local ret=""
	local retry=0
	local scan_pid=""

	# mtwifi_ifname 与 config 同级
	json_get_var mtwifi_ifname "$MTWIFI_CFG_IFNAME_KEY"
	[ -n "$mtwifi_ifname" ] || {
		logger -t "netifd-mtwifi" "skip sta $name: no mtwifi_ifname"
		return 0
	}

	# 等全局 socket 就绪，最多 3 秒
	retry=0
	while [ $retry -lt 30 ]; do
		[ -S "$WPA_CTRL_DIR/global" ] && break
		sleep 0.1
		retry=$((retry+1))
	done
	if [ ! -S "$WPA_CTRL_DIR/global" ]; then
		logger -t "netifd-mtwifi" "supplicant global socket not ready, skip $mtwifi_ifname"
		return 1
	fi

	# 已经加过就先 remove
	if $WPA_CLI -p "$WPA_CTRL_DIR/" -i global interface 2>/dev/null | \
	   tr ' ' '\n' | grep -qx "$mtwifi_ifname"; then
		logger -t "netifd-mtwifi" "interface $mtwifi_ifname already in supplicant, remove first"
		$WPA_CLI -p "$WPA_CTRL_DIR/" -i global \
			interface_remove "$mtwifi_ifname" >/dev/null 2>&1
		sleep 1
	fi

	mkdir -p "$WPA_CTRL_DIR"
	conf="$WPA_CTRL_DIR/wpa_supplicant-$mtwifi_ifname.conf"
	mtwifi_wpas_conf "$mtwifi_ifname" "$conf" || return 1

	# interface_add: <ifname> <conf> <driver> <ctrl_iface> <drv_param> <bridge>
	ret=$($WPA_CLI -p "$WPA_CTRL_DIR/" -i global \
		interface_add "$mtwifi_ifname" "$conf" nl80211 "" "" "" 2>&1)

	logger -t "netifd-mtwifi" "interface_add $mtwifi_ifname: $ret"

	case "$ret" in
	OK*) ;;
	*) logger -t "netifd-mtwifi" "interface_add $mtwifi_ifname FAILED"; return 1 ;;
	esac

	ip link set "$mtwifi_ifname" up 2>/dev/null

	# 等 per-iface ctrl socket 就绪，再挂 scan action
	retry=0
	while [ $retry -lt 30 ]; do
		[ -S "$WPA_CTRL_DIR/$mtwifi_ifname" ] && break
		sleep 0.1
		retry=$((retry+1))
	done

	if [ -S "$WPA_CTRL_DIR/$mtwifi_ifname" ] && [ -f "$SCAN_ACTION_SCRIPT" ]; then
		scan_pid="/var/run/action-$mtwifi_ifname-scan.pid"
		[ -f "$scan_pid" ] && {
			kill -TERM "$(cat "$scan_pid")" 2>/dev/null
			rm -f "$scan_pid"
		}
		exec 1000>&-
		$WPA_CLI -p "$WPA_CTRL_DIR/" -i "$mtwifi_ifname" \
			-a "$SCAN_ACTION_SCRIPT" -B -P "$scan_pid"
		logger -t "netifd-mtwifi" "scan action attached to $mtwifi_ifname"
	else
		logger -t "netifd-mtwifi" "ctrl socket for $mtwifi_ifname not ready, skip scan action"
	fi
}

mtwifi_supplicant_teardown_dev() {
	local dev="$1"
	local apcli_prefix=""
	local scan_pid=""

	apcli_prefix="$(l1util get $dev apcli_ifname)"
	[ -n "$apcli_prefix" ] || return 0

	for ifn in $($WPA_CLI -p "$WPA_CTRL_DIR/" -i global interface 2>/dev/null); do
		case "$ifn" in
		"$apcli_prefix"*)
			# 先 kill 挂着的 wpa_cli action 进程
			scan_pid="/var/run/action-$ifn-scan.pid"
			if [ -f "$scan_pid" ]; then
				kill -TERM "$(cat "$scan_pid")" 2>/dev/null
				rm -f "$scan_pid"
			fi

			$WPA_CLI -p "$WPA_CTRL_DIR/" -i global \
				interface_remove "$ifn" >/dev/null 2>&1

			rm -f "$WPA_CTRL_DIR/wpa_supplicant-$ifn.conf"
			rm -f "/var/run/scan_state-$ifn"
			;;
		esac
	done
}

#
# ---- setup / teardown ----
#

drv_mtwifi_setup() {
	ubus -t 120 wait_for network.interface.lan

	local dev="$1"
	local phy

	json_add_string device "$dev"

	lock $LOCK_FILE

	logger -t "netifd-mtwifi" "up: $dev"

	MTWIFI_AP_IF_PREFIX="$(l1util get $dev ext_ifname)"
	MTWIFI_APCLI_IF_PREFIX="$(l1util get $dev apcli_ifname)"

	AP_IDX=0
	for_each_interface ap mtwifi_vif_ap_set_data

	APCLI_IDX=0
	for_each_interface sta mtwifi_vif_sta_set_data

	# 1. lua 生成 .dat + MTK 侧配置（含 hairpin_mode 和 WPS iface 映射）
	json_dump | /sbin/mtwifi_cfg setup

	# 2. 准备公共变量
	phy="$(l1util get $dev main_ifname)"
	[ -z "$phy" ] && phy="$dev"
	if [ -z "$phy" ]; then
		logger -t "netifd-mtwifi" "l1util get main_ifname failed, fallback to $dev"
		phy="$dev"
	fi

	json_select config
	json_get_vars band htmode channel
	json_select ..

	case "$band" in
		2g|2.4g) hwmode=g ;;
		5g|6g)   hwmode=a ;;
		*) hwmode= ;;
	esac

	case "$channel" in
		auto|"") auto_channel=1; channel=0 ;;
		*) auto_channel=0 ;;
	esac

	hostapd_conf_file="/var/run/hostapd-$phy.conf"
	[ -f "$hostapd_conf_file" ] && mv "$hostapd_conf_file" "$hostapd_conf_file.prev"
	hostapd_ctrl=
	ap_ifname=
	hostapd_noscan=
	macidx=0
	staidx=0
	active_ifnames=

	# 3. 判断有哪些接口
	has_ap=
	has_sta=
	for_each_interface "ap"  mtwifi_check_ap
	for_each_interface "sta" mtwifi_check_sta

	# 3a. AP 侧生成 hostapd 配置
	[ -n "$has_ap" ] && mac80211_hostapd_setup_base "$phy"
	[ -n "$has_ap" ] && for_each_interface "ap" mac80211_prepare_vif

	# 3b. STA 侧生成 wpa_supplicant 配置并 interface_add + 挂 scan action
	[ -n "$has_sta" ] && for_each_interface "sta" mtwifi_supplicant_setup_vif

	# 4. 起 hostapd + 挂 WPS ER
	if [ -n "$has_ap" ] && [ -f "$hostapd_conf_file" ]; then
		mtwifi_hostapd_start "$phy"
		mtwifi_hostapd_wps_er_start "$phy"
	fi

	# 5. vif 挂 netifd（接口名已确定，netifd 负责 up）
	for_each_interface ap mtwifi_vif_ap_config
	for_each_interface sta mtwifi_vif_sta_config

	wireless_set_up

	lock -u $LOCK_FILE
}

drv_mtwifi_teardown() {
	local dev="$1"
	local phy

	lock $LOCK_FILE

	logger -t "netifd-mtwifi" "down: $dev"

	# STA 侧：清掉属于当前 radio 的 apcli 接口 + scan action
	mtwifi_supplicant_teardown_dev "$dev"

	# AP 侧：停 WPS ER + hostapd
	phy="$(l1util get $dev main_ifname)"
	if [ -n "$phy" ]; then
		mtwifi_hostapd_wps_er_stop "$phy"
		mtwifi_hostapd_stop "$phy"
	fi

	/sbin/mtwifi_cfg down "$dev"

	lock -u $LOCK_FILE
}

add_driver mtwifi
