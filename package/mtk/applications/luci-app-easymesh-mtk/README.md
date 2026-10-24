# luci-app-easymesh-mtk 2.0.0 — MediaTek EasyMesh (MAP Turnkey) for OpenWrt 25.12+

A native LuCI 25.12 client application that drives the MediaTek MAP Turnkey stack
(`mapd`, `1905daemon`, `wapp`) from the LuCI web UI.

Menu: **Network → EasyMesh** with three sub-pages.

| Page | Path | Content |
|---|---|---|
| Basic Settings | `network/easymesh/settings` | enable, device role, MAP version, AP-steering RSSI, client steering, channel-load limits, backhaul band priority, network optimization, channel planning, DHCP control |
| Onboarding | `network/easymesh/onboarding` | WPS push button, DPP URI retrieve / enrol, DPP presence band, EasyMesh restart |
| Status | `network/easymesh/status` | daemon state, startup state, control socket, AL MAC, backhaul link metric, topology, mapd log |

## Why it was rewritten

The previous `luci-app-easymesh-mtk` 1.1.0 could not build or run on 25.12: its
Makefile installed `./files/*` and `./www/*` (absent), `luasrc/` used the LuCI-5 Lua
controller API while `htdocs/` held LuCI-2 JavaScript (never wired together, and the
package was not declared through `luci.mk`), and the C ubus backend did not compile and
invented a `mapd.@general[0]` UCI schema no MTK daemon reads.

This package keeps the package name and the UCI option names used by the working
`luci-app-mtk` EasyMesh page (`mapd.mapd_cfg.*`, `mapd.mapd_user.*`,
`mapd.dpp_cfg.*`, `1905d_cfg.map.*`).

## Layout

```
Makefile                                                  luci.mk package definition
htdocs/luci-static/resources/view/easymesh-mtk/
    settings.js                                           form.Map('mapd') settings page
    onboarding.js                                         WPS / DPP action page
    status.js                                             read-only status page
root/usr/share/luci/menu.d/luci-app-easymesh-mtk.json      menu entries
root/usr/share/rpcd/acl.d/luci-app-easymesh-mtk.json       ubus/uci/file ACLs
root/usr/share/ucitrack/luci-app-easymesh-mtk.json         mapd change tracking
root/usr/libexec/rpcd/easymesh-mtk                         ubus object "easymesh"
root/etc/init.d/easymesh                                   MAP bring-up service
root/etc/uci-defaults/99-easymesh-mtk                      UCI section skeleton
po/zh_Hans/easymesh-mtk.po                                 Simplified Chinese
```

No Lua, no compiled C helper, no extra daemon: LuCI talks to rpcd directly.

## Service lifecycle

`/etc/init.d/easymesh` owns the MAP daemons. The vendor bring-up scripts
(`map_restart.sh` / `EasyMesh_openwrt.sh` / `EasyMesh_openwrt5x.sh` / `EasyMesh.sh`)
have no *stop* action and can start a second `mapd`/`wapp`/`1905d` instance when run
twice, so the init script stops the daemons first, runs the bring-up script and then
verifies that `wapp`, `p1905_managerd` and `mapd` are up.

* `Enable EasyMesh` → `set Enable 0|1` → daemons stopped/started (runtime).
* `enable` / `disable` ubus methods → `init.d enable|disable` for `easymesh`, `mapd`,
  `1905d/1905daemon`, `wappd/wapp`, `easymesh_bridge` → boot state, shown as the
  *Startup* row on the status page.
* `restart` → `init.d easymesh restart` (falls back to the bring-up script).

## Backend (rpcd)

```
ubus call easymesh get_status
ubus call easymesh get_uri     '{"ifname":"ra0"}'
ubus call easymesh set         '{"key":"DeviceRole","value":"1"}'
ubus call easymesh action      '{"action":"wps"}'
ubus call easymesh action      '{"action":"dpp_enroll","uri":"DPP:V:2;K=..."}'
ubus call easymesh restart
ubus call easymesh enable | disable
```

