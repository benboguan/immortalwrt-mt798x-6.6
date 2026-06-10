#ifndef __FOE_HOOK_H
#define __FOE_HOOK_H
#include <uapi/linux/foe_hook.h>

#define FOE_MAGIC_PCI		    0x7273
#define FOE_MAGIC_WLAN		    0x7274
#define FOE_MAGIC_GE		    0x7275
#define FOE_MAGIC_PPE		    0x7276
#define FOE_MAGIC_ATM		    0x7277
#define FOE_MAGIC_WLAN_7615	    0x7615

#ifdef TCSUPPORT_MT7510_FE
#define FOE_MAGIC_PTM		    0x7278
#define FOE_MAGIC_EPON		    0x7279
#define FOE_MAGIC_GPON		    0x727a
//#define FOE_MAGIC_CRYPTO	    0x727b

#define FOE_MAGIC_CRYPTO_E_1	    0x727b
#define FOE_MAGIC_CRYPTO_D_1	    0x727c
#define FOE_MAGIC_CRYPTO_E_2	    0x727d
#define FOE_MAGIC_CRYPTO_D_2	    0x727e
#define FOE_MAGIC_OFFLOAD	    0x727f
#define FOE_MAGIC_PTM_LAN		    0x7280
#endif

#define	FOE_MAGIC_L2TP_VPN_UPSTREAM	0x7281
#define	FOE_MAGIC_L2TP_VPN_DOWNSTREAM	0x7282

#define FOE_MAGIC_LOCAL				0x7283
#define FOE_MAGIC_XSI				0x7284

#define	FOE_MAGIC_GRE_UP_1	    0x7285
#define	FOE_MAGIC_GRE_UP_2	    0x7286
#define	FOE_MAGIC_GRE_DOWN_1	0x7287
#define	FOE_MAGIC_GRE_DOWN_2	0x7288

#define	FOE_MAGIC_SPEED_TEST_UPSTREAM	0x7289

#define	FOE_MAGIC_VXLAN_UP_1	0x728a
#define	FOE_MAGIC_VXLAN_UP_2	0x728b
#define	FOE_MAGIC_VXLAN_DOWN_1	0x728c
#define	FOE_MAGIC_VXLAN_DOWN_2	0x728d

#define FOE_MAGIC_ASYM_UPSTREAM 0x728e
#define FOE_MAGIC_ASYM_DOWNSTREAM 0x728f
#define	FOE_MAGIC_PTM_CIRPIR	0X7290

#define	FOE_MAGIC_VXLAN_UP_FRAG	0x7291

#define FOE_MAGIC_LOCAL_MCAST	0x7292

#define FOE_MAGIC_USBNET 0x7293
#define FOE_MAGIC_APP_SHORTCUT	0x7294

#define FOE_MAGIC_AE_WAN				0x7295

#define FOE_MAGIC_NPU_OFFLOAD				0x7296
#define FOE_MAGIC_WLAN_TX				    0x729b


#define	FOE_MAGIC_GRE_HWDOWN_1	0x7297
#define	FOE_MAGIC_VXLAN_HWDOWN_1	0x7298
#define	FOE_MAGIC_L2TP_HWDOWN_1	0x7299

#define FOE_MAGIC_XSI_GDM4				0x729a
#define FOE_MAGIC_WLAN_TX				0x729b



#define FOE_MAGIC_TR471_TEST_UPSTREAM 0x729c
#define FOE_MAGIC_TR471_HW_TEST_UPSTREAM 0x729d

#define FOE_MAGIC_OLT					0x729e

#define FOE_MAGIC_TR471_NPU_DOWNSTREAM 0x729f
#define FOE_MAGIC_TR471_NPU_UPSTREAM 0x72a0




#define	L2TP_VPN_PPP_NAME	"ppp100"
#define L2TP_VPN_GAME_NAME	"l2tp_1"
#define	HWNAT_PKT_ERROR		0
#define	HWNAT_PKT_UPSTREAM	1
#define	HWNAT_PKT_DOWNSTREAM	2

