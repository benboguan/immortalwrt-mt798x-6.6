#!/bin/sh
. /lib/netifd/netifd-wireless.sh
. /lib/netifd/hostapd.sh
. /lib/functions/system.sh
. /lib/netifd/wireless/mtk_wifi_config.sh

init_wireless_driver "$@"

L1_PROFILE="/etc/wireless/l1profile.dat"
if [ -f "$L1_PROFILE" ]; then
    DAT_PATH=$(awk -F= '/^INDEX0_init_path=/ {print $2; exit}' "$L1_PROFILE")
    if [ -z "$DAT_PATH" ] || [ ! -f "$DAT_PATH" ]; then
        echo "Error: INDEX0_init_path not found or file does not exist in $L1_PROFILE" >&2
        exit 1
    fi
else
    echo "Error: Required l1_config file not found at $L1_PROFILE" >&2
    exit 1
fi

MP_CONFIG_INT="mesh_retry_timeout mesh_confirm_timeout mesh_holding_timeout mesh_max_peer_links
	       mesh_max_retries mesh_ttl mesh_element_ttl mesh_hwmp_max_preq_retries
	       mesh_path_refresh_time mesh_min_discovery_timeout mesh_hwmp_active_path_timeout
	       mesh_hwmp_preq_min_interval mesh_hwmp_net_diameter_traversal_time mesh_hwmp_rootmode
	       mesh_hwmp_rann_interval mesh_gate_announcements mesh_sync_offset_max_neighor
	       mesh_rssi_threshold mesh_hwmp_active_path_to_root_timeout mesh_hwmp_root_interval
	       mesh_hwmp_confirmation_interval mesh_awake_window mesh_plink_timeout"
MP_CONFIG_BOOL="mesh_auto_open_plinks mesh_fwding"
MP_CONFIG_STRING="mesh_power_mode"

wdev_tool() {
	ucode /usr/share/hostap/wdev.uc "$@"
}

ubus_call() {
	flock /var/run/hostapd.lock ubus call "$@"
}

drv_mac80211_init_device_config() {
	hostapd_common_add_device_config

	config_add_string path phy 'macaddr:macaddr'
	config_add_string tx_burst
	config_add_string distance
	config_add_int beacon_int chanbw frag rts
	config_add_int mbssid mu_onoff rnr obss_interval
	config_add_int rxantenna txantenna txpower min_tx_power
	config_add_int num_global_macaddr multiple_bssid
	config_add_boolean noscan ht_coex acs_exclude_dfs background_radar background_cert_mode
	config_add_array ht_capab
	config_add_array channels
	config_add_array scan_list
	config_add_boolean \
		rxldpc \
		short_gi_80 \
		short_gi_160 \
		tx_stbc_2by1 \
		su_beamformer \
		su_beamformee \
		mu_beamformer \
		mu_beamformee \
		he_su_beamformer \
		he_su_beamformee \
		he_mu_beamformer \
		vht_txop_ps \
		htc_vht \
		rx_antenna_pattern \
		tx_antenna_pattern \
		he_spr_sr_control \
		he_spr_psr_enabled \
		he_bss_color_enabled \
		he_twt_required \
		he_twt_responder \
		etxbfen \
		itxbfen \
		lpi_psd \
		lpi_bcn_enhance
	config_add_int \
		beamformer_antennas \
		beamformee_antennas \
		vht_max_a_mpdu_len_exp \
		vht_max_mpdu \
		vht_link_adapt \
		vht160 \
		rx_stbc \
		tx_stbc \
		he_bss_color \
		he_spr_non_srg_obss_pd_max_offset \
		pp_bitmap \
		pp_mode \
		eml_disable \
		eml_resp \
		sku_idx \
		lpi_sku_idx
	config_add_boolean \
		ldpc \
		greenfield \
		short_gi_20 \
		short_gi_40 \
		max_amsdu \
		dsss_cck_40
}

drv_mac80211_init_iface_config() {
	hostapd_common_add_bss_config

	config_add_string 'macaddr:macaddr' ifname

	config_add_boolean wds powersave enable
	config_add_string wds_bridge
	config_add_int maxassoc
	config_add_int max_listen_int
	config_add_int dtim_period
	config_add_int start_disabled

	# mesh
	config_add_string mesh_id
	config_add_int $MP_CONFIG_INT
	config_add_boolean $MP_CONFIG_BOOL
	config_add_string $MP_CONFIG_STRING
}

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

get_dat_file() {
    local band="$1"
    local dat_file=""

    case "$band" in
        2g) dat_file=$(grep "BN0" "$DAT_PATH" | awk -F'=' '{print $2}') ;;
        5g) dat_file=$(grep "BN1" "$DAT_PATH" | awk -F'=' '{print $2}') ;;
        6g) dat_file=$(grep "BN2" "$DAT_PATH" | awk -F'=' '{print $2}') ;;
    esac

    echo "$dat_file"
}

set_dat_params() {
    local param="$1" value="$2" dat_file="$3"

    [ ! -f "$dat_file" ] && return 1

    sed -i "s/^${param}=.*/${param}=${value}/g" "$dat_file"
    grep -q "^${param}=${value}" "$dat_file"
}

# 通用 base 函数，同时处理所有频段的参数设置
set_dat_base() {
    local dat_file="$1" ht_bw="$2" vht_bw="$3" eht_apbw="$4" wireless_mode="$5"

    set_dat_params "HT_BW" "$ht_bw" "$dat_file"       || return 1
    set_dat_params "VHT_BW" "$vht_bw" "$dat_file"     || return 1
    set_dat_params "EHT_ApBw" "$eht_apbw" "$dat_file" || return 1
    set_dat_params "WirelessMode" "$wireless_mode" "$dat_file" || return 1
}

# 将频段与对应的“带宽-参数”映射表关联
apply_htmode() {
    local dat_file="$1" htmode="$2"
    shift 2
    # 剩余参数格式：ht_bw vht_bw eht_apbw wireless_mode
    while [ $# -ge 5 ]; do
        local name="$1" ht_bw="$2" vht_bw="$3" eht_apbw="$4" wireless_mode="$5"
        if [ "$htmode" = "$name" ]; then
            set_dat_base "$dat_file" "$ht_bw" "$vht_bw" "$eht_apbw" "$wireless_mode"
            return $?
        fi
        shift 5
    done
    return 1  # 未找到匹配模式
}

set_dat_htmode() {
    local band="$1" htmode="$2"
    local dat_file=$(get_dat_file "$band")

    [ -z "$dat_file" ] || [ ! -f "$dat_file" ] && return 1

    case "$band" in
        2g)
            apply_htmode "$dat_file" "$htmode" \
                "NOHT"   "0" "0" "0" "3" \
                "HT20"   "0" "0" "0" "9" \
                "HT40"   "1" "0" "1" "9" \
                "HE20"   "0" "0" "0" "16" \
                "HE40"   "1" "0" "1" "16" \
                "EHT20"  "0" "0" "0" "22" \
                "EHT40"  "1" "0" "1" "22"
            ;;
        5g)
            apply_htmode "$dat_file" "$htmode" \
                "NOHT"    "0" "0" "0" "2" \
                "HT20"    "0" "0" "0" "8" \
                "HT40"    "1" "0" "1" "8" \
                "VHT20"   "0" "0" "0" "14" \
                "VHT40"   "1" "0" "1" "14" \
                "VHT80"   "1" "1" "2" "14" \
                "VHT80_80" "1" "3" "3" "14" \
                "VHT160"  "1" "2" "3" "14" \
                "HE20"    "0" "0" "0" "17" \
                "HE40"    "1" "0" "1" "17" \
                "HE80"    "1" "1" "2" "17" \
                "HE160"   "1" "2" "3" "17" \
                "HE320"   "" "" "" "17"    \
                "EHT20"   "0" "0" "0" "23" \
                "EHT40"   "1" "0" "1" "23" \
                "EHT80"   "1" "1" "2" "23" \
                "EHT160"  "1" "2" "3" "23" \
                "EHT320"  "1" "2" "4" "23"
            ;;
        6g)
            apply_htmode "$dat_file" "$htmode" \
                "HE20"    "0" "0" "0" "18" \
                "HE40"    "1" "0" "1" "18" \
                "HE80"    "1" "1" "2" "18" \
                "HE160"   "1" "2" "3" "18" \
                "HE320"   "" "" "" "18"    \
                "EHT20"   "0" "0" "0" "24" \
                "EHT40"   "1" "0" "1" "24" \
                "EHT80"   "1" "1" "2" "24" \
                "EHT160"  "1" "2" "3" "24" \
                "EHT320"  "1" "2" "4" "24"
            ;;
        *)
            return 1
            ;;
    esac
}

