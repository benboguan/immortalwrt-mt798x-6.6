#!/usr/bin/lua
local uci2map = {}

local shuci = require("shuci")
function uci_load(filename)
      return shuci.decode(filename)
end

local uciCfgfile = "/etc/config/mapd"

function uci2map.__trim(s)
  if s then return (s:gsub("^%s*(.-)%s*$", "%1")) end
end

function uci2map.read_pipe(pipe)
    local retry_count = 10
    local fp, txt, err
    repeat  -- fp:read() may return error, "Interrupted system call", and can be recovered by doing it again
        fp = io.popen(pipe)
        txt, err = fp:read("*a")
        fp:close()
        retry_count = retry_count - 1
    until err == nil or retry_count == 0
    return txt
end

function uci_apply_mapd_configuration()

-- converting dpp_cfg file

	local file_name = "/etc/dpp_cfg.txt"
        local file
	local uci_cfg
	uci_cfg = uci_load(uciCfgfile)
	for _, uci_vif in pairs(uci_cfg["dpp_cfg"]) do
		os.execute("sed -i '/allowed_role=/d' "..file_name)
		os.execute("sed -i '/presence_band_priority=/d' "..file_name)
	        file = io.open(file_name, "a+")
		io.output(file)
		if uci_vif.presence_band_priority ~= nil and uci_vif.presence_band_priority ~= ' ' then
	              io.write("presence_band_priority=", uci_vif.presence_band_priority, "\n")
		end
	      	if uci_vif.allowed_role ~= nil then
	              io.write("allowed_role=", uci_vif.allowed_role, "\n")
		end
		io.close()
	end

