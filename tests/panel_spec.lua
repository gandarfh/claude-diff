local helpers = require('tests.helpers')

describe('panel', function()
  local panel, store, config
  local test_dir

  before_each(function()
    test_dir = helpers.create_temp_dir()

    config = require('claude-diff.config')
    config.setup({ storage_dir = '.claude-diff' })
    require('claude-diff.ui.highlights').setup()

    -- Pre-load lazy-required modules before cwd changes (plenary clears package.loaded)
    require('claude-diff.actions')
    require('claude-diff.init')
    package.loaded['claude-diff'] = package.loaded['claude-diff.init']

    store = require('claude-diff.store')
    panel = require('claude-diff.ui.panel')
  end)

  after_each(function()
    pcall(function() panel.close() end)
    pcall(function() require('claude-diff.ui.viewer').close() end)
    helpers.remove_dir(test_dir)
  end)

  local function setup_two_files()
    helpers.setup_project({
      dir = test_dir,
      files = {
        ['a.lua'] = 'line1\nmodified\nline3\n',
        ['b.lua'] = 'hello\nworld\nchanged\n',
      },
      snapshots = {
        ['a.lua'] = 'line1\noriginal\nline3\n',
        ['b.lua'] = 'hello\nworld\noriginal\n',
      },
      pending = {
        { file = 'a.lua', is_new = false },
        { file = 'b.lua', is_new = false },
      },
    })
  end

  describe('is_open', function()
    it('returns false when panel is not open', function()
      assert.is_false(panel.is_open())
    end)

    it('returns true when panel is open', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()
        panel.open()
        assert.is_true(panel.is_open())
      end)
    end)
  end)

  describe('open and close', function()
    it('opens with valid window and buffer', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        panel.open()

        assert.is_true(panel.is_open())
        assert.is_not_nil(panel.win)
        assert.is_not_nil(panel.buf)
        assert.is_true(vim.api.nvim_win_is_valid(panel.win))
        assert.is_true(vim.api.nvim_buf_is_valid(panel.buf))
      end)
    end)

    it('closes cleanly', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        panel.open()
        panel.close()

        assert.is_false(panel.is_open())
        assert.is_nil(panel.win)
        assert.is_nil(panel.buf)
      end)
    end)

    it('can reopen after close', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        panel.open()
        panel.close()
        panel.open()

        assert.is_true(panel.is_open())
      end)
    end)
  end)

  describe('render', function()
    it('shows file entries when pending files exist', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        panel.open()

        assert.equals(2, #panel.entries)
        assert.equals('a.lua', panel.entries[1].file)
        assert.equals('b.lua', panel.entries[2].file)
      end)
    end)

    it('updates title with file count', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        panel.open()

        local win_config = vim.api.nvim_win_get_config(panel.win)
        -- Title should contain the count
        local title_text = win_config.title[1][1]
        assert.truthy(title_text:find('2'), 'title should show count of 2 files')
      end)
    end)

    it('shows empty message when no pending files', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          files = {},
          snapshots = {},
          pending = {},
        })

        panel.open()

        assert.equals(0, #panel.entries)
        -- Buffer should contain "No pending changes"
        local lines = vim.api.nvim_buf_get_lines(panel.buf, 0, -1, false)
        local found = false
        for _, line in ipairs(lines) do
          if line:find('No pending changes') then found = true end
        end
        assert.is_true(found, 'should show "No pending changes" message')
      end)
    end)
  end)

  describe('keymaps', function()
    it('has expected keymaps on buffer', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        panel.open()

        local maps = vim.api.nvim_buf_get_keymap(panel.buf, 'n')
        local found_keys = {}
        for _, map in ipairs(maps) do
          found_keys[map.lhs] = true
        end

        assert.is_true(found_keys['q'] ~= nil, 'missing q keymap')
        assert.is_true(found_keys['<Esc>'] ~= nil, 'missing Esc keymap')
        assert.is_true(found_keys['<CR>'] ~= nil, 'missing Enter keymap')
        assert.is_true(found_keys['a'] ~= nil, 'missing a keymap')
        assert.is_true(found_keys['x'] ~= nil, 'missing x keymap')
      end)
    end)

    it('q closes the panel', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        panel.open()
        assert.is_true(panel.is_open())

        vim.api.nvim_feedkeys('q', 'x', false)
        vim.wait(100, function() return false end)

        -- Panel close goes through init.close() which also closes viewer
        assert.is_false(panel.is_open())
      end)
    end)

    it('Enter opens viewer for selected file', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        panel.open()
        -- Cursor should be on first entry
        vim.api.nvim_win_set_cursor(panel.win, { 1, 0 })

        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
        vim.wait(200, function() return false end)

        local viewer = require('claude-diff.ui.viewer')
        assert.is_true(viewer.is_open())
        assert.equals('a.lua', viewer.current_file)
      end)
    end)
  end)

  describe('get_entry_at_cursor', function()
    it('returns correct index for valid cursor position', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        panel.open()
        vim.api.nvim_win_set_cursor(panel.win, { 1, 0 })

        local idx = panel.get_entry_at_cursor()
        assert.equals(1, idx)
      end)
    end)

    it('returns nil when cursor is out of bounds', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          files = {},
          snapshots = {},
          pending = {},
        })

        panel.open()

        local idx = panel.get_entry_at_cursor()
        assert.is_nil(idx)
      end)
    end)
  end)
end)
