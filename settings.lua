local commons = require("scripts.commons")

data:extend({

    {
        type = "int-setting",
        name = commons.prefix .. "_detection_area",
		setting_type = "startup",
        default_value = 4,
        min_value = 2,
        max_value = 10,
		order="ab"
    }
})

--[[
data:extend({
    {
        type = "string-setting",
        name = "stm_fuel_stop_prefix",
        setting_type = "startup",
        default_value = "FuelStop",
		order="aa"
    },
    {
        type = "int-setting",
        name = "stm_fuel_min",
        setting_type = "startup",
        default_value = 120,
		order="ab"
    },
	{
		type = "int-setting",
		name = "stm_processed_interval",
		setting_type = "startup",
		default_value = 30,
		order="ac"
	},
	{
		type = "int-setting",
		name = "stm_processed_count",
		setting_type = "startup",
		default_value = 20,
		order="ad"
    }

})
]]--