mac80211_hostapd_setup_base() {
	local phy="$1"

	json_select config

	[ "$auto_channel" -gt 0 ] && channel=acs_survey

	[ "$auto_channel" -gt 0 ] && json_get_vars acs_exclude_dfs
	[ -n "$acs_exclude_dfs" ] && [ "$acs_exclude_dfs" -gt 0 ] &&
		append base_cfg "acs_exclude_dfs=1" "$N"

	json_get_vars noscan ht_coex min_tx_power:0 tx_burst mbssid mu_onoff rnr obss_interval vendor_vht
	json_get_vars etxbfen:1 itxbfen:0 eml_disable eml_resp lpi_psd sku_idx lpi_sku_idx lpi_bcn_enhance
	json_get_values ht_capab_list ht_capab
	json_get_values channel_list channels

	[ "$min_tx_power" -gt 0 ] && append base_cfg "min_tx_power=$min_tx_power" "$N"

	set_default noscan 0

	[ "$noscan" -gt 0 ] && hostapd_noscan=1
	[ "$tx_burst" = 0 ] && tx_burst=

	chan_ofs=0
	[ "$band" = "6g" ] && chan_ofs=1

	nl_band=1
	[ "$band" = "5g" ] && nl_band=2
	[ "$band" = "6g" ] && nl_band=4

	if [ "$band" != "6g" ]; then
		ieee80211n=1
		ht_capab=
		case "$htmode" in
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
				dsss_cck_40:1

			[ "$ht_coex" -eq 1 ] && {
				set_default obss_interval 300
				append base_cfg "obss_interval=$obss_interval" "$N"
			}

			ht_cap_mask=0
			ht_cap_mask=$(iw phy "$phy" info | grep "Band ${nl_band}:" -A 1 | grep 'Capabilities: ' | cut -d: -f2)

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
				DSSS_CCK-40:0x1000::$dsss_cck_40

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
		VHT20|HE20|EHT20) enable_ac=1;;
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
		VHT160|HE160|EHT160|EHT320)
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
		json_get_vars \
			background_radar:0 \
			background_cert_mode:0 \

		[ "$background_radar" -eq 1 ] && append base_cfg "enable_background_radar=1" "$N"
		[ "$background_cert_mode" -eq 1 ] && append base_cfg "background_radar_mode=1" "$N"
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
			short_gi_160=0
		}

		[ "$etxbfen" -eq 0 ] && {
			su_beamformer=0
			su_beamformee=0
			mu_beamformer=0
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

	# 802.11ax
	enable_ax=0
	enable_be=0
	case "$htmode" in
		HE*) enable_ax=1 ;;
		EHT*) enable_ax=1; enable_be=1 ;;
	esac

	if [ "$enable_ax" != "0" ]; then
		json_get_vars \
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

		he_phy_cap=$(iw phy "$phy" info | sed -n '/Band '"${nl_band}"'/,$p' | sed -n '/HE Iftypes: .*AP/,$p' | awk -F "[()]" '/HE PHY Capabilities/ { print $2 }' | head -1)
		he_phy_cap=${he_phy_cap:2}
		he_mac_cap=$(iw phy "$phy" info | sed -n '/Band '"${nl_band}"'/,$p' | sed -n '/HE Iftypes: .*AP/,$p' | awk -F "[()]" '/HE MAC Capabilities/ { print $2 }' | head -1)
		he_mac_cap=${he_mac_cap:2}

		append base_cfg "ieee80211ax=1" "$N"
		[ "$hwmode" = "a" ] && {
			append base_cfg "he_oper_chwidth=$vht_oper_chwidth" "$N"
			append base_cfg "he_oper_centr_freq_seg0_idx=$vht_center_seg0" "$N"
		}

		[ "$etxbfen" -eq 0 ] && {
			he_su_beamformer=0
			he_mu_beamformer=0
		}

		mac80211_add_he_capabilities \
			he_su_beamformer:${he_phy_cap:6:2}:0x80:$he_su_beamformer \
			he_su_beamformee:${he_phy_cap:8:2}:0x1:$he_su_beamformee \
			he_mu_beamformer:${he_phy_cap:8:2}:0x2:$he_mu_beamformer \
			he_spr_psr_enabled:${he_phy_cap:14:2}:0x1:$he_spr_psr_enabled \
			he_twt_required:${he_mac_cap:0:2}:0x6:$he_twt_required

		if [ -n "$he_twt_responder" ]; then
			append base_cfg "he_twt_responder=$he_twt_responder" "$N"
		fi
		if [ "$he_bss_color_enabled" -gt 0 ]; then
			if !([ -n "$he_bss_color" ] && [ "$he_bss_color" -gt 0 ] && [ "$he_bss_color" -le 64 ]); then
				rand=$(head -n 1 /dev/urandom | tr -dc 0-9 | head -c 2 | sed 's/^0*//')
				he_bss_color=$((rand % 63 + 1))
			fi
			append base_cfg "he_bss_color=$he_bss_color" "$N"
			[ "$he_spr_non_srg_obss_pd_max_offset" -gt 0 ] && {
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
		append base_cfg "he_mu_edca_ac_be_aifsn=0" "$N"
		append base_cfg "he_mu_edca_ac_be_aci=0" "$N"
		append base_cfg "he_mu_edca_ac_be_ecwmin=9" "$N"
		append base_cfg "he_mu_edca_ac_be_ecwmax=10" "$N"
		append base_cfg "he_mu_edca_ac_be_timer=3" "$N"
		append base_cfg "he_mu_edca_ac_bk_aifsn=0" "$N"
		append base_cfg "he_mu_edca_ac_bk_aci=1" "$N"
		append base_cfg "he_mu_edca_ac_bk_ecwmin=9" "$N"
		append base_cfg "he_mu_edca_ac_bk_ecwmax=10" "$N"
		append base_cfg "he_mu_edca_ac_bk_timer=3" "$N"
		append base_cfg "he_mu_edca_ac_vi_ecwmin=5" "$N"
		append base_cfg "he_mu_edca_ac_vi_ecwmax=7" "$N"
		append base_cfg "he_mu_edca_ac_vi_aifsn=0" "$N"
		append base_cfg "he_mu_edca_ac_vi_aci=2" "$N"
		append base_cfg "he_mu_edca_ac_vi_timer=3" "$N"
		append base_cfg "he_mu_edca_ac_vo_aifsn=0" "$N"
		append base_cfg "he_mu_edca_ac_vo_aci=3" "$N"
		append base_cfg "he_mu_edca_ac_vo_ecwmin=5" "$N"
		append base_cfg "he_mu_edca_ac_vo_ecwmax=7" "$N"
		append base_cfg "he_mu_edca_ac_vo_timer=3" "$N"
	fi

	set_default tx_burst 2

	# 802.11be
	enable_be=0
	case "$htmode" in
		EHT*) enable_be=1 ;;
	esac

	if [ "$enable_be" != "0" ]; then

		json_get_vars \
			pp_bitmap \
			pp_mode

		append base_cfg "ieee80211be=1" "$N"
		if [ "$etxbfen" -eq 0 ]; then
			append base_cfg "eht_su_beamformee=1" "$N"
		else
			append base_cfg "eht_su_beamformer=1" "$N"
			append base_cfg "eht_su_beamformee=1" "$N"
			append base_cfg "eht_mu_beamformer=1" "$N"
		fi
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

		[ -n "$pp_bitmap" ] && append base_cfg "punct_bitmap=$pp_bitmap" "$N"

		[ -n "$pp_mode" ] && append base_cfg "pp_mode=$pp_mode" "$N"
	fi

	set_dat_htmode "$band" "$htmode"

	hostapd_prepare_device_config "$hostapd_conf_file" nl80211
	cat >> "$hostapd_conf_file" <<EOF