-- converting mapd_strng file

	local file_name = "/tmp/mapd_strng.txt"
        local file
	for _, uci_vif in pairs(uci_cfg["mapd_strng"]) do
	        file = io.open(file_name, "w+")
		io.output(file)
		if uci_vif.CUOverloadTh_2G ~= nil then
			io.write("CUOverloadTh_2G=", uci_vif.CUOverloadTh_2G, "\n")
		end
		if uci_vif.CUOverloadTh_5G_L ~= nil then
			io.write("CUOverloadTh_5G_L=", uci_vif.CUOverloadTh_5G_L, "\n")
		end
		if uci_vif.CUOverloadTh_5G_H ~= nil then
			io.write("CUOverloadTh_5G_H=", uci_vif.CUOverloadTh_5G_H, "\n")
		end
		if uci_vif.CUSafetyTh_2G ~= nil then
			io.write("CUSafetyTh_2G=", uci_vif.CUSafetyTh_2G, "\n")
		end
        	if uci_vif.CUSafetyTh_5G_L ~= nil then
	        	io.write("CUSafetyTh_5G_L=", uci_vif.CUSafetyTh_5G_L, "\n")
        	end
        	if uci_vif.CUSafetyTh_5G_H ~= nil then
	        	io.write("CUSafetyTh_5G_H=", uci_vif.CUSafetyTh_5G_H, "\n")
        	end
        	if uci_vif.CUOverloadTh_6G ~= nil then
	        	io.write("CUOverloadTh_6G=", uci_vif.CUOverloadTh_6G, "\n")
        	end
        	if uci_vif.CUSafetyTh_6G ~= nil then
	        	io.write("CUSafetyTh_6G=", uci_vif.CUSafetyTh_6G, "\n")
        	end
        	if uci_vif.MinRSSIOverload ~= nil then
	        	io.write("MinRSSIOverload=", uci_vif.MinRSSIOverload, "\n")
        	end
        	if uci_vif.RSSISteeringEdge_DG ~= nil then
	        	io.write("RSSISteeringEdge_DG=", uci_vif.RSSISteeringEdge_DG, "\n")
        	end
        	if uci_vif.RSSISteeringEdge_UG ~= nil then
	        	io.write("RSSISteeringEdge_UG=", uci_vif.RSSISteeringEdge_UG, "\n")
        	end
        	if uci_vif.force_roam_rssi_th ~= nil then
	        	io.write("force_roam_rssi_th=", uci_vif.force_roam_rssi_th, "\n")
        	end
        	if uci_vif.MCSCrossingThreshold_DG ~= nil then
	        	io.write("MCSCrossingThreshold_DG=", uci_vif.MCSCrossingThreshold_DG, "\n")
        	end
        	if uci_vif.MCSCrossingThreshold_UG ~= nil then
	        	io.write("MCSCrossingThreshold_UG=", uci_vif.MCSCrossingThreshold_UG, "\n")
        	end
        	if uci_vif.RSSICrossingThreshold_DG ~= nil then
	        	io.write("RSSICrossingThreshold_DG=", uci_vif.RSSICrossingThreshold_DG, "\n")
        	end
        	if uci_vif.RSSICrossingThreshold_UG ~= nil then
	        	io.write("RSSICrossingThreshold_UG=", uci_vif.RSSICrossingThreshold_UG, "\n")
        	end
        	if uci_vif.MinRSSIOverload_5G ~= nil then
	        	io.write("MinRSSIOverload_5G=", uci_vif.MinRSSIOverload_5G, "\n")
        	end
        	if uci_vif.RSSISteeringEdge_5G_DG ~= nil then
	        	io.write("RSSISteeringEdge_5G_DG=", uci_vif.RSSISteeringEdge_5G_DG, "\n")
        	end
        	if uci_vif.RSSISteeringEdge_5G_UG ~= nil then
	        	io.write("RSSISteeringEdge_5G_UG=", uci_vif.RSSISteeringEdge_5G_UG, "\n")
        	end
        	if uci_vif.MCSCrossingThreshold_5G_DG ~= nil then
	        	io.write("MCSCrossingThreshold_5G_DG=", uci_vif.MCSCrossingThreshold_5G_DG, "\n")
        	end
        	if uci_vif.MCSCrossingThreshold_5G_UG ~= nil then
	        	io.write("MCSCrossingThreshold_5G_UG=", uci_vif.MCSCrossingThreshold_5G_UG, "\n")
        	end
        	if uci_vif.RSSICrossingThreshold_5G_DG ~= nil then
	        	io.write("RSSICrossingThreshold_5G_DG=", uci_vif.RSSICrossingThreshold_5G_DG, "\n")
        	end
        	if uci_vif.RSSICrossingThreshold_5G_UG ~= nil then
	        	io.write("RSSICrossingThreshold_5G_UG=", uci_vif.RSSICrossingThreshold_5G_UG, "\n")
        	end
        	if uci_vif.phy_scal_factx100 ~= nil then
	        	io.write("phy_scal_factx100=", uci_vif.phy_scal_factx100, "\n")
        	end
        	if uci_vif.RSSIAgeLim ~= nil then
	        	io.write("RSSIAgeLim=", uci_vif.RSSIAgeLim, "\n")
        	end
        	if uci_vif.RSSIAgeLim_preAssoc ~= nil then
	        	io.write("RSSIAgeLim_preAssoc=", uci_vif.RSSIAgeLim_preAssoc, "\n")
        	end
        	if uci_vif.RSSIMeasureSamples ~= nil then
	        	io.write("RSSIMeasureSamples=", uci_vif.RSSIMeasureSamples, "\n")
        	end
        	if uci_vif.ForceStrBlockTime ~= nil then
	        	io.write("ForceStrBlockTime=", uci_vif.ForceStrBlockTime, "\n")
        	end
        	if uci_vif.BTMStrBlockTime ~= nil then
	        	io.write("BTMStrBlockTime=", uci_vif.BTMStrBlockTime, "\n")
        	end
        	if uci_vif.ForceStrForbidTime ~= nil then
	        	io.write("ForceStrForbidTime=", uci_vif.ForceStrForbidTime, "\n")
        	end
        	if uci_vif.BTMStrForbidTime ~= nil then
	        	io.write("BTMStrForbidTime=", uci_vif.BTMStrForbidTime, "\n")
        	end
        	if uci_vif.StrForbidTimeJoin ~= nil then
	        	io.write("StrForbidTimeJoin=", uci_vif.StrForbidTimeJoin, "\n")
        	end
        	if uci_vif.MinSteerRetryTime ~= nil then
	        	io.write("MinSteerRetryTime=", uci_vif.MinSteerRetryTime, "\n")
        	end
        	if uci_vif.MaxSteerRetryTime ~= nil then
	        	io.write("MaxSteerRetryTime=", uci_vif.MaxSteerRetryTime, "\n")
        	end
        	if uci_vif.St ~= nil then
	        	io.write("St=", uci_vif.St, "\n")
        	end
        	if uci_vif.MaxClientOverloaded ~= nil then
	        	io.write("MaxClientOverloaded=", uci_vif.MaxClientOverloaded, "\n")
        	end
        	if uci_vif.Btm_Retry_Time ~= nil then
	        	io.write("Btm_Retry_Time=", uci_vif.Btm_Retry_Time, "\n")
        	end
        	if uci_vif.ActivityThreshold ~= nil then
	        	io.write("ActivityThreshold=", uci_vif.ActivityThreshold, "\n")
        	end
        	if uci_vif.StartInActive ~= nil then
	        	io.write("StartInActive=", uci_vif.StartInActive, "\n")
        	end
        	if uci_vif.LowRSSIAPSteerEdge_root ~= nil then
	        	io.write("LowRSSIAPSteerEdge_root=", uci_vif.LowRSSIAPSteerEdge_root, "\n")
        	end
        	if uci_vif.LowRSSIAPSteerEdge_RE ~= nil then
	        	io.write("LowRSSIAPSteerEdge_RE=", uci_vif.LowRSSIAPSteerEdge_RE, "\n")
        	end
        	if uci_vif.MinRssiIncTh_Root ~= nil then
	        	io.write("MinRssiIncTh_Root=", uci_vif.MinRssiIncTh_Root, "\n")
        	end
        	if uci_vif.MinRssiIncTh_RE ~= nil then
	        	io.write("MinRssiIncTh_RE=", uci_vif.MinRssiIncTh_RE, "\n")
        	end
        	if uci_vif.MinRssiIncTh_Peer ~= nil then
	        	io.write("MinRssiIncTh_Peer=", uci_vif.MinRssiIncTh_Peer, "\n")
        	end
        	if uci_vif.CUAvgPeriod ~= nil then
	        	io.write("CUAvgPeriod=", uci_vif.CUAvgPeriod, "\n")
        	end
        	if uci_vif.BTMStrTimeout ~= nil then
	        	io.write("BTMStrTimeout=", uci_vif.BTMStrTimeout, "\n")
        	end
        	if uci_vif.ForceStrTimeout ~= nil then
	        	io.write("ForceStrTimeout=", uci_vif.ForceStrTimeout, "\n")
        	end
        	if uci_vif.single_steer ~= nil then
	        	io.write("single_steer=", uci_vif.single_steer, "\n")
        	end
        	if uci_vif.prohibitTime11K ~= nil then
	        	io.write("prohibitTime11K=", uci_vif.prohibitTime11K, "\n")
        	end
        	if uci_vif.PHYBasedSelection ~= nil then
	        	io.write("PHYBasedSelection=", uci_vif.PHYBasedSelection, "\n")
        	end
        	if uci_vif.disable_pre_assoc_strng ~= nil then
	        	io.write("disable_pre_assoc_strng=", uci_vif.disable_pre_assoc_strng, "\n")
        	end
        	if uci_vif.disable_post_assoc_strng ~= nil then
	        	io.write("disable_post_assoc_strng=", uci_vif.disable_post_assoc_strng, "\n")
        	end
        	if uci_vif.disable_offloading ~= nil then
	        	io.write("disable_offloading=", uci_vif.disable_offloading, "\n")
        	end
        	if uci_vif.disable_nolmultiap ~= nil then
	        	io.write("disable_nolmultiap=", uci_vif.disable_nolmultiap, "\n")
        	end
        	if uci_vif.disable_active_ug ~= nil then
	        	io.write("disable_active_ug=", uci_vif.disable_active_ug, "\n")
        	end
        	if uci_vif.disable_active_dg ~= nil then
	        	io.write("disable_active_dg=", uci_vif.disable_active_dg, "\n")
        	end
        	if uci_vif.disable_idle_dg ~= nil then
	        	io.write("disable_idle_dg=", uci_vif.disable_idle_dg, "\n")
        	end
        	if uci_vif.disable_idle_ug ~= nil then
	        	io.write("disable_idle_ug=", uci_vif.disable_idle_ug, "\n")
        	end
        	if uci_vif.GlobalProhibitTime ~= nil then
	        	io.write("GlobalProhibitTime=", uci_vif.GlobalProhibitTime, "\n")
        	end
        	if uci_vif.idle_count_th ~= nil then
	        	io.write("idle_count_th=", uci_vif.idle_count_th, "\n")
        	end
        	if uci_vif.reset_btm_csbc_at_join ~= nil then
	        	io.write("reset_btm_csbc_at_join=", uci_vif.reset_btm_csbc_at_join, "\n")
        	end
        	if uci_vif.ForcedRssiUpdate ~= nil then
	        	io.write("ForcedRssiUpdate=", uci_vif.ForcedRssiUpdate, "\n")
        	end
        	if uci_vif.CentSteerMaxBSFail ~= nil then
	        	io.write("CentSteerMaxBSFail=", uci_vif.CentSteerMaxBSFail, "\n")
        	end
        	if uci_vif.CentStrMaxOLSteerCand ~= nil then
	        	io.write("CentStrMaxOLSteerCand=", uci_vif.CentStrMaxOLSteerCand, "\n")
        	end
        	if uci_vif.CentStrMaxUGSteerCand ~= nil then
	        	io.write("CentStrMaxUGSteerCand=", uci_vif.CentStrMaxUGSteerCand, "\n")
        	end
        	if uci_vif.CentStrMaxPhyBasedSteerCand ~= nil then
	        	io.write("CentStrMaxPhyBasedSteerCand=", uci_vif.CentStrMaxPhyBasedSteerCand, "\n")
        	end
        	if uci_vif.CentStrCuMonTime ~= nil then
	        	io.write("CentStrCuMonTime=", uci_vif.CentStrCuMonTime, "\n")
        	end
        	if uci_vif.CentStrCuMonProhibitTime ~= nil then
	        	io.write("CentStrCuMonProhibitTime=", uci_vif.CentStrCuMonProhibitTime, "\n")
        	end
        	if uci_vif.MetricPolicyRcpi_24G ~= nil then
	        	io.write("MetricPolicyRcpi_24G=", uci_vif.MetricPolicyRcpi_24G, "\n")
        	end
        	if uci_vif.MetricPolicyHys_24G ~= nil then
	        	io.write("MetricPolicyHys_24G=", uci_vif.MetricPolicyHys_24G, "\n")
        	end
        	if uci_vif.MetricPolicyMetricsInclusion_24G ~= nil then
	        	io.write("MetricPolicyMetricsInclusion_24G=", uci_vif.MetricPolicyMetricsInclusion_24G, "\n")
        	end
        	if uci_vif.MetricPolicyTrafficInclusion_24G ~= nil then
	        	io.write("MetricPolicyTrafficInclusion_24G=", uci_vif.MetricPolicyTrafficInclusion_24G, "\n")
        	end
        	if uci_vif.MetricPolicyChUtilThres_24G ~= nil then
	        	io.write("MetricPolicyChUtilThres_24G=", uci_vif.MetricPolicyChUtilThres_24G, "\n")
        	end
        	if uci_vif.MetricPolicyRcpi_5GL ~= nil then
	        	io.write("MetricPolicyRcpi_5GL=", uci_vif.MetricPolicyRcpi_5GL, "\n")
        	end
        	if uci_vif.MetricPolicyHys_5GL ~= nil then
	        	io.write("MetricPolicyHys_5GL=", uci_vif.MetricPolicyHys_5GL, "\n")
        	end
        	if uci_vif.MetricPolicyMetricsInclusion_5GL ~= nil then
	        	io.write("MetricPolicyMetricsInclusion_5GL=", uci_vif.MetricPolicyMetricsInclusion_5GL, "\n")
        	end
        	if uci_vif.MetricPolicyTrafficInclusion_5GL ~= nil then
	        	io.write("MetricPolicyTrafficInclusion_5GL=", uci_vif.MetricPolicyTrafficInclusion_5GL, "\n")
        	end
        	if uci_vif.MetricPolicyChUtilThres_5GL ~= nil then
	        	io.write("MetricPolicyChUtilThres_5GL=", uci_vif.MetricPolicyChUtilThres_5GL, "\n")
        	end
        	if uci_vif.MetricPolicyRcpi_5GH ~= nil then
	        	io.write("MetricPolicyRcpi_5GH=", uci_vif.MetricPolicyRcpi_5GH, "\n")
        	end
        	if uci_vif.MetricPolicyHys_5GH ~= nil then
	        	io.write("MetricPolicyHys_5GH=", uci_vif.MetricPolicyHys_5GH, "\n")
        	end
        	if uci_vif.MetricPolicyMetricsInclusion_5GH ~= nil then
	        	io.write("MetricPolicyMetricsInclusion_5GH=", uci_vif.MetricPolicyMetricsInclusion_5GH, "\n")
        	end
        	if uci_vif.MetricPolicyTrafficInclusion_5GH ~= nil then
	        	io.write("MetricPolicyTrafficInclusion_5GH=", uci_vif.MetricPolicyTrafficInclusion_5GH, "\n")
        	end
        	if uci_vif.MetricPolicyChUtilThres_5GH ~= nil then
	        	io.write("MetricPolicyChUtilThres_5GH=", uci_vif.MetricPolicyChUtilThres_5GH, "\n")
        	end
        	if uci_vif.MetricPolicyRcpi_6G ~= nil then
	        	io.write("MetricPolicyRcpi_6G=", uci_vif.MetricPolicyRcpi_6G, "\n")
        	end
        	if uci_vif.MetricPolicyHys_6G ~= nil then
	        	io.write("MetricPolicyHys_6G=", uci_vif.MetricPolicyHys_6G, "\n")
        	end
        	if uci_vif.MetricPolicyMetricsInclusion_6G ~= nil then
	        	io.write("MetricPolicyMetricsInclusion_6G=", uci_vif.MetricPolicyMetricsInclusion_6G, "\n")
        	end
        	if uci_vif.MetricPolicyTrafficInclusion_6G ~= nil then
	        	io.write("MetricPolicyTrafficInclusion_6G=", uci_vif.MetricPolicyTrafficInclusion_6G, "\n")
        	end
        	if uci_vif.MetricPolicyChUtilThres_6G ~= nil then
	        	io.write("MetricPolicyChUtilThres_6G=", uci_vif.MetricPolicyChUtilThres_6G, "\n")
        	end
        	if uci_vif.ScalingFactor ~= nil then
	        	io.write("ScalingFactor=", uci_vif.ScalingFactor, "\n")
        	end
        	if uci_vif.ChPlanningChUtilThresh_24G ~= nil then
	        	io.write("ChPlanningChUtilThresh_24G=", uci_vif.ChPlanningChUtilThresh_24G, "\n")
        	end
        	if uci_vif.ChPlanningChUtilThresh_5GL ~= nil then
	        	io.write("ChPlanningChUtilThresh_5GL=", uci_vif.ChPlanningChUtilThresh_5GL, "\n")
        	end
        	if uci_vif.ChPlanningChUtilThresh_6G ~= nil then
	        	io.write("ChPlanningChUtilThresh_6G=", uci_vif.ChPlanningChUtilThresh_6G, "\n")
        	end
        	if uci_vif.ChPlanningEDCCAThresh_24G ~= nil then
	        	io.write("ChPlanningEDCCAThresh_24G=", uci_vif.ChPlanningEDCCAThresh_24G, "\n")
        	end
        	if uci_vif.ChPlanningEDCCAThresh_5GL ~= nil then
	        	io.write("ChPlanningEDCCAThresh_5GL=", uci_vif.ChPlanningEDCCAThresh_5GL, "\n")
        	end
        	if uci_vif.ChPlanningEDCCAThresh_6G ~= nil then
	        	io.write("ChPlanningEDCCAThresh_6G=", uci_vif.ChPlanningEDCCAThresh_6G, "\n")
        	end
        	if uci_vif.ChPlanningOBSSThresh_24G ~= nil then
	        	io.write("ChPlanningOBSSThresh_24G=", uci_vif.ChPlanningOBSSThresh_24G, "\n")
        	end
        	if uci_vif.ChPlanningOBSSThresh_5GL ~= nil then
	        	io.write("ChPlanningOBSSThresh_5GL=", uci_vif.ChPlanningOBSSThresh_5GL, "\n")
        	end
        	if uci_vif.ChPlanningOBSSThresh_6G ~= nil then
	        	io.write("ChPlanningOBSSThresh_6G=", uci_vif.ChPlanningOBSSThresh_6G, "\n")
        	end
        	if uci_vif.ChPlanningR2MonitorTimeoutSecs ~= nil then
	        	io.write("ChPlanningR2MonitorTimeoutSecs=", uci_vif.ChPlanningR2MonitorTimeoutSecs, "\n")
        	end
        	if uci_vif.ChPlanningR2MonitorProhibitSecs ~= nil then
	        	io.write("ChPlanningR2MonitorProhibitSecs=", uci_vif.ChPlanningR2MonitorProhibitSecs, "\n")
        	end
        	if uci_vif.ChPlanningR2MetricReportingInterval ~= nil then
	        	io.write("ChPlanningR2MetricReportingInterval=", uci_vif.ChPlanningR2MetricReportingInterval, "\n")
        	end
        	if uci_vif.ChPlanningR2MinScoreMargin ~= nil then
	        	io.write("ChPlanningR2MinScoreMargin=", uci_vif.ChPlanningR2MinScoreMargin, "\n")
        	end
        	if uci_vif.MetricRepIntv ~= nil then
	        	io.write("MetricRepIntv=", uci_vif.MetricRepIntv, "\n")
        	end
        	if uci_vif.RSSISteeringEdge_6G_DG ~= nil then
	        	io.write("RSSISteeringEdge_6G_DG=", uci_vif.RSSISteeringEdge_6G_DG, "\n")
        	end
        	if uci_vif.RSSISteeringEdge_6G_UG ~= nil then
	        	io.write("RSSISteeringEdge_6G_UG=", uci_vif.RSSISteeringEdge_6G_UG, "\n")
        	end
        	if uci_vif.MCSCrossingThreshold_6G_DG ~= nil then
	        	io.write("MCSCrossingThreshold_6G_DG=", uci_vif.MCSCrossingThreshold_6G_DG, "\n")
        	end
        	if uci_vif.MCSCrossingThreshold_6G_UG ~= nil then
	        	io.write("MCSCrossingThreshold_6G_UG=", uci_vif.MCSCrossingThreshold_6G_UG, "\n")
        	end
        	if uci_vif.RSSICrossingThreshold_6G_DG ~= nil then
	        	io.write("RSSICrossingThreshold_6G_DG=", uci_vif.RSSICrossingThreshold_6G_DG, "\n")
        	end
        	if uci_vif.RSSICrossingThreshold_6G_UG ~= nil then
	        	io.write("RSSICrossingThreshold_6G_UG=", uci_vif.RSSICrossingThreshold_6G_UG, "\n")
        	end
		io.close()
		os.execute("cp /tmp/mapd_strng.txt /etc/mapd_strng.conf")
		os.remove(file_name)
	end