#define HWNAT_IPSEC_LEARING 0
#define HWNAT_IPSEC_SPEED 1
#define HWNAT_IPSEC_ROLLBACK 2

#define IPSEC_SKB_CB			47

#define FOE_OPE_GETENTRYNUM 0
#define FOE_OPE_CLEARENTRY  1

#if defined(TCSUPPORT_HSGMII_LAN)
#define HWNAT_LAN_IF_MAXNUM	12
#else
#define HWNAT_LAN_IF_MAXNUM	8
#endif
#define HWNAT_LAN_IF_BASE		0//0~7 is lan interface
#define HWNAT_WLAN_IF_MAXNUM	16 //16 is max wifi interface
#define HWNAT_WLAN_IF_BASE		16//16  is base
#if defined(TCSUPPORT_XSI_ENABLE) || defined(TCSUPPORT_USB_MULTICAST) ||  defined(TCSUPPORT_HSGMII_LAN)
#define HWNAT_LAN_IF_MASK		(0x3FFF)
#define HWNAT_USB_IF_BASE		15
#define HWNAT_USB_IF_NUM		1 
#define HWNAT_USB_IF_MASK		(0x1)
#define HWNAT_XSI_IF_BASE		14
#define HWNAT_XSI_IF_NUM		1 
#define HWNAT_XSI_IF_MASK		(0x1)
#else
#define HWNAT_LAN_IF_MASK		(0xFFFF)
#define HWNAT_USB_IF_BASE		15
#define HWNAT_USB_IF_NUM		0 
#define HWNAT_USB_IF_MASK		0
#define HWNAT_XSI_IF_BASE		14
#define HWNAT_XSI_IF_NUM		0
#define HWNAT_XSI_IF_MASK		0
#endif
#if defined(TCSUPPORT_WLAN_MT7990)
#define HWNAT_WLAN_IF_NUM		4
#define HWNAT_WLAN_IF_I_NUM		4
#define HWNAT_WLAN_IF_X_NUM		4
#else
#define HWNAT_WLAN_IF_NUM		8 
#define HWNAT_WLAN_IF_I_NUM		8
#endif
#define HWNAT_RA_IF_MASK		(0xFF)
#define HWNAT_RAI_IF_MASK		(0xFF)
#define HWNAT_WLAN_IF_I_BASE		(HWNAT_WLAN_IF_BASE+HWNAT_WLAN_IF_NUM)
#define HWNAT_WLAN_IF_MASK		(HWNAT_RA_IF_MASK | (HWNAT_RAI_IF_MASK << (HWNAT_WLAN_IF_NUM)))
/* Set pon_serdes as lan */
#define HWNAT_AEWAN_LAN_IF_NUM		1 
#define HWNAT_AEWAN_LAN_IF_MASK		(0x1) 

#define MULTICAST_SPEED_STATE_I 		3	//with lan and with wlan
#define MULTICAST_SPEED_STATE_II		1	//with lan and without wlan
#define MULTICAST_SPEED_STATE_III		2	//without lan and with wlan
#define MULTICAST_SPEED_STATE_IV   		0	//without lan and without wlan

#define LAN_STATE_I     1   //soc lan + external lan port
#define LAN_STATE_II    2   //only soc lan or only external lan port or both not

typedef struct {
    char virtual_name[16];
	char dev_name[16];
	char valid;
}wan_virtualdev_ifname;
struct port_info {
    unsigned long int tsid:8;
    unsigned long int channel:5;
    unsigned long int nbq:5;
    unsigned long int fast:1;
    unsigned long int txq:4;
    unsigned long int atm_pppoa:1;
    unsigned long int atm_ipoa:1;
    unsigned long int atm_vc_mux:1;
    unsigned long int eth_macSTagEn:1;
	unsigned long int eth_is_wan:1;
    unsigned long int ds_to_qdma:1;
    unsigned long int ds_need_offload:1;
    unsigned long int force_high_priority_ring:1;
	unsigned long int txq_is_valid:1;
    unsigned long int stag:16;
    unsigned long int magic:16;
	unsigned long int udf:8;//add for inode wifi 
};

