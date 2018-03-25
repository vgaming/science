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
	assert(scope == "strength" or scope == "techs" or scope == "units"
		or scope == "income" or scope == "science" or scope == "era" or scope == "total_era")
	wesnoth.set_variable("science_" .. scope .. "_" .. (side or wesnoth.current.side), value)
end

local function get(scope, side)
	assert(scope == "strength" or scope == "techs" or scope == "units"
		or scope == "income" or scope == "science" or scope == "era" or scope == "total_era")
	return wesnoth.get_variable("science_" .. scope .. "_" .. (side or wesnoth.current.side))
end


local function get_strength(side) return get("strength", side) end

local function get_techs(side) return get("techs", side) end

local function get_income(side) return get("income", side) end

local function get_total_era() return get("total_era", 0) end


local function set_techs(value, side) return set("techs", value, side) end

local function set_strength(value, side) return set("strength", value, side) end

local function set_income(value, side) return set("income", value, side) end

local function set_total_era(value) return set("total_era", value, 0) end


local function total_strength(base_strength) return math.ceil(100 - 70 * math.pow(0.9, base_strength)) end

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
wesnoth.wml_actions.event {
	name = "capture",
	first_time_only = false,
	T.lua { code = "science.capture_event()" }
}



local closest_village = {}
local village_tiles = {}
do
	local width, height = wesnoth.get_map_size()

	local function dist(x, y, vill_x, vill_y)
		local dx = math.abs(x - vill_x)
		local dy = math.abs(y - (x % 2) / 2 - vill_y + (vill_x % 2) / 2)
		return dx * dx + dy * dy
	end

	for x = 0, width do
		for y = 0, height do
			local villages = wesnoth.get_villages()
			table.sort(villages, function(a, b)
				return dist(x, y, a[1], a[2]) < dist(x, y, b[1], b[2])
			end)
			local closest = villages[1]
			if closest then
				local village_tile_array = village_tiles[closest[1] .. "," .. closest[2]] or {}
				village_tile_array[#village_tile_array + 1] = { x = x, y = y }
				village_tiles[closest[1] .. "," .. closest[2]] = village_tile_array
			end
			closest_village[x .. "," .. y] = closest
		end
	end
end


local function enemy_territory_xy(x, y, side)
	--print("filtering unit", x, y)
	local village = closest_village[x .. "," .. y]
	return not village or wesnoth.get_village_owner(village[1], village[2]) ~= side
end

local function enemy_territory(unit)
	return enemy_territory_xy(unit.x, unit.y, unit.side)
end

science_enemy_territory = enemy_territory


local function set_leadership(unit)
	local damage = total_strength(get_strength())
	local increase_damage = damage - 100
	local ability = T.leadership {
		id = "science_mod",
		cumulative = true,
		value = increase_damage,
		affect_self = true,
		affect_allies = false,
		T.filter_self { lua_function = "science_enemy_territory" },
	}
	wesnoth.add_modification(unit, "object", {
		id = "science_" .. damage,
		T.effect { apply_to = "remove_ability", T.abilities { ability } },
		T.effect { apply_to = "new_ability", T.abilities { ability } }
	})
end


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

* When you own a village, all nearby hexes are marked as owned by you.

* If you stand on enemy territory, your damage is reduced.
This penalty is severe at game start, but science advances can reduce the difference.

* Each next advance made within same turn costs 50% more.

* If a unit levels up, it will lose all current modifiers and will be considered freshly recruited.
]],
	}
end

local function strength_menu()
	set_strength(get_strength() + 1)
	for _, unit in ipairs(wesnoth.get_units { side = wesnoth.current.side }) do
		set_leadership(unit)
	end
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
			text = "Tactics",
			effect = "Enemy territory penalty -10%",
			image = "misc/blank-hex.png~BLIT(misc/new-battle.png,20,20)",
			base_cost = 10,
			tech_multiplier = 1.1,
			tech_name = "strength",
			func = strength_menu,
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
	local label = [[Territory under cursor: _territory_
Strength on enemy territory: _strength_%
Village income: _village_income_
]]
	label = string.match(label, "^%s*(.-)%s*$")
	label = string.gsub(label, "_[a-z_]+_", {
		_territory_ = enemy_territory_xy(wesnoth.get_variable("x1"),
			wesnoth.get_variable("y1"),
			wesnoth.current.side) and "Enemy" or "Ours",
		_strength_ = total_strength(get_strength()),
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
	for _, unit in ipairs(wesnoth.get_units { side = wesnoth.current.side }) do
		set_leadership(unit)
	end
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
	set_leadership(unit)
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
	set_if_none("strength", 0, side.side)
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
	for _, unit in ipairs(wesnoth.get_units {}) do
		set_leadership(unit)
	end
end

function science.start()
	help_menu(true)
end

function science.capture_event()
	--print("village captured!!!")
	local image = "misc/blank-hex.png~BLIT(misc/dot-white.png~O(60%),30,30)" -- ~SCALE(5,5)
	local event_x1 = wesnoth.get_variable("x1")
	local event_y1 = wesnoth.get_variable("y1")
	local unit = wesnoth.get_unit(event_x1, event_y1)
	local team_name = wesnoth.sides[unit.side].team_name
	for _, tile in ipairs(village_tiles[event_x1 .. "," .. event_y1]) do
		wesnoth.wml_actions.remove_item {
			x = tile.x,
			y = tile.y,
			image = image,
		}
		wesnoth.wml_actions.item {
			x = tile.x,
			y = tile.y,
			image = image,
			team_name = team_name,
			redraw = false,
		}
	end
	--wesnoth.wml_actions.allow_undo {} -- after implementing on_undo event
	wesnoth.wml_actions.redraw {}
end


function science.reload()
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
