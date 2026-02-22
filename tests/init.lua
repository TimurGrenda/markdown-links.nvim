-- Test initialization and helpers for markdown-links tests
-- This module provides mocking utilities and test helpers

local M = {}

-- Store original globals to restore later
local _original_globals = {}

-- Mock vim global with essential functions
function M.mock_vim()
  -- Save original vim if it exists
  if _G.vim and not _original_globals.vim then
    _original_globals.vim = _G.vim
  end

  -- Create comprehensive vim mock
  local vim_mock = {
    -- API functions
    api = {
      nvim_get_current_line = function()
        return ""
      end,
      nvim_win_get_cursor = function()
        return { 1, 0 }
      end,
      nvim_buf_get_name = function(_)
        return ""
      end,
      nvim_buf_get_lines = function()
        return {}
      end,
      nvim_buf_set_lines = function() end,
      nvim_buf_get_text = function()
        return {}
      end,
      nvim_buf_set_text = function()
        return true
      end,
      nvim_create_user_command = function() end,
      nvim_create_augroup = function(name, _)
        return name
      end,
      nvim_create_autocmd = function(_, _) end,
    },

    -- Built-in functions
    fn = {
      isdirectory = function(path)
        return 1
      end,
      executable = function(cmd)
        return 1
      end,
      systemlist = function(cmd)
        return {}
      end,
      expand = function(expr)
        if expr == "~" then
          return os.getenv("HOME") or "/home/user"
        end
        return expr
      end,
      mkdir = function()
        return 1
      end,
      writefile = function()
        return 0
      end,
      filereadable = function()
        return 0 -- Default: file does not exist (safe for new_file tests)
      end,
    },

    -- Buffer options (modern API)
    bo = setmetatable({}, {
      __index = function(_, bufnr)
        return { filetype = "" }
      end,
    }),

    -- Vim commands
    cmd = function() end,

    -- Notifications
    notify = function(msg, level, opts)
      -- Store last notification for testing
      _G._last_notification = { msg = msg, level = level, opts = opts }
    end,

    -- Utility functions
    tbl_deep_extend = function(mode, ...)
      local result = {}
      for _, t in ipairs({ ... }) do
        for k, v in pairs(t) do
          if type(v) == "table" and type(result[k]) == "table" then
            result[k] = vim.tbl_deep_extend(mode, result[k], v)
          else
            result[k] = v
          end
        end
      end
      return result
    end,

    tbl_contains = function(tbl, value)
      for _, v in pairs(tbl) do
        if v == value then
          return true
        end
      end
      return false
    end,

    tbl_extend = function(mode, ...)
      local result = {}
      for _, t in ipairs({ ... }) do
        for k, v in pairs(t) do
          result[k] = v
        end
      end
      return result
    end,

    list_extend = function(dst, src, start, finish)
      start = start or 1
      finish = finish or #src
      for i = start, finish do
        table.insert(dst, src[i])
      end
      return dst
    end,

    -- Path utilities
    fs = {
      normalize = function(path, opts)
        -- Simple normalization: collapse // and resolve . but don't expand ~
        path = path:gsub("//+", "/")
        return path
      end,
      dirname = function(path)
        if not path or path == "" then
          return nil
        end
        return path:match("^(.+)/[^/]+$")
      end,
    },

    -- String utilities
    startswith = function(s, prefix)
      return s:sub(1, #prefix) == prefix
    end,

    -- Keymap functions
    keymap = {
      set = function(mode, lhs, rhs, opts) end,
    },

    -- Global variables
    g = {},
    v = {
      shell_error = 0,
    },

    -- UI functions
    ui = {
      input = function(opts, callback)
        -- Default implementation - can be overridden in tests
        if callback then
          callback(nil)
        end
      end,
      select = function(items, opts, callback)
        -- Default implementation - can be overridden in tests
        if callback then
          callback(nil, nil)
        end
      end,
    },
  }

  -- Set the global vim
  _G.vim = vim_mock

  return vim_mock
end

-- Mock Telescope picker
function M.mock_telescope()
  local telescope_mock = {
    pickers = {
      new = function(opts, picker_opts)
        return {
          find = function()
            -- Simulate picker opening
            if picker_opts.attach_mappings then
              -- Simulate user selecting first item
              local bufnr = 1
              local entry = picker_opts.finder.results and picker_opts.finder.results[1]
              if entry then
                picker_opts.attach_mappings(bufnr, {
                  select = function()
                    return true
                  end,
                })
              end
            end
          end,
        }
      end,
    },
    finders = {
      new_table = function(opts)
        return {
          results = opts.results or {},
          entry_maker = opts.entry_maker,
        }
      end,
    },
    conf = {
      generic_opts = function()
        return {}
      end,
    },
    themes = {
      get_dropdown = function()
        return {}
      end,
    },
  }

  -- Mock the require for telescope
  package.loaded["telescope"] = telescope_mock
  package.loaded["telescope.pickers"] = telescope_mock.pickers
  package.loaded["telescope.finders"] = telescope_mock.finders
  package.loaded["telescope.config"] = telescope_mock.conf
  package.loaded["telescope.themes"] = telescope_mock.themes

  return telescope_mock
end

-- Create a temporary vault directory for tests
function M.create_temp_vault()
  local temp_dir = os.tmpname() .. "_vault"
  os.remove(temp_dir) -- Remove the temp file created by tmpname

  -- Create directory using system command
  local ok = os.execute("mkdir -p " .. temp_dir)
  if not ok then
    error("Failed to create temp vault directory: " .. temp_dir)
  end

  -- Store for cleanup
  _G._temp_vaults = _G._temp_vaults or {}
  table.insert(_G._temp_vaults, temp_dir)

  return temp_dir
end

-- Cleanup temporary vaults
function M.cleanup_temp_vaults()
  if _G._temp_vaults then
    for _, dir in ipairs(_G._temp_vaults) do
      os.execute("rm -rf " .. dir)
    end
    _G._temp_vaults = {}
  end
end

-- Create a test note file in a vault
function M.create_test_note(vault_path, filename, content)
  content = content or ""
  local filepath = vault_path .. "/" .. filename
  local file = io.open(filepath, "w")
  if file then
    file:write(content)
    file:close()
    return filepath
  end
  return nil
end

-- Assert ID format matches expected pattern
function M.assert_id_format(id)
  if type(id) ~= "string" then
    error("Expected string, got " .. type(id), 2)
  end

  if #id ~= 20 then
    error(string.format("ID should be 20 characters, got %d", #id), 2)
  end

  -- Pattern: YYYYMMDD-HHMMSS-XXXX
  local pattern = "^%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-[0-9a-z][0-9a-z][0-9a-z][0-9a-z]$"
  if not id:match(pattern) then
    error(string.format("ID '%s' should match pattern YYYYMMDD-HHMMSS-XXXX", id), 2)
  end
end

-- Cleanup all mocks
function M.cleanup_mocks()
  -- Restore original vim
  if _original_globals.vim then
    _G.vim = _original_globals.vim
  else
    _G.vim = nil
  end

  -- Clear package.loaded for telescope
  package.loaded["telescope"] = nil
  package.loaded["telescope.pickers"] = nil
  package.loaded["telescope.finders"] = nil
  package.loaded["telescope.config"] = nil
  package.loaded["telescope.themes"] = nil

  -- Cleanup temp vaults
  M.cleanup_temp_vaults()

  -- Clear stored globals
  _original_globals = {}
end

-- Helper to capture notifications
function M.get_last_notification()
  return _G._last_notification
end

-- Helper to set mock vim.ui.input response
function M.set_ui_input_response(response)
  _G.vim.ui.input = function(opts, callback)
    if callback then
      callback(response)
    end
  end
end

-- Helper to set mock vim.ui.select response (item and index)
function M.set_ui_select_response(item, index)
  _G.vim.ui.select = function(items, opts, callback)
    if callback then
      callback(item, index)
    end
  end
end

-- Helper to create a minimal valid config for testing
function M.create_test_config(overrides)
  overrides = overrides or {}
  local base_config = {
    vault_path = { "/home/user/notes" },
    open_mode = "edit",
    picker_display = "title_with_path",
    exclude_dirs = { ".git", ".obsidian" },
  }
  return vim.tbl_deep_extend("force", base_config, overrides)
end

return M