-- converting mapd_cfg file

	local file_name = "/tmp/mapd_cfg.txt"
        local file
	for _, uci_vif in pairs(uci_cfg["mapd_cfg"]) do
	        file = io.open(file_name, "w+")
		io.output(file)
		if uci_vif.mode ~= nil then
			io.write("mode=", uci_vif.mode, "\n")
		end
		if uci_vif.lan_interface ~= nil then
			io.write("lan_interface=", uci_vif.lan_interface, "\n")
		end
		if uci_vif.wan_interface ~= nil then
			io.write("wan_interface=", uci_vif.wan_interface, "\n")
		end
		if uci_vif.DeviceRole ~= nil then
			io.write("DeviceRole=", uci_vif.DeviceRole, "\n")
		end
		if uci_vif.APSteerRssiTh ~= nil then
			io.write("APSteerRssiTh=", uci_vif.APSteerRssiTh, "\n")
		end
		if uci_vif.BhPriority2G ~= nil then
			io.write("BhPriority2G=", uci_vif.BhPriority2G, "\n")
		end
		if uci_vif.BhPriority5GL ~= nil then
			io.write("BhPriority5GL=", uci_vif.BhPriority5GL, "\n")
		end
		if uci_vif.BhPriority5GH ~= nil then
			io.write("BhPriority5GH=", uci_vif.BhPriority5GH, "\n")
		end
		if uci_vif.BhPriority6G ~= nil then
			io.write("BhPriority6G=", uci_vif.BhPriority6G, "\n")
		end
		if uci_vif.ChPlanningIdleByteCount ~= nil  and uci_vif.ChPlanningIdleByteCount ~= ' ' then
			io.write("ChPlanningIdleByteCount=", uci_vif.ChPlanningIdleByteCount, "\n")
		else
	              io.write("ChPlanningIdleByteCount=", "\n")
		end
		if uci_vif.ChPlanningIdleTime ~= nil and uci_vif.ChPlanningIdleTime ~= ' ' then
			io.write("ChPlanningIdleTime=", uci_vif.ChPlanningIdleTime, "\n")
		else
	              io.write("ChPlanningIdleTime=", "\n")
		end
		if uci_vif.ChPlanningUserPreferredChannel5G ~= nil and uci_vif.ChPlanningUserPreferredChannel5G ~= ' ' then
			io.write("ChPlanningUserPreferredChannel5G=", uci_vif.ChPlanningUserPreferredChannel5G, "\n")
		else
	              io.write("ChPlanningUserPreferredChannel5G=", "\n")
		end
		if uci_vif.ChPlanningUserPreferredChannel5GH ~= nil and uci_vif.ChPlanningUserPreferredChannel5GH ~= ' ' then
			io.write("ChPlanningUserPreferredChannel5GH=", uci_vif.ChPlanningUserPreferredChannel5GH, "\n")
		else
	              io.write("ChPlanningUserPreferredChannel5GH=", "\n")
		end
		if uci_vif.ChPlanningUserPreferredChannel6G ~= nil and uci_vif.ChPlanningUserPreferredChannel6G ~= ' ' then
			io.write("ChPlanningUserPreferredChannel6G=", uci_vif.ChPlanningUserPreferredChannel6G, "\n")
		else
	              io.write("ChPlanningUserPreferredChannel6G=", "\n")
		end
		if uci_vif.ChPlanningUserPreferredChannel2G ~= nil and uci_vif.ChPlanningUserPreferredChannel2G ~= ' ' then
			io.write("ChPlanningUserPreferredChannel2G=", uci_vif.ChPlanningUserPreferredChannel2G, "\n")
		else
			io.write("ChPlanningUserPreferredChannel2G=", "\n")
		end
		if uci_vif.ChPlanningInitTimeout ~= nil then
			io.write("ChPlanningInitTimeout=", uci_vif.ChPlanningInitTimeout, "\n")
		end
		if uci_vif.NtwrkOptBootupWaitTime ~= nil then
			io.write("NtwrkOptBootupWaitTime=", uci_vif.NtwrkOptBootupWaitTime, "\n")
		end
		if uci_vif.NtwrkOptConnectWaitTime ~= nil then
			io.write("NtwrkOptConnectWaitTime=", uci_vif.NtwrkOptConnectWaitTime, "\n")
		end
		if uci_vif.NtwrkOptDisconnectWaitTime ~= nil then
			io.write("NtwrkOptDisconnectWaitTime=", uci_vif.NtwrkOptDisconnectWaitTime, "\n")
		end
		if uci_vif.NtwrkOptPeriodicity ~= nil then
			io.write("NtwrkOptPeriodicity=", uci_vif.NtwrkOptPeriodicity, "\n")
		end
		if uci_vif.NetworkOptimizationScoreMargin ~= nil then
			io.write("NetworkOptimizationScoreMargin=", uci_vif.NetworkOptimizationScoreMargin, "\n")
		end
		if uci_vif.BandSwitchTime ~= nil and uci_vif.BandSwitchTime ~= ' ' then
			io.write("BandSwitchTime=", uci_vif.BandSwitchTime, "\n")
		else
	              io.write("BandSwitchTime=", "\n")
		end
		if uci_vif.ScanThreshold2g ~= nil then
			io.write("ScanThreshold2g=", uci_vif.ScanThreshold2g, "\n")
		end
		if uci_vif.ScanThreshold5g ~= nil then
			io.write("ScanThreshold5g=", uci_vif.ScanThreshold5g, "\n")
		end
		if uci_vif.ScanThreshold6g ~= nil then
			io.write("ScanThreshold6g=", uci_vif.ScanThreshold6g, "\n")
		end
		if uci_vif.LowRSSIAPSteerEdge_RE ~= nil then
			io.write("LowRSSIAPSteerEdge_RE=", uci_vif.LowRSSIAPSteerEdge_RE, "\n")
		end
		if uci_vif.BhProfile0Valid ~= nil then
			io.write("BhProfile0Valid=", uci_vif.BhProfile0Valid, "\n")
		end
		if uci_vif.BhProfile0Ssid ~= nil then
			io.write("BhProfile0Ssid=", uci_vif.BhProfile0Ssid, "\n")
		end
		if uci_vif.BhProfile0AuthMode ~= nil then
			io.write("BhProfile0AuthMode=", uci_vif.BhProfile0AuthMode, "\n")
		end
		if uci_vif.BhProfile0EncrypType ~= nil then
			io.write("BhProfile0EncrypType=", uci_vif.BhProfile0EncrypType, "\n")
		end
		if uci_vif.BhProfile0WpaPsk ~= nil then
			io.write("BhProfile0WpaPsk=", uci_vif.BhProfile0WpaPsk, "\n")
		end
		if uci_vif.BhProfile0RaID ~= nil then
			io.write("BhProfile0RaID=", uci_vif.BhProfile0RaID, "\n")
		end
		if uci_vif.BhProfile1Ssid ~= nil then
			io.write("BhProfile1Ssid=", uci_vif.BhProfile1Ssid, "\n")
		end
		if uci_vif.BhProfile1AuthMode ~= nil then
			io.write("BhProfile1AuthMode=", uci_vif.BhProfile1AuthMode, "\n")
		end
		if uci_vif.BhProfile1EncrypType ~= nil then
			io.write("BhProfile1EncrypType=", uci_vif.BhProfile1EncrypType, "\n")
		end
		if uci_vif.BhProfile1WpaPsk ~= nil then
			io.write("BhProfile1WpaPsk=", uci_vif.BhProfile1WpaPsk, "\n")
		end
		if uci_vif.BhProfile1Valid ~= nil then
			io.write("BhProfile1Valid=", uci_vif.BhProfile1Valid, "\n")
		end
		if uci_vif.BhProfile1RaID ~= nil then
			io.write("BhProfile1RaID=", uci_vif.BhProfile1RaID, "\n")
		end
		if uci_vif.BhProfile2Ssid ~= nil then
			io.write("BhProfile2Ssid=", uci_vif.BhProfile2Ssid, "\n")
		end
		if uci_vif.BhProfile2AuthMode ~= nil then
			io.write("BhProfile2AuthMode=", uci_vif.BhProfile2AuthMode, "\n")
		end
		if uci_vif.BhProfile2EncrypType ~= nil then
			io.write("BhProfile2EncrypType=", uci_vif.BhProfile2EncrypType, "\n")
		end
		if uci_vif.BhProfile2WpaPsk ~= nil then
			io.write("BhProfile2WpaPsk=", uci_vif.BhProfile2WpaPsk, "\n")
		end
		if uci_vif.BhProfile2Valid ~= nil then
			io.write("BhProfile2Valid=", uci_vif.BhProfile2Valid, "\n")
		end
		if uci_vif.BhProfile2RaID ~= nil then
			io.write("BhProfile2RaID=", uci_vif.BhProfile2RaID, "\n")
		end
		if uci_vif.ChPlanningEnable ~= nil then
			io.write("ChPlanningEnable=", uci_vif.ChPlanningEnable, "\n")
		end
		if uci_vif.ChPlanningEnableR2 ~= nil and uci_vif.ChPlanningEnableR2 ~= ' ' then
			io.write("ChPlanningEnableR2=", uci_vif.ChPlanningEnableR2, "\n")
		else
	              io.write("ChPlanningEnableR2=", "\n")
		end
		if uci_vif.SteerEnable ~= nil then
			io.write("SteerEnable=", uci_vif.SteerEnable, "\n")
		end
		if uci_vif.NetworkOptimizationEnabled ~= nil then
			io.write("NetworkOptimizationEnabled=", uci_vif.NetworkOptimizationEnabled, "\n")
		end
		if uci_vif.AutoBHSwitching ~= nil then
			io.write("AutoBHSwitching=", uci_vif.AutoBHSwitching, "\n")
		end
		if uci_vif.DhcpCtl ~= nil then
			io.write("DhcpCtl=", uci_vif.DhcpCtl, "\n")
		end
		if uci_vif.ThirdPartyConnection ~= nil then
			io.write("ThirdPartyConnection=", uci_vif.ThirdPartyConnection, "\n")
		end
		if uci_vif.MAP_QuickChChange ~= nil then
			io.write("MAP_QuickChChange=", uci_vif.MAP_QuickChChange, "\n")
		end
		if uci_vif.bss_config_priority ~= nil then
			io.write("bss_config_priority=", uci_vif.bss_config_priority, "\n")
		end
		if uci_vif.DualBH ~= nil  and uci_vif.DualBH ~= ' ' then
			io.write("DualBH=", uci_vif.DualBH, "\n")
		else
			io.write("DualBH=", "\n")
		end
		if uci_vif.MetricRepIntv ~= nil then
			io.write("MetricRepIntv=", uci_vif.MetricRepIntv, "\n")
		end
		if uci_vif.MaxAllowedScan ~= nil and uci_vif.MaxAllowedScan ~= ' ' then
			io.write("MaxAllowedScan=", uci_vif.MaxAllowedScan, "\n")
		else
	              io.write("MaxAllowedScan=", "\n")
		end
		if uci_vif.BHSteerTimeout ~= nil then
			io.write("BHSteerTimeout=", uci_vif.BHSteerTimeout, "\n")
		end
		if uci_vif.NtwrkOptPostCACTriggerTime ~= nil then
			io.write("NtwrkOptPostCACTriggerTime=", uci_vif.NtwrkOptPostCACTriggerTime, "\n")
		end
		if uci_vif.role_detection_external ~= nil then
			io.write("role_detection_external=", uci_vif.role_detection_external, "\n")
		end
		if uci_vif.NetworkOptPrefer5Gover2G ~= nil then
			io.write("NetworkOptPrefer5Gover2G=", uci_vif.NetworkOptPrefer5Gover2G, "\n")
		end
		if uci_vif.NetworkOptPrefer5Gover2GRetryCnt ~= nil then
			io.write("NetworkOptPrefer5Gover2GRetryCnt=", uci_vif.NetworkOptPrefer5Gover2GRetryCnt, "\n")
		end
		if uci_vif.NonMAPAPEnable ~= nil then
			io.write("NonMAPAPEnable=", uci_vif.NonMAPAPEnable, "\n")
		end
		if uci_vif.CentralizedSteering ~= nil then
			io.write("CentralizedSteering=", uci_vif.CentralizedSteering, "\n")
		end
		if uci_vif.ChPlanningEnableR2withBW ~= nil and uci_vif.ChPlanningEnableR2withBW ~= ' ' then
			io.write("ChPlanningEnableR2withBW=", uci_vif.ChPlanningEnableR2withBW, "\n")
		else
	              io.write("ChPlanningEnableR2withBW=", "\n")
		end
		if uci_vif.DivergentChPlanning ~= nil then
			io.write("DivergentChPlanning=", uci_vif.DivergentChPlanning, "\n")
		end
		if uci_vif.LastMapMode ~= nil then
			io.write("LastMapMode=", uci_vif.LastMapMode, "\n")
		end
		if uci_vif.NtwrkOptDataCollectionTime ~= nil then
			io.write("NtwrkOptDataCollectionTime=", uci_vif.NtwrkOptDataCollectionTime, "\n")
		end
		if uci_vif.ChPlanningScanValidTime ~= nil then
			io.write("ChPlanningScanValidTime=", uci_vif.ChPlanningScanValidTime, "\n")
		end
		if uci_vif.NetOptUserSetPriority ~= nil then
			io.write("NetOptUserSetPriority=", uci_vif.NetOptUserSetPriority, "\n")
		end
		if uci_vif.DESerialNumber ~= nil then
			io.write("DESerialNumber=", uci_vif.DESerialNumber, "\n")
		end
		if uci_vif.DESoftwareVersion ~= nil then
			io.write("DESoftwareVersion=", uci_vif.DESoftwareVersion, "\n")
		end
		if uci_vif.DEExecutionEnv ~= nil then
			io.write("DEExecutionEnv=", uci_vif.DEExecutionEnv, "\n")
		end
		if uci_vif.DEChipsetVendor ~= nil then
			io.write("DEChipsetVendor=", uci_vif.DEChipsetVendor, "\n")
		end
		if uci_vif.DEStaConEventPath ~= nil and uci_vif.DEStaConEventPath ~= ' ' then
			io.write("DEStaConEventPath=", uci_vif.DEStaConEventPath, "\n")
		else
	              io.write("DEStaConEventPath=", "\n")
		end
		if uci_vif.SetPSCChannel_6G ~= nil then
			io.write("SetPSCChannel_6G=", uci_vif.SetPSCChannel_6G, "\n")
		end
		if uci_vif.NtwrkOptChUtilCollectionTime6G ~= nil then
			io.write("NtwrkOptChUtilCollectionTime6G=", uci_vif.NtwrkOptChUtilCollectionTime6G, "\n")
		end
		if uci_vif.NtwrkOptDataChUtilThresh6G ~= nil then
			io.write("NtwrkOptDataChUtilThresh6G=", uci_vif.NtwrkOptDataChUtilThresh6G, "\n")
		end
		if uci_vif.NtwrkOptDataChUtilEnDisable6G ~= nil then
			io.write("NtwrkOptDataChUtilEnDisable6G=", uci_vif.NtwrkOptDataChUtilEnDisable6G, "\n")
		end
		if uci_vif.NtwrkOptMldBhPriority ~= nil then
			io.write("NtwrkOptMldBhPriority=", uci_vif.NtwrkOptMldBhPriority, "\n")
		end
		if uci_vif.NtwrkOptDisableRssiVariation ~= nil then
			io.write("NtwrkOptDisableRssiVariation=", uci_vif.NtwrkOptDisableRssiVariation, "\n")
		end
	      	if uci_vif.CUOverloadTh_2G ~= nil then
	              io.write("CUOverloadTh_2G=", uci_vif.CUOverloadTh_2G, "\n")
		end
	      	if uci_vif.CUOverloadTh_5G_L ~= nil then
	              io.write("CUOverloadTh_5G_L=", uci_vif.CUOverloadTh_5G_L, "\n")
		end
	      	if uci_vif.CUOverloadTh_5G_H ~= nil then
	              io.write("CUOverloadTh_5G_H=", uci_vif.CUOverloadTh_5G_H, "\n")
		end
	      	if uci_vif.CUOverloadTh_6G ~= nil then
	              io.write("CUOverloadTh_6G=", uci_vif.CUOverloadTh_6G, "\n")
		end
	      	if uci_vif.channel_setting_5gh ~= nil then
	              io.write("channel_setting_5gh=", uci_vif.channel_setting_5gh, "\n")
		end
	      	if uci_vif.channel_setting_5gl ~= nil then
	              io.write("channel_setting_5gl=", uci_vif.channel_setting_5gl, "\n")
		end
	      	if uci_vif.channel_setting_6g ~= nil then
	              io.write("channel_setting_6g=", uci_vif.channel_setting_6g, "\n")
		end
	      	if uci_vif.client_mac~= nil then
	              io.write("client_mac=", uci_vif.client_mac, "\n")
		end
	     	if uci_vif.dpp_uri  ~= nil then
	             io.write("dpp-uri=", uci_vif.dpp_uri, "\n")
		end
	      	if uci_vif.MapMode ~= nil then
	              io.write("MapMode=", uci_vif.MapMode, "\n")
		end
	      	if uci_vif.TriBand ~= nil then
	              io.write("TriBand=", uci_vif.TriBand, "\n")
		end
	      	if uci_vif.priority ~= nil then
	              io.write("priority=", uci_vif.priority, "\n")
		end
	      	if uci_vif.index ~= nil then
	              io.write("index=", uci_vif.index, "\n")
		end
	      	if uci_vif.protocol ~= nil then
	              io.write("protocol=", uci_vif.protocol, "\n")
		end
		if uci_vif.DfsSlaveEn ~= nil then
	              io.write("DfsSlaveEn=", uci_vif.DfsSlaveEn, "\n")
		end
		if uci_vif.BH_AKM ~= nil then
			io.write("BH_AKM=", uci_vif.BH_AKM, "\n")
		end
		if uci_vif.FH_AKM ~= nil then
                        io.write("FH_AKM=", uci_vif.FH_AKM, "\n")
                end
		if uci_vif.BlaAlgoEnable ~= nil then
	              io.write("BlaAlgoEnable=", uci_vif.BlaAlgoEnable, "\n")
		end
		if uci_vif.BWSync ~= nil then
	              io.write("BWSync=", uci_vif.BWSync, "\n")
		end
		if uci_vif.NopSync ~= nil then
	              io.write("NopSync=", uci_vif.NopSync, "\n")
		end
		if uci_vif.DFSBW80Enable ~= nil then
		      io.write("DFSBW80Enable=", uci_vif.DFSBW80Enable, "\n")
		end
		if uci_vif.COSRAlgoEnable ~= nil then
                      io.write("COSRAlgoEnable=", uci_vif.COSRAlgoEnable, "\n")
                end
		if uci_vif.ChPlanTxPowerEn ~= nil then
                      io.write("ChPlanTxPowerEn=", uci_vif.ChPlanTxPowerEn, "\n")
                end
		if uci_vif.log_option ~= nil then
	              io.write("log_option=", uci_vif.log_option, "\n")
		end
		if uci_vif.StopBcnSupport ~= nil then
	              io.write("StopBcnSupport=", uci_vif.StopBcnSupport, "\n")
		end
		if uci_vif.TSF_Enable ~= nil then
	              io.write("TSF_Enable=", uci_vif.TSF_Enable, "\n")
		end
		if uci_vif.TSF_Band ~= nil then
	              io.write("TSF_Band=", uci_vif.TSF_Band, "\n")
		end

		io.close()
		os.execute("cp /tmp/mapd_cfg.txt /etc/map/mapd_cfg")
		os.remove(file_name)
	end

