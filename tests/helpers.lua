-- Test helpers for claude-diff
local M = {}

--- Create a temporary directory for test fixtures
---@return string path to temp dir
function M.create_temp_dir()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, 'p')
  return tmp
end

--- Remove a directory recursively
---@param dir string
function M.remove_dir(dir)
  vim.fn.delete(dir, 'rf')
end

--- Write a file with content
---@param path string
---@param content string
function M.write_file(path, content)
  local parent = vim.fn.fnamemodify(path, ':h')
  vim.fn.mkdir(parent, 'p')
  local lines = vim.split(content, '\n', { plain = true })
  if #lines > 0 and lines[#lines] == '' then
    table.remove(lines)
  end
  vim.fn.writefile(lines, path)
end

--- Read a file and return content
---@param path string
---@return string
function M.read_file(path)
  local lines = vim.fn.readfile(path)
  return table.concat(lines, '\n') .. '\n'
end

--- Setup a test project with store, snapshot, and pending.json
---@param opts table { dir: string, files: table<string, string>, snapshots: table<string, string>, pending: table[] }
function M.setup_project(opts)
  local dir = opts.dir

  -- Write project files
  for rel_path, content in pairs(opts.files or {}) do
    M.write_file(dir .. '/' .. rel_path, content)
  end

  -- Write snapshots
  local snap_dir = dir .. '/.claude-diff/snapshots'
  vim.fn.mkdir(snap_dir, 'p')
  for rel_path, content in pairs(opts.snapshots or {}) do
    local encoded = rel_path:gsub('/', '__')
    M.write_file(snap_dir .. '/' .. encoded, content)
  end

  -- Write pending.json
  if opts.pending then
    local pending_path = dir .. '/.claude-diff/pending.json'
    vim.fn.writefile({ vim.json.encode(opts.pending) }, pending_path)
  end

  -- Write .gitignore
  M.write_file(dir .. '/.claude-diff/.gitignore', '*\n')
end

--- Run a function with cwd set to a specific directory, then restore
---@param dir string
---@param fn function
function M.with_cwd(dir, fn)
  local old_cwd = vim.fn.getcwd()
  vim.cmd('cd ' .. vim.fn.fnameescape(dir))
  local ok, err = pcall(fn)
  vim.cmd('cd ' .. vim.fn.fnameescape(old_cwd))
  if not ok then
    error(err)
  end
end

return M
