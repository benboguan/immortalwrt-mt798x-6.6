#!/bin/sh

. /lib/functions/system.sh

# 
# 此脚本来自白菜
#
# MediaTek WiFi 配置生成器 - 纯 Shell 版本
# 将 mtkdat.lua 中的逻辑转换为 Shell 脚本
# 
# 此脚本可以作为函数库被 source，也可以作为独立脚本运行
# 当被 source 时，只定义函数，不执行主程序逻辑

MTK_RESERVED_AP_BSSID_NUM="${MTK_RESERVED_AP_BSSID_NUM:-4}"
MTK_RESERVED_APCLI_NUM="${MTK_RESERVED_APCLI_NUM:-1}"
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

# 检查是否被 source（当被 source 时，$0 通常是调用它的 shell，而不是脚本名）
# 如果 $0 包含 "mtk_wifi_config.sh" 或脚本路径，说明是直接执行
_is_sourced() {
    # 如果 $0 是脚本名或包含脚本路径，说明是直接执行
    case "$0" in
        *mtk_wifi_config.sh|*/mtk_wifi_config.sh|./mtk_wifi_config.sh|mtk_wifi_config.sh)
            return 1  # 直接执行
            ;;
        *)
            # 被 source 时，$0 通常是调用它的 shell（如 -sh, bash, sh 等）
            return 0  # 被 source
            ;;
    esac
}

# 只有在直接执行时才显示标题和创建目录
if ! _is_sourced; then
    echo "=== MediaTek WiFi 配置生成器 (纯 Shell 版本) ==="
    
    # 创建必要目录
    mkdir -p /var/run/hostapd
    mkdir -p /tmp/mtk/wifi
    mkdir -p /etc/wireless
fi

# 通用工具函数
exists() {
    [ -e "$1" ]
}

# 检查配置是否变化（模拟 mtkdat.cfg_is_diff）
cfg_is_diff() {
    local uci_cfg_file="/etc/config/wireless"
    local last_cfg_file="/tmp/mtk/wifi/wireless.last"
    
    # 如果上次保存的配置不存在，则认为有变化
    if ! exists "$last_cfg_file"; then
        return 0  # 有变化
    fi
    
    # 比较当前配置和上次保存的配置
    if cmp -s "$uci_cfg_file" "$last_cfg_file"; then
        return 1  # 无变化
    else
        return 0  # 有变化
    fi
}

# 保存当前配置为上次配置
cfg_save_current() {
    local uci_cfg_file="/etc/config/wireless"
    local last_cfg_file="/tmp/mtk/wifi/wireless.last"
    
    # 创建目录
    mkdir -p "/tmp/mtk/wifi"
    
    # 复制当前配置到上次配置文件
    cp "$uci_cfg_file" "$last_cfg_file" 2>/dev/null || return 1
}

# 从 UCI 读取配置的函数
generate_uci_vif_by_vif_name() {
    local uci_cfg="$1"
    local vif_name="$2"
    
    # 遍历所有 wifi-iface 段以查找匹配的名称
    for iface_name in $(echo "$uci_cfg" | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        local name=$(echo "$uci_cfg" | grep "^wireless\\.$iface_name\\.\\.name=" | cut -d'=' -f2-)
        if [ -z "$name" ]; then
            name="$iface_name"  # 如果没有显式指定.name，则使用段名
        fi
        
        if [ "$name" = "$vif_name" ]; then
            # 返回整个接口配置
            echo "$uci_cfg" | grep "^wireless\\.$iface_name\\."
            return 0
        fi
    done
    return 1
}

get_uci_value() {
    local section_type="$1"
    local section_name="$2"
    local option="$3"
    uci -q get wireless.${section_name}.${option} 2>/dev/null
}

# 获取 DAT 文件路径的函数
get_dat_file() {
    local band="$1" dat_file=""

    # 配置文件不存在则直接返回失败
    [ -f "$DAT_PATH" ] || return 1

    # 统一转换为小写，用 case 匹配
    case "$(echo "$band" | tr '[:upper:]' '[:lower:]')" in
        2g|2.4g) dat_file=$(grep "^BN0_profile_path=" "$DAT_PATH" | awk -F= '{print $2}') ;;
        5g)      dat_file=$(grep "^BN1_profile_path=" "$DAT_PATH" | awk -F= '{print $2}') ;;
        6g)      dat_file=$(grep "^BN2_profile_path=" "$DAT_PATH" | awk -F= '{print $2}') ;;
        *)       return 1 ;;
    esac

    # 确认提取到内容，输出并返回成功
    if [ -n "$dat_file" ]; then
        echo "$dat_file"
        return 0
    fi
    
    return 1
}

set_dat_mac_address() {
    local dat_file="$1"
    local band="$2"
    local wifi_mac

    [ -n "$dat_file" ] || return 0

    wifi_mac="$(get_default_bssid_mac "$band" 1)"
    [ -n "$wifi_mac" ] || return 0

    sed -i '/^MacAddress=/d' "$dat_file" 2>/dev/null
    echo "MacAddress=$wifi_mac" >> "$dat_file"
}

get_default_bssid_mac() {
    local band="$1"
    local bssid_index="${2:-1}"
    local lan_mac wifi_mac band_lower step

    lan_mac="$(macaddr_generate_from_mmc_cid mmcblk0 2>/dev/null)"
    [ -n "$lan_mac" ] || return 1

    wifi_mac="$(macaddr_add "$lan_mac" 2)"
    [ -n "$wifi_mac" ] || return 1

    band_lower="$(echo "$band" | tr '[:upper:]' '[:lower:]')"
    case "$band_lower" in
        6g)
            wifi_mac="$(macaddr_add "$wifi_mac" 2)"
            ;;
        5g)
            wifi_mac="$(macaddr_add "$wifi_mac" 1)"
            ;;
    esac

    step=1
    while [ "$step" -lt "$bssid_index" ]; do
        wifi_mac="$(macaddr_add "$wifi_mac" 1)"
        [ -n "$wifi_mac" ] || return 1
        step=$((step + 1))
    done

    echo "$wifi_mac"
    return 0
}