${channel:+channel=$channel}
${channel_list:+chanlist=$channel_list}
${hostapd_noscan:+noscan=1}
${tx_burst:+tx_queue_data2_burst=$tx_burst}
${mbssid:+mbssid=$mbssid}
${mu_onoff:+mu_onoff=$mu_onoff}
${itxbfen:+ibf_enable=$itxbfen}
${rnr:+rnr=$rnr}
${multiple_bssid:+mbssid=$multiple_bssid}
${eml_disable:+eml_disable=$eml_disable}
${eml_resp:+eml_resp=$eml_resp}
${lpi_psd:+lpi_psd=$lpi_psd}
${lpi_bcn_enhance:+lpi_bcn_enhance=$lpi_bcn_enhance}
${sku_idx:+sku_idx=$sku_idx}
${lpi_sku_idx:+lpi_sku_idx=$lpi_sku_idx}
#num_global_macaddr=$num_global_macaddr
#used_radio_mask=$used_radio_mask
$base_cfg

EOF
	json_select ..
}

mac80211_hostapd_setup_bss() {
	local phy="$1"
	local ifname="$2"
	local macaddr="$3"
	local type="$4"

	hostapd_cfg=
	append hostapd_cfg "$type=$ifname" "$N"

	hostapd_set_bss_options hostapd_cfg "$phy" "$vif" || return 1
	json_get_vars wds wds_bridge dtim_period max_listen_int start_disabled

	set_default wds 0
	set_default start_disabled 0

	[ "$wds" -gt 0 ] && {
		append hostapd_cfg "wds_sta=1" "$N"
		[ -n "$wds_bridge" ] && append hostapd_cfg "wds_bridge=$wds_bridge" "$N"
	}
	[ "$staidx" -gt 0 -o "$start_disabled" -eq 1 ] && append hostapd_cfg "start_disabled=1" "$N"

	cat >> /var/run/hostapd-$phy.conf <<EOF
$hostapd_cfg
#bssid=$macaddr
${default_macaddr:+#default_macaddr}
${random_macaddr:+#random_macaddr}
${dtim_period:+dtim_period=$dtim_period}
${max_listen_int:+max_listen_interval=$max_listen_int}
EOF
}

mac80211_get_addr() {
	local phy="$1"
	local idx="$(($2 + 1))"

	head -n $idx /sys/class/ieee80211/${phy}/addresses | tail -n1
}

mac80211_generate_mac() {
	local phy="$1"
	local id="${macidx:-0}"

	wdev_tool "$phy" get_macaddr id=$id num_global=$num_global_macaddr mbssid=${multiple_bssid:-0}
}

get_board_phy_name() (
	local path="$1"
	local fallback_phy=""

	__check_phy() {
		local val="$1"
		local key="$2"
		local ref_path="$3"

		json_select "$key"
		json_get_vars path
		json_select ..

		[ "${ref_path%+*}" = "$path" ] && fallback_phy=$key
		[ "$ref_path" = "$path" ] || return 0

		echo "$key"
		exit
	}

	json_load_file /etc/board.json
	json_for_each_item __check_phy wlan "$path"
	[ -n "$fallback_phy" ] && echo "${fallback_phy}.${path##*+}"
)

rename_board_phy_by_path() {
	local path="$1"

	local new_phy="$(get_board_phy_name "$path")"
	[ -z "$new_phy" -o "$new_phy" = "$phy" ] && return

	iw "$phy" set name "$new_phy" && phy="$new_phy"
}

rename_board_phy_by_name() (
	local phy="$1"
	local suffix="${phy##*.}"
	[ "$suffix" = "$phy" ] && suffix=

	json_load_file /etc/board.json
	json_select wlan
	json_select "${phy%.*}" || return 0
	json_get_vars path

	prev_phy="$(iwinfo nl80211 phyname "path=$path${suffix:++$suffix}")"
	[ -n "$prev_phy" ] || return 0

	[ "$prev_phy" = "$phy" ] && return 0

	iw "$prev_phy" set name "$phy"
)

find_phy() {
	[ -n "$phy" ] && {
		rename_board_phy_by_name "$phy"
		[ -d /sys/class/ieee80211/$phy ] && return 0
	}
	[ -n "$path" ] && {
		phy="$(iwinfo nl80211 phyname "path=$path")"
		[ -n "$phy" ] && {
			rename_board_phy_by_path "$path"
			return 0
		}
	}
	[ -n "$macaddr" ] && {
		for phy in $(ls /sys/class/ieee80211 2>/dev/null); do
			grep -i -q "$macaddr" "/sys/class/ieee80211/${phy}/macaddress" && {
				path="$(iwinfo nl80211 path "$phy")"
				rename_board_phy_by_path "$path"
				return 0
			}
		done
	}
	return 1
}

mac80211_check_ap() {
	has_ap=1
}

mac80211_check_sta() {
	has_sta=1
}

mac80211_set_ifname() {
	local phy="$1"
	local prefix="$2"
	eval "ifname=\"$phy-$prefix\${idx_$prefix:-0}\"; idx_$prefix=\$((\${idx_$prefix:-0 } + 1))"
}

fill_mld_params() {
	local target_mld_id=$1
	local own_phy_idx=$(echo $2 | tr -d "phy")
	local own_radio_idx=$3
	local found_mld=0
	local is_mld_link_id_set=0
	local is_primary=1
	local mld_allowed_links=0
	local mld_radio_mask=0
	local mld_link_cnt=0

	iface_list="$(cat /etc/config/wireless | grep wifi-iface | cut -d ' ' -f3 | tr -s "'\n" ' ')"
	for iface in $iface_list
	do
		local mld_id="$(uci show wireless.$iface | grep "mld_id" | cut -d '=' -f2 | tr -d "'")"
		local mld_link_id="$(uci show wireless.$iface | grep "mld_link_id" | cut -d '=' -f2 | tr -d "'")"
		local device="$(uci show wireless.$iface.device | cut -d '=' -f2 | tr -d "'")"
		local iface_disabled="$(uci show wireless.$iface | grep "disabled" | cut -d '=' -f2 | tr -d "'")"
		local ht_mode="$(uci show wireless.$device.htmode | cut -d '=' -f2 | tr -d "'")"
		local partner_radio_idx="$(uci show wireless.$device.radio | cut -d '=' -f2 | tr -d "'")"
		local radio_disabled="$(uci show wireless.$device | grep "disabled" | cut -d '=' -f2 | tr -d "'")"

		if [ "$iface_disabled" != "1" ] && [ "$radio_disabled" != "1" ] && [ "$mld_id" = "$target_mld_id" ] && [[ "$ht_mode" == "EHT"* ]]; then
			if [ -n "$mld_link_id" ]; then
				is_mld_link_id_set=1
				mld_allowed_links=$(($mld_allowed_links + 2**$mld_link_id))
			elif [ "$is_mld_link_id_set" -eq 1 ]; then
				echo "MLD link id should be set on every link"
				return 1
			else
				mld_allowed_links=$(($mld_allowed_links * 2 + 1))
			fi

			mld_link_cnt=$(($mld_link_cnt + 1))

			[ $partner_radio_idx -lt $own_radio_idx ] && is_primary=0
			mld_radio_mask=$(($mld_radio_mask + 2**$partner_radio_idx))
		fi
	done

	json_add_string "mld_primary" $is_primary
	json_add_string "mld_allowed_links" $mld_allowed_links
	json_add_string "mld_radio_mask" $mld_radio_mask

        mld_list="$(cat /etc/config/wireless | grep wifi-mld | cut -d ' ' -f3 | tr -s "'\n" ' ')"
        for m in $mld_list
        do
		local mld_id="$(uci show wireless.$m | grep "mld_id" | cut -d '=' -f2 | tr -d "'")"
		[ $mld_id = $target_mld_id ] || continue
		found_mld=1

                option_list="$(uci show wireless.$m | tr -s "\n" ' ')"
                for option in $option_list
                do
                        local key="$(echo $option | cut -d '=' -f1 | cut -d '.' -f3)"
                        local val="$(echo $option | cut -d '=' -f2 | tr -d "'")"
			[ -n "$key" ] && json_add_string $key $val
                done
        done

	if [ $found_mld -eq 0 ]; then
		echo "mld_id $target_mld_id is not found"
		return 1
	fi

	if [ $mld_link_cnt -gt 3 ]; then
		echo "mld_link_cnt $mld_link_cnt is invalid"
		return 1
	fi

	if [ $target_mld_id -lt 1 ] || [ $target_mld_id -gt 16 ]; then
		echo "mld_id is out of range (1, 16)"
		return 1
	fi

	return 0
}

mac80211_prepare_vif() {
	json_select config
	json_get_vars mld_id

	if [ -n "$mld_id" ] && [[ "$htmode" != "EHT"* ]]; then
		json_select config
		json_select ..
		return
	fi

	if [ -n "$mld_id" ]; then
		fill_mld_params $mld_id $phy $radio || return

		json_get_vars mld_addr
		if [ -z "$mld_addr" ]; then
			generated_mac=$(mac80211_generate_mac mld)
			# Split the MAC address to get the first byte
			b1="${generated_mac%%:*}"

			# Convert the first byte to a decimal for arithmetic operations
			b1_dec=$((0x$b1))

			# Get the upper 5 bits (first digit in hexadecimal representation)
			upper_nibble=$(($b1_dec & 0xF8))

			# Rotate the upper 5 bits based on mld_id
			# Modulus by 32 ensures that the rotation stays within the bounds of a nibble (5 bits)
			rotated=$(( (upper_nibble + ($mld_id << 3)) & 0xF8 ))

			# Combine the lower 3 bits with the rotated upper 5 bits
			b1_rotated=$(($b1_dec & 0x07 | rotated))

			# Reassemble the MAC address
			result_mac="$(printf '%02X' $b1_rotated):${generated_mac#*:}"

			# Add the MAC address to the JSON object
			json_add_string mld_addr "$result_mac"
		fi
	fi

	json_get_vars ifname mode ssid wds powersave macaddr enable wpa_psk_file sae_password_file vlan_file mld_primary

	[ -n "$ifname" ] || {
		local prefix;

		case "$mode" in
		ap|sta|mesh) prefix=$mode;;
		adhoc) prefix=ibss;;
		monitor) prefix=mon;;
		esac

		mac80211_set_ifname "$phy" "$prefix"
	}

	append active_ifnames "$ifname"
	set_default wds 0
	set_default powersave 0
	json_add_string _ifname "$ifname"

	default_macaddr=
	random_macaddr=
	if [ -z "$macaddr" ]; then
		macaddr="$(mac80211_generate_mac $phy)"
		macidx="$(($macidx + 1))"
		default_macaddr=1
	elif [ "$macaddr" = 'random' ]; then
		macaddr="$(macaddr_random)"
		random_macaddr=1
	fi
	json_add_string _macaddr "$macaddr"
	json_add_string _default_macaddr "$default_macaddr"
	json_select ..

	[ "$mode" == "ap" ] && [ "$mld_primary" != "0" ] && {
		json_select config
		wireless_vif_parse_encryption
		json_select ..

		[ -z "$wpa_psk_file" ] && hostapd_set_psk "$ifname"
		[ -z "$sae_password_file" ] && hostapd_set_sae "$ifname"
		[ -z "$vlan_file" ] && hostapd_set_vlan "$ifname"
	}

	json_select config

	# It is far easier to delete and create the desired interface
	case "$mode" in
		ap)
			# Hostapd will handle recreating the interface and
			# subsequent virtual APs belonging to the same PHY
			if [ -n "$hostapd_ctrl" ]; then
				type=bss
			else
				type=interface
			fi

			local retry=15
			local ifname_folder="/sys/class/ieee80211/$phy/device/net/$ifname"
			while [ "$retry" -gt 0 ] && [ -n "$mld_primary" ] && [ "$mld_primary" -eq 0 ] && [ ! -d $ifname_folder ]
			do
				echo "$phy:$ifname is not mld primary and does not exist, sleep 1s"
				retry=$((retry - 1))
				sleep 3
			done

			[ "$retry" -eq 0 ] && [ ! -d $ifname_folder ] && return

			mac80211_hostapd_setup_bss "$phy" "$ifname" "$macaddr" "$type" || return

			[ -n "$hostapd_ctrl" ] || {
				ap_ifname="${ifname}"
				hostapd_ctrl="${hostapd_ctrl:-/var/run/hostapd/$ifname}"
			}
		;;
	esac

	json_select ..
}

