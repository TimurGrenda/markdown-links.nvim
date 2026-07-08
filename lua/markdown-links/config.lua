--- Configuration defaults and validation for markdown-links
---@module 'markdown-links.config'

local M = {}

--- Valid keymap option keys.
local KEYMAP_KEYS = { "follow_link", "insert_link", "new_file", "add_frontmatter" }

--- Build the normalized default keymap table.
--- @return table keymaps
local function default_keymaps()
  local keymaps = {}
  for _, key in ipairs(KEYMAP_KEYS) do
    keymaps[key] = false
  end
  return keymaps
end

--- Default configuration values
M.defaults = {
  --- Path(s) to note vault directories. String or table of strings.
  --- @type string|string[]
  vault_path = {},

  --- How to open files when following links.
  --- @type "edit"|"vsplit"|"split"|"tabedit"
  open_mode = "edit",

  --- How notes are displayed in the picker.
  --- @type "filename"|"full_path"|"filename_with_path"|"title_with_path"
  picker_display = "title_with_path",

  --- Directories to exclude from vault search.
  --- @type string[]
  exclude_dirs = { ".git", ".obsidian" },

  --- Whether to auto-slugify and add IDs to new .md files created via Oil.nvim.
  --- Requires Oil.nvim to be installed; ignored if Oil is not available.
  --- @type boolean
  oil_create_hook = false,

  --- Keymaps scoped to vault buffers only.
  --- Each key maps to a string (lhs key sequence) or false (disabled).
  --- Set to false to disable the feature entirely (no autocommand created).
  --- @type table|false
  keymaps = default_keymaps(),
}

--- Valid open_mode values for vim.cmd (whitelist to prevent command injection)
M.VALID_OPEN_MODES = { edit = true, vsplit = true, split = true, tabedit = true }

--- Resolve an open_mode value to a safe, whitelisted command.
--- Falls back to "edit" for nil or unrecognized values.
--- @param raw_mode string|nil The raw open_mode from config
--- @return string mode A safe open_mode command (one of edit/vsplit/split/tabedit)
function M.resolve_open_mode(raw_mode)
  local mode = raw_mode or "edit"
  return M.VALID_OPEN_MODES[mode] and mode or "edit"
end

--- List configured vault paths that are not existing directories.
--- Existence is deliberately NOT checked at setup() — a missing dir (e.g. an
--- unmounted drive) must not block startup. Callers check lazily: init.lua
--- warns on first use, health.lua reports via :checkhealth.
--- @param vault_paths string[] Normalized vault paths
--- @return string[] missing Paths that do not exist as directories
function M.missing_vaults(vault_paths)
  local missing = {}
  for _, p in ipairs(vault_paths) do
    if vim.fn.isdirectory(p) ~= 1 then
      table.insert(missing, p)
    end
  end
  return missing
end

--- Validate and normalize configuration.
--- Expands paths, converts string vault_path to array, validates open_mode whitelist.
--- Does not check that vault paths exist (see missing_vaults).
--- @param opts table Raw user configuration (merged with defaults)
--- @return table Validated and normalized configuration
function M.validate(opts)
  local result = {}

  -- vault_path: normalize string to array, expand paths
  local vp = opts.vault_path
  if type(vp) == "string" then
    result.vault_path = { vp }
  elseif type(vp) == "table" then
    result.vault_path = vim.list_extend({}, vp)
  else
    result.vault_path = {}
  end

  local expanded_paths = {}
  for i, p in ipairs(result.vault_path) do
    expanded_paths[i] = vim.fs.normalize(p)
  end
  result.vault_path = expanded_paths

  -- open_mode: whitelist check (security — prevents command injection via vim.cmd)
  if opts.open_mode ~= nil and not M.VALID_OPEN_MODES[opts.open_mode] then
    error(string.format("markdown-links: Invalid open_mode '%s'. Valid: edit, vsplit, split, tabedit", tostring(opts.open_mode)), 2)
  end
  result.open_mode = opts.open_mode

  -- picker_display: pass through (invalid values hit the else/default branch in format_display)
  result.picker_display = opts.picker_display

  -- exclude_dirs: ensure iterable table (search.lua iterates with ipairs)
  result.exclude_dirs = opts.exclude_dirs and vim.list_extend({}, opts.exclude_dirs) or {}

  -- oil_create_hook: pass through (init.lua uses truthiness check)
  result.oil_create_hook = opts.oil_create_hook

  -- keymaps: false disables all; table normalizes known keys to string|false
  if opts.keymaps == false then
    result.keymaps = false
  elseif type(opts.keymaps) == "table" then
    result.keymaps = {}
    for _, k in ipairs(KEYMAP_KEYS) do
      result.keymaps[k] = opts.keymaps[k] or false
    end
  else
    result.keymaps = default_keymaps()
  end

  return result
end

return M
