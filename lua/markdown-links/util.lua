--- Shared utility functions for markdown-links
--- @module markdown-links.util

local id_mod = require("markdown-links.id")

local M = {}

--- Extract the basename (filename) from a file path.
--- @param filepath string The full file path
--- @return string basename The filename portion, or empty string for non-string input
function M.get_basename(filepath)
  return filepath:match("([^/]+)$") or filepath
end

--- Read the frontmatter ID from a markdown file.
--- Opens the file with io.open (works in tests without vim mock).
--- Reads entire frontmatter block and extracts the id field.
--- @param filepath string The absolute path to the file
--- @return string|nil id The frontmatter ID, or nil if not found/invalid
function M.read_frontmatter_id(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end

  local first_line = file:read("*l")
  if not first_line or first_line ~= "---" then
    file:close()
    return nil
  end

  local found_id = nil
  while true do
    local line = file:read("*l")
    if not line then
      break
    end
    if line == "---" then
      break
    end
    local value = line:match("^id:%s*(.-)%s*$")
    if value and id_mod.validate_id(value) then
      found_id = value
      break
    end
  end

  file:close()
  return found_id
end

--- Check if a buffer is a markdown file.
--- Checks the buffer's filetype option first, falls back to checking .md extension.
--- @param bufnr number|nil The buffer number (defaults to current buffer, 0)
--- @return boolean is_markdown True if the buffer is a markdown file
function M.is_markdown_file(bufnr)
  bufnr = bufnr or 0

  -- Try filetype option first
  local ok, ft = pcall(function()
    return vim.bo[bufnr].filetype
  end)
  if ok and ft == "markdown" then
    return true
  end

  -- Fall back to checking filename extension
  local ok2, name = pcall(vim.api.nvim_buf_get_name, bufnr)
  if ok2 and type(name) == "string" and name:match("%.md$") then
    return true
  end

  return false
end

--- Open a file in the editor with a whitelisted open mode.
--- Centralizes the resolve_open_mode + vim.cmd pattern to prevent command injection.
--- @param filepath string The absolute path to the file to open
--- @param raw_open_mode string|nil The user-configured open_mode value
function M.open_file(filepath, raw_open_mode)
  local config_mod = require("markdown-links.config")
  local mode = config_mod.resolve_open_mode(raw_open_mode)
  vim.cmd(mode .. " " .. vim.fn.fnameescape(filepath))
end

return M
