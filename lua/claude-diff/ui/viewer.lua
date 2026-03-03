local config = require('claude-diff.config')
local diff = require('claude-diff.diff')
local store = require('claude-diff.store')

local M = {}

-- State
M.left_buf = nil
M.left_win = nil
M.right_buf = nil
M.right_win = nil
M.tab_buf = nil
M.tab_win = nil
M.current_file = nil
M.hunks = {}
M.current_hunk_idx = 0
M.file_list = {}
M.file_idx = 0

local ns = vim.api.nvim_create_namespace('claude_diff_viewer')
local augroup = vim.api.nvim_create_augroup('claude_diff_viewer', { clear = true })

--- Winhighlight for left pane (original — deletions use red tones)
local WH_LEFT = table.concat({
  'Normal:ClaudeDiffNormal',
  'FloatBorder:ClaudeDiffBorder',
  'DiffAdd:ClaudeDiffAdd',
  'DiffDelete:ClaudeDiffDelete',
  'DiffChange:ClaudeDiffChangeDel',
  'DiffText:ClaudeDiffText',
}, ',')

--- Winhighlight for right pane (modified — additions use green tones)
local WH_RIGHT = table.concat({
  'Normal:ClaudeDiffNormal',
  'FloatBorder:ClaudeDiffBorder',
  'DiffAdd:ClaudeDiffAdd',
  'DiffDelete:ClaudeDiffDelete',
  'DiffChange:ClaudeDiffChangeAdd',
  'DiffText:ClaudeDiffText',
}, ',')

--- Border chars for left pane (connected to right)
local LEFT_BORDER = {
  { '╭', 'ClaudeDiffBorder' },
  { '─', 'ClaudeDiffBorder' },
  { '┬', 'ClaudeDiffBorder' },
  { '│', 'ClaudeDiffBorder' },
  { '┴', 'ClaudeDiffBorder' },
  { '─', 'ClaudeDiffBorder' },
  { '╰', 'ClaudeDiffBorder' },
  { '│', 'ClaudeDiffBorder' },
}

--- Border chars for right pane (connected to left)
local RIGHT_BORDER = {
  { '┬', 'ClaudeDiffBorder' },
  { '─', 'ClaudeDiffBorder' },
  { '╮', 'ClaudeDiffBorder' },
  { '│', 'ClaudeDiffBorder' },
  { '╯', 'ClaudeDiffBorder' },
  { '─', 'ClaudeDiffBorder' },
  { '┴', 'ClaudeDiffBorder' },
  { '│', 'ClaudeDiffBorder' },
}

--- Check if viewer is open
---@return boolean
function M.is_open()
  return M.left_win ~= nil and vim.api.nvim_win_is_valid(M.left_win)
end

--- Calculate floating window dimensions (80% of editor)
---@return table
local function calc_dimensions()
  local ew = vim.o.columns
  local eh = vim.o.lines

  local total_visual_w = math.floor(ew * 0.8)
  local content_h = math.floor(eh * 0.8) - 2

  local half_w = math.floor((total_visual_w - 3) / 2)
  local right_w = total_visual_w - half_w - 3

  local start_row = math.floor((eh - content_h - 2) / 2)
  local left_col = math.floor((ew - total_visual_w) / 2) + 1

  return {
    total_w = total_visual_w,
    half_w = half_w,
    right_w = right_w,
    content_h = content_h,
    start_row = start_row,
    left_col = left_col,
    right_col = left_col + half_w + 1,
  }
end

--- Place hunk signs on a buffer
---@param buf number
---@param hunks Hunk[]
---@param side 'old'|'new'
---@param active_idx number
local function place_hunk_signs(buf, hunks, side, active_idx)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(buf)

  for i, hunk in ipairs(hunks) do
    local start_line = side == 'old' and hunk.old_start or hunk.new_start
    local count = side == 'old' and hunk.old_count or hunk.new_count
    local is_active = (i == active_idx)

    local sign_hl = is_active and 'ClaudeDiffHunkActive' or 'ClaudeDiffHunkInactive'

    for l = start_line, math.min(start_line + count - 1, line_count) do
      if l >= 1 then
        vim.api.nvim_buf_set_extmark(buf, ns, l - 1, 0, {
          sign_text = '▌',
          sign_hl_group = sign_hl,
          priority = 100,
        })
      end
    end
  end
end

--- Update hunk signs on both buffers
---@param active_idx number
function M.update_signs(active_idx)
  place_hunk_signs(M.left_buf, M.hunks, 'old', active_idx)
  place_hunk_signs(M.right_buf, M.hunks, 'new', active_idx)
end

