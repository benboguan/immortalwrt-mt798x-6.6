#ifndef __FOE_USE_HOOK_H
#define __FOE_USE_HOOK_H

#define ETH_HLEN	14
#define IP_HLEN		20

struct SkbFoeInfo{	
	unsigned short ppe_magic;	
	unsigned short ppe_foe_entry;
	unsigned char ppe_ai;
	unsigned char wan_type;
	unsigned short wan_index;
};

struct SmbdSpeedInfo{	
	unsigned char smbd_sk;		/* 1: smbd sock, 0: other sock */
	unsigned char smbd_speed;   /* 1: smbd sock, and has record mac&IP info, 0: has no mac&IP info*/
	void *smbd_outDev;          /* smbd packet dest device */
	unsigned char	smbd_mac_header[ETH_HLEN];
	unsigned char	smbd_ip_header[IP_HLEN];
};

struct ShortCutSpeedInfo{	
	unsigned char shortcut_sk;		    /* 1: shortcut app  sock, 0: other sock */
	unsigned char shortcut_speed;       /* 1: shortcut app sock, and has record mac&IP info, 0: has no mac&IP info*/
	void *        out_dev;              /* shortcut app packet dest device */
	unsigned char mac_header[ETH_HLEN];
	unsigned char ip_header[IP_HLEN];
};

#ifndef IFNAMSIZ
#define	IFNAMSIZ				16
#endif
typedef struct{
	int valid;
	char ifname[IFNAMSIZ];
	unsigned char smac_add[6];
	unsigned char dmac_add[6];
	unsigned int sessionID;
	unsigned int src_ip;
	unsigned int dst_ip;
	int dns_valid;
	unsigned int pri_dns;
	unsigned int snd_dns;
}SMUX_Bridge_Info_Data;
#endif