mac80211_prepare_iw_htmode() {
	case "$htmode" in
		HT20|VHT20|HE20|EHT20)
			iw_htmode=HT20
		;;
		HT40*|VHT40|HE40|EHT40)
			case "$band" in
				2g)
					case "$htmode" in
						HT40+) iw_htmode="HT40+";;
						HT40-) iw_htmode="HT40-";;
						*)
							if [ "$channel" -lt 7 ]; then
								iw_htmode="HT40+"
							else
								iw_htmode="HT40-"
							fi
						;;
					esac
				;;
				*)
					case "$(( ($channel / 4) % 2 ))" in
						1) iw_htmode="HT40+" ;;
						0) iw_htmode="HT40-";;
					esac
				;;
			esac
			[ "$auto_channel" -gt 0 ] && iw_htmode="HT40+"
		;;
		VHT80|HE80|EHT80)
			iw_htmode="80MHz"
		;;
		VHT160|HE160|EHT160)
			iw_htmode="160MHz"
		;;
		EHT320*)
			iw_htmode="320MHz"
		;;
		NONE|NOHT)
			iw_htmode="NOHT"
		;;
		*) iw_htmode="" ;;
	esac
}

mac80211_add_mesh_params() {
	for var in $MP_CONFIG_INT $MP_CONFIG_BOOL $MP_CONFIG_STRING; do
		eval "mp_val=\"\$$var\""
		[ -n "$mp_val" ] && json_add_string "$var" "$mp_val"
	done
}

