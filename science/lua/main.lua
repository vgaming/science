-- << science/main.lua

local science = science
local wesnoth = wesnoth
local ipairs = ipairs
local math = math
local string = string
local table = table
local T = wesnoth.require("lua/helper.lua").set_wml_tag_metatable {}

print("loading science/main.lua ...")

local function set(scope, value, side)
	assert(scope == "techs" or scope == "units"
		or scope == "income" or scope == "science" or scope == "era" or scope == "total_era")
	wesnoth.set_variable("science_" .. scope .. "_" .. (side or wesnoth.current.side), value)
end

local function get(scope, side)
	assert(scope == "techs" or scope == "units"
		or scope == "income" or scope == "science" or scope == "era" or scope == "total_era")
	return wesnoth.get_variable("science_" .. scope .. "_" .. (side or wesnoth.current.side))
end


local function get_techs(side) return get("techs", side) end

local function get_income(side) return get("income", side) end

local function get_total_era() return get("total_era", 0) end


local function set_techs(value, side) return set("techs", value, side) end

local function set_income(value, side) return set("income", value, side) end

local function set_total_era(value) return set("total_era", value, 0) end


local function set_if_none(scope, value, side)
	local name = "science_" .. scope .. "_" .. side
	if not wesnoth.get_variable(name) then
		wesnoth.set_variable(name, value)
	end
end


wesnoth.wml_actions.set_menu_item {
	id = "science_mod",
	description = "Science Mod",
	T.command {
		T.lua {
			code = "science.menu_item()"
		}
	}
}

wesnoth.wml_actions.event {
	id = "science_turn_refresh",
	name = "turn refresh",
	first_time_only = false,
	T.lua { code = "science.turn_refresh()" }
}
wesnoth.wml_actions.event {
	id = "science_prerecruit",
	name = "prerecruit",
	first_time_only = false,
	T.lua { code = "science.prerecruit()" }
}
wesnoth.wml_actions.event {
	id = "science_post_advance",
	name = "post advance",
	first_time_only = false,
	T.lua { code = "science.post_advance_event()" }
}
wesnoth.wml_actions.event {
	name = "side turn end",
	first_time_only = false,
	T.lua { code = "science.side_turn_end()" }
}
wesnoth.wml_actions.event {
	name = "prestart",
	first_time_only = false,
	T.lua { code = "science.prestart()" }
}
wesnoth.wml_actions.event {
	name = "start",
	first_time_only = false,
	T.lua { code = "science.start()" }
}


local function set_era_modifier(unit, diff, is_reset)
	if is_reset then
		wesnoth.wml_actions.remove_object {
			id = unit.id,
			object_id = "science_era_modifier",
		}
	end
	local increase = math.floor(100 * math.pow(10 / 9, diff) - 100)
	local was_hitpoints = unit.hitpoints
	wesnoth.add_modification(unit, "object", {
		id = "science_era_modifier",
		take_only_once = false,
		T.effect { apply_to = "attack", increase_damage = increase .. "%" },
		T.effect { apply_to = "hitpoints", increase_total = increase .. "%", heal_full = is_reset }, --
	})
	print("advancing unit", unit.id, unit.name, increase,
		"is_reset", is_reset, "was_hp", was_hitpoints, "hp", unit.hitpoints)
end


local function help_menu(for_all_sides)
	wesnoth.wml_actions.message {
		speaker = "narrator",
		side_for = for_all_sides == nil and wesnoth.current.side or nil,
		message = [[<b>ScienceMod</b>

* To access Science, MOUSE RIGHT-CLICK anywhere on map when it's your turn.

* Each next Science advance made within same turn costs 50% more.

* Negative effects are stripped off from units when they level-up.

... have fun!
]],
	}
end


local function village_income_menu()
	set_income(get_income() + 1)
	local side = wesnoth.sides[wesnoth.current.side]
	side.village_gold = side.village_gold + 1
end

