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
	wesnoth.set_variable("science_" .. scope .. "_" .. (side or wesnoth.current.side), value)
end

local function get(scope, side)
	return wesnoth.get_variable("science_" .. scope .. "_" .. (side or wesnoth.current.side))
end

local function get_strength(side) return get("strength", side) end

local function get_techs(side) return get("techs", side) end

local function get_income(side) return get("income", side) end

local function set_techs(value, side) return set("techs", value, side) end

local function set_strength(value, side) return set("strength", value, side) end

local function set_income(value, side) return set("income", value, side) end

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


local function set_ability(unit)
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


local function help_menu(for_all_sides)
	wesnoth.wml_actions.message {
		speaker = "narrator",
		side_for = for_all_sides == nil and wesnoth.current.side or nil,
		message = [[<b>ScienceMod</b>

* When you own a village, all nearby hexes are marked as owned by you.

* Units standing on own territory always have 100% damage modifier.
If you stand on enemy territory, your damage is reduced.
This penalty is severe at game start, but science advances can reduce the difference.

* Each next advance made within same turn costs 50% more.
Additionally, "Village Income" becomes 2 times more costy for each advance.

]],
	}
end

local function strength_menu()
	set_strength(get_strength() + 1)
	for _, unit in ipairs(wesnoth.get_units { side = wesnoth.current.side }) do
		set_ability(unit)
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
--		spacer_left = "\n",
--		spacer_right = "\n",
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
	else
		return false
	end
end

function science.menu_item()
	local side = wesnoth.sides[wesnoth.current.side]
	local options = {
		{
			text = "Economy research: village income +1",
			image = "items/gold-coins-small.png~CROP(18,18,36,36)",
			cost = math.floor(40 * math.pow(2, get_income())),
			cost_comment = " (20 * 2^x * turn_modifier)",
			func = village_income_menu,
		},
		{
			text = "Weaponry research: new recruit",
			image = "misc/flag-white.png",
			--image = "misc/flag-red.png",
			cost = 5,
			cost_comment = " (20 * turn_modifier)",
			func = recruit_menu,
		},
		{
			text = "Tactics research: enemy territory penalty -10%",
			image = "misc/new-battle.png",
			--image = "items/gohere.png",
			cost = 8,
			cost_comment = " (20 * turn_modifier)",
			func = strength_menu,
		},
		{
			text = "Help",
			image = "misc/qmark.png~SCALE(24,24)",
			func = help_menu,
		},
	}
	local cost_multiplier = math.pow(1.5, get_techs())
	for _, opt in ipairs(options) do
		if opt.cost then
			opt.cost = math.floor(opt.cost * cost_multiplier)
		end
		if opt.cost and side.gold >= opt.cost then
			opt.text = opt.text .. " | <span color='#FFE680'>cost " .. opt.cost .. "</span>"
		elseif opt.cost then
			opt.text = opt.text .. " | <span color='#FF0000'>cost " .. opt.cost .. "</span>"
		end
	end
	local label = [[<b>Science Mod</b>

Territory under cursor: _territory_
Strength on enemy territory: _strength_%
Village income: _village_income_
]]
	label = string.gsub(label, "_[a-z_]+_", {
		_territory_ = enemy_territory_xy(wesnoth.get_variable("x1"),
			wesnoth.get_variable("y1"),
			wesnoth.current.side) and "Enemy" or "Ours",
		_strength_ = total_strength(get_strength()),
		_village_income_ = side.village_gold,
	})
	local dialog_result = science.show_dialog {
		spacer_left = "\n",
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
	end
end


function science.turn_refresh()
	set_techs(0)
end

function science.side_turn_end()
	for _, unit in ipairs(wesnoth.get_units { side = wesnoth.current.side }) do
		set_ability(unit)
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
	set_ability(unit)
end

function science.prestart()
	for _, side in ipairs(wesnoth.sides) do
		set_if_none("strength", 0, side.side)
		set_if_none("income", 0, side.side)
		set_if_none("units", 0, side.side)
		set_if_none("techs", 0, side.side)
	end
	if not wesnoth.get_variable("science_recruit_init") then
		wesnoth.set_variable("science_recruit_init", true)
		for _, side in ipairs(wesnoth.sides) do
			if side.controller ~= "ai" and side.controller ~= "network_ai" then
				wesnoth.set_variable("science_is_human_" .. side.side, true)
				wesnoth.set_variable("science_hidden_" .. side.side, table.concat(side.recruit, ","))
				side.recruit = { "Peasant" }
			end
		end
	end
	for _, unit in ipairs(wesnoth.get_units {}) do
		set_ability(unit)
	end
	for _, side in ipairs(wesnoth.sides) do
		side.village_gold = side.village_gold - 0
		side.gold = side.gold + 25
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
	--wesnoth.wml_actions.allow_undo {} -- TODO: on_undo event
	wesnoth.wml_actions.redraw {}
end


function science.reload()
	print("reloading...")
	wesnoth.dofile("~add-ons/science/lua/utils.lua")
	wesnoth.dofile("~add-ons/science/lua/dialog.lua")
	wesnoth.dofile("~add-ons/science/lua/main.lua")
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
end

-- >>