mac80211_setup_adhoc() {
	local enable=$1
	json_get_vars bssid ssid key mcast_rate

	NEWUMLIST="${NEWUMLIST}$ifname "

	[ "$enable" = 0 ] && {
		ip link set dev "$ifname" down
		return 0
	}

	keyspec=
	[ "$auth_type" = "wep" ] && {
		set_default key 1
		case "$key" in
			[1234])
				local idx
				for idx in 1 2 3 4; do
					json_get_var ikey "key$idx"

					[ -n "$ikey" ] && {
						ikey="$(($idx - 1)):$(prepare_key_wep "$ikey")"
						[ $idx -eq $key ] && ikey="d:$ikey"
						append keyspec "$ikey"
					}
				done
			;;
			*)
				append keyspec "d:0:$(prepare_key_wep "$key")"
			;;
		esac
	}

	brstr=
	for br in $basic_rate_list; do
		wpa_supplicant_add_rate brstr "$br"
	done

	mcval=
	[ -n "$mcast_rate" ] && wpa_supplicant_add_rate mcval "$mcast_rate"

	local prev
	json_set_namespace wdev_uc prev

	json_add_object "$ifname"
	json_add_string mode adhoc
	json_add_string macaddr "$macaddr"
	json_add_string ssid "$ssid"
	json_add_string freq "$freq"
	json_add_string htmode "$iw_htmode"
	[ -n "$bssid" ] && json_add_string bssid "$bssid"
	json_add_int beacon-interval "$beacon_int"
	[ -n "$brstr" ] && json_add_string basic-rates "$brstr"
	[ -n "$mcval" ] && json_add_string mcast-rate "$mcval"
	[ -n "$keyspec" ] && json_add_string keys "$keyspec"
	json_close_object

	json_set_namespace "$prev"
}

mac80211_setup_mesh() {
	json_get_vars ssid mesh_id mcast_rate

	mcval=
	[ -n "$mcast_rate" ] && wpa_supplicant_add_rate mcval "$mcast_rate"
	[ -n "$mesh_id" ] && ssid="$mesh_id"

	brstr=
	for br in $basic_rate_list; do
		wpa_supplicant_add_rate brstr "$br"
	done

	local prev
	json_set_namespace wdev_uc prev

	json_add_object "$ifname"
	json_add_string mode mesh
	json_add_string macaddr "$macaddr"
	json_add_string ssid "$ssid"
	json_add_string freq "$freq"
	json_add_string htmode "$iw_htmode"
	[ -n "$mcval" ] && json_add_string mcast-rate "$mcval"
	[ -n "$brstr" ] && json_add_string basic-rates "$brstr"
	json_add_int beacon-interval "$beacon_int"
	mac80211_add_mesh_params

	json_close_object

	json_set_namespace "$prev"
}

mac80211_setup_monitor() {
	local prev
	json_set_namespace wdev_uc prev

	json_add_object "$ifname"
	json_add_string mode monitor
	[ -n "$freq" ] && json_add_string freq "$freq"
	json_add_string htmode "$iw_htmode"
	json_close_object

	json_set_namespace "$prev"
}

wpa_supplicant_init_config() {
	json_set_namespace wpa_supp prev

	json_init
	json_add_array config

	json_set_namespace "$prev"
}

wpa_supplicant_add_interface() {
	local ifname="$1"
	local mode="$2"
	local prev

	_wpa_supplicant_common "$ifname"

	json_set_namespace wpa_supp prev

	json_add_object
	json_add_string ctrl "$_rpath"
	json_add_string iface "$ifname"
	json_add_string mode "$mode"
	json_add_string config "$_config"
	json_add_string macaddr "$macaddr"
	json_add_string mld_allowed_phy_bitmap "$mld_allowed_phy_bitmap"
	[ -n "$network_bridge" ] && json_add_string bridge "$network_bridge"
	[ -n "$wds" ] && json_add_boolean 4addr "$wds"
	json_add_boolean powersave "$powersave"
	[ "$mode" = "mesh" ] && mac80211_add_mesh_params
	json_close_object

	json_set_namespace "$prev"

	wpa_supp_init=1
}

wpa_supplicant_set_config() {
	local phy="$1"
	local prev

	json_set_namespace wpa_supp prev
	json_close_array
	json_add_string phy "$phy"
	json_add_int num_global_macaddr "$num_global_macaddr"
	json_add_boolean defer 1
	local data="$(json_dump)"

	json_cleanup
	json_set_namespace "$prev"

	ubus -S -t 0 wait_for wpa_supplicant || {
		[ -n "$wpa_supp_init" ] || return 0

		ubus wait_for wpa_supplicant
	}

	local supplicant_res="$(ubus_call wpa_supplicant config_set "$data")"
	ret="$?"
	[ "$ret" != 0 -o -z "$supplicant_res" ] && wireless_setup_vif_failed WPA_SUPPLICANT_FAILED

	wireless_add_process "$(jsonfilter -s "$supplicant_res" -l 1 -e @.pid)" "/usr/sbin/wpa_supplicant" 1 1

}

mac80211_netdev_exists() {
	local ifname="$1"
	[ -n "$ifname" ] && [ -e "/sys/class/net/$ifname" ]
}

mac80211_append_reserved_ifnames() {
	local phy="$1"
	local max_ap="${MTK_RESERVED_AP_BSSID_NUM:-4}"
	local max_sta="${MTK_RESERVED_APCLI_NUM:-1}"
	local idx

	case "$max_ap" in
		''|*[!0-9]*) max_ap=4 ;;
	esac
	[ "$max_ap" -lt 4 ] && max_ap=4

	case "$max_sta" in
		''|*[!0-9]*) max_sta=1 ;;
	esac
	[ "$max_sta" -lt 1 ] && max_sta=1

	idx=0
	while [ "$idx" -lt "$max_ap" ]; do
		append active_ifnames "${phy}-ap${idx}"
		idx=$((idx + 1))
	done

	idx=0
	while [ "$idx" -lt "$max_sta" ]; do
		append active_ifnames "${phy}-sta${idx}"
		idx=$((idx + 1))
	done
}

mac80211_create_reserved_vif() {
	local phy="$1"
	local ifname="$2"
	local type="$3"

	mac80211_netdev_exists "$ifname" && return 0

	if iw phy "$phy" interface add "$ifname" type "$type" >/dev/null 2>&1; then
		[ "$type" = "managed" ] && iw dev "$ifname" set 4addr on >/dev/null 2>&1
		logger -t mac80211.sh "Created reserved wireless interface $ifname ($type)"
		return 0
	fi

	logger -t mac80211.sh "ERROR: failed to create reserved wireless interface $ifname ($type)"
	return 1
}

mac80211_create_reserved_ifnames() {
	local phy="$1"
	local max_ap="${MTK_RESERVED_AP_BSSID_NUM:-4}"
	local max_sta="${MTK_RESERVED_APCLI_NUM:-1}"
	local idx

	case "$max_ap" in
		''|*[!0-9]*) max_ap=4 ;;
	esac
	[ "$max_ap" -lt 4 ] && max_ap=4

	case "$max_sta" in
		''|*[!0-9]*) max_sta=1 ;;
	esac
	[ "$max_sta" -lt 1 ] && max_sta=1

	idx=0
	while [ "$idx" -lt "$max_ap" ]; do
		mac80211_create_reserved_vif "$phy" "${phy}-ap${idx}" "__ap"
		idx=$((idx + 1))
	done

	idx=0
	while [ "$idx" -lt "$max_sta" ]; do
		mac80211_create_reserved_vif "$phy" "${phy}-sta${idx}" "managed"
		idx=$((idx + 1))
	done
}