# 获取物理接口名的函数
get_physical_ifname() {
    local iface_name="$1"
    local device="$2"
    
    # 首先检查 UCI 配置中是否有 ifname 选项
    local ifname=$(get_uci_value "wifi-iface" "$iface_name" "ifname")
    if [ -n "$ifname" ]; then
        echo "$ifname"
        return
    fi
    
    # 获取设备类型
    local dev_type=$(get_uci_value "wifi-device" "$device" "type")
    
    # 对于 mac80211 类型，尝试从系统中查找
    if [ "$dev_type" = "mac80211" ]; then
        # 方法1: 根据设备索引查找（radio0 -> phy0-ap0, radio1 -> phy1-ap0）
        local dev_idx=0
        for dev_name in $(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1 | sort); do
            if [ "$dev_name" = "$device" ]; then
                # 尝试查找 phy${dev_idx}-ap0
                local candidate="phy${dev_idx}-ap0"
                if [ -e "/sys/class/net/$candidate" ]; then
                    echo "$candidate"
                    return
                fi
                # 如果找不到 ap0，尝试其他 ap 索引
                local ap_idx=1
                while [ $ap_idx -le 15 ]; do
                    candidate="phy${dev_idx}-ap${ap_idx}"
                    if [ -e "/sys/class/net/$candidate" ]; then
                        echo "$candidate"
                        return
                    fi
                    ap_idx=$((ap_idx + 1))
                done
            fi
            dev_idx=$((dev_idx + 1))
        done
        
        # 方法2: 获取设备的 phy，然后查找对应的接口
        local phy=$(get_uci_value "wifi-device" "$device" "phy")
        if [ -n "$phy" ]; then
            # 如果 phy 是 phy0, phy1 等格式，尝试查找 phyX-ap0 格式的接口
            if echo "$phy" | grep -qE '^phy[0-9]+$'; then
                local phy_num=$(echo "$phy" | sed 's/phy//')
                local ap_idx=0
                while [ $ap_idx -le 15 ]; do
                    local candidate="phy${phy_num}-ap${ap_idx}"
                    if [ -e "/sys/class/net/$candidate" ]; then
                        echo "$candidate"
                        return
                    fi
                    ap_idx=$((ap_idx + 1))
                done
            fi
            
            # 方法3: 从 /sys/class/net/ 查找与该 phy 关联的接口
            for netdev in /sys/class/net/*; do
                local netdev_name=$(basename "$netdev")
                # 跳过回环、桥接和以太网接口
                case "$netdev_name" in
                    lo|br-*|eth*|hnat)
                        continue
                        ;;
                esac
                
                # 检查接口是否属于该 phy
                if [ -e "$netdev/phy80211/name" ]; then
                    local phy_name=$(cat "$netdev/phy80211/name" 2>/dev/null | tr -d '\n')
                    if [ "$phy_name" = "$phy" ]; then
                        echo "$netdev_name"
                        return
                    fi
                fi
            done
        fi
        
        # 方法4: 根据 path 查找
        local path=$(get_uci_value "wifi-device" "$device" "path")
        if [ -n "$path" ]; then
            # 尝试从 /sys/class/ieee80211/ 查找匹配的 phy
            for phy_dir in /sys/class/ieee80211/*; do
                if [ ! -d "$phy_dir" ]; then
                    continue
                fi
                local phy_name=$(basename "$phy_dir")
                if command -v iwinfo >/dev/null 2>&1; then
                    local phy_path=$(iwinfo nl80211 path "$phy_name" 2>/dev/null)
                    if [ "$phy_path" = "$path" ]; then
                        # 找到了匹配的 phy，查找对应的接口
                        local phy_num=$(echo "$phy_name" | sed 's/phy//')
                        local ap_idx=0
                        while [ $ap_idx -le 15 ]; do
                            local candidate="phy${phy_num}-ap${ap_idx}"
                            if [ -e "/sys/class/net/$candidate" ]; then
                                echo "$candidate"
                                return
                            fi
                            ap_idx=$((ap_idx + 1))
                        done
                    fi
                fi
            done
        fi
    fi
    
    # 对于 mtkwifi 类型，接口名通常是 ra0, ra1 等
    if [ "$dev_type" = "mtkwifi" ]; then
        local dev_idx=0
        for dev_name in $(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1 | sort); do
            if [ "$dev_name" = "$device" ]; then
                # 检查接口是否存在
                if [ -e "/sys/class/net/ra${dev_idx}" ]; then
                    echo "ra${dev_idx}"
                    return
                fi
            fi
            dev_idx=$((dev_idx + 1))
        done
    fi
    
    # 如果都找不到，尝试列出所有可能的接口并选择第一个匹配的
    for netdev in /sys/class/net/*; do
        local netdev_name=$(basename "$netdev")
        case "$netdev_name" in
            lo|br-*|eth*|hnat)
                continue
                ;;
            phy*-ap*|ra*|wlan*)
                # 对于 phyX-apY 格式，直接返回
                if echo "$netdev_name" | grep -qE '^phy[0-9]+-ap[0-9]+$'; then
                    echo "$netdev_name"
                    return
                fi
                ;;
        esac
    done
    
    # 如果都找不到，返回 UCI 接口名（虽然可能不正确，但至少不会导致脚本失败）
    echo "$iface_name"
}

# 参数映射函数：将 wireless-old 格式的参数转换为 mtkwifi 格式
map_band_value() {
    local band="$1"
    case "$band" in
        "2g"|"2G")
            echo "2.4G"
            ;;
        "5g"|"5G")
            echo "5G"
            ;;
        "6g"|"6G")
            echo "6G"
            ;;
        *)
            echo "${band:-2.4G}"
            ;;
    esac
}

# 根据 htmode 和 band 计算 wireless_mode、bw 和 ht_extcha
# 参考 mtkdat.lua 的 htmode2bw 函数（行 2291-2425）
# 返回值：通过全局变量返回 wireless_mode、bw、ht_extcha
# 使用方式：
#   htmode2wireless_mode "HE160" "5G"
#   echo "wireless_mode=$htmode2wireless_mode_result_wireless_mode"
#   echo "bw=$htmode2wireless_mode_result_bw"
#   echo "ht_extcha=$htmode2wireless_mode_result_ht_extcha"
htmode2wireless_mode() {
    local htmode="$1"
    local band="$2"
    local pure_11b="${3:-0}"  # 可选参数，默认为 0
    
    # 规范化 band 值
    local mapped_band=$(map_band_value "$band")
    
    # 规范化 htmode 值（转换为大写）
    local htmode_upper=$(echo "$htmode" | tr '[:lower:]' '[:upper:]')
    
    # 初始化返回值
    htmode2wireless_mode_result_wireless_mode=""
    htmode2wireless_mode_result_bw=""
    htmode2wireless_mode_result_ht_extcha="0"
    
    case "$htmode_upper" in
        "NOHT")
            case "$mapped_band" in
                "2.4G"|"2G")
                    if [ "$pure_11b" = "1" ]; then
                        htmode2wireless_mode_result_wireless_mode="1"  # PHY_11B
                    else
                        htmode2wireless_mode_result_wireless_mode="0"  # PHY_11BG_MIXED
                    fi
                    htmode2wireless_mode_result_bw="20"
                    ;;
                "5G")
                    htmode2wireless_mode_result_wireless_mode="2"  # PHY_11A
                    htmode2wireless_mode_result_bw="20"
                    ;;
            esac
            ;;
        "HT20")
            case "$mapped_band" in
                "2.4G"|"2G")
                    htmode2wireless_mode_result_wireless_mode="9"  # PHY_11BGN_MIXED
                    htmode2wireless_mode_result_bw="20"
                    ;;
                "5G")
                    htmode2wireless_mode_result_wireless_mode="8"  # PHY_11AN_MIXED
                    htmode2wireless_mode_result_bw="20"
                    ;;
            esac
            ;;
        "HT40")
            case "$mapped_band" in
                "2.4G"|"2G")
                    htmode2wireless_mode_result_wireless_mode="9"  # PHY_11BGN_MIXED
                    htmode2wireless_mode_result_bw="40"
                    htmode2wireless_mode_result_ht_extcha="1"  # 默认使用上边带
                    ;;
                "5G")
                    htmode2wireless_mode_result_wireless_mode="8"  # PHY_11AN_MIXED
                    htmode2wireless_mode_result_bw="40"
                    htmode2wireless_mode_result_ht_extcha="1"  # 默认使用上边带
                    ;;
            esac
            ;;
        "HT40-")
            case "$mapped_band" in
                "2.4G"|"2G")
                    htmode2wireless_mode_result_wireless_mode="9"  # PHY_11BGN_MIXED
                    htmode2wireless_mode_result_bw="40"
                    htmode2wireless_mode_result_ht_extcha="0"
                    ;;
                "5G")
                    htmode2wireless_mode_result_wireless_mode="8"  # PHY_11AN_MIXED
                    htmode2wireless_mode_result_bw="40"
                    htmode2wireless_mode_result_ht_extcha="0"
                    ;;
            esac
            ;;
        "HT40+")
            case "$mapped_band" in
                "2.4G"|"2G")
                    htmode2wireless_mode_result_wireless_mode="9"  # PHY_11BGN_MIXED
                    htmode2wireless_mode_result_bw="40"
                    htmode2wireless_mode_result_ht_extcha="1"
                    ;;
                "5G")
                    htmode2wireless_mode_result_wireless_mode="8"  # PHY_11AN_MIXED
                    htmode2wireless_mode_result_bw="40"
                    htmode2wireless_mode_result_ht_extcha="1"
                    ;;
            esac
            ;;
        "VHT20")
            if [ "$mapped_band" = "5G" ]; then
                htmode2wireless_mode_result_wireless_mode="14"  # PHY_11VHT_N_A_MIXED
                htmode2wireless_mode_result_bw="20"
            fi
            ;;
        "VHT40")
            if [ "$mapped_band" = "5G" ]; then
                htmode2wireless_mode_result_wireless_mode="14"  # PHY_11VHT_N_A_MIXED
                htmode2wireless_mode_result_bw="40"
            fi
            ;;
        "VHT80")
            if [ "$mapped_band" = "5G" ]; then
                htmode2wireless_mode_result_wireless_mode="14"  # PHY_11VHT_N_A_MIXED
                htmode2wireless_mode_result_bw="80"
            fi
            ;;
        "VHT80_80"|"VHT8080")
            if [ "$mapped_band" = "5G" ]; then
                htmode2wireless_mode_result_wireless_mode="14"  # PHY_11VHT_N_A_MIXED
                htmode2wireless_mode_result_bw="161"
            fi
            ;;
        "VHT160")
            if [ "$mapped_band" = "5G" ]; then
                htmode2wireless_mode_result_wireless_mode="14"  # PHY_11VHT_N_A_MIXED
                htmode2wireless_mode_result_bw="160"
            fi
            ;;
        "HE20")
            case "$mapped_band" in
                "2.4G"|"2G")
                    htmode2wireless_mode_result_wireless_mode="16"  # PHY_11AX_24G
                    htmode2wireless_mode_result_bw="20"
                    ;;
                "5G")
                    htmode2wireless_mode_result_wireless_mode="17"  # PHY_11AX_5G
                    htmode2wireless_mode_result_bw="20"
                    ;;
                "6G")
                    htmode2wireless_mode_result_wireless_mode="18"  # PHY_11AX_6G
                    htmode2wireless_mode_result_bw="20"
                    ;;
            esac
            ;;
        "HE40")
            case "$mapped_band" in
                "2.4G"|"2G")
                    htmode2wireless_mode_result_wireless_mode="16"  # PHY_11AX_24G
                    htmode2wireless_mode_result_bw="40"
                    ;;
                "5G")
                    htmode2wireless_mode_result_wireless_mode="17"  # PHY_11AX_5G
                    htmode2wireless_mode_result_bw="40"
                    ;;
                "6G")
                    htmode2wireless_mode_result_wireless_mode="18"  # PHY_11AX_6G
                    htmode2wireless_mode_result_bw="40"
                    ;;
            esac
            ;;
        "HE80")
            case "$mapped_band" in
                "5G")
                    htmode2wireless_mode_result_wireless_mode="17"  # PHY_11AX_5G
                    htmode2wireless_mode_result_bw="80"
                    ;;
                "6G")
                    htmode2wireless_mode_result_wireless_mode="18"  # PHY_11AX_6G
                    htmode2wireless_mode_result_bw="80"
                    ;;
            esac
            ;;
        "HE160")
            case "$mapped_band" in
                "5G")
                    htmode2wireless_mode_result_wireless_mode="17"  # PHY_11AX_5G
                    htmode2wireless_mode_result_bw="160"
                    ;;
                "6G")
                    htmode2wireless_mode_result_wireless_mode="18"  # PHY_11AX_6G
                    htmode2wireless_mode_result_bw="160"
                    ;;
            esac
            ;;
        "HE320")
            # HE320 在 mtkdat.lua 中没有定义，但根据逻辑应该是 HE160 的扩展
            case "$mapped_band" in
                "5G")
                    htmode2wireless_mode_result_wireless_mode="17"  # PHY_11AX_5G
                    htmode2wireless_mode_result_bw="320"
                    ;;
                "6G")
                    htmode2wireless_mode_result_wireless_mode="18"  # PHY_11AX_6G
                    htmode2wireless_mode_result_bw="320"
                    ;;
            esac
            ;;
        "EHT20")
            case "$mapped_band" in
                "2.4G"|"2G")
                    htmode2wireless_mode_result_wireless_mode="22"  # PHY_11BE_24G
                    htmode2wireless_mode_result_bw="20"
                    ;;
                "5G")
                    htmode2wireless_mode_result_wireless_mode="23"  # PHY_11BE_5G
                    htmode2wireless_mode_result_bw="20"
                    ;;
                "6G")
                    htmode2wireless_mode_result_wireless_mode="24"  # PHY_11BE_6G
                    htmode2wireless_mode_result_bw="20"
                    ;;
            esac
            ;;
        "EHT40")
            case "$mapped_band" in
                "2.4G"|"2G")
                    htmode2wireless_mode_result_wireless_mode="22"  # PHY_11BE_24G
                    htmode2wireless_mode_result_bw="40"
                    ;;
                "5G")
                    htmode2wireless_mode_result_wireless_mode="23"  # PHY_11BE_5G
                    htmode2wireless_mode_result_bw="40"
                    ;;
                "6G")
                    htmode2wireless_mode_result_wireless_mode="24"  # PHY_11BE_6G
                    htmode2wireless_mode_result_bw="40"
                    ;;
            esac
            ;;
        "EHT80")
            case "$mapped_band" in
                "5G")
                    htmode2wireless_mode_result_wireless_mode="23"  # PHY_11BE_5G
                    htmode2wireless_mode_result_bw="80"
                    ;;
                "6G")
                    htmode2wireless_mode_result_wireless_mode="24"  # PHY_11BE_6G
                    htmode2wireless_mode_result_bw="80"
                    ;;
            esac
            ;;
        "EHT160")
            case "$mapped_band" in
                "5G")
                    htmode2wireless_mode_result_wireless_mode="23"  # PHY_11BE_5G
                    htmode2wireless_mode_result_bw="160"
                    ;;
                "6G")
                    htmode2wireless_mode_result_wireless_mode="24"  # PHY_11BE_6G
                    htmode2wireless_mode_result_bw="160"
                    ;;
            esac
            ;;
        "EHT320")
            case "$mapped_band" in
                "5G")
                    htmode2wireless_mode_result_wireless_mode="23"  # PHY_11BE_5G
                    htmode2wireless_mode_result_bw="320"
                    ;;
                "6G")
                    htmode2wireless_mode_result_wireless_mode="24"  # PHY_11BE_6G
                    htmode2wireless_mode_result_bw="320"
                    htmode2wireless_mode_result_ht_extcha="0"
                    ;;
            esac
            ;;
        "EHT320-2")
            if [ "$mapped_band" = "6G" ]; then
                htmode2wireless_mode_result_wireless_mode="24"  # PHY_11BE_6G
                htmode2wireless_mode_result_bw="320"
                htmode2wireless_mode_result_ht_extcha="1"
            fi
            ;;
    esac
    
    # 如果未匹配到任何模式，设置默认值
    if [ -z "$htmode2wireless_mode_result_wireless_mode" ]; then
        case "$mapped_band" in
            "2.4G"|"2G")
                htmode2wireless_mode_result_wireless_mode="22"  # PHY_11BE_24G (默认使用最新的)
                htmode2wireless_mode_result_bw="40"
                ;;
            "5G")
                htmode2wireless_mode_result_wireless_mode="23"  # PHY_11BE_5G (默认使用最新的)
                htmode2wireless_mode_result_bw="160"
                ;;
            "6G")
                htmode2wireless_mode_result_wireless_mode="24"  # PHY_11BE_6G (默认使用最新的)
                htmode2wireless_mode_result_bw="160"
                ;;
            *)
                htmode2wireless_mode_result_wireless_mode="9"  # PHY_11BGN_MIXED (最保守的默认值)
                htmode2wireless_mode_result_bw="20"
                ;;
        esac
    fi
}

# 映射 htmode：将 HE40/HE160 等转换为 HT40-/VHT80 等
map_htmode_value() {
    local htmode="$1"
    local band="$2"
    
    case "$htmode" in
        "NOHT"|"noht")
            echo "NOHT"
            ;;
        "HT20"|"ht20")
            echo "HT20"
            ;;
        "HT40"|"ht40")
            if [ "$band" = "2.4G" ] || [ "$band" = "2g" ] || [ "$band" = "2G" ]; then
                echo "HT40-"
            else
                echo "HT40"
            fi
            ;;
        "HT40+"|"ht40+")
            echo "HT40+"
            ;;
        "HT40-"|"ht40-")
            echo "HT40-"
            ;;
        "VHT20"|"vht20")
            echo "VHT20"
            ;;
        "VHT40"|"vht40")
            echo "VHT40"
            ;;
        "VHT80"|"vht80")
            echo "VHT80"
            ;;
        "VHT160"|"vht160")
            echo "VHT160"
            ;;
        "HE20"|"he20")
            echo "HE20"
            ;;
        "HE40"|"he40")
            # HE40 保持原值，不映射
            echo "HE40"
            ;;
        "HE80"|"he80")
            echo "HE80"
            ;;
        "HE160"|"he160")
            echo "HE160"
            ;;
        "HE320"|"he320")
            echo "HE320"
            ;;
        "EHT20"|"eht20")
            echo "EHT20"
            ;;
        "EHT40"|"eht40")
            echo "EHT40"
            ;;
        "EHT80"|"eht80")
            echo "EHT80"
            ;;
        "EHT160"|"eht160")
            echo "EHT160"
            ;;
        *)
            echo "${htmode:-HT20}"
            ;;
    esac
}

get_uci_section_values() {
    local section_type="$1"
    local section_name="$2"
    
    uci -q show wireless.${section_name} 2>/dev/null | grep "^wireless\\.${section_name}\\." || return 1
}

# 字符串分割函数（模拟 mtkdat.split）
split_string() {
    local s="$1"
    local delimiter="$2"
    local pos=1
    local current_part=""
    local char
    
    for i in $(seq 1 ${#s}); do
        char=$(echo "$s" | cut -c$i)
        if [ "$char" = "$delimiter" ]; then
            echo "$current_part"
            current_part=""
        else
            current_part="$current_part$char"
        fi
    done
    [ -n "$current_part" ] && echo "$current_part"
}

trim_string() {
    local s="$1"
    # 移除前导空格
    while [ "${s#?}" != "$s" ]; do
        if [ "${s%?}" = "${s#?}" ]; then
            s="${s#?}"
        else
            break
        fi
    done
    # 移除尾随空格
    while [ "${s%?}" != "$s" ]; do
        if [ "${s#?}" = "${s%?}" ]; then
            s="${s%?}"
        else
            break
        fi
    done
    echo "$s"
}

# 从 UCI 配置生成详细的 DAT 配置
generate_dat_from_uci() {
    local target_phy="$1"
    echo "🔍 正在从 UCI 配置生成详细 DAT 配置..."
    [ -n "$target_phy" ] && logger -t mtk_wifi_config "Generate DAT for target phy: $target_phy"

    # 读取无线设备配置
    for dev_name in $(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1); do
        local dev_phy=""
        local dev_idx=0
        local dev_iter
        for dev_iter in $(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1 | sort); do
            if [ "$dev_iter" = "$dev_name" ]; then
                dev_phy="phy${dev_idx}"
                break
            fi
            dev_idx=$((dev_idx + 1))
        done
        [ -z "$dev_phy" ] && dev_phy="phy0"

        # 只处理目标 phy，避免不同 radio 的 reload 互相覆盖 DAT
        [ -n "$target_phy" ] && [ "$target_phy" != "$dev_phy" ] && continue

        local dev_type=$(get_uci_value "wifi-device" "$dev_name" "type")
        # 支持 mac80211 和 mtkwifi 类型（wireless-old 格式使用 mac80211）
        if [ "$dev_type" = "mtkwifi" ] || [ "$dev_type" = "mac80211" ]; then
            echo "处理设备: $dev_name (类型: $dev_type)"
            
            # 获取设备参数
            local txpower=$(get_uci_value "wifi-device" "$dev_name" "txpower")
            local channel=$(get_uci_value "wifi-device" "$dev_name" "channel")
            local beacon_int=$(get_uci_value "wifi-device" "$dev_name" "beacon_int")
            local txpreamble=$(get_uci_value "wifi-device" "$dev_name" "txpreamble")
            local ht_extcha=$(get_uci_value "wifi-device" "$dev_name" "ht_extcha")
            local ht_txstream=$(get_uci_value "wifi-device" "$dev_name" "ht_txstream")
            local ht_rxstream=$(get_uci_value "wifi-device" "$dev_name" "ht_rxstream")
            local shortslot=$(get_uci_value "wifi-device" "$dev_name" "shortslot")
            local ht_distkip=$(get_uci_value "wifi-device" "$dev_name" "ht_distkip")
            local bgprotect=$(get_uci_value "wifi-device" "$dev_name" "bgprotect")
            local txburst=$(get_uci_value "wifi-device" "$dev_name" "txburst")
            local region=$(get_uci_value "wifi-device" "$dev_name" "region")
            local country=$(get_uci_value "wifi-device" "$dev_name" "country")
            local aregion=$(get_uci_value "wifi-device" "$dev_name" "aregion")
            local e2p_accessmode=$(get_uci_value "wifi-device" "$dev_name" "e2p_accessmode")
            local map_mode=$(get_uci_value "wifi-device" "$dev_name" "map_mode")
            local dbdc_mode=$(get_uci_value "wifi-device" "$dev_name" "dbdc_mode")
            local etxbfencond=$(get_uci_value "wifi-device" "$dev_name" "etxbfencond")
            local itxbfen=$(get_uci_value "wifi-device" "$dev_name" "itxbfen")
            local mu_beamformer=$(get_uci_value "wifi-device" "$dev_name" "mu_beamformer")
            local mutxrx_enable=$(get_uci_value "wifi-device" "$dev_name" "mutxrx_enable")
            local bss_color=$(get_uci_value "wifi-device" "$dev_name" "bss_color")
            local twt_support=$(get_uci_value "wifi-device" "$dev_name" "twt_support")
            local dfs_enable=$(get_uci_value "wifi-device" "$dev_name" "dfs_enable")
            local sr_mode=$(get_uci_value "wifi-device" "$dev_name" "sr_mode")
            local sre_enable=$(get_uci_value "wifi-device" "$dev_name" "sre_enable")
            local powerup_cckofdm=$(get_uci_value "wifi-device" "$dev_name" "powerup_cckofdm")
            local powerup_ht20=$(get_uci_value "wifi-device" "$dev_name" "powerup_ht20")
            local powerup_ht40=$(get_uci_value "wifi-device" "$dev_name" "powerup_ht40")
            local powerup_vht20=$(get_uci_value "wifi-device" "$dev_name" "powerup_vht20")
            local powerup_vht40=$(get_uci_value "wifi-device" "$dev_name" "powerup_vht40")
            local powerup_vht80=$(get_uci_value "wifi-device" "$dev_name" "powerup_vht80")
            local powerup_vht160=$(get_uci_value "wifi-device" "$dev_name" "powerup_vht160")
            local vow_airtime_fairness_en=$(get_uci_value "wifi-device" "$dev_name" "vow_airtime_fairness_en")
            local ht_rdg=$(get_uci_value "wifi-device" "$dev_name" "ht_rdg")
            local vow_bw_ctrl=$(get_uci_value "wifi-device" "$dev_name" "vow_bw_ctrl")
            local vow_ex_en=$(get_uci_value "wifi-device" "$dev_name" "vow_ex_en")
            local doth=$(get_uci_value "wifi-device" "$dev_name" "doth")
            local rd_region=$(get_uci_value "wifi-device" "$dev_name" "rd_region")
            local dfs_slave=$(get_uci_value "wifi-device" "$dev_name" "dfs_slave")
            local cp_support=$(get_uci_value "wifi-device" "$dev_name" "cp_support")
            local percentag_enable=$(get_uci_value "wifi-device" "$dev_name" "percentag_enable")
            local autoch=$(get_uci_value "wifi-device" "$dev_name" "autoch")
            local ht_coex=$(get_uci_value "wifi-device" "$dev_name" "ht_coex")
            local htmode=$(get_uci_value "wifi-device" "$dev_name" "htmode")
            local band=$(get_uci_value "wifi-device" "$dev_name" "band")
            local disabled=$(get_uci_value "wifi-device" "$dev_name" "disabled")
            
            # ACS (Auto Channel Selection) 参数
            local acs_restore_dwell=$(get_uci_value "wifi-device" "$dev_name" "acs_restore_dwell")
            local acs_prio_weight=$(get_uci_value "wifi-device" "$dev_name" "acs_prio_weight")
            local acs_max_acs_times=$(get_uci_value "wifi-device" "$dev_name" "acs_max_acs_times")
            local acs_check_time=$(get_uci_value "wifi-device" "$dev_name" "acs_check_time")
            local acs_scan_mode=$(get_uci_value "wifi-device" "$dev_name" "acs_scan_mode")
            local acs_ice_ch_util_threshold=$(get_uci_value "wifi-device" "$dev_name" "acs_ice_ch_util_threshold")
            local acs_sta_num_threshold=$(get_uci_value "wifi-device" "$dev_name" "acs_sta_num_threshold")
            local acs_ch_util_threshold=$(get_uci_value "wifi-device" "$dev_name" "acs_ch_util_threshold")
            local acs_switch_ch_threshold=$(get_uci_value "wifi-device" "$dev_name" "acs_switch_ch_threshold")
            local acs_data_rate_weight=$(get_uci_value "wifi-device" "$dev_name" "acs_data_rate_weight")
            local acs_scan_dwell=$(get_uci_value "wifi-device" "$dev_name" "acs_scan_dwell")
            local acs_tx_power_cons=$(get_uci_value "wifi-device" "$dev_name" "acs_tx_power_cons")
            local band4_dfs_enable=$(get_uci_value "wifi-device" "$dev_name" "band4_dfs_enable")
            
            # 获取实际的 DAT 文件路径（从 mt799*.1.dat 读取）
            local dat_file=$(get_dat_file "$band")
            
            # 如果无法从配置文件获取，则使用默认路径（设备名.dat）
            if [ -z "$dat_file" ]; then
                dat_file="/etc/wireless/${dev_name}.dat"
                echo "⚠️  无法从配置文件获取 DAT 路径，使用默认路径: $dat_file"
            else
                echo "✅ 从配置文件获取 DAT 路径: $dat_file"
            fi
            echo "#The word of \"Default\" must not be removed" > "$dat_file"
            echo "Default" >> "$dat_file"
            set_dat_mac_address "$dat_file" "$band"
            
            # 初始化配置参数
            # Access Control List 参数
            local i
            i=0
            while [ $i -le 15 ]; do
              echo "AccessControlList$i=" >> "$dat_file"
              echo "AccessPolicy$i=0" >> "$dat_file"
              i=$((i + 1))
            done
            echo "AckPolicy=0;0;0;0" >> "$dat_file"
            echo "APACM=0;0;0;0" >> "$dat_file"
            
            # APAifsn (分号分隔)
            echo "APAifsn=3;7;1;1" >> "$dat_file"
            
            # ApCli 相关参数（参考 mtkdat.lua 行 2935-3008 apcli2cfg 函数）
            echo "ApCliAuthMode=OPEN" >> "$dat_file"
            echo "ApCliBssid=" >> "$dat_file"
            echo "ApCliDefaultKeyID=" >> "$dat_file"
            echo "ApCliEnable=0" >> "$dat_file"
            echo "ApCliEncrypType=NONE" >> "$dat_file"
            echo "ApCliNum=$MTK_RESERVED_APCLI_NUM" >> "$dat_file"
            echo "ApCliSsid=" >> "$dat_file"
            echo "ApCliWirelessMode=" >> "$dat_file"
            echo "ApcliMacAddress=" >> "$dat_file"
            
            # ApCli Keys
            local i
            i=1
            while [ $i -le 4 ]; do
              echo "ApCliKey${i}Str=" >> "$dat_file"
              echo "ApCliKey${i}Str1=" >> "$dat_file"
              echo "ApCliKey${i}Type=" >> "$dat_file"
              i=$((i + 1))
            done
            
            # ApCli WPAPSK
            echo "ApCliWPAPSK=" >> "$dat_file"
            echo "ApCliWPAPSK1=" >> "$dat_file"
            
            # ApCli PMF 相关参数（参考 mtkdat.lua 行 2960-2971）
            # ApCliPMFMFPC 和 ApCliPMFMFPR 在其他地方已初始化，这里不需要重复
            
            # ApCli OWE 和 MAC Repeater（参考 mtkdat.lua 行 2972-2973）
            echo "ApCliOWETranIe=" >> "$dat_file"
            echo "MACRepeaterEn=" >> "$dat_file"
            
            # ApCli SAE Groups（参考 mtkdat.lua 行 2998-3004）
            echo "ApCliSaeGroups=19" >> "$dat_file"
            
            # MU MIMO/OFDMA 参数（根据 WiFi 模式动态设置）
            # MU-MIMO: 支持 802.11ac (VHT, wireless_mode 12-15) 和 802.11ax (HE, wireless_mode 16-21) 和 802.11be (EHT, wireless_mode 22-27)
            # MU-OFDMA: 支持 802.11ax (HE, wireless_mode 16-21) 和 802.11be (EHT, wireless_mode 22-27)
            local apcli_mu_mimo_dl="0"
            local apcli_mu_mimo_ul="0"
            local apcli_mu_ofdma_dl="0"
            local apcli_mu_ofdma_ul="0"
            
            # 根据 htmode 和 band 计算 wireless_mode（使用统一的函数）
            if [ -n "$htmode" ] && [ -n "$band" ]; then
                local mapped_htmode=$(map_htmode_value "$htmode" "$band")
                htmode2wireless_mode "$mapped_htmode" "$band"
                local wireless_mode_val="$htmode2wireless_mode_result_wireless_mode"
                
                # 根据 wireless_mode 设置 MU-MIMO/OFDMA 参数
                if [ -n "$wireless_mode_val" ]; then
                    # MU-MIMO: 支持 VHT (12-15), HE (16-21), EHT (22-27)
                    if [ "$wireless_mode_val" -ge 12 ] && [ "$wireless_mode_val" -le 27 ] 2>/dev/null; then
                        apcli_mu_mimo_dl="1"
                        apcli_mu_mimo_ul="1"
                    fi
                    
                    # MU-OFDMA: 支持 HE (16-21), EHT (22-27)
                    if [ "$wireless_mode_val" -ge 16 ] && [ "$wireless_mode_val" -le 27 ] 2>/dev/null; then
                        apcli_mu_ofdma_dl="1"
                        apcli_mu_ofdma_ul="1"
                    fi
                fi
            fi
            
            echo "ApCliMuOfdmaDlEnable=$apcli_mu_ofdma_dl" >> "$dat_file"
            echo "ApCliMuOfdmaUlEnable=$apcli_mu_ofdma_ul" >> "$dat_file"
            echo "ApCliMuMimoDlEnable=$apcli_mu_mimo_dl" >> "$dat_file"
            echo "ApCliMuMimoUlEnable=$apcli_mu_mimo_ul" >> "$dat_file"
            
            # AP CW Parameters (分号分隔)
            echo "APCwmax=6;10;4;3" >> "$dat_file"
            echo "APCwmin=4;4;3;2" >> "$dat_file"
            
            # APSDCapable is per-BSSID token in mtkdat.lua (cfg.APSDCapable = token_set(...))
            # Leave empty; process_interface_configs will fill it from configured AP interfaces.
            echo "APSDCapable=" >> "$dat_file"
            
            # AP TXOP (分号分隔)
            echo "APTxop=0;0;94;47" >> "$dat_file"
            
            # 认证模式
            # AuthMode 将在 process_encryption 中根据实际配置设置
            
            # 自动频道选择
            echo "AutoChannelSelect=0" >> "$dat_file"
            echo "AutoChannelSkipList=" >> "$dat_file"
            
            # 其他高级参数
            echo "AutoProvisionEn=0" >> "$dat_file"
            echo "BandSteering=0" >> "$dat_file"
            echo "BasicRate=15" >> "$dat_file"
            echo "BeaconPeriod=100" >> "$dat_file"
            echo "BFBACKOFFenable=0" >> "$dat_file"
            echo "BgndScanSkipCh=" >> "$dat_file"
            echo "BGProtection=0" >> "$dat_file"
            echo "BndStrgBssIdx=" >> "$dat_file"
            
            # BSS Parameters (分号分隔)
            echo "BSSACM=0;0;0;0" >> "$dat_file"
            echo "BSSAifsn=3;7;2;2" >> "$dat_file"
            echo "BSSCwmax=10;10;4;3" >> "$dat_file"
            echo "BSSCwmin=4;4;3;2" >> "$dat_file"
            # Driver uses BssidNum as the cfg80211 AP VIF allocation limit.
            echo "BssidNum=$MTK_RESERVED_AP_BSSID_NUM" >> "$dat_file"
            echo "BSSTxop=0;0;94;47" >> "$dat_file"
            
            # 带宽参数
            echo "BW_Enable=0" >> "$dat_file"
            echo "BW_Guarantee_Rate=" >> "$dat_file"
            echo "BW_Maximum_Rate=" >> "$dat_file"
            echo "BW_Priority=" >> "$dat_file"
            echo "BW_Root=0" >> "$dat_file"
            
            # 校准和调试参数
            echo "CalCacheApply=0" >> "$dat_file"
            echo "CarrierDetect=0" >> "$dat_file"
            echo "DebugFlags=0" >> "$dat_file"
            
            # DFS 参数
            echo "DfsCalibration=0" >> "$dat_file"
            echo "DfsEnable=0" >> "$dat_file"
            echo "DfsFalseAlarmPrevent=1" >> "$dat_file"
            echo "DfsZeroWait=0" >> "$dat_file"
            echo "DfsZeroWaitCacTime=255" >> "$dat_file"
            
            # 其他参数
            echo "DisableOLBC=0" >> "$dat_file"
            # per-BSSID token in mtkdat.lua (cfg.DtimPeriod = token_set(...))
            # Don't pre-fill with semicolon tokens; let process_interface_configs build the correct length.
            echo "DtimPeriod=" >> "$dat_file"
            echo "E2pAccessMode=2" >> "$dat_file"
            echo "EAPifname=br-lan" >> "$dat_file"
            echo "EDCCAEnable=1" >> "$dat_file"
            # EncrypType 将在 process_encryption 中根据实际配置设置
            echo "EthConvertMode=dongle" >> "$dat_file"
            echo "EtherTrafficBand=0" >> "$dat_file"
            echo "Ethifname=" >> "$dat_file"
            echo "ETxBfEnCond=1" >> "$dat_file"
            echo "FineAGC=0" >> "$dat_file"
            echo "FixedTxMode=" >> "$dat_file"
            echo "ForceRoamSupport=" >> "$dat_file"
            # per-BSSID token in mtkdat.lua (cfg.FragThreshold = token_set(...))
            echo "FragThreshold=" >> "$dat_file"
            echo "FreqDelta=0" >> "$dat_file"
            # per-BSSID token in mtkdat.lua (cfg.FtSupport = token_set(...))
            echo "FtSupport=" >> "$dat_file"
            echo "GreenAP=0" >> "$dat_file"
            echo "G_BAND_256QAM=1" >> "$dat_file"
            # per-BSSID token in mtkdat.lua (cfg.HideSSID = token_set(...))
            echo "HideSSID=" >> "$dat_file"
            
            # HT 参数 (per-BSSID tokens in mtkdat.lua via token_set)
            # 初始化时写入空值，process_interface_configs 会根据 UCI 配置或默认值填充
            echo "HT_AMSDU=" >> "$dat_file"
            echo "AMSDU_NUM=" >> "$dat_file"
            echo "HT_AutoBA=" >> "$dat_file"
            echo "HT_BADecline=" >> "$dat_file"
            echo "HT_BAWinSize=" >> "$dat_file"
            echo "HT_BSSCoexistence=1" >> "$dat_file"
            echo "HT_BW=" >> "$dat_file"
            echo "HT_DisallowTKIP=1" >> "$dat_file"
            echo "HT_EXTCHA=" >> "$dat_file"
            echo "HT_GI=" >> "$dat_file"
            echo "HT_HTC=1" >> "$dat_file"
            echo "HT_LDPC=" >> "$dat_file"
            echo "HT_LinkAdapt=0" >> "$dat_file"
            echo "HT_MCS=" >> "$dat_file"
            echo "HT_MpduDensity=" >> "$dat_file"
            echo "HT_OpMode=" >> "$dat_file"
            echo "HT_PROTECT=" >> "$dat_file"
            echo "HT_RDG=0" >> "$dat_file"
            echo "HT_RxStream=4" >> "$dat_file"
            echo "HT_STBC=" >> "$dat_file"
            echo "HT_TxStream=4" >> "$dat_file"
            
            # 设置设备参数（为 wireless-old 格式的缺失参数设置默认值）
            [ -n "$txpower" ] && echo "TxPower=$txpower" >> "$dat_file" || echo "TxPower=100" >> "$dat_file"
            
            # PERCENTAGEenable：如果 txpower 是 0-100，自动设置为 1
            if [ -n "$percentag_enable" ]; then
                echo "PERCENTAGEenable=$percentag_enable" >> "$dat_file"
            else
                # 检查 txpower 是否在 0-100 范围内
                local percentag_enable_val="0"
                if [ -n "$txpower" ]; then
                    # 检查 txpower 是否为数字且在 0-100 范围内
                    if [ "$txpower" -ge 0 ] && [ "$txpower" -le 100 ] 2>/dev/null; then
                        percentag_enable_val="1"
                    fi
                fi
                echo "PERCENTAGEenable=$percentag_enable_val" >> "$dat_file"
            fi
            [ -n "$channel" ] && echo "Channel=$channel" >> "$dat_file" || echo "Channel=6" >> "$dat_file"
            if [ "$channel" = "auto" ] || [ "$channel" = "0" ] || [ -z "$channel" ]; then
                echo "Channel=0" >> "$dat_file"
                if [ -n "$autoch" ]; then
                    echo "AutoChannelSelect=$autoch" >> "$dat_file"
                else
                    echo "AutoChannelSelect=3" >> "$dat_file"
                fi
            else
                echo "AutoChannelSelect=0" >> "$dat_file"
            fi
            
            [ -n "$beacon_int" ] && echo "BeaconPeriod=$beacon_int" >> "$dat_file" || echo "BeaconPeriod=100" >> "$dat_file"
            [ -n "$txpreamble" ] && echo "TxPreamble=$txpreamble" >> "$dat_file" || echo "TxPreamble=1" >> "$dat_file"
            
            # 根据 htmode 自动设置 ht_extcha（如果未指定）
            if [ -z "$ht_extcha" ]; then
                case "$htmode" in
                    "HT40+"|"HT40-")
                        ht_extcha="1"
                        ;;
                    *)
                        ht_extcha="0"
                        ;;
                esac
            fi
            # HT_EXTCHA is per-BSSID token; don't prefill with a;b
            update_single_value "$dat_file" "HT_EXTCHA" "$ht_extcha"
            [ -n "$ht_txstream" ] && echo "HT_TxStream=$ht_txstream" >> "$dat_file" || echo "HT_TxStream=4" >> "$dat_file"
            [ -n "$ht_rxstream" ] && echo "HT_RxStream=$ht_rxstream" >> "$dat_file" || echo "HT_RxStream=4" >> "$dat_file"
            [ -n "$shortslot" ] && echo "ShortSlot=$shortslot" >> "$dat_file" || echo "ShortSlot=1" >> "$dat_file"
            [ -n "$ht_distkip" ] && echo "HT_DisallowTKIP=$ht_distkip" >> "$dat_file" || echo "HT_DisallowTKIP=1" >> "$dat_file"
            [ -n "$bgprotect" ] && echo "BGProtection=$bgprotect" >> "$dat_file" || echo "BGProtection=0" >> "$dat_file"
            [ -n "$txburst" ] && echo "TxBurst=$txburst" >> "$dat_file" || echo "TxBurst=1" >> "$dat_file"
            
            # HT Coexistence
            if [ -n "$ht_coex" ]; then
                if [ "$ht_coex" = "1" ]; then
                    echo "HT_BSSCoexistence=0" >> "$dat_file"
                elif [ "$ht_coex" = "0" ]; then
                    echo "HT_BSSCoexistence=1" >> "$dat_file"
                fi
            else
                echo "HT_BSSCoexistence=1" >> "$dat_file"
            fi
            
            # 区域设置（为 wireless-old 格式设置默认值）
            if [ "$band" = "2.4G" ]; then
                [ -n "$region" ] && echo "CountryRegion=$region" >> "$dat_file" || echo "CountryRegion=0" >> "$dat_file"
            else
                [ -n "$aregion" ] && echo "CountryRegionABand=$aregion" >> "$dat_file" || echo "CountryRegionABand=9" >> "$dat_file"
            fi
            
            [ -n "$country" ] && echo "CountryCode=$country" >> "$dat_file" || echo "CountryCode=US" >> "$dat_file"
            [ -n "$map_mode" ] && echo "MapMode=$map_mode" >> "$dat_file" || echo "MapMode=0" >> "$dat_file"
            [ -n "$dbdc_mode" ] && echo "DBDC_MODE=$dbdc_mode" >> "$dat_file" || echo "DBDC_MODE=0" >> "$dat_file"
            [ -n "$e2p_accessmode" ] && echo "E2pAccessMode=$e2p_accessmode" >> "$dat_file" || echo "E2pAccessMode=2" >> "$dat_file"
            [ -n "$etxbfencond" ] && echo "ETxBfEnCond=$etxbfencond" >> "$dat_file" || echo "ETxBfEnCond=1" >> "$dat_file"
            # mu_beamformer 映射到 ITxBfEn（隐式波束成形）
            # 如果设置了 mu_beamformer，优先使用它；否则使用 itxbfen
            if [ -n "$mu_beamformer" ]; then
                echo "ITxBfEn=$mu_beamformer" >> "$dat_file"
            elif [ -n "$itxbfen" ]; then
                echo "ITxBfEn=$itxbfen" >> "$dat_file"
            else
                echo "ITxBfEn=0" >> "$dat_file"
            fi
            [ -n "$mutxrx_enable" ] && echo "MUTxRxEnable=$mutxrx_enable" >> "$dat_file" || echo "MUTxRxEnable=0" >> "$dat_file"
            [ -n "$bss_color" ] && echo "BSSColorValue=$bss_color" >> "$dat_file" || echo "BSSColorValue=255" >> "$dat_file"
            [ -n "$twt_support" ] && echo "TWTSupport=$twt_support" >> "$dat_file" || echo "TWTSupport=3" >> "$dat_file"
            [ -n "$dfs_enable" ] && echo "DfsEnable=$dfs_enable" >> "$dat_file" || echo "DfsEnable=0" >> "$dat_file"
            [ -n "$sr_mode" ] && echo "SRMode=$sr_mode" >> "$dat_file" || echo "SRMode=0" >> "$dat_file"
            [ -n "$sre_enable" ] && echo "SREnable=$sre_enable" >> "$dat_file" || echo "SREnable=1" >> "$dat_file"
            
            # Power Up 设置
            [ -n "$powerup_cckofdm" ] && echo "PowerUpCckOfdm=$powerup_cckofdm" >> "$dat_file" || echo "PowerUpCckOfdm=0:0:0:0:0:0:0" >> "$dat_file"
            [ -n "$powerup_ht20" ] && echo "PowerUpHT20=$powerup_ht20" >> "$dat_file" || echo "PowerUpHT20=0:0:0:0:0:0:0" >> "$dat_file"
            [ -n "$powerup_ht40" ] && echo "PowerUpHT40=$powerup_ht40" >> "$dat_file" || echo "PowerUpHT40=0:0:0:0:0:0:0" >> "$dat_file"
            [ -n "$powerup_vht20" ] && echo "PowerUpVHT20=$powerup_vht20" >> "$dat_file" || echo "PowerUpVHT20=0:0:0:0:0:0:0" >> "$dat_file"
            [ -n "$powerup_vht40" ] && echo "PowerUpVHT40=$powerup_vht40" >> "$dat_file" || echo "PowerUpVHT40=0:0:0:0:0:0:0" >> "$dat_file"
            [ -n "$powerup_vht80" ] && echo "PowerUpVHT80=$powerup_vht80" >> "$dat_file" || echo "PowerUpVHT80=0:0:0:0:0:0:0" >> "$dat_file"
            [ -n "$powerup_vht160" ] && echo "PowerUpVHT160=$powerup_vht160" >> "$dat_file" || echo "PowerUpVHT160=0:0:0:0:0:0:0" >> "$dat_file"
            
            [ -n "$vow_airtime_fairness_en" ] && echo "VOW_Airtime_Fairness_En=$vow_airtime_fairness_en" >> "$dat_file" || echo "VOW_Airtime_Fairness_En=1" >> "$dat_file"
            [ -n "$ht_rdg" ] && echo "HT_RDG=$ht_rdg" >> "$dat_file" || echo "HT_RDG=0" >> "$dat_file"
            [ -n "$vow_bw_ctrl" ] && echo "VOW_BW_Ctrl=$vow_bw_ctrl" >> "$dat_file" || echo "VOW_BW_Ctrl=0" >> "$dat_file"
            [ -n "$vow_ex_en" ] && echo "VOW_RX_En=$vow_ex_en" >> "$dat_file" || echo "VOW_RX_En=1" >> "$dat_file"
            
            # IEEE80211H 和 DFS
            if [ "$band" = "2.4G" ]; then
                [ -n "$doth" ] && echo "SeamlessCSA=$doth" >> "$dat_file" || echo "SeamlessCSA=0" >> "$dat_file"
            else
                [ -n "$doth" ] && echo "IEEE80211H=$doth" >> "$dat_file" || echo "IEEE80211H=1" >> "$dat_file"
            fi
            
            # RDRegion（参考 mtkdat.lua 行 2563-2578）
            # 如果设置了 rd_region，使用该值；否则根据 country 自动设置
            if [ -n "$rd_region" ]; then
                echo "RDRegion=$rd_region" >> "$dat_file"
            else
                # 根据 country 自动设置 RDRegion
                case "$country" in
                    "US"|"TW")
                        echo "RDRegion=FCC" >> "$dat_file"
                        ;;
                    "JP")
                        echo "RDRegion=JAP" >> "$dat_file"
                        ;;
                    "FR"|"IE"|"HK"|"AU"|"NONE"|"")
                        echo "RDRegion=CE" >> "$dat_file"
                        ;;
                    *)
                        # 默认值：如果 country 未设置或不在列表中，使用 CE
                        echo "RDRegion=CE" >> "$dat_file"
                        ;;
                esac
            fi
            [ -n "$dfs_slave" ] && echo "DfsSlaveEn=$dfs_slave" >> "$dat_file" || echo "DfsSlaveEn=0" >> "$dat_file"
            [ -n "$cp_support" ] && echo "CP_SUPPORT=$cp_support" >> "$dat_file" || echo "CP_SUPPORT=2" >> "$dat_file"
            
            # 初始化 BSSID 数量和 SSID
            # In mtkdat.lua, SSID1.. are set per iface; don't prefill extra SSIDs here.
            echo "BssidNum=$MTK_RESERVED_AP_BSSID_NUM" >> "$dat_file"
            echo "SSID=" >> "$dat_file"
            echo "SSID1=" >> "$dat_file"
            local i
            i=3
            while [ $i -le 16 ]; do
              echo "SSID$i=" >> "$dat_file"
              i=$((i + 1))
            done
            
            # 初始化无线模式和其他参数
            echo "WirelessMode=" >> "$dat_file"
            echo "WmmCapable=" >> "$dat_file"
            echo "ApEnable=" >> "$dat_file"
            
            # CCK Tx Stream
            echo "CCKTxStream=4" >> "$dat_file"
            
            # VHT 参数 (per-BSSID tokens via token_set in mtkdat.lua)
            echo "VHT_BW=" >> "$dat_file"
            echo "VHT_BW_SIGNAL=" >> "$dat_file"
            echo "VHT_LDPC=" >> "$dat_file"
            echo "VHT_Sec80_Channel=0" >> "$dat_file"
            echo "VHT_SGI=" >> "$dat_file"
            echo "VHT_STBC=" >> "$dat_file"
            
            # 其他高级参数
            echo "VLANID=0" >> "$dat_file"
            echo "VLANPriority=0" >> "$dat_file"
            echo "VLANTag=1" >> "$dat_file"
            
            # MU 参数 (per-BSSID tokens via token_set in mtkdat.lua)
            echo "MuOfdmaDlEnable=" >> "$dat_file"
            echo "MuOfdmaUlEnable=" >> "$dat_file"
            echo "MuMimoDlEnable=" >> "$dat_file"
            echo "MuMimoUlEnable=" >> "$dat_file"
            
            # EHT 参数 (per-BSSID tokens via token_set in mtkdat.lua)
            echo "EHT_ApBw=" >> "$dat_file"
            echo "EHT_ApNsepPriAccess=" >> "$dat_file"
            echo "EHT_ApOmCtrl=1" >> "$dat_file"
            echo "EHT_ApTxopSharing=" >> "$dat_file"
            
            # 安全相关参数 (per-BSSID tokens via token_set in mtkdat.lua)
            echo "PMFMFPC=" >> "$dat_file"
            echo "PMFMFPR=" >> "$dat_file"
            echo "PMFSHA256=" >> "$dat_file"
            echo "PMKCachePeriod=" >> "$dat_file"
            echo "RekeyInterval=" >> "$dat_file"
            echo "RekeyMethod=" >> "$dat_file"
            echo "RTSThreshold=" >> "$dat_file"
            
            # IEEE8021X / IGMP (per-BSSID tokens via token_set in mtkdat.lua)
            echo "IEEE8021X=0" >> "$dat_file"
            echo "IgmpSnEnable=" >> "$dat_file"
            
            # WMM 参数 (per-BSSID token)
            # already initialized above; keep single empty here
            # WmmCapable 会在 process_interface_configs 中根据 UCI 配置更新
            
            # WPS 参数 (per-BSSID tokens via token_set in mtkdat.lua)
            # 默认值：WscConfMode=0, WscConfStatus=1（参考 mtkdat.lua 行 3359-3360）
            echo "WscConfMode=0" >> "$dat_file"
            echo "WscConfStatus=1" >> "$dat_file"
            
            # TxCmdMode
            echo "TxCmdMode=1" >> "$dat_file"
            
            # 其他高级参数
            echo "MlmeMultiQEnable=1" >> "$dat_file"
            echo "RROSupport=1" >> "$dat_file"
            echo "ApcliMloDisable=1" >> "$dat_file"
            # per-BSSID token via token_set
            echo "MldGroup=" >> "$dat_file"
            echo "ApCliPMFMFPR=0" >> "$dat_file"
            echo "TxRate=0;0" >> "$dat_file"
            echo "SaeGroups=19;19" >> "$dat_file"
            
            # Dot11v 参数
            local dot11v_str="0"
            local i
            for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
                if [ $i -eq 1 ]; then
                    dot11v_str="0"
                else
                    dot11v_str="$dot11v_str;0"
                fi
            done
            echo "Dot11vMbssid=$dot11v_str" >> "$dat_file"
            
            # ApCliPweMethod 将在 process_interface_configs 中根据 station 模式接口的 sae_pwe 动态设置
            echo "ApCliPweMethod=0" >> "$dat_file"
            echo "PweMethod=0;0" >> "$dat_file"
            echo "OcacEnable=0" >> "$dat_file"
            echo "EHT_ApcliT2lmNegoSupport=1" >> "$dat_file"
            echo "EHT_ApEmlsr_mr=0;0" >> "$dat_file"
            echo "EHT_ApT2lmNegoSupport=1;1" >> "$dat_file"
            echo "EHT_ApEmlsr_mr_OMN=0;0" >> "$dat_file"
            echo "EHT_ApEmlsr_mr_trans_to=0;0" >> "$dat_file"
            echo "ApCliPMFMFPC=0" >> "$dat_file"
            echo "TidMapping=255;255" >> "$dat_file"
            echo "MLREnable=1" >> "$dat_file"
            echo "MLRVersion=2" >> "$dat_file"
            echo "Single_RNR=1" >> "$dat_file"
            # ACS (Auto Channel Selection) 参数（参考 mtkdat.lua 行 2467-2479）
            [ -n "$acs_restore_dwell" ] && echo "ACSRestoreDwell=$acs_restore_dwell" >> "$dat_file" || echo "ACSRestoreDwell=150" >> "$dat_file"
            [ -n "$acs_prio_weight" ] && echo "ACSPrioWt=$acs_prio_weight" >> "$dat_file" || echo "ACSPrioWt=0" >> "$dat_file"
            [ -n "$acs_max_acs_times" ] && echo "ACSMaxACSTimes=$acs_max_acs_times" >> "$dat_file" || echo "ACSMaxACSTimes=0" >> "$dat_file"
            [ -n "$acs_check_time" ] && echo "ACSCheckTime=$acs_check_time" >> "$dat_file" || echo "ACSCheckTime=0" >> "$dat_file"
            [ -n "$acs_scan_mode" ] && echo "ACSScanMode=$acs_scan_mode" >> "$dat_file" || echo "ACSScanMode=0" >> "$dat_file"
            [ -n "$acs_ice_ch_util_threshold" ] && echo "ACSIceChUtilThr=$acs_ice_ch_util_threshold" >> "$dat_file" || echo "ACSIceChUtilThr=0" >> "$dat_file"
            [ -n "$acs_sta_num_threshold" ] && echo "ACSStaNumThr=$acs_sta_num_threshold" >> "$dat_file" || echo "ACSStaNumThr=1" >> "$dat_file"
            [ -n "$acs_ch_util_threshold" ] && echo "ACSChUtilThr=$acs_ch_util_threshold" >> "$dat_file" || echo "ACSChUtilThr=0" >> "$dat_file"
            [ -n "$acs_switch_ch_threshold" ] && echo "ACSSwChThr=$acs_switch_ch_threshold" >> "$dat_file" || echo "ACSSwChThr=0" >> "$dat_file"
            [ -n "$acs_data_rate_weight" ] && echo "ACSDataRateWt=$acs_data_rate_weight" >> "$dat_file" || echo "ACSDataRateWt=1" >> "$dat_file"
            [ -n "$acs_scan_dwell" ] && echo "ACSScanDwell=$acs_scan_dwell" >> "$dat_file" || echo "ACSScanDwell=200" >> "$dat_file"
            [ -n "$acs_tx_power_cons" ] && echo "ACSTXPowerCons=$acs_tx_power_cons" >> "$dat_file" || echo "ACSTXPowerCons=0" >> "$dat_file"
            [ -n "$band4_dfs_enable" ] && echo "Band4DfsEnable=$band4_dfs_enable" >> "$dat_file" || echo "Band4DfsEnable=0" >> "$dat_file"
            
            # RRMEnable
            echo "RRMEnable=1;1" >> "$dat_file"
            
            # session_timeout_interval
            echo "session_timeout_interval=0;0" >> "$dat_file"
            
            # idle_timeout_interval
            echo "idle_timeout_interval=0" >> "$dat_file"
            
            # AuthMode 和 EncrypType 将在 process_encryption 中根据实际配置设置
            # 不在这里设置默认值，避免重复
            
            # RadioOn
            [ -n "$disabled" ] && [ "$disabled" = "1" ] && echo "RadioOn=0" >> "$dat_file" || echo "RadioOn=1" >> "$dat_file"
            
            
            # PCIe 参数
            echo "PcieAspm=0" >> "$dat_file"
            
            # 性能相关参数
            echo "PhyRateLimit=0" >> "$dat_file"
            
            # Link Test Support
            echo "LinkTestSupport=0" >> "$dat_file"
            
            # MAC Repeater
            echo "MACRepeaterEn=" >> "$dat_file"
            echo "MACRepeaterOuiMode=2" >> "$dat_file"
            
            # Mesh 参数
            echo "MeshAuthMode=" >> "$dat_file"
            echo "MeshAutoLink=0" >> "$dat_file"
            echo "MeshDefaultkey=0" >> "$dat_file"
            echo "MeshEncrypType=" >> "$dat_file"
            echo "MeshId=" >> "$dat_file"
            echo "MeshWEPKEY=" >> "$dat_file"
            echo "MeshWPAKEY=" >> "$dat_file"
            
            # No Forwarding
            echo "NoForwarding=0;0" >> "$dat_file"
            echo "NoForwardingBTNBSSID=0" >> "$dat_file"
            echo "own_ip_addr=192.168.1.1" >> "$dat_file"
            
            # Stream Mode
            echo "StreamMode=0" >> "$dat_file"
            local i
            i=0
            while [ $i -le 3 ]; do
              echo "StreamModeMac$i=" >> "$dat_file"
              i=$((i + 1))
            done
            
            # 测试相关
            echo "TGnWifiTest=0" >> "$dat_file"
            echo "ThermalRecal=0" >> "$dat_file"
            
            # WiFi Test
            echo "WiFiTest=0" >> "$dat_file"
            
            # Station Keep Alive
            echo "StationKeepAlive=0;0" >> "$dat_file"
            
            # Auto Channel Skip List
            echo "AutoChannelSkipList=" >> "$dat_file"
            
            # SKU 参数
            echo "SkuTableIdx=0" >> "$dat_file"
            echo "SKUenable=0" >> "$dat_file"
            
            # SR 参数
            echo "SRDPDEnable=0" >> "$dat_file"
            echo "SRSDEnable=1" >> "$dat_file"
            echo "PPEnable=1" >> "$dat_file"
            
            # VOW 参数
            echo "VOW_Airtime_Ctrl_En=" >> "$dat_file"
            echo "VOW_Group_Backlog=" >> "$dat_file"
            echo "VOW_Group_DWRR_Max_Wait_Time=" >> "$dat_file"
            echo "VOW_Group_DWRR_Quantum=" >> "$dat_file"
            echo "VOW_Group_Max_Airtime_Bucket_Size=" >> "$dat_file"
            echo "VOW_Group_Max_Rate=" >> "$dat_file"
            echo "VOW_Group_Max_Rate_Bucket_Size=" >> "$dat_file"
            echo "VOW_Group_Max_Ratio=" >> "$dat_file"
            echo "VOW_Group_Max_Wait_Time=" >> "$dat_file"
            echo "VOW_Group_Min_Airtime_Bucket_Size=" >> "$dat_file"
            echo "VOW_Group_Min_Rate=" >> "$dat_file"
            echo "VOW_Group_Min_Rate_Bucket_Size=" >> "$dat_file"
            echo "VOW_Group_Min_Ratio=" >> "$dat_file"
            echo "VOW_Rate_Ctrl_En=" >> "$dat_file"
            echo "VOW_Refill_Period=" >> "$dat_file"
            echo "VOW_Sta_BE_DWRR_Quantum=" >> "$dat_file"
            echo "VOW_Sta_BK_DWRR_Quantum=" >> "$dat_file"
            echo "VOW_Sta_DWRR_Max_Wait_Time=" >> "$dat_file"
            echo "VOW_Sta_VI_DWRR_Quantum=" >> "$dat_file"
            echo "VOW_Sta_VO_DWRR_Quantum=" >> "$dat_file"
            echo "VOW_WATF_Enable=" >> "$dat_file"
            echo "VOW_WATF_MAC_LV0=" >> "$dat_file"
            echo "VOW_WATF_MAC_LV1=" >> "$dat_file"
            echo "VOW_WATF_MAC_LV2=" >> "$dat_file"
            echo "VOW_WATF_MAC_LV3=" >> "$dat_file"
            echo "VOW_WATF_Q_LV0=" >> "$dat_file"
            echo "VOW_WATF_Q_LV1=" >> "$dat_file"
            echo "VOW_WATF_Q_LV2=" >> "$dat_file"
            echo "VOW_WATF_Q_LV3=" >> "$dat_file"
            echo "VOW_WMM_Search_Rule_Band0=" >> "$dat_file"
            echo "VOW_WMM_Search_Rule_Band1=" >> "$dat_file"
            
            # WAPI 参数
            echo "WapiAsCertPath=" >> "$dat_file"
            echo "WapiAsIpAddr=" >> "$dat_file"
            echo "WapiAsPort=" >> "$dat_file"
            echo "Wapiifname=" >> "$dat_file"
            local i
            i=1
            while [ $i -le 16 ]; do
              echo "WapiPsk$i=" >> "$dat_file"
              i=$((i + 1))
            done
            echo "WapiPskType=" >> "$dat_file"
            echo "WapiUserCertPath=" >> "$dat_file"
            
            echo "WCNTest=0" >> "$dat_file"
            
            # WDS 参数
            local i
            i=0
            while [ $i -le 3 ]; do
              echo "Wds${i}Key=" >> "$dat_file"
              i=$((i + 1))
            done
            echo "WdsEnable=0;0" >> "$dat_file"
            echo "WdsEncrypType=NONE" >> "$dat_file"
            echo "WdsList=" >> "$dat_file"
            echo "WdsPhyMode=0" >> "$dat_file"
            
            # WPAPSK 参数
            echo "WPAPSK=" >> "$dat_file"
            echo "WPAPSK1=12345678" >> "$dat_file"
            local i
            i=2
            while [ $i -le 16 ]; do
              echo "WPAPSK$i=" >> "$dat_file"
              i=$((i + 1))
            done
            
            # RADIUS 参数
            echo "RADIUS_Acct_Key=" >> "$dat_file"
            echo "RADIUS_Acct_Port=1813" >> "$dat_file"
            echo "RADIUS_Acct_Server=" >> "$dat_file"
            local i
            i=1
            while [ $i -le 16 ]; do
              echo "RADIUS_Key$i=" >> "$dat_file"
              i=$((i + 1))
            done
            echo "RADIUS_Port=1812" >> "$dat_file"
            echo "RADIUS_Server=0" >> "$dat_file"
            
            # RED Enable
            echo "RED_Enable=1" >> "$dat_file"
            
            # IcapMode
            echo "IcapMode=0" >> "$dat_file"
            
            
            # 密钥参数
            local i j
            i=1
            while [ $i -le 4 ]; do
              j=1
              while [ $j -le 16 ]; do
                echo "Key${i}Str$j=" >> "$dat_file"
                j=$((j + 1))
              done
              echo "Key${i}Type=0" >> "$dat_file"
              i=$((i + 1))
            done
            
            # 处理接口配置
            process_interface_configs "$dev_name" "$dat_file"

            # 去重：如果同一个参数被写入多次（例如 BssidNum），保留最后一次写入的值
            # 同时保持文件中非 key=value 的行（注释/Default）原样保留。
            dedupe_dat_kv_lines() {
                local f="$1"
                local tmp="$(mktemp)"
                awk -F'=' '
                    BEGIN { OFS="=" }
                    # preserve non key=value lines (comments, Default, blanks)
                    !index($0,"=") { pre[++pn]=$0; next }
                    {
                        k=$1
                        # store last value, remember first-seen order
                        if (!(k in seen)) { order[++on]=k; seen[k]=1 }
                        val[k]=substr($0, length(k)+2)
                    }
                    END {
                        for (i=1;i<=pn;i++) print pre[i]
                        for (i=1;i<=on;i++) { k=order[i]; print k OFS val[k] }
                    }
                ' "$f" > "$tmp" && cat "$tmp" > "$f"
                rm -f "$tmp"
            }

            dedupe_dat_kv_lines "$dat_file"
            
            # 对 DAT 文件中的参数按字母顺序排序（保留注释行和空行）
            sort_dat_file() {
                local f="$1"
                local tmp="$(mktemp)"
                local tmp_params="$(mktemp)"
                
                # 使用 awk 分离注释行/空行和参数行
                awk '
                    # 注释行或空行：直接输出到注释文件
                    /^[[:space:]]*#/ || /^[[:space:]]*$/ {
                        print > "'"$tmp"'"
                        next
                    }
                    # 参数行（key=value 格式）：输出到参数文件
                    /^[^=]+=/ {
                        print > "'"$tmp_params"'"
                        next
                    }
                    # 其他行：也保留
                    {
                        print > "'"$tmp"'"
                    }
                ' "$f"
                
                # 对参数行按字母顺序排序并追加到输出文件
                if [ -s "$tmp_params" ]; then
                    sort "$tmp_params" >> "$tmp"
                fi
                
                # 替换原文件
                cat "$tmp" > "$f"
                rm -f "$tmp" "$tmp_params"
            }
            
            sort_dat_file "$dat_file"
            
            echo "✅ 已生成详细 DAT 配置: $dat_file"
        fi
    done
}

# 处理接口配置的函数
process_interface_configs() {
    local dev_name="$1"
    local dat_file="$2"
    local bssid_count=0

    # If最终只有 1 个 BSSID/SSID，则所有 token 参数应输出为单值（无分号）。
    # 这里做一次收尾归一化，避免中间因为误计数/模板残留导致出现 ";0"。
    normalize_single_bssid_tokens() {
        local f="$1"
        local p v first
        # 这些字段在 mtkdat.lua 里通过 token_set(cfg.X, i, ...) 生成
        for p in \
            ApEnable HideSSID WmmCapable DtimPeriod \
            HT_BW VHT_BW EHT_ApBw WirelessMode HT_EXTCHA \
            MacAddress \
            AuthMode EncrypType IEEE8021X RADIUS_Server RADIUS_Port \
            PMFMFPC PMFMFPR PMFSHA256 RekeyInterval RekeyMethod PMKCachePeriod \
            PreAuth NoForwarding RTSThreshold FragThreshold IgmpSnEnable \
            VHT_BW_SIGNAL VHT_LDPC VHT_SGI VHT_STBC \
            HT_LDPC HT_STBC HT_PROTECT HT_GI HT_OpMode HT_AMSDU HT_AutoBA HT_BADecline HT_BAWinSize \
            MuOfdmaDlEnable MuOfdmaUlEnable MuMimoDlEnable MuMimoUlEnable \
            WscConfMode WscConfStatus MldGroup MBO StationKeepAlive FtSupport TidMapping \
            APSDCapable TxRate SaeGroups PweMethod session_timeout_interval WdsEnable \
            EHT_ApEmlsr_mr EHT_ApT2lmNegoSupport EHT_ApEmlsr_mr_OMN EHT_ApEmlsr_mr_trans_to RRMEnable \
            HT_MCS HT_MpduDensity
        do
            v="$(grep "^${p}=" "$f" | head -1 | cut -d'=' -f2-)"
            # only trim when there's a semicolon tokenization
            if echo "$v" | grep -q ';'; then
                first="$(echo "$v" | cut -d';' -f1)"
                update_single_value "$f" "$p" "$first"
            fi
        done
    }
    
    # 遍历所有接口配置
    for iface_name in $(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        local device=$(get_uci_value "wifi-iface" "$iface_name" "device")
        local mode=$(get_uci_value "wifi-iface" "$iface_name" "mode")
        
        if [ "$device" = "$dev_name" ] && [ "$mode" = "ap" ]; then
            # 检查接口是否被禁用
            local iface_disabled=$(get_uci_value "wifi-iface" "$iface_name" "disabled")
            # 检查设备是否被禁用
            local device_disabled=$(get_uci_value "wifi-device" "$dev_name" "disabled")
            
            # 如果接口或设备被禁用，跳过生成配置
            if [ "$iface_disabled" = "1" ] || [ "$device_disabled" = "1" ]; then
                continue
            fi
            
            bssid_count=$((bssid_count + 1))
            
            local ssid=$(get_uci_value "wifi-iface" "$iface_name" "ssid")
            local encryption=$(get_uci_value "wifi-iface" "$iface_name" "encryption")
            local key=$(get_uci_value "wifi-iface" "$iface_name" "key")
            local iface_macaddr=$(get_uci_value "wifi-iface" "$iface_name" "macaddr")
            local hidden=$(get_uci_value "wifi-iface" "$iface_name" "hidden")
            local wmm=$(get_uci_value "wifi-iface" "$iface_name" "wmm")
            local dtim_period=$(get_uci_value "wifi-iface" "$iface_name" "dtim_period")
            local disabled=$(get_uci_value "wifi-iface" "$iface_name" "disabled")
            local isolate=$(get_uci_value "wifi-iface" "$iface_name" "isolate")
            local rts=$(get_uci_value "wifi-iface" "$iface_name" "rts")
            local frag=$(get_uci_value "wifi-iface" "$iface_name" "frag")
            local apsd_capable=$(get_uci_value "wifi-iface" "$iface_name" "apsd_capable")
            local vht_ldpc=$(get_uci_value "wifi-iface" "$iface_name" "vht_ldpc")
            local vht_stbc=$(get_uci_value "wifi-iface" "$iface_name" "vht_stbc")
            local vht_sgi=$(get_uci_value "wifi-iface" "$iface_name" "vht_sgi")
            local ht_ldpc=$(get_uci_value "wifi-iface" "$iface_name" "ht_ldpc")
            local ht_stbc=$(get_uci_value "wifi-iface" "$iface_name" "ht_stbc")
            local ht_protect=$(get_uci_value "wifi-iface" "$iface_name" "ht_protect")
            local ht_gi=$(get_uci_value "wifi-iface" "$iface_name" "ht_gi")
            local ht_opmode=$(get_uci_value "wifi-iface" "$iface_name" "ht_opmode")
            local ht_amsdu=$(get_uci_value "wifi-iface" "$iface_name" "ht_amsdu")
            local ht_autoba=$(get_uci_value "wifi-iface" "$iface_name" "ht_autoba")
            local ht_badec=$(get_uci_value "wifi-iface" "$iface_name" "ht_badec")
            local ht_bawinsize=$(get_uci_value "wifi-iface" "$iface_name" "ht_bawinsize")
            local igmpsn_enable=$(get_uci_value "wifi-iface" "$iface_name" "igmpsn_enable")
            local ieee80211w=$(get_uci_value "wifi-iface" "$iface_name" "ieee80211w")
            local pmf_sha256=$(get_uci_value "wifi-iface" "$iface_name" "pmf_sha256")
            
            # 如果 ieee80211w 未设置，根据加密方式自动设置（参考 hostapd.lua 逻辑）
            # 这样可以确保 SAE/WPA3 等加密方式有正确的 PMF 设置
            if [ -z "$ieee80211w" ]; then
                case "$encryption" in
                    "sae")
                        # SAE 加密需要 ieee80211w=2（必需）
                        ieee80211w="2"
                        ;;
                    "sae-mixed")
                        # SAE-mixed 加密需要 ieee80211w=1（可选但推荐）
                        ieee80211w="1"
                        ;;
                    "wpa3")
                        # WPA3 加密需要 ieee80211w=2（必需）
                        ieee80211w="2"
                        ;;
                    "wpa3-192")
                        # WPA3-192 加密需要 ieee80211w=2（必需）
                        ieee80211w="2"
                        ;;
                    *)
                        # 其他加密方式默认为 0（禁用 PMF）
                        ieee80211w="0"
                        ;;
                esac
            fi
            
            local rekey_interval=$(get_uci_value "wifi-iface" "$iface_name" "rekey_interval")
            local rekey_meth=$(get_uci_value "wifi-iface" "$iface_name" "rekey_meth")
            local pmk_cache_period=$(get_uci_value "wifi-iface" "$iface_name" "pmk_cache_period")
            local ieee8021x=$(get_uci_value "wifi-iface" "$iface_name" "ieee8021x")
            local auth_server=$(get_uci_value "wifi-iface" "$iface_name" "auth_server")
            local auth_port=$(get_uci_value "wifi-iface" "$iface_name" "auth_port")
            local ownip=$(get_uci_value "wifi-iface" "$iface_name" "ownip")
            local idle_timeout=$(get_uci_value "wifi-iface" "$iface_name" "idle_timeout")
            local session_timeout=$(get_uci_value "wifi-iface" "$iface_name" "session_timeout")
            local rsn_preauth=$(get_uci_value "wifi-iface" "$iface_name" "rsn_preauth")
            local tx_rate=$(get_uci_value "wifi-iface" "$iface_name" "tx_rate")
            local mbo=$(get_uci_value "wifi-iface" "$iface_name" "mbo")
            local proxy_arp=$(get_uci_value "wifi-iface" "$iface_name" "proxy_arp")
            local mlo=$(get_uci_value "wifi-iface" "$iface_name" "mlo")
            local mldgroup="0"
            if [ "$mlo" = "1" ]; then
                mldgroup="1"  # 自动分配组 ID 1
            else
                # 也检查是否有显式设置的 mldgroup
                local explicit_mldgroup=$(get_uci_value "wifi-iface" "$iface_name" "mldgroup")
                if [ -n "$explicit_mldgroup" ]; then
                    mldgroup="$explicit_mldgroup"
                fi
            fi
            # 获取设备参数（需要映射）
            local raw_htmode=$(get_uci_value "wifi-device" "$dev_name" "htmode")
            local raw_band=$(get_uci_value "wifi-device" "$dev_name" "band")
            local htmode=$(map_htmode_value "$raw_htmode" "$raw_band")
            local band=$(map_band_value "$raw_band")
            
            # 更新 SSID（先删除旧值，再添加新值）
            update_single_value "$dat_file" "SSID${bssid_count}" "$ssid"

            # 更新 BSSID 的 MAC：
            # 优先使用 wifi-iface.macaddr，未配置时回退到按 band/index 自动生成的默认值
            local bssid_mac="$iface_macaddr"
            [ -z "$bssid_mac" ] && bssid_mac="$(get_default_bssid_mac "$raw_band" "$bssid_count")"
            [ -n "$bssid_mac" ] && update_single_value "$dat_file" "MacAddress" "$bssid_mac"
            
            # 更新隐藏 SSID 设置
            [ -n "$hidden" ] && update_token_value "$dat_file" "HideSSID" "$bssid_count" "$hidden"
            
            # 更新 WMM 设置
            [ -n "$wmm" ] && update_token_value "$dat_file" "WmmCapable" "$bssid_count" "$wmm"
            
            # 更新 DTIM 周期
            [ -n "$dtim_period" ] && update_token_value "$dat_file" "DtimPeriod" "$bssid_count" "$dtim_period"
            
            # 更新 AP 启用状态
            if [ "$disabled" = "1" ]; then
                update_token_value "$dat_file" "ApEnable" "$bssid_count" "0"
            else
                update_token_value "$dat_file" "ApEnable" "$bssid_count" "1"
            fi
            
            # 设置无线模式和带宽（使用统一的函数）
            local wireless_mode bw ht_extcha
            if [ -n "$htmode" ]; then
                # 使用统一的 htmode2wireless_mode 函数计算 wireless_mode、bw 和 ht_extcha
                htmode2wireless_mode "$htmode" "$band"
                wireless_mode="$htmode2wireless_mode_result_wireless_mode"
                bw="$htmode2wireless_mode_result_bw"
                ht_extcha="$htmode2wireless_mode_result_ht_extcha"
                
                # 根据 bw 计算 HT_BW, VHT_BW, EHT_ApBw（参考 mtkdat.lua iface2cfg 函数 2666-2691 行）
                local ht_bw vht_bw eht_apbw
                if [ "$bw" = "20" ]; then
                    ht_bw=0      # HT_BW_20
                    vht_bw=0     # VHT_BW_2040
                    eht_apbw=0   # EHT_BW_20
                else
                    ht_bw=1      # HT_BW_40
                    if [ "$bw" = "40" ]; then
                        vht_bw=0     # VHT_BW_2040
                        eht_apbw=1   # EHT_BW_2040
                    elif [ "$bw" = "60" ]; then
                        vht_bw=0     # VHT_BW_2040
                        eht_apbw=""  # 未定义
                    elif [ "$bw" = "80" ]; then
                        vht_bw=1     # VHT_BW_80
                        eht_apbw=2   # EHT_BW_80
                    elif [ "$bw" = "160" ]; then
                        vht_bw=2     # VHT_BW_160
                        eht_apbw=3   # EHT_BW_160
                    elif [ "$bw" = "161" ]; then
                        # VHT80_80 (80+80): 根据 mtkdat.lua iface2cfg 2685-2686 行
                        # ht_bw = HT_BW_40 (1), vht_bw = VHT_BW_8080 (3)
                        ht_bw=1      # HT_BW_40 (因为不是 20)
                        vht_bw=3     # VHT_BW_8080
                        eht_apbw=""  # mtkdat.lua 中未设置，保持为空
                    elif [ "$bw" = "320" ]; then
                        # HE320/EHT320: 根据 mtkdat.lua iface2cfg 2687-2689 行
                        # ht_bw = HT_BW_40 (1), vht_bw = VHT_BW_160 (2), eht_apbw = EHT_BW_320 (4)
                        ht_bw=1      # HT_BW_40 (因为不是 20)
                        vht_bw=2     # VHT_BW_160
                        eht_apbw=4   # EHT_BW_320
                    else
                        vht_bw=0
                        eht_apbw=0
                    fi
                fi
                
                # 更新参数：1 个 SSID 时写成单值；多个 SSID 时自动扩展为 a;b;...
                # 统一走 update_token_value（它会按 index 扩展 token 长度）
                update_token_value "$dat_file" "HT_BW" "$bssid_count" "$ht_bw"
                update_token_value "$dat_file" "VHT_BW" "$bssid_count" "$vht_bw"
                # eht_apbw 在某些 bw（例如 161）可能为空；为空就不写入/不更新
                [ -n "$eht_apbw" ] && update_token_value "$dat_file" "EHT_ApBw" "$bssid_count" "$eht_apbw"
                update_token_value "$dat_file" "WirelessMode" "$bssid_count" "$wireless_mode"
                update_token_value "$dat_file" "HT_EXTCHA" "$bssid_count" "$ht_extcha"
            fi
            
            # 处理加密设置（传递 pmf_sha256 参数）
            local pmf_sha256_val="${pmf_sha256:-0}"
            process_encryption "$encryption" "$key" "$bssid_count" "$dat_file" "$pmf_sha256_val"
            
            # 更新各种配置
            # 更新密钥相关配置（参考 mtkdat.lua 行 2742-2744）
            # RekeyInterval, RekeyMethod, PMKCachePeriod 从 UCI 配置读取，如果没有设置则使用默认值
            if [ -n "$rekey_interval" ]; then
                update_token_value "$dat_file" "RekeyInterval" "$bssid_count" "$rekey_interval"
            else
                # 默认值：3600 秒（1小时）
                update_token_value "$dat_file" "RekeyInterval" "$bssid_count" "3600"
            fi
            if [ -n "$rekey_meth" ]; then
                update_token_value "$dat_file" "RekeyMethod" "$bssid_count" "$rekey_meth"
            else
                # 默认值：0（禁用）
                update_token_value "$dat_file" "RekeyMethod" "$bssid_count" "TIME"
            fi
            if [ -n "$pmk_cache_period" ]; then
                update_token_value "$dat_file" "PMKCachePeriod" "$bssid_count" "$pmk_cache_period"
            else
                # 默认值：0（禁用）
                update_token_value "$dat_file" "PMKCachePeriod" "$bssid_count" "10"
            fi
            
            # IEEE 802.1X 和 RADIUS 配置
            if [ -n "$ieee8021x" ]; then
                update_token_value "$dat_file" "IEEE8021X" "$bssid_count" "$ieee8021x"
            else
                update_token_value "$dat_file" "IEEE8021X" "$bssid_count" "0"
            fi
            if [ -n "$auth_server" ]; then
                update_single_value "$dat_file" "RADIUS_Server" "$auth_server"
            else
                update_single_value "$dat_file" "RADIUS_Server" "0"
            fi
            if [ -n "$auth_port" ]; then
                update_single_value "$dat_file" "RADIUS_Port" "$auth_port"
            else
                update_single_value "$dat_file" "RADIUS_Port" "1812"
            fi
            if [ -n "$auth_secret" ]; then
                # RADIUS_Key 使用 RADIUS_Key1, RADIUS_Key2 等格式（根据 mtkdat.lua）
                update_single_value "$dat_file" "RADIUS_Key${bssid_count}" "$auth_secret"
            fi
            [ -n "$ownip" ] && update_single_value "$dat_file" "own_ip_addr" "$ownip"
            # 更新 idle_timeout_interval（先删除旧值，再添加新值）
            if [ -n "$idle_timeout" ]; then
                update_single_value "$dat_file" "idle_timeout_interval" "$idle_timeout"
            fi
            session_timeout="0"
            update_token_value "$dat_file" "session_timeout_interval" "$bssid_count" "$session_timeout"
            if [ -n "$rsn_preauth" ]; then
                update_token_value "$dat_file" "PreAuth" "$bssid_count" "$rsn_preauth"
            else
                update_token_value "$dat_file" "PreAuth" "$bssid_count" "0"
            fi
            if [ -n "$tx_rate" ]; then
                update_token_value "$dat_file" "TxRate" "$bssid_count" "$tx_rate"
            else
                update_token_value "$dat_file" "TxRate" "$bssid_count" "0"
            fi
            update_token_value "$dat_file" "SaeGroups" "$bssid_count" "19"
            
            # IEEE80211w 和 PMF 设置
            if [ -n "$ieee80211w" ]; then
                case "$ieee80211w" in
                    "2")
                        update_token_value "$dat_file" "PMFMFPC" "$bssid_count" "1"
                        update_token_value "$dat_file" "PMFMFPR" "$bssid_count" "1"
                        ;;
                    "1")
                        update_token_value "$dat_file" "PMFMFPC" "$bssid_count" "1"
                        update_token_value "$dat_file" "PMFMFPR" "$bssid_count" "0"
                        ;;
                    "0"|*)
                        update_token_value "$dat_file" "PMFMFPC" "$bssid_count" "0"
                        update_token_value "$dat_file" "PMFMFPR" "$bssid_count" "0"
                        ;;
                esac
            else
                # 如果没有设置 ieee80211w，默认为 0
                update_token_value "$dat_file" "PMFMFPC" "$bssid_count" "0"
                update_token_value "$dat_file" "PMFMFPR" "$bssid_count" "0"
            fi
            
            # PMFSHA256 设置（参考 mtkdat.lua 行 2708-2713, 2122-2129）
            # 如果 ieee80211w=2 且加密方式是 psk2+ccmp, wpa2+ccmp, 或 wpa3，则自动设置为 1
            local pmf_sha256_val="$pmf_sha256"
            if [ "$ieee80211w" = "2" ]; then
                case "$encryption" in
                    "psk2"|"psk2+ccmp"|"wpa2+ccmp"|"wpa3")
                        pmf_sha256_val="1"
                        ;;
                esac
            fi
            # 如果 pmf_sha256 未设置，使用计算出的值或默认值 0
            [ -n "$pmf_sha256_val" ] && update_token_value "$dat_file" "PMFSHA256" "$bssid_count" "$pmf_sha256_val" || update_token_value "$dat_file" "PMFSHA256" "$bssid_count" "0"
            
            # 更新隔离设置
            [ -n "$isolate" ] && update_token_value "$dat_file" "NoForwarding" "$bssid_count" "$isolate"
            
            # 更新 RTS/CTS 和碎片阈值（参考 mtkdat.lua）
            # RTSThreshold：从 UCI 配置读取，如果没有设置则使用默认值 2347
            if [ -n "$rts" ]; then
                update_token_value "$dat_file" "RTSThreshold" "$bssid_count" "$rts"
            else
                # 默认值：2347（参考 hostapd 默认值）
                update_token_value "$dat_file" "RTSThreshold" "$bssid_count" "2347"
            fi
            # FragThreshold：从 UCI 配置读取，如果没有设置则使用默认值 2346
            if [ -n "$frag" ]; then
                update_token_value "$dat_file" "FragThreshold" "$bssid_count" "$frag"
            else
                # 默认值：2346（参考 hostapd 默认值）
                update_token_value "$dat_file" "FragThreshold" "$bssid_count" "2346"
            fi
            
            # 更新 APSD 功能（参考 mtkdat.lua __delete_mbss_para 行 3286）
            # APSD 通常在有加密的情况下更有用，但默认值为 0
            if [ -n "$apsd_capable" ]; then
                update_token_value "$dat_file" "APSDCapable" "$bssid_count" "$apsd_capable"
            else
                # 默认值：0（参考 mtkdat.lua __delete_mbss_para）
                # 注意：可以根据加密方式自动启用，但 mtkdat.lua 中默认是 0
                update_token_value "$dat_file" "APSDCapable" "$bssid_count" "0"
            fi
            
            # 更新 VHT 设置（参考 mtkdat.lua __delete_mbss_para 行 3312-3315）
            # 如果 wireless_mode 是 VHT/HE/EHT 模式（>= 14），可以自动启用这些功能
            # 但为了兼容性，默认值仍为 0，除非明确设置
            if [ -n "$vht_ldpc" ]; then
                update_token_value "$dat_file" "VHT_LDPC" "$bssid_count" "$vht_ldpc"
            else
                # 如果 wireless_mode 是 VHT/HE/EHT 模式，可以自动启用（硬件支持时）
                # PHY_11VHT_N_* (12-15) 或 PHY_11AX_* (16-21) 或 PHY_11BE_* (22-27)
                local vht_ldpc_default="0"
                if [ -n "$wireless_mode" ]; then
                    if [ "$wireless_mode" -ge 12 ] && [ "$wireless_mode" -le 27 ] 2>/dev/null; then
                        # VHT/HE/EHT 模式，默认启用 LDPC（如果硬件支持）
                        vht_ldpc_default="1"
                    fi
                fi
                update_token_value "$dat_file" "VHT_LDPC" "$bssid_count" "$vht_ldpc_default"
            fi
            if [ -n "$vht_stbc" ]; then
                update_token_value "$dat_file" "VHT_STBC" "$bssid_count" "$vht_stbc"
            else
                # 如果 wireless_mode 是 VHT/HE/EHT 模式，可以自动启用
                local vht_stbc_default="0"
                if [ -n "$wireless_mode" ]; then
                    if [ "$wireless_mode" -ge 12 ] && [ "$wireless_mode" -le 27 ] 2>/dev/null; then
                        vht_stbc_default="1"
                    fi
                fi
                update_token_value "$dat_file" "VHT_STBC" "$bssid_count" "$vht_stbc_default"
            fi
            if [ -n "$vht_sgi" ]; then
                update_token_value "$dat_file" "VHT_SGI" "$bssid_count" "$vht_sgi"
            else
                # 如果 wireless_mode 是 VHT/HE/EHT 模式，可以自动启用
                local vht_sgi_default="0"
                if [ -n "$wireless_mode" ]; then
                    if [ "$wireless_mode" -ge 12 ] && [ "$wireless_mode" -le 27 ] 2>/dev/null; then
                        vht_sgi_default="1"
                    fi
                fi
                update_token_value "$dat_file" "VHT_SGI" "$bssid_count" "$vht_sgi_default"
            fi
            
            # 更新 HT 设置（参考 mtkdat.lua __delete_mbss_para 行 3292-3297）
            # 如果 wireless_mode 是 HT/HE/EHT 模式（>= 8），可以自动启用这些功能
            if [ -n "$ht_ldpc" ]; then
                update_token_value "$dat_file" "HT_LDPC" "$bssid_count" "$ht_ldpc"
            else
                # 如果 wireless_mode 是 HT/HE/EHT 模式，可以自动启用
                # PHY_11AN_MIXED (8) 或更高
                local ht_ldpc_default="0"
                if [ -n "$wireless_mode" ]; then
                    if [ "$wireless_mode" -ge 8 ] && [ "$wireless_mode" -le 27 ] 2>/dev/null; then
                        ht_ldpc_default="1"
                    fi
                fi
                update_token_value "$dat_file" "HT_LDPC" "$bssid_count" "$ht_ldpc_default"
            fi
            if [ -n "$ht_stbc" ]; then
                update_token_value "$dat_file" "HT_STBC" "$bssid_count" "$ht_stbc"
            else
                # 如果 wireless_mode 是 HT/HE/EHT 模式，可以自动启用
                local ht_stbc_default="0"
                if [ -n "$wireless_mode" ]; then
                    if [ "$wireless_mode" -ge 8 ] && [ "$wireless_mode" -le 27 ] 2>/dev/null; then
                        ht_stbc_default="1"
                    fi
                fi
                update_token_value "$dat_file" "HT_STBC" "$bssid_count" "$ht_stbc_default"
            fi
            if [ -n "$ht_protect" ]; then
                update_token_value "$dat_file" "HT_PROTECT" "$bssid_count" "$ht_protect"
            else
                # HT_PROTECT 默认值：0（通常不需要自动启用）
                update_token_value "$dat_file" "HT_PROTECT" "$bssid_count" "0"
            fi
            if [ -n "$ht_gi" ]; then
                update_token_value "$dat_file" "HT_GI" "$bssid_count" "$ht_gi"
            else
                # 如果 wireless_mode 是 HT/HE/EHT 模式，可以自动启用
                local ht_gi_default="0"
                if [ -n "$wireless_mode" ]; then
                    if [ "$wireless_mode" -ge 8 ] && [ "$wireless_mode" -le 27 ] 2>/dev/null; then
                        ht_gi_default="1"
                    fi
                fi
                update_token_value "$dat_file" "HT_GI" "$bssid_count" "$ht_gi_default"
            fi
            if [ -n "$ht_opmode" ]; then
                update_token_value "$dat_file" "HT_OpMode" "$bssid_count" "$ht_opmode"
            else
                # HT_OpMode 默认值：0（混合模式）
                update_token_value "$dat_file" "HT_OpMode" "$bssid_count" "0"
            fi
            if [ -n "$ht_amsdu" ]; then
                update_token_value "$dat_file" "HT_AMSDU" "$bssid_count" "$ht_amsdu"
            else
                # HT_AMSDU 默认值：0（通常不需要自动启用）
                update_token_value "$dat_file" "HT_AMSDU" "$bssid_count" "1"
            fi
            # HT_AutoBA（参考 mtkdat.lua 行 2797-2801）
            if [ -n "$ht_autoba" ]; then
                update_token_value "$dat_file" "HT_AutoBA" "$bssid_count" "$ht_autoba"
            else
                # 默认值：1
                update_token_value "$dat_file" "HT_AutoBA" "$bssid_count" "1"
            fi
            # HT_BADecline（参考 mtkdat.lua 行 2802-2806）
            if [ -n "$ht_badec" ]; then
                update_token_value "$dat_file" "HT_BADecline" "$bssid_count" "$ht_badec"
            else
                # 默认值：0
                update_token_value "$dat_file" "HT_BADecline" "$bssid_count" "0"
            fi
            # HT_BAWinSize（参考 mtkdat.lua 行 2807-2819）
            if [ -n "$ht_bawinsize" ]; then
                update_token_value "$dat_file" "HT_BAWinSize" "$bssid_count" "$ht_bawinsize"
            else
                # 根据 wireless_mode 设置默认值
                # PHY_11BE_24G (22) 到 PHY_11BE_24G_5G_6G (25): 1024
                # PHY_11AX_24G (16) 到 PHY_11AX_24G_5G_6G (19): 256
                # 其他: 64
                local ht_bawinsize_default="64"
                if [ -n "$wireless_mode" ]; then
                    if [ "$wireless_mode" -ge 22 ] && [ "$wireless_mode" -le 25 ] 2>/dev/null; then
                        ht_bawinsize_default="1024"
                    elif [ "$wireless_mode" -ge 16 ] && [ "$wireless_mode" -le 19 ] 2>/dev/null; then
                        ht_bawinsize_default="256"
                    fi
                fi
                update_token_value "$dat_file" "HT_BAWinSize" "$bssid_count" "$ht_bawinsize_default"
            fi
            
            # 更新 IGMP Snooping
            igmpsn_enable="1"
            [ -n "$igmpsn_enable" ] && update_token_value "$dat_file" "IgmpSnEnable" "$bssid_count" "$igmpsn_enable"
            
            # 更新 MU-MIMO/OFDMA 参数（参考 mtkdat.lua 行 2823-2826）
            # 这些参数可以从 UCI 配置读取，如果没有设置则根据 wireless_mode 自动设置
            local mumimodl_enable=$(get_uci_value "wifi-iface" "$iface_name" "mumimodl_enable")
            local mumimoul_enable=$(get_uci_value "wifi-iface" "$iface_name" "mumimoul_enable")
            local muofdmadl_enable=$(get_uci_value "wifi-iface" "$iface_name" "muofdmadl_enable")
            local muofdmaul_enable=$(get_uci_value "wifi-iface" "$iface_name" "muofdmaul_enable")
            
            # MU-MIMO: 支持 802.11ac (VHT, wireless_mode 12-15) 和 802.11ax (HE, wireless_mode 16-21) 和 802.11be (EHT, wireless_mode 22-27)
            if [ -n "$mumimodl_enable" ]; then
                update_token_value "$dat_file" "MuMimoDlEnable" "$bssid_count" "$mumimodl_enable"
            else
                # 根据 wireless_mode 自动设置
                local mu_mimo_dl_default="0"
                if [ -n "$wireless_mode" ]; then
                    if [ "$wireless_mode" -ge 12 ] && [ "$wireless_mode" -le 27 ] 2>/dev/null; then
                        mu_mimo_dl_default="1"
                    fi
                fi
                update_token_value "$dat_file" "MuMimoDlEnable" "$bssid_count" "$mu_mimo_dl_default"
            fi
            
            if [ -n "$mumimoul_enable" ]; then
                update_token_value "$dat_file" "MuMimoUlEnable" "$bssid_count" "$mumimoul_enable"
            else
                # 根据 wireless_mode 自动设置
                local mu_mimo_ul_default="0"
                if [ -n "$wireless_mode" ]; then
                    if [ "$wireless_mode" -ge 12 ] && [ "$wireless_mode" -le 27 ] 2>/dev/null; then
                        mu_mimo_ul_default="1"
                    fi
                fi
                update_token_value "$dat_file" "MuMimoUlEnable" "$bssid_count" "$mu_mimo_ul_default"
            fi
            
            # MU-OFDMA: 支持 802.11ax (HE, wireless_mode 16-21) 和 802.11be (EHT, wireless_mode 22-27)
            if [ -n "$muofdmadl_enable" ]; then
                update_token_value "$dat_file" "MuOfdmaDlEnable" "$bssid_count" "$muofdmadl_enable"
            else
                # 根据 wireless_mode 自动设置
                local mu_ofdma_dl_default="0"
                if [ -n "$wireless_mode" ]; then
                    if [ "$wireless_mode" -ge 16 ] && [ "$wireless_mode" -le 27 ] 2>/dev/null; then
                        mu_ofdma_dl_default="1"
                    fi
                fi
                update_token_value "$dat_file" "MuOfdmaDlEnable" "$bssid_count" "$mu_ofdma_dl_default"
            fi
            
            if [ -n "$muofdmaul_enable" ]; then
                update_token_value "$dat_file" "MuOfdmaUlEnable" "$bssid_count" "$muofdmaul_enable"
            else
                # 根据 wireless_mode 自动设置
                local mu_ofdma_ul_default="0"
                if [ -n "$wireless_mode" ]; then
                    if [ "$wireless_mode" -ge 16 ] && [ "$wireless_mode" -le 27 ] 2>/dev/null; then
                        mu_ofdma_ul_default="1"
                    fi
                fi
                update_token_value "$dat_file" "MuOfdmaUlEnable" "$bssid_count" "$mu_ofdma_ul_default"
            fi
            
            # 更新 MBO 设置
            [ -n "$mbo" ] && update_token_value "$dat_file" "MBO" "$bssid_count" "$mbo"
            
            # 更新 PweMethod（参考 mtkdat.lua 行 2906-2912）
            local sae_pwe=$(get_uci_value "wifi-iface" "$iface_name" "sae_pwe")
            
            # 如果 sae_pwe 未设置，根据加密方式自动设置
            # SAE 和 SAE-mixed 加密方式默认使用 sae_pwe=2（对应 PweMethod=0）
            if [ -z "$sae_pwe" ]; then
                case "$encryption" in
                    "sae"|"sae-mixed"|"sae+ccmp"|"sae+gcmp"|"sae+ccmp256"|"sae+gcmp256"|"sae-ext"|"sae-ext+ccmp"|"sae-ext+gcmp"|"sae-ext+ccmp256"|"sae-ext+gcmp256")
                        sae_pwe="2"
                        ;;
                    *)
                        # 其他加密方式不使用 SAE，sae_pwe 保持为空，对应 PweMethod=0
                        ;;
                esac
            fi
            
            # 将 sae_pwe 转换为 PweMethod（参考 mtkdat.lua 行 2906-2912）
            local pwe_method="0"  # 默认值（对应 sae_pwe=nil 或 sae_pwe=2）
            if [ -n "$sae_pwe" ]; then
                case "$sae_pwe" in
                    "0")
                        pwe_method="1"  # sae_pwe=0 → PweMethod=1
                        ;;
                    "1")
                        pwe_method="2"  # sae_pwe=1 → PweMethod=2
                        ;;
                    "2")
                        pwe_method="0"  # sae_pwe=2 → PweMethod=0
                        ;;
                    *)
                        pwe_method="0"  # 其他值默认使用 0
                        ;;
                esac
            fi
            update_token_value "$dat_file" "PweMethod" "$bssid_count" "$pwe_method"
            
            # 更新代理 ARP（先删除旧值，再添加新值）
            if [ -n "$proxy_arp" ]; then
                update_single_value "$dat_file" "ProxyArp" "$proxy_arp"
            fi
            
            # 更新 MLO/MLD 组（参考 mtkdat.lua 行 2769）
            # mldgroup 为 "0" 表示不属于任何 MLD 组
            if [ -n "$mldgroup" ]; then
                update_token_value "$dat_file" "MldGroup" "$bssid_count" "$mldgroup"
                update_token_value "$dat_file" "EHT_ApEmlsr_mr" "$bssid_count" "1"
            else
                # 如果未设置，默认为 "0"（不属于任何组）
                update_token_value "$dat_file" "MldGroup" "$bssid_count" "0"
                update_token_value "$dat_file" "EHT_ApEmlsr_mr" "$bssid_count" "0"
            fi
            
            # 更新 WPS 参数（参考 mtkdat.lua 行 2843-2858）
            local wps_state=$(get_uci_value "wifi-iface" "$iface_name" "wps_state")
            local wps_pin=$(get_uci_value "wifi-iface" "$iface_name" "wps_pin")
            
            # 根据 wps_state 设置 WscConfMode 和 WscConfStatus
            # wps_state == '1' -> WscConfMode = '7', WscConfStatus = '1'
            # wps_state == '2' -> WscConfMode = '7', WscConfStatus = '2'
            # 其他 -> WscConfMode = '0', WscConfStatus = '1'
            local wsc_confmode="0"
            local wsc_confstatus="1"
            if [ -n "$wps_state" ]; then
                case "$wps_state" in
                    "1")
                        wsc_confmode="7"
                        wsc_confstatus="1"
                        ;;
                    "2")
                        wsc_confmode="7"
                        wsc_confstatus="2"
                        ;;
                    *)
                        wsc_confmode="0"
                        wsc_confstatus="1"
                        ;;
                esac
            fi
            update_token_value "$dat_file" "WscConfMode" "$bssid_count" "$wsc_confmode"
            update_token_value "$dat_file" "WscConfStatus" "$bssid_count" "$wsc_confstatus"
            
            # 更新其他 per-BSSID 参数的默认值（参考 mtkdat.lua 行 2922-2930）
            # 这些参数在初始化时写入空值，这里根据 UCI 配置或默认值填充
            
            # HT_MCS（参考 mtkdat.lua 行 2925，默认值 33）
            local ht_mcs=$(get_uci_value "wifi-iface" "$iface_name" "ht_mcs")
            if [ -n "$ht_mcs" ]; then
                update_token_value "$dat_file" "HT_MCS" "$bssid_count" "$ht_mcs"
            else
                update_token_value "$dat_file" "HT_MCS" "$bssid_count" "33"
            fi
            
            # HT_MpduDensity（参考 mtkdat.lua 行 2926，默认值 4）
            local ht_mpdu_density=$(get_uci_value "wifi-iface" "$iface_name" "ht_mpdu_density")
            if [ -n "$ht_mpdu_density" ]; then
                update_token_value "$dat_file" "HT_MpduDensity" "$bssid_count" "$ht_mpdu_density"
            else
                update_token_value "$dat_file" "HT_MpduDensity" "$bssid_count" "4"
            fi
            
            # AMSDU_NUM（参考 mtkdat.lua 行 2927，默认值 5）
            local amsdu_num=$(get_uci_value "wifi-iface" "$iface_name" "amsdu_num")
            if [ -n "$amsdu_num" ]; then
                update_token_value "$dat_file" "AMSDU_NUM" "$bssid_count" "$amsdu_num"
            else
                update_token_value "$dat_file" "AMSDU_NUM" "$bssid_count" "5"
            fi
            
            # EHT_ApNsepPriAccess（参考 mtkdat.lua 行 2928，默认值 1）
            local eht_ap_nsep_pri_access=$(get_uci_value "wifi-iface" "$iface_name" "eht_ap_nsep_pri_access")
            if [ -n "$eht_ap_nsep_pri_access" ]; then
                update_token_value "$dat_file" "EHT_ApNsepPriAccess" "$bssid_count" "$eht_ap_nsep_pri_access"
            else
                update_token_value "$dat_file" "EHT_ApNsepPriAccess" "$bssid_count" "1"
            fi
            
            # EHT_ApTxopSharing（参考 mtkdat.lua 行 2929，默认值 0）
            local eht_ap_txop_sharing=$(get_uci_value "wifi-iface" "$iface_name" "eht_ap_txop_sharing")
            if [ -n "$eht_ap_txop_sharing" ]; then
                update_token_value "$dat_file" "EHT_ApTxopSharing" "$bssid_count" "$eht_ap_txop_sharing"
            else
                update_token_value "$dat_file" "EHT_ApTxopSharing" "$bssid_count" "0"
            fi
            
            update_token_value "$dat_file" "WmmCapable" "$bssid_count" "1"

            # VHT_BW_SIGNAL（参考 mtkdat.lua 行 2776，默认值 0）
            local vht_bw_signal=$(get_uci_value "wifi-iface" "$iface_name" "vht_bw_signal")
            if [ -n "$vht_bw_signal" ]; then
                update_token_value "$dat_file" "VHT_BW_SIGNAL" "$bssid_count" "$vht_bw_signal"
            else
                update_token_value "$dat_file" "VHT_BW_SIGNAL" "$bssid_count" "0"
            fi
            
            # TidMapping（参考 mtkdat.lua 行 2924，默认值 255）
            local tid_mapping=$(get_uci_value "wifi-iface" "$iface_name" "tid_mapping")
            if [ -n "$tid_mapping" ]; then
                update_token_value "$dat_file" "TidMapping" "$bssid_count" "$tid_mapping"
            else
                update_token_value "$dat_file" "TidMapping" "$bssid_count" "255"
            fi
            
            # StationKeepAlive（参考 mtkdat.lua 行 2922，默认值 0）
            local sta_keepalive=$(get_uci_value "wifi-iface" "$iface_name" "sta_keepalive")
            if [ -n "$sta_keepalive" ]; then
                update_token_value "$dat_file" "StationKeepAlive" "$bssid_count" "$sta_keepalive"
            else
                update_token_value "$dat_file" "StationKeepAlive" "$bssid_count" "0"
            fi
            
            # FtSupport（参考 mtkdat.lua 行 2923，默认值 0）
            local ieee80211r=$(get_uci_value "wifi-iface" "$iface_name" "ieee80211r")
            if [ -n "$ieee80211r" ]; then
                update_token_value "$dat_file" "FtSupport" "$bssid_count" "$ieee80211r"
            else
                update_token_value "$dat_file" "FtSupport" "$bssid_count" "0"
            fi
            
            # RRMEnable（参考 mtkdat.lua 行 2930，默认值 1）
            local ieee80211k=$(get_uci_value "wifi-iface" "$iface_name" "ieee80211k")
            if [ -n "$ieee80211k" ]; then
                update_token_value "$dat_file" "RRMEnable" "$bssid_count" "$ieee80211k"
            else
                update_token_value "$dat_file" "RRMEnable" "$bssid_count" "1"
            fi

            update_token_value "$dat_file" "EHT_ApT2lmNegoSupport" "$bssid_count" "0"
            update_token_value "$dat_file" "EHT_ApEmlsr_mr_OMN" "$bssid_count" "0"
            update_token_value "$dat_file" "EHT_ApEmlsr_mr_trans_to" "$bssid_count" "0"
            update_token_value "$dat_file" "WdsEnable" "$bssid_count" "0"
        fi
    done

    # 更新 BSSID 数量。驱动用 BssidNum 作为可创建 AP VIF 的上限；
    # 即使当前 UCI 只有 1 个 AP，也保留 phyX-ap0..3 的创建配额。
    if [ $bssid_count -gt 0 ]; then
        local bssid_limit="$bssid_count"
        [ "$bssid_limit" -lt "$MTK_RESERVED_AP_BSSID_NUM" ] && bssid_limit="$MTK_RESERVED_AP_BSSID_NUM"
        update_single_value "$dat_file" "BssidNum" "$bssid_limit"
    fi

    # 只有一个实际配置的 AP 时，token 参数保持单值；BssidNum 仍可保留更高的驱动配额。
    if [ "$bssid_count" -eq 1 ]; then
        normalize_single_bssid_tokens "$dat_file"
    fi
    
    # 处理 station 模式接口（ApCli）的配置
    # 遍历所有 station 模式的接口，更新 ApCliPweMethod（参考 mtkdat.lua 行 2990-2996）
    for iface_name in $(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        local device=$(get_uci_value "wifi-iface" "$iface_name" "device")
        local mode=$(get_uci_value "wifi-iface" "$iface_name" "mode")
        
        if [ "$device" = "$dev_name" ] && [ "$mode" = "sta" ]; then
            # 检查接口是否被禁用
            local iface_disabled=$(get_uci_value "wifi-iface" "$iface_name" "disabled")
            # 检查设备是否被禁用
            local device_disabled=$(get_uci_value "wifi-device" "$dev_name" "disabled")
            
            # 如果接口或设备被禁用，跳过
            if [ "$iface_disabled" = "1" ] || [ "$device_disabled" = "1" ]; then
                continue
            fi
            
            # 获取 station 模式接口的 sae_pwe
            local sae_pwe=$(get_uci_value "wifi-iface" "$iface_name" "sae_pwe")
            local encryption=$(get_uci_value "wifi-iface" "$iface_name" "encryption")
            
            # 如果 sae_pwe 未设置，根据加密方式自动设置
            # SAE 和 SAE-mixed 加密方式默认使用 sae_pwe=2（对应 ApCliPweMethod=0）
            if [ -z "$sae_pwe" ]; then
                case "$encryption" in
                    "sae"|"sae-mixed"|"sae+ccmp"|"sae+gcmp"|"sae+ccmp256"|"sae+gcmp256"|"sae-ext"|"sae-ext+ccmp"|"sae-ext+gcmp"|"sae-ext+ccmp256"|"sae-ext+gcmp256")
                        sae_pwe="2"
                        ;;
                    *)
                        # 其他加密方式不使用 SAE，sae_pwe 保持为空，对应 ApCliPweMethod=0
                        ;;
                esac
            fi
            
            # 将 sae_pwe 转换为 ApCliPweMethod（参考 mtkdat.lua 行 2990-2996）
            # 映射关系：
            #   sae_pwe=2 或 nil → ApCliPweMethod=0
            #   sae_pwe=0 → ApCliPweMethod=1
            #   sae_pwe=1 → ApCliPweMethod=2
            local apcli_pwe_method="0"  # 默认值（对应 sae_pwe=nil 或 sae_pwe=2）
            if [ -n "$sae_pwe" ]; then
                case "$sae_pwe" in
                    "0")
                        apcli_pwe_method="1"  # sae_pwe=0 → ApCliPweMethod=1
                        ;;
                    "1")
                        apcli_pwe_method="2"  # sae_pwe=1 → ApCliPweMethod=2
                        ;;
                    "2")
                        apcli_pwe_method="0"  # sae_pwe=2 → ApCliPweMethod=0
                        ;;
                    *)
                        apcli_pwe_method="0"  # 其他值默认使用 0
                        ;;
                esac
            fi
            
            # 更新 ApCliPweMethod
            update_single_value "$dat_file" "ApCliPweMethod" "$apcli_pwe_method"
            
            # 更新其他 ApCli 参数（参考 mtkdat.lua 行 2935-3008 apcli2cfg 函数）
            local apcli_macaddr=$(get_uci_value "wifi-iface" "$iface_name" "macaddr")
            local apcli_ssid=$(get_uci_value "wifi-iface" "$iface_name" "ssid")
            local apcli_bssid=$(get_uci_value "wifi-iface" "$iface_name" "bssid")
            local apcli_key=$(get_uci_value "wifi-iface" "$iface_name" "key")
            local apcli_ieee80211w=$(get_uci_value "wifi-iface" "$iface_name" "ieee80211w")
            local apcli_pmf_sha256=$(get_uci_value "wifi-iface" "$iface_name" "pmf_sha256")
            local apcli_owetrante=$(get_uci_value "wifi-iface" "$iface_name" "owetrante")
            local apcli_mac_repeateren=$(get_uci_value "wifi-iface" "$iface_name" "mac_repeateren")
            local apcli_sae_groups=$(get_uci_value "wifi-iface" "$iface_name" "sae_groups")
            local apcli_wireless_mode=$(get_uci_value "wifi-iface" "$iface_name" "wireless_mode")
            
            # 更新 ApCliSsid
            if [ -n "$apcli_ssid" ]; then
                update_single_value "$dat_file" "ApCliSsid" "$apcli_ssid"
            fi
            
            # 更新 ApCliBssid
            if [ -n "$apcli_bssid" ]; then
                update_single_value "$dat_file" "ApCliBssid" "$apcli_bssid"
            fi
            
            # 更新 ApcliMacAddress
            if [ -n "$apcli_macaddr" ]; then
                update_single_value "$dat_file" "ApcliMacAddress" "$apcli_macaddr"
            fi
            
            # 更新 ApCliWPAPSK（参考 mtkdat.lua 行 2955-2958）
            if [ -n "$apcli_key" ]; then
                update_single_value "$dat_file" "ApCliWPAPSK" "$apcli_key"
            fi
            
            # 更新 ApCliPMFMFPC 和 ApCliPMFMFPR（参考 mtkdat.lua 行 2960-2969）
            if [ -n "$apcli_ieee80211w" ]; then
                if [ "$apcli_ieee80211w" = "2" ]; then
                    update_single_value "$dat_file" "ApCliPMFMFPC" "1"
                    update_single_value "$dat_file" "ApCliPMFMFPR" "1"
                elif [ "$apcli_ieee80211w" = "1" ]; then
                    update_single_value "$dat_file" "ApCliPMFMFPC" "1"
                    update_single_value "$dat_file" "ApCliPMFMFPR" "0"
                else
                    update_single_value "$dat_file" "ApCliPMFMFPC" "0"
                    update_single_value "$dat_file" "ApCliPMFMFPR" "0"
                fi
            fi
            
            # 更新 ApCliPMFSHA256（参考 mtkdat.lua 行 2971）
            if [ -n "$apcli_pmf_sha256" ]; then
                update_single_value "$dat_file" "ApCliPMFSHA256" "$apcli_pmf_sha256"
            fi
            
            # 更新 ApCliOWETranIe（参考 mtkdat.lua 行 2972）
            if [ -n "$apcli_owetrante" ]; then
                update_single_value "$dat_file" "ApCliOWETranIe" "$apcli_owetrante"
            fi
            
            # 更新 MACRepeaterEn（参考 mtkdat.lua 行 2973）
            if [ -n "$apcli_mac_repeateren" ]; then
                update_single_value "$dat_file" "MACRepeaterEn" "$apcli_mac_repeateren"
            fi
            
            # 更新 ApCliSaeGroups（参考 mtkdat.lua 行 2998-3004）
            if [ -n "$apcli_sae_groups" ]; then
                update_single_value "$dat_file" "ApCliSaeGroups" "$apcli_sae_groups"
            else
                # 默认值为 "19"（参考 mtkdat.lua 行 3003）
                update_single_value "$dat_file" "ApCliSaeGroups" "19"
            fi
            
            # 更新 ApCliWirelessMode（参考 mtkdat.lua 行 3006）
            if [ -n "$apcli_wireless_mode" ]; then
                update_single_value "$dat_file" "ApCliWirelessMode" "$apcli_wireless_mode"
            fi
            
            # 更新 ApCliEnable（参考 mtkdat.lua 行 2936-2940）
            # 如果接口被禁用，ApCliEnable=0，否则为 1
            if [ "$iface_disabled" = "1" ] || [ "$device_disabled" = "1" ]; then
                update_single_value "$dat_file" "ApCliEnable" "0"
            else
                update_single_value "$dat_file" "ApCliEnable" "1"
            fi
            
            # 更新 ApCliAuthMode 和 ApCliEncrypType（参考 mtkdat.lua 行 2946-2948）
            # 使用 uci2dat_encryption 函数，第三个参数为 true 表示 ApCli 模式
            local apcli_encryption=$(get_uci_value "wifi-iface" "$iface_name" "encryption")
            if [ -n "$apcli_encryption" ]; then
                local apcli_auth_mode apcli_enc_type
                
                # 根据 mtkdat.lua 的 uci2dat_encryption 函数逻辑（apcli=true）
                case "$apcli_encryption" in
                    "none")
                        apcli_auth_mode="OPEN"
                        apcli_enc_type="NONE"
                        ;;
                    "wpa+tkip")
                        apcli_auth_mode="WPA"
                        apcli_enc_type="TKIP"
                        ;;
                    "wpa+tkip+ccmp")
                        apcli_auth_mode="WPA"
                        apcli_enc_type="TKIPAES"
                        ;;
                    "wpa+ccmp")
                        apcli_auth_mode="WPA"
                        apcli_enc_type="AES"
                        ;;
                    "wpa2+tkip")
                        apcli_auth_mode="WPA2"
                        apcli_enc_type="TKIP"
                        ;;
                    "wpa2+tkip+ccmp")
                        apcli_auth_mode="WPA2"
                        apcli_enc_type="TKIPAES"
                        ;;
                    "wpa2+ccmp")
                        apcli_auth_mode="WPA2"
                        apcli_enc_type="AES"
                        ;;
                    "wpa3")
                        apcli_auth_mode="WPA3"
                        apcli_enc_type="AES"
                        ;;
                    "wpa3-192")
                        apcli_auth_mode="WPA3-192"
                        apcli_enc_type="GCMP256"
                        ;;
                    "psk+ccmp")
                        apcli_auth_mode="WPAPSK"
                        apcli_enc_type="AES"
                        ;;
                    "psk+tkip")
                        apcli_auth_mode="WPAPSK"
                        apcli_enc_type="TKIP"
                        ;;
                    "psk+tkip+ccmp")
                        apcli_auth_mode="WPAPSK"
                        apcli_enc_type="TKIPAES"
                        ;;
                    "psk2+ccmp"|"psk2")
                        apcli_auth_mode="WPA2PSK"
                        apcli_enc_type="AES"
                        ;;
                    "psk2+tkip")
                        apcli_auth_mode="WPA2PSK"
                        apcli_enc_type="TKIP"
                        ;;
                    "psk2+tkip+ccmp")
                        apcli_auth_mode="WPA2PSK"
                        apcli_enc_type="TKIPAES"
                        ;;
                    "sae")
                        # ApCli 模式下使用 WPA3PSK 和 CCMP128（参考 mtkdat.lua 行 1563-1569）
                        apcli_auth_mode="WPA3PSK"
                        apcli_enc_type="CCMP128"
                        ;;
                    "sae+ccmp")
                        # ApCli 模式下使用 WPA3PSK 和 CCMP128（参考 mtkdat.lua 行 1570-1577）
                        apcli_auth_mode="WPA3PSK"
                        apcli_enc_type="CCMP128"
                        ;;
                    "sae+gcmp")
                        # ApCli 模式下使用 WPA3PSK 和 GCMP128（参考 mtkdat.lua 行 1578-1585）
                        apcli_auth_mode="WPA3PSK"
                        apcli_enc_type="GCMP128"
                        ;;
                    "sae+ccmp256")
                        # ApCli 模式下使用 WPA3PSK 和 CCMP256（参考 mtkdat.lua 行 1586-1593）
                        apcli_auth_mode="WPA3PSK"
                        apcli_enc_type="CCMP256"
                        ;;
                    "sae+gcmp256")
                        # ApCli 模式下使用 WPA3PSK 和 GCMP256（参考 mtkdat.lua 行 1594-1601）
                        apcli_auth_mode="WPA3PSK"
                        apcli_enc_type="GCMP256"
                        ;;
                    "sae-ext")
                        apcli_auth_mode="WPA3PSK_EXT"
                        apcli_enc_type="GCMP256"
                        ;;
                    "sae-ext+ccmp")
                        apcli_auth_mode="WPA3PSK_EXT"
                        apcli_enc_type="CCMP128"
                        ;;
                    "sae-ext+gcmp")
                        apcli_auth_mode="WPA3PSK_EXT"
                        apcli_enc_type="GCMP128"
                        ;;
                    "sae-ext+ccmp256")
                        apcli_auth_mode="WPA3PSK_EXT"
                        apcli_enc_type="CCMP256"
                        ;;
                    "sae-ext+gcmp256")
                        apcli_auth_mode="WPA3PSK_EXT"
                        apcli_enc_type="GCMP256"
                        ;;
                    "psk-mixed+tkip")
                        apcli_auth_mode="WPAPSK,WPA2PSK"
                        apcli_enc_type="TKIP"
                        ;;
                    "psk-mixed+tkip+ccmp")
                        apcli_auth_mode="WPAPSK,WPA2PSK"
                        apcli_enc_type="TKIPAES"
                        ;;
                    "psk-mixed+ccmp")
                        apcli_auth_mode="WPAPSK,WPA2PSK"
                        apcli_enc_type="AES"
                        ;;
                    "sae-mixed")
                        # 根据 pmf_sha256 决定（参考 mtkdat.lua 行 1626-1632）
                        if [ "$apcli_pmf_sha256" = "1" ]; then
                            apcli_auth_mode="WPA2PSKMIXWPA3PSK,WPA3PSK_EXT"
                        else
                            apcli_auth_mode="WPA2PSKWPA3PSK,WPA3PSK_EXT"
                        fi
                        apcli_enc_type="CCMP128,GCMP256"
                        ;;
                    "owe")
                        apcli_auth_mode="OWE"
                        apcli_enc_type="AES"
                        ;;
                    *)
                        apcli_auth_mode="OPEN"
                        apcli_enc_type="NONE"
                        ;;
                esac
                
                # 更新 ApCliAuthMode 和 ApCliEncrypType
                update_single_value "$dat_file" "ApCliAuthMode" "$apcli_auth_mode"
                update_single_value "$dat_file" "ApCliEncrypType" "$apcli_enc_type"
            fi
            
            # 只处理第一个 station 模式接口（每个设备只有一个 ApCli）
            break
        fi
    done
}

# 更新令牌值的函数 (用于分号分隔的值)
# 模拟 mtkdat.lua 中的 token_set 函数
# 使用兼容 /bin/sh 的实现，不依赖数组语法
update_token_value() {
    local dat_file="$1"
    local param="$2"
    local index="$3"
    local value="$4"
    
    # 检查参数是否已存在
    if grep -q "^$param=" "$dat_file"; then
        # 获取当前值（取第一个匹配的行）
        local current_val=$(grep "^$param=" "$dat_file" | head -1 | cut -d'=' -f2-)
        local old_val="${current_val:-}"
        
        # 使用临时文件处理分号分隔的值
        local tmp_file=$(mktemp)
        if [ -n "$old_val" ]; then
            # 将分号分隔的值转换为行
            echo "$old_val" | tr ';' '\n' > "$tmp_file"
        else
            # 如果 old_val 为空，创建一个空文件
            > "$tmp_file"
        fi
        
        # 计算当前行数（排除空行）
        local count=$(grep -c . "$tmp_file" 2>/dev/null || echo "0")
        if [ -z "$old_val" ]; then
            count=0
        fi
        
        # 如果当前值数量小于索引，需要扩展
        if [ $count -lt $index ]; then
            # 获取最后一个值作为填充值
            local last_val="0"
            if [ $count -gt 0 ]; then
                last_val=$(grep . "$tmp_file" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            fi
            if [ -z "$last_val" ]; then
                last_val="0"
            fi
            
            # 扩展文件（添加缺失的值）
            local j
            j=$((count + 1))
            while [ $j -le $index ]; do
                echo "$last_val" >> "$tmp_file"
                j=$((j + 1))
            done
        fi
        
        # 确保文件至少有 index 行（如果不够，用 0 填充）
        local file_line_count=$(wc -l < "$tmp_file" 2>/dev/null || echo "0")
        while [ $file_line_count -lt $index ]; do
            echo "0" >> "$tmp_file"
            file_line_count=$((file_line_count + 1))
        done
        
        # 替换指定行的值（使用 sed 直接替换第 index 行）
        sed -i "${index}s/.*/$value/" "$tmp_file" 2>/dev/null
        
        # 重建字符串（过滤空行，然后用分号连接）
        local new_val=$(grep . "$tmp_file" 2>/dev/null | tr '\n' ';' | sed 's/;$//')
        if [ -z "$new_val" ]; then
            # 如果所有行都是空的，至少应该有一个值
            new_val="$value"
        fi
        rm -f "$tmp_file"
        
        # 更新文件（删除所有旧行，然后添加新行）
        update_single_value "$dat_file" "$param" "$new_val"
    else
        # 如果参数不存在，创建新的
        local new_val=""
        local i
        i=1
        while [ $i -le $index ]; do
            if [ $i -eq $index ]; then
                if [ $i -eq 1 ]; then
                    new_val="$value"
                else
                    new_val="$new_val;$value"
                fi
            else
                if [ $i -eq 1 ]; then
                    new_val="0"
                else
                    new_val="$new_val;0"
                fi
            fi
            i=$((i + 1))
        done
        echo "$param=$new_val" >> "$dat_file"
    fi
}

