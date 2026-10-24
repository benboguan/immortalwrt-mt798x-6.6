'use strict';

// SPDX-License-Identifier: GPL-2.0
/*
 * mtwifi ucode support - phy capability lookup
 *
 * Copyright (C) 2026 nanchuci <nanchuci023@gmail.com>
 *
 * 通过 nl80211 读取 HT/VHT/HE 能力与扩展特性，取代 shell 版里
 * `iw phy <phy> info | sed/awk/grep` 的解析。结构对齐官方
 * wifi-scripts 的 usr/share/ucode/wifi/hostapd.uc:device_capabilities()。
 */

import * as nl80211 from 'nl80211';
import { wiphy_info, wiphy_band, log } from 'wifi.common';

const NL80211_EXT_FEATURE_ENABLE_FTM_RESPONDER = 33;
const NL80211_EXT_FEATURE_RADAR_BACKGROUND = 61;

const WLAN_CIPHER_SUITE_GCMP_256 = 0x000fac09;

function extended_feature(data, flag) {
	if (!data)
		return false;

	let byte = int(flag / 8);
	let mask = 1 << int(flag % 8);

	return !!((data[byte] ?? 0) & mask);
};

/*
 * 返回：
 *   ht_capa / vht_capa / he_phy_cap / he_mac_cap / eht_phy_cap
 *   features = { ftm_responder, radar_background, cipher_gcmp256 }
 *   band     = 该 band 的 nl80211 信息（可能为 null）
 */
export function device_capabilities(config) {
	let caps = {
		ht_capa: 0,
		vht_capa: 0,
		he_phy_cap: [],
		he_mac_cap: [],
		eht_phy_cap: [],
		features: {
			ftm_responder: false,
			radar_background: false,
			cipher_gcmp256: false,
		},
		band: null,
	};

	let info;

	try {
		info = wiphy_info(config.phy);
	} catch (e) {
		log(`failed to query phy ${config.phy}: ${e}`);
		return caps;
	}

	if (!info)
		return caps;

	let band = wiphy_band(info, config.band);

	if (band) {
		caps.band = band;
		caps.ht_capa = band.ht_capa ?? 0;
		caps.vht_capa = band.vht_capa ?? 0;

		for (let iftype in band.iftype_data ?? []) {
			if (!iftype.iftypes?.ap)
				continue;

			caps.he_mac_cap = iftype.he_cap_mac ?? [];
			caps.he_phy_cap = iftype.he_cap_phy ?? [];
			caps.eht_phy_cap = iftype.eht_phy_cap ?? [];
		}
	}

	caps.features.ftm_responder =
		extended_feature(info.extended_features, NL80211_EXT_FEATURE_ENABLE_FTM_RESPONDER);
	caps.features.radar_background =
		extended_feature(info.extended_features, NL80211_EXT_FEATURE_RADAR_BACKGROUND);
	caps.features.cipher_gcmp256 =
		index(info.cipher_suites ?? [], WLAN_CIPHER_SUITE_GCMP_256) >= 0;

	return caps;
};

export function eht_phy_cap(caps, byte, mask) {
	return ((caps?.eht_phy_cap?.[byte] ?? 0) & mask) != 0;
};

export function he_phy_cap(caps, byte, mask) {
	return ((caps?.he_phy_cap?.[byte] ?? 0) & mask) != 0;
};

export function he_mac_cap(caps, byte, mask) {
	return ((caps?.he_mac_cap?.[byte] ?? 0) & mask) != 0;
};

export { WLAN_CIPHER_SUITE_GCMP_256 };
