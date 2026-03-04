local helpers = require('tests.helpers')

--- Normalize path resolving macOS /var -> /private/var symlinks
local function normalize_path(p)
  return vim.fn.resolve(p)
end

describe('plan', function()
  local plan, config
  local test_dir

  before_each(function()
    test_dir = normalize_path(helpers.create_temp_dir())

    config = require('claude-diff.config')
    config.setup({ storage_dir = '.claude-diff' })
    require('claude-diff.ui.highlights').setup()

    require('claude-diff.ui.inline_diff')
    require('claude-diff.ui.viewer')
    require('claude-diff.ui.panel')
    require('claude-diff.actions')
    require('claude-diff.init')
    package.loaded['claude-diff'] = package.loaded['claude-diff.init']

    plan = require('claude-diff.ui.plan')
  end)

  after_each(function()
    pcall(function() plan.close() end)
    helpers.remove_dir(test_dir)
  end)

  --- Helper: create a fake plan file and current-plan pointer
  local function setup_plan(opts)
    opts = opts or {}
    local plan_dir = test_dir .. '/plans'
    vim.fn.mkdir(plan_dir, 'p')

    local content = opts.content or '# Test Plan\n\nThis is a test plan.\n'
    local name = opts.name or 'test-plan.md'
    local plan_path = plan_dir .. '/' .. name
    helpers.write_file(plan_path, content)

    local storage_dir = test_dir .. '/.claude-diff'
    vim.fn.mkdir(storage_dir, 'p')
    vim.fn.writefile({ plan_path }, storage_dir .. '/current-plan')

    return plan_path
  end

  describe('is_open', function()
    it('returns false when not open', function()
      assert.is_false(plan.is_open())
    end)

    it('returns true when open', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open(plan_path)
        assert.is_true(plan.is_open())
      end)
    end)
  end)

  describe('resolve_plan_path', function()
    it('returns nil when no current-plan file exists', function()
      helpers.with_cwd(test_dir, function()
        assert.is_nil(plan.resolve_plan_path())
      end)
    end)

    it('returns the plan path when current-plan exists', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        assert.equals(plan_path, plan.resolve_plan_path())
      end)
    end)

    it('returns nil when plan file does not exist on disk', function()
      helpers.with_cwd(test_dir, function()
        local storage_dir = test_dir .. '/.claude-diff'
        vim.fn.mkdir(storage_dir, 'p')
        vim.fn.writefile({ '/nonexistent/plan.md' }, storage_dir .. '/current-plan')
        assert.is_nil(plan.resolve_plan_path())
      end)
    end)

    it('returns nil when current-plan is empty', function()
      helpers.with_cwd(test_dir, function()
        local storage_dir = test_dir .. '/.claude-diff'
        vim.fn.mkdir(storage_dir, 'p')
        vim.fn.writefile({ '' }, storage_dir .. '/current-plan')
        assert.is_nil(plan.resolve_plan_path())
      end)
    end)
  end)

  describe('open', function()
    it('opens a floating window with the plan file', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open(plan_path)

        assert.is_true(plan.is_open())
        assert.is_not_nil(plan.buf)
        assert.is_not_nil(plan.win)

        local buf_name = normalize_path(vim.api.nvim_buf_get_name(plan.buf))
        assert.equals(normalize_path(plan_path), buf_name)
      end)
    end)

    it('buffer is read-only', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open(plan_path)

        assert.is_false(vim.bo[plan.buf].modifiable)
        assert.is_true(vim.bo[plan.buf].readonly)
      end)
    end)

    it('buffer has markdown filetype', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open(plan_path)

        assert.equals('markdown', vim.bo[plan.buf].filetype)
      end)
    end)

    it('window has line numbers enabled', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open(plan_path)

        assert.is_true(vim.wo[plan.win].number)
      end)
    end)

    it('window has wrap enabled', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open(plan_path)

        assert.is_true(vim.wo[plan.win].wrap)
        assert.is_true(vim.wo[plan.win].linebreak)
      end)
    end)

    it('does not error when no plan found', function()
      helpers.with_cwd(test_dir, function()
        plan.open()
        assert.is_false(plan.is_open())
      end)
    end)

    it('focuses existing window if already open', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open(plan_path)
        local first_win = plan.win

        plan.open(plan_path)
        assert.equals(first_win, plan.win)
      end)
    end)

    it('uses resolve_plan_path when no argument given', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open()

        assert.is_true(plan.is_open())
        local buf_name = normalize_path(vim.api.nvim_buf_get_name(plan.buf))
        assert.equals(normalize_path(plan_path), buf_name)
      end)
    end)
  end)

  describe('close', function()
    it('closes the floating window', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open(plan_path)
        assert.is_true(plan.is_open())

        plan.close()
        assert.is_false(plan.is_open())
        assert.is_nil(plan.win)
        assert.is_nil(plan.buf)
      end)
    end)

    it('does not error when not open', function()
      plan.close()
      assert.is_false(plan.is_open())
    end)

    it('does not delete the buffer (real file)', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open(plan_path)
        local buf = plan.buf

        plan.close()

        -- Buffer should still be valid since it's a real file
        assert.is_true(vim.api.nvim_buf_is_valid(buf))
      end)
    end)
  end)

  describe('keymaps', function()
    it('q closes the plan', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open(plan_path)
        assert.is_true(plan.is_open())

        vim.api.nvim_feedkeys('q', 'x', false)
        vim.wait(200, function() return not plan.is_open() end)
        assert.is_false(plan.is_open())
      end)
    end)
  end)

  describe('integration with init.close', function()
    it('close() also closes plan preview', function()
      helpers.with_cwd(test_dir, function()
        local plan_path = setup_plan()
        plan.open(plan_path)
        assert.is_true(plan.is_open())

        require('claude-diff').close()
        assert.is_false(plan.is_open())
      end)
    end)
  end)
end)
