local migration = require("__flib__.migration")

local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")
local gui = require("scripts.gui")
local Runtime = require("scripts.runtime")

------------------------------------------------------

local get_vars = tools.get_vars
local device_name = commons.device_name

local gmatch = string.gmatch
local item_splitter = "([^/]+)"

---@type EntityMap<Device>
local devices

---@type Runtime
local devices_runtime

local filterSourceToWireConnectorId = {

    [FilterSource.green_signal] = defines.wire_connector_id.circuit_green,
    [FilterSource.red_signal] = defines.wire_connector_id.circuit_red
}

local detection_area = settings.startup[commons.prefix .. "_detection_area"].value

local wire_connector = defines.wire_connector_id
-----------------------------------------------------

---@param entity LuaEntity
---@param connector1 defines.wire_connector_id
---@param connector2 defines.wire_connector_id
---@return LuaEntity
local function create_cc(entity, connector1, connector2)
    local cc = entity.surface.create_entity {
        name = entity.name .. '-cc',
        position = entity.position,
        force = entity.force,
        create_build_effect_smoke = false
    }
    ---@cast cc -nil
    local cb = cc.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
    if cb.sections_count == 0 then cb.add_section("") end

    local cc_connector = cc.get_wire_connector(connector1, true)
    local device_connector = entity.get_wire_connector(connector2, true)
    cc_connector.connect_to(device_connector, false)
    cc.destructible = false
    return cc
end

---@param device Device
local function create_ccs(device)
    -- cdebug(create_trace, "create_cc:" .. tostring(g.id))
    local entity = device.entity
    device.out_red = create_cc(entity, wire_connector.circuit_red, wire_connector.combinator_output_red)
    device.out_green = create_cc(entity, wire_connector.circuit_green, wire_connector.combinator_output_green)
end

---@param device  Device
local function delete_ccs(device)
    -- cdebug(create_trace, "delete_ccs:" .. tostring(g.id))
    for _, name in pairs({ "out_red", "out_green" }) do
        local cc = device[name]
        if cc and cc.valid then cc.destroy() end
        device[name] = nil
    end
end

---@param e LuaEntity
---@param tags Tags
---@return Device
local function new_device(e, tags)
    ---@type Device
    local device = {
        id = e.unit_number,
        entity = e,
        filter_tick = 0,
        filter_source = FilterSource.none,
        filling_mode = defs.filling_modes.balanced
    }

    create_ccs(device)
    devices_runtime:add(device)

    local cb = e.get_or_create_control_behavior()
    ---@cast cb LuaArithmeticCombinatorControlBehavior
    local flags = cb.parameters.second_constant
    if flags and flags ~= 0 then
        device.filter_source = defs.from_flags("filter_source", flags)
        device.disabled = defs.from_flags("enabled", flags) == 1
        device.filling_mode = defs.from_flags("filling_mode", flags)
    end
    return device
end

---@param e LuaEntity
---@param tags Tags
local function on_controller_built(e, tags)
    if e.name == device_name then
        new_device(e, tags)
        -- cdebug(create_trace, "on_sensor_built:" .. sensor.id)
    end
end

---@param e LuaEntity
local function on_controller_destroyed(e)
    if e.name ~= device_name then return end

    local id = e.unit_number
    ---@cast id -nil

    local device = devices[id]
    if not device then return end

    -- cdebug(create_trace, "on_sor_destroyed:" .. id)
    devices_runtime:remove(device)
    delete_ccs(device)
end

