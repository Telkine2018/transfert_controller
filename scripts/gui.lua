
local defs = require("scripts._defs")
local tools = require("scripts.tools")
local commons = require("scripts.commons")

------------------------------------------------------

local get_vars = tools.get_vars
local device_name = commons.device_name
local prefix = commons.prefix
local frame_name = prefix .. "_frame"

---@type EntityMap<Device>
local devices

------------------------------------------------------
local Gui = {}

---Close current ui
---@param player LuaPlayer
---@param element LuaGuiElement?
function Gui.close(player, element)

    ---@type LuaGuiElement
    local frame = player.gui.screen[frame_name]
    if element ~= nil and element ~= frame then return end

    if frame and frame.valid then

        local vars = defs.get_vars(player)
        vars.selected_device = nil
        frame.destroy()
    end
end

local filter_source_labels = {
    {prefix .. "-item.none"},
     {prefix .. "-item.green_signal"},
     {prefix .. "-item.red_signal"},
     {prefix .. "-item.internal_yatm"} 
    }

---@param player LuaPlayer
---@param entity LuaEntity
function Gui.create(player, entity)

    local device = devices[entity.unit_number]
    if not device then return end

    defs.get_vars(player).selected_device = device

    local frame = player.gui.screen.add { type = "frame",  name = frame_name, direction='vertical'}

    local titleflow = frame.add{type="flow"}
    titleflow.add{type="label",caption = { prefix .. "-frame.title" }, style="frame_title", ignored_by_interaction=true}
    local drag = titleflow.add{type="empty-widget",style="flib_titlebar_drag_handle"}
    drag.drag_target = frame
    titleflow.add{type="sprite-button",name=prefix.."-close", style="frame_action_button", mouse_button_filter={"left"}, 
        sprite="utility/close", hovered_sprite="utility/close_black" }

    local inner_frame = frame.add{type ="frame", style="inside_shallow_frame_with_padding",direction="vertical"}

    inner_frame.add{type="checkbox", name="disabled", state=device.disabled or false, caption = {prefix.."-field.disabled"}}

    local flow1 = inner_frame.add{type="flow", direction="horizontal"} 
    flow1.style.top_margin = 6
    local filter_source = device.filter_source or FilterSource.none
    flow1.add{type="label", caption={prefix .. "-field.filter_source"}}
    flow1.add{state=false, type="drop-down", name="filter_source", selected_index=filter_source, items=filter_source_labels, tooltip={"tooltip.filter_source"}}

    local flow2 = inner_frame.add{type="flow", direction="horizontal"} 
    flow2.style.top_margin = 6
    local items = tools.table_map(defs.filling_modes, function(k,v) return v, {prefix.."-item." .. k} end)
    flow2.add{type="label", caption={prefix .. "-field.filling_mode"}}
    flow2.add{type="drop-down", items=items, name="filling_mode", selected_index=device.filling_mode or defs.filling_modes.balanced}

    local bflow = frame.add{type="flow", direction="horizontal"}
    bflow.style.top_margin = 10

    local b = bflow.add{type="button", caption={prefix .. "-button.ok"}, name=prefix .. "-ok"}
    b = bflow.add{type="button", caption={prefix .. "-button.cancel"}, name=prefix.."-cancel"}

    frame.force_auto_center()
end


tools.on_gui_click(prefix .. "-close", 
---@EventData.on_gui_click
function(e) 
    Gui.close(game.players[e.player_index])
end)


