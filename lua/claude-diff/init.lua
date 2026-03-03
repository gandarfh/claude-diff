local M = {}

--- Setup the plugin with user options
---@param opts? table
function M.setup(opts)
  require('claude-diff.config').setup(opts)
  require('claude-diff.ui.highlights').setup()
end

--- Open the Claude Diff review UI
function M.open()
  local panel = require('claude-diff.ui.panel')
  panel.open()
end

--- Close all Claude Diff UI
function M.close()
  local viewer = require('claude-diff.ui.viewer')
  local panel = require('claude-diff.ui.panel')

  viewer.close()
  panel.close()
end

--- Toggle the UI open/closed
function M.toggle()
  local panel = require('claude-diff.ui.panel')
  if panel.is_open() then
    M.close()
  else
    M.open()
  end
end

--- Refresh the file list
function M.refresh()
  local store = require('claude-diff.store')
  local panel = require('claude-diff.ui.panel')
  store.invalidate_cache()
  if panel.is_open() then
    panel.render()
  end
end

return M
