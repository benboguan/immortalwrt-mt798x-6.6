'use strict';
'require view';
'require form';
'require uci';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('wireless'),
			uci.load('mapd'),
			uci.load('1905d_cfg')
		]);
	},

	render: function() {
		var maps = [];

		/* ================================================================ */
		/* Map 1: Driver / Radio 配置（写入 /etc/config/wireless）           */
		/* ================================================================ */
		var wm = new form.Map('wireless', _('Driver Configuration'),
			_('Driver MAP parameters are stored in /etc/config/wireless.'));

		var wifi_devices = uci.sections('wireless', 'wifi-device') || [];

		if (wifi_devices.length === 0) {
			var s = wm.section(form.NamedSection, 'dummy', 'wifi-device',
				_('No wireless device'));
			s.addremove = false;
			var o = s.option(form.DummyValue, '_none', _('No wireless device'));
			o.rawhtml = true;
			o.cfgvalue = function() {
				return _('No wifi-device section found in /etc/config/wireless.');
			};
		} else {
			wifi_devices.forEach(function(dev) {
				var radio = dev['.name'] || dev.name;
				if (!radio)
					return;

				var title = _('Driver / Radio: %s').format(radio);
				var s = wm.section(form.NamedSection, radio, 'wifi-device', title);
				s.addremove = false;

				/* MapMode */
				var o = s.option(form.ListValue, 'map_mode', _('MAP driver mode'));
				o.value('0', _('Disabled'));
				o.value('1', _('MAP Turnkey'));
				o.value('2', _('BS 2.0'));
				o.value('3', _('API Mode'));
				o.value('4', _('Cert'));
				o.default = '1';
				o.rmempty = false;
				o.description = _('Driver MapMode. 1 = EasyMesh/MAP Turnkey, 2 = Standalone Band Steering (BS 2.0), 3 = API Mode, 4 = Cert. Requires driver reload / reboot.');

				/* SRMeshUlMode */
				o = s.option(form.ListValue, 'SRMeshUlMode', _('SR Mesh Uplink Mode'));
				o.value('0', _('Disabled'));
				o.value('1', _('Enabled'));
				o.default = '0';
				o.rmempty = false;
				o.description = _('Only used when CFG_SUPPORT_FALCON_SR is enabled.');

				/* MapStatsDisable */
				o = s.option(form.ListValue, 'MapStatsDisable', _('MAP statistics'));
				o.value('0', _('Enabled'));
				o.value('1', _('Disabled'));
				o.default = '0';
				o.rmempty = false;
				o.description = _('Only used when EM_PLUS_SUPPORT is enabled.');

				/* MapAccept3Addr */
				o = s.option(form.ListValue, 'MapAccept3Addr', _('Accept 3-address MAP frames'));
				o.value('0', _('Disabled'));
				o.value('1', _('Enabled'));
				o.default = '0';
				o.rmempty = false;
				o.description = _('Only used when CONFIG_MAP_3ADDR_SUPPORT is enabled.');

				/* MapBalance */
				o = s.option(form.ListValue, 'MapBalance', _('MAP load balance'));
				o.value('0', _('Disabled'));
				o.value('1', _('Enabled'));
				o.default = '0';
				o.rmempty = false;
				o.description = _('Driver MAP balance flag.');

				/* SREnable */
				o = s.option(form.ListValue, 'SREnable', _('Spatial Reuse'));
				o.value('0', _('Disabled'));
				o.value('1', _('Enabled'));
				o.default = '0';
				o.rmempty = false;
				o.description = _('Enable Wi-Fi 6 Spatial Reuse. 0 = no SR, 1 = enable SR. Currently verified only on AX4200 Panther platform.');

				/* SRMode */
				o = s.option(form.ListValue, 'SRMode', _('Spatial Reuse mode'));
				o.value('0', _('Single AP Mode'));
				o.value('1', _('Mesh Mode'));
				o.default = '1';
				o.rmempty = false;
				o.description = _('0 = SR in Single AP Mode, 1 = SR in Mesh Mode.');

				/* SRDPDEnable */
				o = s.option(form.ListValue, 'SRDPDEnable', _('Dynamic OBSS PD'));
				o.value('0', _('Disabled'));
				o.value('1', _('Enabled'));
				o.default = '1';
				o.rmempty = false;
				o.description = _('Enable Dynamic OBSS PD to increase SR reuse range stronger than the ED threshold.');
			});
		}

		maps.push(wm);

		/* ================================================================ */
		/* Map 2: EasyMesh 主配置（写入 /etc/config/mapd）                    */
		/* 三个分组用同一个 NamedSection + tab 显示，避免保存时触发 delete    */
		/* ================================================================ */
		var m = new form.Map('mapd', _('EasyMesh'),
			_('MediaTek MAP Turnkey. The device role, channel planning and client ' +
			  'steering settings below are stored in /etc/config/mapd.'));

		var s = m.section(form.NamedSection, 'mapd_cfg', 'mapd_cfg');
		s.addremove = false;

		s.tab('general', _('General'));
		s.tab('backhaul', _('Backhaul'));
		s.tab('advanced', _('Advanced'));

		/* ---------- General ---------- */
		var o = s.taboption('general', form.Flag, 'enable', _('Enable EasyMesh'));
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('general', form.ListValue, 'mode', _('Work Mode'));
		o.value('0', _('Router'));
		o.value('1', _('Bridge'));
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('general', form.ListValue, 'DeviceRole', _('Device role'));
		o.value('0', _('Auto'));
		o.value('1', _('Controller'));
		o.value('2', _('Agent'));
		o.default = '2';
		o.rmempty = false;
		o.description = _('Changing the role requires a restart of the EasyMesh daemons.');

		o = s.taboption('general', form.ListValue, 'map_ver', _('MAP version'));
		o.value('R1', 'R1');
		o.value('R2', 'R2');
		o.value('R3', 'R3');
		o.value('R4', 'R4');
		o.value('R5', 'R5');
		o.default = 'R3';
		o.cfgvalue = function() {
			return uci.get('1905d_cfg', 'map', 'map_ver') || 'R3';
		};
		o.write = function(section_id, value) {
			uci.set('1905d_cfg', 'map', 'map_ver', value);
		};
		o.remove = function() {
			uci.unset('1905d_cfg', 'map', 'map_ver');
		};
		o.description = _('All devices in the mesh must use the same MAP version. ' +
			'Use R3 for MAP R4 capable devices, DPP onboarding requires R3.');

		o = s.taboption('general', form.Value, 'APSteerRssiTh', _('AP steering RSSI threshold'),
			_('Minimum RSSI (dBm) below which the controller considers steering a client.'));
		o.datatype = 'range(-100,-20)';
		o.placeholder = '-54';
		o.modalonly = false;

		o = s.taboption('general', form.Flag, 'SteerEnable', _('Client steering'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('Centralized steering of clients between the mesh devices.');

		o = s.taboption('general', form.Value, 'CUOverloadTh_2G', _('2.4 GHz channel load limit'),
			_('Channel utilisation (%) above which the band counts as overloaded.'));
		o.datatype = 'range(1,100)';
		o.placeholder = '70';

		o = s.taboption('general', form.Value, 'CUOverloadTh_5G_L', _('5 GHz low channel load limit'));
		o.datatype = 'range(1,100)';
		o.placeholder = '80';

		o = s.taboption('general', form.Value, 'CUOverloadTh_5G_H', _('5 GHz high channel load limit'));
		o.datatype = 'range(1,100)';
		o.placeholder = '80';

		/* ---------- Backhaul ---------- */
		o = s.taboption('backhaul', form.ListValue, 'BhPriority2G', _('2.4 GHz backhaul priority'));
		o.value('0', _('Never'));
		o.value('1', _('Highest'));
		o.value('2', _('Medium'));
		o.value('3', _('Lowest'));
		o.default = '3';
		o.rmempty = false;

		o = s.taboption('backhaul', form.ListValue, 'BhPriority5GL', _('5 GHz low backhaul priority'));
		o.value('0', _('Never'));
		o.value('1', _('Highest'));
		o.value('2', _('Medium'));
		o.value('3', _('Lowest'));
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('backhaul', form.ListValue, 'BhPriority5GH', _('5 GHz high backhaul priority'));
		o.value('0', _('Never'));
		o.value('1', _('Highest'));
		o.value('2', _('Medium'));
		o.value('3', _('Lowest'));
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('backhaul', form.ListValue, 'BhPriority6G', _('6 GHz backhaul priority'));
		o.value('0', _('Never'));
		o.value('1', _('Highest'));
		o.value('2', _('Medium'));
		o.value('3', _('Lowest'));
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('backhaul', form.Flag, 'AutoBHSwitching', _('Automatic Ethernet / Wi-Fi backhaul switching'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('Agents fall back to a wireless backhaul when the Ethernet link goes down.');

		/* ---------- Advanced ---------- */
		o = s.taboption('advanced', form.Flag, 'NetworkOptimizationEnabled', _('Network optimization'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('Periodically re-evaluates the backhaul link of every agent. ' +
			'Disable it before triggering a backhaul steer or a band switch.');

		o = s.taboption('advanced', form.Value, 'NtwrkOptConnectWaitTime', _('Optimization delay after join'),
			_('Seconds to wait after a new device joins before evaluating the backhaul.'));
		o.datatype = 'uinteger';
		o.placeholder = '45';
		o.depends('NetworkOptimizationEnabled', '1');

		o = s.taboption('advanced', form.Value, 'NtwrkOptDisconnectWaitTime', _('Optimization delay after leave'),
			_('Seconds to wait after a device leaves before evaluating the backhaul.'));
		o.datatype = 'uinteger';
		o.placeholder = '45';
		o.depends('NetworkOptimizationEnabled', '1');

		o = s.taboption('advanced', form.Value, 'BandSwitchTime', _('Backhaul retry delay'),
			_('Seconds before retrying a higher priority backhaul, 0 to never retry.'));
		o.datatype = 'uinteger';
		o.placeholder = '120';
		o.cfgvalue = function(section_id) {
			var v = uci.get('mapd', section_id, 'BandSwitchTime');
			return (v && v.trim() !== '') ? v.trim() : '';
		};

		o = s.taboption('advanced', form.Flag, 'NetworkOptPrefer5Gover2G', _('Prefer 5 GHz backhaul'),
			_('Force a backhaul re-evaluation when an agent stays on 2.4 GHz.'));
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('advanced', form.Flag, 'ChPlanningEnable', _('Automatic channel planning'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('The controller moves all agents to a common channel per band.');

		o = s.taboption('advanced', form.Value, 'ChPlanningUserPreferredChannel2G', _('Preferred 2.4 GHz channel'),
			_('Leave empty for automatic selection.'));
		o.datatype = 'range(1,14)';
		o.placeholder = 'auto';
		o.depends('ChPlanningEnable', '1');
		o.cfgvalue = function(section_id) {
			var v = uci.get('mapd', section_id, 'ChPlanningUserPreferredChannel2G');
			return (v && v.trim() !== '') ? v.trim() : '';
		};

		o = s.taboption('advanced', form.Value, 'ChPlanningUserPreferredChannel5G', _('Preferred 5 GHz channel'),
			_('Leave empty for automatic selection.'));
		o.datatype = 'range(36,177)';
		o.placeholder = 'auto';
		o.depends('ChPlanningEnable', '1');
		o.cfgvalue = function(section_id) {
			var v = uci.get('mapd', section_id, 'ChPlanningUserPreferredChannel5G');
			return (v && v.trim() !== '') ? v.trim() : '';
		};

		o = s.taboption('advanced', form.Value, 'ChPlanningIdleTime', _('Channel planning idle time'),
			_('Seconds without traffic before channel planning may run again.'));
		o.datatype = 'uinteger';
		o.placeholder = '120';
		o.depends('ChPlanningEnable', '1');
		o.cfgvalue = function(section_id) {
			var v = uci.get('mapd', section_id, 'ChPlanningIdleTime');
			return (v && v.trim() !== '') ? v.trim() : '';
		};

		o = s.taboption('advanced', form.Flag, 'DhcpCtl', _('DHCP control'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('The controller manages the DHCP server setting of its agents.');

		maps.push(m);

		/* ================================================================ */
		/* 合并渲染                                                          */
		/* ================================================================ */
		return Promise.all(maps.map(function(x) { return x.render(); }))
			.then(function(rendered) {
				var container = E('div');
				rendered.forEach(function(r) {
					container.appendChild(r);
				});
				return container;
			});
	}
});
