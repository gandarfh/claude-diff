local M = {}

M.defaults = {
  storage_dir = '.claude-diff',
  panel_width = 35,
  auto_refresh = true,
  icons = {
    modified = '●',
    new_file = '+',
    approved = '✓',
  },
  keymaps = {
    open = '<leader>cd',
    approve_file = 'a',
    reject_file = 'x',
    approve_all = 'A',
    reject_all = 'X',
    refresh = 'r',
    close = 'q',
    open_diff = '<CR>',
    next_hunk = '<C-n>',
    prev_hunk = '<C-p>',
    approve_hunk = '<leader>ha',
    reject_hunk = '<leader>hx',
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', {}, M.defaults, opts or {})
end

function M.get()
  if vim.tbl_isempty(M.options) then
    M.setup({})
  end
  return M.options
end

return M