--converting mapd_user file

	local file_name = "/etc/map/mapd_user.cfg"
        local file
--delete all parameter to avoid repeat
		os.execute("sed -i '/mode=/d' "..file_name)
		os.execute("sed -i '/lan_interface=/d' "..file_name)
		os.execute("sed -i '/wan_interface=/d' "..file_name)
		os.execute("sed -i '/DeviceRole=/d' "..file_name)
		os.execute("sed -i '/APSteerRssiTh=/d' "..file_name)
		os.execute("sed -i '/BhPriority2G=/d' "..file_name)
		os.execute("sed -i '/BhPriority5GL=/d' "..file_name)
		os.execute("sed -i '/BhPriority5GH=/d' "..file_name)
		os.execute("sed -i '/BhPriority6G=/d' "..file_name)
		os.execute("sed -i '/ChPlanningIdleByteCount=/d' "..file_name)
		os.execute("sed -i '/ChPlanningIdleTime=/d' "..file_name)
		os.execute("sed -i '/ChPlanningUserPreferredChannel5G=/d' "..file_name)
		os.execute("sed -i '/ChPlanningUserPreferredChannel5GH=/d' "..file_name)
		os.execute("sed -i '/ChPlanningUserPreferredChannel2G=/d' "..file_name)
		os.execute("sed -i '/ChPlanningUserPreferredChannel6G=/d' "..file_name)
		os.execute("sed -i '/ChPlanningInitTimeout=/d' "..file_name)
		os.execute("sed -i '/NtwrkOptBootupWaitTime=/d' "..file_name)
		os.execute("sed -i '/NtwrkOptConnectWaitTime=/d' "..file_name)
		os.execute("sed -i '/NtwrkOptDisconnectWaitTime=/d' "..file_name)
		os.execute("sed -i '/NtwrkOptPeriodicity=/d' "..file_name)
		os.execute("sed -i '/NetworkOptimizationScoreMargin=/d' "..file_name)
		os.execute("sed -i '/BandSwitchTime=/d' "..file_name)
		os.execute("sed -i '/ScanThreshold2g=/d' "..file_name)
		os.execute("sed -i '/ScanThreshold2g=/d' "..file_name)
		os.execute("sed -i '/ScanThreshold5g=/d' "..file_name)
		os.execute("sed -i '/ScanThreshold6g=/d' "..file_name)
		os.execute("sed -i '/LowRSSIAPSteerEdge_RE=/d' "..file_name)
		os.execute("sed -i '/ChPlanningEnable=/d' "..file_name)
		os.execute("sed -i '/ChPlanningEnableR2=/d' "..file_name)
		os.execute("sed -i '/SteerEnable=/d' "..file_name)
		os.execute("sed -i '/NetworkOptimizationEnabled=/d' "..file_name)
		os.execute("sed -i '/AutoBHSwitching=/d' "..file_name)
		os.execute("sed -i '/DhcpCtl=/d' "..file_name)
		os.execute("sed -i '/ThirdPartyConnection=/d' "..file_name)
		os.execute("sed -i '/MAP_QuickChChange=/d' "..file_name)
		os.execute("sed -i '/bss_config_priority=/d' "..file_name)
		os.execute("sed -i '/DualBH=/d' "..file_name)
		os.execute("sed -i '/MetricRepIntv=/d' "..file_name)
		os.execute("sed -i '/MaxAllowedScan=/d' "..file_name)
		os.execute("sed -i '/BHSteerTimeout=/d' "..file_name)
		os.execute("sed -i '/NtwrkOptPostCACTriggerTime=/d' "..file_name)
		os.execute("sed -i '/role_detection_external=/d' "..file_name)
		os.execute("sed -i '/NetworkOptPrefer5Gover2G=/d' "..file_name)
		os.execute("sed -i '/NetworkOptPrefer5Gover2GRetryCnt=/d' "..file_name)
		os.execute("sed -i '/NonMAPAPEnable=/d' "..file_name)
		os.execute("sed -i '/CentralizedSteering=/d' "..file_name)
		os.execute("sed -i '/ChPlanningEnableR2withBW=/d' "..file_name)
		os.execute("sed -i '/DivergentChPlanning=/d' "..file_name)
		os.execute("sed -i '/LastMapMode=/d' "..file_name)
		os.execute("sed -i '/NtwrkOptDataCollectionTime=/d' "..file_name)
		os.execute("sed -i '/ChPlanningScanValidTime=/d' "..file_name)
		os.execute("sed -i '/NetOptUserSetPriority=/d' "..file_name)
		os.execute("sed -i '/DESerialNumber=/d' "..file_name)
		os.execute("sed -i '/DESoftwareVersion=/d' "..file_name)
		os.execute("sed -i '/DEExecutionEnv=/d' "..file_name)
		os.execute("sed -i '/DEChipsetVendor=/d' "..file_name)
		os.execute("sed -i '/DEStaConEventPath=/d' "..file_name)
		os.execute("sed -i '/SetPSCChannel_6G=/d' "..file_name)
		os.execute("sed -i '/NtwrkOptChUtilCollectionTime6G=/d' "..file_name)
		os.execute("sed -i '/NtwrkOptDataChUtilThresh6G=/d' "..file_name)
		os.execute("sed -i '/NtwrkOptDataChUtilEnDisable6G=/d' "..file_name)
		os.execute("sed -i '/CUOverloadTh_2G=/d' "..file_name)
		os.execute("sed -i '/CUOverloadTh_5G_L=/d' "..file_name)
		os.execute("sed -i '/CUOverloadTh_5G_H=/d' "..file_name)
		os.execute("sed -i '/CUOverloadTh_6G=/d' "..file_name)
		os.execute("sed -i '/channel_setting_5gh=/d' "..file_name)
		os.execute("sed -i '/channel_setting_5gl=/d' "..file_name)
		os.execute("sed -i '/channel_setting_6g=/d' "..file_name)
		os.execute("sed -i '/client_mac=/d' "..file_name)
		os.execute("sed -i '/dpp-uri=/d' "..file_name)
		os.execute("sed -i '/MapMode=/d' "..file_name)
		os.execute("sed -i '/TriBand=/d' "..file_name)
		os.execute("sed -i '/priority=/d' "..file_name)
		os.execute("sed -i '/index=/d' "..file_name)
		os.execute("sed -i '/protocol=/d' "..file_name)
		os.execute("sed -i '/BlaAlgoEnable=/d' "..file_name)
		os.execute("sed -i '/BWSync=/d' "..file_name)
		os.execute("sed -i '/NopSync=/d' "..file_name)
		os.execute("sed -i '/log_option=/d' "..file_name)
		os.execute("sed -i '/DFSBW80Enable=/d' "..file_name)
		os.execute("sed -i '/COSRAlgoEnable=/d' "..file_name)
		os.execute("sed -i '/ChPlanTxPowerEn=/d' "..file_name)
		os.execute("sed -i '/StopBcnSupport=/d' "..file_name)
		os.execute("sed -i '/TSF_Enabe=/d' "..file_name)
		os.execute("sed -i '/TSF_Band=/d' "..file_name)

