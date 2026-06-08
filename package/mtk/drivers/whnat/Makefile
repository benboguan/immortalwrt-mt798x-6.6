# All rights reserved.
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk


PKG_NAME:=whnat
PKG_REVISION:=a12500f4
PKG_SOURCE:=$(PKG_NAME)-$(PKG_REVISION).tar.xz
PKG_SOURCE_URL:=
PKG_BUILD_DIR:=$(KERNEL_BUILD_DIR)/$(PKG_NAME)
#PKG_SOURCE:=./src

include $(INCLUDE_DIR)/package.mk

define KernelPackage/whnat
  CATEGORY:=MTK Properties
  SUBMENU:=MTK_Drivers
  TITLE:=MTK wifi whnat driver
  FILES:=$(PKG_BUILD_DIR)/mt_whnat.ko
  AUTOLOAD:=$(call AutoLoad,67,mt_wifi mt_whnat)
  DEPENDS:=
endef

define KernelPackage/whnat/description
  Kernel module for whnat driver
endef

EXTRA_KCONFIG:= \
	CONFIG_MTK_WIFI7_WHNAT_SUPPORT=m

EXTRA_CFLAGS += -DWHNAT_SUPPORT

define Build/Compile
	+$(MAKE) $(PKG_JOBS) -C "$(LINUX_DIR)" \
		$(KERNEL_MAKE_FLAGS) \
		M="$(PKG_BUILD_DIR)" \
		EXTRA_CFLAGS="$(EXTRA_CFLAGS)" \
		$(EXTRA_KCONFIG) \
		modules
endef

$(eval $(call KernelPackage,whnat))
