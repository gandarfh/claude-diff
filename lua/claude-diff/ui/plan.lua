local config = require('claude-diff.config')

local M = {}

M.buf = nil
M.win = nil

--- Check if plan preview is open
---@return boolean
function M.is_open()
  return M.win ~= nil and vim.api.nvim_win_is_valid(M.win)
end

--- Resolve the current plan file path
--- Reads from <cwd>/<storage_dir>/current-plan
---@return string|nil absolute path to plan markdown file
function M.resolve_plan_path()
  local storage_dir = config.get().storage_dir
  local pointer_file = vim.fn.getcwd() .. '/' .. storage_dir .. '/current-plan'

  if vim.fn.filereadable(pointer_file) ~= 1 then
    return nil
  end

  local lines = vim.fn.readfile(pointer_file)
  if #lines == 0 or lines[1] == '' then
    return nil
  end

  local plan_path = vim.fn.expand(lines[1])

  if vim.fn.filereadable(plan_path) ~= 1 then
    return nil
  end

  return plan_path
end

--- Calculate window dimensions (80% of editor)
---@return table {width, height, row, col}
local function calc_dimensions()
  local ew = vim.o.columns
  local eh = vim.o.lines

  local width = math.floor(ew * 0.8)
  local height = math.floor(eh * 0.8)

  local row = math.max(0, math.floor((eh - height) / 2) - 1)
  local col = math.floor((ew - width) / 2)

  return { width = width, height = height, row = row, col = col }
end

--- Setup keymaps for the plan buffer
---@param buf number
local function setup_keymaps(buf)
  local bopts = { buffer = buf, noremap = true, silent = true, nowait = true }

  vim.keymap.set('n', 'q', function() M.close() end, bopts)
  vim.keymap.set('n', '<Esc>', function() M.close() end, bopts)
end

--- Open the plan preview floating window
---@param plan_path? string override plan path (for testing)
function M.open(plan_path)
  if M.is_open() then
    vim.api.nvim_set_current_win(M.win)
    return
  end

  plan_path = plan_path or M.resolve_plan_path()
  if not plan_path then
    vim.notify('claude-diff: no plan found. Check if .claude-diff/current-plan exists.', vim.log.levels.WARN)
    return
  end

  local buf = vim.fn.bufadd(plan_path)
  -- Ensure fresh content: unlock, reload from disk, then lock
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.fn.bufload(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd('silent! edit!')
  end)
  M.buf = buf

  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true

  local dim = calc_dimensions()
  local plan_name = vim.fn.fnamemodify(plan_path, ':t:r')
  local title = ' Plan: ' .. plan_name .. ' '
  local footer = ' q close '

  M.win = vim.api.nvim_open_win(buf, true, {
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

  vim.wo[M.win].number = true
  vim.wo[M.win].relativenumber = false
  vim.wo[M.win].signcolumn = 'no'
  vim.wo[M.win].wrap = true
  vim.wo[M.win].linebreak = true
  vim.wo[M.win].cursorline = false
  vim.wo[M.win].winhighlight = 'Normal:ClaudeDiffNormal,FloatBorder:ClaudeDiffBorder,CursorLine:Visual'
  vim.wo[M.win].conceallevel = 2
  vim.wo[M.win].concealcursor = 'nvic'

  vim.bo[buf].filetype = 'markdown'
  pcall(vim.treesitter.start, buf, 'markdown')

  setup_keymaps(buf)
end

--- Close the plan preview
function M.close()
  if M.win then
    pcall(vim.api.nvim_win_close, M.win, true)
  end

  M.win = nil
  M.buf = nil

  -- Safety net: escape from floating window if stuck
  local cur_win = vim.api.nvim_get_current_win()
  local ok_cfg, cur_cfg = pcall(vim.api.nvim_win_get_config, cur_win)
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

--- Install the plan-watcher hook into .claude/hooks/
function M.install_hook()
  local hooks_dir = vim.fn.getcwd() .. '/.claude/hooks'
  vim.fn.mkdir(hooks_dir, 'p')

  local hook_path = hooks_dir .. '/plan-watcher.sh'
  if vim.fn.filereadable(hook_path) == 1 then
    vim.notify('claude-diff: hook already exists at ' .. hook_path, vim.log.levels.INFO)
    return
  end

  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h:h')
  local source = plugin_dir .. '/hooks/plan-watcher.sh'

  if vim.fn.filereadable(source) ~= 1 then
    vim.notify('claude-diff: cannot find hook template at ' .. source, vim.log.levels.ERROR)
    return
  end

  vim.fn.writefile(vim.fn.readfile(source), hook_path)
  vim.fn.setfperm(hook_path, 'rwxr-xr-x')

  vim.notify(
    'claude-diff: hook installed at ' .. hook_path
      .. '\nAdd to .claude/settings.json:\n'
      .. '  "hooks": { "PostToolUse": [{ "matcher": "Write", "hooks": [{ "type": "command", "command": ".claude/hooks/plan-watcher.sh" }] }] }',
    vim.log.levels.INFO
  )
end

return M
