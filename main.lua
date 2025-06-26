--- @since 25.5.31

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
	POSITION = "position",
	SHOW_CONFIRM = "show_confirm",
	THEME = "theme",
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
		Command("trash-list"):arg({ "--volumes" }):stdout(Command.PIPED):stderr(Command.PIPED):output()

	---@type string|nil
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
---@param curr_working_volume string currently working volume
---@return TRASHED_ITEM[]|nil, TRASHED_ITEM[]|nil
local function get_latest_trashed_items(curr_working_volume)
	---@type TRASHED_ITEM[], TRASHED_ITEM[]
	local restorable_items, existed_items = {}, {}

	local fake_enter = Command("printf"):stderr(Command.PIPED):stdout(Command.PIPED):spawn():take_stdout()
	local trash_list_stream, err_cmd = Command(shell)
		:arg({ "-c", "trash-restore " .. path_quote(curr_working_volume) })
		:stdin(fake_enter)
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:spawn()

	if trash_list_stream then
		local last_item_datetime = nil

		while true do
			local line, event = trash_list_stream:read_line()
			if event ~= 0 then
				break
			end
			-- remove leading spaces
			line = line:match("^%s*(.+)$")
			local trash_index, item_date, item_path = line:match("^(%d+) (%S+ %S+) (.+)$")
			if item_date and item_path and trash_index ~= nil then
				if last_item_datetime and last_item_datetime ~= item_date then
					restorable_items = {}
				end
				table.insert(restorable_items, {
					trash_index = tonumber(trash_index),
					trashed_date_time = item_date,
					trashed_path = item_path,
					type = File_Type.None_Exist,
				})
				last_item_datetime = item_date
			end
		end
		trash_list_stream:start_kill()

		if #restorable_items == 0 then
			success("Nothing left to restore")
			return
		end

		for _, trash_item in ipairs(restorable_items) do
			if trash_item then
				trash_item.type = get_file_type(trash_item.trashed_path)
				if trash_item.type ~= File_Type.None_Exist then
					table.insert(existed_items, trash_item)
				end
			end
		end
	else
		fail("Failed to start `trash-restore` with error: `%s`. Do you have `trash-cli` installed?", err_cmd)
		return
	end
	return restorable_items, existed_items
end

local function restore_files(curr_working_volume, start_index, end_index)
	if type(start_index) ~= "number" or type(end_index) ~= "number" or start_index < 0 or end_index < 0 then
		fail("Failed to restore file(s): out of range")
		return
	end

	local restored_status, _ = Command(shell)
		:arg({
			"-c",
			"echo " .. ya.quote(start_index .. "-" .. end_index) .. " | trash-restore --overwrite " .. path_quote(
				curr_working_volume
			),
		})
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	local file_to_restore_count = end_index - start_index + 1
	if restored_status then
		success("Restored " .. tostring(file_to_restore_count) .. " file" .. (file_to_restore_count > 1 and "s" or ""))
	else
		fail(
			"Failed to restore "
				.. tostring(file_to_restore_count)
				.. " file"
				.. (file_to_restore_count > 1 and "s" or "")
		)
	end
end

function M:setup(opts)
	if opts and opts.position and type(opts.position) == "table" then
		set_state(STATE.POSITION, opts.position)
	else
		set_state(STATE.POSITION, { "center", w = 70, h = 40 })
	end
	if opts and opts.show_confirm ~= nil then
		set_state(STATE.SHOW_CONFIRM, opts.show_confirm)
	else
		set_state(STATE.SHOW_CONFIRM, true)
	end
	if opts and opts.theme and type(opts.theme) == "table" then
		set_state(STATE.THEME, opts.theme)
	else
		set_state(STATE.THEME, {})
	end
end

---@param trash_list TRASHED_ITEM[]
local function get_components(trash_list)
	local theme = get_state(STATE.THEME) or {}
	local item_odd_style = theme.list_item and theme.list_item.odd and ui.Style():fg(theme.list_item.odd)
		or (th.confirm.list or ui.Style():fg("blue"))
	local item_even_style = theme.list_item and theme.list_item.even and ui.Style():fg(theme.list_item.even)
		or (th.confirm.list or ui.Style():fg("blue"))

	local trashed_items_components = {}
	for idx, item in pairs(trash_list) do
		table.insert(
			trashed_items_components,
			ui.Line({
				ui.Span(" "),
				ui.Span(item.trashed_path):style(idx % 2 == 0 and item_even_style or item_odd_style),
			}):align(ui.Align.LEFT)
		)
	end
	return trashed_items_components
end

function M:entry()
	local curr_working_volume = get_trash_volume()
	if not curr_working_volume then
		return
	end
	local trashed_items, collided_items = get_latest_trashed_items(curr_working_volume)
	if trashed_items == nil then
		return
	end
	local overwrite_confirmed = true
	local show_confirm = get_state(STATE.SHOW_CONFIRM)
	show_confirm = show_confirm == nil and true or show_confirm
	local pos = get_state(STATE.POSITION)
	pos = pos or { "center", w = 70, h = 40 }

	local theme = get_state(STATE.THEME) or {}
	theme.title = theme.title and ui.Style():fg(theme.title):bold() or th.confirm.title
	theme.header = theme.header and ui.Style():fg(theme.header) or th.confirm.content
	theme.header_warning = ui.Style():fg(theme.header_warning or "yellow")
	if ya.confirm and show_confirm then
		local continue_restore = ya.confirm({
			title = ui.Line("Restore files/folders"):style(theme.title),
			body = ui.Text({
				ui.Line(""),
				ui.Line("The following files and folders are going to be restored:"):style(theme.header),
				ui.Line(""),
				table.unpack(get_components(trashed_items)),
			})
				:align(ui.Align.LEFT)
				:wrap(ui.Wrap.YES),
			-- TODO: remove this after next yazi released
			content = ui.Text({
				ui.Line(""),
				ui.Line("The following files and folders are going to be restored:"):style(theme.header),
				ui.Line(""),
				table.unpack(get_components(trashed_items)),
			})
				:align(ui.Align.LEFT)
				:wrap(ui.Wrap.YES),
			pos = pos,
		})
		-- stopping
		if not continue_restore then
			return
		end
	end

	-- show Confirm dialog with list of collided items
	if collided_items and #collided_items > 0 then
		overwrite_confirmed = ya.confirm({
			title = ui.Line("Restore files/folders"):style(theme.title),
			body = ui.Text({
				ui.Line(""),
				ui.Line("The following files and folders are existed, overwrite?"):style(theme.header_warning),
				ui.Line(""),
				table.unpack(get_components(collided_items)),
			})
				:align(ui.Align.LEFT)
				:wrap(ui.Wrap.YES),
			-- TODO: remove this after next yazi released
			content = ui.Text({
				ui.Line(""),
				ui.Line("The following files and folders are existed, overwrite?"):style(theme.header_warning),
				ui.Line(""),
				table.unpack(get_components(collided_items)),
			})
				:align(ui.Align.LEFT)
				:wrap(ui.Wrap.YES),
			pos = pos,
		})
	end
	if overwrite_confirmed then
		restore_files(curr_working_volume, trashed_items[1].trash_index, trashed_items[#trashed_items].trash_index)
	end
end

return M
