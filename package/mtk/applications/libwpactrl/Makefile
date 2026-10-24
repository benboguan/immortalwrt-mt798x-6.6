#
# MTK Property Software.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=libwpactrl
PKG_REVISION:=dcc1d7
PKG_SOURCE:=$(PKG_NAME)-$(PKG_REVISION).tar.bz2
PKG_RELEASE:=1

PKG_BUILD_PARALLEL:=0

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

# set to 1 to enable debugging
DEBUG=

PKG_BUILD_DEPENDS:= hostapd

define Package/libwpactrl
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=C library for the wpa ctrl interface
  DEPENDS:=@(PACKAGE_hostapd||PACKAGE_hostapd-basic||PACKAGE_hostapd-basic-openssl||PACKAGE_hostapd-basic-wolfssl||PACKAGE_hostapd-mini||PACKAGE_hostapd-openssl||PACKAGE_hostapd-wolfssl||PACKAGE_wpad||PACKAGE_wpad-mesh-openssl||PACKAGE_wpad-mesh-wolfssl||PACKAGE_wpad-basic||PACKAGE_wpad-basic-openssl||PACKAGE_wpad-basic-wolfssl||PACKAGE_wpad-mini||PACKAGE_wpad-openssl||PACKAGE_wpad-wolfssl)
  ABI_VERSION:=20130104
endef

HOSTAPD_DIR=$(shell find ${BUILD_DIR}/hostapd* -name hs20 | xargs dirname)
CMAKE_OPTIONS += -DHOSTAPD_DIR=$(HOSTAPD_DIR)

TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include -DWPACTRL_SUPPORT_MTK_EXTENSION
TARGET_LDFLAGS += -L$(STAGING_DIR)/usr/lib

define Package/libwpactrl/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/libwpactrl.so* $(1)/usr/lib/
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include/wpactrl
	$(CP) $(PKG_BUILD_DIR)/include/libwpactrl.h $(1)/usr/include/wpactrl
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/libwpactrl.so* $(1)/usr/lib
endef

$(eval $(call BuildPackage,libwpactrl))
