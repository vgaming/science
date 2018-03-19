-- << science/utils

science = {}
local science = science
local wesnoth = wesnoth
local ipairs = ipairs
local string = string

function science.split_comma(string_to_split)
	local result = {}
	local n = 1
	for s in string.gmatch(string_to_split, "[^,]+") do
		result[n] = s
		n = n + 1
	end
	return result
end


function science.i_am_observer()
	for _, side in ipairs(wesnoth.sides) do
		if side.controller == "human" and side.is_local ~= false then
			return false
		end
	end
	return true
end


-- >>
