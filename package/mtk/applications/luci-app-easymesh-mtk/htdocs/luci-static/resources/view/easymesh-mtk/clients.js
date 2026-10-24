'use strict';
'require view';
'require fs';
'require poll';
'require ui';
'require dom';

/*
 * EasyMesh 客户端显示 - 对标原生 LuCI "Associated Stations"
 * 特点：
 *   - 汇总全网 Mesh 内所有 Agent 的关联客户端
 *   - 可视化信号强度条（4 级颜色）
 *   - MLO / Backhaul STA 标签
 *   - poll 每 10 秒自动刷新
 *   - 使用标准 cbi-section-table，与 OpenWrt 25.12 状态页样式一致
 */

var RPC = '/usr/libexec/rpcd/easymesh-mtk';

function rpcExec(method, args) {
	return fs.exec(RPC, [ 'call', method ].concat(args || []))
		.then(function(res) {
			try {
				var data = JSON.parse(res.stdout || '{}');
				return data;
			} catch (e) {
				return { ok: false, error: res.stdout || res.stderr };
			}
		})
		.catch(function(e) {
			return { ok: false, error: e.message };
		});
}

return view.extend({
	load: function() {
		return rpcExec('get_clients').then(function(r) {
			if (r.ok) {
				try { return JSON.parse(r.clients || '[]'); }
				catch (e) { return []; }
			}
			return [];
		});
	},

	/* ---------- 信号强度分级 ---------- */
	signalInfo: function(rssi) {
		if (rssi >= -50) return { level: 4, color: '#43a047', text: _('Excellent') };
		if (rssi >= -60) return { level: 3, color: '#7cb342', text: _('Good') };
		if (rssi >= -70) return { level: 2, color: '#fbc02d', text: _('Fair') };
		if (rssi >= -80) return { level: 1, color: '#ef6c00', text: _('Weak') };
		return { level: 0, color: '#c62828', text: _('Very Weak') };
	},

	/* ---------- 信号条 ---------- */
	renderSignalBar: function(rssi) {
		var info = this.signalInfo(rssi);
		var bars = [];
		for (var i = 1; i <= 4; i++) {
			var active = i <= info.level;
			bars.push(E('span', {
				'style': [
					'display:inline-block',
					'width:4px',
					'height:' + (4 + i * 3) + 'px',
					'background:' + (active ? info.color : '#d0d0d0'),
					'margin-right:2px',
					'border-radius:1px',
					'vertical-align:bottom'
				].join(';')
			}));
		}
		return E('span', {
			'title': rssi + ' dBm — ' + info.text,
			'style': 'white-space:nowrap'
		}, bars.concat([
			E('span', {
				'style': 'margin-left:6px;font-size:11px;color:#666;vertical-align:bottom'
			}, rssi + ' dBm')
		]));
	},

	/* ---------- 速率格式化 ---------- */
	formatRate: function(rate) {
		if (!rate || rate === '0' || rate === '0.0') return '-';
		var r = parseFloat(rate);
		if (isNaN(r) || r === 0) return '-';
		if (r >= 1000) return (r / 1000).toFixed(1) + ' Gbps';
		return r.toFixed(0) + ' Mbps';
	},

	/* ---------- 频段标签 ---------- */
	renderBand: function(band) {
		var colors = {
			'2.4G': { bg: '#e8f5e9', fg: '#2e7d32' },
			'5G':   { bg: '#e3f2fd', fg: '#1565c0' },
			'6G':   { bg: '#f3e5f5', fg: '#6a1b9a' }
		};
		var c = colors[band] || { bg: '#eeeeee', fg: '#424242' };
		return E('span', {
			'style': [
				'display:inline-block',
				'padding:1px 8px',
				'border-radius:10px',
				'font-size:11px',
				'font-weight:bold',
				'background:' + c.bg,
				'color:' + c.fg
			].join(';')
		}, band);
	},

	/* ---------- 类型标签 ---------- */
	renderType: function(c) {
		var tags = [];
		if (c.is_backhaul === 'Yes') {
			tags.push(E('span', {
				'style': 'display:inline-block;padding:1px 8px;border-radius:10px;font-size:11px;font-weight:bold;background:#fff3e0;color:#e65100;margin-right:4px'
			}, _('Backhaul')));
		} else {
			tags.push(E('span', {
				'style': 'display:inline-block;padding:1px 8px;border-radius:10px;font-size:11px;background:#f5f5f5;color:#616161;margin-right:4px'
			}, _('Client')));
		}
		if (c.is_mlo) {
			tags.push(E('span', {
				'style': 'display:inline-block;padding:1px 8px;border-radius:10px;font-size:11px;font-weight:bold;background:#e1f5fe;color:#0277bd',
				'title': c.mld_mac ? 'MLD MAC: ' + c.mld_mac : ''
			}, 'MLO'));
		}
		return E('span', {}, tags);
	},

	/* ---------- 构建表格行 ---------- */
	buildRows: function(clients) {
		var self = this;
		return clients.map(function(c) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'data-title': _('Hostname / IP') }, [
					E('strong', {}, c.hostname || c.mac),
					c.ip ? E('span', { 'style': 'color:#888;margin-left:6px;font-size:12px' },
						'(' + c.ip + ')') : ''
				]),
				E('td', { 'class': 'td', 'data-title': _('MAC Address') }, [
					E('code', { 'style': 'font-size:12px' }, c.mac)
				]),
				E('td', { 'class': 'td', 'data-title': _('Band') },
					self.renderBand(c.band || c.iface)),
				E('td', { 'class': 'td', 'data-title': _('Signal'), 'style': 'text-align:center' },
					self.renderSignalBar(c.signal)),
				E('td', { 'class': 'td', 'data-title': _('RX / TX'), 'style': 'white-space:nowrap' },
					self.formatRate(c.rx_rate) + ' / ' + self.formatRate(c.tx_rate)),
				E('td', { 'class': 'td', 'data-title': _('Type') },
					self.renderType(c))
			]);
		});
	},

	/* ---------- 空状态 ---------- */
	renderEmpty: function() {
		return E('div', {
			'style': 'text-align:center;padding:2em 1em;color:#999'
		}, [
			E('div', { 'style': 'font-size:2em;margin-bottom:8px' }, '📶'),
			E('p', {}, _('No clients connected.'))
		]);
	},

	/* ---------- 主渲染 ---------- */
	render: function(clients) {
		var self = this;
		var container = E('div', { 'class': 'cbi-map' });

		function rebuild(list) {
			var content = [
				E('h2', {}, _('Connected Clients')),
				E('div', { 'class': 'cbi-map-descr' },
					_('All clients currently associated to the EasyMesh network. ' +
					  'Signal bars reflect RSSI. Rates show RX/TX in Mbps. ' +
					  'This list refreshes automatically every 10 seconds.'))
			];

			if (list.length === 0) {
				content.push(self.renderEmpty());
			} else {
				content.push(E('div', { 'class': 'cbi-section' }, [
					E('div', {
						'style': 'margin-bottom:8px;font-size:12px;color:#666'
					}, _('%d client(s) connected').format(list.length)),
					E('table', { 'class': 'table cbi-section-table' }, [
						E('tr', { 'class': 'tr table-titles' }, [
							E('th', { 'class': 'th' }, _('Hostname / IP')),
							E('th', { 'class': 'th' }, _('MAC Address')),
							E('th', { 'class': 'th' }, _('Band')),
							E('th', { 'class': 'th', 'style': 'text-align:center' }, _('Signal')),
							E('th', { 'class': 'th' }, _('RX / TX')),
							E('th', { 'class': 'th' }, _('Type'))
						])
					].concat(self.buildRows(list)))
				]));
			}

			content.push(E('div', { 'class': 'cbi-page-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': function(ev) {
						var btn = ev.currentTarget;
						btn.classList.add('spinning');
						btn.disabled = true;
						return self.load().then(function(list) {
							btn.classList.remove('spinning');
							btn.disabled = false;
							rebuild(list);
						});
					}
				}, _('Refresh'))
			]));

			dom.content(container, content);
		}

		rebuild(clients || []);

		/* 轮询：每 10 秒自动刷新 */
		poll.add(L.bind(function() {
			return self.load().then(function(list) {
				rebuild(list);
				return list;
			});
		}, this), 10);

		return container;
	}
});