--- Build the file list from pending entries
---@return string[] list of relative paths
local function build_file_list()
  local entries = store.get_pending()
  local files = {}
  for _, entry in ipairs(entries) do
    table.insert(files, entry.file)
  end
  return files
end

--- Find index of a file in the file list
---@param file_list string[]
---@param file string
---@return number 0 if not found
local function find_file_idx(file_list, file)
  for i, f in ipairs(file_list) do
    if f == file then return i end
  end
  return 0
end

--- Build tab bar content with highlights (sliding window for many files)
---@param width number total width of the tab bar
---@return string line, table[] highlights
local function build_tab_content(width)
  local parts = {}
  local hls = {}
  local col = 0
  local total = #M.file_list
  local active = M.file_idx

  -- Sliding window: show up to MAX_VISIBLE tabs centered on active
  local MAX_VISIBLE = 7
  local half = math.floor(MAX_VISIBLE / 2)
  local vis_start = math.max(1, active - half)
  local vis_end = math.min(total, vis_start + MAX_VISIBLE - 1)
  vis_start = math.max(1, vis_end - MAX_VISIBLE + 1)

  -- Left overflow indicator
  if vis_start > 1 then
    local indicator = ' \u{25C0} '
    table.insert(parts, indicator)
    table.insert(hls, { col_start = col, col_end = col + #indicator, hl = 'ClaudeDiffBorder' })
    col = col + #indicator
  else
    table.insert(parts, '  ')
    col = col + 2
  end

  for i = vis_start, vis_end do
    local file = M.file_list[i]
    local name = vim.fn.fnamemodify(file, ':t')
    local is_active = (i == active)

    if i > vis_start then
      local sep = ' \u{2502} '
      table.insert(parts, sep)
      table.insert(hls, { col_start = col, col_end = col + #sep, hl = 'ClaudeDiffBorder' })
      col = col + #sep
    end

    local label = ' ' .. name .. ' '
    table.insert(parts, label)
    local hl_group = is_active and 'ClaudeDiffTabActive' or 'ClaudeDiffTabInactive'
    table.insert(hls, { col_start = col, col_end = col + #label, hl = hl_group })
    col = col + #label
  end

  -- Right overflow indicator
  if vis_end < total then
    local indicator = ' \u{25B6} '
    table.insert(parts, indicator)
    table.insert(hls, { col_start = col, col_end = col + #indicator, hl = 'ClaudeDiffBorder' })
    col = col + #indicator
  end

  -- Position indicator
  local pos = '  ' .. active .. '/' .. total
  table.insert(parts, pos)
  table.insert(hls, { col_start = col, col_end = col + #pos, hl = 'ClaudeDiffHelp' })
  col = col + #pos

  local line = table.concat(parts)

  -- Pad to width (use display width for correct multibyte alignment)
  local display_width = vim.fn.strdisplaywidth(line)
  if display_width < width then
    line = line .. string.rep(' ', width - display_width)
  end

  return line, hls
end

--- Create or update the tab bar window
---@param dim table dimensions from calc_dimensions
local function create_tab_bar(dim)
  local tab_ns = vim.api.nvim_create_namespace('claude_diff_tabs')
  local bar_width = dim.total_w
  local line, hls = build_tab_content(bar_width)

  if M.tab_buf and vim.api.nvim_buf_is_valid(M.tab_buf) then
    vim.bo[M.tab_buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.tab_buf, 0, -1, false, { line })
    vim.bo[M.tab_buf].modifiable = false
  else
    M.tab_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(M.tab_buf, 0, -1, false, { line })
    vim.bo[M.tab_buf].buftype = 'nofile'
    vim.bo[M.tab_buf].bufhidden = 'wipe'
    vim.bo[M.tab_buf].swapfile = false
    vim.bo[M.tab_buf].modifiable = false
  end

  -- Apply highlights
  vim.api.nvim_buf_clear_namespace(M.tab_buf, tab_ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(M.tab_buf, tab_ns, h.hl, 0, h.col_start, h.col_end)
  end

  if not M.tab_win or not vim.api.nvim_win_is_valid(M.tab_win) then
    M.tab_win = vim.api.nvim_open_win(M.tab_buf, false, {
      relative = 'editor',
      width = bar_width,
      height = 1,
      row = dim.start_row - 1,
      col = dim.left_col,
      style = 'minimal',
      border = 'none',
      focusable = false,
      zindex = 51,
    })

    vim.wo[M.tab_win].winhighlight = 'Normal:ClaudeDiffNormal'
  end
end

--- Setup autocmds for viewer lifecycle (WinClosed cleanup)
local function setup_autocmds()
  vim.api.nvim_clear_autocmds({ group = augroup })

  -- Auto-cleanup when a viewer window is closed externally
  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    callback = function(args)
      local closed_win = tonumber(args.match)
      if closed_win and (closed_win == M.left_win or closed_win == M.right_win) then
        -- Defer cleanup to avoid issues during WinClosed processing
        vim.schedule(function()
          M.close()
        end)
      end
    end,
  })
end

--- Create a scratch buffer with content for diff viewing
---@param name string buffer name (e.g., 'claude-diff://original/foo.lua')
---@param lines string[]
---@param ft string filetype
---@return number buf
local function create_diff_buffer(name, lines, ft)
  local existing = vim.fn.bufnr(name)
  if existing ~= -1 then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, name)
  if ft ~= '' then vim.bo[buf].filetype = ft end
  return buf
end

--- Create a floating window for diff viewing
---@param buf number
---@param opts table { dim, side:'left'|'right', title, footer, focus }
---@return number win
local function create_float_window(buf, opts)
  local is_left = opts.side == 'left'
  local win = vim.api.nvim_open_win(buf, opts.focus or false, {
    relative = 'editor',
    width = is_left and opts.dim.half_w or opts.dim.right_w,
    height = opts.dim.content_h,
    row = opts.dim.start_row,
    col = is_left and opts.dim.left_col or opts.dim.right_col,
    style = 'minimal',
    border = is_left and LEFT_BORDER or RIGHT_BORDER,
    title = opts.title,
    title_pos = 'center',
    footer = opts.footer,
    footer_pos = 'center',
    focusable = true,
    zindex = 50,
    noautocmd = true,
  })

  vim.wo[win].number = true
  vim.wo[win].signcolumn = 'yes:1'
  vim.wo[win].foldcolumn = '0'
  vim.wo[win].wrap = false
  vim.wo[win].winhighlight = is_left and WH_LEFT or WH_RIGHT
  return win
end

--- Enable diff mode on both windows
---@param left_win number
---@param right_win number
local function setup_diff_mode(left_win, right_win)
  vim.api.nvim_win_call(left_win, function()
    vim.cmd('noautocmd diffthis')
  end)
  vim.api.nvim_win_call(right_win, function()
    vim.cmd('noautocmd diffthis')
  end)
end

--- Internal open implementation
---@param relative_path string
local function _open_impl(relative_path)
  -- 1. Resolve file list and index
  if #M.file_list == 0 or find_file_idx(M.file_list, relative_path) == 0 then
    M.file_list = build_file_list()
  end
  M.file_idx = find_file_idx(M.file_list, relative_path)
  if M.file_idx == 0 then
    M.file_list = { relative_path }
    M.file_idx = 1
  end

  -- 2. Get content and metadata
  local old_lines, new_lines, _ = diff.get_file_lines(relative_path)
  M.current_file = relative_path

  local diff_text = diff.compute(relative_path)
  M.hunks = diff_text and diff.parse_hunks(diff_text) or {}
  M.current_hunk_idx = 0

  local ft = vim.filetype.match({ filename = relative_path }) or ''
  local dim = calc_dimensions()

  -- 3. Create buffers
  M.left_buf = create_diff_buffer('claude-diff://original/' .. relative_path, old_lines, ft)
  M.right_buf = create_diff_buffer('claude-diff://modified/' .. relative_path, new_lines, ft)

  -- 4. Create windows
  local hunk_info = #M.hunks > 0
    and (' ' .. #M.hunks .. (#M.hunks == 1 and ' hunk' or ' hunks'))
    or ''

  M.left_win = create_float_window(M.left_buf, {
    dim = dim,
    side = 'left',
    title = { { ' Original ', 'ClaudeDiffWinbarOriginal' } },
    footer = { { ' ' .. relative_path .. ' ', 'ClaudeDiffHelp' } },
  })

  M.right_win = create_float_window(M.right_buf, {
    dim = dim,
    side = 'right',
    focus = true,
    title = { { ' Modified' .. hunk_info .. ' ', 'ClaudeDiffWinbarModified' } },
    footer = { { ' Tab/S-Tab file  C-n/C-p hunk  a/x hunk  A/X file  q close ', 'ClaudeDiffHelp' } },
  })

  -- 5. Tab bar, diff mode, inline highlights, keymaps, autocmds
  if #M.file_list > 1 then
    create_tab_bar(dim)
  end

  pcall(function() vim.wo[M.left_win].winfixbuf = true end)
  pcall(function() vim.wo[M.right_win].winfixbuf = true end)

  setup_diff_mode(M.left_win, M.right_win)
  require('claude-diff.ui.inline_diff').apply(M.left_buf, M.right_buf, M.left_win, M.right_win, old_lines, new_lines, M.hunks)

  M.setup_keymaps(M.left_buf)
  M.setup_keymaps(M.right_buf)
  setup_autocmds()
  M.update_signs(0)

  -- 6. Focus and jump to first hunk
  vim.api.nvim_set_current_win(M.right_win)
  if #M.hunks > 0 then
    M.goto_hunk(1)
  end
end

--- Helper: close a window safely
---@param win number|nil
local function safe_close_win(win)
  if not win then return end
  if not vim.api.nvim_win_is_valid(win) then return end
  pcall(vim.api.nvim_win_close, win, true)
end

--- Helper: delete a buffer safely
---@param buf number|nil
local function safe_delete_buf(buf)
  if not buf then return end
  if not vim.api.nvim_buf_is_valid(buf) then return end
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

--- Helper: run diffoff on a window safely
---@param win number|nil
local function safe_diffoff(win)
  if not win then return end
  if not vim.api.nvim_win_is_valid(win) then return end
  pcall(vim.api.nvim_win_call, win, function()
    vim.cmd('noautocmd diffoff')
  end)
end

--- Close windows and buffers without resetting navigation state (file_list, file_idx)
local function close_windows()
  vim.api.nvim_clear_autocmds({ group = augroup })
  require('claude-diff.ui.inline_diff').clear(M.left_buf, M.right_buf)

  safe_diffoff(M.left_win)
  safe_diffoff(M.right_win)

  safe_close_win(M.tab_win)
  safe_close_win(M.left_win)
  safe_close_win(M.right_win)

  safe_delete_buf(M.tab_buf)
  safe_delete_buf(M.left_buf)
  safe_delete_buf(M.right_buf)

  M.tab_buf = nil
  M.tab_win = nil
  M.left_buf = nil
  M.left_win = nil
  M.right_buf = nil
  M.right_win = nil
  M.current_file = nil
  M.hunks = {}
  M.current_hunk_idx = 0

  -- Safety net: if we're still in a floating window after cleanup, escape to a normal window
  local cur_win = vim.api.nvim_get_current_win()
  local ok_cfg, cur_cfg = pcall(vim.api.nvim_win_get_config, cur_win)
  if ok_cfg and cur_cfg.relative and cur_cfg.relative ~= '' then
    pcall(vim.api.nvim_win_close, cur_win, true)

    cur_win = vim.api.nvim_get_current_win()
    ok_cfg, cur_cfg = pcall(vim.api.nvim_win_get_config, cur_win)
    if ok_cfg and cur_cfg.relative and cur_cfg.relative ~= '' then
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local w_ok, w_cfg = pcall(vim.api.nvim_win_get_config, w)
        if w_ok and (not w_cfg.relative or w_cfg.relative == '') then
          pcall(vim.api.nvim_set_current_win, w)
          break
        end
      end
    end
  end
end

--- Reset all navigation state
local function reset_state()
  M.file_list = {}
  M.file_idx = 0
end

--- Open diff view as a floating modal
---@param relative_path string
function M.open(relative_path)
  close_windows()

  local ok, err = pcall(_open_impl, relative_path)
  if not ok then
    close_windows()
    reset_state()
    vim.notify('claude-diff viewer error: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

--- Close the viewer completely
function M.close()
  close_windows()
  reset_state()
end

--- Navigate to a specific hunk
---@param idx number 1-based hunk index
function M.goto_hunk(idx)
  if idx < 1 or idx > #M.hunks then return end

  M.current_hunk_idx = idx
  local hunk = M.hunks[idx]

  -- Update signs to highlight active hunk
  M.update_signs(idx)

  if M.left_win and vim.api.nvim_win_is_valid(M.left_win) then
    local line = math.max(1, math.min(hunk.old_start, vim.api.nvim_buf_line_count(M.left_buf)))
    vim.api.nvim_win_set_cursor(M.left_win, { line, 0 })
  end

  if M.right_win and vim.api.nvim_win_is_valid(M.right_win) then
    local line = math.max(1, math.min(hunk.new_start, vim.api.nvim_buf_line_count(M.right_buf)))
    vim.api.nvim_win_set_cursor(M.right_win, { line, 0 })

    pcall(vim.api.nvim_win_set_config, M.right_win, {
      title = { {
        ' Modified  hunk ' .. idx .. '/' .. #M.hunks .. ' ',
        'ClaudeDiffWinbarModified',
      } },
      title_pos = 'center',
    })
  end
end

function M.next_hunk()
  if #M.hunks == 0 then return end
  if M.current_hunk_idx < #M.hunks then
    M.goto_hunk(M.current_hunk_idx + 1)
  end
end

function M.prev_hunk()
  if #M.hunks == 0 then return end
  if M.current_hunk_idx > 1 then
    M.goto_hunk(M.current_hunk_idx - 1)
  end
end

function M.refresh()
  if not M.current_file then return end
  M.open(M.current_file)
end


--- Navigate to a file in the pending list by direction.
---@param target 'next'|'prev'|'current'
local function navigate_to(target)
  local files = build_file_list()
  if #files == 0 then
    M.close()
    return
  end

  local cur_idx = find_file_idx(files, M.current_file)
  local target_idx

  if target == 'next' then
    if cur_idx > 0 and cur_idx < #files then
      target_idx = cur_idx + 1
    elseif cur_idx == 0 then
      target_idx = math.min(M.file_idx, #files)
    else
      return -- already at end
    end
  elseif target == 'prev' then
    if cur_idx > 1 then
      target_idx = cur_idx - 1
    elseif cur_idx == 0 then
      target_idx = math.max(1, math.min(M.file_idx - 1, #files))
    else
      return -- already at start
    end
  else -- 'current' (used by navigate_after_action)
    target_idx = math.min(M.file_idx, #files)
  end

  M.file_list = files
  M.open(files[target_idx])
end

--- Navigate to the next pending file after approve/reject.
function M.navigate_after_action()
  navigate_to('current')
end

--- Navigate to the next file in the list
function M.next_file()
  navigate_to('next')
end

--- Navigate to the previous file in the list
function M.prev_file()
  navigate_to('prev')
end

--- Switch focus to the other pane
local function switch_pane()
  local cur = vim.api.nvim_get_current_win()
  if cur == M.left_win then
    if M.right_win and vim.api.nvim_win_is_valid(M.right_win) then
      vim.api.nvim_set_current_win(M.right_win)
    end
  else
    if M.left_win and vim.api.nvim_win_is_valid(M.left_win) then
      vim.api.nvim_set_current_win(M.left_win)
    end
  end
end

--- Setup keymaps for viewer buffers
---@param buf number
function M.setup_keymaps(buf)
  local km = config.get().keymaps
  local bopts = { buffer = buf, noremap = true, silent = true, nowait = true }

  vim.keymap.set('n', km.next_hunk, function() M.next_hunk() end, bopts)
  vim.keymap.set('n', km.prev_hunk, function() M.prev_hunk() end, bopts)

  -- In viewer: approve_hunk/reject_hunk = hunk, approve_file/reject_file = whole file
  vim.keymap.set('n', km.approve_hunk, function()
    if M.current_hunk_idx > 0 and M.current_file then
      require('claude-diff.actions').approve_hunk(M.current_file, M.current_hunk_idx)
    end
  end, bopts)

  vim.keymap.set('n', km.reject_hunk, function()
    if M.current_hunk_idx > 0 and M.current_file then
      require('claude-diff.actions').reject_hunk(M.current_file, M.current_hunk_idx)
    end
  end, bopts)

  vim.keymap.set('n', km.approve_file, function()
    if M.current_file then
      require('claude-diff.actions').approve_file(M.current_file)
    end
  end, bopts)

  vim.keymap.set('n', km.reject_file, function()
    if M.current_file then
      require('claude-diff.actions').reject_file(M.current_file)
    end
  end, bopts)

  vim.keymap.set('n', km.close, function() M.close() end, bopts)
  vim.keymap.set('n', '<Esc>', function() M.close() end, bopts)

  -- File navigation
  vim.keymap.set('n', '<Tab>', function() M.next_file() end, bopts)
  vim.keymap.set('n', '<S-Tab>', function() M.prev_file() end, bopts)

  -- Window navigation: all <C-w> movement and common remaps switch between panes
  local nav_bopts = { buffer = buf, noremap = true, silent = true }
  for _, lhs in ipairs({
    '<C-w>h', '<C-w><C-h>',
    '<C-w>l', '<C-w><C-l>',
    '<C-w>w', '<C-w><C-w>',
    '<C-w>j', '<C-w><C-j>',
    '<C-w>k', '<C-w><C-k>',
    '<C-w>p',
    '<C-h>', '<C-j>', '<C-k>', '<C-l>',
  }) do
    vim.keymap.set('n', lhs, switch_pane, nav_bopts)
  end

  -- Disable commands that could mess with the viewer buffers
  for _, lhs in ipairs({ 'dp', 'do', 'dP', 'dO', '<S-h>', '<S-l>' }) do
    vim.keymap.set('n', lhs, '', bopts)
  end
end

return M
