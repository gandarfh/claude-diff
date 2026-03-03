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

  -- Pad to width
  if #line < width then
    line = line .. string.rep(' ', width - #line)
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

--- Internal open implementation
---@param relative_path string
local function _open_impl(relative_path)
  -- Restore or rebuild file list
  if #M.file_list == 0 or find_file_idx(M.file_list, relative_path) == 0 then
    M.file_list = build_file_list()
  end
  M.file_idx = find_file_idx(M.file_list, relative_path)
  if M.file_idx == 0 then
    M.file_list = { relative_path }
    M.file_idx = 1
  end

  local old_lines, new_lines, _ = diff.get_file_lines(relative_path)
  M.current_file = relative_path

  local diff_text = diff.compute(relative_path)
  M.hunks = diff_text and diff.parse_hunks(diff_text) or {}
  M.current_hunk_idx = 0

  local ft = vim.filetype.match({ filename = relative_path }) or ''
  local dim = calc_dimensions()

  -- Wipe any stale buffers with the same name
  local left_name = 'claude-diff://original/' .. relative_path
  local right_name = 'claude-diff://modified/' .. relative_path
  for _, name in ipairs({ left_name, right_name }) do
    local existing = vim.fn.bufnr(name)
    if existing ~= -1 then
      pcall(vim.api.nvim_buf_delete, existing, { force = true })
    end
  end

  -- Create original (left) buffer
  M.left_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(M.left_buf, 0, -1, false, old_lines)
  vim.bo[M.left_buf].buftype = 'nofile'
  vim.bo[M.left_buf].bufhidden = 'wipe'
  vim.bo[M.left_buf].swapfile = false
  vim.bo[M.left_buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, M.left_buf, left_name)
  if ft ~= '' then vim.bo[M.left_buf].filetype = ft end

  -- Create modified (right) buffer
  M.right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(M.right_buf, 0, -1, false, new_lines)
  vim.bo[M.right_buf].buftype = 'nofile'
  vim.bo[M.right_buf].bufhidden = 'wipe'
  vim.bo[M.right_buf].swapfile = false
  vim.bo[M.right_buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, M.right_buf, right_name)
  if ft ~= '' then vim.bo[M.right_buf].filetype = ft end

  local hunk_info = #M.hunks > 0
    and (' ' .. #M.hunks .. (#M.hunks == 1 and ' hunk' or ' hunks'))
    or ''

  -- Left floating window (original) — noautocmd prevents user autocmds from interfering
  M.left_win = vim.api.nvim_open_win(M.left_buf, false, {
    relative = 'editor',
    width = dim.half_w,
    height = dim.content_h,
    row = dim.start_row,
    col = dim.left_col,
    style = 'minimal',
    border = LEFT_BORDER,
    title = { { ' Original ', 'ClaudeDiffWinbarOriginal' } },
    title_pos = 'center',
    footer = { { ' ' .. relative_path .. ' ', 'ClaudeDiffHelp' } },
    footer_pos = 'center',
    focusable = true,
    zindex = 50,
    noautocmd = true,
  })

  vim.wo[M.left_win].number = true
  vim.wo[M.left_win].signcolumn = 'yes:1'
  vim.wo[M.left_win].foldcolumn = '0'
  vim.wo[M.left_win].wrap = false
  vim.wo[M.left_win].winhighlight = WH_LEFT

  -- Right floating window (modified) — noautocmd prevents user autocmds from interfering
  M.right_win = vim.api.nvim_open_win(M.right_buf, true, {
    relative = 'editor',
    width = dim.right_w,
    height = dim.content_h,
    row = dim.start_row,
    col = dim.right_col,
    style = 'minimal',
    border = RIGHT_BORDER,
    title = { { ' Modified' .. hunk_info .. ' ', 'ClaudeDiffWinbarModified' } },
    title_pos = 'center',
    footer = { { ' Tab/S-Tab file  C-n/C-p hunk  a/x hunk  A/X file  q close ', 'ClaudeDiffHelp' } },
    footer_pos = 'center',
    focusable = true,
    zindex = 50,
    noautocmd = true,
  })

  vim.wo[M.right_win].number = true
  vim.wo[M.right_win].signcolumn = 'yes:1'
  vim.wo[M.right_win].foldcolumn = '0'
  vim.wo[M.right_win].wrap = false
  vim.wo[M.right_win].winhighlight = WH_RIGHT

  -- Create tab bar above the panes (after panes so we know positions)
  if #M.file_list > 1 then
    create_tab_bar(dim)
  end

  -- Lock buffers to their windows
  for _, win in ipairs({ M.left_win, M.right_win }) do
    pcall(function() vim.wo[win].winfixbuf = true end)
  end

  -- Enable diff mode on both — use noautocmd to prevent user autocmds from firing
  -- during the temporary window switches
  vim.api.nvim_win_call(M.left_win, function()
    vim.cmd('noautocmd diffthis')
  end)
  vim.api.nvim_win_call(M.right_win, function()
    vim.cmd('noautocmd diffthis')
  end)

  -- Apply character-level inline diff highlights
  require('claude-diff.ui.inline_diff').apply(M.left_buf, M.right_buf, M.left_win, M.right_win, old_lines, new_lines, M.hunks)

  -- Setup keymaps on both buffers
  M.setup_keymaps(M.left_buf)
  M.setup_keymaps(M.right_buf)

  -- Setup autocmds for viewer lifecycle
  setup_autocmds()

  -- Place initial hunk signs (no active hunk yet)
  M.update_signs(0)

  -- Focus modified side and jump to first hunk
  vim.api.nvim_set_current_win(M.right_win)
  if #M.hunks > 0 then
    M.goto_hunk(1)
  end
end

--- Open diff view as a floating modal
---@param relative_path string
function M.open(relative_path)
  -- Save file list before closing (close resets it)
  local saved_file_list = M.file_list

  M.close()

  -- Restore saved file list
  if #saved_file_list > 0 then
    M.file_list = saved_file_list
  end

  local ok, err = pcall(_open_impl, relative_path)
  if not ok then
    M.close()
    vim.notify('claude-diff viewer error: ' .. tostring(err), vim.log.levels.ERROR)
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

--- Close the viewer
function M.close()
  -- Clear autocmds first to prevent WinClosed from re-triggering close
  vim.api.nvim_clear_autocmds({ group = augroup })

  -- Clear inline diff highlights before closing
  require('claude-diff.ui.inline_diff').clear(M.left_buf, M.right_buf)

  -- Diffoff on each diff window (explicit calls, no ipairs with nil holes)
  safe_diffoff(M.left_win)
  safe_diffoff(M.right_win)

  -- Close all windows (explicit calls, no ipairs with nil holes)
  safe_close_win(M.tab_win)
  safe_close_win(M.left_win)
  safe_close_win(M.right_win)

  -- Force-delete buffers
  safe_delete_buf(M.tab_buf)
  safe_delete_buf(M.left_buf)
  safe_delete_buf(M.right_buf)

  -- Reset all state
  M.tab_buf = nil
  M.tab_win = nil
  M.left_buf = nil
  M.left_win = nil
  M.right_buf = nil
  M.right_win = nil
  M.current_file = nil
  M.hunks = {}
  M.current_hunk_idx = 0
  M.file_list = {}
  M.file_idx = 0

  -- Safety net: if we're still in a floating window after cleanup, escape to a normal window
  local cur_win = vim.api.nvim_get_current_win()
  local ok_cfg, cur_cfg = pcall(vim.api.nvim_win_get_config, cur_win)
  if ok_cfg and cur_cfg.relative and cur_cfg.relative ~= '' then
    pcall(vim.api.nvim_win_close, cur_win, true)

    -- If still floating, find any normal window
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


--- Rebuild file list from pending, keeping current file for preview
---@return string[] updated file list
local function rebuild_file_list_for_nav()
  local pending = build_file_list()
  -- If current file is not in pending (already approved), that's fine —
  -- we just navigate to pending files only
  return pending
end

--- Navigate to the next pending file after approve/reject.
--- Goes to next file, or previous if at end, or closes if none left.
function M.navigate_after_action()
  local files = rebuild_file_list_for_nav()
  if #files == 0 then
    M.close()
    return
  end

  -- Try to stay at same position or go to previous if we were at the end
  local target_idx = math.min(M.file_idx, #files)
  M.file_list = files
  M.open(files[target_idx])
end

--- Navigate to the next file in the list
function M.next_file()
  -- Rebuild list from pending to skip already-approved files
  local files = rebuild_file_list_for_nav()
  if #files == 0 then return end

  -- Find where current file sits relative to pending list
  local cur_idx = find_file_idx(files, M.current_file)
  if cur_idx > 0 and cur_idx < #files then
    -- Current file is in list, go to next
    M.file_list = files
    M.open(files[cur_idx + 1])
  elseif cur_idx == 0 then
    -- Current file was approved (not in pending), find next by position
    local target_idx = math.min(M.file_idx, #files)
    M.file_list = files
    M.open(files[target_idx])
  end
end

--- Navigate to the previous file in the list
function M.prev_file()
  -- Rebuild list from pending to skip already-approved files
  local files = rebuild_file_list_for_nav()
  if #files == 0 then return end

  -- Find where current file sits relative to pending list
  local cur_idx = find_file_idx(files, M.current_file)
  if cur_idx > 1 then
    M.file_list = files
    M.open(files[cur_idx - 1])
  elseif cur_idx == 0 then
    -- Current file was approved, find prev by position
    local target_idx = math.max(1, math.min(M.file_idx - 1, #files))
    M.file_list = files
    M.open(files[target_idx])
  end
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
