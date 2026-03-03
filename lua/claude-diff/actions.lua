local store = require("claude-diff.store")
local diff = require("claude-diff.diff")

local M = {}

--- Open diff view for a file
---@param relative_path string
function M.open_diff(relative_path)
	local viewer = require("claude-diff.ui.viewer")
	viewer.open(relative_path)
end

--- Approve a file: accept all changes, remove snapshot
---@param relative_path string
function M.approve_file(relative_path)
	store.remove_snapshot(relative_path)
	store.remove_pending(relative_path)

	vim.notify("Approved: " .. relative_path, vim.log.levels.INFO, { title = "claude-diff" })

	M._refresh_ui()

	-- Defer refresh so the keymap callback finishes before we destroy/recreate buffers
	local viewer = require("claude-diff.ui.viewer")
	if viewer.current_file == relative_path then
		vim.schedule(function()
			viewer.refresh()
		end)
	end
end

--- Reject a file: revert to original snapshot
---@param relative_path string
function M.reject_file(relative_path)
	local snapshot, is_new = store.get_snapshot(relative_path)

	if is_new then
		store.delete_file(relative_path)
	elseif snapshot then
		store.write_file(relative_path, snapshot)
		M._reload_buffer(relative_path)
	end

	store.remove_snapshot(relative_path)
	store.remove_pending(relative_path)

	vim.notify("Rejected: " .. relative_path, vim.log.levels.INFO, { title = "claude-diff" })

	M._refresh_ui()

	local viewer = require("claude-diff.ui.viewer")
	if viewer.current_file == relative_path then
		vim.schedule(function()
			viewer.refresh()
		end)
	end
end

--- Approve all pending files
function M.approve_all()
	require("claude-diff.ui.viewer").close()

	local entries = store.get_pending()

	for _, entry in ipairs(entries) do
		store.remove_snapshot(entry.file)
	end

	store.set_pending({})

	local count = #entries
	vim.notify(
		"Approved " .. count .. " file" .. (count ~= 1 and "s" or ""),
		vim.log.levels.INFO,
		{ title = "claude-diff" }
	)

	M._refresh_ui()
end

--- Reject all pending files
function M.reject_all()
	require("claude-diff.ui.viewer").close()

	local entries = store.get_pending()

	for _, entry in ipairs(entries) do
		local snapshot, is_new = store.get_snapshot(entry.file)
		if is_new then
			store.delete_file(entry.file)
		elseif snapshot then
			store.write_file(entry.file, snapshot)
			M._reload_buffer(entry.file)
		end
		store.remove_snapshot(entry.file)
	end

	store.set_pending({})

	local count = #entries
	vim.notify(
		"Rejected " .. count .. " file" .. (count ~= 1 and "s" or ""),
		vim.log.levels.INFO,
		{ title = "claude-diff" }
	)

	M._refresh_ui()
end

--- Approve a specific hunk
---@param relative_path string
---@param hunk_index number
function M.approve_hunk(relative_path, hunk_index)
	local ok = diff.approve_hunk_in_file(relative_path, hunk_index)

	if ok then
		vim.notify(
			string.format("Approved hunk %d in %s", hunk_index, relative_path),
			vim.log.levels.INFO,
			{ title = "claude-diff" }
		)

		-- Check if there are any remaining diffs
		local remaining_diff = diff.compute(relative_path)
		if not remaining_diff or remaining_diff == "" then
			-- No more changes — clean up
			store.remove_snapshot(relative_path)
			store.remove_pending(relative_path)
		end

		M._refresh_ui()

		-- Defer refresh so the keymap callback finishes before we destroy/recreate buffers
		local viewer = require("claude-diff.ui.viewer")
		if viewer.current_file == relative_path then
			vim.schedule(function()
				viewer.refresh()
			end)
		end
	else
		vim.notify("Failed to approve hunk", vim.log.levels.ERROR, { title = "claude-diff" })
	end
end

--- Reject a specific hunk
---@param relative_path string
---@param hunk_index number
function M.reject_hunk(relative_path, hunk_index)
	local ok = diff.revert_hunk_in_file(relative_path, hunk_index)

	if ok then
		vim.notify(
			string.format("Rejected hunk %d in %s", hunk_index, relative_path),
			vim.log.levels.INFO,
			{ title = "claude-diff" }
		)

		M._reload_buffer(relative_path)

		-- Check if there are any remaining diffs
		local diff_text = diff.compute(relative_path)
		if not diff_text or diff_text == "" then
			-- No more changes — clean up
			store.remove_snapshot(relative_path)
			store.remove_pending(relative_path)
		end

		M._refresh_ui()

		local viewer = require("claude-diff.ui.viewer")
		if viewer.current_file == relative_path then
			vim.schedule(function()
				viewer.refresh()
			end)
		end
	else
		vim.notify("Failed to reject hunk", vim.log.levels.ERROR, { title = "claude-diff" })
	end
end

--- Reload a buffer if it's open in Neovim
---@param relative_path string
function M._reload_buffer(relative_path)
	local cwd = vim.fn.getcwd()
	local abs_path = cwd .. "/" .. relative_path

	-- Find buffer by path
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local buf_name = vim.api.nvim_buf_get_name(buf)
			if buf_name == abs_path then
				-- Reload buffer from disk
				vim.api.nvim_buf_call(buf, function()
					vim.cmd("edit!")
				end)
				break
			end
		end
	end
end

--- Refresh all UI components
function M._refresh_ui()
	local ok, panel = pcall(require, "claude-diff.ui.panel")
	if ok and panel.is_open() then
		panel.render()
	end
end

return M