typedef union {
#if defined(TCSUPPORT_CPU_EN7523)
	struct {
#ifdef __BIG_ENDIAN
			unsigned int resv0		: 1 ;
			unsigned int mic_idx	: 1 ;
			unsigned int sp_tag 	: 16 ;
			unsigned int ico		: 1;
			unsigned int uco		: 1;
			unsigned int tco		: 1;
			unsigned int tso		: 1;
			unsigned int fast		: 1 ;
			unsigned int oam		: 1 ;
			unsigned int channel	: 5 ;
			unsigned int queue		: 3 ;
#else
			unsigned int queue		: 3 ;
			unsigned int channel	: 5 ;
			unsigned int oam		: 1 ;
			unsigned int fast		: 1 ;
			unsigned int tso		: 1;
			unsigned int tco		: 1;
			unsigned int uco		: 1;
			unsigned int ico		: 1;
			unsigned int sp_tag 	: 16 ;
			unsigned int mic_idx	: 1 ;
			unsigned int resv0		: 1 ;
#endif
		
#ifdef __BIG_ENDIAN
			unsigned int no_drop	: 1;	/*means not be dropped by QDMA*/
			unsigned int mtr_g		: 7;	/*0x7f means not use meter*/
			unsigned int fport		: 4;
			unsigned int nboq		: 5;
			unsigned int hwf		: 1;
			unsigned int resv2		: 3;
			unsigned int act_grp	: 11;
#else
			unsigned int act_grp	: 11;
			unsigned int resv2		: 3;
			unsigned int hwf		: 1;
			unsigned int nboq		: 5;
			unsigned int fport		: 4;	/* EN7581 force port extend to 4bit */
			unsigned int mtr_g		: 7;	/*0x7f means not use meter*/
			unsigned int no_drop	: 1;	/*means not be dropped by QDMA*/
#endif
		} raw ;
#elif defined(TCSUPPORT_CPU_EN7580)
struct {
#ifdef __BIG_ENDIAN
		unsigned int resv0		: 1 ;
		unsigned int mic_idx	: 1 ;
		unsigned int sp_tag		: 16 ;
		unsigned int ico		: 1;
		unsigned int uco		: 1;
		unsigned int tco		: 1;
		unsigned int tso		: 1;
		unsigned int fast		: 1 ;
		unsigned int oam		: 1 ;
		unsigned int channel	: 5 ;
		unsigned int queue		: 3 ;
#else
		unsigned int queue		: 3 ;
		unsigned int channel	: 5 ;
		unsigned int oam		: 1 ;
		unsigned int fast		: 1 ;
		unsigned int tso		: 1;
		unsigned int tco		: 1;
		unsigned int uco		: 1;
		unsigned int ico		: 1;
		unsigned int sp_tag		: 16 ;
		unsigned int mic_idx	: 1 ;
		unsigned int resv0		: 1 ;
#endif
	
#ifdef __BIG_ENDIAN
		unsigned int no_drop	: 1;	/*means not be dropped by QDMA*/
		unsigned int mtr_g		: 7;	/*0x7f means not use meter*/
		unsigned int fport		: 3;
		unsigned int nboq		: 5;
		unsigned int resv2		: 6;
		unsigned int act_grp	: 10;
#else
		unsigned int act_grp	: 10;
		unsigned int resv2		: 6;
		unsigned int nboq		: 5;
		unsigned int fport		: 3;
		unsigned int mtr_g		: 7;	/*0x7f means not use meter*/
		unsigned int no_drop	: 1;	/*means not be dropped by QDMA*/
#endif
	} raw ;
#else
	struct {
#ifdef __BIG_ENDIAN
		unsigned int resv				: 1 ;
		unsigned int tsid				: 5 ;
		unsigned int tse				: 1 ;
		unsigned int dei				: 1 ;
		unsigned int gem				: 12 ;
		unsigned int oam				: 1 ;
		unsigned int channel			: 8 ;
		unsigned int queue				: 3 ;	
#else
		unsigned int queue				: 3 ;	
		unsigned int channel			: 8 ;
		unsigned int oam				: 1 ;
		unsigned int gem				: 12 ;
		unsigned int dei				: 1 ;
		unsigned int tse				: 1 ;
		unsigned int tsid				: 5 ;
		unsigned int resv				: 1 ;
#endif /* __BIG_ENDIAN */

#ifdef __BIG_ENDIAN
		unsigned int ico				: 1 ;
		unsigned int uco				: 1 ;
		unsigned int tco				: 1 ;
		unsigned int tso				: 1 ;
		unsigned int pmap				: 6 ;
		unsigned int fport				: 3 ;
		unsigned int insv				: 1 ;
		unsigned int tpid				: 2 ;	
		unsigned int vid				: 16 ;	
#else
		unsigned int vid				: 16 ;	
		unsigned int tpid				: 2 ;	
		unsigned int insv				: 1 ;
		unsigned int fport				: 3 ;
		unsigned int pmap				: 6 ;
		unsigned int tso				: 1 ;
		unsigned int tco				: 1 ;
		unsigned int uco				: 1 ;
		unsigned int ico				: 1 ;
#endif /* __BIG_ENDIAN */
	} raw ;
#endif

	struct {
#ifdef __BIG_ENDIAN
		unsigned int mtr				: 1 ;
		unsigned int fport_ppe			: 3 ;
		unsigned int gem				: 16 ;
		unsigned int oam				: 1 ;
		unsigned int channel_ppe		: 5 ;
		unsigned int channel			:3 ;
		unsigned int queue				: 3 ;	
#else
		unsigned int queue				: 3 ;	
		unsigned int channel			:3 ;
		unsigned int channel_ppe		: 8 ;
		unsigned int oam				: 1 ;
		unsigned int gem				: 16 ;
		unsigned int fport_ppe			: 3 ;
		unsigned int mtr				: 1 ;
#endif /* __BIG_ENDIAN */

#ifdef __BIG_ENDIAN
		unsigned int ico				: 1 ;
		unsigned int uco				: 1 ;
		unsigned int tco				: 1 ;
		unsigned int tso				: 1 ;
		unsigned int mtr_index			: 6 ;
		unsigned int fport				: 3 ;
		unsigned int insv				: 1 ;
		unsigned int tpid				: 2 ;	
		unsigned int vid				: 16 ;	
#else
		unsigned int vid				: 16 ;	
		unsigned int tpid				: 2 ;	
		unsigned int insv				: 1 ;
		unsigned int fport				: 3 ;
		unsigned int mtr_index			: 6 ;
		unsigned int tso				: 1 ;
		unsigned int tco				: 1 ;
		unsigned int uco				: 1 ;
		unsigned int ico				: 1 ;
#endif /* __BIG_ENDIAN */
	} raw1 ;/*tx msg format1 for cpu path ratelimit by ppe meter in EN7526C*/
	
	unsigned int word[2] ;
}FETxMsg_T ;


