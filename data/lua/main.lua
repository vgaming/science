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

local function total_strength(base_strength) return 30 + 10 * base_strength end

local function set_if_none(scope, value, side)
	local name = "science_" .. scope .. "_" .. side
	if not wesnoth.get_variable(name) then
		wesnoth.set_variable(name, value)
	end
end

if not wesnoth.get_variable("science_recruit_init") then
	wesnoth.set_variable("science_recruit_init", true)
	for _, side in ipairs(wesnoth.sides) do
		wesnoth.set_variable("science_recruits_" .. side.side, table.concat(side.recruit, ","))
		side.recruit = { "Peasant" }
	end
end



wesnoth.wml_actions.clear_menu_item {
	id = "science_mod",
}
wesnoth.wml_actions.set_menu_item {
	id = "science_mod",
	description = "Science Mod",
	T.command {
		T.lua {
			code = "science.menu_item()"
		}
	}
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
	T.lua { code = "science.side_turn_end()" }
}
wesnoth.wml_actions.event {
	name = "prestart",
	T.lua { code = "science.prestart()" }
}



local closest_villages = {}
do
	local width, height = wesnoth.get_map_size()

	local function dist(x, y, vill)
		local dx = math.abs(x - vill[1])
		local dy = math.abs(y - vill[2])
		return dx * dx + dy * dy
	end

	for x = 0, width do
		for y = 0, height do
			local villages = wesnoth.get_villages()
			table.sort(villages, function(a, b)
				return dist(x, y, a) < dist(x, y, b)
			end)
			closest_villages[x .. "," .. y] = villages
		end
	end
end


local function enemy_territory_xy(x, y, side)
	print("filtering unit", x, y)
	for _, village in ipairs(closest_villages[x .. "," .. y]) do
		local owner = wesnoth.get_village_owner(village[1], village[2])
		if owner == side then
			return false
		elseif owner ~= nil then
			return true
		end
	end
	return false
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
		name = "s" .. unit.side,
		value = increase_damage,
		affect_self = true,
		affect_allies = false,
		description = "side" .. unit.side
			.. "@ScienceMod. This unit has " .. damage
			.. "% damage when it's not near own village",
		T.filter_self { lua_function = "science_enemy_territory" },
	}
	wesnoth.add_modification(unit, "object", {
		id = "science_" .. damage,
		T.effect { apply_to = "remove_ability", T.abilities { ability } },
		T.effect { apply_to = "new_ability", T.abilities { ability } }
	})
end


for _, side in ipairs(wesnoth.sides) do
	set_if_none("strength", 0, side.side)
	set_if_none("income", 0, side.side)
	set_if_none("units", 0, side.side)
	set_if_none("techs", 0, side.side)
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

local function help_menu()
	wesnoth.wml_actions.message {
		speaker = "narrator",
		message = "TODO: help",
	}
end


function science.prestart()
	for _, unit in ipairs(wesnoth.get_units {}) do
		set_ability(unit)
	end
end

function science.turn_refresh()
	set_techs(0)
end

function science.side_turn_end()
	for _, unit in ipairs(wesnoth.get_units { side = wesnoth.current.side }) do
		set_ability(unit)
	end
end


function science.prerecruit()
	local unit = wesnoth.get_unit(wesnoth.get_variable("x1"), wesnoth.get_variable("y1"))
	set_ability(unit)
end


function science.menu_item()
	local side = wesnoth.sides[wesnoth.current.side]
	local options = {
		{
			text = "Village income +1",
			cost = math.floor(80 * math.pow(2, get_income())),
			cost_comment = " (20 * 2^x * turn_modifier)",
			func = village_income_menu,
		},
		{
			text = "Research unit",
			cost = 20,
			cost_comment = " (20 * turn_modifier)",
		},
		{
			text = "Strength on enemy territory +10%",
			cost = 20,
			cost_comment = " (20 * turn_modifier)",
			func = strength_menu,
		},
		{
			text = "Help",
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
	--Technology cost multiplier for this turn: _cost_multiplier_%
	--_cost_multiplier_ = math.floor(100 * cost_multiplier),
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
		if not opt.func then
			print("!!! unhandled menu item ", options[dialog_result.index].text)
		elseif opt.cost and side.gold < opt.cost then
			print("not enouth gold")
		else
			if opt.cost then
				side.gold = side.gold - opt.cost
				set_techs(get_techs() + 1)
			end
			opt.func()
		end
		--science.menu_item()
	end
end

function science.reload()
	wesnoth.dofile("~add-ons/science/lua/dialog.lua")
	wesnoth.dofile("~add-ons/science/lua/main.lua")
	print("reloading")
end

-- >>