update_single_value() {
    local dat_file="$1"
    local param="$2"
    local value="$3"
    
    # 单值参数：直接替换或添加，不需要分号分隔的多值
    # 检查参数是否已存在
    if grep -q "^$param=" "$dat_file"; then
        # 删除所有旧行（可能有多个匹配）
        sed -i "/^$param=/d" "$dat_file"
    fi
    
    # 添加新行
    echo "$param=$value" >> "$dat_file"
}

# 处理加密设置的函数（基于 mtkdat.lua 的 uci2dat_encryption）
process_encryption() {
    local encryption="$1"
    local key="$2"
    local index="$3"
    local dat_file="$4"
    local pmf_sha256="${5:-0}"  # 可选参数，默认为0
    
    local auth_mode enc_type
    
    # 根据 mtkdat.lua 的 uci2dat_encryption 函数逻辑
    case "$encryption" in
        "none")
            auth_mode="OPEN"
            enc_type="NONE"
            ;;
        "wpa+tkip")
            auth_mode="WPA"
            enc_type="TKIP"
            ;;
        "wpa+tkip+ccmp")
            auth_mode="WPA"
            enc_type="TKIPAES"
            ;;
        "wpa+ccmp")
            auth_mode="WPA"
            enc_type="AES"
            ;;
        "wpa2+tkip")
            auth_mode="WPA2"
            enc_type="TKIP"
            ;;
        "wpa2+tkip+ccmp")
            auth_mode="WPA2"
            enc_type="TKIPAES"
            ;;
        "wpa2+ccmp")
            auth_mode="WPA2"
            enc_type="AES"
            ;;
        "wpa3")
            auth_mode="WPA3"
            enc_type="AES"
            ;;
        "wpa3-192")
            auth_mode="WPA3-192"
            enc_type="GCMP256"
            ;;
        "psk+ccmp")
            auth_mode="WPAPSK"
            enc_type="AES"
            ;;
        "psk+tkip")
            auth_mode="WPAPSK"
            enc_type="TKIP"
            ;;
        "psk+tkip+ccmp")
            auth_mode="WPAPSK"
            enc_type="TKIPAES"
            ;;
        "psk"|"psk+tkip")
            auth_mode="WPAPSK"
            enc_type="TKIP"
            ;;
        "psk2+ccmp"|"psk2")
            auth_mode="WPA2PSK"
            enc_type="AES"
            ;;
        "psk2+tkip")
            auth_mode="WPA2PSK"
            enc_type="TKIP"
            ;;
        "psk2+tkip+ccmp")
            auth_mode="WPA2PSK"
            enc_type="TKIPAES"
            ;;
        "sae")
            # 根据 mtkdat.lua，sae 在非 apcli 模式下使用 WPA3PSK,WPA3PSK_EXT 和 CCMP128,GCMP256
            auth_mode="WPA3PSK,WPA3PSK_EXT"
            enc_type="CCMP128,GCMP256"
            ;;
        "sae+ccmp")
            auth_mode="WPA3PSK,WPA3PSK_EXT"
            enc_type="CCMP128"
            ;;
        "sae+gcmp")
            auth_mode="WPA3PSK,WPA3PSK_EXT"
            enc_type="GCMP128"
            ;;
        "sae+ccmp256")
            auth_mode="WPA3PSK,WPA3PSK_EXT"
            enc_type="CCMP256"
            ;;
        "sae+gcmp256")
            auth_mode="WPA3PSK,WPA3PSK_EXT"
            enc_type="GCMP256"
            ;;
        "sae-ext")
            auth_mode="WPA3PSK_EXT"
            enc_type="GCMP256"
            ;;
        "sae-mixed")
            # 根据 pmf_sha256 决定
            if [ "$pmf_sha256" = "1" ]; then
                auth_mode="WPA2PSKMIXWPA3PSK,WPA3PSK_EXT"
            else
                auth_mode="WPA2PSKWPA3PSK,WPA3PSK_EXT"
            fi
            enc_type="CCMP128,GCMP256"
            ;;
        "psk-mixed+tkip")
            auth_mode="WPAPSK,WPA2PSK"
            enc_type="TKIP"
            ;;
        "psk-mixed+tkip+ccmp")
            auth_mode="WPAPSK,WPA2PSK"
            enc_type="TKIPAES"
            ;;
        "psk-mixed+ccmp")
            auth_mode="WPAPSK,WPA2PSK"
            enc_type="AES"
            ;;
        "wpa-mixed+tkip")
            auth_mode="WPA1WPA2"
            enc_type="TKIP"
            ;;
        "wpa-mixed+ccmp")
            auth_mode="WPA1WPA2"
            enc_type="AES"
            ;;
        "wpa-mixed+tkip+ccmp")
            auth_mode="WPA1WPA2"
            enc_type="TKIPAES"
            ;;
        "wpa3-mixed")
            auth_mode="WPA3WPA2"
            enc_type="AES"
            ;;
        "owe")
            auth_mode="OWE"
            enc_type="AES"
            ;;
        *)
            auth_mode="OPEN"
            enc_type="NONE"
            ;;
    esac
    
    # 更新认证模式和加密类型
    update_token_value "$dat_file" "AuthMode" "$index" "$auth_mode"
    update_token_value "$dat_file" "EncrypType" "$index" "$enc_type"
    
    # 如果有密钥，也要更新（使用 WPAPSK1, WPAPSK2 等格式）
    if [ -n "$key" ] && [ "$encryption" != "none" ]; then
        # 删除旧的密钥行（如果存在）
        update_single_value "$dat_file" "WPAPSK${index}" "$key"
    fi
}