mac80211_acquire_hostapd_lock() {
	local phy="$1"
	local lock_dir="/tmp/mac80211-hostapd.lock"
	local wait=0
	local max_wait=30

	while ! mkdir "$lock_dir" 2>/dev/null; do
		if [ -f "$lock_dir/owner" ]; then
			local owner_pid="$(cat "$lock_dir/owner" 2>/dev/null | cut -d: -f1)"
			if [ -n "$owner_pid" ] && ! kill -0 "$owner_pid" 2>/dev/null; then
				logger -t mac80211.sh "WARNING: removing stale hostapd lock from pid=$owner_pid"
				rm -rf "$lock_dir" 2>/dev/null
				continue
			fi
		fi

		wait=$((wait + 1))
		if [ "$wait" -ge "$max_wait" ]; then
			logger -t mac80211.sh "ERROR: timeout waiting hostapd lock for $phy"
			return 1
		fi
		sleep 1
	done

	echo "$$:$phy" > "$lock_dir/owner" 2>/dev/null
	return 0
}

mac80211_release_hostapd_lock() {
	local lock_dir="/tmp/mac80211-hostapd.lock"

	[ -d "$lock_dir" ] || return 0
	rm -f "$lock_dir/owner" 2>/dev/null
	rmdir "$lock_dir" 2>/dev/null
	return 0
}

hostapd_set_config() {
	# 启动所有为该 phy 生成的 hostapd 配置文件
	# 格式：/var/run/hostapd-${phy}-ap${index}.conf
	local phy="$1"
	local logfile="/var/log/hostapd.log"
	local started=0
	local skip_confs="/tmp/hostapd_skip_${phy}_$$.tmp"
	local stale_pids="/tmp/hostapd_stale_${phy}_$$.tmp"

	# 第一步：关闭那些没有配置文件的hostapd进程，保留默认VAP接口池
	# 查找所有该phy的pid文件
	for pidfile in /var/run/hostapd-${phy}-ap*.pid; do
		[ ! -f "$pidfile" ] && continue
		local pid=$(cat "$pidfile" 2>/dev/null)
		[ -z "$pid" ] && continue
		
		# 从pid文件名提取ap_index
		local ap_index=$(basename "$pidfile" | sed "s/hostapd-${phy}-ap\([0-9]*\)\.pid/\1/")
		local conf="/var/run/hostapd-${phy}-ap${ap_index}.conf"
		
		# 如果配置文件不存在，只关闭这个hostapd进程，不删除默认VAP接口
		if [ ! -f "$conf" ]; then
			logger -t mac80211.sh "Closing hostapd process (no config file): pid=$pid, conf=$conf"
			kill "$pid" 2>/dev/null
			sleep 1
			if kill -0 "$pid" 2>/dev/null; then
				kill -9 "$pid" 2>/dev/null
				sleep 1
			fi
			rm -f "$pidfile"
		fi
	done

	# 第二步：先停掉该 phy 上当前配置相关的所有 hostapd，避免边杀边起导致同频冲突
	rm -f "$stale_pids"
	for conf in /var/run/hostapd-${phy}-ap*.conf; do
		local ap_index pidfile ifname old_pid

		[ -f "$conf" ] || continue

		ap_index=$(basename "$conf" | sed "s/hostapd-${phy}-ap\([0-9]*\)\.conf/\1/")
		pidfile="/var/run/hostapd-${phy}-ap${ap_index}.pid"
		ifname=$(grep "^interface=" "$conf" 2>/dev/null | cut -d'=' -f2 | head -1)
		[ -z "$ifname" ] && ifname="${phy}-ap${ap_index}"

		if [ -f "$pidfile" ]; then
			old_pid=$(cat "$pidfile" 2>/dev/null)
			[ -n "$old_pid" ] && echo "$old_pid" >> "$stale_pids"
			rm -f "$pidfile"
		fi

		ps | grep "[h]ostapd" | while read line; do
			if echo "$line" | grep -q "$(basename "$conf")" || echo "$line" | grep -q "$ifname"; then
				local existing_pid=$(echo "$line" | awk '{print $1}')
				[ -n "$existing_pid" ] && echo "$existing_pid" >> "$stale_pids"
			fi
		done
	done

	if [ -f "$stale_pids" ]; then
		while read existing_pid; do
			[ -z "$existing_pid" ] && continue
			if kill -0 "$existing_pid" 2>/dev/null; then
				logger -t mac80211.sh "Stopping stale hostapd process on $phy: pid=$existing_pid"
				kill "$existing_pid" 2>/dev/null
				sleep 1
				if kill -0 "$existing_pid" 2>/dev/null; then
					kill -9 "$existing_pid" 2>/dev/null
					sleep 1
				fi
			fi
		done < "$stale_pids"
	fi

	# 第三步：只检查默认接口池，不再根据配置动态创建接口
	rm -f "$skip_confs"
	for conf in /var/run/hostapd-${phy}-ap*.conf; do
		local ap_index ifname

		[ -f "$conf" ] || continue

		ap_index=$(basename "$conf" | sed "s/hostapd-${phy}-ap\([0-9]*\)\.conf/\1/")
		ifname=$(grep "^interface=" "$conf" 2>/dev/null | cut -d'=' -f2 | head -1)
		[ -z "$ifname" ] && ifname="${phy}-ap${ap_index}"

		if mac80211_netdev_exists "$ifname"; then
			ip link set dev "$ifname" up 2>/dev/null
		else
			logger -t mac80211.sh "ERROR: Interface $ifname is missing from default pool, will skip hostapd start for $conf"
			echo "$conf" >> "$skip_confs"
		fi
	done

	# 第四步：启动所有匹配的 hostapd 配置文件
	for conf in /var/run/hostapd-${phy}-ap*.conf; do
		# 检查文件是否存在（避免通配符未匹配时的情况）
		[ ! -f "$conf" ] && continue
		[ -f "$skip_confs" ] && grep -qxF "$conf" "$skip_confs" && continue
		
		# 从文件名提取 ap_index（如 hostapd-phy0-ap1.conf -> 1）
		local ap_index=$(basename "$conf" | sed "s/hostapd-${phy}-ap\([0-9]*\)\.conf/\1/")
		local pidfile="/var/run/hostapd-${phy}-ap${ap_index}.pid"
		
		# 从配置文件读取接口名
		local ifname=$(grep "^interface=" "$conf" 2>/dev/null | cut -d'=' -f2 | head -1)
		[ -z "$ifname" ] && ifname="${phy}-ap${ap_index}"
		
		# 启动 hostapd
		logger -t mac80211.sh "Starting hostapd with config: $conf (interface: $ifname)"
		/usr/sbin/hostapd -B -P "$pidfile" -f "$logfile" "$conf"
		ret=$?
		if [ "$ret" = "0" ]; then
			sleep 1
			if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
				started=$((started + 1))
				# 让 netifd 记录这个进程
				wireless_add_process "$(cat "$pidfile" 2>/dev/null)" "/usr/sbin/hostapd" 1 1
				logger -t mac80211.sh "hostapd started successfully for $conf (pid: $(cat "$pidfile" 2>/dev/null))"
			else
				logger -t mac80211.sh "ERROR: hostapd process died immediately after start for $conf"
			fi
		else
			logger -t mac80211.sh "hostapd start failed for $conf, ret=$ret"
		fi
	done

	# 如果没有启动任何 hostapd，返回错误
	if [ "$started" -eq 0 ]; then
		rm -f "$stale_pids"
		rm -f "$skip_confs"
		logger -t mac80211.sh "No hostapd configs found or started for phy=$phy"
		wireless_setup_failed HOSTAPD_START_FAILED
		return 1
	fi

	rm -f "$stale_pids"
	rm -f "$skip_confs"

	logger -t mac80211.sh "Started $started hostapd instance(s) for phy=$phy"
	return 0
}


