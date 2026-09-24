local M = {}

local uci = require "uci"
local fs = require "oui.fs"
local ubus = require "oui.ubus"

local function mtkwifi_split(s, delimiter)
    if s == nil then s = "" end
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

local function get_random_bssid()
    local f = io.open('/dev/urandom')

    assert(f)

    local addr = {}

    local limits = { '2', '6', 'A', 'E' }

    for i = 1, 6 do
        local v = string.format("%02x", f:read(1):byte()):upper()
        if i == 1 then
            addr[i] = v:sub(1, 1) .. limits[f:read(1):byte() % 4 + 1]
        elseif i == 6 then
            -- for QCA 6G MAC rule: The first five bytes should be same, and last byte can't be 0xFF
            -- so we need to avoid use 0xF6~0xFF because the last byte maybe 94:xx:xx:xx:xx:FF if enable more SSID in the furture(MESH)
            local last_byte
            repeat
                last_byte = string.format("%02x", f:read(1):byte()):upper()
            until tonumber(last_byte, 16) < 0xF6
            addr[i] = last_byte
        else
            addr[i] = v
        end
    end

    f:close()

    return table.concat(addr, ":")
end

local function setup_guest_network(c)
    local disabled = '1'

    for s in c:each("wireless", "wifi-iface") do
        if s.network == 'guest' and s.disabled ~= '1' then
            disabled = '0'
            break
        end
    end

    if c:get("network", "guest", "disabled") ~= disabled then
        c:set("network", "guest", "disabled", disabled)
        c:commit("network")

        ubus.call("network", "reload", {})
    end
end

local function set_mld_random_bssid(c, ifname, on, enable)
    local mac_bytes
    local mld_macaddr
    local macaddr
    local config = c:get_all("mlo", 'global')

    if on == nil or (config.random_bssid == "1") == on then
        if enable then
            mld_macaddr = c:get('mlo', ifname, 'mld_macaddr')
            c:set('wireless', ifname, 'mld_macaddr', mld_macaddr)
        end
        return false
    end

    c:set("mlo", 'global', "random_bssid", on and 1 or 0)

    c:foreach("wireless", "wifi-iface", function(s)
        if s.mode ~= "ap" or not s.mld then
            return
        end

        local name = s[".name"]

        if on then
            macaddr = get_random_bssid()
            mld_macaddr = get_random_bssid()
        else
            macaddr = c:get("wireless", name, "factory_macaddr")
            mac_bytes = macaddr:sub(1, 2)
            mac_bytes = string.format("%02x", tonumber(mac_bytes, 16) + 4):upper()
            mld_macaddr = mac_bytes .. macaddr:sub(3, -1)
        end

        c:set("wireless", name, "macaddr", macaddr)
        c:set('mlo', s.mld, 'mld_macaddr', mld_macaddr)
        c:set("wireless", s.mld, "mld_addr", mld_macaddr)
    end)
end

