

local tools = require("scripts.tools")

local prefix = "transfert_controller"
local modpath = "__transfert_controller__"
local device_name = prefix .. "-device"

local commons = {

	prefix = prefix ,
    modpath = modpath,
	device_name = device_name,
	cc_name = device_name .. "-cc",
	graphic_path = modpath .. '/graphics/%s.png',
    refresh_rate = 10,
	idle_count = 2,
	reconfigure_delay = 30,
	max_per_tick = 2
}

---@param name string
---@return string
function commons.png(name) return (commons.graphic_path):format(name) end


return commons