`set` accepts only a whitelist of MTK options (each with a value domain), mirrors
`mapd.mapd_cfg.*` into `mapd.mapd_user.*` (the daemon's user override) and, for
`DeviceRole`, updates `mapd.dpp_cfg.allowed_role` (controller→2, agent→1, auto→0).

Accepted keys: `DeviceRole`, `Enable`, `SteerEnable`, `APSteerRssiTh`,
`CUOverloadTh_2G/5G_L/5G_H/6G`, `BhPriority2G/5GL/5GH/6G`,
`NetworkOptimizationEnabled`, `NtwrkOptConnectWaitTime`, `NtwrkOptDisconnectWaitTime`,
`NtwrkOptPostCACTriggerTime`, `BandSwitchTime`, `NetworkOptPrefer5Gover2G`,
`NetworkOptPrefer5Gover2GRetryCnt`, `ChPlanningEnable`,
`ChPlanningUserPreferredChannel2G/5G/6G`, `ChPlanningIdleTime`,
`ChPlanningIdleByteCount`, `AutoBHSwitching`, `DhcpCtl`, `map_ver`, `allowed_role`,
`presence_band_priority`.

## Installation

```sh
cp -a luci-app-easymesh-mtk /path/to/immortalwrt-openwrt-25.12/package/mtk/applications/
cd /path/to/immortalwrt-openwrt-25.12
make menuconfig     # LuCI -> Applications -> luci-app-easymesh-mtk
make package/luci-app-easymesh-mtk/compile V=s
```

Device-only install (no rebuild): `cp -r htdocs/* /www/; cp -r root/* /` then
`/etc/init.d/rpcd restart` and `/etc/init.d/uhttpd restart`.

## Coverage of the MTK "Multi-AP Application Note v4.1"

| Documented item | Where it lands |
|---|---|
| `mapd.mapd_cfg.DeviceRole` (0/1/2) + `dpp_cfg.allowed_role` mapping | Settings → General |
| `1905d_cfg.map.map_ver` (R1…R5, R4 ⇒ use R3) | Settings → General |
| `APSteerRssiTh`, `SteerEnable`, `CUOverloadTh_2G/5G_L/5G_H` | Settings → General |
| `BhPriority2G/5GL/5GH/6G` (0 = never, 1 = highest) | Settings → Backhaul |
| `AutoBHSwitching`, `BandSwitchTime` (0 = never retry) | Settings → Backhaul / Advanced |
| `NetworkOptimizationEnabled`, `NtwrkOpt*WaitTime`, `NetworkOptPrefer5Gover2G` | Settings → Advanced |
| `ChPlanningEnable`, `ChPlanningUserPreferredChannel2G/5G`, `ChPlanningIdleTime` | Settings → Advanced |
| `DhcpCtl` | Settings → Advanced |
| WPS push button (`wappctrl <if> wps_pbc`) | Onboarding |
| DPP `get_dpp_uri` / `dpp_bootstrap_get_uri`, `dpp_qr_code`, `dpp_start`, `presence_band_priority` | Onboarding |
| Daemon start order, `/tmp/mapd_ctrl`, bring-up script re-run | `restart`, `init.d easymesh` |
| `mapd_cli show_bh_link_metric`, `dump_topology_v1`, `/tmp/mapd_log` | Status |

Deliberately **not** implemented: the `mapd_cli` runtime operations of the reference UI
(`bh_priority`, `steerbh`, `steermand`, `acl_ctrl`, `set_bss_prio`, `metric_policy_set`,
`mib *`, `sp_*`) — the persistent UCI equivalents are used instead;
`/etc/mapd_strng.conf` band-steering parameters (different file, not the `mapd` UCI
package); the `wts_bss_info_config` BSS/MLD editor, traffic separation, DSCP→PCP and
Mesh SR (vendor `luci-app-mtk` Advanced page); `ThirdPartyConnection` / `BhProfile*`
(needs a DHCP-control caveat).

## Driver `.dat` / nvram values (not UCI)

| Driver value | Purpose | How to set it |
|---|---|---|
| `MapMode` | `1` = MAP Turnkey, `2` = standalone band steering | driver `.dat` (all radios) / `nvram_set 2860 MapMode 1`, reboot |
| `MAP_Turnkey`, `MapEnable` | enable turnkey features / MAP support | `.dat` + `nvram_set`, reboot |
| `AutoChannelSkipList` / `…6G` | per-radio channel skip list, e.g. `52;56;60;64` | `.dat` (`datconf`), reboot the MAP network |
| `ChannelGrp` | 5 GHz channel grouping for triband (`0:0:1:1` / `1:1:0:0`) | `.dat`, reboot |
| `BssidNum` | MBSS count per radio; add/remove requires MAP disabled first | `.dat` / WiFi pages |
| `SREnable`, `SRMode`, `SRDPDEnable`, `BSSColorValue` | Mesh Spatial Reuse | `.dat`; `MapMode=1` forces `SREnable=0`/`SRMode=0` |
| `DfsDedicatedZeroWait` / `DfsZeroWaitDefault` | zero-wait DFS | `.dat` / `uci set wireless.<radio>.<opt>`, reboot |
| `BSEnable`, nvram forms of `APSteerRssiTh`/`SteerEnable`/`CUOverloadTh_*` | standalone band steering (`MapMode=2`) | `nvram_set 2860 …`, reboot |

## Vendor driver interface — checked

`mt_wifi/os/linux/cfg80211/cfg80211_vndr_easy_mesh.c` dispatches 52
`MTK_NL80211_VENDOR_ATTR_EASYMESH_*` sub-IDs (SSID, wireless mode, channel, HT/VHT/EHT
BW, MLD create/reconf/destroy/link add/del/transfer, SR enable, BH SR bitmap, hidden
SSID, auth/encrypt, WPA PSK / PSK / PMK, radio on, disconnect STA, TS BH primary VID /
PCP / BH VID / FH VID, transparent VID, BCN request, HT BSS coex, PMF, auto roaming,
DSCP policy, QoS map, DPP frame, assoc-req frame, WAPP IE, ROC, CCE IE, R3 DPP URI, R3
1905 security, R3 onboarding type, BH/FH BSS, MAP channel, MAP enable, BH assoc ctrl,
DPP STA MAC, NOP state, channel-preference state). That is the **daemon → driver** RPC
surface used by `wapp`/`1905daemon`/`mapd`, not a user configuration interface: every
attribute is derived from the BSS/MAP configuration those daemons already hold.

`mt_wifi/feature/map/map.c` is the MAP protocol implementation and exports no module
parameter, proc or debugfs entry; its only configuration-looking symbols are read-only
consumers of driver profile values (`pAd->ApCfg.AutoChannelSkipList`, `BssidNum`).

The user-facing equivalents are the per-BSS `mapd.<idx>` sections /
`wts_bss_info_config` and the `mapd_cfg` options this package writes; the BSS/MLD editor
belongs to the vendor `luci-app-mtk` Advanced page and is not duplicated here.
