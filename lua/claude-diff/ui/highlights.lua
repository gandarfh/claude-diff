local M = {}

local function apply()
  local hl = vim.api.nvim_set_hl

  -- Floating windows
  hl(0, 'ClaudeDiffNormal', { link = 'NormalFloat' })
  hl(0, 'ClaudeDiffBorder', { link = 'FloatBorder' })
  hl(0, 'ClaudeDiffTitle', { link = 'FloatTitle' })

  -- File list entries
  hl(0, 'ClaudeDiffModified', { link = 'DiagnosticWarn' })
  hl(0, 'ClaudeDiffNewFile', { link = 'DiagnosticOk' })
  hl(0, 'ClaudeDiffFilePath', { link = 'Comment' })

  -- Help / footer
  hl(0, 'ClaudeDiffHelp', { link = 'Comment' })

  -- Viewer winbar titles
  hl(0, 'ClaudeDiffWinbarOriginal', { link = 'DiagnosticError' })
  hl(0, 'ClaudeDiffWinbarModified', { link = 'DiagnosticOk' })

  -- Diff backgrounds (only bg, no fg change)
  hl(0, 'ClaudeDiffAdd', { bg = '#1e3a28' })
  hl(0, 'ClaudeDiffDelete', { bg = '#3a1e22' })
  hl(0, 'ClaudeDiffChange', { bg = 'NONE' })
  hl(0, 'ClaudeDiffText', { bg = 'NONE' })

  -- Hunk signs in sign column
  hl(0, 'ClaudeDiffHunkActive', { fg = '#61afef' })
  hl(0, 'ClaudeDiffHunkInactive', { fg = '#3e4452' })

  -- File tabs in viewer
  hl(0, 'ClaudeDiffTabActive', { fg = '#61afef', bold = true })
  hl(0, 'ClaudeDiffTabInactive', { link = 'Comment' })
end

function M.setup()
  apply()

  -- Re-apply after colorscheme changes
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('ClaudeDiffHighlights', { clear = true }),
    callback = apply,
  })
end

return M
