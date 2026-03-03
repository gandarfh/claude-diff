local M = {}

local ns = vim.api.nvim_create_namespace('claude_diff_inline')

local MAX_LINE_LENGTH = 500

--- Compute character-level diff between two strings.
--- Returns 0-indexed byte ranges of changed characters in each string.
---@param old_str string
---@param new_str string
---@return table[] old_ranges  { {start_col, end_col}, ... }
---@return table[] new_ranges  { {start_col, end_col}, ... }
function M.char_diff(old_str, new_str)
  if old_str == new_str then
    return {}, {}
  end

  -- Guard: skip very long lines
  if #old_str > MAX_LINE_LENGTH or #new_str > MAX_LINE_LENGTH then
    return { { 0, #old_str } }, { { 0, #new_str } }
  end

  -- Guard: handle empty strings directly (vim.diff behaves oddly with empty input)
  if #old_str == 0 then
    return {}, #new_str > 0 and { { 0, #new_str } } or {}
  end
  if #new_str == 0 then
    return #old_str > 0 and { { 0, #old_str } } or {}, {}
  end

  -- Convert strings to one-char-per-line for vim.diff
  local old_chars = {}
  for i = 1, #old_str do
    old_chars[i] = old_str:sub(i, i)
  end
  local new_chars = {}
  for i = 1, #new_str do
    new_chars[i] = new_str:sub(i, i)
  end

  local old_input = table.concat(old_chars, '\n') .. '\n'
  local new_input = table.concat(new_chars, '\n') .. '\n'

  local indices = vim.diff(old_input, new_input, {
    result_type = 'indices',
    algorithm = 'patience',
  })

  if not indices then
    return {}, {}
  end

  local old_ranges = {}
  local new_ranges = {}

  for _, idx in ipairs(indices) do
    local os_start, oc, ns_start, nc = idx[1], idx[2], idx[3], idx[4]
    if oc > 0 then
      table.insert(old_ranges, { os_start - 1, os_start - 1 + oc })
    end
    if nc > 0 then
      table.insert(new_ranges, { ns_start - 1, ns_start - 1 + nc })
    end
  end

  return old_ranges, new_ranges
end

--- Scan a line range for DiffChange highlights, appending matches to changed.
---@param start_line number
---@param end_line number
---@param changed number[] (mutated)
local function scan_range_for_diff_change(start_line, end_line, changed)
  for lnum = start_line, end_line do
    local hl_id = vim.fn.diff_hlID(lnum, 1)
    if hl_id > 0 then
      local name = vim.fn.synIDattr(hl_id, 'name')
      if name == 'DiffChange' then
        table.insert(changed, lnum)
      end
    end
  end
end

--- Get line numbers that have DiffChange highlight in a window, scanning only within given ranges.
---@param win number
---@param line_count number
---@param ranges? table[] list of {start_line, end_line} 1-indexed ranges to scan (nil = scan all)
---@return number[]
local function get_diff_change_lines(win, line_count, ranges)
  local changed = {}
  vim.api.nvim_win_call(win, function()
    if ranges and #ranges > 0 then
      for _, range in ipairs(ranges) do
        scan_range_for_diff_change(math.max(1, range[1]), math.min(line_count, range[2]), changed)
      end
    else
      scan_range_for_diff_change(1, line_count, changed)
    end
  end)
  return changed
end

--- Apply character-level inline diff highlights to both buffers.
--- Uses Neovim's own diff info (diff_hlID) to find DiffChange lines,
--- ensuring char highlights match the visual alignment from diffthis.
---@param left_buf number
---@param right_buf number
---@param left_win number
---@param right_win number
---@param old_lines string[]
---@param new_lines string[]
---@param hunks? table[] Parsed hunks to limit scanning (optional, scans all lines if nil)
function M.apply(left_buf, right_buf, left_win, right_win, old_lines, new_lines, hunks)
  M.clear(left_buf, right_buf)

  -- Build scan ranges from hunks if available
  local old_ranges, new_ranges
  if hunks and #hunks > 0 then
    old_ranges = {}
    new_ranges = {}
    for _, hunk in ipairs(hunks) do
      table.insert(old_ranges, { hunk.old_start, hunk.old_start + hunk.old_count - 1 })
      table.insert(new_ranges, { hunk.new_start, hunk.new_start + hunk.new_count - 1 })
    end
  end

  local left_changed = get_diff_change_lines(left_win, #old_lines, old_ranges)
  local right_changed = get_diff_change_lines(right_win, #new_lines, new_ranges)

  local count = math.min(#left_changed, #right_changed)
  for i = 1, count do
    local old_lnum = left_changed[i]
    local new_lnum = right_changed[i]
    local old_text = old_lines[old_lnum] or ''
    local new_text = new_lines[new_lnum] or ''

    local old_ranges, new_ranges = M.char_diff(old_text, new_text)

    for _, range in ipairs(old_ranges) do
      pcall(vim.api.nvim_buf_set_extmark, left_buf, ns, old_lnum - 1, range[1], {
        end_col = math.min(range[2], #old_text),
        hl_group = 'ClaudeDiffDeleteText',
        priority = 110,
      })
    end

    for _, range in ipairs(new_ranges) do
      pcall(vim.api.nvim_buf_set_extmark, right_buf, ns, new_lnum - 1, range[1], {
        end_col = math.min(range[2], #new_text),
        hl_group = 'ClaudeDiffAddText',
        priority = 110,
      })
    end
  end
end

--- Clear all inline diff highlights from both buffers.
---@param left_buf number|nil
---@param right_buf number|nil
function M.clear(left_buf, right_buf)
  if left_buf and vim.api.nvim_buf_is_valid(left_buf) then
    vim.api.nvim_buf_clear_namespace(left_buf, ns, 0, -1)
  end
  if right_buf and vim.api.nvim_buf_is_valid(right_buf) then
    vim.api.nvim_buf_clear_namespace(right_buf, ns, 0, -1)
  end
end

return M
