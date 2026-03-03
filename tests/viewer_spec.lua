local helpers = require('tests.helpers')

describe('viewer', function()
  local viewer, store, actions, config
  local test_dir

  before_each(function()
    test_dir = helpers.create_temp_dir()

    config = require('claude-diff.config')
    config.setup({ storage_dir = '.claude-diff' })
    require('claude-diff.ui.highlights').setup()

    store = require('claude-diff.store')
    viewer = require('claude-diff.ui.viewer')
    actions = require('claude-diff.actions')
  end)

  after_each(function()
    -- Always close viewer
    pcall(function() viewer.close() end)
    helpers.remove_dir(test_dir)
  end)

  --- Setup a standard test project with 2 modified files
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

  describe('open and close', function()
    it('opens the viewer with valid windows', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')

        assert.is_true(viewer.is_open())
        assert.is_not_nil(viewer.left_win)
        assert.is_not_nil(viewer.right_win)
        assert.is_true(vim.api.nvim_win_is_valid(viewer.left_win))
        assert.is_true(vim.api.nvim_win_is_valid(viewer.right_win))
      end)
    end)

    it('closes cleanly', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        assert.is_true(viewer.is_open())

        viewer.close()
        assert.is_false(viewer.is_open())
        assert.is_nil(viewer.left_win)
        assert.is_nil(viewer.right_win)
        assert.is_nil(viewer.current_file)
      end)
    end)

    it('can open after close (no stale buffer error)', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        viewer.close()
        viewer.open('a.lua')

        assert.is_true(viewer.is_open())
        assert.equals('a.lua', viewer.current_file)
      end)
    end)

    it('can reopen the same file multiple times (refresh)', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        viewer.open('a.lua')
        viewer.open('a.lua')

        assert.is_true(viewer.is_open())
        assert.equals('a.lua', viewer.current_file)
      end)
    end)

    it('sets up keymaps on buffers', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')

        -- Check that 'q' keymap exists on the right buffer
        local maps = vim.api.nvim_buf_get_keymap(viewer.right_buf, 'n')
        local has_q = false
        local has_esc = false
        local has_tab = false
        for _, map in ipairs(maps) do
          if map.lhs == 'q' then has_q = true end
          if map.lhs == '<Esc>' then has_esc = true end
          if map.lhs == '<Tab>' then has_tab = true end
        end

        assert.is_true(has_q, 'missing q keymap')
        assert.is_true(has_esc, 'missing Esc keymap')
        assert.is_true(has_tab, 'missing Tab keymap')
      end)
    end)
  end)

  describe('refresh', function()
    it('refreshes without error', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        viewer.refresh()

        assert.is_true(viewer.is_open())
        assert.equals('a.lua', viewer.current_file)
      end)
    end)

    it('refreshes multiple times without error', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        for _ = 1, 5 do
          viewer.refresh()
        end

        assert.is_true(viewer.is_open())
      end)
    end)
  end)

  describe('file navigation', function()
    it('builds file list from pending', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')

        assert.equals(2, #viewer.file_list)
        assert.equals(1, viewer.file_idx)
        assert.equals('a.lua', viewer.file_list[1])
        assert.equals('b.lua', viewer.file_list[2])
      end)
    end)

    it('navigates to next file', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        assert.equals('a.lua', viewer.current_file)

        viewer.next_file()
        assert.equals('b.lua', viewer.current_file)
        assert.is_true(viewer.is_open())
      end)
    end)

    it('navigates to previous file', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('b.lua')
        assert.equals('b.lua', viewer.current_file)

        viewer.prev_file()
        assert.equals('a.lua', viewer.current_file)
        assert.is_true(viewer.is_open())
      end)
    end)

    it('stops at last file (no wrap)', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('b.lua')
        viewer.next_file()

        assert.equals('b.lua', viewer.current_file)
      end)
    end)

    it('stops at first file (no wrap)', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        viewer.prev_file()

        assert.equals('a.lua', viewer.current_file)
      end)
    end)
  end)

  describe('approve file flow', function()
    it('keeps viewer open after approve (shows preview)', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        actions.approve_file('a.lua')

        -- Process the scheduled refresh
        vim.wait(100, function() return false end)

        assert.is_true(viewer.is_open())
        assert.equals('a.lua', viewer.current_file)
      end)
    end)

    it('viewer is closable after approve', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        actions.approve_file('a.lua')

        -- Process the scheduled refresh
        vim.wait(100, function() return false end)

        assert.is_true(viewer.is_open())

        -- Keymaps should work - close should succeed
        viewer.close()
        assert.is_false(viewer.is_open())
      end)
    end)

    it('has keymaps after approve refresh', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        actions.approve_file('a.lua')

        -- Process the scheduled refresh
        vim.wait(100, function() return false end)

        -- Verify keymaps are set on the new buffer
        assert.is_not_nil(viewer.right_buf)
        assert.is_true(vim.api.nvim_buf_is_valid(viewer.right_buf))

        local maps = vim.api.nvim_buf_get_keymap(viewer.right_buf, 'n')
        local has_q = false
        for _, map in ipairs(maps) do
          if map.lhs == 'q' then has_q = true end
        end
        assert.is_true(has_q, 'missing q keymap after approve refresh')
      end)
    end)

    it('can navigate to next file after approve', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        actions.approve_file('a.lua')

        -- Process the scheduled refresh
        vim.wait(100, function() return false end)

        assert.is_true(viewer.is_open())

        -- Should be able to navigate to b.lua
        viewer.next_file()
        assert.equals('b.lua', viewer.current_file)
        assert.is_true(viewer.is_open())
      end)
    end)

    it('can approve all files sequentially and close', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        -- Approve first file
        viewer.open('a.lua')
        actions.approve_file('a.lua')
        vim.wait(100, function() return false end)
        assert.is_true(viewer.is_open())

        -- Navigate to second file
        viewer.next_file()
        assert.equals('b.lua', viewer.current_file)

        -- Approve second file
        actions.approve_file('b.lua')
        vim.wait(100, function() return false end)
        assert.is_true(viewer.is_open())

        -- Should be able to close
        viewer.close()
        assert.is_false(viewer.is_open())
      end)
    end)

    it('q keymap works after approving last file', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        -- Approve first, navigate to second, approve second
        viewer.open('a.lua')
        actions.approve_file('a.lua')
        vim.wait(100, function() return false end)

        viewer.next_file()
        actions.approve_file('b.lua')
        vim.wait(100, function() return false end)

        assert.is_true(viewer.is_open())

        -- Verify focus is on a viewer buffer
        local cur_buf = vim.api.nvim_get_current_buf()
        local is_viewer_buf = (cur_buf == viewer.left_buf or cur_buf == viewer.right_buf)
        assert.is_true(is_viewer_buf, 'focus should be on viewer buffer, got buf ' .. cur_buf)

        -- Verify q keymap exists
        local maps = vim.api.nvim_buf_get_keymap(cur_buf, 'n')
        local has_q = false
        for _, map in ipairs(maps) do
          if map.lhs == 'q' then has_q = true end
        end
        assert.is_true(has_q, 'q keymap should exist on current buffer')

        -- Simulate pressing q via feedkeys
        vim.api.nvim_feedkeys('q', 'x', false)
        vim.wait(100, function() return false end)

        assert.is_false(viewer.is_open(), 'viewer should be closed after pressing q')
      end)
    end)

    it('Esc keymap works after approving last file', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        actions.approve_file('a.lua')
        vim.wait(100, function() return false end)

        viewer.next_file()
        actions.approve_file('b.lua')
        vim.wait(100, function() return false end)

        assert.is_true(viewer.is_open())

        -- Simulate pressing Escape
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)
        vim.wait(100, function() return false end)

        assert.is_false(viewer.is_open(), 'viewer should be closed after pressing Esc')
      end)
    end)

    it('focus stays on viewer buffer after approve refresh', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        actions.approve_file('a.lua')
        vim.wait(100, function() return false end)

        -- Check current window is one of the viewer windows
        local cur_win = vim.api.nvim_get_current_win()
        local is_viewer_win = (cur_win == viewer.left_win or cur_win == viewer.right_win)
        assert.is_true(is_viewer_win, 'focus should be on viewer window after approve')
      end)
    end)
  end)

  describe('reject file flow', function()
    it('keeps viewer open after reject (shows reverted state)', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        actions.reject_file('a.lua')

        vim.wait(100, function() return false end)

        assert.is_true(viewer.is_open())
      end)
    end)

    it('viewer is closable after reject', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        actions.reject_file('a.lua')

        vim.wait(100, function() return false end)

        viewer.close()
        assert.is_false(viewer.is_open())
      end)
    end)
  end)

  describe('approve hunk flow', function()
    it('refreshes viewer after hunk approve', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        assert.is_true(#viewer.hunks > 0)

        actions.approve_hunk('a.lua', 1)
        vim.wait(100, function() return false end)

        assert.is_true(viewer.is_open())
      end)
    end)

    it('viewer is closable after last hunk approve', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')

        -- Approve all hunks one by one
        local count = #viewer.hunks
        for i = 1, count do
          actions.approve_hunk('a.lua', 1) -- always index 1 since list shifts
          vim.wait(100, function() return false end)
        end

        assert.is_true(viewer.is_open())

        viewer.close()
        assert.is_false(viewer.is_open())
      end)
    end)
  end)

  describe('full keymap flow (simulating real user)', function()
    it('A to approve file, then q to close', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        -- Need to be on a hunk for 'a' to work, but 'A' works always
        assert.is_true(viewer.is_open())

        -- Simulate pressing A (approve file)
        vim.api.nvim_feedkeys('A', 'x', false)
        vim.wait(200, function() return false end)

        assert.is_true(viewer.is_open(), 'viewer should stay open showing preview')

        -- Simulate pressing q
        vim.api.nvim_feedkeys('q', 'x', false)
        vim.wait(100, function() return false end)

        assert.is_false(viewer.is_open(), 'viewer should close after q')
      end)
    end)

    it('approve all files via A keymap, then close via q', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')

        -- Approve first file via A
        vim.api.nvim_feedkeys('A', 'x', false)
        vim.wait(200, function() return false end)
        assert.is_true(viewer.is_open())

        -- Navigate to next file via Tab
        local tab = vim.api.nvim_replace_termcodes('<Tab>', true, false, true)
        vim.api.nvim_feedkeys(tab, 'x', false)
        vim.wait(200, function() return false end)
        assert.equals('b.lua', viewer.current_file)

        -- Approve second file via A
        vim.api.nvim_feedkeys('A', 'x', false)
        vim.wait(200, function() return false end)
        assert.is_true(viewer.is_open(), 'viewer should stay open showing preview of last file')

        -- Now close via q
        vim.api.nvim_feedkeys('q', 'x', false)
        vim.wait(100, function() return false end)

        assert.is_false(viewer.is_open(), 'viewer should be closable after approving all files via keymap')
      end)
    end)

    it('approve all hunks via a keymap, then close via q', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        local hunk_count = #viewer.hunks

        -- Approve each hunk via 'a' keymap
        for _ = 1, hunk_count do
          vim.api.nvim_feedkeys('a', 'x', false)
          vim.wait(200, function() return false end)
        end

        assert.is_true(viewer.is_open(), 'viewer should stay open showing preview')

        -- Close via q
        vim.api.nvim_feedkeys('q', 'x', false)
        vim.wait(100, function() return false end)

        assert.is_false(viewer.is_open(), 'viewer should close after pressing q')
      end)
    end)
  end)

  describe('single file (no tab bar)', function()
    local function setup_one_file()
      helpers.setup_project({
        dir = test_dir,
        files = {
          ['a.lua'] = 'line1\nmodified\nline3\n',
        },
        snapshots = {
          ['a.lua'] = 'line1\noriginal\nline3\n',
        },
        pending = {
          { file = 'a.lua', is_new = false },
        },
      })
    end

    it('opens and closes with single file (tab_win is nil)', function()
      helpers.with_cwd(test_dir, function()
        setup_one_file()

        viewer.open('a.lua')
        assert.is_true(viewer.is_open())
        assert.is_nil(viewer.tab_win)  -- no tab bar for single file

        viewer.close()
        assert.is_false(viewer.is_open())
      end)
    end)

    it('approve single file then close via q', function()
      helpers.with_cwd(test_dir, function()
        setup_one_file()

        viewer.open('a.lua')
        assert.is_nil(viewer.tab_win)

        -- Approve via A keymap
        vim.api.nvim_feedkeys('A', 'x', false)
        vim.wait(200, function() return false end)

        assert.is_true(viewer.is_open(), 'viewer should stay open showing preview')

        -- Close via q
        vim.api.nvim_feedkeys('q', 'x', false)
        vim.wait(100, function() return false end)

        assert.is_false(viewer.is_open(), 'viewer should close after pressing q')
      end)
    end)

    it('approve single file then close via Esc', function()
      helpers.with_cwd(test_dir, function()
        setup_one_file()

        viewer.open('a.lua')

        actions.approve_file('a.lua')
        vim.wait(200, function() return false end)

        assert.is_true(viewer.is_open())

        viewer.close()
        assert.is_false(viewer.is_open())
      end)
    end)
  end)

  describe('preview state (no snapshot)', function()
    it('shows current content on both sides when no snapshot', function()
      helpers.with_cwd(test_dir, function()
        -- File exists but no snapshot (already approved)
        helpers.setup_project({
          dir = test_dir,
          files = { ['a.lua'] = 'final content\n' },
          snapshots = {},
          pending = {},
        })

        local diff_mod = require('claude-diff.diff')
        local old_lines, new_lines = diff_mod.get_file_lines('a.lua')

        assert.are.same(old_lines, new_lines)
      end)
    end)
  end)
end)
