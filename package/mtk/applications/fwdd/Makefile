#
# jie.shen@mediatek.com
#
# MTK Property Software.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=fwdd
PKG_REVISION:=1f6e18
PKG_SOURCE:=$(PKG_NAME)-$(PKG_REVISION).tar.bz2
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/kernel.mk

#TARGET_CFLAGS += -DCONFIG_SUPPORT_OPENWRT
#MAKE_FLAGS += CONFIG_SUPPORT_OPENWRT=y

define Package/fwdd
  SECTION:=MTK Properties
  CATEGORY:=MTK Properties
  TITLE:=Forward daemon
  SUBMENU:=Applications
endef

define Package/fwdd/config
	source "$(SOURCE)/Config.in"
endef

define Package/fwdd/description
  forward daemon
endef

define Package/fwdd/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/fwdd $(1)/usr/bin
	$(INSTALL_BIN) ./files/fwdd.init $(1)/etc/init.d/fwdd
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/fwdd.config $(1)/etc/config/fwdd
	if [ -n "$(CONFIG_FWDD_DEFAULT_TARGET_BAND)" ]; then \
		sed -i "s/option target_band	'5G'/option target_band	'$(CONFIG_FWDD_DEFAULT_TARGET_BAND)'/g" $(1)/etc/config/fwdd; \
	fi
endef


$(eval $(call BuildPackage,fwdd))
