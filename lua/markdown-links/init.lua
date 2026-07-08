--- markdown-links: A minimalist note-linking system for Neovim
---@module 'markdown-links'

local config = require("markdown-links.config")
local follow = require("markdown-links.follow")
local id_mod = require("markdown-links.id")
local insert = require("markdown-links.insert")
local new_file_mod = require("markdown-links.new_file")
local search = require("markdown-links.search")
local util = require("markdown-links.util")

local M = {}

--- Module-level state (not captured by require cache)
local state = {
  --- @type table|nil Validated configuration
  config = nil,
  --- @type boolean Whether Telescope is available
  has_telescope = false,
  --- @type boolean Whether setup() has been called
  is_setup = false,
  --- @type boolean Whether missing vault dirs were already warned about
  vaults_checked = false,
}

--- Guard for public entry points: requires setup(), and warns once per
--- setup() about configured vault paths that don't exist. Missing vaults
--- don't block usage — the remaining ones still work, and
--- :checkhealth markdown-links shows details.
--- @return boolean ready True if the plugin is usable
local function ensure_ready()
  if not state.is_setup then
    vim.notify("markdown-links: setup() must be called before using the plugin", vim.log.levels.ERROR)
    return false
  end
  if not state.vaults_checked then
    state.vaults_checked = true
    local missing = config.missing_vaults(state.config.vault_path)
    if #missing > 0 then
      vim.notify(
        "markdown-links: vault_path does not exist or is not a directory: "
          .. table.concat(missing, ", ")
          .. " (see :checkhealth markdown-links)",
        vim.log.levels.WARN
      )
    end
  end
  return true
end

--- Set up vault-scoped keymaps via BufEnter autocommand.
--- Only creates autocommand if at least one keymap is configured.
local function setup_keymaps(cfg)
  local km = cfg.keymaps
  if km == false then
    return
  end

  -- Check if any keymap is actually set
  local any_set = false
  for _, v in pairs(km) do
    if v and v ~= false then
      any_set = true
      break
    end
  end
  if not any_set then
    return
  end

  local group = vim.api.nvim_create_augroup("MarkdownLinksKeymaps", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      local bufnr = ev.buf
      local buf_path = vim.api.nvim_buf_get_name(bufnr)
      if buf_path == "" then
        return
      end

      local vault = search.detect_vault(buf_path, cfg.vault_path)
      if not vault then
        return
      end

      local map_opts = { buffer = bufnr, silent = true }

      if km.follow_link then
        vim.keymap.set("n", km.follow_link, function()
          require("markdown-links").follow_link()
        end, vim.tbl_extend("force", map_opts, { desc = "Follow link under cursor" }))
      end

      if km.insert_link then
        vim.keymap.set("n", km.insert_link, function()
          require("markdown-links").insert_link()
        end, vim.tbl_extend("force", map_opts, { desc = "Insert markdown link" }))
        vim.keymap.set(
          "v",
          km.insert_link,
          ":MLInsertLink<CR>",
          vim.tbl_extend("force", map_opts, { desc = "Insert link with selection" })
        )
      end

      if km.new_file then
        vim.keymap.set("n", km.new_file, function()
          require("markdown-links").new_file()
        end, vim.tbl_extend("force", map_opts, { desc = "Create new note" }))
      end

      if km.add_frontmatter then
        vim.keymap.set("n", km.add_frontmatter, function()
          require("markdown-links").add_frontmatter()
        end, vim.tbl_extend("force", map_opts, { desc = "Add frontmatter ID to current file" }))
      end
    end,
  })
end