wpa_supplicant_start() {
	local phy="$1"

	[ -n "$wpa_supp_init" ] || return 0

	ubus_call wpa_supplicant config_set '{ "phy": "'"$phy"'", "num_global_macaddr": '"$num_global_macaddr"' }' > /dev/null
}

mac80211_setup_supplicant() {
	local enable=$1
	local add_sp=0

	wpa_supplicant_prepare_interface "$ifname" nl80211 || return 1

	if [ "$mode" = "sta" ]; then
		wpa_supplicant_add_network "$ifname" "" "$htmode"
	else
		wpa_supplicant_add_network "$ifname" "$freq" "$htmode" "$hostapd_noscan"
	fi

	wpa_supplicant_add_interface "$ifname" "$mode"

	return 0
}

mac80211_setup_vif() {
	local name="$1"
	local failed

	json_select config
	json_get_var ifname _ifname
	json_get_var macaddr _macaddr
	json_get_vars mode wds powersave

	set_default powersave 0
	set_default wds 0

	case "$mode" in
		mesh)
			json_get_vars $MP_CONFIG_INT $MP_CONFIG_BOOL $MP_CONFIG_STRING
			wireless_vif_parse_encryption
			[ -z "$htmode" ] && htmode="NOHT";
			if [ -x /usr/sbin/wpa_supplicant ] && wpa_supplicant -vmesh; then
				mac80211_setup_supplicant || failed=1
			else
				mac80211_setup_mesh
			fi
		;;
		adhoc)
			wireless_vif_parse_encryption
			if [ "$wpa" -gt 0 -o "$auto_channel" -gt 0 ]; then
				mac80211_setup_supplicant || failed=1
			else
				mac80211_setup_adhoc
			fi
		;;
		sta)
			mac80211_setup_supplicant || failed=1
		;;
		monitor)
			mac80211_setup_monitor
		;;
	esac

	json_select ..
	if [ -n "$failed" ]; then
		echo "error: $ifname failed to setup"
	else
		wireless_add_vif "$name" "$ifname"
	fi

	echo "Setup SMP Affinity"
	/sbin/smp.sh
}

mac80211_start_sta_vif() {
	json_select config
	json_get_var ifname _ifname
	json_get_var mode mode

	if [ "$mode" = "sta" ]; then
		if mac80211_netdev_exists "$ifname"; then
			ip link set dev "$ifname" up 2>/dev/null
			ubus_call wpa_supplicant config_remove '{ "iface": "'"$ifname"'" }' >/dev/null 2>&1
			wpa_supplicant_run "$ifname"
		else
			logger -t mac80211.sh "ERROR: STA interface $ifname is missing from default pool"
			wireless_setup_vif_failed NO_DEVICE
		fi
	fi

	json_select ..
}

get_freq() {
	local phy="$1"
	local channel="$2"
	local band="$3"

	case "$band" in
		2g) band="1:";;
		5g) band="2:";;
		60g) band="3:";;
		6g) band="4:";;
	esac

	iw "$phy" info | awk -v band="$band" -v channel="[$channel]" '

$1 ~ /Band/ {
	band_match = band == $2
}

band_match && $3 == "MHz" && $4 == channel {
	print int($2)
	exit
}
'
}

chan_is_dfs() {
	local phy="$1"
	local chan="$2"
	iw "$phy" info | grep -E -m1 "(\* ${chan:-....} MHz${chan:+|\\[$chan\\]})" | grep -q "MHz.*radar detection"
	return $!
}

mac80211_set_noscan() {
	hostapd_noscan=1
}

drv_mac80211_cleanup() {
	hostapd_common_cleanup
}

mac80211_reset_config() {
	local phy="$1"

	hostapd_conf_file="/var/run/hostapd-$phy.conf"
	ubus_call hostapd config_set '{ "phy": "'"$phy"'", "config": "", "prev_config": "'"$hostapd_conf_file"'" }' > /dev/null
	ubus_call wpa_supplicant config_set '{ "phy": "'"$phy"'", "config": [] }' > /dev/null
}

mac80211_device_needs_restart() {
	local phy="$1"
	local changes=""

	[ -n "$prev_phy" ] || return 1
	[ "$prev_phy" = "$phy" ] || return 1

	[ "${prev_channel:-}" = "${channel:-}" ] || append changes "channel:${prev_channel:--}->${channel:--}" ", "
	[ "${prev_band:-}" = "${band:-}" ] || append changes "band:${prev_band:--}->${band:--}" ", "
	[ "${prev_htmode:-}" = "${htmode:-}" ] || append changes "htmode:${prev_htmode:--}->${htmode:--}" ", "
	[ "${prev_country:-}" = "${country:-}" ] || append changes "country:${prev_country:--}->${country:--}" ", "
	[ "${prev_chanbw:-}" = "${chanbw:-}" ] || append changes "chanbw:${prev_chanbw:--}->${chanbw:--}" ", "
	[ "${prev_macaddr:-}" = "${macaddr:-}" ] || append changes "macaddr:${prev_macaddr:--}->${macaddr:--}" ", "

	[ -n "$changes" ] || return 1

	logger -t mac80211.sh "Radio config changed on $phy, forcing full reload: $changes"
	return 0
}

mac80211_force_phy_reload() {
	local phy="$1"
	local pidfile pid wdev

	logger -t mac80211.sh "Running full reload cleanup for $phy"
	mac80211_reset_config "$phy"

	for pidfile in /var/run/hostapd-${phy}-ap*.pid; do
		[ -f "$pidfile" ] || continue

		pid="$(cat "$pidfile" 2>/dev/null)"
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			logger -t mac80211.sh "Stopping hostapd before reload on $phy: pid=$pid"
			kill "$pid" 2>/dev/null
			sleep 1
			if kill -0 "$pid" 2>/dev/null; then
				kill -9 "$pid" 2>/dev/null
				sleep 1
			fi
		fi

		rm -f "$pidfile"
	done

	ps | grep "[h]ostapd" | grep "${phy}-ap" | while read pid _rest; do
		[ -n "$pid" ] || continue
		kill "$pid" 2>/dev/null
	done

	for wdev in $(list_phy_interfaces "$phy"); do
		ip link set dev "$wdev" down 2>/dev/null
	done

	sleep 1
}

