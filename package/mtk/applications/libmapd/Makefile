#
# Copyright (C) 2006-2012 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=libmapd
PKG_REVISION:=e1e011
PKG_SOURCE:=$(PKG_NAME)-$(PKG_REVISION).tar.bz2
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/kernel.mk

define Package/libmapd
  SECTION:=MTK Properties
  CATEGORY:=MTK Properties
  SUBMENU:=Libraries
  TITLE:=mtk mapd library
endef

define Package/libmapd/description
  mtk mapd library
endef

include ./mapd_config

Hooks/Prepare/Pre += Build/Prepare/PrintConfig

TARGET_CFLAGS += $(FPIC)

ifeq ($(CONFIG_MULTIAP),y)
TARGET_CFLAGS += -DSUPPORT_MULTI_AP
endif
ifeq (y, $(filter y, $(CONFIG_MTK_MAP_R2_6E_SUPPORT) $(CONFIG_MTK_WIFI_MAP_R2_6E_SUPPORT) $(CONFIG_MTK_WIFI7_MAP_R2_6E_SUPPORT)))
TARGET_CFLAGS += -DMAP_6E_SUPPORT
endif
ifeq (y, $(filter y, $(CONFIG_MTK_WIFI_MAP_R6_SUPPORT) $(CONFIG_MTK_WIFI7_MAP_R6_SUPPORT)))
TARGET_CFLAGS += -DMAP_R6
endif
ifeq (y, $(filter y, $(CONFIG_MTK_WIFI_MAP_HOSTAPD_SUPPORT) $(CONFIG_MTK_WIFI7_MAP_HOSTAPD_SUPPORT)))
TARGET_CFLAGS += -DMTK_MLO_MAP_SUPPORT
endif
define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		$(MAKE_FLAGS) \
		$(TARGET_CONFIGURE_OPTS) \
		CFLAGS="$(TARGET_CFLAGS)" \
		shared
endef

define Build/InstallDev
	$(INSTALL_DIR)  $(1)/usr/include
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/include/mapd_interface_ctrl.h  $(1)/usr/include/
	$(INSTALL_DIR)  $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/libmapd_interface_client.so* $(1)/usr/lib/
endef

define Package/libmapd/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/libmapd_interface_client.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,libmapd))