--
	for _, uci_vif in pairs(uci_cfg["mapd_user"]) do
	        file = io.open(file_name, "a+")
		io.output(file)
		if uci_vif.mode ~= nil then
			io.write("mode=", uci_vif.mode, "\n")
		end
		if uci_vif.lan_interface ~= nil then
			io.write("lan_interface=", uci_vif.lan_interface, "\n")
		end
		if uci_vif.wan_interface ~= nil then
			io.write("wan_interface=", uci_vif.wan_interface, "\n")
		end
		if uci_vif.DeviceRole ~= nil then
			io.write("DeviceRole=", uci_vif.DeviceRole, "\n")
		end
		if uci_vif.APSteerRssiTh ~= nil then
			io.write("APSteerRssiTh=", uci_vif.APSteerRssiTh, "\n")
		end
		if uci_vif.BhPriority2G ~= nil then
			io.write("BhPriority2G=", uci_vif.BhPriority2G, "\n")
		end
		if uci_vif.BhPriority5GL ~= nil then
			io.write("BhPriority5GL=", uci_vif.BhPriority5GL, "\n")
		end
		if uci_vif.BhPriority5GH ~= nil then
			io.write("BhPriority5GH=", uci_vif.BhPriority5GH, "\n")
		end
		if uci_vif.BhPriority6G ~= nil then
			io.write("BhPriority6G=", uci_vif.BhPriority6G, "\n")
		end
		if uci_vif.ChPlanningIdleByteCount ~= nil and uci_vif.ChPlanningIdleByteCount ~= ' ' then
			io.write("ChPlanningIdleByteCount=", uci_vif.ChPlanningIdleByteCount, "\n")
		end
		if uci_vif.ChPlanningIdleTime ~= nil and uci_vif.ChPlanningIdleTime ~= ' ' then
			io.write("ChPlanningIdleTime=", uci_vif.ChPlanningIdleTime, "\n")
		end
		if uci_vif.ChPlanningUserPreferredChannel5G ~= nil and uci_vif.ChPlanningUserPreferredChannel5G ~= ' ' then
			io.write("ChPlanningUserPreferredChannel5G=", uci_vif.ChPlanningUserPreferredChannel5G, "\n")
		end
		if uci_vif.ChPlanningEnableR2 ~= nil and uci_vif.ChPlanningEnableR2 ~= ' ' then
			io.write("ChPlanningEnableR2=", uci_vif.ChPlanningEnableR2, "\n")
		end
		if uci_vif.ChPlanningUserPreferredChannel5GH ~= nil and uci_vif.ChPlanningUserPreferredChannel5GH ~= ' ' then
			io.write("ChPlanningUserPreferredChannel5GH=", uci_vif.ChPlanningUserPreferredChannel5GH, "\n")
		end
		if uci_vif.ChPlanningUserPreferredChannel6G ~= nil and uci_vif.ChPlanningUserPreferredChannel6G ~= ' ' then
			io.write("ChPlanningUserPreferredChannel6G=", uci_vif.ChPlanningUserPreferredChannel6G, "\n")
		end
		if uci_vif.ChPlanningUserPreferredChannel2G ~= nil and uci_vif.ChPlanningUserPreferredChannel2G ~= ' ' then
			io.write("ChPlanningUserPreferredChannel2G=", uci_vif.ChPlanningUserPreferredChannel2G, "\n")
		end
		if uci_vif.ChPlanningInitTimeout ~= nil then
			io.write("ChPlanningInitTimeout=", uci_vif.ChPlanningInitTimeout, "\n")
		end
		if uci_vif.NtwrkOptBootupWaitTime ~= nil then
			io.write("NtwrkOptBootupWaitTime=", uci_vif.NtwrkOptBootupWaitTime, "\n")
		end
		if uci_vif.NtwrkOptConnectWaitTime ~= nil then
			io.write("NtwrkOptConnectWaitTime=", uci_vif.NtwrkOptConnectWaitTime, "\n")
		end
		if uci_vif.NtwrkOptDisconnectWaitTime ~= nil then
			io.write("NtwrkOptDisconnectWaitTime=", uci_vif.NtwrkOptDisconnectWaitTime, "\n")
		end
		if uci_vif.NtwrkOptPeriodicity ~= nil then
			io.write("NtwrkOptPeriodicity=", uci_vif.NtwrkOptPeriodicity, "\n")
		end
		if uci_vif.NetworkOptimizationScoreMargin ~= nil then
			io.write("NetworkOptimizationScoreMargin=", uci_vif.NetworkOptimizationScoreMargin, "\n")
		end
		if uci_vif.BandSwitchTime ~= nil or uci_vif.BandSwitchTime == '' then
			io.write("BandSwitchTime=", uci_vif.BandSwitchTime, "\n")
		end
		if uci_vif.ScanThreshold2g ~= nil then
			io.write("ScanThreshold2g=", uci_vif.ScanThreshold2g, "\n")
		end
		if uci_vif.ScanThreshold5g ~= nil then
			io.write("ScanThreshold5g=", uci_vif.ScanThreshold5g, "\n")
		end
		if uci_vif.ScanThreshold6g ~= nil then
			io.write("ScanThreshold6g=", uci_vif.ScanThreshold6g, "\n")
		end
		if uci_vif.LowRSSIAPSteerEdge_RE ~= nil then
			io.write("LowRSSIAPSteerEdge_RE=", uci_vif.LowRSSIAPSteerEdge_RE, "\n")
		end
		if uci_vif.ChPlanningEnable ~= nil then
			io.write("ChPlanningEnable=", uci_vif.ChPlanningEnable, "\n")
		end
		if uci_vif.SteerEnable ~= nil then
			io.write("SteerEnable=", uci_vif.SteerEnable, "\n")
		end
		if uci_vif.NetworkOptimizationEnabled ~= nil then
			io.write("NetworkOptimizationEnabled=", uci_vif.NetworkOptimizationEnabled, "\n")
		end
		if uci_vif.AutoBHSwitching ~= nil then
			io.write("AutoBHSwitching=", uci_vif.AutoBHSwitching, "\n")
		end
		if uci_vif.DhcpCtl ~= nil then
			io.write("DhcpCtl=", uci_vif.DhcpCtl, "\n")
		end
		if uci_vif.ThirdPartyConnection ~= nil then
			io.write("ThirdPartyConnection=", uci_vif.ThirdPartyConnection, "\n")
		end
		if uci_vif.MAP_QuickChChange ~= nil then
			io.write("MAP_QuickChChange=", uci_vif.MAP_QuickChChange, "\n")
		end
		if uci_vif.bss_config_priority ~= nil then
			io.write("bss_config_priority=", uci_vif.bss_config_priority, "\n")
		end
		if uci_vif.DualBH ~= nil and uci_vif.DualBH ~= ' ' then
			io.write("DualBH=", uci_vif.DualBH, "\n")
		end
		if uci_vif.MetricRepIntv ~= nil then
			io.write("MetricRepIntv=", uci_vif.MetricRepIntv, "\n")
		end
		if uci_vif.MaxAllowedScan ~= nil and uci_vif.MaxAllowedScan ~= ' ' then
			io.write("MaxAllowedScan=", uci_vif.MaxAllowedScan, "\n")
		end
		if uci_vif.BHSteerTimeout ~= nil then
			io.write("BHSteerTimeout=", uci_vif.BHSteerTimeout, "\n")
		end
		if uci_vif.NtwrkOptPostCACTriggerTime ~= nil then
			io.write("NtwrkOptPostCACTriggerTime=", uci_vif.NtwrkOptPostCACTriggerTime, "\n")
		end
		if uci_vif.role_detection_external ~= nil then
			io.write("role_detection_external=", uci_vif.role_detection_external, "\n")
		end
		if uci_vif.NetworkOptPrefer5Gover2G ~= nil then
			io.write("NetworkOptPrefer5Gover2G=", uci_vif.NetworkOptPrefer5Gover2G, "\n")
		end
		if uci_vif.NetworkOptPrefer5Gover2GRetryCnt ~= nil then
			io.write("NetworkOptPrefer5Gover2GRetryCnt=", uci_vif.NetworkOptPrefer5Gover2GRetryCnt, "\n")
		end
		if uci_vif.NonMAPAPEnable ~= nil then
			io.write("NonMAPAPEnable=", uci_vif.NonMAPAPEnable, "\n")
		end
		if uci_vif.CentralizedSteering ~= nil then
			io.write("CentralizedSteering=", uci_vif.CentralizedSteering, "\n")
		end
		if uci_vif.ChPlanningEnableR2withBW ~= nil and uci_vif.ChPlanningEnableR2withBW ~= ' ' then
			io.write("ChPlanningEnableR2withBW=", uci_vif.ChPlanningEnableR2withBW, "\n")
		end
		if uci_vif.DivergentChPlanning ~= nil then
			io.write("DivergentChPlanning=", uci_vif.DivergentChPlanning, "\n")
		end
		if uci_vif.LastMapMode ~= nil then
			io.write("LastMapMode=", uci_vif.LastMapMode, "\n")
		end
		if uci_vif.NtwrkOptDataCollectionTime ~= nil then
			io.write("NtwrkOptDataCollectionTime=", uci_vif.NtwrkOptDataCollectionTime, "\n")
		end
		if uci_vif.ChPlanningScanValidTime ~= nil then
			io.write("ChPlanningScanValidTime=", uci_vif.ChPlanningScanValidTime, "\n")
		end
		if uci_vif.NetOptUserSetPriority ~= nil then
			io.write("NetOptUserSetPriority=", uci_vif.NetOptUserSetPriority, "\n")
		end
		if uci_vif.DESerialNumber ~= nil then
			io.write("DESerialNumber=", uci_vif.DESerialNumber, "\n")
		end
		if uci_vif.DESoftwareVersion ~= nil then
			io.write("DESoftwareVersion=", uci_vif.DESoftwareVersion, "\n")
		end
		if uci_vif.DEExecutionEnv ~= nil then
			io.write("DEExecutionEnv=", uci_vif.DEExecutionEnv, "\n")
		end
		if uci_vif.DEChipsetVendor ~= nil then
			io.write("DEChipsetVendor=", uci_vif.DEChipsetVendor, "\n")
		end
		if uci_vif.DEStaConEventPath ~= nil and uci_vif.DEStaConEventPath ~= ' ' then
			io.write("DEStaConEventPath=", uci_vif.DEStaConEventPath, "\n")
		end
		if uci_vif.SetPSCChannel_6G ~= nil then
			io.write("SetPSCChannel_6G=", uci_vif.SetPSCChannel_6G, "\n")
		end
		if uci_vif.NtwrkOptChUtilCollectionTime6G ~= nil then
			io.write("NtwrkOptChUtilCollectionTime6G=", uci_vif.NtwrkOptChUtilCollectionTime6G, "\n")
		end
		if uci_vif.NtwrkOptDataChUtilThresh6G ~= nil then
			io.write("NtwrkOptDataChUtilThresh6G=", uci_vif.NtwrkOptDataChUtilThresh6G, "\n")
		end
		if uci_vif.NtwrkOptDataChUtilEnDisable6G ~= nil then
			io.write("NtwrkOptDataChUtilEnDisable6G=", uci_vif.NtwrkOptDataChUtilEnDisable6G, "\n")
		end
	      	if uci_vif.CUOverloadTh_2G ~= nil then
	              io.write("CUOverloadTh_2G=", uci_vif.CUOverloadTh_2G, "\n")
		end
	      	if uci_vif.CUOverloadTh_5G_L ~= nil then
	              io.write("CUOverloadTh_5G_L=", uci_vif.CUOverloadTh_5G_L, "\n")
		end
	      	if uci_vif.CUOverloadTh_5G_H ~= nil then
	              io.write("CUOverloadTh_5G_H=", uci_vif.CUOverloadTh_5G_H, "\n")
		end
	      	if uci_vif.CUOverloadTh_6G ~= nil then
	              io.write("CUOverloadTh_6G=", uci_vif.CUOverloadTh_6G, "\n")
		end
	      	if uci_vif.channel_setting_5gh ~= nil then
	              io.write("channel_setting_5gh=", uci_vif.channel_setting_5gh, "\n")
		end
	      	if uci_vif.channel_setting_5gl ~= nil then
	              io.write("channel_setting_5gl=", uci_vif.channel_setting_5gl, "\n")
		end
	      	if uci_vif.channel_setting_6g ~= nil then
	              io.write("channel_setting_6g=", uci_vif.channel_setting_6g, "\n")
		end
	      	if uci_vif.client_mac~= nil then
	              io.write("client_mac=", uci_vif.client_mac, "\n")
		end
	     	if uci_vif.dpp_uri  ~= nil then
	             io.write("dpp-uri=", uci_vif.dpp_uri, "\n")
		end
	      	if uci_vif.MapMode ~= nil then
	              io.write("MapMode=", uci_vif.MapMode, "\n")
		end
	      	if uci_vif.TriBand ~= nil then
	              io.write("TriBand=", uci_vif.TriBand, "\n")
		end
	      	if uci_vif.priority ~= nil then
	              io.write("priority=", uci_vif.priority, "\n")
		end
	      	if uci_vif.index ~= nil then
	              io.write("index=", uci_vif.index, "\n")
		end
	      	if uci_vif.protocol ~= nil then
	              io.write("protocol=", uci_vif.protocol, "\n")
		end
		if uci_vif.BlaAlgoEnable ~= nil then
	              io.write("BlaAlgoEnable=", uci_vif.BlaAlgoEnable, "\n")
		end
		if uci_vif.BWSync ~= nil then
	              io.write("BWSync=", uci_vif.BWSync, "\n")
		end
		if uci_vif.NopSync ~= nil then
	              io.write("NopSync=", uci_vif.NopSync, "\n")
		end
		if uci_vif.DFSBW80Enable ~= nil then
	              io.write("DFSBW80Enable=", uci_vif.DFSBW80Enable, "\n")
		end
		if uci_vif.COSRAlgoEnable ~= nil then
                      io.write("COSRAlgoEnable=", uci_vif.COSRAlgoEnable, "\n")
                end
		if uci_vif.ChPlanTxPowerEn ~= nil then
                      io.write("ChPlanTxPowerEn=", uci_vif.ChPlanTxPowerEn, "\n")
                end
		if uci_vif.log_option ~= nil then
	              io.write("log_option=", uci_vif.log_option, "\n")
		end
		if uci_vif.StopBcnSupport ~= nil then
	              io.write("StopBcnSupport=", uci_vif.StopBcnSupport, "\n")
		end
		if uci_vif.TSF_Enable ~= nil then
	              io.write("TSF_Enable=", uci_vif.TSF_Enable, "\n")
		end
		if uci_vif.TSF_Band ~= nil then
	              io.write("TSF_Band=", uci_vif.TSF_Band, "\n")
		end
		io.close()
	end

