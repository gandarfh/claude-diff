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

  local is_dark = vim.o.background ~= 'light'

  -- Diff backgrounds (only bg, no fg change)
  hl(0, 'ClaudeDiffAdd', { bg = is_dark and '#1e3a28' or '#d4edda' })
  hl(0, 'ClaudeDiffDelete', { bg = is_dark and '#3a1e22' or '#f8d7da' })
  hl(0, 'ClaudeDiffChange', { bg = 'NONE' })
  hl(0, 'ClaudeDiffText', { bg = 'NONE' })

  -- DiffChange per-side: dim background for the whole changed line
  hl(0, 'ClaudeDiffChangeDel', { bg = is_dark and '#2a1a1e' or '#fce4ec' })
  hl(0, 'ClaudeDiffChangeAdd', { bg = is_dark and '#1a2a20' or '#e8f5e9' })

  -- Character-level inline diff (bright bg for the actual changed characters)
  hl(0, 'ClaudeDiffDeleteText', { bg = is_dark and '#6e3040' or '#e57373' })
  hl(0, 'ClaudeDiffAddText', { bg = is_dark and '#2a6e3e' or '#66bb6a' })

  -- Hunk signs in sign column
  hl(0, 'ClaudeDiffHunkActive', { fg = is_dark and '#61afef' or '#1976d2' })
  hl(0, 'ClaudeDiffHunkInactive', { fg = is_dark and '#3e4452' or '#bdbdbd' })

  -- File tabs in viewer
  hl(0, 'ClaudeDiffTabActive', { fg = is_dark and '#61afef' or '#1976d2', bold = true })
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
