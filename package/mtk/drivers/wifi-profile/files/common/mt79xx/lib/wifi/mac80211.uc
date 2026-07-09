#!/usr/bin/env ucode
import { readfile, glob } from "fs";
import * as uci from 'uci';

let idx = 0;
let commit = false;
let mld_id = 1;
let has_6g = false;
let device_list = [];

let assocresp_elements = "dd07000ce700000000";
let mld_encryption = "psk2";
let mld_encryption_rsno = "sae";
let mld_ieee80211w = "1";

let config = uci.cursor().get_all("wireless") ?? {};

function radio_exists(phy) {
	for (let name in config) {
		let s = config[name];
		if (s[".type"] != "wifi-device")
			continue;
		if (s.phy == phy || s.path == hw_path)
			return true;
	}
	return false;
}

function get_phy_path(phy) {
	let tmp = "/tmp/iwpath_" + phy + ".txt";
	system("iwinfo nl80211 path " + phy + " > " + tmp + " 2>/dev/null");
	let out = "";
	try { out = trim(readfile(tmp)); } catch(e) {}
	return out;
}

let band_map = {
	"phy0": "2g",
	"phy1": "5g",
	"phy2": "6g"
};

let phy_list = [];
try {
	phy_list = glob("/sys/class/ieee80211/phy*");
} catch (e) {}

if (length(phy_list) == 0) {
	print("# No phy interfaces found.\n");
	exit(0);
}

for (let pIdx = 0; pIdx < length(phy_list); pIdx++)
{
	let phy_sysfs = phy_list[pIdx];
	let parts = split(phy_sysfs, "/");
	let phy_name = parts[length(parts) - 1];

	if (radio_exists(phy_name))
		continue;

	if (!band_map[phy_name])
		continue;

	while (config[`radio${idx}`])
		idx++;
	let name = "radio" + idx;


	let band_name = band_map[phy_name];
	let channel, hwmode, htmode, noscan = 0, background_radar = 0;
	let encryption = "none";
	let mbssid = 0;
	let mbo = 0;
	let ssid = "";
	let country = "US";

	if (band_name == "6g") {
		channel = 37; htmode = "EHT320";
		noscan = 1;
		mbo = 1;
		hwmode = a;
		ssid = "ImmortalWrt_6G";
		mbssid = 1;
		has_6g = true;
	} else if (band_name == "5g") {
		channel = 36; htmode = "EHT160";
		hwmode = a;
		noscan = 1;
		ssid = "ImmortalWrt_5G";
	} else if (band_name == "2g") {
		channel = 6; htmode = "EHT40";
		noscan = 1;
		hwmode = g;
		ssid = "ImmortalWrt_2.4G";
	} else {
		continue;
	}

	let hw_path = get_phy_path(phy_name);
	let dev_id;
	if (hw_path && length(hw_path) > 0 && match(phy_name, /^phy[0-9]/))
		dev_id = `path='${hw_path}'`;
	else
		dev_id = `phy='${phy_name}'`;

	print(`set wireless.${name}=wifi-device
set wireless.${name}.type='mac80211'
set wireless.${name}.phy='${phy_name}'
set wireless.${name}.${dev_id}
set wireless.${name}.band='${band_name}'
set wireless.${name}.hwmode='${hwmode}'
set wireless.${name}.channel='${channel}'
set wireless.${name}.htmode='${htmode}'
set wireless.${name}.country='${country}'
set wireless.${name}.disabled='0'
set wireless.${name}.noscan=${noscan}
`);
	if (mbssid) print(`set wireless.${name}.mbssid=1\n`);
	if (background_radar) print(`set wireless.${name}.background_radar=1\n`);
	print(`set wireless.${name}.tx_burst=2.0\n`);

	print(`set wireless.default_${name}=wifi-iface
set wireless.default_${name}.device='${name}'
set wireless.default_${name}.network='lan'
set wireless.default_${name}.mode='ap'
set wireless.default_${name}.ssid='${ssid}'
set wireless.default_${name}.encryption='${encryption}'
set wireless.default_${name}.key=''
set wireless.default_${name}.mbo='${mbo || '0'}'
set wireless.default_${name}.assocresp_elements='${assocresp_elements}'
`);

	config[name] = {};
	push(device_list, name);
	commit = true;
	idx++;
}

if (length(device_list) >= 2) {
	print(`set wireless.ap_mld_1=wifi-mld\n`);
	for (let d = 0; d < length(device_list); d++)
		print(`add_list wireless.ap_mld_1.device=${device_list[d]}\n`);
	print(`set wireless.ap_mld_1.ifname=ap-mld-1
set wireless.ap_mld_1.network='lan'
set wireless.ap_mld_1.mode='ap'
set wireless.ap_mld_1.mlo=1
set wireless.ap_mld_1.mld_id=${mld_id}
set wireless.ap_mld_1.ssid='ImmortalWrt_MLO'
set wireless.ap_mld_1.encryption_rsno_2='sae-ext'
set wireless.ap_mld_1.key=12345678
set wireless.ap_mld_1.sae_pwe=2
set wireless.ap_mld_1.ieee80211w='${mld_ieee80211w}'
set wireless.ap_mld_1.encryption='${mld_encryption}'
set wireless.ap_mld_1.assocresp_elements='${assocresp_elements}'
`);
	if (!has_6g)
		print(`set wireless.ap_mld_1.encryption_rsno=${mld_encryption_rsno}\n`);
}

if (commit)
	print("commit wireless\n");