--converting wts file

	local file_name = "/tmp/wts_bss_info_config"
	local fd = io.open(file_name, "w")
	local file
	local index = 1
	local ssid
	local pwd
	fd:write('#ucc_bss_info\n')
    for _, uci_vif in pairs(uci_cfg["iface"]) do
        ssid = uci2map.__trim(uci2map.read_pipe("uci get mapd." ..index..".ssid"))
        local tmpSsid = ssid:gsub("\\", "\\\\")
        local tmpSsid = tmpSsid:gsub("%s", "\\ ")
        pwd = uci2map.__trim(uci2map.read_pipe("uci get mapd." ..index..".PSK"))
        local tmpPwd = pwd:gsub("\\", "\\\\")
        local tmpPwd = tmpPwd:gsub("%s", "\\ ")
        fd:write(
            index..','..uci_vif.mac..' '..
            uci_vif.radio ..' '..
            tmpSsid..' '..
            uci_vif.authmode..' '..
            uci_vif.EncryptType..' '..
            tmpPwd..' '..
            uci_vif.bhbss..' '..
            uci_vif.fhbss..' hidden-' ..
            uci_vif.hidden ..' '..
            uci_vif.vlan..' '..
            uci_vif.pvid..' '..
            uci_vif.pcp..' mld_groupID '..
	    uci_vif.mld_groupID ..'\n')
        index = index + 1
    end
	io.close(fd)
	os.execute("cp /tmp/wts_bss_info_config /etc/map/wts_bss_info_config")
	os.remove(file_name)
