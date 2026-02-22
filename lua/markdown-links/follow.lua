--- Link following functionality for markdown-links
--- @module markdown-links.follow

local id_mod = require("markdown-links.id")
local util = require("markdown-links.util")

local M = {}

--- Lua pattern for matching markdown links with balanced brackets
--- Uses %b[] to properly handle nested brackets in link text
--- Captures the URL portion from inside the parentheses
local LINK_PATTERN = "(%b[])(%b())"

--- Lua pattern for matching an ID in a URL (bare ID or old slug-ID.md format)
local URL_ID_PATTERN = "(" .. id_mod.ID_PATTERN .. ")"

--- Parse a line and extract all markdown links with their positions.
--- Returns a list of link tables with url, start_col, and end_col fields.
--- Skips image links (those preceded by !).
--- @param line string The line content to parse
--- @return table[] links List of link tables {url, start_col, end_col}
function M.parse_links(line)
  local links = {}
  local search_start = 1

  while true do
    local s, e, _, parens = line:find(LINK_PATTERN, search_start)
    if not s then
      break
    end

    -- Extract URL from parentheses (remove surrounding () and any whitespace)
    local url = parens:sub(2, -2)

    -- Check if this is an image link (preceded by !)
    local is_image = false
    if s > 1 then
      local char_before = line:sub(s - 1, s - 1)
      if char_before == "!" then
        is_image = true
      end
    end

    if not is_image then
      table.insert(links, {
        url = url,
        start_col = s,
        end_col = e,
      })
    end

    search_start = e + 1
  end

  return links
end

--- Find the link at the given cursor column position.
--- Returns the first link if cursor is not on any link.
--- @param links table[] List of parsed link tables
--- @param col number 1-based cursor column position
--- @return table|nil link The link at cursor, or first link, or nil if no links
function M.find_link_at_cursor(links, col)
  if #links == 0 then
    return nil
  end

  -- Find link at cursor position
  for _, link in ipairs(links) do
    if col >= link.start_col and col <= link.end_col then
      return link
    end
  end

  -- Fall back to first link on the line
  return links[1]
end

--- Strip URL fragments (anchor links) from a URL.
--- Converts "file.md#heading" to "file.md"
--- @param url string The URL to strip
--- @return string stripped_url URL without fragment
function M.strip_fragment(url)
  return (url:gsub("#.*$", ""))
end

--- Extract an ID from a URL or filename.
--- Looks for YYYYMMDD-HHMMSS-XXXX pattern before .md extension.
--- @param url string The URL or filename to extract from
--- @return string|nil id The extracted ID, or nil if not found
function M.extract_id_from_url(url)
  return url:match(URL_ID_PATTERN)
end

--- Follow a link at the current cursor position.
--- Main entry point for the follow functionality.
--- @param config table The plugin configuration
--- @param search_module table The search module (for vault detection and file search)
function M.follow_link(config, search_module)
  -- Get current line and cursor position
  local line = vim.api.nvim_get_current_line()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local col = cursor[2] + 1 -- Convert to 1-based column

  -- Parse links on the line
  local links = M.parse_links(line)
  if #links == 0 then
    vim.notify("markdown-links: No markdown link found on current line", vim.log.levels.WARN)
    return
  end

  -- Find link at cursor or fall back to first link
  local link = M.find_link_at_cursor(links, col)
  if not link then
    -- Should not happen since we check #links > 0, but be safe
    vim.notify("markdown-links: No markdown link found on current line", vim.log.levels.WARN)
    return
  end

  -- Strip any fragment from the URL
  local url = M.strip_fragment(link.url)

  -- Extract ID from URL
  local id = M.extract_id_from_url(url)
  if not id then
    vim.notify("markdown-links: Not a note ID link: " .. link.url, vim.log.levels.WARN)
    return
  end

  -- Detect vault for current buffer
  local buf_path = vim.api.nvim_buf_get_name(0)
  local vault = search_module.detect_vault(buf_path, config.vault_path)
  if not vault then
    vim.notify("markdown-links: Buffer is not in a configured vault", vim.log.levels.ERROR)
    return
  end

  -- Search vault for files matching the ID via frontmatter
  local matches = search_module.search_files_by_frontmatter_id(id, vault, config.exclude_dirs)

  -- Handle results
  if #matches == 0 then
    vim.notify("Note not found for ID: " .. id, vim.log.levels.WARN)
  elseif #matches == 1 then
    util.open_file(matches[1], config.open_mode)
  else
    -- Multiple matches - show picker with full paths
    vim.ui.select(matches, {
      prompt = "Multiple notes found with ID " .. id .. ":",
      format_item = function(item)
        return item
      end,
    }, function(choice)
      if choice then
        util.open_file(choice, config.open_mode)
      end
    end)
  end
end

return M
