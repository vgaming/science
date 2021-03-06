-- << science/dialog.lua

local science = science
local wesnoth = wesnoth
local ipairs = ipairs
local string = string
local type = type
local T = wesnoth.require("lua/helper.lua").set_wml_tag_metatable {}
local translate = wesnoth.textdomain "wesnoth"


local function pango_escape(str)
	if wesnoth.compare_versions(wesnoth.game_config.version, ">=", "1.13") then
		return str
	else
		str = string.gsub(tostring(str), "<[^>]+>", "") -- html tags
		str = string.gsub(str, "&lt;", "<")
		str = string.gsub(str, "&gt;", ">")
		return str
	end
end

--- shows a wesnoth "list" dialog and returns the result.
-- Example:
--   item = {text = "", image = ""}
--   show_dialog { label = "Choose from this list", options = {item, item, item} }
local function show_dialog_unsynchronized(settings)
	-- spacer = wesnoth.compare_versions(wesnoth.game_config.version, ">=", "1.13") and "" or "\n"
	local spacer = settings.spacer or "\n"
	local spacer_left = settings.spacer_left or spacer
	local spacer_right = settings.spacer_right or spacer
	local label = settings.label
	label = label and (spacer_left .. pango_escape(label) .. spacer_right) or ""
	local options = settings.options
	local show_images = options[1].image and true or false
	local has_minimum = settings.has_minimum ~= false and true or false

	local description_row = T.row {
		T.column { T.label { use_markup = true, label = label } },
	}

	local list_sub_row
	if show_images then
		list_sub_row = T.row {
			T.column { T.image { id = "the_icon" } },
			T.column { grow_factor = 0, T.label { use_markup = true, id = "the_label" } },
			T.column { grow_factor = 1, T.spacer {} },
		}
	else
		list_sub_row = T.row {
			T.column { horizontal_alignment = "left", T.label { use_markup = true, id = "the_label" } }
		}
	end

	local toggle_panel = T.toggle_panel { return_value = -1, T.grid { list_sub_row } }

	local list_definition = T.list_definition { T.row { T.column { horizontal_grow = true, toggle_panel } } }

	local listbox = T.listbox { id = "the_list", list_definition, has_minimum = has_minimum }

	local ok_cancel_buttons = T.grid {
		T.row {
			T.column { T.button { id = "cancel", return_value = -2, label = "\n" .. translate "Cancel" .. "\n" } },
			T.column { T.button { id = "ok", return_value = -1, label = "\n" .. translate "OK" .. "\n" } },
		}
	}

	local dialog = {
		T.tooltip { id = "tooltip_large" },
		T.helptip { id = "tooltip_large" },
		T.grid {
			T.row { T.column { T.spacer { width = 250 } } },
			description_row,
			T.row { T.column { horizontal_grow = true, listbox } },
			T.row { T.column { ok_cancel_buttons } }
		}
	}

	local function preshow()
		for i, v in ipairs(options) do
			wesnoth.set_dialog_value(spacer_left .. pango_escape(v.text) .. spacer_right, "the_list", i, "the_label")
			if show_images then
				local img = v.image
				if type(img) == "function" then img = img() end
				wesnoth.set_dialog_value(img or "misc/blank-hex.png", "the_list", i, "the_icon")
			end
		end

		if wesnoth.compare_versions(wesnoth.game_config.version, ">=", "1.13.10") then
			wesnoth.set_dialog_focus("the_list")
		end

		if show_images then
			local function select()
				local i = wesnoth.get_dialog_value "the_list"
				if i > 0 then
					local img = options[i].image
					if type(img) == "function" then img = img() end
					wesnoth.set_dialog_value(img or "misc/blank-hex.png", "the_list", i, "the_icon")
				end
			end
			wesnoth.set_dialog_callback(select, "the_list")
		end
	end

	local item_result
	local function postshow()
		item_result = wesnoth.get_dialog_value "the_list"
	end

	local dialog_exit_code = wesnoth.show_dialog(dialog, preshow, postshow)
	local is_ok = dialog_exit_code == -1 and item_result >= 1
	print(string.format("Button %s pressed (%s). Item %s selected: %s",
		dialog_exit_code, is_ok and "ok" or "not_ok", item_result, options[item_result].text))
	return {
		is_ok = is_ok,
		id = options[item_result].id,
		index = item_result,
	}
end


local function show_dialog(settings)
	local func = function() return show_dialog_unsynchronized(settings) end
	return wesnoth.synchronize_choice(func)
end


science.show_dialog = show_dialog
science.show_dialog_unsynchronized = show_dialog_unsynchronized


-- >>
