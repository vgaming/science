-- << science/main.lua

local science = science
local wesnoth = wesnoth
local assert = assert
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

local function get_unspent(side) return get("unspent", side) end

local function get_income(side) return get("income", side) end

local function get_strength(side) return get("strength", side) end

local function set_if_none(scope, value, side)
	local name = "science_" .. scope .. "_" .. side
	if not wesnoth.get_variable(name) then
		wesnoth.set_variable(name, value)
	end
end

for _, side in ipairs(wesnoth.sides) do
	set_if_none("unspent", 1000, side.side)
	set_if_none("research", 0, side.side)
	set_if_none("income", 0, side.side)
	set_if_none("upkeep", 0, side.side)
	set_if_none("strength", 0, side.side)
	set_if_none("units", 0, side.side)
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

function science.menu_item()
	local options = {
		{
			text = "Village income +1",
			cost = math.floor(300 * math.pow(2, get_income()))
		},
		{
			text = "Research unit",
			cost = 300
		},
		{
			text = "Strength on enemy territory +10%",
			cost = 200 --+ 100 * get_strength()
		},
		{
			text = "Set research intensity",
		},
		{
			text = "Help"
		},
	}
	for _, opt in ipairs(options) do
		if opt.cost and get_unspent() >= opt.cost then
			opt.text = opt.text .. " | <span color='#FFE680'>cost " .. opt.cost .. " research points</span>"
		elseif opt.cost then
			opt.text = opt.text .. " | <span color='#FF0000'>cost " .. opt.cost .. " research points</span>"
		end
	end
	local label = [[<b>Science Mod</b>

Territory under cursor: _territory_
Strength on enemy territory: _strength_%
Unspent research points: _points_
Village income: _village_income_
	]]
	label = string.gsub(label, "_[a-z_]+_", {
		_points_ = get_unspent(),
		_village_income_ = wesnoth.sides[wesnoth.current.side].village_gold,
		_territory_ = true and "Ours" or "Enemy",
		_strength_ = 30 + 10 * get_strength()
	})
	local dialog_result = science.show_dialog {
		spacer_left = "",
		spacer_right = "\n",
		label = label,
		options = options,
	}
	if dialog_result.is_ok then
		science.menu_item()
	end
end

function science.reload()
	wesnoth.dofile("~add-ons/science/lua/dialog.lua")
	wesnoth.dofile("~add-ons/science/lua/main.lua")
	print("reloading")
end

-- >>
