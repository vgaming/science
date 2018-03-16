-- << science/utils

science = {}
local science = science
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


-- >>