local function recruit_menu()
	local side = wesnoth.sides[wesnoth.current.side]
	local hidden_units = science.split_comma(wesnoth.get_variable("science_hidden_" .. side.side))
	for i, ut_string in ipairs(hidden_units) do
		local unit = wesnoth.unit_types[ut_string]
		hidden_units[i] = {
			text = unit.name,
			image = unit.__cfg.image or "misc/blank-hex.png",
			id = unit.id,
		}
	end
	local result = science.show_dialog {
		label = "Pick recruit",
		options = hidden_units,
	}
	if result.is_ok then
		local old_recruits = side.recruit
		old_recruits[#old_recruits + 1] = result.id
		side.recruit = old_recruits
		local new_hidden = {}
		for _, ut in ipairs(hidden_units) do
			if ut.id ~= result.id then
				new_hidden[#new_hidden + 1] = ut.id
			end
		end
		wesnoth.set_variable("science_hidden_" .. side.side, table.concat(new_hidden, ","))
		set("units", get("units") + 1)
	else
		return false
	end
end


local function science_menu()
	set("science", get("science") + 1)
end


local function era_menu()
	set("era", get("era") + 1)
	set_total_era(get_total_era() + 1)
	for _, unit in ipairs(wesnoth.get_units { canrecruit = false }) do
		set_era_modifier(unit, -1, false)
	end
end


function science.menu_item()
	local side = wesnoth.sides[wesnoth.current.side]
	local options = {
		{
			text = "Economy",
			effect = "Village income +1",
			image = "items/gold-coins-small.png~CROP(7,0,65,72)",
			base_cost = 40,
			tech_multiplier = 2.0,
			tech_name = "income",
			func = village_income_menu,
		},
		{
			text = "Recruitment",
			effect = "New recruit",
			image = "misc/blank-hex.png~BLIT(misc/flag-white.png,20,20)",
			--image = "misc/flag-red.png",
			base_cost = 10,
			tech_multiplier = 1.1,
			tech_name = "units",
			func = recruit_menu,
		},
		{
			text = "New Era",
			effect = "All non-leaders in game -10% damage, -10% hitpoints\n"
				.. "All future enemy recruits -10% damage, -10% hitpoints,\n"
				.. "All your future recruits +10% damage, +10% hitpoints",
			image = "misc/blank-hex.png~BLIT(misc/new-battle.png,20,20)",
			base_cost = 40,
			tech_multiplier = 2.0,
			tech_name = "era",
			func = era_menu,
		},
		{
			text = "Fundamental research",
			effect = "Reduces future technology cost",
			image = "icons/potion_green_small.png~SWAP(red,blue,green)",
			base_cost = 10,
			tech_multiplier = 0.9,
			tech_name = "science",
			func = science_menu
		},
		{
			text = "Help",
			image = "misc/blank-hex.png~BLIT(misc/qmark.png~SCALE(24,24),20,20)",
			func = help_menu,
		},
	}
	local turn_multiplier = math.pow(1.5, get_techs())
	local science_multiplier = 1.0
	for _, opt in ipairs(options) do
		if opt.tech_multiplier then
			science_multiplier = science_multiplier * math.pow(opt.tech_multiplier, get(opt.tech_name))
		end
	end

	for _, opt in ipairs(options) do
		if opt.tech_name and get(opt.tech_name) > 0 then
			opt.text = string.format("%s (%s)", opt.text, get(opt.tech_name))
		end
		if opt.base_cost then
			opt.base_cost = opt.base_cost * science_multiplier
			opt.cost = math.floor(opt.base_cost * turn_multiplier)
			opt.base_cost = math.floor(opt.base_cost)
		end
		if opt.cost then
			local tech_mult_color = opt.tech_multiplier and opt.tech_multiplier > 1.0 and "pink" or "green"
			local tech_mult_string = (opt.tech_multiplier == nil or opt.tech_multiplier == 1.0) and ""
				or string.format(", <span color='%s'>future technology cost x%.1f</span>",
				tech_mult_color,
				opt.tech_multiplier)
			local base_cost_string = turn_multiplier > 1
				and string.format(" (base %s)", opt.base_cost)
				or ""
			local cost_color = side.gold >= opt.cost and "FFE680" or "FF0000"
			opt.text = string.format('%s\n<span>%s</span>\n<span color="#%s">cost %s%s</span>%s',
				opt.text,
				opt.effect,
				cost_color,
				opt.cost,
				base_cost_string,
				tech_mult_string)
		end
	end
	local label = [[]]
	label = string.match(label, "^%s*(.-)%s*$")
	label = string.gsub(label, "_[a-z_]+_", {
		_village_income_ = side.village_gold,
	})
	local dialog_result = science.show_dialog {
		spacer_left = "",
		spacer_right = "\n",
		label = label,
		options = options,
	}
	if dialog_result.is_ok then
		local opt = options[dialog_result.index]
		if opt.cost and side.gold < opt.cost then
			wesnoth.wml_actions.message {
				speaker = "narrator",
				message = "not enough gold",
				side_for = wesnoth.current.side,
			}
			print("not enouth gold")
		else
			local func_result = opt.func()
			if science.i_am_observer() and opt.cost then
				wesnoth.wml_actions.print {
					text = side.name .. " has done " .. opt.text,
					duration = 300,
					size = 26,
					red = 255,
					green = 255,
					blue = 255,
				}
			end
			if opt.cost and func_result ~= false then
				side.gold = side.gold - opt.cost
				set_techs(get_techs() + 1)
			end
		end
		if wesnoth.compare_versions(wesnoth.game_config.version, ">=", "1.13") then
			science.menu_item()
		end
	end
end


function science.turn_refresh()
	set_techs(0)
end

function science.side_turn_end()
	local is_human = wesnoth.get_variable("science_is_human_" .. wesnoth.current.side)
	if wesnoth.current.turn == 1 and get_techs() == 0 and is_human then
		wesnoth.wml_actions.message {
			message = "You MUST use Science at turn 1.\n"
				.. "If you didn't, you probably just don't know the rules.\n\n"
				.. "Please MOUSE RIGHT-CLICK anywhere on map!",
		}
		wesnoth.wml_actions.kill {
			side = wesnoth.current.side
		}
	end
end


function science.prerecruit()
	local unit = wesnoth.get_unit(wesnoth.get_variable("x1"), wesnoth.get_variable("y1"))
	set_era_modifier(unit, get("era") * 2 - get_total_era(), true)
end

function science.post_advance_event()
	print("advancing unit, era", get("era") * 2 - get_total_era())
	local event_x1 = wesnoth.get_variable("x1")
	local event_y1 = wesnoth.get_variable("y1")
	local unit = wesnoth.get_unit(event_x1, event_y1)
	set_era_modifier(unit, get("era") * 2 - get_total_era(), true)
end


set_if_none("total_era", 0, 0)
for _, side in ipairs(wesnoth.sides) do
	set_if_none("income", 0, side.side)
	set_if_none("units", 0, side.side)
	set_if_none("techs", 0, side.side)
	set_if_none("science", 0, side.side)
	set_if_none("era", 0, side.side)
end
function science.prestart()
	for _, side in ipairs(wesnoth.sides) do
		if side.controller ~= "ai" and side.controller ~= "network_ai" then
			wesnoth.set_variable("science_is_human_" .. side.side, true)
			wesnoth.set_variable("science_hidden_" .. side.side, table.concat(side.recruit, ","))
			side.recruit = { "Woodsman" }
			side.village_gold = side.village_gold - 0
			side.gold = side.gold + 25
		end
	end
end

function science.start()
	help_menu(true)
end


function science.reload()
	help_menu(true)
	print("reloading...")
	wesnoth.dofile("~add-ons/science/lua/utils.lua")
	wesnoth.dofile("~add-ons/science/lua/dialog.lua")
	wesnoth.dofile("~add-ons/science/lua/main.lua")
	science = _G.science
	wesnoth.wml_actions.clear_menu_item {
		id = "deleteme",
	}
	wesnoth.wml_actions.set_menu_item {
		id = "deleteme",
		description = "reload()",
		T.command {
			T.lua {
				code = "science.reload()"
			}
		}
	}
	science.menu_item()
end

-- >>
