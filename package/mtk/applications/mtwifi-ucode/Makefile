#
# Copyright (C) 2023 hanwckf <hanwckf@vip.qq.com>
# Copyright (C) 2026 nanchuci <nanchuci023@gmail.com>
#
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=mtwifi-ucode
PKG_LICENSE:=GPL-2.0+
PKG_VERSION:=2
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/mtwifi-ucode
  SECTION:=MTK Properties
  CATEGORY:=MTK Properties
  SUBMENU:=Applications
  TITLE:=mtwifi configure scripts for mt799x (ucode)
  DEPENDS:=+wifi-dats +wifi-scripts \
	+ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-ubus \
	+ucode-mod-nl80211 +ucode-mod-rtnl +ucode-mod-digest \
	@!PACKAGE_luci-app-mtk @!PACKAGE_wifi-profile
  CONFLICTS:=mtwifi-cfg
endef

define Package/mtwifi-ucode/description
  mtwifi driver glue for the netifd ucode wireless framework:
  L1 profile parsing, MTK .dat generation, hostapd/wpa_supplicant
  handling, VAP name allocation, WPS external registrar.
endef

define Build/Compile
endef

define Package/mtwifi-ucode/install
	$(INSTALL_DIR) $(1)/sbin

	$(CP) ./files/* $(1)/
	$(LN) l1util $(1)/sbin/l1dat
endef

$(eval $(call BuildPackage,mtwifi-ucode))