---@param ev EventData.on_entity_cloned
local function on_entity_clone(ev)
    local source = ev.source
    local dest = ev.destination
    local src_id = source.unit_number
    local dst_id = dest.unit_number

    ---@cast src_id -nil
    ---@cast dst_id -nil

    -- cdebug(create_trace, "clone: source=" .. src_id .. ",destination=" .. dst_id)

    if source.name == device_name then
        -- debug(create_trace, "clone sensor")
        local device = devices[src_id]
        if not device then return end

        ---@type Device
        local dst_device = { id = dst_id, entity = dest }
        for _, name in pairs({ "name", "group", "factory", "alerts" }) do
            dest[name] = source[name]
        end

        create_ccs(device)
        local dst_section = (dst_device.out_red.get_or_create_control_behavior() --[[@ as LuaConstantCombinatorControlBehavior]]).get_section(1)
        local src_section = (device.out_red.get_or_create_control_behavior() --[[@ as LuaConstantCombinatorControlBehavior]]).get_section(1)
        ---@cast src_section -nil
        dst_section.filters = src_section.filters

        dst_section = (dst_device.out_green.get_or_create_control_behavior() --[[@ as LuaConstantCombinatorControlBehavior]]).get_section(1)
        src_section = (device.out_green.get_or_create_control_behavior() --[[@ as LuaConstantCombinatorControlBehavior]]).get_section(1)
        ---@cast src_section -nil
        dst_section.filters = src_section.filters

        if dst_id and src_id then
            devices_runtime:remove(device)
            devices_runtime:add(dst_device)
        end
    elseif source.name == device_name .. "-cc" then
        dest.destroy()
        -- cdebug(create_trace, sensor_name_cc)
    end
end

---@param evt EventData.on_built_entity | EventData.on_robot_built_entity | EventData.script_raised_built | EventData.script_raised_revive
local function on_built(evt)
    local e = evt.entity
    if not e or not e.valid then return end

    if e.name == device_name then on_controller_built(e, evt.tags) end
end

---@param evt EventData.on_pre_player_mined_item|EventData.on_entity_died|EventData.script_raised_destroy
local function on_destroyed(evt)
    local entity = evt.entity

    on_controller_destroyed(entity)
end

------------------------------------------------------------------------

local entity_filter = {
    { filter = 'name', name = device_name },
    { filter = "name", name = commons.cc_name }
}

tools.on_event(defines.events.on_built_entity, on_built, entity_filter)
tools.on_event(defines.events.on_robot_built_entity, on_built, entity_filter)
tools.on_event(defines.events.script_raised_built, on_built, entity_filter)
tools.on_event(defines.events.script_raised_revive, on_built, entity_filter)

tools.on_event(defines.events.on_pre_player_mined_item, on_destroyed, entity_filter)
tools.on_event(defines.events.on_robot_pre_mined, on_destroyed, entity_filter)
tools.on_event(defines.events.on_entity_died, on_destroyed, entity_filter)
tools.on_event(defines.events.script_raised_destroy, on_destroyed, entity_filter)

tools.on_event(defines.events.on_entity_cloned, on_entity_clone, {
    { filter = 'name', name = device_name },
    { filter = 'name', name = commons.cc_name }
})

------------------------------------------------------------------------

local function on_load()
    devices_runtime = Runtime.get("Device")
    devices = devices_runtime.map --[[@as EntityMap<Device>]]
end

tools.on_load(on_load)

local function on_init()
    -- debug("on_init")
    ---@type EntityMap<Device>
    storage.controllers = {}
    storage.device_execution_map = {}

    tools.fire_on_load()
end

tools.on_init(on_init)

------------------------------------------------------------------------

---@type table<string, boolean>
local container_filter = {
    ["container"] = true,
    ["logistic-container"] = true,
    ["linked-container"] = true
}

---Get inventory from entity
---@param entity LuaEntity
---@return LuaInventory
---@return defines.relative_gui_type
local function get_inventory(entity)
    ---@type defines.relative_gui_type
    local gui_type
    local inv
    if entity.type == "cargo-wagon" then
        inv, gui_type = entity.get_inventory(defines.inventory.cargo_wagon),
            defines.relative_gui_type.container_gui
    elseif container_filter[entity.type] then
        if (entity.type == "linked-container") then
            inv, gui_type = entity.get_inventory(defines.inventory.chest),
                defines.relative_gui_type.linked_container_gui
        else
            inv, gui_type = entity.get_inventory(defines.inventory.chest),
                defines.relative_gui_type.container_gui
        end
    elseif entity.type == "car" then
        inv, gui_type = entity.get_inventory(defines.inventory.car_trunk),
            defines.relative_gui_type.car_gui
    elseif entity.type == "spider-vehicle" then
        inv, gui_type = entity.get_inventory(defines.inventory.spider_trunk),
            defines.relative_gui_type.spider_vehicle_gui
    elseif entity.type == "character" then
        inv, gui_type = entity.get_inventory(defines.inventory.character_main),
            defines.relative_gui_type.controller_gui
    else
        error("Failure")
    end

    ---@cast inv -nil
    ---@cast gui_type -nil
    return inv, gui_type
