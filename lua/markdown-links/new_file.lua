--- New file creation for markdown-links
--- @module markdown-links.new_file

local id = require("markdown-links.id")
local util = require("markdown-links.util")

local M = {}

--- Maximum number of ID generation attempts (initial + 3 retries)
local MAX_ID_ATTEMPTS = 4

--- Check if a string contains only printable ASCII characters (codes 32-126).
--- @param str string The string to validate
--- @return boolean valid True if all characters are printable ASCII
function M.is_ascii(str)
  for i = 1, #str do
    local byte = string.byte(str, i)
    if byte < 32 or byte > 126 then
      return false
    end
  end
  return true
end

--- Generate a unique ID with collision retry.
--- Attempts up to MAX_ID_ATTEMPTS times to generate a unique ID.
--- Checks uniqueness by searching for matching frontmatter IDs in the vault.
--- @param vault_path string The vault directory to check uniqueness against
--- @param search_module table The search module with search_files_by_frontmatter_id
--- @param cfg table The plugin configuration (needs exclude_dirs)
--- @return string|nil generated_id The unique ID, or nil if all attempts failed
function M.generate_unique_id(vault_path, search_module, cfg)
  local search_fn = function(check_id, vp)
    return search_module.search_files_by_frontmatter_id(check_id, vp, cfg.exclude_dirs)
  end
  for _ = 1, MAX_ID_ATTEMPTS do
    local new_id = id.generate_id()
    if id.check_id_uniqueness(new_id, vault_path, search_fn) then
      return new_id
    end
  end
  return nil
end

--- Create a new note file.
--- Prompts user for a filename, generates slug and ID, creates the file,
--- and opens it in the editor.
--- @param config table The plugin configuration
--- @param search_module table The search module (for vault detection and file search)
--- @param path_arg string|nil Optional absolute path for the target directory
function M.new_file(config, search_module, path_arg)
  -- Determine target directory and vault
  local target_dir
  local vault_path

  if path_arg and path_arg ~= "" then
    -- Validate path_arg is absolute
    if path_arg:sub(1, 1) ~= "/" then
      vim.notify("markdown-links: Path argument must be absolute: " .. path_arg, vim.log.levels.ERROR)
      return
    end

    -- Check that path_arg is inside a configured vault
    local normalized_path = vim.fs.normalize(path_arg)
    vault_path = search_module.detect_vault(normalized_path .. "/placeholder", config.vault_path)
    if not vault_path then
      vim.notify("markdown-links: Path is outside all configured vaults: " .. path_arg, vim.log.levels.ERROR)
      return
    end

    target_dir = normalized_path
  else
    -- Use current buffer's directory
    local buf_path = vim.api.nvim_buf_get_name(0)
    if buf_path == "" then
      vim.notify("markdown-links: Buffer has no file name", vim.log.levels.ERROR)
      return
    end

    vault_path = search_module.detect_vault(buf_path, config.vault_path)
    if not vault_path then
      vim.notify("markdown-links: Buffer is outside all configured vaults", vim.log.levels.ERROR)
      return
    end

    -- Extract directory from buffer path
    target_dir = vim.fs.dirname(buf_path) or vault_path
  end

  -- Prompt user for filename
  M._prompt_for_name(config, search_module, target_dir, vault_path)
end

--- Prompt the user for a note name and handle the response.
--- Separated for testability and re-prompting on invalid input.
--- @param config table The plugin configuration
--- @param search_module table The search module
--- @param target_dir string The directory to create the file in
--- @param vault_path string The vault path for ID uniqueness checking
function M._prompt_for_name(config, search_module, target_dir, vault_path)
  vim.ui.input({ prompt = "Name for new note:" }, function(input)
    -- Handle cancel (Escape) - silent abort
    if input == nil then
      return
    end

    -- Handle empty input (Enter with no text)
    if input == "" then
      vim.notify("markdown-links: File creation cancelled", vim.log.levels.INFO)
      return
    end

    -- Validate ASCII only (codes 32-126)
    if not M.is_ascii(input) then
      vim.notify("Invalid characters in name. Only printable ASCII characters are allowed.", vim.log.levels.ERROR)
      -- Re-prompt
      M._prompt_for_name(config, search_module, target_dir, vault_path)
      return
    end

    -- Trim whitespace, use original input as filename (no slugify)
    local name = input:match("^%s*(.-)%s*$")
    if name == "" then
      name = "Untitled"
    end

    -- Generate unique ID with collision retry
    local new_id = M.generate_unique_id(vault_path, search_module, config)
    if not new_id then
      vim.notify(
        "markdown-links: Failed to generate unique ID after " .. MAX_ID_ATTEMPTS .. " attempts",
        vim.log.levels.ERROR
      )
      return
    end

    -- Build filename (natural name, no ID in filename)
    local filename = name .. ".md"
    local filepath = target_dir .. "/" .. filename

    -- Guard against overwriting an existing file
    if vim.fn.filereadable(filepath) == 1 then
      vim.notify("markdown-links: File already exists: " .. filepath, vim.log.levels.ERROR)
      return
    end

    -- Create directory if needed
    vim.fn.mkdir(target_dir, "p")

    -- Create file with frontmatter containing the ID
    local write_result = vim.fn.writefile({ "---", "id: " .. new_id, "---", "" }, filepath)
    if write_result ~= 0 then
      vim.notify("markdown-links: Failed to create file: " .. filepath, vim.log.levels.ERROR)
      return
    end

    -- Open file (open_mode is whitelisted inside util.open_file to prevent command injection)
    util.open_file(filepath, config.open_mode)

    -- Show notification
    vim.notify("Created new note: " .. filename .. " in vault " .. vault_path, vim.log.levels.INFO)
  end)
end

return M
