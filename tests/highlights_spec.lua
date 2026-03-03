describe('highlights', function()
  local highlights

  before_each(function()
    package.loaded['claude-diff.ui.highlights'] = nil
    highlights = require('claude-diff.ui.highlights')
  end)

  it('applies dark theme highlights by default', function()
    vim.o.background = 'dark'
    highlights.setup()
    local hl = vim.api.nvim_get_hl(0, { name = 'ClaudeDiffAdd' })
    assert.equals(tonumber('1e3a28', 16), hl.bg)
  end)

  it('applies light theme highlights when background is light', function()
    vim.o.background = 'light'
    highlights.setup()
    local hl = vim.api.nvim_get_hl(0, { name = 'ClaudeDiffAdd' })
    assert.equals(tonumber('d4edda', 16), hl.bg)
    vim.o.background = 'dark' -- restore
  end)

  it('updates highlights on colorscheme change', function()
    vim.o.background = 'dark'
    highlights.setup()

    vim.o.background = 'light'
    vim.cmd('doautocmd ColorScheme')
    local hl = vim.api.nvim_get_hl(0, { name = 'ClaudeDiffDelete' })
    assert.equals(tonumber('f8d7da', 16), hl.bg)
    vim.o.background = 'dark' -- restore
  end)
end)