end

---Clear wagons filters
---@param device Device
---@param set_bar_to_1 boolean | nil
local function clear_wagons_filters(device, set_bar_to_1)
    local wagons = device.wagons_to_unfilter
    if not wagons then return end

    device.wagons_to_unfilter = nil
    for _, wagon in ipairs(wagons) do
        if wagon.valid then
            local inv = wagon.get_inventory(defines.inventory.cargo_wagon)
            ---@cast inv -nil

            for i = 1, #inv do
                inv.set_filter(i, nil)
            end
            if set_bar_to_1 then
                inv.set_bar(1)
            else
                inv.set_bar()
            end
        end
    end
end

---@param wagon LuaEntity
---@return LuaInventory
local function get_wagon_inventory(wagon)
    local inv = wagon.get_inventory(defines.inventory.cargo_wagon)
    ---@cast inv -nil
    return inv
end

---@param qname string
---@return any
---@return string
local function get_filter(qname)
    local split = gmatch(qname, item_splitter)
    local name = split()
    local quality = split()
    ---@type any
    local filter
    if quality then
        filter = { name = name, quality = quality, comparator = "=" }
    else
        filter = name
    end
    return filter, name
end

---@param device Device
---@param wagons LuaEntity[]
---@param signal_map ItemTable
local function dispatch_slots_in_wagons1(device, wagons, signal_map)
    local wagon_index = 1
    local slot_index = 1
    local current_inv = get_wagon_inventory(wagons[wagon_index])
    local max_slot = #current_inv
    local wagon_count = #wagons

    for qname, count in pairs(signal_map) do
        local filter, name = get_filter(qname)
        local slot = math.ceil(count / prototypes.item[name].stack_size)
        for i = 1, slot do
            current_inv.set_filter(slot_index, filter)
            slot_index = slot_index + 1
            if slot_index > max_slot then
                current_inv.set_bar(#current_inv + 1)
                wagon_index = wagon_index + 1
                if wagon_index > wagon_count then goto end_loop end
                slot_index = 1
                current_inv = get_wagon_inventory(wagons[wagon_index])
                max_slot = #current_inv
            end
        end
    end
    ::end_loop::

    -- Set bar
    if wagon_index <= #wagons then
        for i = wagon_index, #wagons do
            local inv = get_wagon_inventory(wagons[i])
            inv.set_bar(slot_index)
            slot_index = 1
        end
    end
end

---@class device.WagonData
---@field inv LuaInventory
---@field slot_count integer
---@field remaining integer
---@field index integer
---@field slot_per_item table<QName, integer>
---@field slot_counter integer

---@class device.SortedSlots
---@field qname QName
---@field count integer
---@field proto LuaItemPrototype

---@param device Device
---@param wagons LuaEntity[]
---@param signal_map ItemTable
---@return device.WagonData[]?
local function dispatch_slots_balanced(device, wagons, signal_map)
    ---@type device.WagonData[]
    local wagon_data = {}

    for _, wagon in pairs(wagons) do
        local inv = get_wagon_inventory(wagon)
        local count = #inv
        ---@type device.WagonData
        local wd = {
            inv = inv,
            slot_count = count,
            remaining = count,
            index = 1,
            slot_per_item = {},
            slot_counter = 1
        }
        table.insert(wagon_data, wd)
    end
    if #wagon_data == 0 then return nil end

    ---@type device.SortedSlots[]
    local sorted_signals = {}
    for qname, count in pairs(signal_map) do
        local name = gmatch(qname, item_splitter)()
        local proto = prototypes.item[name]
        local slot_count = math.ceil(count / proto.stack_size)
        ---@type device.SortedSlots
        local ss = { qname = qname, count = slot_count, proto = proto }
        table.insert(sorted_signals, ss)
    end

    table.sort(sorted_signals, function(s1, s2) return s1.count > s2.count end)

    local wd_index = 1
    for _, ss in pairs(sorted_signals) do
        local filter = get_filter(ss.qname)
        for _ = 1, ss.count do
            local wd = wagon_data[wd_index]
            if wd.remaining > 0 then
                wd.inv.set_filter(wd.index, filter)
                wd.index = wd.index + 1
                wd.remaining = wd.remaining - 1
            end
            wd_index = wd_index + 1
            if wd_index > #wagon_data then wd_index = 1 end
        end
        for _, wd in pairs(wagon_data) do
            wd.slot_per_item[ss.qname] = wd.index - wd.slot_counter
            wd.slot_counter = wd.index
        end
    end

    for _, wd in ipairs(wagon_data) do
        wd.inv.set_bar(wd.slot_count + 1 - wd.remaining)
    end

    return wagon_data
end

---@param device Device
---@param wagons LuaEntity[]
---@param signal_map ItemTable
local function dispatch_slots_in_wagons3(device, wagons, signal_map)
    ---@type device.WagonData[]
    local wagon_data = {}

    for _, wagon in pairs(wagons) do
        local inv = get_wagon_inventory(wagon)
        local count = #inv
        ---@type device.WagonData
        local wd = { inv = inv, slot_count = count, remaining = count, index = 1 }
        table.insert(wagon_data, wd)
    end

    ---@type device.SortedSlots[]
    local sorted_signals = {}
    for qname, count in pairs(signal_map) do
        local name = gmatch(qname, item_splitter)()
        local proto = prototypes.item[name]
        local slot_count = math.ceil(count / proto.stack_size)
        ---@type device.SortedSlots
        local ss = { qname = qname, count = slot_count, proto = proto }
        table.insert(sorted_signals, ss)
    end

    table.sort(sorted_signals, function(s1, s2)
        if s1.proto.group ~= s2.proto.group then
            return s1.proto.group.order < s2.proto.group.order
        elseif s1.proto.subgroup ~= s2.proto.subgroup then
            return s1.proto.subgroup.order < s2.proto.subgroup.order
        else
            return s1.proto.order < s2.proto.order
        end
    end)

    ---@param wd device.WagonData
    ---@param ss device.SortedSlots
    ---@return integer
    local function apply(wd, ss)
        local count = math.min(wd.remaining, ss.count)
        if count == 0 then return 0 end
        local index = wd.index
        local max_index = index + count
        local inv = wd.inv
        local filter = get_filter(ss.qname)
        while index < max_index do
            inv.set_filter(index, filter)
            index = index + 1
        end
        wd.index = index
        ss.count = ss.count - count
        wd.remaining = wd.remaining - count
        return count
    end

    for _, ss in pairs(sorted_signals) do
        local max_wd = nil
        for _, wd in ipairs(wagon_data) do
            if wd.remaining >= ss.count then
                max_wd = ws
                break
            end
        end
        if max_wd then apply(max_wd, ss) end
        if ss.count > 0 then
            for _, wd in ipairs(wagon_data) do
                if wd.remaining > 0 then apply(wd, ss) end
                if ss.count == 0 then break end
            end
        end
    end
    for _, wd in ipairs(wagon_data) do
        wd.inv.set_bar(wd.slot_count + 1 - wd.remaining)
    end
end

---Compute filter from green input
---@param device Device
local function compute_train_filters(device)
    if not device.entity.valid then return end

    local wagon = device.wagon
    if not wagon or not wagon.valid then return end

    ---@type {[string]:integer}
    local target_content

    if device.filter_source == FilterSource.internal_yatm then
        if not (device.target_content and next(device.target_content)) and remote.interfaces["yet_another_train_manager"] then
            device.target_content = remote.call("yet_another_train_manager",
                "register_transfert_controller", wagon.train.id, device.id, true)
            device.target_content_changed = true
        else
            target_content = device.target_content
        end

        if not device.target_content_changed then
            return
        end

        device.target_content_changed = nil
        if not device.target_content then
            device.target_content = {}
        end
        target_content = tools.table_dup(device.target_content)
    else
        target_content = {}

        local wconnector = filterSourceToWireConnectorId[device.filter_source]
        if not wconnector then return end

        local circuit = device.entity.get_circuit_network(wconnector)
        if not circuit then return end

        local signals = circuit.signals
        if not signals then return end

        for _, signal in pairs(signals) do
            local s = signal.signal
            if not s.type and signal.count > 0 then
                local qname = s.name
                ---@cast qname -nil
                local quality = s.quality
                if quality and quality ~= "normal" then qname = qname .. "/" .. quality end
                target_content[qname] = signal.count
            end
        end
        device.target_content = target_content
    end

    if not next(target_content) then
        device.filter_counts = {}
        return
    end

    local train = wagon.train
    if not train then return end

    clear_wagons_filters(device, true)

    -- Remove content
    local wagons = train.cargo_wagons
    local train_content = train.get_contents()
    for i = 1, #wagons do
        wagons[i].clear_items_inside()
    end

    for _, item in pairs(train_content) do
        local qname = item.name
        local quality = item.quality
        if quality and quality ~= "normal" then qname = qname .. "/" .. quality end

        local current = target_content[qname]
        local amount = item.count
        if not current or amount > current then
            target_content[qname] = amount
        end
    end

    local wagon_data
    -- Set slots
    if device.filling_mode == defs.filling_modes.balanced then
        wagon_data = dispatch_slots_balanced(device, wagons, target_content)
    elseif device.filling_mode == defs.filling_modes.packed then
        dispatch_slots_in_wagons1(device, wagons, target_content)
    elseif device.filling_mode == defs.filling_modes.order then
        dispatch_slots_in_wagons3(device, wagons, target_content)
    else
        dispatch_slots_balanced(device, wagons, target_content)
    end

    if wagon_data then
        -- content back
        for _, item in pairs(train_content) do
            local name = item.name
            local count = item.count
            local n = #wagon_data
            local wcount = math.floor(count / n)
            local sum = 0
            for i = 1, n do
                local wd = wagon_data[i]
                local real = wd.inv.insert { name = name, count = wcount, quality = item.quality }
                sum = sum + real
            end
            if sum < count then
                for i = 1, n do
                    local wd = wagon_data[i]
                    local real = wd.inv.insert { name = name, count = sum, quality = item.quality }
                    sum = sum - real
                    if sum == 0 then break end
                end
            end
        end
    else
        -- content back
        for _, item in pairs(train_content) do
            local name = item.name
            local count = item.count
            local remaining = count
            for _, w in pairs(wagons) do
                local inv = get_wagon_inventory(w)
                local real = inv.insert { name = name, count = remaining, quality = item.quality }
                remaining = remaining - real
                if remaining == 0 then break end
            end
            if remaining > 0 then
                local w = wagons[1]
                w.surface.spill_item_stack { position = w.position,
                    stack = { name = name, count = remaining, quality = item.quality },
                    enable_looted = false,
                    force = device.wagon.force --[[@as LuaForce]] }
            end
        end
    end

    device.wagons_to_unfilter = wagons
end

---Get filters from inventory
---@param inv LuaInventory
---@return FilterTable
local function get_filters(inv)
    ---@type FilterTable
    local filter_counts = {}
    local max = #inv

    for index = 1, max do
        local item = inv.get_filter(index)
        if item then
            local qname = item.name
            ---@cast qname -nil
            local quality = item.quality
            if quality and quality ~= "normal" then qname = qname .. "/" .. quality end
            filter_counts[qname] = (filter_counts[qname] or 0) + 1
        end
    end

    return filter_counts
end

---@param device Device
local function clear_signal(device)
    local section = (device.out_red.get_or_create_control_behavior() --[[@ as LuaConstantCombinatorControlBehavior]]).get_section(1)
    section.filters = {}

    section = (device.out_green.get_or_create_control_behavior() --[[@ as LuaConstantCombinatorControlBehavior]]).get_section(1)
    section.filters = {}

    device.idle_count = commons.idle_count
end

---@param device Device
---@return LuaEntity[] | nil
local function find_inserters(device)
    ---@type LuaEntity
    local wagon = device.wagon

    if not (wagon and wagon.valid) then
        device.inserters = nil
        device.pickup_map = nil
        return nil
    end

    local proto = wagon.prototype
    local orientation = wagon.orientation
    local pos = wagon.position
    local area
    local tile_width = proto.tile_width / 2
    local tile_height = proto.tile_height / 2

    local collision_box
    local margin = 3
    local xmargin = 3
    if orientation == 0.25 or orientation == 0.75 then
        collision_box = {
            left_top = { x = pos.x - tile_height, y = pos.y - tile_width },
            right_bottom = { x = pos.x + tile_height, y = pos.y + tile_height }
        }
        area = {
            {
                collision_box.left_top.x - xmargin,
                collision_box.left_top.y - margin
            },
            {
                collision_box.right_bottom.x + xmargin,
                collision_box.right_bottom.y + margin
            }
        }
    else
        collision_box = {
            left_top = { x = pos.x - tile_width, y = pos.y - tile_height },
            right_bottom = { x = pos.x + tile_width, y = pos.y + tile_height }
        }
        area = {
            {
                collision_box.left_top.x - margin,
                collision_box.left_top.y - xmargin
            },
            {
                collision_box.right_bottom.x + margin,
                collision_box.right_bottom.y + xmargin
            }
        }
    end

    device.wagon_box = collision_box
    local found = wagon.surface.find_entities_filtered {
        area = area,
        type = "inserter"
    }
    local inserters = {}

    --- @type ItemCount
    local transfert_size = 0
    local is_filtered = false
    local pickup_map = {}
    for _, inserter in pairs(found) do
        local drop_position = inserter.drop_position
        if drop_position.x >= collision_box.left_top.x - 1 and drop_position.x <=
            collision_box.right_bottom.x + 1 and drop_position.y >=
            collision_box.left_top.y - 1 and drop_position.y <=
            collision_box.right_bottom.y + 1 then
            table.insert(inserters, inserter)
            transfert_size = transfert_size +
                inserter.inserter_target_pickup_count
            is_filtered = inserter.filter_slot_count > 0
            local pickup = inserter.pickup_target
            if pickup then pickup_map[pickup.unit_number] = pickup end
        end
    end

    device.pickup_map = pickup_map
    device.transfert_size = transfert_size
    device.inserters = inserters
    device.inserter_tick = game.tick + 300
    device.is_filtered = is_filtered
    return inserters
end

---Unstuck inserters
---@param device Device
---@param inserters LuaEntity[]
---@param request_map ItemTable
local function clear_inserters_internal(device, inserters, request_map)
    if not inserters then return end

    ---@type table<string, integer> | nil
    local stuck
    for _, inserter in ipairs(inserters) do
        if not inserter.valid then
            device.inserter_tick = 0
        else
            local stack = inserter.held_stack
            if stack and stack.valid_for_read then
                local qname = stack.name
                if qname then
                    local quality = stack.quality.name
                    if quality ~= "normal" then qname = qname .. "/" .. quality end
                    if not request_map[qname] then
                        if not stuck then stuck = {} end
                        stuck[qname] = (stuck[qname] or 0) + stack.count
                        stack.clear()
                    end
                end
            end
        end
    end

    if stuck then
        local first = inserters[1]
        local position = first.pickup_position
        local containers = first.surface.find_entities_filtered {
            position = position,
            type = { "container", "logistic-container", "linked-container", "infinity-container" }
        }
        if #containers >= 1 then
            local container = containers[1]
            local inv = container.get_inventory(defines.inventory.chest)
            ---@cast inv -nil
            for qname, count in pairs(stuck) do
                local split = gmatch(qname, item_splitter)
                local name = split()
                local quality = split()
                ---@cast count -integer +uint
                inv.insert({ name = name, count = count, quality = quality })
            end
        end
    end
end

---@param device Device
---@param request_map table<Item, ItemCount>
local function clear_inserters(device, request_map)
    local inserters = device.inserters
    if not inserters or device.inserter_tick < game.tick then
        inserters = find_inserters(device)
        if not inserters then return end
    end

    clear_inserters_internal(device, inserters, request_map)
end

---@param device Device
local function clear_all_inserters(device)
    if not device.inserters then return end

    clear_inserters_internal(device, device.inserters, {})
end

---@param device Device
local function process_device(device)
    if device.filter_reset then
        clear_wagons_filters(device, true)
        clear_signal(device)
        clear_all_inserters(device)
        device.filter_counts = nil
        device.filter_reset = false
        device.unloading = nil
        device.idle_count = nil
        device.target_content = nil
        device.target_content_changed = true
    end

    if device.disabled then return end
    if device.unloading then return end

    local idle_count = device.idle_count
    if idle_count then
        idle_count = idle_count - 1
        if idle_count > 0 then
            device.idle_count = idle_count
            return
        end
        device.idle_count = nil
    end

    local entity = device.entity
    local wagon = device.wagon
    local wagon_pos = device.wagon_pos
    ---@cast wagon_pos -nil

    local pos = entity.position
    local inv

    if not wagon or not wagon.valid or wagon.position.x ~= wagon_pos.x or
        wagon.position.y ~= wagon_pos.y or math.abs(wagon.speed) > 0 or
        (wagon.train.manual_mode or not wagon.train.station) then
        local wagons = entity.surface.find_entities_filtered {
            area = { { pos.x - detection_area, pos.y - detection_area }, { pos.x + detection_area, pos.y + detection_area } },
            type = "cargo-wagon"
        }

        if wagon and wagons[1] == wagon then
            inv = get_inventory(wagon)
            goto skip
        end

        device.wagon = nil
        clear_wagons_filters(device)

        if #wagons == 0 then
            clear_signal(device)
            clear_all_inserters(device)
            device.target_content = nil
            return
        end

        if #wagons > 1 then
            local dx1 = wagons[1].position.x - pos.x
            local dy1 = wagons[1].position.y - pos.y

            local dx2 = wagons[2].position.x - pos.x
            local dy2 = wagons[2].position.y - pos.y

            local d1 = dx1 * dx1 + dy1 * dy1
            local d2 = dx2 * dx2 + dy2 * dy2

            local invert = false
            local iw = 1
            if d1 < d2 - 0.1 then
                iw = 1
            elseif d1 > d2 + 0.1 then
                iw = 2
            elseif math.abs(wagons[1].position.x - wagons[2].position.x) < 0.1 then
                if wagons[1].position.y < wagons[2].position.y then
                    iw = 1
                else
                    iw = 2
                end
                invert = pos.x > wagons[1].position.x
            else
                if wagons[1].position.x < wagons[2].position.x then
                    iw = 1
                else
                    iw = 2
                end
                invert = pos.y < wagons[1].position.y
            end
            if invert then
                if iw == 1 then
                    iw = 2
                else
                    iw = 1
                end
            end
            wagon = wagons[iw]
        else
            wagon = wagons[1]
        end

        if not wagon or not wagon.valid or math.abs(wagon.speed) > 0 and
            (not wagon.train.manual_mode and not wagon.train.station) then
            clear_signal(device)
            clear_all_inserters(device)
            return
        end

        inv = get_inventory(wagon)
        if not inv.supports_filters() then
            clear_signal(device)
            return
        end

        device.wagon = wagon
        device.wagon_pos = wagon.position
        device.filter_counts = nil
        find_inserters(device)
    else
        inv = get_inventory(wagon)
    end

    ::skip::

    local gametick = game.tick
    local filter_counts = device.filter_counts
    if not filter_counts
        or ((device.filter_tick < gametick) and (device.wagon.train.manual_mode or not next(filter_counts)))
        or device.target_content == nil then
        if device.filter_source ~= FilterSource.none then
            compute_train_filters(device)
        else
            if not (device.target_content and next(device.target_content))
                and remote.interfaces["yet_another_train_manager"] then
                device.target_content = remote.call("yet_another_train_manager",
                    "register_transfert_controller", wagon.train.id, device.id, false)
                device.target_content_changed = true
            end
        end
        filter_counts = get_filters(inv)
        device.filter_counts = filter_counts
        device.filter_tick = gametick + 120
        if not next(filter_counts) then return end
        if not device.target_content then
            device.target_content = device.filter_counts
        end
    end

    local base_content = inv.get_contents()
    ---@type FilterTable
    local content = {}
    for _, item in pairs(base_content) do
        local qname = item.name
        local quality = item.quality
        if quality and quality ~= "normal" then qname = qname .. "/" .. quality end
        content[qname] = item.count
    end

    ---@type ItemTable
    local requested_map = {}

    local delivery_content = device.target_content
    if not device.target_content then
        return
    end
    for qname, count in pairs(filter_counts) do
        if delivery_content[qname] then
            local item_count

            local name = gmatch(qname, item_splitter)()
            local proto = prototypes.item[name]
            if proto then
                local stack_size = proto.stack_size
                item_count = stack_size * count

                local inv_count = content[qname]
                if inv_count then item_count = item_count - inv_count end
                if item_count > 0 then requested_map[qname] = item_count end
            end
        end
    end

    if next(requested_map) then
        local filter_set = {}
        local index = 1
        ---@type Item
        for qname, count in pairs(requested_map) do
            local split = gmatch(qname, item_splitter)
            local name = split()
            local quality = split()
            if not quality then
                table.insert(filter_set, {
                    value = name,
                    min = count
                })
            else
                table.insert(filter_set, {
                    value = { name = name, quality = quality, comparator = "=" },
                    min = count
                })
            end
            index = index + 1
        end

        local red_section = (device.out_red.get_or_create_control_behavior() --[[@ as LuaConstantCombinatorControlBehavior]]).get_section(1)
        red_section.filters = filter_set

        local inserter_clear_map = requested_map
        local green_section = (device.out_green.get_or_create_control_behavior() --[[@ as LuaConstantCombinatorControlBehavior]]).get_section(1)
        green_section.filters = filter_set
        inserter_clear_map = requested_map

        clear_inserters(device, inserter_clear_map)
    else
        clear_signal(device)
        clear_all_inserters(device)
    end
end

local function remove_surface(surface_index)
    local to_delete = {}
    for id, device in pairs(devices_runtime.map) do
        if not device.entity.valid or device.entity.surface_index ==
            surface_index then
            to_delete[id] = device
        end
    end
    for id, _ in pairs(to_delete) do devices_runtime:remove(id) end
end

tools.on_event(defines.events.on_pre_surface_deleted, --
    ---@param e EventData.on_pre_surface_deleted
    function(e) remove_surface(e.surface_index) end)

tools.on_event(defines.events.on_surface_cleared, --
    ---@param e EventData.on_surface_cleared
    function(e) remove_surface(e.surface_index) end)

Runtime.register {
    name = "Device",
    global_name = "controllers",
    process = process_device,
    ntick = 5
}

remote.add_interface("transfert_controller", {

    ---@param main_id integer
    ---@param secondary_ids table<integer, boolean>
    ---@param delivery_content table<string, integer>
    ---@return boolean
    fire_train_arrived = function(main_id, secondary_ids, delivery_content)
        local device = devices[main_id]
        if not device then return false end
        if not device.entity.valid then return false end
        if not delivery_content then
            device.unloading = true
            return false
        end
        device.unloading = nil
        device.idle_count = nil
        device.target_content = delivery_content
        device.target_content_changed = true
        process_device(device)
        if secondary_ids then
            for id, _ in pairs(secondary_ids) do
                local secondary = devices[id]
                if not secondary then return false end
                if not secondary.entity.valid then return false end
                secondary.target_content = delivery_content
                secondary.target_content_changed = true
                secondary.idle_count = nil
                process_device(secondary)
            end
        end
        return true
    end,
    ---@param main_id integer
    fire_train_leave = function(main_id)
        local device = devices[main_id]
        if not device then return false end
        if not device.entity.valid then return false end

        device.wagon = nil
        clear_wagons_filters(device)

        clear_signal(device)
        clear_all_inserters(device)
        device.target_content = nil
        device.target_content_changed = nil
    end

})


local function migration_2_0_0(data)

    if not devices_runtime.map then
        return
    end

    ---@type Device
    for _, device in pairs(devices_runtime.map) do
        if device.target_content then
            local to_remove = {}
            for qname in pairs(device.target_content) do
                local split = gmatch(qname, item_splitter)
                local name = split()
                if not prototypes.item[name] then
                    to_remove[name] = true
                end
            end
            for name in pairs(to_remove) do
                device.target_content[name] = nil
            end
        end 
    end

end

local function migration_1_0_1(data)
    if not devices_runtime.map then
        return
    end

    for _, device in pairs(devices_runtime.map) do
        if device.delivery_content then
            ---@diagnostic disable-next-line: inject-field
            device.target_content = device.delivery_content
        end
        ---@diagnostic disable-next-line: inject-field
        device.previous_train_content = nil
    end
end


local migrations_table = {
    ["1.0.1"] = migration_1_0_1,
    ["2.0.0"] = migration_2_0_0

}

local function on_configuration_changed(data)
    Runtime.initialize()
    migration.on_config_changed(data, migrations_table)
end

script.on_configuration_changed(on_configuration_changed)
