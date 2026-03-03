local helpers = require('tests.helpers')

describe('actions', function()
  local actions, store, config, viewer
  local test_dir

  before_each(function()
    test_dir = helpers.create_temp_dir()

    config = require('claude-diff.config')
    config.setup({ storage_dir = '.claude-diff' })
    require('claude-diff.ui.highlights').setup()

    store = require('claude-diff.store')
    actions = require('claude-diff.actions')
    viewer = require('claude-diff.ui.viewer')
  end)

  after_each(function()
    pcall(function() viewer.close() end)
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

  local function setup_with_new_file()
    helpers.setup_project({
      dir = test_dir,
      files = {
        ['a.lua'] = 'line1\nmodified\nline3\n',
        ['new.lua'] = 'brand new content\n',
      },
      snapshots = {
        ['a.lua'] = 'line1\noriginal\nline3\n',
      },
      pending = {
        { file = 'a.lua', is_new = false },
        { file = 'new.lua', is_new = true },
      },
    })
    -- Mark new.lua snapshot as new file
    local snap_dir = test_dir .. '/.claude-diff/snapshots'
    vim.fn.writefile({ '__CLAUDE_DIFF_NEW_FILE__' }, snap_dir .. '/new.lua')
  end

  describe('approve_file', function()
    it('removes snapshot and pending entry', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        actions.approve_file('a.lua')

        assert.is_nil(store.get_snapshot('a.lua'))
        local pending = store.get_pending()
        assert.equals(1, #pending)
        assert.equals('b.lua', pending[1].file)
      end)
    end)

    it('keeps current file content unchanged', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        actions.approve_file('a.lua')

        local content = helpers.read_file(test_dir .. '/a.lua')
        assert.truthy(content:find('modified'))
      end)
    end)

    it('schedules viewer refresh when viewer is showing the file', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        actions.approve_file('a.lua')

        vim.wait(200, function() return false end)

        assert.is_true(viewer.is_open())
      end)
    end)
  end)

  describe('reject_file', function()
    it('restores file to snapshot content', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        actions.reject_file('a.lua')

        local content = helpers.read_file(test_dir .. '/a.lua')
        assert.truthy(content:find('original'))
        assert.is_falsy(content:find('modified'))
      end)
    end)

    it('deletes file when is_new', function()
      helpers.with_cwd(test_dir, function()
        setup_with_new_file()

        assert.equals(1, vim.fn.filereadable(test_dir .. '/new.lua'))

        actions.reject_file('new.lua')

        assert.equals(0, vim.fn.filereadable(test_dir .. '/new.lua'))
      end)
    end)

    it('removes snapshot and pending entry', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        actions.reject_file('a.lua')

        assert.is_nil(store.get_snapshot('a.lua'))
        local pending = store.get_pending()
        assert.equals(1, #pending)
        assert.equals('b.lua', pending[1].file)
      end)
    end)
  end)

  describe('approve_all', function()
    it('removes all snapshots and pending entries', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        actions.approve_all()

        assert.is_nil(store.get_snapshot('a.lua'))
        assert.is_nil(store.get_snapshot('b.lua'))
        assert.are.same({}, store.get_pending())
      end)
    end)

    it('closes viewer before clearing', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        assert.is_true(viewer.is_open())

        actions.approve_all()

        assert.is_false(viewer.is_open())
      end)
    end)

    it('keeps all file contents unchanged', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        actions.approve_all()

        local a_content = helpers.read_file(test_dir .. '/a.lua')
        local b_content = helpers.read_file(test_dir .. '/b.lua')
        assert.truthy(a_content:find('modified'))
        assert.truthy(b_content:find('changed'))
      end)
    end)
  end)

  describe('reject_all', function()
    it('restores all files to snapshot content', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        actions.reject_all()

        local a_content = helpers.read_file(test_dir .. '/a.lua')
        local b_content = helpers.read_file(test_dir .. '/b.lua')
        assert.truthy(a_content:find('original'))
        assert.truthy(b_content:find('original'))
      end)
    end)

    it('deletes new files', function()
      helpers.with_cwd(test_dir, function()
        setup_with_new_file()

        actions.reject_all()

        assert.equals(0, vim.fn.filereadable(test_dir .. '/new.lua'))
      end)
    end)

    it('closes viewer and clears pending', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        viewer.open('a.lua')
        assert.is_true(viewer.is_open())

        actions.reject_all()

        assert.is_false(viewer.is_open())
        assert.are.same({}, store.get_pending())
      end)
    end)
  end)

  describe('reject_hunk', function()
    it('reverts a specific hunk in the file', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        local diff_mod = require('claude-diff.diff')
        local diff_text = diff_mod.compute('a.lua')
        local hunks = diff_mod.parse_hunks(diff_text)
        assert.is_true(#hunks > 0)

        actions.reject_hunk('a.lua', 1)
        vim.wait(100, function() return false end)

        local content = helpers.read_file(test_dir .. '/a.lua')
        assert.truthy(content:find('original'))
      end)
    end)

    it('removes pending when all hunks rejected', function()
      helpers.with_cwd(test_dir, function()
        setup_two_files()

        local diff_mod = require('claude-diff.diff')
        local diff_text = diff_mod.compute('a.lua')
        local hunk_count = #diff_mod.parse_hunks(diff_text)

        for _ = 1, hunk_count do
          actions.reject_hunk('a.lua', 1)
          vim.wait(100, function() return false end)
        end

        local pending = store.get_pending()
        local found = false
        for _, entry in ipairs(pending) do
          if entry.file == 'a.lua' then found = true end
        end
        assert.is_false(found, 'a.lua should be removed from pending after all hunks rejected')
      end)
    end)
  end)

  describe('_refresh_ui', function()
    it('does not crash when panel is not open', function()
      helpers.with_cwd(test_dir, function()
        -- Should not error
        actions._refresh_ui()
      end)
    end)
  end)
end)