--- Setup the plugin with user configuration.
--- Can be called multiple times; replaces previous config.
--- @param opts table|nil User configuration options
function M.setup(opts)
  opts = opts or {}

  if type(opts) ~= "table" then
    error("markdown-links: setup() expects a table, got " .. type(opts), 2)
  end

  -- Merge with defaults (replacement, not deep merge of previous config)
  local merged = vim.tbl_deep_extend("force", {}, config.defaults, opts)

  -- Validate and normalize
  local validated = config.validate(merged)

  -- Cache Telescope availability
  local has_telescope, _ = pcall(require, "telescope")
  state.has_telescope = has_telescope

  -- Store validated config; re-arm the deferred vault existence warning
  state.config = validated
  state.is_setup = true
  state.vaults_checked = false

  -- Set up vault-scoped keymaps
  setup_keymaps(validated)

  -- Set up Oil.nvim create hook if enabled and Oil is available
  if validated.oil_create_hook then
    local oil_mod = require("markdown-links.oil")
    if oil_mod.is_oil_available() then
      oil_mod.setup_hook(validated, search)
    end
  end

  return state.config
end

--- Get the current validated configuration.
--- @return table|nil config The current config, or nil if setup() hasn't been called
function M._get_config()
  return state.config
end

--- Check if Telescope is available.
--- @return boolean
function M._has_telescope()
  return state.has_telescope
end

--- Insert a link to a note at the cursor position.
--- Opens a picker to select a note and inserts a markdown link.
--- @param from_range boolean|nil True when invoked from a visual-mode range command
function M.insert_link(from_range)
  if not ensure_ready() then
    return
  end
  insert.insert_link(state.config, search, state.has_telescope, from_range)
end

--- Follow the link under the cursor.
--- Finds markdown links at cursor position, extracts ID, and opens matching file.
function M.follow_link()
  if not ensure_ready() then
    return
  end
  follow.follow_link(state.config, search)
end

--- Create a new note file.
--- Prompts user for a filename, generates slug and ID, creates the file.
--- @param path string|nil Optional absolute path for the target directory
function M.new_file(path)
  if not ensure_ready() then
    return
  end
  new_file_mod.new_file(state.config, search, path)
end

--- Add a frontmatter ID to the current buffer if it doesn't have one.
--- Handles three cases:
---   1. No frontmatter at all → prepends full frontmatter block
---   2. Frontmatter exists but no id field → inserts id line into existing block
---   3. Frontmatter with valid id → skips, notifies user
--- Changes are made in-buffer (undoable with `u`), not written to disk.
function M.add_frontmatter()
  if not ensure_ready() then
    return
  end

  -- Check it's a markdown file
  if not util.is_markdown_file(0) then
    vim.notify("markdown-links: Current buffer is not a markdown file", vim.log.levels.WARN)
    return
  end

  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == "" then
    vim.notify("markdown-links: Buffer has no file name", vim.log.levels.ERROR)
    return
  end

  -- Detect vault
  local vault_path = search.detect_vault(buf_path, state.config.vault_path)
  if not vault_path then
    vim.notify("markdown-links: Buffer is outside all configured vaults", vim.log.levels.WARN)
    return
  end

  -- Read buffer content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Find closing --- index (nil if no frontmatter or unclosed)
  local closing_idx = nil
  if #lines >= 1 and lines[1] == "---" then
    for i = 2, #lines do
      if lines[i] == "---" then
        -- Check if any line in the frontmatter has a valid id (early return)
        for j = 2, i - 1 do
          local value = lines[j]:match("^id:%s*(.-)%s*$")
          if value and id_mod.validate_id(value) then
            vim.notify("markdown-links: Already has frontmatter ID: " .. value, vim.log.levels.INFO)
            return
          end
        end
        closing_idx = i
        break
      end
    end
  end

  -- Generate a unique ID (needed by both branches below)
  local new_id = new_file_mod.generate_unique_id(vault_path, search, state.config)
  if not new_id then
    vim.notify("markdown-links: Failed to generate unique ID", vim.log.levels.ERROR)
    return
  end

  -- Insert into existing frontmatter or prepend a new block
  if closing_idx then
    vim.api.nvim_buf_set_lines(0, 1, 1, false, { "id: " .. new_id })
    vim.notify("markdown-links: Added ID " .. new_id .. " to existing frontmatter", vim.log.levels.INFO)
  else
    vim.api.nvim_buf_set_lines(0, 0, 0, false, { "---", "id: " .. new_id, "---", "" })
    vim.notify("markdown-links: Added frontmatter with ID: " .. new_id, vim.log.levels.INFO)
  end
end

return M
