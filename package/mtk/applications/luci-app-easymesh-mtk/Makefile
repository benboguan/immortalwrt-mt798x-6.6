# SPDX-License-Identifier: GPL-2.0
# MediaTek EasyMesh (MAP Turnkey) LuCI application for OpenWrt 25.12+
# Rewritten from the legacy Lua/LuCI-5 package; the native LuCI client
# (menu.d + htdocs JS views + rpcd) is used, so no lua sources remain.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-easymesh-mtk
PKG_VERSION:=2.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=MTK EasyMesh maintainers

LUCI_TITLE:=LuCI support for MediaTek EasyMesh (MAP Turnkey)
LUCI_DEPENDS:=+luci-base +libmapd +libwpactrl +mapd +wapp +1905daemon +kmod-mapfilter
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
