/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef __MT_WIFI_MTD_H__
#define __MT_WIFI_MTD_H__

#include <linux/types.h>
#include <linux/fs.h>

int mt_mtd_write_nm_wifi(char *name, loff_t to, size_t len, const u_char *buf);
int mt_mtd_read_nm_wifi(char *name, loff_t from, size_t len, u_char *buf);

#endif /* __MT_WIFI_MTD_H__ */
