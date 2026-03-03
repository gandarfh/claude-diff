local helpers = require('tests.helpers')

describe('init', function()
  local init, panel, viewer, config
  local test_dir

  before_each(function()
    test_dir = helpers.create_temp_dir()

    config = require('claude-diff.config')
    config.setup({ storage_dir = '.claude-diff' })
    require('claude-diff.ui.highlights').setup()

    -- Pre-load lazy-required modules before cwd changes
    require('claude-diff.actions')
    require('claude-diff.init')
    package.loaded['claude-diff'] = package.loaded['claude-diff.init']

    init = require('claude-diff.init')
    panel = require('claude-diff.ui.panel')
    viewer = require('claude-diff.ui.viewer')
  end)

  after_each(function()
    pcall(function() viewer.close() end)
    pcall(function() panel.close() end)
    helpers.remove_dir(test_dir)
  end)

  local function setup_files()
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

  describe('setup', function()
    it('configures defaults correctly', function()
      init.setup({ storage_dir = '.custom-dir' })
      local cfg = config.get()
      assert.equals('.custom-dir', cfg.storage_dir)
    end)
  end)

  describe('open and close', function()
    it('open() opens the panel', function()
      helpers.with_cwd(test_dir, function()
        setup_files()

        init.open()

        assert.is_true(panel.is_open())
      end)
    end)

    it('close() closes panel', function()
      helpers.with_cwd(test_dir, function()
        setup_files()

        init.open()
        assert.is_true(panel.is_open())

        init.close()

        assert.is_false(panel.is_open())
      end)
    end)

    it('close() closes viewer', function()
      helpers.with_cwd(test_dir, function()
        setup_files()

        viewer.open('a.lua')
        assert.is_true(viewer.is_open())

        init.close()

        assert.is_false(viewer.is_open())
      end)
    end)
  end)

  describe('toggle', function()
    it('opens when closed', function()
      helpers.with_cwd(test_dir, function()
        setup_files()

        assert.is_false(panel.is_open())
        init.toggle()
        assert.is_true(panel.is_open())
      end)
    end)

    it('closes when open', function()
      helpers.with_cwd(test_dir, function()
        setup_files()

        init.open()
        assert.is_true(panel.is_open())

        init.toggle()
        assert.is_false(panel.is_open())
      end)
    end)
  end)

  describe('refresh', function()
    it('does not crash when panel is not open', function()
      -- Should not error
      init.refresh()
    end)

    it('refreshes when panel is open', function()
      helpers.with_cwd(test_dir, function()
        setup_files()

        init.open()
        -- Should not error
        init.refresh()
        assert.is_true(panel.is_open())
      end)
    end)
  end)
end)
