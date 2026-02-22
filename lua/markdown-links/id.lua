--- ID generation, validation, and collision checking for markdown-links
--- @module markdown-links.id

local M = {}

--- Character set for random suffix: lowercase alphanumeric
local CHARSET = "0123456789abcdefghijklmnopqrstuvwxyz"
local CHARSET_LEN = #CHARSET

--- Lua pattern for a valid ID: YYYYMMDD-HHMMSS-XXXX
local ID_PATTERN = "%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-[0-9a-z][0-9a-z][0-9a-z][0-9a-z]"
M.ID_PATTERN = ID_PATTERN

--- Seed math.random once at module load time.
--- Use os.time() + os.clock() * 1000 for better seed entropy.
--- Discard the first random value (known Lua quirk for better randomness).
math.randomseed(os.time() + math.floor(os.clock() * 1000))
math.random()

--- Generate a random 4-character suffix from the charset.
--- @return string suffix 4 lowercase alphanumeric characters
local function random_suffix()
  local chars = {}
  for i = 1, 4 do
    local idx = math.random(1, CHARSET_LEN)
    chars[i] = CHARSET:sub(idx, idx)
  end
  return table.concat(chars)
end

--- Generate a new unique ID using UTC timestamp + 4 random characters.
--- Format: YYYYMMDD-HHMMSS-XXXX where X is [0-9a-z]
--- @return string id A 20-character ID string
function M.generate_id()
  local timestamp = os.date("!%Y%m%d-%H%M%S")
  local suffix = random_suffix()
  return timestamp .. "-" .. suffix
end

--- Validate whether a string is a valid markdown-links ID.
--- @param id_string string The string to validate
--- @return boolean valid True if the string matches the ID format
function M.validate_id(id_string)
  if #id_string ~= 20 then
    return false
  end
  return id_string:match("^" .. ID_PATTERN .. "$") ~= nil
end

--- Check whether an ID is unique within a vault.
--- Uses an injected search function for testability.
--- Passes the raw ID to search_fn — the search function decides how to match
--- filenames (handles both slug-ID.md and ID-only.md formats).
--- @param id string The ID to check
--- @param vault_path string The vault directory to search in
--- @param search_fn function A function(id, vault_path) -> table of matching filenames
--- @return boolean unique True if no files match the ID, false if collision or search failure
function M.check_id_uniqueness(id, vault_path, search_fn)
  local matches = search_fn(id, vault_path)
  return #matches == 0
end

return M