# 从 UCI 配置生成 hostapd 配置
generate_hostapd_from_uci() {
    echo "🔍 正在从 UCI 配置生成 hostapd 配置..."

    # 遍历所有 AP 模式的接口
    for iface_name in $(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        local mode=$(get_uci_value "wifi-iface" "$iface_name" "mode")
        local device=$(get_uci_value "wifi-iface" "$iface_name" "device")
        
        if [ "$mode" = "ap" ]; then
            local ssid=$(get_uci_value "wifi-iface" "$iface_name" "ssid")
            local encryption=$(get_uci_value "wifi-iface" "$iface_name" "encryption")
            local key=$(get_uci_value "wifi-iface" "$iface_name" "key")
            local network=$(get_uci_value "wifi-iface" "$iface_name" "network")
            
            # 获取设备参数
            local channel=$(get_uci_value "wifi-device" "$device" "channel")
            local band=$(get_uci_value "wifi-device" "$device" "band")
            local htmode=$(get_uci_value "wifi-device" "$device" "htmode")
            
            # 获取物理接口名
            local physical_ifname=$(get_physical_ifname "$iface_name" "$device")
            
            # 从物理接口名提取 phy（如 phy0-ap0 -> phy0）
            # 匹配 mac80211.sh 的文件名格式：/var/run/hostapd-$phy.conf
            local phy=""
            if echo "$physical_ifname" | grep -qE '^phy[0-9]+'; then
                # phy0-ap0 -> phy0
                phy=$(echo "$physical_ifname" | sed 's/-.*$//')
            elif echo "$physical_ifname" | grep -qE '^ra[0-9]+'; then
                # ra0 -> phy0 (假设 ra0 对应 phy0)
                local ra_num=$(echo "$physical_ifname" | sed 's/ra//')
                phy="phy${ra_num}"
            else
                # 如果无法提取，尝试从设备名推断（radio0 -> phy0）
                local dev_idx=0
                for dev_name in $(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1 | sort); do
                    if [ "$dev_name" = "$device" ]; then
                        phy="phy${dev_idx}"
                        break
                    fi
                    dev_idx=$((dev_idx + 1))
                done
            fi
            
            # 如果仍然无法确定 phy，使用默认值
            [ -z "$phy" ] && phy="phy0"
            
            # 生成 hostapd 配置文件（匹配 mac80211.sh 的格式：/var/run/hostapd-$phy.conf）
            local conf_file="/var/run/hostapd-$phy.conf"
            echo "# Generated hostapd configuration for $iface_name" > "$conf_file"
            echo "# Created at $(date)" >> "$conf_file"
            echo "" >> "$conf_file"
            
            # 基本配置
            echo "interface=$physical_ifname" >> "$conf_file"
            [ -n "$ssid" ] && echo "ssid=$ssid" >> "$conf_file"
            echo "hw_mode=g" >> "$conf_file"  # 默认 2.4GHz
            
            if [ "$band" = "5G" ]; then
                echo "hw_mode=a" >> "$conf_file"
            elif [ "$band" = "6G" ]; then
                echo "hw_mode=a" >> "$conf_file"
            fi
            
            [ -n "$channel" ] && echo "channel=$channel" >> "$conf_file"
            
            # 根据 HT 模式设置
            case "$htmode" in
                "HT20")
                    echo "ieee80211n=1" >> "$conf_file"
                    echo "ht_capab=[HT20]" >> "$conf_file"
                    ;;
                "HT40+"|"HT40-")
                    echo "ieee80211n=1" >> "$conf_file"
                    echo "ht_capab=[HT40]" >> "$conf_file"
                    ;;
                "VHT20")
                    echo "ieee80211n=1" >> "$conf_file"
                    echo "ieee80211ac=1" >> "$conf_file"
                    echo "vht_capab=[VHT20]" >> "$conf_file"
                    ;;
                "VHT40"|"VHT80"|"VHT160")
                    echo "ieee80211n=1" >> "$conf_file"
                    echo "ieee80211ac=1" >> "$conf_file"
                    echo "vht_oper_chwidth=1" >> "$conf_file"
                    ;;
            esac
            
            # 桥接配置
            if [ -n "$network" ]; then
                echo "bridge=br-$network" >> "$conf_file"
            else
                echo "bridge=br-lan" >> "$conf_file"
            fi
            
            # 安全配置
            case "$encryption" in
                "psk2"|"wpa2")
                    echo "auth_algs=1" >> "$conf_file"
                    echo "wpa=2" >> "$conf_file"
                    echo "wpa_key_mgmt=WPA-PSK" >> "$conf_file"
                    echo "rsn_pairwise=CCMP" >> "$conf_file"
                    [ -n "$key" ] && echo "wpa_passphrase=$key" >> "$conf_file"
                    ;;
                "psk"|"wpa")
                    echo "auth_algs=1" >> "$conf_file"
                    echo "wpa=1" >> "$conf_file"
                    echo "wpa_key_mgmt=WPA-PSK" >> "$conf_file"
                    echo "wpa_pairwise=TKIP" >> "$conf_file"
                    [ -n "$key" ] && echo "wpa_passphrase=$key" >> "$conf_file"
                    ;;
                "sae"|"wpa3")
                    echo "auth_algs=1" >> "$conf_file"
                    echo "wpa=2" >> "$conf_file"
                    echo "wpa_key_mgmt=SAE" >> "$conf_file"
                    echo "rsn_pairwise=CCMP" >> "$conf_file"
                    [ -n "$key" ] && echo "sae_password=$key" >> "$conf_file"
                    echo "sae_pwe=2" >> "$conf_file"
                    ;;
                "sae-mixed")
                    echo "auth_algs=1" >> "$conf_file"
                    echo "wpa=2" >> "$conf_file"
                    echo "wpa_key_mgmt=WPA-PSK SAE" >> "$conf_file"
                    echo "rsn_pairwise=CCMP TKIP" >> "$conf_file"
                    [ -n "$key" ] && echo "wpa_passphrase=$key" >> "$conf_file"
                    [ -n "$key" ] && echo "sae_password=$key" >> "$conf_file"
                    echo "sae_pwe=2" >> "$conf_file"
                    ;;
                *)
                    echo "auth_algs=1" >> "$conf_file"
                    echo "wpa=0" >> "$conf_file"
                    ;;
            esac
            
            # 其他常用配置
            echo "wmm_enabled=1" >> "$conf_file"
            echo "ignore_broadcast_ssid=0" >> "$conf_file"
            echo "ctrl_interface=/var/run/hostapd" >> "$conf_file"
            echo "ap_isolate=0" >> "$conf_file"
            
            echo "✅ 已生成 hostapd 配置: $conf_file"
        fi
    done
    
    echo "✅ hostapd 配置生成完成"
}

