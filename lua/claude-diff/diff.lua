local store = require('claude-diff.store')

local M = {}

---@class Hunk
---@field old_start number Line number in original file (1-indexed)
---@field old_count number Number of lines in original
---@field new_start number Line number in modified file (1-indexed)
---@field new_count number Number of lines in modified
---@field lines string[] Diff lines (prefixed with ' ', '+', '-')
---@field header string The @@ header line

--- Compute unified diff between snapshot and current file
---@param relative_path string
---@return string|nil diff_text
---@return boolean is_new
function M.compute(relative_path)
  local snapshot, is_new = store.get_snapshot(relative_path)
  local current = store.get_current(relative_path)

  if is_new then
    -- New file: diff is everything added
    if not current then
      return nil, true
    end
    local result = vim.diff(
      '',
      current,
      { result_type = 'unified', ctxlen = 3 }
    )
    return result, true
  end

  if not snapshot or not current then
    return nil, false
  end

  -- Check if files are identical
  if snapshot == current then
    return nil, false
  end

  local result = vim.diff(
    snapshot,
    current,
    { result_type = 'unified', ctxlen = 3 }
  )

  return result, false
end

--- Parse unified diff text into a list of hunks
---@param diff_text string
---@return Hunk[]
function M.parse_hunks(diff_text)
  if not diff_text or diff_text == '' then
    return {}
  end

  local hunks = {}
  local lines = vim.split(diff_text, '\n', { plain = true })
  local current_hunk = nil

  for _, line in ipairs(lines) do
    local old_start, old_count, new_start, new_count =
      line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')

    if old_start then
      -- Save previous hunk
      if current_hunk then
        table.insert(hunks, current_hunk)
      end

      current_hunk = {
        old_start = tonumber(old_start),
        old_count = tonumber(old_count) or 1,
        new_start = tonumber(new_start),
        new_count = tonumber(new_count) or 1,
        header = line,
        lines = {},
      }
    elseif current_hunk then
      -- Only include diff content lines (context, add, delete)
      if line:match('^[ +%-]') or line == '\\ No newline at end of file' then
        table.insert(current_hunk.lines, line)
      end
    end
  end

  -- Don't forget the last hunk
  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  return hunks
end

--- Get the original lines from a file's content
---@param content string
---@return string[]
local function content_to_lines(content)
  if not content or content == '' then
    return {}
  end
  local lines = vim.split(content, '\n', { plain = true })
  -- Remove trailing empty from split
  if #lines > 0 and lines[#lines] == '' then
    table.remove(lines)
  end
  return lines
end

--- Apply a single hunk to lines (forward: apply the change)
---@param original_lines string[]
---@param hunk Hunk
---@return string[] result_lines
function M.apply_hunk(original_lines, hunk)
  local result = {}
  local old_idx = 1

  -- Copy lines before the hunk
  while old_idx < hunk.old_start do
    table.insert(result, original_lines[old_idx])
    old_idx = old_idx + 1
  end

  -- Apply the hunk: process diff lines
  for _, dline in ipairs(hunk.lines) do
    local prefix = dline:sub(1, 1)
    local text = dline:sub(2)

    if prefix == ' ' then
      -- Context line: copy from original, advance
      table.insert(result, text)
      old_idx = old_idx + 1
    elseif prefix == '+' then
      -- Added line: insert
      table.insert(result, text)
    elseif prefix == '-' then
      -- Deleted line: skip in original
      old_idx = old_idx + 1
    end
  end

  -- Copy remaining lines after the hunk
  while old_idx <= #original_lines do
    table.insert(result, original_lines[old_idx])
    old_idx = old_idx + 1
  end

  return result
end

--- Revert a single hunk: given the CURRENT file and the hunk,
--- reconstruct what the file would look like without this hunk's changes.
--- This means: in the modified file, replace the hunk's new content with old content.
---@param current_lines string[]
---@param hunk Hunk
---@return string[] result_lines
function M.revert_hunk(current_lines, hunk)
  local result = {}
  local new_idx = 1

  -- Copy lines before the hunk (in modified file space)
  while new_idx < hunk.new_start do
    table.insert(result, current_lines[new_idx])
    new_idx = new_idx + 1
  end

  -- Reverse the hunk: process diff lines
  for _, dline in ipairs(hunk.lines) do
    local prefix = dline:sub(1, 1)
    local text = dline:sub(2)

    if prefix == ' ' then
      -- Context line: keep it, advance in current
      table.insert(result, text)
      new_idx = new_idx + 1
    elseif prefix == '+' then
      -- Was added: skip in current (revert = remove)
      new_idx = new_idx + 1
    elseif prefix == '-' then
      -- Was deleted: restore it
      table.insert(result, text)
    end
  end

  -- Copy remaining lines after the hunk
  while new_idx <= #current_lines do
    table.insert(result, current_lines[new_idx])
    new_idx = new_idx + 1
  end

  return result
end

--- Revert a hunk in a file on disk
---@param relative_path string
---@param hunk_index number 1-based index of the hunk to revert
---@return boolean success
function M.revert_hunk_in_file(relative_path, hunk_index)
  local diff_text = M.compute(relative_path)
  if not diff_text then
    return false
  end

  local hunks = M.parse_hunks(diff_text)
  if hunk_index < 1 or hunk_index > #hunks then
    return false
  end

  local current_content = store.get_current(relative_path)
  if not current_content then
    return false
  end

  local current_lines = content_to_lines(current_content)
  local new_lines = M.revert_hunk(current_lines, hunks[hunk_index])
  local new_content = table.concat(new_lines, '\n') .. '\n'

  store.write_file(relative_path, new_content)
  return true
end

--- Approve a hunk: update the snapshot so this hunk is no longer shown as a diff.
--- We rebuild the snapshot by applying the approved hunk to it.
---@param relative_path string
---@param hunk_index number 1-based index of the hunk to approve
---@return boolean success
function M.approve_hunk_in_file(relative_path, hunk_index)
  local diff_text, is_new = M.compute(relative_path)
  if not diff_text then
    return false
  end

  local hunks = M.parse_hunks(diff_text)
  if hunk_index < 1 or hunk_index > #hunks then
    return false
  end

  if is_new then
    -- Individual hunk approval doesn't make sense for new files.
    -- The user should approve the entire file instead.
    return false
  end

  local snapshot_content = store.get_snapshot(relative_path)
  if not snapshot_content then
    return false
  end

  local snapshot_lines = content_to_lines(snapshot_content)
  local new_snapshot_lines = M.apply_hunk(snapshot_lines, hunks[hunk_index])
  local new_snapshot_content = table.concat(new_snapshot_lines, '\n') .. '\n'

  store.update_snapshot(relative_path, new_snapshot_content)

  -- Check if snapshot now matches current (all hunks approved)
  local current_content = store.get_current(relative_path)
  if new_snapshot_content == current_content then
    store.remove_snapshot(relative_path)
    store.remove_pending(relative_path)
  end

  return true
end

--- Get snapshot and current content as line arrays (for UI)
---@param relative_path string
---@return string[]|nil old_lines, string[]|nil new_lines, boolean is_new
function M.get_file_lines(relative_path)
  local snapshot, is_new = store.get_snapshot(relative_path)
  local current = store.get_current(relative_path)

  local new_lines = {}
  if current then
    new_lines = content_to_lines(current)
  end

  local old_lines = {}
  if snapshot and not is_new then
    old_lines = content_to_lines(snapshot)
  elseif not is_new and not snapshot then
    -- No snapshot (e.g. already approved): show current on both sides
    old_lines = new_lines
  end

  return old_lines, new_lines, is_new
end

return M