local function check_mlo_band_support(c, param)
    local need_disable_device = nil
    local mlo_bandlist = {}

    for s in c:each('wireless', 'wifi-device') do
        local mlo_band_selected = 0
        for _, check_band in ipairs(param.mlo_band) do
            if check_band == s.band then
                mlo_band_selected = 1
                mlo_bandlist[#mlo_bandlist + 1] = s.band
            end
        end
        if mlo_band_selected == 0 then
            need_disable_device = s['.name']
        end
    end

    c:set('mlo', param.name, 'bands', mlo_bandlist)
    return need_disable_device
end

function M.mtkwifi_set_force_40MHz(device, c, enable)
    local type = c:get("wireless", device, "type")
    c:foreach("wireless", "wifi-device", function(s)
        if s[".name"] ~= device then return end
        if type == "mtkwifi" then
            if enable == 1 then
                c:set("wireless", s[".name"], "ht_coex", "1")
            else
                c:set("wireless", s[".name"], "ht_coex", "0")
            end
        end
    end)
end

function M.rpc2uci_encryption(param)
    if param.encryption == "psk2" then
        param.encryption = "psk2+ccmp"
    elseif param.encryption == "psk-mixed" then
        param.encryption = "psk-mixed+ccmp"
    end
end

function M.uci2rpc_encryption(param)
    if param.encryption == "psk2+ccmp" then
        param.encryption = "psk2"
    elseif param.encryption == "psk-mixed+ccmp" then
        param.encryption = "psk-mixed"
    end
end

function M.set_mlo_config(param)
    local c = uci.cursor()
    local iface
    local mlo_support_bands = c:get('mlo', 'global', 'support_bands')

    --MLOwifi启动开启、关闭时，UI只下发了name&enable参数
    if not param.mlo_band then
        param.mlo_band = c:get('mlo', param.name, 'bands')
        --第一次开启MLO时，/etc/config/mlo中还未记录bands信息
        if not param.mlo_band then
            param.mlo_band = mlo_support_bands
        end

        c:set('mlo', param.name, 'bands', param.mlo_band)

        for s in c:each("wireless", "wifi-iface") do
            if s.mld == param.name then
                local device = c:get_all("wireless", s.device)
                local enable_band = false
                for _, band in ipairs(param.mlo_band) do
                    if device.band == band then
                        enable_band = true
                        break
                    end
                end
                c:set('wireless', s['.name'], 'disabled', (param.mlo_enable and enable_band) and '0' or '1')
            end
        end
    else
        local need_disable_device = check_mlo_band_support(c, param)

        M.rpc2uci_encryption(param)
        for s in c:each('wireless', 'wifi-iface') do
            if s.mld == param.name then
                c:set('wireless', s['.name'], 'ssid', param.ssid)
                c:set('wireless', s['.name'], 'encryption', param.encryption)
                c:set('wireless', s['.name'], 'key', param.key)
                c:set('wireless', s['.name'], 'hidden', param.hidden and '1' or '0')
                local need_disable = (s.device == need_disable_device)
                if param.mlo_enable then
                    c:set('wireless', s['.name'], 'disabled', need_disable and '1' or '0')
                else
                    c:set('wireless', s['.name'], 'disabled', '1')
                end
                if not need_disable then
                    iface = iface and (iface.." "..s.ifname) or s.ifname
                end
            end
        end
        c:set('wireless', param.name, 'ssid', param.ssid)
        c:set('wireless', param.name, 'encryption', param.encryption)
        c:set('wireless', param.name, 'key', param.key)
        c:set('wireless', param.name, 'hidden', param.hidden and '1' or '0')
        --c:set('wireless', param.name, 'guest', param.guest and '1' or '0')
        c:set('wireless', param.name, 'iface', iface)
    end

    c:set('wireless', param.name, 'disabled', param.mlo_enable and '0' or '1')

    c:set('mlo', param.name, 'disabled', param.mlo_enable and '0' or '1')

    set_mld_random_bssid(c, param.name, param.random_bssid, param.mlo_enable)
    setup_guest_network(c)
    ubus.send('gl-cloud', { feature = 'wifi' })
    c:commit("wireless")
    c:commit("mlo")
    fs.sync()
    ngx.pipe.spawn({"/sbin/wifi", "reload"}, { stdout_read_timeout = 30000 }):wait()
end

function M.get_mlo_config()
    local c = uci.cursor()
    local res
    local ifaces = {}
    local encryptions = {"none","psk2","psk-mixed","sae","sae-mixed"}
    local mlo_bandsupport = c:get('mlo', 'global', 'support_bands')

    for s in c:each("wireless", "wifi-mld") do
        local mlo_bandlist = {}
        local mlo_on = false
        local mld_iface

        mld_iface = mtkwifi_split(s.iface, " ")
        if s.disabled == '0' then
            mlo_on = true
        end
        if s.iface == nil then
            mlo_on = false
        end

        for _, vifname in pairs(mld_iface) do
            if vifname:match("^ra%d+$") then
                mlo_bandlist[#mlo_bandlist + 1] = '2g'
            elseif vifname:match("^rai%d+$") then
                mlo_bandlist[#mlo_bandlist + 1] = '5g'
            elseif vifname:match("^rax%d+$") then
                mlo_bandlist[#mlo_bandlist + 1] = '6g'
            end
        end

        M.uci2rpc_encryption(s)

        ifaces[#ifaces + 1] = {
            mlo_enable = mlo_on,
            mlo_band = mlo_bandlist,
            ssid = s.ssid,
            encryption = s.encryption,
            key = s.key,
            hidden = s.hidden == "1",
            guest = s.guest == "1",
            name = s['.name']
        }
    end

    res = {
        ifaces = ifaces,
        encryptions = encryptions,
        mlo_bandsupport = mlo_bandsupport,
        random_bssid = c:get('mlo', 'global', 'random_bssid') == "1"
    }
    return { res = res }
end

return M

