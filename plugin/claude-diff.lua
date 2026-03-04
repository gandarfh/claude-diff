if vim.g.loaded_claude_diff then
  return
end
vim.g.loaded_claude_diff = true

-- Require Neovim 0.9+ for vim.diff and modern APIs
if vim.fn.has('nvim-0.9') == 0 then
  vim.notify('claude-diff.nvim requires Neovim 0.9+', vim.log.levels.ERROR)
  return
end

-- User commands
vim.api.nvim_create_user_command('ClaudeDiff', function()
  require('claude-diff').toggle()
end, { desc = 'Toggle Claude Diff review UI' })

vim.api.nvim_create_user_command('ClaudeDiffOpen', function()
  require('claude-diff').open()
end, { desc = 'Open Claude Diff review UI' })

vim.api.nvim_create_user_command('ClaudeDiffClose', function()
  require('claude-diff').close()
end, { desc = 'Close Claude Diff review UI' })

vim.api.nvim_create_user_command('ClaudeDiffRefresh', function()
  require('claude-diff').refresh()
end, { desc = 'Refresh Claude Diff file list' })

vim.api.nvim_create_user_command('ClaudeDiffApproveAll', function()
  require('claude-diff.actions').approve_all()
end, { desc = 'Approve all pending changes' })

vim.api.nvim_create_user_command('ClaudeDiffRejectAll', function()
  require('claude-diff.actions').reject_all()
end, { desc = 'Reject all pending changes' })

vim.api.nvim_create_user_command('ClaudeDiffPlan', function()
  require('claude-diff').open_plan()
end, { desc = 'Open Claude plan preview' })

vim.api.nvim_create_user_command('ClaudeDiffPlanClose', function()
  require('claude-diff').close_plan()
end, { desc = 'Close Claude plan preview' })

