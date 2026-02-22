--- Vault detection and file search for markdown-links
--- @module markdown-links.search

local M = {}

--- Check if a command is available in PATH.
--- @param cmd string The command name to check
--- @return boolean available True if the command is executable
local function is_executable(cmd)
  return vim.fn.executable(cmd) == 1
end

--- Pick the first available command from a prioritized list.
--- @param candidates string[] command candidates in priority order
--- @return string|nil cmd The first available command, or nil if none found
local function resolve_command(candidates)
  for _, cmd in ipairs(candidates) do
    if is_executable(cmd) then
      return cmd
    end
  end
  return nil
end

--- Run a command list and normalize result handling.
--- Returns empty table on shell error and removes empty lines.
--- @param cmd string[] Command argument list
--- @return string[] results
local function run_and_collect(cmd)
  local results = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return {}
  end

  local filtered = {}
  for _, item in ipairs(results) do
    if item ~= "" then
      table.insert(filtered, item)
    end
  end
  return filtered
end

--- Detect which vault a buffer belongs to using prefix matching.
--- Normalizes paths and returns the longest matching vault path (handles nested vaults).
--- Appends '/' to vault paths before prefix check to avoid false positives.
--- @param buffer_path string The absolute path of the current buffer
--- @param vault_paths string[] List of normalized vault paths
--- @return string|nil vault_path The matching vault path, or nil if no match
function M.detect_vault(buffer_path, vault_paths)
  local normalized = vim.fs.normalize(buffer_path)
  local best_match = nil
  local best_length = 0

  for _, vault_path in ipairs(vault_paths) do
    local normalized_vault = vim.fs.normalize(vault_path)
    local prefix = normalized_vault .. "/"
    if vim.startswith(normalized, prefix) then
      if #normalized_vault > best_length then
        best_match = normalized_vault
        best_length = #normalized_vault
      end
    end
  end

  return best_match
end

--- Build an fd/fdfind command as an argument list.
--- @param fd_cmd string The fd binary name
--- @param vault_path string The vault directory to search
--- @param exclude_dirs string[] Directories to exclude
--- @return string[] cmd The command as an argument list
local function build_fd_command(fd_cmd, vault_path, exclude_dirs)
  local cmd = { fd_cmd, "--extension", "md", "--no-ignore", "--hidden" }

  for _, dir in ipairs(exclude_dirs) do
    table.insert(cmd, "--exclude")
    table.insert(cmd, dir)
  end

  -- fd expects the search path as the last argument (after an implicit pattern)
  table.insert(cmd, ".")
  table.insert(cmd, vault_path)

  return cmd
end

--- Build an rg command for frontmatter ID search.
--- @param pattern string Regex pattern to match
--- @param vault_path string The vault directory to search
--- @param exclude_dirs string[] Directories to exclude
--- @return string[] cmd
local function build_rg_command(pattern, vault_path, exclude_dirs)
  local cmd = { "rg", "-l", "-m1", pattern }
  for _, dir in ipairs(exclude_dirs) do
    table.insert(cmd, "--glob")
    table.insert(cmd, "!" .. dir)
  end
  table.insert(cmd, vault_path)
  return cmd
end

--- Search a vault for markdown files using fd (or fdfind on Debian/Ubuntu).
--- Builds commands as argument lists (not concatenated strings) for security.
--- @param vault_path string The vault directory to search
--- @param exclude_dirs string[] Directories to exclude from search
--- @return string[] files List of absolute file paths, empty table on error
function M.search_vault(vault_path, exclude_dirs)
  exclude_dirs = exclude_dirs or {}

  local fd_cmd = resolve_command({ "fd", "fdfind" })
  if not fd_cmd then
    vim.notify("markdown-links: fd/fdfind not found in PATH", vim.log.levels.ERROR)
    return {}
  end

  local cmd = build_fd_command(fd_cmd, vault_path, exclude_dirs)
  return run_and_collect(cmd)
end

--- Search for files with a matching frontmatter ID using rg.
--- Builds commands as argument lists (not concatenated strings) for security.
--- @param id string The ID to search for in frontmatter
--- @param vault_path string The vault directory to search
--- @param exclude_dirs string[] Directories to exclude from search
--- @return string[] matches List of matching file paths
function M.search_files_by_frontmatter_id(id, vault_path, exclude_dirs)
  exclude_dirs = exclude_dirs or {}

  if not is_executable("rg") then
    vim.notify("markdown-links: rg not found in PATH", vim.log.levels.ERROR)
    return {}
  end

  local pattern = "^id: " .. id .. "$"
  local cmd = build_rg_command(pattern, vault_path, exclude_dirs)
  return run_and_collect(cmd)
end

return M
