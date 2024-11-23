local M = {}
local shell = os.getenv("SHELL") or ""
local PackageName = "Restore"
local function success(s, ...)
	ya.notify({ title = PackageName, content = string.format(s, ...), timeout = 5, level = "info" })
end

local function fail(s, ...)
	ya.notify({ title = PackageName, content = string.format(s, ...), timeout = 5, level = "error" })
end

---@enum STATE
local STATE = {
	OVERWRITE_POPUP_POSITION = "overwrite_popup_position",
}

local set_state = ya.sync(function(state, key, value)
	if state then
		state[key] = value
	else
		state = {}
		state[key] = value
	end
end)

local get_state = ya.sync(function(state, key)
	if state then
		return state[key]
	else
		return nil
	end
end)

---@enum File_Type
local File_Type = {
	File = "file",
	Dir = "dir_all",
	None_Exist = "unknown",
}

---@alias TRASHED_ITEM {trash_index: number, trashed_date_time: string, trashed_path: string, type: File_Type} Item in trash list

local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

local function path_quote(path)
	local result = "'" .. string.gsub(path, "'", "'\\''") .. "'"
	return result
end

local function get_file_type(path)
	local cha, _ = fs.cha(Url(path))
	if cha then
		return cha.is_dir and File_Type.Dir or File_Type.File
	else
		return File_Type.None_Exist
	end
end

local function get_trash_volume()
	local cwd = get_cwd()
	local trash_volumes_stream, cmr_err =
		Command("trash-list"):args({ "--volumes" }):stdout(Command.PIPED):stderr(Command.PIPED):output()

	local matched_vol_path = nil
	if trash_volumes_stream then
		local matched_vol_length = 0
		for vol in trash_volumes_stream.stdout:gmatch("[^\r\n]+") do
			local vol_length = utf8.len(vol) or 0
			if cwd:sub(1, vol_length) == vol and vol_length > matched_vol_length then
				matched_vol_path = vol
				matched_vol_length = vol_length
			end
		end
		if not matched_vol_path then
			fail("Can't get trash directory")
		end
	else
		fail("Failed to start `trash-list` with error: `%s`. Do you have `trash-cli` installed?", cmr_err)
	end
	return matched_vol_path
end

---get list of latest files/folders trashed
---@param curr_working_volume currently working volume
---@return TRASHED_ITEM[]|nil
local function get_latest_trashed_items(curr_working_volume)
	---@type TRASHED_ITEM[]
	local restorable_items = {}
	local fake_enter = Command("printf"):stderr(Command.PIPED):stdout(Command.PIPED):spawn():take_stdout()
	local trash_list_stream, err_cmd = Command(shell)
		:args({ "-c", "trash-restore " .. path_quote(curr_working_volume) })
		:stdin(fake_enter)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if trash_list_stream then
		---@type TRASHED_ITEM[]
		local trash_list = {}
		for line in trash_list_stream.stdout:gmatch("[^\r\n]+") do
			-- remove leading spaces
			line = line:match("^%s*(.+)$")
			local trash_index, item_date, item_path = line:match("^(%d+) (%S+ %S+) (.+)$")
			if item_date and item_path and trash_index ~= nil then
				table.insert(trash_list, {
					trash_index = tonumber(trash_index),
					trashed_date_time = item_date,
					trashed_path = item_path,
					type = File_Type.None_Exist,
				})
			end
		end

		if #trash_list == 0 then
			success("Nothing left to restore")
			return
		end

		local last_item_datetime = trash_list[#trash_list].trashed_date_time

		for _, trash_item in ipairs(trash_list) do
			if trash_item then
				if trash_item.trashed_date_time == last_item_datetime then
					trash_item.type = get_file_type(trash_item.trashed_path)
					table.insert(restorable_items, trash_item)
				end
			end
		end
	else
		fail("Failed to start `trash-restore` with error: `%s`. Do you have `trash-cli` installed?", err_cmd)
		return
	end
	return restorable_items
	-- return newest_trashed_items
end

---@param trash_list TRASHED_ITEM[]
local function filter_none_exised_paths(trash_list)
	---@type TRASHED_ITEM[]
	local existed_trash_items = {}
	for _, v in ipairs(trash_list) do
		if v.type ~= File_Type.None_Exist then
			table.insert(existed_trash_items, v)
		end
	end
	return existed_trash_items
end

local function restore_files(curr_working_volume, start_index, end_index)
	if type(start_index) ~= "number" or type(end_index) ~= "number" or start_index < 0 or end_index < 0 then
		fail("Failed to restore file(s): out of range")
		return
	end

	ya.manager_emit("shell", {
		"echo " .. ya.quote(start_index .. "-" .. end_index) .. " | trash-restore --overwrite " .. path_quote(
			curr_working_volume
		),
		confirm = true,
	})
	local file_to_restore_count = end_index - start_index + 1
	success("Restored " .. tostring(file_to_restore_count) .. " file" .. (file_to_restore_count > 1 and "s" or ""))
end

function M:setup(_, opts)
	if opts and opts.overwrite_popup_position and type(opts.overwrite_popup_position) == "table" then
		set_state(STATE.OVERWRITE_POPUP_POSITION, opts.overwrite_popup_position)
	else
		set_state(STATE.OVERWRITE_POPUP_POSITION, { "center", w = 70 })
	end
end

function M:entry()
	local curr_working_volume = get_trash_volume()
	if not curr_working_volume then
		return
	end
	local trashed_items = get_latest_trashed_items(curr_working_volume)
	if trashed_items == nil then
		return
	end
	local collided_items = filter_none_exised_paths(trashed_items)
	local overwrite_confirmed = true
	-- show Confirm dialog with list of collided items
	if #collided_items > 0 then
		--[[
			-- https://github.com/sxyazi/yazi/pull/1789
			if ya.confirm then
				-- local overwrite_confirmed, event = ya.confirm({
				-- -- title = "Overwrite the destination file?",
				-- 	content = "Restored file is existed, want to overwirte it?",
				-- 	list = { collided_items.... },
				-- })
			end
			--]]
		-- TODO: Remove after ya.confirm() API released
		local _, input_event = ya.input({
			title = "Still want to restore?",
			value = #collided_items .. " files and folders existed.",
			position = get_state(STATE.OVERWRITE_POPUP_POSITION),
		})
		overwrite_confirmed = input_event == 1
	end
	if overwrite_confirmed then
		restore_files(curr_working_volume, trashed_items[1].trash_index, trashed_items[#trashed_items].trash_index)
	end
end

return M
