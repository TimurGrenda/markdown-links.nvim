--- Link insertion with picker for markdown-links
--- @module markdown-links.insert

local util = require("markdown-links.util")

local M = {}

--- Get the relative directory from vault root (excludes filename).
--- @param filepath string The full file path
--- @param vault_path string The vault path
--- @return string relative_dir The directory relative to vault root
local function get_relative_dir(filepath, vault_path)
  local normalized_file = vim.fs.normalize(filepath)
  local normalized_vault = vim.fs.normalize(vault_path)
  local prefix = normalized_vault .. "/"
  if vim.startswith(normalized_file, prefix) then
    local rel = normalized_file:sub(#prefix + 1)
    -- Get directory part only (remove filename)
    local dir = rel:match("^(.-)/[^/]+$") or ""
    return dir
  end
  return ""
end

--- Format a label with an optional directory suffix.
--- @param label string The primary display text (filename or title)
--- @param relative_dir string Directory relative to vault root ("" for root)
--- @param padded boolean When true, pad label to 50 chars and append dir; when false, prepend dir
--- @return string display The formatted display string
local function format_with_optional_dir(label, relative_dir, padded)
  if relative_dir == "" then
    return label
  end
  if padded then
    return string.format("%-50s  %s/", label, relative_dir)
  end
  return relative_dir .. "/" .. label
end

--- Format display based on picker_display mode.
--- @param filepath string Full file path
--- @param vault_path string Vault path for relative calculations
--- @param mode string One of the 4 picker_display modes
--- @return string display The formatted display string
--- @return string ordinal The ordinal (full path for fuzzy matching)
local function format_display(filepath, vault_path, mode)
  local ctx = {
    filename = util.get_basename(filepath),
    relative_dir = get_relative_dir(filepath, vault_path),
  }
  ctx.title = ctx.filename:gsub("%.md$", "")

  local formatters = {
    filename = function(c)
      return c.filename
    end,
    full_path = function(c)
      return format_with_optional_dir(c.filename, c.relative_dir, false)
    end,
    filename_with_path = function(c)
      return format_with_optional_dir(c.filename, c.relative_dir, true)
    end,
    title_with_path = function(c)
      return format_with_optional_dir(c.title, c.relative_dir, true)
    end,
  }

  local formatter = formatters[mode] or formatters.title_with_path
  return formatter(ctx), filepath
end

--- Get the text from visual selection.
--- Returns nil if multi-line selection (invalid for markdown links).
--- @return string|nil text The selected text, or nil if multi-line or error
local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- Check if marks are valid
  if start_pos[2] == 0 or end_pos[2] == 0 then
    return nil
  end

  -- Multi-line selection is invalid for markdown links
  if start_pos[2] ~= end_pos[2] then
    vim.notify("markdown-links: Multi-line selection not supported for links", vim.log.levels.ERROR)
    return nil
  end

  local line = start_pos[2] - 1 -- 0-indexed
  local start_col = start_pos[3] - 1 -- 0-indexed

  -- Mark columns are 1-indexed inclusive. nvim_buf_get_text expects 0-indexed exclusive.
  -- 1-indexed inclusive == 0-indexed exclusive, so end_pos[3] is correct as-is.
  local mode = vim.fn.visualmode()
  if mode == "V" then
    -- Line-wise: shouldn't happen as we check for same line above
    return nil
  end
  local end_col = end_pos[3]

  local ok, lines = pcall(vim.api.nvim_buf_get_text, 0, line, start_col, line, end_col, {})
  if not ok or not lines or #lines == 0 then
    return nil
  end

  return lines[1]
end

--- Show picker using vim.ui.select as fallback.
--- @param items table[] Array of {display, filepath, filename} items
--- @param prompt string The prompt to show
--- @param callback function Callback(selected_item)
local function show_vim_ui_select(items, prompt, callback)
  if #items == 0 then
    vim.notify("markdown-links: No markdown files found in vault", vim.log.levels.WARN)
    return
  end

  local displays = {}
  for _, item in ipairs(items) do
    table.insert(displays, item.display)
  end

  vim.ui.select(displays, {
    prompt = prompt,
  }, function(choice, idx)
    if choice and idx then
      callback(items[idx])
    end
    -- If cancelled (nil), do nothing
  end)
end

--- Show picker using Telescope.
--- @param items table[] Array of {display, ordinal, filepath, filename} items
--- @param prompt string The prompt to show
--- @param callback function Callback(selected_item)
local function show_telescope_picker(items, prompt, callback)
  local ok, _ = pcall(require, "telescope")
  if not ok then
    show_vim_ui_select(items, prompt, callback)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local entry_maker = function(item)
    return {
      value = item,
      display = item.display,
      ordinal = item.ordinal,
    }
  end

  local picker_ok = pcall(function()
    pickers
      .new({}, {
        prompt_title = prompt,
        finder = finders.new_table({
          results = items,
          entry_maker = entry_maker,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(bufnr, _)
          actions.select_default:replace(function()
            actions.close(bufnr)
            local selection = action_state.get_selected_entry()
            if selection and selection.value then
              callback(selection.value)
            end
          end)
          return true -- Keep default mappings
        end,
      })
      :find()
  end)

  if not picker_ok then
    -- Fall back to vim.ui.select on Telescope error
    show_vim_ui_select(items, prompt, callback)
  end
end

--- Insert a link to a note at the cursor position.
--- @param config table The validated configuration
--- @param search table The search module for vault operations
--- @param has_telescope boolean Whether Telescope is available
--- @param from_range boolean|nil True when invoked from a visual-mode range command
function M.insert_link(config, search, has_telescope, from_range)
  -- Capture context at invocation for async safety
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local was_visual = from_range == true
  local visual_text = nil

  -- Get visual selection text if in visual mode
  if was_visual then
    visual_text = get_visual_selection()
    if visual_text == nil then
      return
    end
  end

  -- Check if buffer is markdown
  if not util.is_markdown_file(bufnr) then
    vim.notify("markdown-links: Not a markdown file", vim.log.levels.ERROR)
    return
  end

  -- Get buffer path
  local ok, buffer_path = pcall(vim.api.nvim_buf_get_name, bufnr)
  if not ok or buffer_path == "" then
    vim.notify("markdown-links: Buffer has no file name", vim.log.levels.ERROR)
    return
  end

  -- Detect vault
  local vault_path = search.detect_vault(buffer_path, config.vault_path)
  if not vault_path then
    vim.notify("markdown-links: Buffer is outside all configured vaults", vim.log.levels.ERROR)
    return
  end

  -- Search vault for markdown files
  local files = search.search_vault(vault_path, config.exclude_dirs)

  -- Filter files by ID (filename or frontmatter) and resolve IDs
  local id_files = {}
  for _, filepath in ipairs(files) do
    local note_id = util.read_frontmatter_id(filepath)
    if note_id then
      table.insert(id_files, { filepath = filepath, id = note_id })
    end
  end

  if #id_files == 0 then
    vim.notify("markdown-links: No markdown files with IDs found in vault", vim.log.levels.WARN)
    return
  end

  -- Build picker items
  local picker_display = config.picker_display or "title_with_path"
  local items = {}
  for _, entry in ipairs(id_files) do
    local display, ordinal = format_display(entry.filepath, vault_path, picker_display)
    local filename = util.get_basename(entry.filepath)
    table.insert(items, {
      display = display,
      ordinal = ordinal,
      filepath = entry.filepath,
      filename = filename,
      id = entry.id,
    })
  end

  -- Sort items alphabetically by display text for consistent UX
  table.sort(items, function(a, b)
    return a.display < b.display
  end)

  -- Show picker
  local prompt = string.format("Select note (%d found)", #items)
  local callback = function(selected)
    if not selected then
      return
    end

    -- Determine link title
    local title
    if was_visual and visual_text then
      title = visual_text
    else
      -- Generate title from filename
      title = selected.filename:gsub("%.md$", "")
    end

    -- Build link with bare ID as URL (never the human-readable filename)
    local link = string.format("[%s](%s)", title, selected.id)

    -- Insert or replace
    if was_visual then
      -- Replace visual selection
      local start_pos = vim.fn.getpos("'<")
      local end_pos = vim.fn.getpos("'>")
      local line = start_pos[2] - 1
      local start_col = start_pos[3] - 1
      -- Mark columns are 1-indexed inclusive; nvim_buf_set_text needs 0-indexed exclusive.
      -- 1-indexed inclusive == 0-indexed exclusive, so end_pos[3] is correct as-is.
      local end_col = end_pos[3]

      local ok, set_err = pcall(vim.api.nvim_buf_set_text, bufnr, line, start_col, line, end_col, { link })
      if not ok then
        vim.notify("markdown-links: Failed to insert link: " .. tostring(set_err), vim.log.levels.ERROR)
        return
      end

      -- Position cursor after the closing )
      local new_col = start_col + #link
      pcall(vim.api.nvim_win_set_cursor, 0, { line + 1, new_col })
    else
      -- Insert at cursor (after current character, like vim "a")
      local row = cursor_pos[1] - 1 -- 0-indexed
      local line_text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
      -- Clamp to line length so empty lines (length 0) don't produce col=1
      local col = math.min(cursor_pos[2] + 1, #line_text)

      local ok, set_err = pcall(vim.api.nvim_buf_set_text, bufnr, row, col, row, col, { link })
      if not ok then
        vim.notify("markdown-links: Failed to insert link: " .. tostring(set_err), vim.log.levels.ERROR)
        return
      end

      -- Position cursor after the closing )
      local new_col = col + #link
      pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, new_col })
    end
  end

  if has_telescope then
    show_telescope_picker(items, prompt, callback)
  else
    show_vim_ui_select(items, prompt, callback)
  end
end

-- Expose internals for testing
M._get_relative_dir = get_relative_dir
M._format_display = format_display

return M