end

function uci_apply_1905d_cfg()
        local file_name = "/etc/map/1905d.cfg"
        local file
	local uciCfgfile = "/etc/config/1905d_cfg"
        local uci_cfg
        uci_cfg = uci_load(uciCfgfile)
        for _, uci_vif in pairs(uci_cfg["iface"]) do
                os.execute("sed -i '/map_ver=/d' "..file_name)
                file = io.open(file_name, "a+")
                io.output(file)
                if uci_vif.map_ver ~= nil then
                      io.write("map_ver=", uci_vif.map_ver, "\n")
                end
                io.close()
        end
end

function uci_apply_bh_sta_cfg()
	--updating wts_bsta_mlo_config

	local uci_cfg
	uci_cfg = uci_load(uciCfgfile)

	local file_name = "/tmp/wts_bsta_mlo_config"
	local fd = io.open(file_name, "w")
	local index = 1
	local almac
	local mlo_links
	local ruid_or_band
	fd:write('#ucc_bhsta_info\n')

	if uci_cfg["bh_sta"] then
			for idx, val in pairs(uci_cfg["bh_sta"]) do
					almac = uci2map.__trim(uci2map.read_pipe("uci get mapd.stamld" ..index..".almac"))
					mlo_links = uci2map.__trim(uci2map.read_pipe("uci get mapd.stamld" ..index..".mlo_links"))
					ruid_or_band = uci2map.__trim(uci2map.read_pipe("uci get mapd.stamld" ..index..".ruid_or_band"))
					fd:write(
					index..','..val.almac..' '..
					val.mlo_links ..' '..
					val.ruid_or_band..'\n')
					index = index + 1
			end
	end
	io.close(fd)
	os.execute("cp /tmp/wts_bsta_mlo_config /etc/map/wts_bsta_mlo_config")
	os.remove(file_name)