/*****************************
 * FRAME ENGINE REGISTERS OFFSET *
 *****************************/
#define FE_GLO_CFG_OFF          (0x0000)
#define CDMP_VLAN_CT_OFF		(0x0400)
#define CDM_VLAN_GE_OFF         (0x1400)
#define GDM2_FWD_CFG_OFF		(0x1500)
#define GDM2_MIB_CLR_OFF		(0x1520)
#define GDM2_LEN_CFG_OFF		(0x1524)
#define GDM2_CHN_EN_OFF			(0x152c)
#define GDM2_TX_GET_CNT_OFF		(0x1600)
#define GDM2_TX_OK_CNT_OFF		(0x1604)
#define GDM2_TX_DROP_CNT_OFF	(0x1608)
#define GDM2_TX_OK_BYTE_CNT_OFF	(0x160c)
#define GDM2_RX_OK_CNT_OFF		(0x1650)
#define GDM2_RX_OVER_DROP_CNT_OFF	(0x1654)
#define GDM2_RX_ERROR_DROP_CNT_OFF	(0x1658)
#define GDM2_RX_OK_BYTE_CNT_OFF		(0x165c)
#define GDM2_RX_ETH_CRCE_CNT_OFF	(0x1674)
#define GDM2_RX_ETH_RUNT_CNT_OFF	(0x1680)
#define GDM2_RX_ETH_LONG_CNT_OFF	(0x1684)


