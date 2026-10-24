'use strict';
'require view';
'require form';
'require uci';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('mapd', _('MLO/MLD Configuration'),
			_('Configure MLO/MLD for 802.11be Multi-Link Devices (MLD). ' +
			  'Multi-link group IDs range from 1 to 16, single-link group IDs from 17 to 48. ' +
			  'All BSSes in the same MLD group must share the same SSID, password and security settings.'));

		/* ------------------------------------------------------------------ */
		/* 收集无线接口                                                        */
		/* ------------------------------------------------------------------ */
		var all_ifaces = [];
		uci.sections('wireless', 'wifi-iface').forEach(function(w) {
			if (w.ifname && all_ifaces.indexOf(w.ifname) === -1)
				all_ifaces.push(w.ifname);
		});
		all_ifaces.sort();

		function band_of(name) {
			if (/^rax/i.test(name)) return '6G';
			if (/^rai/i.test(name)) return '5G';
			if (/^ra/i.test(name)) return '2.4G';
			if (/^radio/i.test(name)) return 'Radio';
			return _('Other');
		}

		/* ================================================================== */
		/* 1. 全局 MLD 设置                                                    */
		/* ================================================================== */
		s = m.section(form.NamedSection, 'mapd_cfg', 'mapd_cfg', _('Global MLD Settings'));
		s.addremove = false;

		o = s.option(form.Flag, 'MldEnable', _('Enable MLD'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('Enable Multi-Link Operation for this device. Only supported on 802.11be (Wi-Fi 7) SKUs.');

		/* ================================================================== */
		/* 2. AP MLD 组（Mode = AP）                                           */
		/* ================================================================== */
		s = m.section(form.GridSection, 'mld_ap', _('AP MLD Groups'));
		s.addremove = true;
		s.anonymous = false;
		s.addbtntitle = _('Add AP MLD Configuration');
		s.description = _('Each entry defines one AP MLD group. Interfaces selected in the same group are affiliated to the same AP MLD. ' +
			'SSID, password and security settings must match for all interfaces in a group.');
		s.write = function(section_id, values) {
			var name = section_id || ('mld_ap_' + Date.now());
			uci.set('mapd', name, 'mld');
			uci.set('mapd', name, 'Mode', 'ap');
			for (var k in values)
				uci.set('mapd', name, k, values[k]);
		};

		o = s.option(form.Flag, 'Enable', _('Enable'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'SSID', _('SSID'));
		o.datatype = 'maxlength(32)';
		o.rmempty = false;

		o = s.option(form.MultiValue, 'IfaceList', _('Interface list'),
			_('Select the interfaces that belong to this AP MLD group. An interface can only join one MLD group.'));
		if (all_ifaces.length === 0) {
			o.value('', _('No wireless interface found'));
		} else {
			all_ifaces.forEach(function(ifname) {
				o.value(ifname, ifname + ' (' + band_of(ifname) + ')');
			});
		}
		o.rmempty = false;

		o = s.option(form.Value, 'Address', _('Address'),
			_('Optional MLD MAC address. Leave empty for automatic assignment.'));
		o.datatype = 'macaddr';
		o.rmempty = true;

		o = s.option(form.ListValue, 'AuthMode', _('Auth Mode'));
		o.value('Enhanced Open', _('Enhanced Open'));
		o.value('WPA2-PSK', _('WPA2-PSK'));
		o.value('WPA3-SAE', _('WPA3-SAE'));
		o.value('WPA3-SAE-Transition', _('WPA3 Transition'));
		o.default = 'WPA3-SAE';
		o.rmempty = false;

		o = s.option(form.ListValue, 'Encryption', _('Encryption'));
		o.value('AES', 'AES');
		o.default = 'AES';
		o.rmempty = false;

		o = s.option(form.Flag, 'MFPC', _('MFPC'),
			_('Management Frame Protection Capable.'));
		o.default = '1';

		o = s.option(form.Flag, 'MFPR', _('MFPR'),
			_('Management Frame Protection Required.'));
		o.default = '1';

		o = s.option(form.Value, 'MldGroupID', _('MLD group ID'),
			_('Multi-link groups: 1-16, Single-link groups: 17-48.'));
		o.datatype = 'range(1,48)';
		o.rmempty = true;

		/* ================================================================== */
		/* 3. APCLI MLD 组（Mode = STA）                                       */
		/* ================================================================== */
		s = m.section(form.GridSection, 'mld_sta', _('APCLI MLD Groups (STA)'));
		s.addremove = true;
		s.anonymous = false;
		s.addbtntitle = _('Add APCLI MLD Configuration');
		s.description = _('Each entry defines one APCLI MLD group used for the wireless backhaul STA (bSTA). ' +
			'After creating the STA MLD, authentication, association and EAPOL handshakes happen only on the primary link, ' +
			'but data can be transferred on all links.');
		s.write = function(section_id, values) {
			var name = section_id || ('mld_sta_' + Date.now());
			uci.set('mapd', name, 'mld');
			uci.set('mapd', name, 'Mode', 'sta');
			for (var k in values)
				uci.set('mapd', name, k, values[k]);
		};

		o = s.option(form.Flag, 'Enable', _('Enable'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'SSID', _('SSID'));
		o.datatype = 'maxlength(32)';
		o.rmempty = false;

		o = s.option(form.MultiValue, 'IfaceList', _('Interface list'),
			_('Select the APCLI interfaces that belong to this STA MLD group. An interface can only join one MLD group.'));
		if (all_ifaces.length === 0) {
			o.value('', _('No wireless interface found'));
		} else {
			all_ifaces.forEach(function(ifname) {
				o.value(ifname, ifname + ' (' + band_of(ifname) + ')');
			});
		}
		o.rmempty = false;

		o = s.option(form.Value, 'Address', _('Address'),
			_('Optional MLD MAC address. Leave empty for automatic assignment.'));
		o.datatype = 'macaddr';
		o.rmempty = true;

		o = s.option(form.ListValue, 'AuthMode', _('Auth Mode'));
		o.value('Enhanced Open', _('Enhanced Open'));
		o.value('WPA2-PSK', _('WPA2-PSK'));
		o.value('WPA3-SAE', _('WPA3-SAE'));
		o.value('WPA3-SAE-Transition', _('WPA3 Transition'));
		o.default = 'WPA3-SAE';
		o.rmempty = false;

		o = s.option(form.ListValue, 'Encryption', _('Encryption'));
		o.value('AES', 'AES');
		o.default = 'AES';
		o.rmempty = false;

		o = s.option(form.Flag, 'MFPC', _('MFPC'),
			_('Management Frame Protection Capable.'));
		o.default = '1';

		o = s.option(form.Flag, 'MFPR', _('MFPR'),
			_('Management Frame Protection Required.'));
		o.default = '1';

		o = s.option(form.Value, 'MldGroupID', _('MLD group ID'),
			_('Multi-link groups: 1-16, Single-link groups: 17-48.'));
		o.datatype = 'range(1,48)';
		o.rmempty = true;

		/* ================================================================== */
		/* 4. 每个 BSS 的 MLD Group ID（来自 /etc/config/mapd）                 */
		/* ================================================================== */
		var ifaces = uci.sections('mapd', 'iface') || [];

		if (ifaces.length === 0) {
			s = m.section(form.NamedSection, 'mapd_cfg', 'mapd_cfg', _('BSS MLD Group IDs'));
			s.addremove = false;
			o = s.option(form.DummyValue, '_no_iface', _('No BSS found'));
			o.rawhtml = true;
			o.cfgvalue = function() {
				return _('No BSS configuration found in /etc/config/mapd.');
			};
		} else {
			s = m.section(form.GridSection, 'iface', _('BSS MLD Group IDs'));
			s.addremove = false;
			s.anonymous = false;
			s.description = _('Assign each BSS to an MLD group. BSSes with the same group ID are affiliated to the same MLD. ' +
				'Leave empty to disable MLD for this BSS.');

			o = s.option(form.DummyValue, '_ssid_disp', _('SSID'));
			o.cfgvalue = function(section_id) {
				return uci.get('mapd', section_id, 'ssid') || '-';
			};

			o = s.option(form.DummyValue, '_radio_disp', _('Radio'));
			o.cfgvalue = function(section_id) {
				var r = uci.get('mapd', section_id, 'radio') || '-';
				if (r === '8x') return '2.4G';
				if (r === '11x') return '5G Low';
				if (r === '12x') return '5G High';
				if (r === '13x') return '6G';
				return r;
			};

			o = s.option(form.Value, 'mld_groupID', _('MLD group ID'),
				_('Multi-link groups: 1-16, Single-link groups: 17-48. Leave empty to disable MLD for this BSS.'));
			o.datatype = 'range(1,48)';
			o.rmempty = true;
			o.placeholder = _('e.g. 1');
		}

		/* ================================================================== */
		/* 5. MLD 网络优化                                                     */
		/* ================================================================== */
		s = m.section(form.NamedSection, 'mapd_cfg', 'mapd_cfg', _('Network Optimization for MLD'));
		s.addremove = false;

		o = s.option(form.Flag, 'NetOptUserSetPriority', _('Use user BH priority in network optimization'),
			_('When enabled, network optimization gives preference to the BH priorities set by the user.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'NtwrkOptMldBhPriority', _('MLD BH priority override'),
			_('Set to 1 in MLD controller to let network optimization choose the best primary backhaul for each MLD agent.'));
		o.datatype = 'range(0,1)';
		o.default = '1';
		o.rmempty = false;

		/* ================================================================== */
		/* 6. 行为与限制（只读提示）                                           */
		/* ================================================================== */
		s = m.section(form.NamedSection, 'mapd_cfg', 'mapd_cfg', _('Behavior & Limitations'));
		s.addremove = false;

		o = s.option(form.DummyValue, '_mld_regroup_note', _('Dynamic MLD regrouping'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return _('When MLD groups are changed, hostapd is reloaded on all mesh devices, ' +
				'and all stations (including agents) will disconnect and reconnect.');
		};

		o = s.option(form.DummyValue, '_mld_band_steer_note', _('Band steering for MLD clients'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return _('Band steering is not supported for MLD clients. ' +
				'MLD clients are expected to be connected on multiple links already.');
		};

		o = s.option(form.DummyValue, '_mld_bh_priority_note', _('Backhaul priority for MLD'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return _('For MLO-capable SKUs, backhaul priority has no effect. ' +
				'All backhaul links are treated as highest priority (1). ' +
				'WPS registrar only provides profiles for the band on which the WPS handshake occurred.');
		};

		o = s.option(form.DummyValue, '_mld_scan_note', _('MLD scan and link selection'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return _('For MLO-capable SKUs, scanning is performed on 5G, 6G and 2.4G with equal priority. ' +
				'Best AP score combines individual band scores and cumulative MLD score (X+Y+Z). ' +
				'The primary link is preferably formed on 6G to avoid DFS interruptions.');
		};

		o = s.option(form.DummyValue, '_mld_divergent_note', _('Divergent channel planning'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return _('Divergent channel planning is not supported when the mesh network contains MLD devices, ' +
				'because all links of an MLD must operate on the same channel.');
		};

		o = s.option(form.DummyValue, '_mld_wts_note', _('WTS / UCI configuration'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return _('In wts_bss_info_config, add the MLD Group ID column at the end. ' +
				'All BSSes in the same MLD group must share the same SSID, password, auth mode and encryption type. ' +
				'In UCI, set <code>option mld_groupID \'1\'</code> in the corresponding interface section.');
		};

		/* ================================================================== */
		/* 7. 调试                                                             */
		/* ================================================================== */
		s = m.section(form.NamedSection, 'mapd_cfg', 'mapd_cfg', _('Debug'));
		s.addremove = false;

		o = s.option(form.DummyValue, '_debug_note', _('Runtime MLD information'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return _('To check the current MLD grouping at runtime, use the following command on the device console:') +
				'<br /><code>iwpriv ra0 show bssmngr</code>';
		};

		o = s.option(form.DummyValue, '_mld_cli_note', _('MLD CLI commands'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return _('Useful commands for MLD debugging:') +
				'<br /><code>mapd_cli /tmp/mapd_ctrl mib assoc_sta_list</code>' +
				'<br /><code>mapd_cli /tmp/mapd_ctrl block_acl 0 5 &lt;duration&gt; &lt;cli_mac&gt; &lt;mld_mac&gt;</code> (block MLD device)' +
				'<br /><code>mapd_cli /tmp/mapd_ctrl block_acl 0 6 &lt;cli_mac&gt; &lt;mld_mac&gt;</code> (unblock MLD device)';
		};

		return m.render();
	}
});
