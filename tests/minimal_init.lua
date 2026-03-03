-- Minimal init for running tests with plenary
-- Usage: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

-- Add plenary to rtp
local plenary_path = vim.fn.expand('~/.local/share/nvim/lazy/plenary.nvim')
vim.opt.rtp:prepend(plenary_path)

-- Add the plugin itself to rtp
local plugin_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
vim.opt.rtp:prepend(plugin_path)

-- Ensure our lua modules are always findable even when cwd changes
-- Neovim's loader uses both rtp and package.path
package.path = plugin_path .. '/lua/?.lua;'
  .. plugin_path .. '/lua/?/init.lua;'
  .. plugin_path .. '/tests/?.lua;'
  .. package.path

-- Pre-load all plugin modules so they are available on first require
require('claude-diff.config')
require('claude-diff.store')
require('claude-diff.diff')
require('claude-diff.ui.highlights')
require('claude-diff.ui.panel')
require('claude-diff.ui.viewer')
require('claude-diff.actions')
require('claude-diff.init')

-- Alias: panel.lua uses require('claude-diff') which resolves to init.lua
package.loaded['claude-diff'] = package.loaded['claude-diff.init']

-- Disable swap files for tests
vim.o.swapfile = false
