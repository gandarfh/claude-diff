local config = require('claude-diff.config')
local store = require('claude-diff.store')
local diff = require('claude-diff.diff')

local M = {}

-- State
M.buf = nil
M.win = nil
M.entries = {}
M.ns = vim.api.nvim_create_namespace('claude_diff_panel')

-- Line where file entries start (0-indexed)
M.ENTRIES_START = 0

--- Check if panel is open
---@return boolean
function M.is_open()
  return M.win ~= nil and vim.api.nvim_win_is_valid(M.win)
end

--- Build display lines and highlights for the panel
---@return string[] lines, table[] highlights
local function build_content(entries)
  local lines = {}
  local hls = {}

  if #entries == 0 then
    table.insert(lines, '')
    table.insert(lines, '    No pending changes')
    table.insert(hls, { line = 1, col_start = 0, col_end = -1, hl = 'ClaudeDiffHelp' })
    table.insert(lines, '')
    table.insert(lines, '    Changes made by Claude will')
    table.insert(hls, { line = 3, col_start = 0, col_end = -1, hl = 'ClaudeDiffHelp' })
    table.insert(lines, '    appear here for review.')
    table.insert(hls, { line = 4, col_start = 0, col_end = -1, hl = 'ClaudeDiffHelp' })
    return lines, hls
  end

  for _, entry in ipairs(entries) do
    local icon, icon_hl
    if entry.is_new then
      icon = ' '
      icon_hl = 'ClaudeDiffNewFile'
    else
      icon = ' '
      icon_hl = 'ClaudeDiffModified'
    end

    -- Count hunks
    local diff_text = diff.compute(entry.file)
    local hunks = diff_text and diff.parse_hunks(diff_text) or {}
    local hunk_count = #hunks

    -- Build the line: "  icon  filename           +3 hunks"
    local filename = vim.fn.fnamemodify(entry.file, ':t')
    local dir = vim.fn.fnamemodify(entry.file, ':h')
    if dir == '.' then
      dir = ''
    else
      dir = dir .. '/'
    end

    local badge
    if entry.is_new then
      badge = 'new'
    else
      badge = hunk_count .. (hunk_count == 1 and ' hunk' or ' hunks')
    end

    -- Format: "  icon  dir/filename  badge"
    local left = '  ' .. icon .. '  ' .. dir .. filename .. '  ' .. badge
    local line_idx = #lines

    table.insert(lines, left)

    -- Icon highlight
    table.insert(hls, { line = line_idx, col_start = 2, col_end = 2 + #icon, hl = icon_hl })
    -- Dir path (dimmed)
    if dir ~= '' then
      local dir_start = 2 + #icon + 2
      table.insert(hls, { line = line_idx, col_start = dir_start, col_end = dir_start + #dir, hl = 'ClaudeDiffFilePath' })
    end
  end

  return lines, hls
end

--- Render panel content
function M.render()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    return
  end

  local entries = store.get_pending()
  M.entries = entries
  M.ENTRIES_START = 0

  local lines, hls = build_content(entries)

  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.bo[M.buf].modifiable = false

  -- Apply highlights
  vim.api.nvim_buf_clear_namespace(M.buf, M.ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(M.buf, M.ns, h.hl, h.line, h.col_start, h.col_end)
  end

  -- Update title with count
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    local count = #entries
    local title = ' Claude Diff (' .. count .. ') '
    vim.api.nvim_win_set_config(M.win, {
      title = { { title, 'ClaudeDiffTitle' } },
      title_pos = 'center',
    })
  end
end

--- Get the file index from the current cursor line
---@return number|nil 1-based index into M.entries
function M.get_entry_at_cursor()
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(M.win)
  local line = cursor[1] -- 1-based
  local entry_idx = line - M.ENTRIES_START

  if entry_idx >= 1 and entry_idx <= #M.entries then
    return entry_idx
  end

  return nil
end

--- Calculate window dimensions
---@return table {width, height, row, col}
local function calc_dimensions()
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines

  local width = math.min(math.max(60, math.floor(editor_w * 0.5)), 80)
  local height = math.min(math.max(10, math.floor(editor_h * 0.4)), 30)

  local row = math.floor((editor_h - height) / 2) - 1
  local col = math.floor((editor_w - width) / 2)

  return { width = width, height = height, row = row, col = col }
end

--- Create the panel buffer and floating window
function M.open()
  if M.is_open() then
    vim.api.nvim_set_current_win(M.win)
    M.render()
    return
  end

  -- Create buffer
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].buftype = 'nofile'
  vim.bo[M.buf].bufhidden = 'wipe'
  vim.bo[M.buf].swapfile = false
  vim.bo[M.buf].filetype = 'claude-diff-panel'

  local dim = calc_dimensions()
  local entries = store.get_pending()
  local count = #entries
  local title = ' Claude Diff (' .. count .. ') '

  -- Footer help line
  local footer = ' a approve  x reject  Enter view  q close '

  -- Create floating window
  M.win = vim.api.nvim_open_win(M.buf, true, {
    relative = 'editor',
    width = dim.width,
    height = dim.height,
    row = dim.row,
    col = dim.col,
    style = 'minimal',
    border = 'rounded',
    title = { { title, 'ClaudeDiffTitle' } },
    title_pos = 'center',
    footer = { { footer, 'ClaudeDiffHelp' } },
    footer_pos = 'center',
    noautocmd = true,
  })

  -- Window options
  vim.wo[M.win].number = false
  vim.wo[M.win].relativenumber = false
  vim.wo[M.win].signcolumn = 'no'
  vim.wo[M.win].wrap = false
  vim.wo[M.win].cursorline = true
  vim.wo[M.win].winhighlight = 'Normal:ClaudeDiffNormal,FloatBorder:ClaudeDiffBorder,CursorLine:Visual'

  M.render()
  M.setup_keymaps()

  -- Position cursor on first entry
  if #M.entries > 0 then
    vim.api.nvim_win_set_cursor(M.win, { M.ENTRIES_START + 1, 0 })
  end

end

--- Close the panel
function M.close()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
  end
  M.win = nil
  M.buf = nil
end

--- Setup keymaps for the panel buffer
function M.setup_keymaps()
  if not M.buf then
    return
  end

  local km = config.get().keymaps
  local actions = require('claude-diff.actions')
  local bopts = { buffer = M.buf, noremap = true, silent = true, nowait = true }

  vim.keymap.set('n', km.open_diff, function()
    local idx = M.get_entry_at_cursor()
    if idx and M.entries[idx] then
      M.close()
      actions.open_diff(M.entries[idx].file)
    end
  end, bopts)

  vim.keymap.set('n', km.approve_file, function()
    local idx = M.get_entry_at_cursor()
    if idx and M.entries[idx] then
      actions.approve_file(M.entries[idx].file)
    end
  end, bopts)

  vim.keymap.set('n', km.reject_file, function()
    local idx = M.get_entry_at_cursor()
    if idx and M.entries[idx] then
      actions.reject_file(M.entries[idx].file)
    end
  end, bopts)

  vim.keymap.set('n', km.approve_all, function()
    actions.approve_all()
  end, bopts)

  vim.keymap.set('n', km.reject_all, function()
    actions.reject_all()
  end, bopts)

  vim.keymap.set('n', km.refresh, function()
    M.render()
  end, bopts)

  vim.keymap.set('n', km.close, function()
    require('claude-diff').close()
  end, bopts)

  -- ESC also closes
  vim.keymap.set('n', '<Esc>', function()
    require('claude-diff').close()
  end, bopts)
end

return M
