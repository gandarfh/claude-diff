local helpers = require('tests.helpers')

describe('store', function()
  local store
  local test_dir

  before_each(function()
    test_dir = helpers.create_temp_dir()

    -- Reset store module
    package.loaded['claude-diff.store'] = nil
    package.loaded['claude-diff.config'] = nil

    local config = require('claude-diff.config')
    config.setup({ storage_dir = '.claude-diff' })
    store = require('claude-diff.store')
  end)

  after_each(function()
    helpers.remove_dir(test_dir)
  end)

  describe('encode_path / decode_path', function()
    it('encodes slashes with URL-style encoding', function()
      assert.equals('src%2Ffoo%2Fbar.ts', store.encode_path('src/foo/bar.ts'))
    end)

    it('decodes URL-encoded paths back to slashes', function()
      assert.equals('src/foo/bar.ts', store.decode_path('src%2Ffoo%2Fbar.ts'))
    end)

    it('roundtrips correctly', function()
      local path = 'lua/claude-diff/ui/viewer.lua'
      assert.equals(path, store.decode_path(store.encode_path(path)))
    end)

    it('handles filenames with double underscores without collision', function()
      local path_with_underscores = 'src/my__module.lua'
      local path_with_slashes = 'src/my/module.lua'
      local encoded1 = store.encode_path(path_with_underscores)
      local encoded2 = store.encode_path(path_with_slashes)
      assert.are_not.equal(encoded1, encoded2)
      assert.equals(path_with_underscores, store.decode_path(encoded1))
      assert.equals(path_with_slashes, store.decode_path(encoded2))
    end)

    it('handles paths with percent signs', function()
      local path = 'src/100%done.lua'
      assert.equals(path, store.decode_path(store.encode_path(path)))
    end)
  end)

  describe('abs_path', function()
    it('builds absolute path from relative', function()
      helpers.with_cwd(test_dir, function()
        local result = store.abs_path('foo/bar.lua')
        -- Use getcwd() to account for macOS symlink resolution (/var -> /private/var)
        assert.equals(vim.fn.getcwd() .. '/foo/bar.lua', result)
      end)
    end)
  end)

  describe('path validation', function()
    it('rejects absolute paths in write_file', function()
      assert.has_error(function()
        store.write_file('/etc/passwd', 'bad')
      end)
    end)

    it('rejects path traversal in delete_file', function()
      assert.has_error(function()
        store.delete_file('../../etc/passwd')
      end)
    end)

    it('rejects path traversal in update_snapshot', function()
      assert.has_error(function()
        store.update_snapshot('../escape.lua', 'bad')
      end)
    end)
  end)

  describe('pending', function()
    it('returns empty when no pending.json', function()
      helpers.with_cwd(test_dir, function()
        assert.are.same({}, store.get_pending())
      end)
    end)

    it('reads and writes pending entries', function()
      helpers.with_cwd(test_dir, function()
        local entries = {
          { file = 'foo.lua', is_new = false },
          { file = 'bar.lua', is_new = true },
        }
        store.set_pending(entries)

        local result = store.get_pending()
        assert.equals(2, #result)
        assert.equals('foo.lua', result[1].file)
        assert.equals('bar.lua', result[2].file)
      end)
    end)

    it('removes a specific entry', function()
      helpers.with_cwd(test_dir, function()
        store.set_pending({
          { file = 'a.lua' },
          { file = 'b.lua' },
          { file = 'c.lua' },
        })

        store.remove_pending('b.lua')

        local result = store.get_pending()
        assert.equals(2, #result)
        assert.equals('a.lua', result[1].file)
        assert.equals('c.lua', result[2].file)
      end)
    end)
  end)

  describe('snapshots', function()
    it('returns nil for non-existent snapshot', function()
      helpers.with_cwd(test_dir, function()
        local content, is_new = store.get_snapshot('nonexistent.lua')
        assert.is_nil(content)
        assert.is_false(is_new)
      end)
    end)

    it('reads snapshot content', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          snapshots = { ['foo.lua'] = 'original content\n' },
        })

        local content, is_new = store.get_snapshot('foo.lua')
        assert.is_not_nil(content)
        assert.is_false(is_new)
        assert.truthy(content:find('original content'))
      end)
    end)

    it('detects new file marker', function()
      helpers.with_cwd(test_dir, function()
        local snap_dir = test_dir .. '/.claude-diff/snapshots'
        vim.fn.mkdir(snap_dir, 'p')
        vim.fn.writefile({ '__CLAUDE_DIFF_NEW_FILE__' }, snap_dir .. '/foo.lua')

        local content, is_new = store.get_snapshot('foo.lua')
        assert.is_nil(content)
        assert.is_true(is_new)
      end)
    end)

    it('removes snapshot', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          snapshots = { ['foo.lua'] = 'content\n' },
        })

        store.remove_snapshot('foo.lua')

        local content = store.get_snapshot('foo.lua')
        assert.is_nil(content)
      end)
    end)

    it('updates snapshot', function()
      helpers.with_cwd(test_dir, function()
        helpers.setup_project({
          dir = test_dir,
          snapshots = { ['foo.lua'] = 'old\n' },
        })

        store.update_snapshot('foo.lua', 'new content\n')

        local content = store.get_snapshot('foo.lua')
        assert.truthy(content:find('new content'))
      end)
    end)
  end)

  describe('file operations', function()
    it('reads current file content', function()
      helpers.with_cwd(test_dir, function()
        helpers.write_file(test_dir .. '/test.lua', 'hello world\n')

        local content = store.get_current('test.lua')
        assert.truthy(content:find('hello world'))
      end)
    end)

    it('writes file content', function()
      helpers.with_cwd(test_dir, function()
        store.write_file('output.lua', 'written content\n')

        local content = helpers.read_file(test_dir .. '/output.lua')
        assert.truthy(content:find('written content'))
      end)
    end)

    it('deletes a file', function()
      helpers.with_cwd(test_dir, function()
        helpers.write_file(test_dir .. '/to_delete.lua', 'bye\n')
        assert.equals(1, vim.fn.filereadable(test_dir .. '/to_delete.lua'))

        store.delete_file('to_delete.lua')
        assert.equals(0, vim.fn.filereadable(test_dir .. '/to_delete.lua'))
      end)
    end)
  end)
end)