tools.on_gui_click(prefix .. "-ok", 
---@EventData.on_gui_click
function(e) 
    local player = game.players[e.player_index]
    local frame = player.gui.screen[frame_name]
    local device = defs.get_vars(player).selected_device
    local flags = 0

    local field = tools.get_child(frame, "filter_source")
    ---@cast field -nil
    local filter_source = field.selected_index
    device.filter_source = filter_source
    flags = flags + defs.to_flags("filter_source", filter_source or 1)

    field = tools.get_child(frame, "disabled")
    ---@cast field -nil
    device.disabled = field.state
    flags = flags + defs.to_flags("enabled", field.state and 1 or 0)

    field = tools.get_child(frame, "filling_mode")
    ---@cast field -nil
    device.filling_mode = field.selected_index
    flags = flags + defs.to_flags("filling_mode", field.selected_index or 1)


    local cb = device.entity.get_or_create_control_behavior()
    ---@cast cb LuaArithmeticCombinatorControlBehavior
    local parameters = cb.parameters
    parameters.second_constant = flags
    cb.parameters = parameters
    device.filter_reset = true

    Gui.close(game.players[e.player_index])
end)

tools.on_gui_click(prefix .. "-cancel", 
---@EventData.on_gui_click
function(e) 
    Gui.close(game.players[e.player_index])
end)


---@param e EventData.on_gui_opened
local function on_gui_opened(e)
    local player = game.players[e.player_index]
    local entity = e.entity

    Gui.close(player)
    if not(entity and entity.valid and entity.name == device_name) then return end
    player.opened = nil
    Gui.create(player, entity)
end


---@param e EventData.on_gui_closed
local function on_gui_closed(e)
    local player = game.players[e.player_index]

    Gui.close(player, e.element)
end

tools.on_event(defines.events.on_gui_closed, on_gui_closed)
--tools.on_event(defines.events.on_gui_confirmed, on_gui_confirmed)

tools.on_event(defines.events.on_gui_opened, on_gui_opened)

local function on_load() 
    devices = storage.controllers --[[@as EntityMap<Device>]]
end
tools.on_load(on_load)

------------------------------------------------------


------------------------------------------------------

tools.on_event(defines.events.on_entity_settings_pasted, function(e)
    local source = devices[e.source.unit_number]
    local dest = devices[e.destination.unit_number]
    if not source or not dest then return end
end)

------------------------------------------------------

---@param bp LuaItemStack
---@param mapping {[integer]: LuaEntity}
local function register_mapping(bp, mapping)
    for index = 1, bp.get_blueprint_entity_count() do
        local entity = mapping[index]
        if entity and entity.name == device_name then
            local device = devices[entity.unit_number]
            if device then
                bp.set_blueprint_entity_tags(index, {
                    group = device.group,
                    factory = device.factory,
                    alerts = device.alerts and helpers.table_to_json(device.alerts)
                })
            end
        end
    end
end

tools.on_event(defines.events.on_player_setup_blueprint,
    ---@param e EventData.on_player_setup_blueprint,,
    function(e)
        local player = game.players[e.player_index]
        local mapping = e.mapping.get()
        if not player.is_cursor_empty() then
            local bp = player.cursor_stack
            if bp then register_mapping(bp, mapping) end
        else
            local bp = player.blueprint_to_setup
            if bp then register_mapping(bp, mapping) end
        end
    end)

---@param e EventData.on_selected_entity_changed
local function on_selected_entity_changed(e)
    local player = game.players[e.player_index]
    local selected = player.selected
    local vars = defs.get_vars(player) 

    if vars.selected_uis then
        for _, id in pairs(vars.selected_uis) do
            id.destroy()
        end
        vars.selected_uis = nil
    end

    if not selected or not selected.valid then return end
    
    if selected.name ~= device_name then return end

    local unit_number = selected.unit_number
    ---@cast unit_number -nil
    local device = devices[unit_number]
    if not device then return end
    local wagon = device.wagon
    if not wagon then return end

    local uis = {}
    vars.selected_uis = uis

    local color = { 1, 1, 1 }
    local surface = selected.surface
    local radius = 0.25

    local id = rendering.draw_circle {
        color = color,
        radius = radius,
        surface = surface,
        player = player,
        width = 3,
        target = wagon.position,
        only_in_alt_mode = true
    }
    table.insert(uis, id)
end

tools.on_event(defines.events.on_selected_entity_changed, on_selected_entity_changed)