struct sk_buff;
struct net_device;
struct net_device_stats;
struct net_data_s;


extern int (*ra_sw_nat_hook_rx_set_l2lu) (struct sk_buff * skb, unsigned int direction, int PpeIndex);
extern int (*ra_sw_nat_hook_rx) (struct sk_buff * skb);
extern int (*ra_sw_nat_hook_wifi_tx) (struct sk_buff * skb, unsigned int rx_len);
extern int (*ra_sw_nat_to_wifi_fast_tx) (struct sk_buff * skb);
extern int (*ra_sw_nat_to_xsi_fast_tx) (struct sk_buff * skb);
extern int (*ra_sw_nat_mcst_offload)(struct sk_buff *skb, int *dp);
extern int (*ra_sw_nat_ds_offload)(struct sk_buff *skb, int *dp);
extern int (*ra_nat_cirpir_get_start_idx)(void);
extern int (*ra_sw_nat_hook_update_dp)(int index, int dp);
extern int (*ra_sw_nat_hook_update_vlan)(int index,int outer_vlan,int inner_vlan);
extern int (*ra_sw_nat_local_in_tx) (struct sk_buff * skb,unsigned short port);
extern int (*ra_sw_nat_cds_all_ratelimit_hook) (struct sk_buff* skb);

extern int (*ra_sw_nat_hook_tunnel_down_acc_hook)(struct sk_buff * skb, unsigned int rx_len, unsigned short sptag, unsigned short udf, int magic, char *data, int data_length);

extern int (*ra_sw_nat_hook_save_rxinfo)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_restore_rxinfo)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_save_txinfo)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_restore_txinfo)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_save_gre_txinfo)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_restore_gre_txinfo)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_is_gre_offload_pkt)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_save_vxlan_txinfo)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_restore_vxlan_txinfo)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_is_vxlan_offload_pkt)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_is_hwnat_pkt)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_sendto_ppe)(struct sk_buff *skb);
extern int (*ra_sw_nat_hook_set_l2tp_dev)(struct net_device *dev);
extern struct net_device* (*ra_sw_nat_hook_read_l2tp_dev)(void);
extern int (*ra_sw_nat_rtsp_offload_restore) (struct sk_buff * skb, int calc_sum);
extern int (*ra_sw_nat_rtsp_data_handle) (struct sk_buff * skb, char *rb_ptr, unsigned int datalen);
extern void (*ra_sw_nat_set_wan_acntid_hook) (struct sk_buff *skb, unsigned char wan_index, unsigned char dir);
extern void (*ra_sw_nat_clear_wan_acntid_hook)(unsigned char wan_index);
extern void (*ra_sw_nat_get_wan_acntid_counter_hook)(unsigned char wan_index, struct net_device_stats *storage);
extern void (*ra_sw_nat_set_mac_hook) (struct sk_buff *skb, unsigned char *mac);
extern void (*ra_sw_nat_set_wan_meterid_hook) (struct sk_buff *skb, unsigned char wan_index);
extern int (*ra_sw_nat_rtspv6_npt_data_handle) (struct sk_buff * skb);
#if defined(CONFIG_BRIDGE_VLAN_FILTERING)
extern void (*ra_sw_nat_set_mul_br_vid_hook)(struct sk_buff *skb, unsigned short vid);
extern unsigned short (*ra_sw_nat_get_mul_br_vid_hook)(struct sk_buff *skb);
#endif
#ifdef TCSUPPORT_MT7510_FE
extern int (*ra_sw_nat_hook_tx) (struct sk_buff * skb, struct port_info * pinfo, int magic);
#else
extern int (*ra_sw_nat_hook_tx) (struct sk_buff * skb, int gmac_no);
#endif
extern int (*ra_hit_bind_force_to_cpu) (struct sk_buff * skb);
extern int (*ra_sw_nat_hook_free) (struct sk_buff * skb);
extern int (*ra_sw_nat_hook_rxinfo) (struct sk_buff * skb, int magic, char *data, int data_length);
extern int (*ra_sw_nat_hook_txq) (struct sk_buff * skb, int txq);
extern int (*ra_sw_nat_hook_magic) (struct sk_buff * skb, int magic);
extern int (*ra_sw_nat_hook_set_magic) (struct sk_buff * skb, int magic);
extern int (*ra_sw_nat_hook_xfer) (struct sk_buff *skb, const struct sk_buff *prev_p);
extern int (*ra_sw_nat_hook_foeentry) (void * inputvalue,int operation);
extern int (*ra_sw_nat_hook_is_entry_valid) (int foe_entry_idx, int ring_idx);
extern int (*ra_sw_nat_hook_is_alive_pkt)(unsigned int crsn);
extern int (*ra_sw_nat_hook_clean_entry_by_dst_mac)(struct net_data_s *net_data);
extern int (*ra_sw_nat_hook_clean_entry_by_channel)(int channelIdx);
extern int (*ra_sw_nat_hook_clean_entry_by_dev)(struct net_device *dev);
extern int (*ra_sw_nat_hook_clean_entry_by_mac)(const unsigned char* mac);
#if defined(TCSUPPORT_CPU_MT7520) || defined(TCSUPPORT_CPU_EN7512)
extern int (*MT7530LanPortMap2Switch_hook)(int port); 
#endif