# 模拟 mtkdat.auth2hostapd_encryption 函数
auth2hostapd_encryption() {
    local encryption="$1"
    local key="$2"
    
    case "$encryption" in
        "none")
            echo "auth_algs=1"
            echo "wpa="
            ;;
        "wep-open")
            echo "auth_algs=1"
            echo "wpa=0"
            ;;
        "wep-shared")
            echo "auth_algs=2"
            echo "wpa=0"
            ;;
        "wep-auto")
            echo "auth_algs=3"
            echo "wpa=0"
            ;;
        "wpa+tkip")
            echo "auth_algs=1"
            echo "wpa=1"
            echo "wpa_key_mgmt=WPA-EAP"
            echo "wpa_pairwise=TKIP"
            ;;
        "wpa+ccmp")
            echo "auth_algs=1"
            echo "wpa=1"
            echo "wpa_key_mgmt=WPA-EAP"
            echo "wpa_pairwise=CCMP"
            ;;
        "wpa2+tkip")
            echo "auth_algs=1"
            echo "wpa=2"
            echo "wpa_key_mgmt=WPA-EAP"
            echo "rsn_pairwise=TKIP"
            ;;
        "wpa2+ccmp")
            echo "auth_algs=1"
            echo "wpa=2"
            echo "wpa_key_mgmt=WPA-EAP"
            echo "rsn_pairwise=CCMP"
            ;;
        "psk")
            echo "auth_algs=1"
            echo "wpa=1"
            echo "wpa_key_mgmt=WPA-PSK"
            echo "wpa_pairwise=TKIP"
            [ -n "$key" ] && echo "wpa_passphrase=$key"
            ;;
        "psk2")
            echo "auth_algs=1"
            echo "wpa=2"
            echo "wpa_key_mgmt=WPA-PSK"
            echo "rsn_pairwise=CCMP"
            [ -n "$key" ] && echo "wpa_passphrase=$key"
            ;;
        "psk-mixed")
            echo "auth_algs=1"
            echo "wpa=3"
            echo "wpa_key_mgmt=WPA-PSK"
            echo "wpa_pairwise=TKIP CCMP"
            [ -n "$key" ] && echo "wpa_passphrase=$key"
            ;;
        "sae")
            echo "auth_algs=1"
            echo "wpa=2"
            echo "wpa_key_mgmt=SAE"
            echo "rsn_pairwise=CCMP"
            echo "ieee80211w=2"
            [ -n "$key" ] && echo "sae_password=$key"
            ;;
        "sae-mixed")
            echo "auth_algs=1"
            echo "wpa=2"
            echo "wpa_key_mgmt=WPA-PSK SAE"
            echo "rsn_pairwise=CCMP"
            echo "ieee80211w=1"
            [ -n "$key" ] && echo "wpa_passphrase=$key"
            [ -n "$key" ] && echo "sae_password=$key"
            ;;
        "owe")
            echo "auth_algs=1"
            echo "wpa=2"
            echo "wpa_key_mgmt=OWE"
            echo "rsn_pairwise=CCMP"
            ;;
        *)
            echo "auth_algs=1"
            echo "wpa=0"
            ;;