drv_mac80211_setup() {
	json_select config
	json_get_vars \
		phy path \
		country chanbw distance \
		txpower \
		rxantenna txantenna \
		frag rts beacon_int:100 htmode \
		num_global_macaddr:1 multiple_bssid
	json_get_values basic_rate_list basic_rate
	json_get_values scan_list scan_list
	json_select ..

	local macaddr
	json_select interfaces 2>/dev/null && {
		local _ifaces _iface _type _found
		json_get_keys _ifaces
		for _iface in $_ifaces; do
			json_select "$_iface" 2>/dev/null || continue
			json_select config 2>/dev/null || { json_select ..; continue; }
			json_get_var _type mode
			[ "$_type" = "ap" -a -z "$_found" ] && {
				json_get_var macaddr macaddr
				_found=1
			}
			json_select ..
			json_select ..
			[ -n "$_found" ] && break
		done
		json_select ..
	}

	json_select data && {
		json_get_var prev_phy phy
		json_get_var prev_channel channel
		json_get_var prev_band band
		json_get_var prev_htmode htmode
		json_get_var prev_country country
		json_get_var prev_chanbw chanbw
		json_get_var prev_rxantenna rxantenna
		json_get_var prev_txantenna txantenna
		json_get_var prev_macaddr macaddr
		json_select ..
	}

	find_phy || {
		echo "Could not find PHY for device '$1'"
		wireless_set_retry 0
		return 1
	}

	case "$phy" in
  		phy0)
			[ "$band" = "2g" ] || { echo "force band=2g for $phy"; band=2g; }
		;;
		phy1)
			[ "$band" = "5g" ] || { echo "force band=5g for $phy"; band=5g; }
		;;
		phy2)
			[ "$band" = "6g" ] || { echo "force band=6g for $phy"; band=6g; }
		;;
	esac

	local wdev
	local cwdev
	local found

	# convert channel to frequency
	[ "$auto_channel" -gt 0 ] || freq="$(get_freq "$phy" "$channel" "$band")"

	[ -n "$country" ] && {
		iw reg get | grep -q "^country $country:" || {
			iw reg set "$country"
			sleep 1
		}
	}

	hostapd_conf_file="/var/run/hostapd-$phy.conf"

	macidx=0
	staidx=0

	[ "$phy" = "phy1" ] && macidx=20
	[ "$phy" = "phy2" ] && macidx=40

	[ -n "$chanbw" ] && {
		for file in /sys/kernel/debug/ieee80211/$phy/ath9k*/chanbw /sys/kernel/debug/ieee80211/$phy/ath5k/bwmode; do
			[ -f "$file" ] && echo "$chanbw" > "$file"
		done
	}

	set_default rxantenna 0xffffffff
	set_default txantenna 0xffffffff
	set_default distance 0

	[ "$txantenna" = "all" ] && txantenna=0xffffffff
	[ "$rxantenna" = "all" ] && rxantenna=0xffffffff

	if mac80211_device_needs_restart "$phy"; then
		mac80211_force_phy_reload "$phy"
	fi

	[ "$rxantenna" = "$prev_rxantenna" -a "$txantenna" = "$prev_txantenna" ] || mac80211_reset_config "$phy"
	wireless_set_data \
		phy="$phy" \
		channel="${channel:-}" \
		band="${band:-}" \
		htmode="${htmode:-}" \
		country="${country:-}" \
		chanbw="${chanbw:-}" \
		macaddr="${macaddr:-}" \
		txantenna="$txantenna" \
		rxantenna="$rxantenna"

	iw phy "$phy" set antenna $txantenna $rxantenna >/dev/null 2>&1
	iw phy "$phy" set distance "$distance" >/dev/null 2>&1

	if [ -n "$txpower" ]; then
		iw phy "$phy" set txpower fixed "${txpower%%.*}00"
	else
		iw phy "$phy" set txpower auto
	fi

	[ -n "$frag" ] && iw phy "$phy" set frag "${frag%%.*}"
	[ -n "$rts" ] && iw phy "$phy" set rts "${rts%%.*}"

	has_ap=
	has_sta=
	hostapd_ctrl=
	ap_ifname=
	hostapd_noscan=
	wpa_supp_init=
	for_each_interface "ap" mac80211_check_ap
	for_each_interface "sta" mac80211_check_sta

	# 不再需要备份旧配置文件，mtk_wifi_config.sh 会直接生成新的
	# [ -f "$hostapd_conf_file" ] && mv "$hostapd_conf_file" "$hostapd_conf_file.prev"

	for_each_interface "sta adhoc mesh" mac80211_set_noscan
	[ -n "$has_ap" ] && mac80211_hostapd_setup_base "$phy"
	# 注意：原来的 mac80211_hostapd_setup_base 在这里被调用，但现在我们移到后面
	# 因为需要先准备好所有接口信息

	local prev
	json_set_namespace wdev_uc prev
	json_init
	json_set_namespace "$prev"

	wpa_supplicant_init_config

	mac80211_prepare_iw_htmode
	active_ifnames=
	mac80211_append_reserved_ifnames "$phy"
	for_each_interface "ap sta adhoc mesh monitor" mac80211_prepare_vif
	for_each_interface "ap sta adhoc mesh monitor" mac80211_setup_vif

	# 使用 mtk_wifi_config.sh 生成 DAT 和 hostapd 配置（在所有接口准备完成后）
	# 替换原来的 mac80211_hostapd_setup_base 逻辑
	logger -t mac80211.sh "has_ap=$has_ap has_sta=$has_sta, calling mtk_wifi_config functions"
	local hostapd_lock_acquired=
	[ -n "$has_ap" -o -n "$has_sta" ] && {
		if mac80211_acquire_hostapd_lock "$phy"; then
			hostapd_lock_acquired=1
		else
			logger -t mac80211.sh "WARNING: continue without hostapd lock on $phy"
		fi

		logger -t mac80211.sh "Generating DAT configs..."
		generate_dat_from_uci "$phy" || logger -t mac80211.sh "ERROR: generate_dat_from_uci failed with code $?"
		[ -n "$has_ap" ] && {
			logger -t mac80211.sh "Generating hostapd configs..."
			generate_hostapd_from_uci_improved "$phy" || logger -t mac80211.sh "ERROR: generate_hostapd_from_uci_improved failed with code $?"
		}
		logger -t mac80211.sh "DAT/hostapd configs generation completed"
	} || {
		logger -t mac80211.sh "WARNING: has_ap and has_sta are empty, skipping config generation"
	}

	#[ -x /usr/sbin/wpa_supplicant ] && wpa_supplicant_set_config "$phy"
	json_set_namespace wdev_uc prev
	wdev_tool "$phy" set_config "$(json_dump)" $active_ifnames
	json_set_namespace "$prev"
	mac80211_create_reserved_ifnames "$phy"
	if [ -n "$has_ap" -a -x /usr/sbin/hostapd ]; then
		hostapd_set_config "$phy"
	fi
	[ -n "$hostapd_lock_acquired" ] && mac80211_release_hostapd_lock

	#[ -x /usr/sbin/wpa_supplicant ] && wpa_supplicant_start "$phy"

	for_each_interface "sta" mac80211_start_sta_vif
	wireless_set_up
}

_list_phy_interfaces() {
	local phy="$1"
	if [ -d "/sys/class/ieee80211/${phy}/device/net" ]; then
		ls "/sys/class/ieee80211/${phy}/device/net" 2>/dev/null;
	else
		ls "/sys/class/ieee80211/${phy}/device" 2>/dev/null | grep net: | sed -e 's,net:,,g'
	fi
}

list_phy_interfaces() {
	local phy="$1"

	for dev in $(_list_phy_interfaces "$phy"); do
		readlink "/sys/class/net/${dev}/phy80211" | grep -q "/${phy}\$" || continue
		echo "$dev"
	done
}

drv_mac80211_teardown() {
	json_select data
	json_get_vars phy
	json_select ..
	[ -n "$phy" ] || {
		echo "Bug: PHY is undefined for device '$1'"
		return 1
	}

	mac80211_reset_config "$phy"

	for wdev in $(list_phy_interfaces "$phy"); do
		ip link set dev "$wdev" down
	done
}

add_driver mac80211
