
local tools = require("scripts.tools")

---@alias QName string
---@class FilterTable : table<QName, integer>        

---@class Device : EntityWithIdAndProcess
---@field id Entity.unit_number             @ Unit number
---@field entity LuaEntity                  @ Associated entity
---@field filter_source FilterSource        @ Source to get filters
---@field filling_mode integer                      @ Filling mode 
---@field idle_count integer                @ Idle counter between wagon scan
---@field wagon LuaEntity | nil 
---@field wagon_pos MapPosition | nil 
---@field wagon_box BoundingBox | nil
---@field filter_counts FilterTable                 @ Counts of filter slot in wagon
---@field filter_tick integer                       @ Timer to renew filter scan
---@field inserters LuaEntity[] | nil               @ Managed inserters
---@field inserter_tick integer                     @ Counter to renew inserter scan
---@field is_filtered boolean                       @ Inserter are filtered
---@field execution_index integer
---@field transfert_size ItemCount                  @ Sum of all inserter stack size
---@field out_red LuaEntity                         @ Red output combinator
---@field out_green LuaEntity                       @ Green output combinator
---@field wagons_to_unfilter LuaEntity[] | nil      @ list of wagons to reset filter and bar
---@field filter_reset boolean                      @ Reset filter reset and reload
---@field disabled boolean                          @ Reset filter reset and reload
---@field pickup_map table<int, LuaEntity>          @ Chest for pick
---@field target_content table<QName, integer>     @ Target train content after loading
---@field target_content_changed boolean?
---@field not_connected_to_yatm boolean
---@field unloading boolean?
---@field current_image integer

---@class GlobalsPerPlayer
---@field selected_uis number[]
---@field selected_device Device
---@field cc LuaEntity

---@enum FilterSource
FilterSource = {
    none = 1,
    green_signal = 2,
    red_signal = 3,
    internal_yatm = 4
}


local def = { }

---@enum SortMode
def.filling_modes = {
    packed = 1,
    balanced = 2,
    order = 3
}

---@type EntityMap<Device>
def.devices = {}

---@param player LuaPlayer
---@return GlobalsPerPlayer
function def.get_vars(player) 
    return tools.get_vars(player) --[[@as GlobalsPerPlayer]]
end

def.flags = {

    filter_source = { mask=0x7, shift=0 },
    enabled = { mask = 0x1, shift = 3 },
    filling_mode = { mask = 0x0f, shift=4 }
}

---@alias FlagsName "filter_source" | "enabled" | "filling_mode"

---@param name FlagsName
---@param value integer
---@return integer
function def.to_flags(name, value) 
    local fdef = def.flags[name]
    return bit32.lshift(value, fdef.shift)
end

---@param name FlagsName
---@param value integer
---@return integer
function def.from_flags(name, value) 
    local fdef = def.flags[name]
    return bit32.band(bit32.rshift(value, fdef.shift), fdef.mask)
end

return def