end

function uci_apply_wsc_m8_cfg()
	--updating bsta_wsc_reconfig

	local uci_cfg
	uci_cfg = uci_load(uciCfgfile)

	local file_name = "/tmp/bsta_wsc_reconfig"
	local fd = io.open(file_name, "w")
	local index = 1
	local almac
	local ssid
	local authmode
	local encryption
	local key
	fd:write('#bsta_wsc_reconfig\n')

	if uci_cfg["wsc_m8"] then
			for idx, val in pairs(uci_cfg["wsc_m8"]) do
					almac = uci2map.__trim(uci2map.read_pipe("uci get mapd.conf" ..index..".almac"))
					ssid = uci2map.__trim(uci2map.read_pipe("uci get mapd.conf" ..index..".ssid"))
					authmode = uci2map.__trim(uci2map.read_pipe("uci get mapd.conf" ..index..".authmode"))
					encryption = uci2map.__trim(uci2map.read_pipe("uci get mapd.conf" ..index..".encryption"))
					key = uci2map.__trim(uci2map.read_pipe("uci get mapd.conf" ..index..".key"))
					fd:write(
					index..','..val.almac..' '..
					val.ssid ..' '..
					val.authmode..' '..
					val.encryption..' '..
					val.key..'\n')
					index = index + 1
			end
	end
	io.close(fd)
	os.execute("cp /tmp/bsta_wsc_reconfig /etc/map/bsta_wsc_reconfig")
	os.remove(file_name)
end

uci_apply_mapd_configuration()
uci_apply_1905d_cfg()
uci_apply_bh_sta_cfg()
--uci_apply_wsc_m8_cfg()