#ifdef TCSUPPORT_RA_HWNAT_ENHANCE_HOOK
extern int (*ra_sw_nat_hook_drop_packet) (struct sk_buff * skb);
extern int (*ra_sw_nat_hook_clean_table) (void);
extern int (*ra_sw_nat_hook_clean_multicast_entry) (void);
#endif

#ifdef TCSUPPORT_MT7510_FE
extern void (*restore_offload_info_hook)(struct sk_buff *skb, struct port_info *pinfo, int magic);
#endif

extern int (*ra_sw_nat_hook_cpu_meter)(struct sk_buff* skb,FETxMsg_T* txMsg,struct port_info* pinfo,unsigned char dir,unsigned short mtrIndex);
extern int (*ra_sw_nat_natv6_fast_handler) (struct sk_buff * skb);

extern int (*ra_sw_nat_vxlan_fast_handler) (struct sk_buff * skb);

extern int (*ra_sw_nat_npu_offload_vxlan_enable)(void);
extern int (*ra_sw_nat_npu_store_vxlan_hdr) (struct sk_buff * skb,unsigned int type);
extern int (*ra_sw_nat_npu_check_vxlan_hdr_list_hook)(void);
extern int (*ra_sw_nat_restore_npu_pingpong_info) (struct sk_buff * skb,unsigned short cpu_info);
extern int (*ra_sw_nat_add_nptv6_prefix)(unsigned char* ifname,unsigned short* s_prefix,unsigned int s_prefix_len,unsigned short* d_prefix,unsigned int d_prefix_len);

extern int (*ra_sw_wifi_hook_is_wifi_down) (struct sk_buff * skb, int band);
extern int (*ra_sw_wifi_hook_wifi_down_handle) (struct net_device *dev);
extern int (*ra_sw_wifi_hook_wifi_up_handle) (struct net_device *dev);

extern int (*ra_nat_delete_mc_drop_by_grp) (unsigned int grp_addr);

extern int (*ra_sw_nat_hit_ifc_fast_handler) (struct sk_buff * skb);
extern int (*ra_sw_nat_hook_ifc_hit_info) (struct sk_buff* skb, unsigned char hit, unsigned int ifc_id);

#endif
