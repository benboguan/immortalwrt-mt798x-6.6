'use strict';
'require view';
'require rpc';
'require ui';

/*
 * MediaTek EasyMesh / MAP Turnkey - runtime status.
 *
 * Read-only view: daemon state, startup state, control socket, backhaul link
 * metric, topology dump and the mapd log.
 */

var callStatus = rpc.declare({
	object: 'easymesh-mtk',
	method: 'get_status',
	expect: {
		role: '', enable: '', svc_enabled: '', map_ver: '', mapd: '', p1905: '', wapp: '',
		socket: '', almac: '', dpp_role: '', bh_status: '', topology: '', mapd_log: ''
	}
});

var DAEMONS = [ 'mapd', 'p1905', 'wapp' ];

return view.extend({
	load: function() {
		return Promise.all([ callStatus() ]);
	},

	render: function(data) {
		var st = (data && data[0]) || {};

		function roleText(v) {
			return (v === '1' || v === '2')
				? (v === '1' ? _('Controller') : _('Agent'))
				: _('Auto');
		}

		function badge(state, onText, offText) {
			var ok = (state === 'running' || state === 'up' || state === '1');
			return E('span', {
				'class': 'cbi-button cbi-button-%s'.format(ok ? 'apply' : 'reset'),
				'style': 'pointer-events:none'
			}, ok ? (onText || _('running')) : (offText || _('stopped')));
		}

		function row(title, value) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '25%' }, title),
				E('td', { 'class': 'td left' }, value)
			]);
		}

		function pre(text) {
			return E('pre', {
				'style': 'max-height:22em;overflow:auto;white-space:pre-wrap;margin:0'
			}, text || _('(no data)'));
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('EasyMesh status')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Runtime state of the MAP Turnkey daemons and of the current mesh.')),

			E('h3', {}, _('Overview')),
			E('table', { 'class': 'table' }, [
				row(_('State'), badge(st.enable === '0' ? 'stopped' : 'running')),
				row(_('Startup'), badge(st.svc_enabled, _('enabled at boot'), _('disabled at boot'))),
				row(_('Device role'), roleText(st.role)),
				row(_('MAP version'), st.map_ver || '-'),
				row(_('AL MAC'), st.almac || '-'),
				row(_('Control socket'), badge(st.socket)),
				row(_('DPP allowed role'), roleText(st.dpp_role === '2' ? '1' : st.dpp_role))
			]),

			E('h3', {}, _('Daemons')),
			E('table', { 'class': 'table' }, DAEMONS.map(function(d) {
				return row(d === 'p1905' ? 'p1905_managerd' : d, badge(st[d]));
			})),

			E('h3', {}, _('Backhaul link metric')),
			pre(st.bh_status),

			E('h3', {}, _('Topology')),
			pre(st.topology),

			E('h3', {}, _('mapd log')),
			pre(st.mapd_log),

			E('div', { 'class': 'cbi-page-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, function() {
						window.location.reload();
					})
				}, _('Refresh'))
			])
		]);
	}
});
