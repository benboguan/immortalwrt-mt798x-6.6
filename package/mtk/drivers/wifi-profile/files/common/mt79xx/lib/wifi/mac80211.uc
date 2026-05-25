#!/usr/bin/env ucode
import { readfile, exec, printf } from "fs";
import * as uci from 'uci';

const bands_order = [ "6G", "5G", "2G" ];
const htmode_order = [ "EHT", "HE", "VHT", "HT" ];

let idx = 0;
let commit = false;
let mld_id = 1;
let has_mlo = false;
let has_6g = false;
let device_list = [];
let assocresp_elements = "dd07000ce700000000";
let mld_encryption = "psk2";
let mld_encryption_rsno = "sae";
let mld_ieee80211w = "1";

let config = uci.cursor().get_all("wireless") ?? {};

// 判断 radio 是否已存在
function radio_exists(phy) {
	for (let name, s in config) {
		if (s[".type"] != "wifi-device") continue;
		if (s.phy == phy) return true;
	}
	return false;
}

// 用 iw 命令获取真实 PHY 支持的频段（核心修复）
function get_phy_band(phy_name) {
	let band = null;
	try {
		let out = exec(`iw phy ${phy_name} info`);
		if (out.match(/\* 5\.180 GHz$/m) || out.match(/\* 5 GHz/m)) band = "5G";
		if (out.match(/\* 2\.412 GHz$/m) || out.match(/\* 2\.4 GHz/m)) band = "2G";
		if (out.match(/\* 5\.955 GHz/m) || out.match(/\* 6 GHz/m)) band = "6G";
	} catch (e) {}
	return band;
}

// 获取 HTMODE
function get_phy_htmode(phy_name, band) {
	let htmode = "NOHT";
	try {
		let out = exec(`iw phy ${phy_name} info`);
		for (let m of htmode_order) {
			if (out.match(new RegExp(m, 'i'))) {
				htmode = m;
				break;
			}
		}
	} catch (e) {}
	return htmode;
}

// 遍历系统真实 PHY（/sys/class/ieee80211/）
let phys = exec("ls /sys/class/ieee80211/ 2>/dev/null").split(/\n/);
for (let phy_name of phys) {
	phy_name = trim(phy_name);
	if (!phy_name || !phy_name.match(/^phy/)) continue;

	// 跳过已存在的 radio
	if (radio_exists(phy_name)) continue;

	// 获取真实 band（2G/5G/6G）
	let band_name = get_phy_band(phy_name);
	if (!band_name) continue;

	// 分配 radio 名称
	while (config[`radio${idx}`]) idx++;
	let name = `radio${idx}`;
	let s = `wireless.${name}`;
	let si = `wireless.default_${name}`;

	// 信道默认值
	let channel = "auto";
	if (band_name == "6G") channel = 37;

	// 获取 HTMODE
	let htmode = get_phy_htmode(phy_name, band_name);
	let width = band_name == "6G" ? "160" : band_name == "5G" ? "80" : "40";
	if (htmode != "NOHT") htmode += width;

	// 国家码
	let country = "US";
	try { country = trim(readfile("/etc/config/country")); } catch(e) {}

	// 接口参数
	let noscan = 0, mbssid = 0, rnr = 0, background_radar = 0, mbo = 0;
	let encryption = "none";
	let ssid = "";

	if (band_name == "6G") {
		encryption = "sae";
		mld_encryption = "sae";
		mld_ieee80211w = "2";
		mbo = 1;
		ssid = "ImmortalWrt_6G";
		mbssid = 1;
		has_6g = true;
	} else if (band_name == "5G") {
		encryption = "none";
		noscan = 1;
		rnr = 1;
		background_radar = 1;
		ssid = "ImmortalWrt_5G";
	} else {
		encryption = "none";
		noscan = 1;
		rnr = 1;
		ssid = "ImmortalWrt_2.4G";
	}

	// 输出 UCI 配置
	printf(`set ${s}=wifi-device
set ${s}.type='mac80211'
set ${s}.phy='${phy_name}'
set ${s}.band='${lc(band_name)}'
set ${s}.channel='${channel}'
set ${s}.htmode='${htmode}'
set ${s}.country='${country}'
set ${s}.disabled='0'
set ${s}.noscan=${noscan}
set ${s}.tx_burst=0.0
`);

	if (mbssid) printf(`set ${s}.mbssid=${mbssid}\n`);
	if (rnr) printf(`set ${s}.rnr=${rnr}\n`);
	if (background_radar) printf(`set ${s}.background_radar=${background_radar}\n`);

	printf(`set ${si}=wifi-iface
set ${si}.device='${name}'
set ${si}.network='lan'
set ${si}.mode='ap'
set ${si}.ssid='${ssid}'
set ${si}.encryption='${encryption}'
set ${si}.key=''
set ${si}.mbo=${mbo}
set ${si}.assocresp_elements='${assocresp_elements}'
`);

	if (encryption == "sae") {
		printf(`set ${si}.key=12345678
set ${si}.sae_pwe=2
set ${si}.ieee80211w=2
`);
	}

	config[name] = {};
	push(device_list, name);
	commit = true;
}

// MLD/MLO
if (has_mlo && commit && length(device_list) > 1) {
	let mld_sec = "wireless.ap_mld_1";
	printf(`set ${mld_sec}=wifi-mld\n`);
	for (let dev of device_list)
		printf(`add_list ${mld_sec}.device=${dev}\n`);

	printf(`set ${mld_sec}.ifname=ap-mld-1
set ${mld_sec}.network='lan'
set ${mld_sec}.mode='ap'
set ${mld_sec}.mlo=1
set ${mld_sec}.mld_id=${mld_id}
set ${mld_sec}.ssid='ImmortalWrt_MLO'
set ${mld_sec}.encryption_rsno_2='sae-ext'
set ${mld_sec}.key=12345678
set ${mld_sec}.sae_pwe=2
set ${mld_sec}.ieee80211w='${mld_ieee80211w}'
set ${mld_sec}.encryption='${mld_encryption}'
set ${mld_sec}.assocresp_elements='${assocresp_elements}'
`);
	if (!has_6g)
		printf(`set ${mld_sec}.encryption_rsno=${mld_encryption_rsno}\n`);
}

if (commit)
	print("commit wireless\n");
