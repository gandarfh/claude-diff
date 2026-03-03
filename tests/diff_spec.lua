local diff = require('claude-diff.diff')

describe('diff', function()
  describe('parse_hunks', function()
    it('returns empty for nil input', function()
      assert.are.same({}, diff.parse_hunks(nil))
    end)

    it('returns empty for empty string', function()
      assert.are.same({}, diff.parse_hunks(''))
    end)

    it('parses a single hunk', function()
      local text = table.concat({
        '@@ -1,3 +1,4 @@',
        ' line1',
        ' line2',
        '+new line',
        ' line3',
      }, '\n')

      local hunks = diff.parse_hunks(text)
      assert.equals(1, #hunks)
      assert.equals(1, hunks[1].old_start)
      assert.equals(3, hunks[1].old_count)
      assert.equals(1, hunks[1].new_start)
      assert.equals(4, hunks[1].new_count)
      assert.equals(4, #hunks[1].lines)
    end)

    it('parses multiple hunks', function()
      local text = table.concat({
        '@@ -1,3 +1,3 @@',
        ' line1',
        '-old line2',
        '+new line2',
        ' line3',
        '@@ -10,3 +10,4 @@',
        ' line10',
        ' line11',
        '+added line',
        ' line12',
      }, '\n')

      local hunks = diff.parse_hunks(text)
      assert.equals(2, #hunks)
      assert.equals(1, hunks[1].old_start)
      assert.equals(10, hunks[2].old_start)
    end)

    it('handles hunks with count=1 (no comma)', function()
      local text = '@@ -5 +5,2 @@\n line4\n+added\n'
      local hunks = diff.parse_hunks(text)
      assert.equals(1, #hunks)
      assert.equals(1, hunks[1].old_count)
      assert.equals(2, hunks[1].new_count)
    end)

    it('handles "No newline at end of file"', function()
      local text = table.concat({
        '@@ -1,2 +1,2 @@',
        '-old',
        '+new',
        ' last',
        '\\ No newline at end of file',
      }, '\n')

      local hunks = diff.parse_hunks(text)
      assert.equals(1, #hunks)
      assert.equals(4, #hunks[1].lines)
    end)
  end)

  describe('apply_hunk', function()
    it('applies an addition', function()
      local original = { 'line1', 'line2', 'line3' }
      local hunk = {
        old_start = 2, old_count = 1, new_start = 2, new_count = 2,
        lines = { ' line2', '+new line' },
      }

      local result = diff.apply_hunk(original, hunk)
      assert.are.same({ 'line1', 'line2', 'new line', 'line3' }, result)
    end)

    it('applies a deletion', function()
      local original = { 'line1', 'line2', 'line3' }
      local hunk = {
        old_start = 2, old_count = 2, new_start = 2, new_count = 1,
        lines = { '-line2', ' line3' },
      }

      local result = diff.apply_hunk(original, hunk)
      assert.are.same({ 'line1', 'line3' }, result)
    end)

    it('applies a replacement', function()
      local original = { 'line1', 'old line', 'line3' }
      local hunk = {
        old_start = 2, old_count = 1, new_start = 2, new_count = 1,
        lines = { '-old line', '+new line' },
      }

      local result = diff.apply_hunk(original, hunk)
      assert.are.same({ 'line1', 'new line', 'line3' }, result)
    end)

    it('applies hunk at the beginning', function()
      local original = { 'line1', 'line2' }
      local hunk = {
        old_start = 1, old_count = 1, new_start = 1, new_count = 2,
        lines = { '+new first', ' line1' },
      }

      local result = diff.apply_hunk(original, hunk)
      assert.are.same({ 'new first', 'line1', 'line2' }, result)
    end)

    it('applies hunk at the end', function()
      local original = { 'line1', 'line2' }
      local hunk = {
        old_start = 2, old_count = 1, new_start = 2, new_count = 2,
        lines = { ' line2', '+new last' },
      }

      local result = diff.apply_hunk(original, hunk)
      assert.are.same({ 'line1', 'line2', 'new last' }, result)
    end)
  end)

  describe('revert_hunk', function()
    it('reverts an addition', function()
      local current = { 'line1', 'line2', 'new line', 'line3' }
      local hunk = {
        old_start = 2, old_count = 1, new_start = 2, new_count = 2,
        lines = { ' line2', '+new line' },
      }

      local result = diff.revert_hunk(current, hunk)
      assert.are.same({ 'line1', 'line2', 'line3' }, result)
    end)

    it('reverts a deletion', function()
      local current = { 'line1', 'line3' }
      local hunk = {
        old_start = 2, old_count = 2, new_start = 2, new_count = 1,
        lines = { '-line2', ' line3' },
      }

      local result = diff.revert_hunk(current, hunk)
      assert.are.same({ 'line1', 'line2', 'line3' }, result)
    end)

    it('reverts a replacement', function()
      local current = { 'line1', 'new line', 'line3' }
      local hunk = {
        old_start = 2, old_count = 1, new_start = 2, new_count = 1,
        lines = { '-old line', '+new line' },
      }

      local result = diff.revert_hunk(current, hunk)
      assert.are.same({ 'line1', 'old line', 'line3' }, result)
    end)

    it('apply then revert is identity', function()
      local original = { 'aaa', 'bbb', 'ccc', 'ddd', 'eee' }
      local hunk = {
        old_start = 2, old_count = 2, new_start = 2, new_count = 3,
        lines = { '-bbb', '-ccc', '+BBB', '+NEW', '+CCC' },
      }

      local applied = diff.apply_hunk(original, hunk)
      assert.are.same({ 'aaa', 'BBB', 'NEW', 'CCC', 'ddd', 'eee' }, applied)

      -- To revert, we need the hunk relative to the new positions
      local revert_hunk = {
        old_start = 2, old_count = 2, new_start = 2, new_count = 3,
        lines = hunk.lines,
      }
      local reverted = diff.revert_hunk(applied, revert_hunk)
      assert.are.same(original, reverted)
    end)
  end)

  describe('revert_hunk_in_file', function()
    local helpers = require('tests.helpers')
    local store = require('claude-diff.store')
    local config = require('claude-diff.config')
    local test_dir

    before_each(function()
      test_dir = helpers.create_temp_dir()
      config.setup({ storage_dir = '.claude-diff' })
    end)

    after_each(function()
      helpers.remove_dir(test_dir)
    end)

    it('reverts a hunk on disk', function()
      helpers.with_cwd(test_dir, function()
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

        local ok = diff.revert_hunk_in_file('a.lua', 1)
        assert.is_true(ok)

        local content = helpers.read_file(test_dir .. '/a.lua')
        assert.truthy(content:find('original'))
        assert.is_falsy(content:find('modified'))
      end)
    end)

    it('returns false for invalid hunk index', function()
      helpers.with_cwd(test_dir, function()
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

        assert.is_false(diff.revert_hunk_in_file('a.lua', 0))
        assert.is_false(diff.revert_hunk_in_file('a.lua', 99))
      end)
    end)

    it('returns false when no diff exists', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          files = {
            ['a.lua'] = 'same\n',
          },
          snapshots = {
            ['a.lua'] = 'same\n',
          },
          pending = {},
        })

        assert.is_false(diff.revert_hunk_in_file('a.lua', 1))
      end)
    end)
  end)

  describe('approve_hunk_in_file', function()
    local helpers = require('tests.helpers')
    local store = require('claude-diff.store')
    local config = require('claude-diff.config')
    local test_dir

    before_each(function()
      test_dir = helpers.create_temp_dir()
      config.setup({ storage_dir = '.claude-diff' })
    end)

    after_each(function()
      helpers.remove_dir(test_dir)
    end)

    it('updates snapshot to include approved hunk', function()
      helpers.with_cwd(test_dir, function()
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

        local ok = diff.approve_hunk_in_file('a.lua', 1)
        assert.is_true(ok)

        -- After approving the only hunk, snapshot should be removed
        assert.is_nil(store.get_snapshot('a.lua'))
      end)
    end)

    it('returns false for invalid hunk index', function()
      helpers.with_cwd(test_dir, function()
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

        assert.is_false(diff.approve_hunk_in_file('a.lua', 0))
        assert.is_false(diff.approve_hunk_in_file('a.lua', 99))
      end)
    end)

    it('returns false for individual hunk approve on new file', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          files = { ['new.lua'] = 'line1\nline2\n' },
          snapshots = {},
          pending = { { file = 'new.lua', is_new = true } },
        })
        local snap_dir = test_dir .. '/.claude-diff/snapshots'
        vim.fn.writefile({ '__CLAUDE_DIFF_NEW_FILE__' }, snap_dir .. '/new.lua')

        local ok = diff.approve_hunk_in_file('new.lua', 1)
        assert.is_false(ok)
      end)
    end)

    it('keeps snapshot when multiple hunks and only one approved', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          files = {
            ['a.lua'] = 'modified1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nmodified9\nline10\n',
          },
          snapshots = {
            ['a.lua'] = 'original1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\noriginal9\nline10\n',
          },
          pending = {
            { file = 'a.lua', is_new = false },
          },
        })

        local ok = diff.approve_hunk_in_file('a.lua', 1)
        assert.is_true(ok)

        -- Snapshot should still exist (second hunk remains)
        local snapshot = store.get_snapshot('a.lua')
        assert.is_not_nil(snapshot)
      end)
    end)
  end)

  describe('compute', function()
    local helpers = require('tests.helpers')
    local store = require('claude-diff.store')
    local config = require('claude-diff.config')
    local test_dir

    before_each(function()
      test_dir = helpers.create_temp_dir()
      config.setup({ storage_dir = '.claude-diff' })
    end)

    after_each(function()
      helpers.remove_dir(test_dir)
    end)

    it('returns nil when files are identical', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          files = { ['a.lua'] = 'same\n' },
          snapshots = { ['a.lua'] = 'same\n' },
          pending = {},
        })

        local result = diff.compute('a.lua')
        assert.is_nil(result)
      end)
    end)

    it('returns diff text for modified files', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          files = { ['a.lua'] = 'line1\nmodified\nline3\n' },
          snapshots = { ['a.lua'] = 'line1\noriginal\nline3\n' },
          pending = { { file = 'a.lua', is_new = false } },
        })

        local result = diff.compute('a.lua')
        assert.is_not_nil(result)
        assert.truthy(result:find('%-original'))
        assert.truthy(result:find('%+modified'))
      end)
    end)

    it('handles new files', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          files = { ['new.lua'] = 'brand new\n' },
          snapshots = {},
          pending = { { file = 'new.lua', is_new = true } },
        })
        -- Mark as new file
        local snap_dir = test_dir .. '/.claude-diff/snapshots'
        vim.fn.writefile({ '__CLAUDE_DIFF_NEW_FILE__' }, snap_dir .. '/new.lua')

        local result, is_new = diff.compute('new.lua')
        assert.is_true(is_new)
        assert.is_not_nil(result)
      end)
    end)
  end)

  describe('get_file_lines', function()
    local helpers = require('tests.helpers')
    local config = require('claude-diff.config')
    local test_dir

    before_each(function()
      test_dir = helpers.create_temp_dir()
      config.setup({ storage_dir = '.claude-diff' })
    end)

    after_each(function()
      helpers.remove_dir(test_dir)
    end)

    it('returns old and new lines for modified file', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          files = { ['a.lua'] = 'line1\nmodified\nline3\n' },
          snapshots = { ['a.lua'] = 'line1\noriginal\nline3\n' },
          pending = { { file = 'a.lua', is_new = false } },
        })

        local old_lines, new_lines, is_new = diff.get_file_lines('a.lua')
        assert.is_false(is_new)
        assert.are.same({ 'line1', 'original', 'line3' }, old_lines)
        assert.are.same({ 'line1', 'modified', 'line3' }, new_lines)
      end)
    end)

    it('returns empty old_lines for new file', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          files = { ['new.lua'] = 'content\n' },
          snapshots = {},
          pending = { { file = 'new.lua', is_new = true } },
        })
        local snap_dir = test_dir .. '/.claude-diff/snapshots'
        vim.fn.writefile({ '__CLAUDE_DIFF_NEW_FILE__' }, snap_dir .. '/new.lua')

        local old_lines, new_lines, is_new = diff.get_file_lines('new.lua')
        assert.is_true(is_new)
        assert.are.same({}, old_lines)
        assert.are.same({ 'content' }, new_lines)
      end)
    end)
  end)
end)
