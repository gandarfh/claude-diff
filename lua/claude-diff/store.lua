local config = require('claude-diff.config')

local M = {}

-- In-memory cache for pending.json
local _pending_cache = nil

--- Get the absolute path to the storage directory
---@return string
function M.storage_dir()
  local cwd = vim.fn.getcwd()
  return cwd .. '/' .. config.get().storage_dir
end

--- Get the absolute path to the snapshots directory
---@return string
function M.snapshots_dir()
  return M.storage_dir() .. '/snapshots'
end

--- Get the path to pending.json
---@return string
function M.pending_file()
  return M.storage_dir() .. '/pending.json'
end

--- Encode a relative file path for use as snapshot filename
---@param relative_path string
---@return string
function M.encode_path(relative_path)
  return relative_path:gsub('/', '__')
end

--- Decode a snapshot filename back to relative path
---@param encoded string
---@return string
function M.decode_path(encoded)
  return encoded:gsub('__', '/')
end

--- Read and parse pending.json (cached)
---@return table[] List of pending entries
function M.get_pending()
  if _pending_cache then
    return _pending_cache
  end

  local path = M.pending_file()
  if vim.fn.filereadable(path) ~= 1 then
    _pending_cache = {}
    return _pending_cache
  end

  local content = vim.fn.readfile(path)
  if #content == 0 then
    _pending_cache = {}
    return _pending_cache
  end

  local ok, data = pcall(vim.json.decode, table.concat(content, '\n'))
  if not ok or type(data) ~= 'table' then
    _pending_cache = {}
    return _pending_cache
  end

  _pending_cache = data
  return _pending_cache
end

--- Write pending list to pending.json
---@param entries table[]
function M.set_pending(entries)
  _pending_cache = entries

  local dir = M.storage_dir()
  vim.fn.mkdir(dir, 'p')

  local json = vim.json.encode(entries)
  vim.fn.writefile({ json }, M.pending_file())
end

--- Invalidate the pending cache (forces re-read from disk on next get_pending)
function M.invalidate_cache()
  _pending_cache = nil
end

--- Remove a file entry from pending list
---@param relative_path string
function M.remove_pending(relative_path)
  local entries = M.get_pending()
  local filtered = {}
  for _, entry in ipairs(entries) do
    if entry.file ~= relative_path then
      table.insert(filtered, entry)
    end
  end
  M.set_pending(filtered)
end

--- Get snapshot content for a file
---@param relative_path string
---@return string|nil content, boolean is_new
function M.get_snapshot(relative_path)
  local encoded = M.encode_path(relative_path)
  local snapshot_path = M.snapshots_dir() .. '/' .. encoded

  if vim.fn.filereadable(snapshot_path) ~= 1 then
    return nil, false
  end

  local lines = vim.fn.readfile(snapshot_path)
  local content = table.concat(lines, '\n')

  if content == '__CLAUDE_DIFF_NEW_FILE__' then
    return nil, true
  end

  -- Preserve trailing newline if the original file had one
  if #lines > 0 then
    content = content .. '\n'
  end

  return content, false
end

--- Get current file content from disk
---@param relative_path string
---@return string|nil
function M.get_current(relative_path)
  local cwd = vim.fn.getcwd()
  local abs_path = cwd .. '/' .. relative_path

  if vim.fn.filereadable(abs_path) ~= 1 then
    return nil
  end

  local lines = vim.fn.readfile(abs_path)
  local content = table.concat(lines, '\n')
  if #lines > 0 then
    content = content .. '\n'
  end
  return content
end

--- Remove snapshot file for a given path
---@param relative_path string
function M.remove_snapshot(relative_path)
  local encoded = M.encode_path(relative_path)
  local snapshot_path = M.snapshots_dir() .. '/' .. encoded
  vim.fn.delete(snapshot_path)
end

--- Write content to a project file (for reverting)
---@param relative_path string
---@param content string
function M.write_file(relative_path, content)
  local cwd = vim.fn.getcwd()
  local abs_path = cwd .. '/' .. relative_path

  -- Ensure parent dir exists
  local parent = vim.fn.fnamemodify(abs_path, ':h')
  vim.fn.mkdir(parent, 'p')

  local lines = vim.split(content, '\n', { plain = true })
  -- Remove trailing empty string from split if content ends with \n
  if #lines > 0 and lines[#lines] == '' then
    table.remove(lines)
  end
  vim.fn.writefile(lines, abs_path)
end

--- Delete a project file (for rejecting new files)
---@param relative_path string
function M.delete_file(relative_path)
  local cwd = vim.fn.getcwd()
  local abs_path = cwd .. '/' .. relative_path
  vim.fn.delete(abs_path)
end

--- Update snapshot content (for hunk-level approve)
---@param relative_path string
---@param content string
function M.update_snapshot(relative_path, content)
  local encoded = M.encode_path(relative_path)
  local snapshot_path = M.snapshots_dir() .. '/' .. encoded

  local lines = vim.split(content, '\n', { plain = true })
  if #lines > 0 and lines[#lines] == '' then
    table.remove(lines)
  end
  vim.fn.writefile(lines, snapshot_path)
end

return M
