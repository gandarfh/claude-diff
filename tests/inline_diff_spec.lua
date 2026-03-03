local inline_diff = require('claude-diff.ui.inline_diff')

describe('inline_diff', function()
  describe('char_diff', function()
    it('returns empty ranges for identical strings', function()
      local old_ranges, new_ranges = inline_diff.char_diff('hello world', 'hello world')
      assert.are.same({}, old_ranges)
      assert.are.same({}, new_ranges)
    end)

    it('detects single character change in middle', function()
      local old_ranges, new_ranges = inline_diff.char_diff('hello', 'hallo')
      -- 'e' at index 1 changed to 'a'
      assert.equals(1, #old_ranges)
      assert.equals(1, #new_ranges)
      assert.equals(1, old_ranges[1][1]) -- 0-indexed: byte 1
      assert.equals(2, old_ranges[1][2])
      assert.equals(1, new_ranges[1][1])
      assert.equals(2, new_ranges[1][2])
    end)

    it('detects change at beginning', function()
      local old_ranges, new_ranges = inline_diff.char_diff('abc', 'xbc')
      assert.equals(1, #old_ranges)
      assert.equals(0, old_ranges[1][1])
      assert.equals(1, old_ranges[1][2])
    end)

    it('detects change at end', function()
      local old_ranges, new_ranges = inline_diff.char_diff('abc', 'abx')
      assert.equals(1, #old_ranges)
      assert.equals(2, old_ranges[1][1])
      assert.equals(3, old_ranges[1][2])
    end)

    it('detects multiple disjoint changes', function()
      local old_ranges, new_ranges = inline_diff.char_diff('abcdef', 'xbcdxf')
      -- 'a' changed to 'x', 'e' changed to 'x'
      assert.equals(2, #old_ranges)
      assert.equals(2, #new_ranges)
    end)

    it('handles completely different strings', function()
      local old_ranges, new_ranges = inline_diff.char_diff('abc', 'xyz')
      assert.is_true(#old_ranges > 0)
      assert.is_true(#new_ranges > 0)
    end)

    it('handles empty old string', function()
      local old_ranges, new_ranges = inline_diff.char_diff('', 'hello')
      assert.are.same({}, old_ranges)
      assert.equals(1, #new_ranges)
      assert.equals(0, new_ranges[1][1])
      assert.equals(5, new_ranges[1][2])
    end)

    it('handles empty new string', function()
      local old_ranges, new_ranges = inline_diff.char_diff('hello', '')
      assert.equals(1, #old_ranges)
      assert.equals(0, old_ranges[1][1])
      assert.equals(5, old_ranges[1][2])
      assert.are.same({}, new_ranges)
    end)

    it('handles addition in middle', function()
      local old_ranges, new_ranges = inline_diff.char_diff('ac', 'abc')
      assert.are.same({}, old_ranges) -- nothing deleted
      assert.equals(1, #new_ranges) -- 'b' added
    end)

    it('handles deletion in middle', function()
      local old_ranges, new_ranges = inline_diff.char_diff('abc', 'ac')
      assert.equals(1, #old_ranges) -- 'b' deleted
      assert.are.same({}, new_ranges)
    end)
  end)

  describe('apply and clear', function()
    -- Helper: create two windows with diffthis enabled
    local function setup_diff_wins(old_lines, new_lines)
      local left_buf = vim.api.nvim_create_buf(false, true)
      local right_buf = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, old_lines)
      vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, new_lines)

      -- Create a split layout for diff
      vim.cmd('enew')
      local left_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(left_win, left_buf)
      vim.cmd('diffthis')

      vim.cmd('vsplit')
      local right_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(right_win, right_buf)
      vim.cmd('diffthis')

      return left_buf, right_buf, left_win, right_win
    end

    local function cleanup(left_buf, right_buf)
      vim.cmd('diffoff!')
      pcall(vim.cmd, 'only')
      pcall(vim.api.nvim_buf_delete, left_buf, { force = true })
      pcall(vim.api.nvim_buf_delete, right_buf, { force = true })
    end

    it('places extmarks on buffers for changed characters', function()
      local old_lines = { 'hello world', 'unchanged' }
      local new_lines = { 'hello earth', 'unchanged' }

      local left_buf, right_buf, left_win, right_win = setup_diff_wins(old_lines, new_lines)

      inline_diff.apply(left_buf, right_buf, left_win, right_win, old_lines, new_lines)

      local ns_id = vim.api.nvim_create_namespace('claude_diff_inline')
      local left_marks = vim.api.nvim_buf_get_extmarks(left_buf, ns_id, 0, -1, {})
      local right_marks = vim.api.nvim_buf_get_extmarks(right_buf, ns_id, 0, -1, {})

      assert.is_true(#left_marks > 0)
      assert.is_true(#right_marks > 0)

      -- Marks should be on line 0 (first line changed), not line 1 (unchanged)
      assert.equals(0, left_marks[1][2])
      assert.equals(0, right_marks[1][2])

      cleanup(left_buf, right_buf)
    end)

    it('clear removes all extmarks', function()
      local old_lines = { 'old' }
      local new_lines = { 'new' }

      local left_buf, right_buf, left_win, right_win = setup_diff_wins(old_lines, new_lines)

      inline_diff.apply(left_buf, right_buf, left_win, right_win, old_lines, new_lines)
      inline_diff.clear(left_buf, right_buf)

      local ns_id = vim.api.nvim_create_namespace('claude_diff_inline')
      local left_marks = vim.api.nvim_buf_get_extmarks(left_buf, ns_id, 0, -1, {})
      local right_marks = vim.api.nvim_buf_get_extmarks(right_buf, ns_id, 0, -1, {})

      assert.are.same({}, left_marks)
      assert.are.same({}, right_marks)

      cleanup(left_buf, right_buf)
    end)

    it('does not crash with identical content', function()
      local lines = { 'same', 'content' }

      local left_buf, right_buf, left_win, right_win = setup_diff_wins(lines, lines)

      -- Should not error
      inline_diff.apply(left_buf, right_buf, left_win, right_win, lines, lines)

      cleanup(left_buf, right_buf)
    end)

    it('does not place marks on purely added/deleted lines', function()
      local old_lines = { 'keep', 'deleted' }
      local new_lines = { 'keep', 'added1', 'added2' }

      local left_buf, right_buf, left_win, right_win = setup_diff_wins(old_lines, new_lines)

      inline_diff.apply(left_buf, right_buf, left_win, right_win, old_lines, new_lines)

      local ns_id = vim.api.nvim_create_namespace('claude_diff_inline')
      local right_marks = vim.api.nvim_buf_get_extmarks(right_buf, ns_id, 0, -1, {})

      -- Purely added lines should not have char-level marks
      -- Only DiffChange lines get char marks, DiffAdd lines do not
      for _, mark in ipairs(right_marks) do
        -- line 2 (0-indexed) is 'added2' which is purely added, should have no marks
        assert.is_not.equals(2, mark[2])
      end

      cleanup(left_buf, right_buf)
    end)
  end)
end)
