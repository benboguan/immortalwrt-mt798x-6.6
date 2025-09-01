/*
 * Copyright (c) [2020], MediaTek Inc. All rights reserved.
 *
 * This software/firmware and related documentation ("MediaTek Software") are
 * protected under relevant copyright laws.
 * The information contained herein is confidential and proprietary to
 * MediaTek Inc. and/or its licensors.
 * Except as otherwise provided in the applicable licensing terms with
 * MediaTek Inc. and/or its licensors, any reproduction, modification, use or
 * disclosure of MediaTek Software, and information contained herein, in whole
 * or in part, shall be strictly prohibited.
*/
/*
 ***************************************************************************
 ***************************************************************************

	Module Name:
	sta_profile.c

	Abstract:

*/
#include "rt_config.h"

#ifndef CONFIG_PROFILE_OFF

#ifdef CONFIG_STA_SUPPORT
#ifdef DOT11_EHT_BE
void read_sta_eht_config_from_file(
	IN PRTMP_ADAPTER pAd,
	IN char *tmpbuf,
	IN char *pBuffer)
{
	char *macptr;
	UINT32 idx;
	long value;
	struct wifi_dev *wdev = NULL;
	UINT8 band_idx = hc_get_hw_band_idx(pAd);

	if (RTMPGetKeyParameter("EHT_StaNsepPriAccess", tmpbuf,
			MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_nsep_priority_access(
					wdev, (u8)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaOmCtrl", tmpbuf,
			MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_eht_om_ctrl(
					wdev, (u8)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaTxopSharing", tmpbuf,
			MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_eht_txop_sharing_trigger(
					wdev, (u8)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaRestrictedTwt", tmpbuf,
			MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_eht_restricted_twt(
					wdev, (u8)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaScsTraffic", tmpbuf,
			MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_eht_scs_traffic(
					wdev, (u8)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaEmlsr_mr", tmpbuf,
			MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_emlsr_mr(
					wdev, (u8)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaEmlsr_padding_delay", tmpbuf,
			MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_emlsr_padding(
					wdev, (u8)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaEmlsr_trans_delay", tmpbuf,
			MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_emlsr_trans_delay(
					wdev, (u8)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaEmlsr_bitmap", tmpbuf,
		MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_emlsr_bitmap(
					wdev, (u16)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaLinkAntNum", tmpbuf,
		MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_emlsr_antnum(
					wdev, (u8)value);
			}
		}
	}

	if (RTMPGetKeyParameter("EHT_StaNstr_bitmap", tmpbuf,
		MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_nstr_bitmap(
					wdev, (u8)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaBw", tmpbuf,
			MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_eht_bw(
					wdev, (u8)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaTxNss", tmpbuf,
			MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_eht_tx_nss(
					wdev, (u8)value);
			}
		}
	}
	if (RTMPGetKeyParameter("EHT_StaRxNss", tmpbuf,
			MAX_PARAMETER_LEN, pBuffer, TRUE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("Line.%d - Band%d(STA%d): error input(=%s)\n",
					__LINE__,
					band_idx,
					idx,
					macptr);
			else {
				MTWF_PRINT("Line.%d - Band%d(STA%d) ==> ",
					__LINE__, band_idx, idx);
				wlan_config_set_eht_rx_nss(
					wdev, (u8)value);
			}
		}
	}

	/* ApcliMloDisable */
	if (RTMPGetKeyParameter("ApcliMloDisable", tmpbuf, 32, pBuffer, FALSE)) {

		for (idx = 0, macptr = rstrtok(tmpbuf, ";");
			(macptr && idx < pAd->MaxMSTANum);
			macptr = rstrtok(NULL, ";"), idx++) {
			wdev = &pAd->StaCfg[idx].wdev;
			if (kstrtol(macptr, 10, &value))
				MTWF_PRINT("I/F STA (%s%d): error input(=%s)\n",
					INF_MBSSID_DEV_NAME,
					idx,
					macptr);
			else {
				if (wdev) {
					wdev->apcli_mlo_diable = value;
#if defined(CONFIG_MAP_SUPPORT) && defined(MTK_HOSTAPD_SUPPORT)
					pAd->map_apcli_mlo_disable = value;
#endif
				}
				MTWF_PRINT("I/F STA (%s%d) ==> ApcliMloDisable = %d\n",
					INF_MBSSID_DEV_NAME, idx, wdev->apcli_mlo_diable);
			}
		}
	}

	/* ApcliMldAddr */
	if (RTMPGetKeyParameter("ApcliMldAddr", tmpbuf, 25, pBuffer, TRUE)) {
		INT j, mac_len;
		UCHAR Address[MAC_ADDR_LEN];

		/* Mac address acceptable format 01:02:03:04:05:06 (len=17) */
		mac_len = strlen(tmpbuf);
		if (mac_len != 17)
			MTWF_PRINT("%s(): invalid length (%d)\n", __func__, mac_len);
		else if (strcmp(tmpbuf, "00:00:00:00:00:00") == 0)
			MTWF_PRINT("%s(): invalid mac setting\n", __func__);
		else {
			for (idx = 0, macptr = rstrtok(tmpbuf, ";");
				(macptr && idx < pAd->MaxMSTANum);
				macptr = rstrtok(NULL, ";"), idx++) {
				wdev = &pAd->StaCfg[idx].wdev;
				if (kstrtol(macptr, 10, &value))
					MTWF_PRINT("I/F STA (%s%d): ApcliMldAddr error input(=%s)\n",
						INF_MBSSID_DEV_NAME,
						idx,
						macptr);
				else {
					for (j = 0; j < MAC_ADDR_LEN; j++)
						AtoH((tmpbuf + (j*3)), &Address[j], 1);

					if (wdev && !IS_APCLI_DISABLE_MLO(wdev)) {
						/* MLD Mac address which registers to STA Manager */
						COPY_MAC_ADDR(wdev->mld_dev->mld_addr, Address);
						MTWF_PRINT("I/F STA (%s%d) ==> ApcliMldAddr = %p\n",
							INF_MBSSID_DEV_NAME, idx, wdev->mld_dev->mld_addr);
					} else {
						COPY_MAC_ADDR(&pAd->StaCfg[idx].wdev.if_addr[0], Address);
						MTWF_PRINT("I/F STA (%s%d) ==> ApcliMldAddr = %p\n",
							INF_MBSSID_DEV_NAME, idx, &pAd->StaCfg[idx].wdev.if_addr[0]);
					}
				}
			}
		}
	}

}

#endif /* DOT11_EHT_BE */
#endif /* CONFIG_STA_SUPPORT */

#endif /* !CONFIG_PROFILE_OFF */

