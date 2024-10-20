local M = {}

local PackageName = "Restore"
local function success(s, ...)
	ya.notify({ title = PackageName, content = string.format(s, ...), timeout = 5, level = "info" })
end

local function fail(s, ...)
	ya.notify({ title = PackageName, content = string.format(s, ...), timeout = 5, level = "error" })
end

--- Extract datetime from trash-list string
---@param data string
---@return string
local function datetime(data)
	return data:match("^(%S+ %S+)")
end

--- Extract path from trash-list string
---@param data string
---@return string
local function file_folder_path(data)
	return data:match("%S+ %S+ (.+)$")
end

---@enum File_Type
local File_Type = {
	File = "file",
	Dir = "dir_all",
	None_Exist = "unknown",
}

local function get_file_type(path)
	local cha, _ = fs.cha(Url(path))
	if cha then
		return cha.is_dir and File_Type.Dir or File_Type.File
	else
		return File_Type.None_Exist
	end
end

local function get_latest_trashed_items()
	---@type {trash_restore_index: integer, path: string, type: File_Type}[]
	local restorable_items = {}

	local trash_list_stream, err_code = Command("trash-list"):stdout(Command.PIPED):stderr(Command.PIPED):output()

	if trash_list_stream then
		local trash_list_output = {}
		for line in trash_list_stream.stdout:gmatch("[^\r\n]+") do
			local dateTime, path = line:match("^(%S+ %S+) (.+)$")
			if dateTime and path then
				table.insert(trash_list_output, dateTime .. " " .. path)
			end
		end

		if #trash_list_output == 0 then
			success("Nothing left to restore")
			return
		end

		local last_item_datetime = datetime(trash_list_output[#trash_list_output])

		for index, line in ipairs(trash_list_output) do
			if line then
				local line_datetime = datetime(line)
				local line_path = file_folder_path(line)
				if line_datetime == last_item_datetime then
					-- trash restore index start with 0
					table.insert(
						restorable_items,
						{ trash_restore_index = index - 1, path = line_path, type = get_file_type(line_path) }
					)
				end
			end
		end
	else
		fail("Spawn `trash-cli` failed with error code %s. Do you have it installed?", err_code)
		return
	end
	return restorable_items
	-- return newest_trashed_items
end

---@param data { trash_restore_index: integer, path: string, type: File_Type }[]
local function filter_none_exised_paths(data)
	---@type { trash_restore_index: integer, path: string, type: File_Type}[]
	local list_of_path_existed = {}
	for _, v in ipairs(data) do
		if v.type ~= File_Type.None_Exist then
			table.insert(list_of_path_existed, v)
		end
	end
	return list_of_path_existed
end

local function restore_files(start_index, end_index)
	if type(start_index) ~= "number" or type(end_index) ~= "number" or start_index < 0 or end_index < 0 then
		fail("Failed to restore file(s): out of range")
		return
	end

	ya.manager_emit(
		"shell",
		{ "echo " .. ya.quote(start_index .. "-" .. end_index) .. " | trash-restore --overwrite", confirm = true }
	)
	local file_to_restore_count = end_index - start_index + 1
	success("Restored " .. tostring(file_to_restore_count) .. " file" .. (file_to_restore_count > 1 and "s" or ""))
end

function M:entry()
	local trashed_items = get_latest_trashed_items()
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
		overwrite_confirmed = true
	end
	if overwrite_confirmed then
		restore_files(trashed_items[1].trash_restore_index, trashed_items[#trashed_items].trash_restore_index)
	end
end

return M
