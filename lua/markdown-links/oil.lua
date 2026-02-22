--- Oil.nvim integration for markdown-links
--- Hooks into Oil's file creation to add frontmatter IDs to new markdown files.
---
--- Uses a single-phase approach: OilActionsPost processes all file creation
--- and adds frontmatter after Oil creates the files.
--- @module markdown-links.oil

local new_file_mod = require("markdown-links.new_file")

local M = {}

--- Check if Oil.nvim is available.
--- @return boolean available True if Oil is installed and loadable
function M.is_oil_available()
  local ok, _ = pcall(require, "oil")
  return ok
end

--- Add frontmatter to an existing file, preserving its content.
--- @param filepath string The path to the file
--- @param frontmatter_id string The ID to include in frontmatter
--- @return boolean success True if operation succeeded
function M.add_frontmatter_to_file(filepath, frontmatter_id)
  -- Read existing content (if any)
  local lines = {}
  local file = io.open(filepath, "r")
  if file then
    while true do
      local line = file:read("*l")
      if not line then
        break
      end
      table.insert(lines, line)
    end
    file:close()
  end

  -- Build frontmatter lines
  local new_lines = { "---", "id: " .. frontmatter_id, "---", "" }

  -- Append original content
  for _, line in ipairs(lines) do
    table.insert(new_lines, line)
  end

  -- Write back
  local write_result = vim.fn.writefile(new_lines, filepath)
  if write_result ~= 0 then
    vim.notify("markdown-links: Failed to write frontmatter to " .. filepath, vim.log.levels.ERROR)
    return false
  end

  return true
end

--- Register the OilActionsPost autocmd to add frontmatter to new files.
--- @param config table The plugin configuration
--- @param search_module table The search module
function M.setup_hook(config, search_module)
  local group = vim.api.nvim_create_augroup("MarkdownLinksOil", { clear = true })

  vim.api.nvim_create_autocmd("User", {
    pattern = "OilActionsPost",
    group = group,
    callback = function(ev)
      if ev.data.err then
        return
      end

      for _, action in ipairs(ev.data.actions) do
        -- Only process new file creation
        if action.type ~= "create" or action.entry_type ~= "file" then
          goto continue
        end

        local oil_util = require("oil.util")
        local _, path = oil_util.parse_url(action.url)
        if not path then
          goto continue
        end

        -- Only process markdown files
        if not path:match("%.md$") then
          goto continue
        end

        -- Only process files inside configured vaults
        local vault_path = search_module.detect_vault(path, config.vault_path)
        if not vault_path then
          goto continue
        end

        -- Generate unique ID with collision retry
        local new_id = new_file_mod.generate_unique_id(vault_path, search_module, config)
        if not new_id then
          vim.notify("markdown-links: Failed to generate unique ID for " .. path, vim.log.levels.ERROR)
          goto continue
        end

        M.add_frontmatter_to_file(path, new_id)

        ::continue::
      end
    end,
  })
end

return M
