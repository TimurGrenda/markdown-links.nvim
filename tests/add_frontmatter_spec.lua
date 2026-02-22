-- Tests for add_frontmatter command
---@diagnostic disable: need-check-nil, undefined-field
local helpers = require("tests.init")

describe("add_frontmatter", function()
  local ml
  local notifications
  local set_lines_calls

  before_each(function()
    helpers.mock_vim()
    vim.log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } }
    vim.inspect = function(v)
      return tostring(v)
    end

    -- Capture notifications
    notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    -- Capture nvim_buf_set_lines calls
    set_lines_calls = {}
    vim.api.nvim_buf_set_lines = function(buf, start, stop, strict, lines)
      table.insert(set_lines_calls, { buf = buf, start = start, stop = stop, lines = lines })
    end

    -- Default: buffer is a markdown file inside vault
    vim.bo = setmetatable({}, {
      __index = function()
        return { filetype = "markdown" }
      end,
    })
    vim.api.nvim_buf_get_name = function()
      return "/home/user/notes/existing.md"
    end

    -- Clear all plugin modules
    package.loaded["markdown-links"] = nil
    package.loaded["markdown-links.config"] = nil
    package.loaded["markdown-links.init"] = nil
    package.loaded["markdown-links.search"] = nil
    package.loaded["markdown-links.id"] = nil
    package.loaded["markdown-links.new_file"] = nil
    package.loaded["markdown-links.util"] = nil
    package.loaded["markdown-links.follow"] = nil
    package.loaded["markdown-links.insert"] = nil

    -- Deterministic ID generation
    package.loaded["markdown-links.id"] = nil
    local id_mod = require("markdown-links.id")
    local counter = 0
    id_mod.generate_id = function()
      counter = counter + 1
      return string.format("20260214-120000-%04d", counter)
    end

    -- Mock search module for vault detection
    package.loaded["markdown-links.search"] = {
      detect_vault = function(path, vault_paths)
        for _, vp in ipairs(vault_paths) do
          if vim.startswith(path, vp .. "/") or path == vp then
            return vp
          end
        end
        return nil
      end,
      search_vault = function()
        return {}
      end,
      search_files_by_frontmatter_id = function()
        return {} -- No collisions
      end,
    }

    -- Load and set up the plugin
    local vault_dir = "/home/user/notes"
    vim.fn.isdirectory = function()
      return 1
    end
    vim.api.nvim_create_augroup = function(name)
      return name
    end
    vim.api.nvim_create_autocmd = function() end

    ml = require("markdown-links")
    ml.setup({ vault_path = vault_dir })
  end)

  after_each(function()
    package.loaded["markdown-links"] = nil
    package.loaded["markdown-links.config"] = nil
    package.loaded["markdown-links.init"] = nil
    package.loaded["markdown-links.search"] = nil
    package.loaded["markdown-links.id"] = nil
    package.loaded["markdown-links.new_file"] = nil
    package.loaded["markdown-links.util"] = nil
    package.loaded["markdown-links.follow"] = nil
    package.loaded["markdown-links.insert"] = nil
    helpers.cleanup_mocks()
  end)

  describe("no frontmatter", function()
    it("should prepend full frontmatter block to buffer with no frontmatter", function()
      vim.api.nvim_buf_get_lines = function()
        return { "# My Note", "", "Some content here." }
      end

      ml.add_frontmatter()

      assert.equal(1, #set_lines_calls)
      local call = set_lines_calls[1]
      assert.equal(0, call.buf)
      assert.equal(0, call.start)
      assert.equal(0, call.stop)
      assert.equal("---", call.lines[1])
      assert.truthy(call.lines[2]:match("^id: %d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-[0-9a-z]+$"))
      assert.equal("---", call.lines[3])
      assert.equal("", call.lines[4])
    end)

    it("should prepend frontmatter to empty buffer", function()
      vim.api.nvim_buf_get_lines = function()
        return { "" }
      end

      ml.add_frontmatter()

      assert.equal(1, #set_lines_calls)
      assert.equal("---", set_lines_calls[1].lines[1])
    end)

    it("should notify with the generated ID", function()
      vim.api.nvim_buf_get_lines = function()
        return { "# Note" }
      end

      ml.add_frontmatter()

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("Added frontmatter with ID"))
      assert.equal(vim.log.levels.INFO, notifications[1].level)
    end)
  end)

  describe("existing frontmatter without id", function()
    it("should insert id line into existing frontmatter", function()
      vim.api.nvim_buf_get_lines = function()
        return { "---", "title: My Note", "tags: [test]", "---", "", "Content." }
      end

      ml.add_frontmatter()

      assert.equal(1, #set_lines_calls)
      local call = set_lines_calls[1]
      -- Should insert at line 1 (after opening ---)
      assert.equal(1, call.start)
      assert.equal(1, call.stop)
      assert.equal(1, #call.lines)
      assert.truthy(call.lines[1]:match("^id: %d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-[0-9a-z]+$"))
    end)

    it("should notify about adding id to existing frontmatter", function()
      vim.api.nvim_buf_get_lines = function()
        return { "---", "title: My Note", "---", "", "Content." }
      end

      ml.add_frontmatter()

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("Added ID .+ to existing frontmatter"))
    end)

    it("should handle frontmatter with only opening and closing delimiters", function()
      vim.api.nvim_buf_get_lines = function()
        return { "---", "---", "", "Content." }
      end

      ml.add_frontmatter()

      assert.equal(1, #set_lines_calls)
      -- Should insert id between the two ---
      assert.equal(1, set_lines_calls[1].start)
      assert.equal(1, set_lines_calls[1].stop)
    end)
  end)

  describe("existing frontmatter with valid id", function()
    it("should skip and notify if frontmatter already has a valid id", function()
      vim.api.nvim_buf_get_lines = function()
        return { "---", "id: 20260101-120000-abcd", "title: Existing", "---", "", "Content." }
      end

      ml.add_frontmatter()

      -- Should NOT modify buffer
      assert.equal(0, #set_lines_calls)
      -- Should notify
      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("Already has frontmatter ID"))
      assert.equal(vim.log.levels.INFO, notifications[1].level)
    end)

    it("should detect id field even if not first in frontmatter", function()
      vim.api.nvim_buf_get_lines = function()
        return { "---", "title: Note", "tags: []", "id: 20260101-120000-wxyz", "---", "", "Content." }
      end

      ml.add_frontmatter()

      assert.equal(0, #set_lines_calls)
      assert.truthy(notifications[1].msg:match("Already has frontmatter ID"))
    end)
  end)

  describe("edge cases", function()
    it("should error if setup not called", function()
      -- Create a fresh instance without setup
      package.loaded["markdown-links"] = nil
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil
      local fresh_ml = require("markdown-links")

      fresh_ml.add_frontmatter()

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("setup%(%) must be called"))
    end)

    it("should warn if buffer is not a markdown file", function()
      vim.bo = setmetatable({}, {
        __index = function()
          return { filetype = "lua" }
        end,
      })
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/script.lua"
      end

      ml.add_frontmatter()

      assert.equal(0, #set_lines_calls)
      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("not a markdown file"))
    end)

    it("should error if buffer has no file name", function()
      vim.api.nvim_buf_get_name = function()
        return ""
      end

      ml.add_frontmatter()

      assert.equal(0, #set_lines_calls)
      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("no file name"))
    end)

    it("should warn if buffer is outside all vaults", function()
      vim.api.nvim_buf_get_name = function()
        return "/some/other/path/note.md"
      end

      ml.add_frontmatter()

      assert.equal(0, #set_lines_calls)
      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("outside all configured vaults"))
    end)

    it("should treat unclosed frontmatter as no frontmatter", function()
      vim.api.nvim_buf_get_lines = function()
        return { "---", "title: Broken", "No closing delimiter", "Content." }
      end

      ml.add_frontmatter()

      -- Should prepend full frontmatter block (not insert into broken block)
      assert.equal(1, #set_lines_calls)
      assert.equal(0, set_lines_calls[1].start)
      assert.equal(0, set_lines_calls[1].stop)
      assert.equal("---", set_lines_calls[1].lines[1])
    end)

    it("should handle frontmatter with invalid id format as no id", function()
      vim.api.nvim_buf_get_lines = function()
        return { "---", "id: not-a-valid-id", "---", "", "Content." }
      end

      ml.add_frontmatter()

      -- Should insert a valid id into the existing frontmatter
      assert.equal(1, #set_lines_calls)
      assert.truthy(set_lines_calls[1].lines[1]:match("^id: %d%d%d%d%d%d%d%d"))
    end)

    it("should handle ID generation failure", function()
      -- Make all IDs collide
      local search_mod = require("markdown-links.search")
      search_mod.search_files_by_frontmatter_id = function()
        return { "collision.md" }
      end

      vim.api.nvim_buf_get_lines = function()
        return { "# Note" }
      end

      ml.add_frontmatter()

      assert.equal(0, #set_lines_calls)
      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("Failed to generate unique ID"))
    end)
  end)
end)
