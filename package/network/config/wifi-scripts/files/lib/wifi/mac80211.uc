#!/usr/bin/env ucode
import { readfile } from "fs";
import * as uci from 'uci';

const bands_order = [ "6G", "5G", "2G" ];
const htmode_order = [ "EHT", "HE", "VHT", "HT" ];

let board = json(readfile("/etc/board.json"));
if (!board.wlan)
	exit(0);

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

function radio_exists(path, macaddr, phy, radio) {
	for (let name, s in config) {
		if (s[".type"] != "wifi-device")
			continue;
		if (radio != null && int(s.radio) != radio)
			continue;
		if (s.macaddr && lc(s.macaddr) == lc(macaddr))
			return true;
		if (s.phy == phy)
			return true;
		if (!s.path || !path)
			continue;
		if (substr(s.path, -length(path)) == path)
			return true;
	}
	return false;
}

for (let phy_name, phy in board.wlan) {
	let info = phy.info;
	if (!info || !length(info.bands))
		continue;

	for (let band_name, band in info.bands) {
		for (let mode in band.modes) {
			if (wildcard(mode, 'EHT*')) {
				has_mlo = true;
				break;
			}
		}
		if (has_mlo) break;
	}

	let radios = length(info.radios) > 0 ? info.radios : [{ bands: info.bands }];
	for (let radio in radios) {
		let macaddr = "";
		try {
			macaddr = trim(readfile(`/sys/class/ieee80211/${phy_name}/macaddress`));
		} catch (e) {}

		if (radio_exists(phy.path, macaddr, phy_name, radio.index))
			continue;

		while (config[`radio${idx}`])
			idx++;
		let name = "radio" + idx;

		let s = "wireless." + name;
		let si = "wireless.default_" + name;

		let band_name = filter(bands_order, (b) => radio.bands[b])[0];
		if (!band_name)
			continue;

		let band = info.bands[band_name];
		let rband = radio.bands[band_name];
		let channel = rband.default_channel ?? "auto";
		if (band_name == "6G" || band_name == "6g")
			channel = 37;

		let width = band.max_width;

		let htmode = filter(htmode_order, (m) => band[lc(m)])[0];
		if (htmode)
			htmode += width;
		else
			htmode = "NOHT";

		if (!phy.path)
			continue;

		let id = `phy='${phy_name}'`;
		if (match(phy_name, /^phy[0-9]/))
			id = `path='${phy.path}'`;

		band_name = lc(band_name);

		let country, encryption, defaults, num_global_macaddr;
		if (board.wlan.defaults) {
			defaults = board.wlan.defaults.ssids?.[band_name]?.ssid ? board.wlan.defaults.ssids?.[band_name] : board.wlan.defaults.ssids?.all;
			country = board.wlan.defaults.country;
			if (!country && band_name != '2g')
				defaults = null;
			num_global_macaddr = board.wlan.defaults.ssids?.[band_name]?.mac_count;
		}

		if (length(info.radios) > 0)
			id += `\nset ${s}.radio='${radio.index}'`;

		let noscan = 0;
		let mbssid = 0;
		let rnr = 0;
		let background_radar = 0;
		let mbo = 0;
		let ssid = "";

		if (band_name == "6G" || band_name == "6g") {
			encryption = "sae";
			mld_encryption = "sae";
			mld_ieee80211w = "2";
			mbo = 1;
			ssid = "ImmortalWrt_6G";
			mbssid = 1;
			has_6g = true;
		} else if (band_name == "5G" || band_name == "5g") {
			encryption = "none";
			noscan = 1;
			rnr = 1;
			background_radar = 1;
			ssid = "ImmortalWrt_5G";
		} else { /* 2g */
			encryption = "none";
			noscan = 1;
			rnr = 1;
			ssid = "ImmortalWrt_2.4G";
		}

		print(`set ${s}=wifi-device
set ${s}.type='mac80211'
set ${s}.${id}
set ${s}.band='${band_name}'
set ${s}.channel='${channel}'
set ${s}.htmode='${htmode}'
set ${s}.country='${country || 'US'}'
set ${s}.num_global_macaddr='${num_global_macaddr || ''}'
set ${s}.disabled='0'
set ${s}.noscan=${noscan}
`);

		if (mbssid)
			print(`set ${s}.mbssid=${mbssid}
`);
		if (rnr)
			print(`set ${s}.rnr=${rnr}
`);
		if (background_radar)
			print(`set ${s}.background_radar=${background_radar}
`);
		print(`set ${s}.tx_burst=0.0
`);

		print(`set ${si}=wifi-iface
set ${si}.device='${name}'
set ${si}.network='lan'
set ${si}.mode='ap'
set ${si}.ssid='${defaults?.ssid || ssid}'
set ${si}.encryption='${defaults?.encryption || encryption}'
set ${si}.key='${defaults?.key || ""}'
set ${si}.mbo=${mbo}
set ${si}.assocresp_elements='${assocresp_elements}'
`);

		if (encryption == "sae") {
			print(`set ${si}.key=12345678
set ${si}.sae_pwe=2
set ${si}.ieee80211w=2
`);
		}

		config[name] = {};
		push(device_list, name);
		commit = true;
	}

	/* MLD/MLO */
	if (has_mlo && commit) {
		let mld_sec = "wireless.ap_mld_1";

		print(`set ${mld_sec}=wifi-iface
`);
		for (let device_name in device_list)
			print(`add_list ${mld_sec}.device=${device_name}
`);

		print(`set ${mld_sec}.ifname=ap-mld-1
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
			print(`set ${mld_sec}.encryption_rsno=${mld_encryption_rsno}
`);
	}
}

if (commit)
	print("commit wireless\n");
