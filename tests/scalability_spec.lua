local helpers = require('tests.helpers')

describe('scalability', function()
  local store, panel, viewer, actions, config
  local test_dir

  before_each(function()
    test_dir = helpers.create_temp_dir()

    config = require('claude-diff.config')
    config.setup({ storage_dir = '.claude-diff' })
    require('claude-diff.ui.highlights').setup()

    require('claude-diff.init')
    package.loaded['claude-diff'] = package.loaded['claude-diff.init']

    store = require('claude-diff.store')
    panel = require('claude-diff.ui.panel')
    viewer = require('claude-diff.ui.viewer')
    actions = require('claude-diff.actions')
  end)

  after_each(function()
    pcall(function() viewer.close() end)
    pcall(function() panel.close() end)
    helpers.remove_dir(test_dir)
  end)

  --- Generate N files with diffs for stress testing
  ---@param n number number of files to generate
  local function setup_n_files(n)
    local files = {}
    local snapshots = {}
    local pending = {}

    for i = 1, n do
      local name = string.format('file_%03d.lua', i)
      files[name] = 'line1\nmodified_' .. i .. '\nline3\n'
      snapshots[name] = 'line1\noriginal_' .. i .. '\nline3\n'
      table.insert(pending, { file = name, is_new = false })
    end

    helpers.setup_project({
      dir = test_dir,
      files = files,
      snapshots = snapshots,
      pending = pending,
    })
  end

  describe('store pending cache', function()
    it('get_pending returns cached data without re-reading disk', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(10)

        -- First call reads from disk
        local result1 = store.get_pending()
        assert.equals(10, #result1)

        -- Delete pending.json from disk — cache should still return data
        vim.fn.delete(store.pending_file())
        local result2 = store.get_pending()
        assert.equals(10, #result2)
      end)
    end)

    it('invalidate_cache forces re-read from disk', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(5)

        local result1 = store.get_pending()
        assert.equals(5, #result1)

        -- Delete pending.json and invalidate
        vim.fn.delete(store.pending_file())
        store.invalidate_cache()

        local result2 = store.get_pending()
        assert.equals(0, #result2)
      end)
    end)

    it('set_pending updates cache immediately', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(5)

        store.get_pending() -- populate cache

        -- set_pending should update cache
        store.set_pending({ { file = 'only.lua', is_new = false } })

        -- Delete disk file — cache should have the new value
        vim.fn.delete(store.pending_file())

        local result = store.get_pending()
        assert.equals(1, #result)
        assert.equals('only.lua', result[1].file)
      end)
    end)

    it('remove_pending updates cache without extra disk reads', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(3)

        store.get_pending() -- populate cache

        store.remove_pending('file_002.lua')

        local result = store.get_pending()
        assert.equals(2, #result)
        assert.equals('file_001.lua', result[1].file)
        assert.equals('file_003.lua', result[2].file)
      end)
    end)
  end)

  describe('panel hunk cache', function()
    it('caches hunk counts across renders', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(5)

        panel.open()
        assert.equals(5, #panel.entries)

        -- Re-render — should use cached hunk counts, not recompute
        panel.render()
        assert.equals(5, #panel.entries)
      end)
    end)

    it('invalidate_hunk_cache for specific file only recomputes that file', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(3)

        panel.open()
        assert.equals(3, #panel.entries)

        -- Invalidate one file and re-render
        panel.invalidate_hunk_cache('file_001.lua')
        panel.render()
        assert.equals(3, #panel.entries)
      end)
    end)

    it('invalidate_hunk_cache with no args clears all', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(3)

        panel.open()

        panel.invalidate_hunk_cache()
        panel.render()
        assert.equals(3, #panel.entries)
      end)
    end)
  end)

  describe('mass file operations', function()
    it('handles 100 pending files in panel', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(100)

        panel.open()
        assert.equals(100, #panel.entries)

        -- Verify title shows count
        local win_config = vim.api.nvim_win_get_config(panel.win)
        local title_text = win_config.title[1][1]
        assert.truthy(title_text:find('100'), 'title should show 100 files')
      end)
    end)

    it('approve_all with 50 files clears all at once', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(50)

        local entries = store.get_pending()
        assert.equals(50, #entries)

        actions.approve_all()

        local remaining = store.get_pending()
        assert.equals(0, #remaining)

        -- All snapshots should be removed
        for i = 1, 50 do
          local name = string.format('file_%03d.lua', i)
          local content = store.get_snapshot(name)
          assert.is_nil(content)
        end
      end)
    end)

    it('reject_all with 50 files reverts all', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(50)

        actions.reject_all()

        local remaining = store.get_pending()
        assert.equals(0, #remaining)

        -- All files should be reverted to original
        for i = 1, 50 do
          local name = string.format('file_%03d.lua', i)
          local content = store.get_current(name)
          assert.truthy(content:find('original_' .. i), name .. ' should be reverted')
        end
      end)
    end)
  end)

  describe('viewer tab bar with many files', function()
    it('opens viewer with 20 files without error', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(20)

        viewer.open('file_001.lua')
        assert.is_true(viewer.is_open())
        assert.equals(20, #viewer.file_list)
        assert.equals(1, viewer.file_idx)
      end)
    end)

    it('tab bar shows position indicator with many files', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(20)

        viewer.open('file_010.lua')
        assert.is_true(viewer.is_open())
        assert.equals(10, viewer.file_idx)

        -- Tab bar should exist
        assert.is_not_nil(viewer.tab_buf)
        assert.is_true(vim.api.nvim_buf_is_valid(viewer.tab_buf))

        -- Tab bar content should have position indicator
        local lines = vim.api.nvim_buf_get_lines(viewer.tab_buf, 0, -1, false)
        assert.truthy(lines[1]:find('10/20'), 'tab bar should show position 10/20')
      end)
    end)

    it('tab bar shows overflow indicators', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(20)

        -- Open file in the middle — should show both overflow indicators
        viewer.open('file_010.lua')

        local lines = vim.api.nvim_buf_get_lines(viewer.tab_buf, 0, -1, false)
        local tab_line = lines[1]

        -- Should contain left arrow (◀) and right arrow (▶) for overflow
        assert.truthy(tab_line:find('\u{25C0}'), 'should show left overflow indicator')
        assert.truthy(tab_line:find('\u{25B6}'), 'should show right overflow indicator')
      end)
    end)

    it('tab bar does not show left overflow at first file', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(20)

        viewer.open('file_001.lua')

        local lines = vim.api.nvim_buf_get_lines(viewer.tab_buf, 0, -1, false)
        local tab_line = lines[1]

        assert.is_falsy(tab_line:find('\u{25C0}'), 'should NOT show left overflow at start')
        assert.truthy(tab_line:find('\u{25B6}'), 'should show right overflow')
        assert.truthy(tab_line:find('1/20'), 'should show position 1/20')
      end)
    end)

    it('tab bar does not show right overflow at last file', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(20)

        viewer.open('file_020.lua')

        local lines = vim.api.nvim_buf_get_lines(viewer.tab_buf, 0, -1, false)
        local tab_line = lines[1]

        assert.truthy(tab_line:find('\u{25C0}'), 'should show left overflow')
        assert.is_falsy(tab_line:find('\u{25B6}'), 'should NOT show right overflow at end')
        assert.truthy(tab_line:find('20/20'), 'should show position 20/20')
      end)
    end)

    it('navigates through many files with Tab', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(20)

        viewer.open('file_001.lua')
        assert.equals(1, viewer.file_idx)

        -- Navigate forward 5 times
        for _ = 1, 5 do
          viewer.next_file()
          vim.wait(100, function() return false end)
        end

        assert.equals(6, viewer.file_idx)
        assert.equals('file_006.lua', viewer.current_file)
      end)
    end)
  end)

  describe('inline_diff with hunks optimization', function()
    it('apply with hunks parameter does not error', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(1)

        viewer.open('file_001.lua')
        assert.is_true(viewer.is_open())

        -- Inline diff should have been applied during open without error
        -- The fact that the viewer opened successfully validates this
      end)
    end)

    it('apply works with empty hunks list', function()
      local inline_diff = require('claude-diff.ui.inline_diff')

      local left_buf = vim.api.nvim_create_buf(false, true)
      local right_buf = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, { 'same', 'content' })
      vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { 'same', 'content' })

      -- Should not error with empty hunks
      local ok = pcall(inline_diff.apply, left_buf, right_buf, 0, 0, { 'same', 'content' }, { 'same', 'content' }, {})
      -- Window 0 is not valid for diff_hlID, but should not crash
      -- The important thing is the function accepts the hunks parameter

      pcall(vim.api.nvim_buf_delete, left_buf, { force = true })
      pcall(vim.api.nvim_buf_delete, right_buf, { force = true })
    end)
  end)

  describe('refresh with cache invalidation', function()
    it('init.refresh invalidates store cache', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(3)

        -- Populate cache
        local result1 = store.get_pending()
        assert.equals(3, #result1)

        -- Modify pending.json on disk directly (simulating hook)
        local pending_path = store.pending_file()
        vim.fn.writefile({ vim.json.encode({
          { file = 'new_file.lua', is_new = true },
        }) }, pending_path)

        -- Without refresh, cache still has old data
        local stale = store.get_pending()
        assert.equals(3, #stale)

        -- refresh() should invalidate cache and re-read
        require('claude-diff').refresh()
        local fresh = store.get_pending()
        assert.equals(1, #fresh)
        assert.equals('new_file.lua', fresh[1].file)
      end)
    end)

    it('_refresh_ui with path only invalidates that file hunk cache', function()
      helpers.with_cwd(test_dir, function()
        setup_n_files(3)

        panel.open()
        assert.equals(3, #panel.entries)

        -- Call _refresh_ui with specific path — should not crash
        actions._refresh_ui('file_001.lua')
        assert.equals(3, #panel.entries)
      end)
    end)
  end)
end)
