#
# Copyright (C) hanwckf <hanwckf@vip.qq.com>
#
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for mtwifi-ucode/mtwifi-cfg
LUCI_DEPENDS:=+mtwifi-ucode +rpcd-mod-ucode
LUCI_PKGARCH:=all

PKG_VERSION:=2

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
