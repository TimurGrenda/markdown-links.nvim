-- Tests for utility functions (fn-1.3)
local helpers = require("tests.init")

describe("util", function()
  local util

  before_each(function()
    helpers.mock_vim()
    -- Clear cached module to get fresh state
    package.loaded["markdown-links.util"] = nil
    util = require("markdown-links.util")
  end)

  after_each(function()
    package.loaded["markdown-links.util"] = nil
    helpers.cleanup_mocks()
  end)

  describe("get_basename", function()
    it("should extract basename from full path", function()
      assert.equal("file.md", util.get_basename("/home/user/notes/file.md"))
      assert.equal("test.md", util.get_basename("/a/b/c/test.md"))
    end)

    it("should return the string if no directory separator", function()
      assert.equal("file.md", util.get_basename("file.md"))
    end)

  end)

  describe("read_frontmatter_id", function()
    local temp_dir

    before_each(function()
      temp_dir = helpers.create_temp_vault()
    end)

    after_each(function()
      helpers.cleanup_temp_vaults()
    end)

    it("extracts id from frontmatter", function()
      helpers.create_test_note(temp_dir, "note.md", "---\nid: 20260210-212427-yesu\n---\nSome content")
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.equal("20260210-212427-yesu", result)
    end)

    it("returns nil if no frontmatter", function()
      helpers.create_test_note(temp_dir, "note.md", "Some content without frontmatter")
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.is_nil(result)
    end)

    it("returns nil if frontmatter has no id field", function()
      helpers.create_test_note(temp_dir, "note.md", "---\ntitle: My Note\ntags: [a]\n---\nContent")
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.is_nil(result)
    end)

    it("returns nil if id value is invalid format", function()
      helpers.create_test_note(temp_dir, "note.md", "---\nid: not-a-valid-id\n---\nContent")
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.is_nil(result)
    end)

    it("returns nil for non-existent file", function()
      local result = util.read_frontmatter_id(temp_dir .. "/nonexistent.md")
      assert.is_nil(result)
    end)

    it("handles frontmatter with other fields", function()
      helpers.create_test_note(
        temp_dir,
        "note.md",
        "---\ntitle: My Note\nid: 20260210-212427-yesu\ntags: [a]\n---\nContent"
      )
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.equal("20260210-212427-yesu", result)
    end)

    it("returns nil if file is empty", function()
      helpers.create_test_note(temp_dir, "note.md", "")
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.is_nil(result)
    end)

    it("ignores id field outside frontmatter block", function()
      helpers.create_test_note(temp_dir, "note.md", "Some text\nid: 20260210-212427-yesu\n")
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.is_nil(result)
    end)

    it("handles id as first field in frontmatter", function()
      helpers.create_test_note(temp_dir, "note.md", "---\nid: 20260210-212427-yesu\ntitle: Test\n---\nContent")
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.equal("20260210-212427-yesu", result)
    end)

    it("handles extra whitespace around id value", function()
      helpers.create_test_note(temp_dir, "note.md", "---\nid:   20260210-212427-yesu  \n---\nContent")
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.equal("20260210-212427-yesu", result)
    end)

    it("returns id from unclosed frontmatter (robust parsing)", function()
      helpers.create_test_note(
        temp_dir,
        "note.md",
        "---\nid: 20260210-212427-yesu\ntitle: Broken\nNo closing delimiter"
      )
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      -- Should still find the id even without closing ---
      assert.equal("20260210-212427-yesu", result)
    end)

    it("returns nil from frontmatter with only opening delimiter and no id", function()
      helpers.create_test_note(temp_dir, "note.md", "---\ntitle: Note\nNo closing")
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.is_nil(result)
    end)

    it("returns nil for file with only ---", function()
      helpers.create_test_note(temp_dir, "note.md", "---")
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.is_nil(result)
    end)

    it("returns nil when id value has leading/trailing text on same line", function()
      helpers.create_test_note(
        temp_dir,
        "note.md",
        "---\nxid: 20260210-212427-yesu\n---\nContent"
      )
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      -- "xid:" should NOT match "^id:" pattern
      assert.is_nil(result)
    end)

    it("handles file with only two dashes on first line (not frontmatter)", function()
      helpers.create_test_note(temp_dir, "note.md", "--\nid: 20260210-212427-yesu\n---\n")
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.is_nil(result)
    end)

    it("finds id at bottom of large frontmatter with more than 10 fields", function()
      local fields = {}
      for i = 1, 15 do
        table.insert(fields, "field" .. i .. ": value" .. i)
      end
      table.insert(fields, "id: 20260210-212427-yesu")
      local frontmatter = "---\n" .. table.concat(fields, "\n") .. "\n---\nContent"
      helpers.create_test_note(temp_dir, "note.md", frontmatter)
      local result = util.read_frontmatter_id(temp_dir .. "/note.md")
      assert.equal("20260210-212427-yesu", result)
    end)
  end)

  describe("open_file", function()
    it("should open file with 'edit' command by default", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      util.open_file("/home/user/notes/note.md", "edit")
      assert.is_not_nil(cmd_called)
      assert.truthy(cmd_called:match("^edit "))
      assert.truthy(cmd_called:match("note%.md$"))
    end)

    it("should fall back to 'edit' for nil open_mode", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      util.open_file("/home/user/notes/note.md", nil)
      assert.is_not_nil(cmd_called)
      assert.truthy(cmd_called:match("^edit "))
    end)

    it("should fall back to 'edit' for invalid open_mode", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      util.open_file("/home/user/notes/note.md", "!rm -rf /")
      assert.is_not_nil(cmd_called)
      -- Should NOT contain the injected command
      assert.truthy(cmd_called:match("^edit "))
      assert.is_nil(cmd_called:match("rm"))
    end)

    it("should use vsplit when configured", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      util.open_file("/home/user/notes/note.md", "vsplit")
      assert.truthy(cmd_called:match("^vsplit "))
    end)

    it("should use split when configured", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      util.open_file("/home/user/notes/note.md", "split")
      assert.truthy(cmd_called:match("^split "))
    end)

    it("should use tabedit when configured", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      util.open_file("/home/user/notes/note.md", "tabedit")
      assert.truthy(cmd_called:match("^tabedit "))
    end)

    it("should call fnameescape on filepath", function()
      local escaped_path = nil
      vim.fn.fnameescape = function(s)
        escaped_path = s
        return "ESCAPED_" .. s
      end
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end

      util.open_file("/home/user/notes/My Note.md", "edit")
      assert.equal("/home/user/notes/My Note.md", escaped_path)
      assert.truthy(cmd_called:match("ESCAPED_"))
    end)

    it("should prevent command injection via open_mode", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      -- Try various injection attempts
      local injections = { "edit | !rm", "split;rm", "tabedit && echo", "!echo pwned" }
      for _, inject in ipairs(injections) do
        util.open_file("/home/user/notes/note.md", inject)
        assert.truthy(cmd_called:match("^edit "), "Injection '" .. inject .. "' should fall back to 'edit'")
      end
    end)
  end)

  describe("is_markdown_file", function()
    it("should return true when filetype is markdown", function()
      vim.bo = setmetatable({}, {
        __index = function(_, bufnr)
          return { filetype = "markdown" }
        end,
      })
      assert.is_true(util.is_markdown_file(0))
    end)

    it("should return true when filename ends with .md", function()
      vim.bo = setmetatable({}, {
        __index = function(_, bufnr)
          return { filetype = "text" }
        end,
      })
      vim.api.nvim_buf_get_name = function(bufnr)
        return "/home/user/notes/test.md"
      end
      assert.is_true(util.is_markdown_file(0))
    end)

    it("should return false for non-markdown file", function()
      vim.bo = setmetatable({}, {
        __index = function(_, bufnr)
          return { filetype = "lua" }
        end,
      })
      vim.api.nvim_buf_get_name = function(bufnr)
        return "/home/user/test.lua"
      end
      assert.is_false(util.is_markdown_file(0))
    end)

    it("should return false when no filetype and no .md extension", function()
      vim.bo = setmetatable({}, {
        __index = function(_, bufnr)
          return { filetype = "" }
        end,
      })
      vim.api.nvim_buf_get_name = function(bufnr)
        return "/home/user/test.txt"
      end
      assert.is_false(util.is_markdown_file(0))
    end)

    it("should default to buffer 0 when no bufnr given", function()
      local captured_bufnr = nil
      vim.bo = setmetatable({}, {
        __index = function(_, bufnr)
          captured_bufnr = bufnr
          return { filetype = "markdown" }
        end,
      })
      util.is_markdown_file()
      assert.equal(0, captured_bufnr)
    end)

    it("should handle errors from vim.bo gracefully", function()
      vim.bo = setmetatable({}, {
        __index = function()
          error("Invalid buffer")
        end,
      })
      vim.api.nvim_buf_get_name = function()
        return "/test.md"
      end
      -- Should not error, should fall back to extension check
      assert.is_true(util.is_markdown_file(999))
    end)

    it("should handle errors from nvim_buf_get_name gracefully", function()
      vim.bo = setmetatable({}, {
        __index = function()
          error("Invalid buffer")
        end,
      })
      vim.api.nvim_buf_get_name = function()
        error("Invalid buffer")
      end
      -- Both calls error, should return false
      assert.is_false(util.is_markdown_file(999))
    end)

    it("should accept specific buffer numbers", function()
      local captured_bufnr = nil
      vim.bo = setmetatable({}, {
        __index = function(_, bufnr)
          captured_bufnr = bufnr
          return { filetype = "markdown" }
        end,
      })
      util.is_markdown_file(42)
      assert.equal(42, captured_bufnr)
    end)
  end)
end)