esac
}

# 改进的 hostapd 配置生成函数，使用 auth2hostapd_encryption 函数
generate_hostapd_from_uci_improved() {
    local target_phy="$1"
    echo "🔍 正在从 UCI 配置生成改进版 hostapd 配置..."
    [ -n "$target_phy" ] && logger -t mtk_wifi_config "Generate hostapd confs for target phy: $target_phy"

    # 先按设备分组，为每个设备下的每个SSID分配索引
    # 遍历所有设备
    for device in $(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1 | sort); do
        # 确定该设备对应的phy
        local phy=""
        local dev_idx=0
        for dev_name in $(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1 | sort); do
            if [ "$dev_name" = "$device" ]; then
                phy="phy${dev_idx}"
                break
            fi
            dev_idx=$((dev_idx + 1))
        done
        [ -z "$phy" ] && phy="phy0"

        # 只处理目标 phy，避免不同 radio 的 reload 互相删除配置文件
        [ -n "$target_phy" ] && [ "$target_phy" != "$phy" ] && continue
        
        # 清理该phy的所有旧配置文件（在生成新配置前）
        # 注意：只删除配置文件，不删除pid文件和VAP接口（因为进程可能还在运行）
        # pid文件和接口的清理应该在hostapd_set_config中进行
        logger -t mtk_wifi_config "Cleaning up old hostapd configs for $phy"
        for old_conf in /var/run/hostapd-${phy}-ap*.conf; do
            [ -f "$old_conf" ] && rm -f "$old_conf"
        done
        
        local ap_index=0  # 每个设备下的AP索引从0开始
        
        # 遍历该设备下的所有AP模式接口
        for iface_name in $(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
            local mode=$(get_uci_value "wifi-iface" "$iface_name" "mode")
            local iface_device=$(get_uci_value "wifi-iface" "$iface_name" "device")
            
            # 只处理当前设备下的AP模式接口
            if [ "$mode" = "ap" ] && [ "$iface_device" = "$device" ]; then
            # 检查接口是否被禁用
            local iface_disabled=$(get_uci_value "wifi-iface" "$iface_name" "disabled")
            # 检查设备是否被禁用
            local device_disabled=$(get_uci_value "wifi-device" "$device" "disabled")
            
            # 如果接口或设备被禁用，跳过生成配置
            if [ "$iface_disabled" = "1" ] || [ "$device_disabled" = "1" ]; then
                continue
            fi
            
            local ssid=$(get_uci_value "wifi-iface" "$iface_name" "ssid")
            local encryption=$(get_uci_value "wifi-iface" "$iface_name" "encryption")
            local key=$(get_uci_value "wifi-iface" "$iface_name" "key")
            local network=$(get_uci_value "wifi-iface" "$iface_name" "network")
            
            # 获取设备参数
            local channel=$(get_uci_value "wifi-device" "$device" "channel")
            # band 将在后面通过 map_band_value 转换（在写入 hw_mode 之前）
            local htmode=$(get_uci_value "wifi-device" "$device" "htmode")
            # beacon_int: 先检查 wifi-iface，如果没有再检查 wifi-device（参考 hostapd.lua 行 1327-1334）
            local beacon_int=$(get_uci_value "wifi-iface" "$iface_name" "beacon_int")
            [ -z "$beacon_int" ] && beacon_int=$(get_uci_value "wifi-device" "$device" "beacon_int")
            local max_listen_interval=$(get_uci_value "wifi-iface" "$iface_name" "max_listen_interval")
            local dtim_period=$(get_uci_value "wifi-iface" "$iface_name" "dtim_period")
            local hidden=$(get_uci_value "wifi-iface" "$iface_name" "hidden")
            local wmm=$(get_uci_value "wifi-iface" "$iface_name" "wmm")
            local isolate=$(get_uci_value "wifi-iface" "$iface_name" "isolate")
            local rts=$(get_uci_value "wifi-iface" "$iface_name" "rts")
            local frag=$(get_uci_value "wifi-iface" "$iface_name" "frag")
            local apsd_capable=$(get_uci_value "wifi-iface" "$iface_name" "apsd_capable")
            local vht_ldpc=$(get_uci_value "wifi-iface" "$iface_name" "vht_ldpc")
            local vht_stbc=$(get_uci_value "wifi-iface" "$iface_name" "vht_stbc")
            local vht_sgi=$(get_uci_value "wifi-iface" "$iface_name" "vht_sgi")
            local ht_ldpc=$(get_uci_value "wifi-iface" "$iface_name" "ht_ldpc")
            local ht_stbc=$(get_uci_value "wifi-iface" "$iface_name" "ht_stbc")
            local ht_protect=$(get_uci_value "wifi-iface" "$iface_name" "ht_protect")
            local ht_gi=$(get_uci_value "wifi-iface" "$iface_name" "ht_gi")
            local ht_opmode=$(get_uci_value "wifi-iface" "$iface_name" "ht_opmode")
            local ht_amsdu=$(get_uci_value "wifi-iface" "$iface_name" "ht_amsdu")
            local ht_autoba=$(get_uci_value "wifi-iface" "$iface_name" "ht_autoba")
            local ht_badec=$(get_uci_value "wifi-iface" "$iface_name" "ht_badec")
            local ht_bawinsize=$(get_uci_value "wifi-iface" "$iface_name" "ht_bawinsize")
            local igmpsn_enable=$(get_uci_value "wifi-iface" "$iface_name" "igmpsn_enable")
            local ieee80211w=$(get_uci_value "wifi-iface" "$iface_name" "ieee80211w")
            local pmf_sha256=$(get_uci_value "wifi-iface" "$iface_name" "pmf_sha256")
            local mbo=$(get_uci_value "wifi-iface" "$iface_name" "mbo")
            local proxy_arp=$(get_uci_value "wifi-iface" "$iface_name" "proxy_arp")
            local ieee8021x=$(get_uci_value "wifi-iface" "$iface_name" "ieee8021x")
            local auth_server=$(get_uci_value "wifi-iface" "$iface_name" "auth_server")
            local auth_port=$(get_uci_value "wifi-iface" "$iface_name" "auth_port")
            local ownip=$(get_uci_value "wifi-iface" "$iface_name" "ownip")
            local idle_timeout=$(get_uci_value "wifi-iface" "$iface_name" "idle_timeout")
            local session_timeout=$(get_uci_value "wifi-iface" "$iface_name" "session_timeout")
            local rsn_preauth=$(get_uci_value "wifi-iface" "$iface_name" "rsn_preauth")
            local pmk_cache_period=$(get_uci_value "wifi-iface" "$iface_name" "pmk_cache_period")
            local rekey_interval=$(get_uci_value "wifi-iface" "$iface_name" "rekey_interval")
            local rekey_meth=$(get_uci_value "wifi-iface" "$iface_name" "rekey_meth")
            local tx_rate=$(get_uci_value "wifi-iface" "$iface_name" "tx_rate")
            local vht_bw_signal=$(get_uci_value "wifi-iface" "$iface_name" "vht_bw_signal")
            local ht_mpdu_density=$(get_uci_value "wifi-iface" "$iface_name" "ht_mpdu_density")
            local mrsno_enable=$(get_uci_value "wifi-iface" "$iface_name" "mrsno_enable")
            local encryption_override=$(get_uci_value "wifi-iface" "$iface_name" "encryption_override")
            local encryption_override_2=$(get_uci_value "wifi-iface" "$iface_name" "encryption_override_2")
            local auth_secret=$(get_uci_value "wifi-iface" "$iface_name" "auth_secret")
            local ieee80211r=$(get_uci_value "wifi-iface" "$iface_name" "ieee80211r")
            local mobility_domain=$(get_uci_value "wifi-iface" "$iface_name" "mobility_domain")
            local ft_psk_generate_local=$(get_uci_value "wifi-iface" "$iface_name" "ft_psk_generate_local")
            local ft_over_ds=$(get_uci_value "wifi-iface" "$iface_name" "ft_over_ds")
            local reassociation_deadline=$(get_uci_value "wifi-iface" "$iface_name" "reassociation_deadline")
            local r0_key_lifetime=$(get_uci_value "wifi-iface" "$iface_name" "r0_key_lifetime")
            local pmk_r1_push=$(get_uci_value "wifi-iface" "$iface_name" "pmk_r1_push")
            local r0kh=$(get_uci_value "wifi-iface" "$iface_name" "r0kh")
            local r1kh=$(get_uci_value "wifi-iface" "$iface_name" "r1kh")
            local wps_state=$(get_uci_value "wifi-iface" "$iface_name" "wps_state")
            local wps_pin=$(get_uci_value "wifi-iface" "$iface_name" "wps_pin")
            local ext_registrar=$(get_uci_value "wifi-iface" "$iface_name" "ext_registrar")
            local wps_label=$(get_uci_value "wifi-iface" "$iface_name" "wps_label")
            local wps_pushbutton=$(get_uci_value "wifi-iface" "$iface_name" "wps_pushbutton")
            local wps_device_name=$(get_uci_value "wifi-iface" "$iface_name" "wps_device_name")
            local wps_device_type=$(get_uci_value "wifi-iface" "$iface_name" "wps_device_type")
            local wps_manufacturer=$(get_uci_value "wifi-iface" "$iface_name" "wps_manufacturer")
            local wps_cred_add_sae=$(get_uci_value "wifi-iface" "$iface_name" "wps_cred_add_sae")
            local multi_ap=$(get_uci_value "wifi-iface" "$iface_name" "multi_ap")
            local multi_ap_backhaul_ssid=$(get_uci_value "wifi-iface" "$iface_name" "multi_ap_backhaul_ssid")
            local multi_ap_backhaul_key=$(get_uci_value "wifi-iface" "$iface_name" "multi_ap_backhaul_key")
            local multi_ap_backhaul_key_mgmt=$(get_uci_value "wifi-iface" "$iface_name" "multi_ap_backhaul_key_mgmt")
            local uuid=$(get_uci_value "wifi-iface" "$iface_name" "uuid")
            local interworking=$(get_uci_value "wifi-iface" "$iface_name" "interworking")
            local oce=$(get_uci_value "wifi-iface" "$iface_name" "oce")
            local ieee80211k=$(get_uci_value "wifi-iface" "$iface_name" "ieee80211k")
            local rrm_neighbor_report=$(get_uci_value "wifi-iface" "$iface_name" "rrm_neighbor_report")
            local rrm_beacon_report=$(get_uci_value "wifi-iface" "$iface_name" "rrm_beacon_report")
            local bss_transition=$(get_uci_value "wifi-iface" "$iface_name" "bss_transition")
            local ocvc=$(get_uci_value "wifi-iface" "$iface_name" "ocv")
            local sae_groups=$(get_uci_value "wifi-iface" "$iface_name" "sae_groups")
            local sae_require_mfp=$(get_uci_value "wifi-iface" "$iface_name" "sae_require_mfp")
            local sae_pwe=$(get_uci_value "wifi-iface" "$iface_name" "sae_pwe")
            local owe_transition_bssid=$(get_uci_value "wifi-iface" "$iface_name" "owe_transition_bssid")
            local owe_transition_ssid=$(get_uci_value "wifi-iface" "$iface_name" "owe_transition_ssid")
            local owe_transition_ifname=$(get_uci_value "wifi-iface" "$iface_name" "owe_transition_ifname")
            local owe_groups=$(get_uci_value "wifi-iface" "$iface_name" "owe_groups")
            
            # 根据 phy 和 ap_index 生成物理接口名（如 phy0-ap0, phy0-ap1）
            local phy_num=$(echo "$phy" | sed 's/phy//')
            local physical_ifname="phy${phy_num}-ap${ap_index}"
            
            # 生成 hostapd 配置文件（格式：/var/run/hostapd-${phy}-ap${ap_index}.conf）
            local conf_file="/var/run/hostapd-${phy}-ap${ap_index}.conf"
            echo "# Generated hostapd configuration for $iface_name" > "$conf_file"
            echo "# Created at $(date)" >> "$conf_file"
            echo "" >> "$conf_file"
            
            # 基本配置（参考 hostapd.lua）
            echo "interface=$physical_ifname" >> "$conf_file"
            [ -n "$ssid" ] && echo "ssid=$ssid" >> "$conf_file"
            
            # 桥接配置
            if [ -n "$network" ]; then
                echo "bridge=br-$network" >> "$conf_file"
            else
                echo "bridge=br-lan" >> "$conf_file"
            fi
            
            # Channel 设置（参考 hostapd.lua 行 1277-1284）
            local acs=false
            if [ "$channel" = "auto" ] || [ "$channel" = "0" ] || [ -z "$channel" ]; then
                echo "channel=0" >> "$conf_file"
                acs=true
            else
                echo "channel=$channel" >> "$conf_file"
            fi
            
            # Driver（参考 hostapd.lua 行 1288）
            echo "driver=nl80211" >> "$conf_file"
            
            # 转换 band 格式（wireless-old 格式使用 2g/5g，需要转换为 2.4G/5G）
            local raw_band=$(get_uci_value "wifi-device" "$device" "band")
            local band=$(map_band_value "$raw_band")
            
            # 硬件模式（参考 hostapd.lua 行 1290-1324）
            if [ "$band" = "2.4G" ]; then
                if [ "$acs" = true ]; then
                    echo "hw_mode=any" >> "$conf_file"
                else
                    echo "hw_mode=g" >> "$conf_file"
                fi
                echo "preamble=1" >> "$conf_file"
                echo "ieee80211n=1" >> "$conf_file"
                echo "ieee80211ac=1" >> "$conf_file"
                echo "ieee80211ax=1" >> "$conf_file"
                echo "ieee80211be=1" >> "$conf_file"
            elif [ "$band" = "5G" ]; then
                if [ "$acs" = true ]; then
                    echo "hw_mode=any" >> "$conf_file"
                else
                    echo "hw_mode=a" >> "$conf_file"
                fi
                echo "ieee80211n=1" >> "$conf_file"
                echo "ieee80211ac=1" >> "$conf_file"
                echo "ieee80211ax=1" >> "$conf_file"
                echo "ieee80211be=1" >> "$conf_file"
            elif [ "$band" = "6G" ]; then
                if [ "$acs" = true ]; then
                    echo "hw_mode=any" >> "$conf_file"
                else
                    echo "hw_mode=a" >> "$conf_file"
                fi
                echo "ieee80211ax=1" >> "$conf_file"
                echo "ieee80211be=1" >> "$conf_file"
                echo "he_6ghz_max_mpdu=0" >> "$conf_file"
                echo "he_6ghz_max_ampdu_len_exp=0" >> "$conf_file"
                echo "he_6ghz_rx_ant_pat=0" >> "$conf_file"
                echo "he_6ghz_tx_ant_pat=0" >> "$conf_file"
                echo "op_class=131" >> "$conf_file"
            fi
            
            # noscan（参考 hostapd.lua 行 1325）
            echo "noscan=1" >> "$conf_file"
            
            # HT/VHT 能力配置（根据参数动态构建 ht_capab 和 vht_capab）
            # 如果参数未设置，根据 wireless_mode 或 htmode 自动启用
            local ht_capab_items=""
            local vht_capab_items=""
            
            # 确定带宽（用于 ht_capab 和 vht_capab）
            local ht_bw=""
            local vht_bw=""
            case "$htmode" in
                "HT20")
                    ht_bw="HT20"
                    ;;
                "HT40"|"HT40+"|"HT40-")
                    ht_bw="HT40"
                    ;;
                "VHT20")
                    vht_bw="VHT20"
                    ;;
                "VHT40")
                    vht_bw="VHT40"
                    ;;
                "VHT80")
                    vht_bw="VHT80"
                    ;;
                "VHT160"|"VHT80_80"|"VHT8080")
                    vht_bw="VHT160"
                    ;;
                "HE20"|"HE40"|"HE80"|"HE160"|"HE320")
                    # HE 模式也支持 VHT
                    case "$htmode" in
                        "HE20") vht_bw="VHT20" ;;
                        "HE40") vht_bw="VHT40" ;;
                        "HE80") vht_bw="VHT80" ;;
                        "HE160"|"HE320") vht_bw="VHT160" ;;
                    esac
                    ;;
                "EHT20"|"EHT40"|"EHT80"|"EHT160"|"EHT320")
                    # EHT 模式也支持 VHT
                    case "$htmode" in
                        "EHT20") vht_bw="VHT20" ;;
                        "EHT40") vht_bw="VHT40" ;;
                        "EHT80") vht_bw="VHT80" ;;
                        "EHT160"|"EHT320") vht_bw="VHT160" ;;
                    esac
                    ;;
            esac
            
            # 构建 HT 能力（如果启用了 ieee80211n）
            if [ -n "$ht_bw" ] || [ "$band" = "2.4G" ] || [ "$band" = "5G" ]; then
                # 如果参数未设置，根据 wireless_mode 自动启用
                # 这里我们根据 htmode 来判断，如果包含 HT/HE/EHT，则自动启用
                local ht_ldpc_val="$ht_ldpc"
                local ht_stbc_val="$ht_stbc"
                local ht_gi_val="$ht_gi"
                
                if [ -z "$ht_ldpc_val" ]; then
                    # 如果 htmode 包含 HT/HE/EHT，自动启用
                    case "$htmode" in
                        "HT"*|"HE"*|"EHT"*)
                            ht_ldpc_val="1"
                            ;;
                        *)
                            ht_ldpc_val="0"
                            ;;
                    esac
                fi
                if [ -z "$ht_stbc_val" ]; then
                    case "$htmode" in
                        "HT"*|"HE"*|"EHT"*)
                            ht_stbc_val="1"
                            ;;
                        *)
                            ht_stbc_val="0"
                            ;;
                    esac
                fi
                if [ -z "$ht_gi_val" ]; then
                    case "$htmode" in
                        "HT"*|"HE"*|"EHT"*)
                            ht_gi_val="1"
                            ;;
                        *)
                            ht_gi_val="0"
                            ;;
                    esac
                fi
                
                # 构建 ht_capab
                if [ -n "$ht_bw" ]; then
                    ht_capab_items="$ht_bw"
                    [ "$ht_ldpc_val" = "1" ] && ht_capab_items="$ht_capab_items LDPC"
                    [ "$ht_stbc_val" = "1" ] && ht_capab_items="$ht_capab_items STBC"
                    [ "$ht_gi_val" = "1" ] && ht_capab_items="$ht_capab_items SHORT-GI-20 SHORT-GI-40"
                    [ "$ht_opmode" = "1" ] && ht_capab_items="$ht_capab_items GF"
                    [ "$ht_amsdu" = "1" ] && ht_capab_items="$ht_capab_items MAX-AMSDU-7935"
                fi
            fi
            
            # 构建 VHT 能力（如果启用了 ieee80211ac）
            if [ -n "$vht_bw" ] || [ "$band" = "5G" ] || [ "$band" = "6G" ]; then
                # 如果参数未设置，根据 wireless_mode 自动启用
                local vht_ldpc_val="$vht_ldpc"
                local vht_stbc_val="$vht_stbc"
                local vht_sgi_val="$vht_sgi"
                
                if [ -z "$vht_ldpc_val" ]; then
                    # 如果 htmode 包含 VHT/HE/EHT，自动启用
                    case "$htmode" in
                        "VHT"*|"HE"*|"EHT"*)
                            vht_ldpc_val="1"
                            ;;
                        *)
                            vht_ldpc_val="0"
                            ;;
                    esac
                fi
                if [ -z "$vht_stbc_val" ]; then
                    case "$htmode" in
                        "VHT"*|"HE"*|"EHT"*)
                            vht_stbc_val="1"
                            ;;
                        *)
                            vht_stbc_val="0"
                            ;;
                    esac
                fi
                if [ -z "$vht_sgi_val" ]; then
                    case "$htmode" in
                        "VHT"*|"HE"*|"EHT"*)
                            vht_sgi_val="1"
                            ;;
                        *)
                            vht_sgi_val="0"
                            ;;
                    esac
                fi
                
                # 构建 vht_capab
                if [ -n "$vht_bw" ]; then
                    vht_capab_items="$vht_bw"
                    [ "$vht_ldpc_val" = "1" ] && vht_capab_items="$vht_capab_items LDPC"
                    [ "$vht_stbc_val" = "1" ] && vht_capab_items="$vht_capab_items STBC"
                    [ "$vht_sgi_val" = "1" ] && vht_capab_items="$vht_capab_items SHORT-GI-80 SHORT-GI-160"
                fi
            fi
            
            # 写入 ht_capab 和 vht_capab
            if [ -n "$ht_capab_items" ]; then
                echo "ht_capab=[$ht_capab_items]" >> "$conf_file"
            fi
            if [ -n "$vht_capab_items" ]; then
                echo "vht_capab=[$vht_capab_items]" >> "$conf_file"
            fi
            
            # Beacon 间隔（参考 hostapd.lua 行 1327-1335）
            if [ -n "$beacon_int" ]; then
                if [ "$beacon_int" -ge 15 ] && [ "$beacon_int" -le 65535 ] 2>/dev/null; then
                    echo "beacon_int=$beacon_int" >> "$conf_file"
                else
                    echo "beacon_int=100" >> "$conf_file"
                fi
            else
                echo "beacon_int=100" >> "$conf_file"
            fi
            
            # DTIM 周期（参考 hostapd.lua 行 1346-1352）
            if [ -n "$dtim_period" ]; then
                if [ "$dtim_period" -ge 1 ] && [ "$dtim_period" -le 255 ] 2>/dev/null; then
                    echo "dtim_period=$dtim_period" >> "$conf_file"
                fi
            else
                echo "dtim_period=1" >> "$conf_file"
            fi
            
            # 隐藏 SSID
            if [ "$hidden" = "1" ]; then
                echo "ignore_broadcast_ssid=1" >> "$conf_file"
            elif [ "$hidden" = "2" ]; then
                echo "ignore_broadcast_ssid=2" >> "$conf_file"
            else
                echo "ignore_broadcast_ssid=0" >> "$conf_file"
            fi
            
            # MAC 地址 ACL（参考 hostapd.lua 行 1370）
            echo "macaddr_acl=0" >> "$conf_file"
            
            # 加密配置（参考 hostapd.lua 的 find_encryption 和加密表）
            if [ -z "$encryption" ]; then
                encryption="none"
            fi
            if [ -z "$key" ]; then
                key=""
            fi
            
            # 设置 ieee80211w（参考 hostapd.lua 行 1337-1343）
            local map_mode=$(get_uci_value "wifi-device" "$device" "map_mode")
            if [ "$band" = "6G" ]; then
                ieee80211w="2"
            else
                if [ -n "$map_mode" ] && [ "$map_mode" != "0" ]; then
                    if [ -z "$ieee80211w" ]; then
                        ieee80211w="1"
                    fi
                fi
            fi
            
            # 根据加密类型设置参数（参考 hostapd.lua 的 encryption_table）
            case "$encryption" in
                "none")
                    echo "auth_algs=1" >> "$conf_file"
                    ;;
                "sae-mixed")
                    echo "auth_algs=1" >> "$conf_file"
                    echo "wpa=2" >> "$conf_file"
                    # 根据 pmf_sha256 和 rsne/rsno/rsno2 设置（参考 hostapd.lua 行 540-661）
                    if [ -n "$pmf_sha256" ] && [ "$pmf_sha256" = "1" ]; then
                        echo "wpa_key_mgmt=SAE SAE-EXT-KEY WPA-PSK WPA-PSK-SHA256" >> "$conf_file"
                    else
                        echo "wpa_key_mgmt=SAE SAE-EXT-KEY WPA-PSK" >> "$conf_file"
                    fi
                    echo "rsn_pairwise=CCMP GCMP-256" >> "$conf_file"
                    echo "ieee80211w=1" >> "$conf_file"
                    echo "wps_cred_add_sae=1" >> "$conf_file"
                    echo "sae_require_mfp=1" >> "$conf_file"
                    echo "beacon_prot=1" >> "$conf_file"
                    echo "sae_groups=19 20 21" >> "$conf_file"
                    if [ -n "$key" ]; then
                        echo "wpa_passphrase=$key" >> "$conf_file"
                        echo "sae_password=$key" >> "$conf_file"
                    fi
                    ;;
                "sae")
                    echo "auth_algs=1" >> "$conf_file"
                    echo "wpa=2" >> "$conf_file"
                    echo "wpa_key_mgmt=SAE SAE-EXT-KEY" >> "$conf_file"
                    echo "rsn_pairwise=CCMP GCMP-256" >> "$conf_file"
                    echo "ieee80211w=2" >> "$conf_file"
                    if [ -n "$key" ]; then
                        echo "sae_password=$key" >> "$conf_file"
                    fi
                    echo "sae_groups=19 20 21" >> "$conf_file"
                    ;;
                "psk2")
                    echo "auth_algs=1" >> "$conf_file"
                    echo "wpa=2" >> "$conf_file"
                    if [ -n "$pmf_sha256" ] && [ "$pmf_sha256" = "1" ]; then
                        echo "wpa_key_mgmt=WPA-PSK WPA-PSK-SHA256" >> "$conf_file"
                        echo "ieee80211w=1" >> "$conf_file"
                        echo "pmf_sha256=1" >> "$conf_file"
                    elif [ "$ieee80211w" = "2" ]; then
                        echo "wpa_key_mgmt=WPA-PSK-SHA256" >> "$conf_file"
                        echo "ieee80211w=2" >> "$conf_file"
                    else
                        echo "wpa_key_mgmt=WPA-PSK" >> "$conf_file"
                    fi
                    echo "rsn_pairwise=CCMP" >> "$conf_file"
                    if [ -n "$key" ]; then
                        echo "wpa_passphrase=$key" >> "$conf_file"
                        echo "sae_password=$key" >> "$conf_file"
                    fi
                    ;;
                *)
                    echo "auth_algs=1" >> "$conf_file"
                    echo "wpa=2" >> "$conf_file"
                    echo "wpa_key_mgmt=WPA-PSK" >> "$conf_file"
                    echo "rsn_pairwise=CCMP" >> "$conf_file"
                    if [ -n "$key" ]; then
                        echo "wpa_passphrase=$key" >> "$conf_file"
                        echo "sae_password=$key" >> "$conf_file"
                    fi
                    ;;
            esac
            
            # IEEE 802.11w (PMF) 设置（参考 hostapd.lua 行 1694-1706）
            if [ -n "$ieee80211w" ] && [ "$encryption" != "none" ]; then
                if [ "$ieee80211w" -ge 0 ] && [ "$ieee80211w" -le 2 ] 2>/dev/null; then
                    echo "ieee80211w=$ieee80211w" >> "$conf_file"
                    if [ "$ieee80211w" -ge 1 ] && [ "$ieee80211w" -le 2 ]; then
                        if [ -n "$beacon_prot" ] && [ "$beacon_prot" = "1" ]; then
                            echo "beacon_prot=1" >> "$conf_file"
                        fi
                        if [ -n "$ocvc" ] && [ "$ocvc" -ge 0 ] && [ "$ocvc" -le 2 ] 2>/dev/null; then
                            echo "ocv=$ocvc" >> "$conf_file"
                        fi
                    fi
                fi
            fi
            
            # PMF SHA256
            [ -n "$pmf_sha256" ] && [ "$pmf_sha256" = "1" ] && echo "sae_psk_anonce_rand=1" >> "$conf_file"
            
            # WMM 设置
            if [ -n "$wmm" ]; then
                echo "wmm_enabled=$wmm" >> "$conf_file"
            else
                echo "wmm_enabled=1" >> "$conf_file"
            fi
            
            # AP 隔离
            if [ -n "$isolate" ]; then
                echo "ap_isolate=$isolate" >> "$conf_file"
            else
                echo "ap_isolate=0" >> "$conf_file"
            fi
            
            # RTS 阈值（参考 hostapd.lua 行 1682-1686）
            if [ -n "$rts" ]; then
                echo "rts_threshold=$rts" >> "$conf_file"
            else
                echo "rts_threshold=-1" >> "$conf_file"
            fi
            
            # 分片阈值（参考 hostapd.lua 行 1688-1692）
            if [ -n "$frag" ]; then
                echo "fragm_threshold=$frag" >> "$conf_file"
            else
                echo "fragm_threshold=-1" >> "$conf_file"
            fi
            
            # APSD 功能（参考 hostapd.lua 行 2175-2179）
            if [ -n "$apsd_capable" ]; then
                echo "uapsd_advertisement_enabled=$apsd_capable" >> "$conf_file"
            else
                echo "uapsd_advertisement_enabled=1" >> "$conf_file"
            fi
            
            # MBO 设置（参考 hostapd.lua 行 2135-2143）
            if [ -n "$mbo" ] && [ "$mbo" = "1" ]; then
                echo "mbo=1" >> "$conf_file"
            else
                if [ -n "$map_mode" ] && [ "$map_mode" != "0" ]; then
                    echo "mbo=1" >> "$conf_file"
                else
                    echo "mbo=0" >> "$conf_file"
                fi
            fi
            
            # OCE 设置（参考 hostapd.lua 行 2145-2149）
            if [ -n "$oce" ] && [ "$oce" -ge 0 ] && [ "$oce" -le 7 ] 2>/dev/null; then
                echo "oce=$oce" >> "$conf_file"
            else
                echo "oce=0" >> "$conf_file"
            fi
            
            # 802.11k 设置（参考 hostapd.lua 行 2151-2165）
            if [ -n "$rrm_neighbor_report" ]; then
                echo "rrm_neighbor_report=$rrm_neighbor_report" >> "$conf_file"
            elif [ -n "$ieee80211k" ]; then
                echo "rrm_neighbor_report=$ieee80211k" >> "$conf_file"
            elif [ -n "$map_mode" ] && [ "$map_mode" != "0" ]; then
                echo "rrm_neighbor_report=1" >> "$conf_file"
            else
                # 默认值：1（参考原厂配置）
                echo "rrm_neighbor_report=1" >> "$conf_file"
            fi
            
            if [ -n "$rrm_beacon_report" ]; then
                echo "rrm_beacon_report=$rrm_beacon_report" >> "$conf_file"
            elif [ -n "$ieee80211k" ]; then
                echo "rrm_beacon_report=$ieee80211k" >> "$conf_file"
            elif [ -n "$map_mode" ] && [ "$map_mode" != "0" ]; then
                echo "rrm_beacon_report=1" >> "$conf_file"
            else
                # 默认值：1（参考原厂配置）
                echo "rrm_beacon_report=1" >> "$conf_file"
            fi
            
            if [ -n "$bss_transition" ]; then
                echo "bss_transition=$bss_transition" >> "$conf_file"
            elif [ -n "$map_mode" ] && [ "$map_mode" != "0" ]; then
                echo "bss_transition=1" >> "$conf_file"
            fi
            
            # 代理 ARP（参考 hostapd.lua 行 2271-2277）
            if [ "$proxy_arp" = "1" ] && [ -n "$network" ] && [ "$isolate" = "1" ]; then
                echo "proxy_arp=1" >> "$conf_file"
            else
                echo "proxy_arp=0" >> "$conf_file"
            fi
            
            # RSN 预认证（参考 hostapd.lua 行 1670-1674）
            if [ -n "$rsn_preauth" ]; then
                echo "rsn_preauth=$rsn_preauth" >> "$conf_file"
            else
                echo "rsn_preauth=0" >> "$conf_file"
            fi
            
            # PMK 缓存周期
            if [ -n "$pmk_cache_period" ]; then
                echo "okc=1" >> "$conf_file"
                echo "pmksa_caching=1" >> "$conf_file"
                echo "pmk_cache_expire=$pmk_cache_period" >> "$conf_file"
            fi
            
            # 密钥重生成间隔（参考 hostapd.lua 行 1884-1886）
            if [ -n "$rekey_interval" ]; then
                echo "wpa_group_rekey=$rekey_interval" >> "$conf_file"
            elif [ "$encryption" != "none" ]; then
                # 如果有加密但未设置 rekey_interval，使用默认值 3600
                echo "wpa_group_rekey=3600" >> "$conf_file"
            fi
            
            # SAE 配置（参考 hostapd.lua 行 1624-1642）
            if [ -n "$sae_pwe" ]; then
                if [ "$sae_pwe" -ge 0 ] && [ "$sae_pwe" -le 2 ] 2>/dev/null; then
                    echo "sae_pwe=$sae_pwe" >> "$conf_file"
                fi
            else
                echo "sae_pwe=2" >> "$conf_file"
            fi
            
            if [ -n "$sae_require_mfp" ]; then
                echo "sae_require_mfp=$sae_require_mfp" >> "$conf_file"
            fi
            
            if [ -n "$sae_groups" ]; then
                echo "sae_groups=$sae_groups" >> "$conf_file"
            elif [ "$encryption" = "sae" ] || [ "$encryption" = "sae-mixed" ]; then
                echo "sae_groups=19 20 21" >> "$conf_file"
            fi
            
            # OWE 配置
            if [ -n "$owe_transition_bssid" ]; then
                echo "owe_transition_bssid=$owe_transition_bssid" >> "$conf_file"
            fi
            if [ -n "$owe_transition_ssid" ]; then
                echo "owe_transition_ssid=$owe_transition_ssid" >> "$conf_file"
            fi
            if [ -n "$owe_transition_ifname" ]; then
                echo "owe_transition_ifname=$owe_transition_ifname" >> "$conf_file"
            fi
            if [ -n "$owe_groups" ]; then
                echo "owe_groups=$owe_groups" >> "$conf_file"
            fi
            
            # 802.11r (快速漫游) 配置
            if [ "$ieee80211r" = "1" ]; then
                # nas_identifier 将在后面统一写入，这里不重复
                echo "wpa_key_mgmt=WPA-PSK FT-PSK" >> "$conf_file"
                if [ -n "$mobility_domain" ]; then
                    echo "mobility_domain=$mobility_domain" >> "$conf_file"
                else
                    # 生成默认漫游域
                    local default_md=$(echo -n "$ssid" | md5sum | cut -c1-4)
                    echo "mobility_domain=$default_md" >> "$conf_file"
                fi
                if [ -n "$ft_psk_generate_local" ]; then
                    echo "ft_psk_generate_local=$ft_psk_generate_local" >> "$conf_file"
                else
                    echo "ft_psk_generate_local=0" >> "$conf_file"
                fi
                if [ -n "$ft_over_ds" ]; then
                    echo "ft_over_ds=$ft_over_ds" >> "$conf_file"
                else
                    echo "ft_over_ds=0" >> "$conf_file"
                fi
                if [ -n "$reassociation_deadline" ]; then
                    echo "reassociation_deadline=$reassociation_deadline" >> "$conf_file"
                else
                    echo "reassociation_deadline=1000" >> "$conf_file"
                fi
                if [ -n "$r0_key_lifetime" ]; then
                    echo "r0_key_lifetime=$r0_key_lifetime" >> "$conf_file"
                else
                    echo "r0_key_lifetime=10000" >> "$conf_file"
                fi
                if [ -n "$pmk_r1_push" ]; then
                    echo "pmk_r1_push=$pmk_r1_push" >> "$conf_file"
                else
                    echo "pmk_r1_push=0" >> "$conf_file"
                fi
                if [ -n "$r0kh" ]; then
                    echo "r0kh=$r0kh" >> "$conf_file"
                fi
                if [ -n "$r1kh" ]; then
                    echo "r1kh=$r1kh" >> "$conf_file"
                fi
            fi
            
            # WPS 配置（部分配置将在后面统一写入，避免重复）
            local wps_enabled=0
            if [ -n "$wps_state" ]; then
                if [ "$wps_state" = "1" ]; then
                    wps_enabled=1
                    echo "wps_state=2" >> "$conf_file"
                    echo "ap_setup_locked=0" >> "$conf_file"
                    [ -n "$wps_pin" ] && echo "ap_pin=$wps_pin" >> "$conf_file"
                    
                    # WPS 配置方法
                    local wps_methods="display virtual_display"
                    if [ "$wps_pushbutton" != "0" ]; then
                        wps_methods="$wps_methods push_button"
                    fi
                    if [ "$wps_label" != "0" ]; then
                        wps_methods="$wps_methods label"
                    fi
                    echo "config_methods=$wps_methods" >> "$conf_file"
                    
                    # WPS 设备信息（仅在 WPS 启用时写入，避免与后面的统一写入重复）
                    [ -n "$wps_device_name" ] && echo "device_name=$wps_device_name" >> "$conf_file" || echo "device_name=Wireless AP" >> "$conf_file"
                    [ -n "$wps_device_type" ] && echo "device_type=$wps_device_type" >> "$conf_file" || echo "device_type=6-0050F204-1" >> "$conf_file"
                    [ -n "$wps_manufacturer" ] && echo "manufacturer=$wps_manufacturer" >> "$conf_file" || echo "manufacturer=MediaTek Inc." >> "$conf_file"
                    
                    # WPS RF 频段
                    if [ "$band" = "2.4G" ]; then
                        echo "wps_rf_bands=b" >> "$conf_file"
                    elif [ "$band" = "5G" ]; then
                        echo "wps_rf_bands=a" >> "$conf_file"
                    else
                        echo "wps_rf_bands=ag" >> "$conf_file"
                    fi
                    
                    # WPS Cred Add SAE
                    if [ -n "$wps_cred_add_sae" ]; then
                        echo "wps_cred_add_sae=$wps_cred_add_sae" >> "$conf_file"
                    elif [ "$encryption" = "sae" ] || [ "$encryption" = "sae-mixed" ]; then
                        echo "wps_cred_add_sae=1" >> "$conf_file"
                    fi
                else
                    echo "wps_state=0" >> "$conf_file"
                fi
            fi
            
            # Multi-AP 配置
            if [ -n "$multi_ap" ]; then
                echo "multi_ap=$multi_ap" >> "$conf_file"
                if [ -n "$multi_ap_backhaul_ssid" ]; then
                    echo "multi_ap_backhaul_ssid=$multi_ap_backhaul_ssid" >> "$conf_file"
                    if [ -n "$multi_ap_backhaul_key" ]; then
                        if [ ${#multi_ap_backhaul_key} -eq 64 ] && [ -n "$(echo $multi_ap_backhaul_key | grep -E '^[0-9a-fA-F]{64}$')" ]; then
                            echo "multi_ap_backhaul_wpa_psk=$multi_ap_backhaul_key" >> "$conf_file"
                        elif [ ${#multi_ap_backhaul_key} -ge 8 ] && [ ${#multi_ap_backhaul_key} -le 63 ]; then
                            echo "multi_ap_backhaul_wpa_passphrase=$multi_ap_backhaul_key" >> "$conf_file"
                        fi
                    fi
                    if [ -n "$multi_ap_backhaul_key_mgmt" ]; then
                        echo "multi_ap_backhaul_key_mgmt=$multi_ap_backhaul_key_mgmt" >> "$conf_file"
                    fi
                fi
            fi
            
            # UUID
            [ -n "$uuid" ] && echo "uuid=$uuid" >> "$conf_file"
            
            # Interworking（参考 hostapd.lua 行 2127-2133）
            # 如果 UCI 中设置了 interworking，使用该值
            # 否则，如果 map_mode != "0"，自动设置为 1
            # 否则不写入（默认值为 0，但 hostapd.lua 中不明确写入）
            if [ -n "$interworking" ]; then
                echo "interworking=$interworking" >> "$conf_file"
            elif [ -n "$map_mode" ] && [ "$map_mode" != "0" ]; then
                echo "interworking=1" >> "$conf_file"
            fi
            
            # RADIUS 配置（参考 hostapd.lua 行 1891-1908）
            if [ -n "$ieee8021x" ] && [ "$ieee8021x" != "0" ]; then
                echo "ieee8021x=$ieee8021x" >> "$conf_file"
            fi
            
            if [ -n "$auth_server" ] && [ "$auth_server" != "0" ]; then
                echo "auth_server_addr=$auth_server" >> "$conf_file"
            else
                echo "auth_server_addr=127.0.0.1" >> "$conf_file"
            fi
            
            if [ -n "$auth_port" ] && [ "$auth_port" != "0" ]; then
                echo "auth_server_port=$auth_port" >> "$conf_file"
            else
                echo "auth_server_port=1812" >> "$conf_file"
            fi
            
            if [ -n "$auth_secret" ]; then
                echo "auth_server_shared_secret=$auth_secret" >> "$conf_file"
            fi
            
            # NAS 标识符和通用配置（参考 hostapd.lua 行 1934-1938）
            echo "ctrl_interface=/var/run/hostapd/" >> "$conf_file"
            echo "nas_identifier=ap.mtk.com" >> "$conf_file"
            echo "use_driver_iface_addr=1" >> "$conf_file"
            
            # WPS 设备信息（参考 hostapd.lua 行 1940-1944）
            echo "friendly_name=WPS Access Point" >> "$conf_file"
            echo "model_name=MediaTek Wireless Access Point" >> "$conf_file"
            echo "model_number=MT7988" >> "$conf_file"
            echo "serial_number=12345678" >> "$conf_file"
            echo "os_version=80000000" >> "$conf_file"
            
            if [ -n "$ownip" ]; then
                echo "own_ip_addr=$ownip" >> "$conf_file"
            else
                # 默认值：192.168.1.1
                echo "own_ip_addr=192.168.1.1" >> "$conf_file"
            fi
            
            # WPS 配置方法（参考 hostapd.lua 行 1960-2000）
            # 如果 WPS 未启用，写入默认的 config_methods
            if [ "$wps_enabled" != "1" ]; then
                echo "config_methods=display virtual_push_button keypad" >> "$conf_file"
            fi
            echo "eapol_key_index_workaround=0" >> "$conf_file"
            echo "eapol_version=2" >> "$conf_file"
            
            # EAP Server（参考 hostapd.lua 行 2001-2021）
            if [ -n "$(echo "$encryption" | grep -E 'psk|sae|none')" ]; then
                echo "eap_server=1" >> "$conf_file"
            elif [ -n "$(echo "$encryption" | grep -E 'wpa')" ]; then
                if [ -n "$map_mode" ] && [ "$map_mode" != "0" ]; then
                    echo "eap_server=1" >> "$conf_file"
                else
                    echo "eap_server=0" >> "$conf_file"
                fi
            else
                if [ -n "$map_mode" ] && [ "$map_mode" != "0" ]; then
                    echo "eap_server=1" >> "$conf_file"
                fi
            fi
            
            # WPS 设备名称（参考 hostapd.lua 行 2023-2027）
            # 如果 WPS 未启用，写入默认的 device_name
            if [ "$wps_enabled" != "1" ]; then
                if [ -n "$wps_device_name" ]; then
                    echo "device_name=$wps_device_name" >> "$conf_file"
                else
                    echo "device_name=Wireless AP" >> "$conf_file"
                fi
            fi
            
            # WPS 设备类型（参考 hostapd.lua 行 2029-2033）
            # 如果 WPS 未启用，写入默认的 device_type
            if [ "$wps_enabled" != "1" ]; then
                if [ -n "$wps_device_type" ]; then
                    echo "device_type=$wps_device_type" >> "$conf_file"
                else
                    echo "device_type=6-0050F204-1" >> "$conf_file"
                fi
            fi
            
            # WPS 制造商（参考 hostapd.lua 行 2035-2039）
            # 如果 WPS 未启用，写入默认的 manufacturer
            if [ "$wps_enabled" != "1" ]; then
                if [ -n "$wps_manufacturer" ]; then
                    echo "manufacturer=$wps_manufacturer" >> "$conf_file"
                else
                    echo "manufacturer=MediaTek Inc." >> "$conf_file"
                fi
            fi
            
            # WPS RF 频段（参考 hostapd.lua 行 2041-2049）
            # 如果 WPS 未启用，写入默认的 wps_rf_bands
            if [ "$wps_enabled" != "1" ]; then
                if [ -n "$map_mode" ] && [ "$map_mode" != "0" ] && [ "$band" != "6G" ]; then
                    echo "wps_rf_bands=ag" >> "$conf_file"
                else
                    if [ "$band" = "2.4G" ]; then
                        echo "wps_rf_bands=b" >> "$conf_file"
                    elif [ "$band" = "5G" ]; then
                        echo "wps_rf_bands=a" >> "$conf_file"
                    fi
                fi
            fi
            
            # WPS 状态（参考 hostapd.lua 行 2051-2062）
            # 如果 WPS 状态未设置，写入默认值
            if [ -z "$wps_state" ]; then
                if [ -n "$map_mode" ] && [ "$map_mode" != "0" ]; then
                    echo "wps_state=2" >> "$conf_file"
                else
                    echo "wps_state=0" >> "$conf_file"
                fi
            fi
            
            # WPS Independent（参考 hostapd.lua 行 2072-2078）
            if [ -n "$map_mode" ] && [ "$map_mode" != "0" ]; then
                echo "wps_independent=0" >> "$conf_file"
            else
                if [ -n "$wps_independent" ]; then
                    echo "wps_independent=$wps_independent" >> "$conf_file"
                else
                    echo "wps_independent=1" >> "$conf_file"
                fi
            fi
            
            echo "✅ 已生成改进版 hostapd 配置: $conf_file (interface: $physical_ifname)"
            
            # 增加该设备下的AP索引
            ap_index=$((ap_index + 1))
            fi
        done
    done
    
    echo "✅ 改进版 hostapd 配置生成完成"
}

# 显示配置状态
show_config_status() {
    echo "📋 当前配置状态:"
    echo "DAT 配置文件:"
    ls -la /etc/wireless/mediatek/*.dat 2>/dev/null || echo "  无 DAT 配置文件"
    echo ""
    echo "Hostapd 配置文件"
    ls -la /var/run/hostapd-phy*-ap*.conf 2>/dev/null || echo "  无本脚本生成的 hostapd 配置文件"
    echo ""
    echo "Hostapd 其他 .conf（可能是历史遗留/系统生成，内容可能与 UCI 不一致）:"
    ls -la /var/run/hostapd-phy*.conf /var/run/hostapd/*.conf 2>/dev/null || true
    echo ""
    echo "无线配置:"
    uci show wireless 2>/dev/null || echo "  无法读取无线配置"
}

# 主函数
main() {
    case "${1:-all}" in
        "dat")
            generate_dat_from_uci
            ;;
        "hostapd")
            generate_hostapd_from_uci_improved
            ;;
        "hostapd-basic")
            generate_hostapd_from_uci
            ;;
        "status")
            show_config_status
            ;;
        "all")
            echo "🚀 开始生成所有配置..."
            if cfg_is_diff; then
                echo "配置有变化，重新生成..."
                generate_dat_from_uci
                generate_hostapd_from_uci_improved
                cfg_save_current  # 保存当前配置
            else
                echo "配置无变化，跳过生成"
            fi
            echo "✅ 所有配置生成完成!"
            show_config_status
            ;;
        "force-all")
            echo "🚀 强制生成所有配置..."
            generate_dat_from_uci
            generate_hostapd_from_uci_improved
            cfg_save_current  # 保存当前配置
            echo "✅ 所有配置生成完成!"
            show_config_status
            ;;
        *)
            echo "📚 用法: $0 [all|force-all|dat|hostapd|hostapd-basic|status]"
            echo "  all           - 生成所有配置 (默认)"
            echo "  force-all     - 强制生成所有配置（忽略变化检测）"
            echo "  dat           - 仅生成 DAT 配置"
            echo "  hostapd       - 生成改进版 hostapd 配置（使用加密转换）"
            echo "  hostapd-basic - 生成基础版 hostapd 配置"
            echo "  status        - 显示当前配置状态"
            exit 1
            ;;
    esac
}

# 只有在直接执行时才执行主函数（不是被 source 时）
if ! _is_sourced; then
    main "$@"
fi
