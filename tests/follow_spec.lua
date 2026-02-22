-- Tests for link following functionality (fn-1.5)
local helpers = require("tests.init")

describe("follow", function()
  local follow
  local search_module

  before_each(function()
    helpers.mock_vim()
    vim.log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } }
    -- Clear cached module to get fresh state
    package.loaded["markdown-links.follow"] = nil
    follow = require("markdown-links.follow")

    -- Create a mock search module
    -- Delegates search_files_by_frontmatter_id to real search module (uses vim.fn.systemlist mocks)
    local real_search = require("markdown-links.search")
    search_module = {
      detect_vault = function(buf_path, vault_paths)
        return "/home/user/notes"
      end,
      search_vault = function(vault, exclude_dirs)
        return {}
      end,
      search_files_by_frontmatter_id = real_search.search_files_by_frontmatter_id,
    }
  end)

  after_each(function()
    package.loaded["markdown-links.follow"] = nil
    helpers.cleanup_mocks()
  end)

  describe("parse_links", function()
    it("should return empty table for line with no links", function()
      local result = follow.parse_links("This is a plain line with no links.")
      assert.same({}, result)
    end)

    it("should parse a single markdown link", function()
      local result = follow.parse_links("Here is a [link](file.md) in text.")
      assert.equal(1, #result)
      assert.equal("file.md", result[1].url)
      assert.equal(11, result[1].start_col)
      assert.equal(25, result[1].end_col)
    end)

    it("should parse multiple markdown links", function()
      local result = follow.parse_links("[First](a.md) and [Second](b.md)")
      assert.equal(2, #result)
      assert.equal("a.md", result[1].url)
      assert.equal("b.md", result[2].url)
    end)

    it("should skip image links", function()
      local result = follow.parse_links("![alt](image.png) and [link](file.md)")
      assert.equal(1, #result)
      assert.equal("file.md", result[1].url)
    end)

    it("should skip multiple image links", function()
      local result = follow.parse_links("![img1](a.png) [link](b.md) ![img2](c.png)")
      assert.equal(1, #result)
      assert.equal("b.md", result[1].url)
    end)

    it("should handle links with special characters in text", function()
      local result = follow.parse_links("[Link with [brackets]](file.md)")
      assert.equal(1, #result)
      assert.equal("file.md", result[1].url)
    end)

    it("should handle links with simple URLs", function()
      local result = follow.parse_links("[Link](file.md) text")
      assert.equal(1, #result)
      assert.equal("file.md", result[1].url)
    end)

    it("should handle links with paths", function()
      local result = follow.parse_links("[Note](../../notes/file-20260207-143055-a3f7.md)")
      assert.equal(1, #result)
      assert.equal("../../notes/file-20260207-143055-a3f7.md", result[1].url)
    end)

    it("should handle links with URL fragments", function()
      local result = follow.parse_links("[Note](file.md#section)")
      assert.equal(1, #result)
      assert.equal("file.md#section", result[1].url)
    end)

    it("should parse links at start of line", function()
      local result = follow.parse_links("[Start](a.md) middle")
      assert.equal(1, #result)
      assert.equal(1, result[1].start_col)
    end)

    it("should parse links at end of line", function()
      local result = follow.parse_links("middle [End](z.md)")
      assert.equal(1, #result)
      assert.equal("z.md", result[1].url)
    end)

    it("should handle empty link text", function()
      local result = follow.parse_links("[](file.md)")
      assert.equal(1, #result)
      assert.equal("file.md", result[1].url)
    end)

    it("should not parse unclosed brackets", function()
      local result = follow.parse_links("[text](file.md")
      assert.equal(0, #result)
    end)

    it("should not parse unclosed parentheses", function()
      local result = follow.parse_links("[text](file.md")
      assert.equal(0, #result)
    end)

    it("should handle URL-encoded characters in URL", function()
      local result = follow.parse_links("[Link](file%20name.md)")
      assert.equal(1, #result)
      assert.equal("file%20name.md", result[1].url)
    end)

    it("should handle nested brackets in link text", function()
      local result = follow.parse_links("[Link with [nested]](file.md)")
      assert.equal(1, #result)
      assert.equal("file.md", result[1].url)
    end)

    it("should parse multiple links correctly", function()
      local result = follow.parse_links("[A](a.md) [B](b.md) [C](c.md)")
      assert.equal(3, #result)
      assert.equal("a.md", result[1].url)
      assert.equal("b.md", result[2].url)
      assert.equal("c.md", result[3].url)
    end)
  end)

  describe("find_link_at_cursor", function()
    it("should return nil for empty links table", function()
      local result = follow.find_link_at_cursor({}, 5)
      assert.is_nil(result)
    end)

    it("should return first link when cursor is not on any link", function()
      local links = {
        { url = "a.md", start_col = 10, end_col = 20 },
        { url = "b.md", start_col = 30, end_col = 40 },
      }
      local result = follow.find_link_at_cursor(links, 5)
      assert.equal("a.md", result.url)
    end)

    it("should find link at cursor position (start)", function()
      local links = {
        { url = "a.md", start_col = 1, end_col = 10 },
        { url = "b.md", start_col = 12, end_col = 21 },
      }
      local result = follow.find_link_at_cursor(links, 1)
      assert.equal("a.md", result.url)
    end)

    it("should find link at cursor position (middle)", function()
      local links = {
        { url = "a.md", start_col = 1, end_col = 10 },
        { url = "b.md", start_col = 12, end_col = 21 },
      }
      local result = follow.find_link_at_cursor(links, 15)
      assert.equal("b.md", result.url)
    end)

    it("should find link at cursor position (end)", function()
      local links = {
        { url = "a.md", start_col = 1, end_col = 10 },
        { url = "b.md", start_col = 12, end_col = 21 },
      }
      local result = follow.find_link_at_cursor(links, 21)
      assert.equal("b.md", result.url)
    end)

  end)

  describe("strip_fragment", function()
    it("should return URL unchanged when no fragment", function()
      local result = follow.strip_fragment("file.md")
      assert.equal("file.md", result)
    end)

    it("should strip fragment from URL", function()
      local result = follow.strip_fragment("file.md#heading")
      assert.equal("file.md", result)
    end)

    it("should strip fragment with hyphen", function()
      local result = follow.strip_fragment("file.md#my-heading")
      assert.equal("file.md", result)
    end)

    it("should strip fragment with number", function()
      local result = follow.strip_fragment("file.md#section-1")
      assert.equal("file.md", result)
    end)

    it("should handle empty fragment", function()
      local result = follow.strip_fragment("file.md#")
      assert.equal("file.md", result)
    end)

    it("should only strip first fragment", function()
      local result = follow.strip_fragment("file.md#section#subsection")
      assert.equal("file.md", result)
    end)

    it("should handle URL with only fragment", function()
      local result = follow.strip_fragment("#heading")
      assert.equal("", result)
    end)
  end)

  describe("extract_id_from_url", function()
    it("should return nil for URL without ID", function()
      local result = follow.extract_id_from_url("file.md")
      assert.is_nil(result)
    end)

    it("should extract bare ID from URL", function()
      local result = follow.extract_id_from_url("20260207-143055-a3f7")
      assert.equal("20260207-143055-a3f7", result)
    end)

    it("should extract ID from old-format filename with .md", function()
      local result = follow.extract_id_from_url("note-20260207-143055-a3f7.md")
      assert.equal("20260207-143055-a3f7", result)
    end)

    it("should extract ID from URL with path", function()
      local result = follow.extract_id_from_url("/home/user/notes/note-20260207-143055-a3f7.md")
      assert.equal("20260207-143055-a3f7", result)
    end)

    it("should extract ID from URL with relative path", function()
      local result = follow.extract_id_from_url("../notes/note-20260207-143055-a3f7.md")
      assert.equal("20260207-143055-a3f7", result)
    end)

    it("should extract ID from URL with fragment", function()
      local result = follow.extract_id_from_url("20260207-143055-a3f7#section")
      assert.equal("20260207-143055-a3f7", result)
    end)

    it("should return nil for partial ID", function()
      local result = follow.extract_id_from_url("note-20260207-143055.md")
      assert.is_nil(result)
    end)

    it("should return nil for ID with uppercase letters", function()
      local result = follow.extract_id_from_url("note-20260207-143055-A3F7.md")
      assert.is_nil(result)
    end)
  end)

  describe("follow_link", function()
    local config

    before_each(function()
      config = helpers.create_test_config()
    end)

    it("should show warning when no links on line", function()
      vim.api.nvim_get_current_line = function()
        return "This is a line with no links."
      end

      local notified = false
      vim.notify = function(msg, level)
        notified = true
        assert.matches("No markdown link found", msg)
        assert.equal(vim.log.levels.WARN, level)
      end

      follow.follow_link(config, search_module)
      assert.is_true(notified)
    end)

    it("should show warning when link has no ID pattern", function()
      vim.api.nvim_get_current_line = function()
        return "Here is a [link](https://example.com) to external."
      end

      local notified = false
      local notify_msg = nil
      vim.notify = function(msg, level)
        notified = true
        notify_msg = msg
        assert.equal(vim.log.levels.WARN, level)
      end

      follow.follow_link(config, search_module)
      assert.is_true(notified)
      assert.truthy(notify_msg:match("Not a note ID link"))
      assert.truthy(notify_msg:match("https://example.com"))
    end)

    it("should show warning when link has regular filename without ID", function()
      vim.api.nvim_get_current_line = function()
        return "Here is a [link](regular-file.md) without ID."
      end

      local notified = false
      vim.notify = function(msg, level)
        notified = true
        assert.matches("Not a note ID link", msg)
        assert.equal(vim.log.levels.WARN, level)
      end

      follow.follow_link(config, search_module)
      assert.is_true(notified)
    end)

    it("should show error when buffer is not in vault", function()
      vim.api.nvim_get_current_line = function()
        return "Here is a [link](20260207-143055-a3f7)."
      end
      vim.api.nvim_buf_get_name = function()
        return "/outside/vault/file.md"
      end

      search_module.detect_vault = function()
        return nil
      end

      local notified = false
      vim.notify = function(msg, level)
        notified = true
        assert.matches("not in a configured vault", msg)
        assert.equal(vim.log.levels.ERROR, level)
      end

      follow.follow_link(config, search_module)
      assert.is_true(notified)
    end)

    it("should show warning when no files match ID", function()
      vim.api.nvim_get_current_line = function()
        return "Here is a [link](20260207-143055-a3f7)."
      end
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/file.md"
      end

      search_module.detect_vault = function()
        return "/home/user/notes"
      end

      vim.fn.executable = function(cmd)
        if cmd == "rg" then
          return 1
        end
        return 0
      end
      vim.fn.systemlist = function()
        return {}
      end
      vim.v.shell_error = 0

      local notified = false
      vim.notify = function(msg, level)
        notified = true
        assert.matches("Note not found for ID", msg)
        assert.equal(vim.log.levels.WARN, level)
      end

      follow.follow_link(config, search_module)
      assert.is_true(notified)
    end)

    it("should open file with :edit when 1 match found", function()
      vim.api.nvim_get_current_line = function()
        return "Here is a [link](20260207-143055-a3f7)."
      end
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/file.md"
      end

      search_module.detect_vault = function()
        return "/home/user/notes"
      end

      vim.fn.executable = function(cmd)
        if cmd == "rg" then
          return 1
        end
        return 0
      end
      vim.fn.systemlist = function(cmd)
        if cmd[1] == "rg" then
          return { "/home/user/notes/My Note.md" }
        end
        return {}
      end
      vim.v.shell_error = 0

      local edit_called = false
      local edit_file = nil
      vim.cmd = function(cmd)
        if cmd:match("^edit ") then
          edit_called = true
          edit_file = cmd:sub(6)
        end
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      follow.follow_link(config, search_module)
      assert.is_true(edit_called)
      assert.equal("/home/user/notes/My Note.md", edit_file)
    end)

    it("should use configured open_mode when opening file", function()
      config.open_mode = "vsplit"

      vim.api.nvim_get_current_line = function()
        return "Here is a [link](20260207-143055-a3f7)."
      end
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/file.md"
      end

      search_module.detect_vault = function()
        return "/home/user/notes"
      end

      vim.fn.executable = function(cmd)
        if cmd == "rg" then
          return 1
        end
        return 0
      end
      vim.fn.systemlist = function(cmd)
        if cmd[1] == "rg" then
          return { "/home/user/notes/My Note.md" }
        end
        return {}
      end
      vim.v.shell_error = 0

      local vsplit_called = false
      vim.cmd = function(cmd)
        if cmd:match("^vsplit ") then
          vsplit_called = true
        end
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      follow.follow_link(config, search_module)
      assert.is_true(vsplit_called)
    end)

    it("should show picker when multiple matches found", function()
      vim.api.nvim_get_current_line = function()
        return "Here is a [link](20260207-143055-a3f7)."
      end
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/file.md"
      end

      search_module.detect_vault = function()
        return "/home/user/notes"
      end

      vim.fn.executable = function(cmd)
        if cmd == "rg" then
          return 1
        end
        return 0
      end
      vim.fn.systemlist = function(cmd)
        if cmd[1] == "rg" then
          return {
            "/home/user/notes/My Note.md",
            "/home/user/backup/My Note.md",
          }
        end
        return {}
      end
      vim.v.shell_error = 0

      local picker_shown = false
      vim.ui.select = function(items, opts, callback)
        picker_shown = true
        assert.equal(2, #items)
        assert.matches("Multiple notes found", opts.prompt)
        if callback then
          callback(items[1], 1)
        end
      end

      vim.cmd = function(cmd)
        if cmd:match("^edit ") then
          -- Success
        end
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      follow.follow_link(config, search_module)
      assert.is_true(picker_shown)
    end)

    it("should strip fragment before extracting ID", function()
      vim.api.nvim_get_current_line = function()
        return "Here is a [link](20260207-143055-a3f7#section)."
      end
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/file.md"
      end

      search_module.detect_vault = function()
        return "/home/user/notes"
      end

      vim.fn.executable = function(cmd)
        if cmd == "rg" then
          return 1
        end
        return 0
      end
      vim.fn.systemlist = function(cmd)
        if cmd[1] == "rg" then
          return { "/home/user/notes/My Note.md" }
        end
        return {}
      end
      vim.v.shell_error = 0

      local edit_called = false
      vim.cmd = function(cmd)
        if cmd:match("^edit ") then
          edit_called = true
        end
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      follow.follow_link(config, search_module)
      assert.is_true(edit_called)
    end)

    it("should skip image links and use next link", function()
      vim.api.nvim_get_current_line = function()
        return "![alt](image.png) [link](20260207-143055-a3f7)"
      end
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/file.md"
      end

      search_module.detect_vault = function()
        return "/home/user/notes"
      end

      vim.fn.executable = function(cmd)
        if cmd == "rg" then
          return 1
        end
        return 0
      end
      vim.fn.systemlist = function(cmd)
        if cmd[1] == "rg" then
          return { "/home/user/notes/My Note.md" }
        end
        return {}
      end
      vim.v.shell_error = 0

      local edit_called = false
      vim.cmd = function(cmd)
        if cmd:match("^edit ") then
          edit_called = true
        end
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      follow.follow_link(config, search_module)
      assert.is_true(edit_called)
    end)

    it("should find link at cursor position", function()
      vim.api.nvim_get_current_line = function()
        return "[First](20260207-111111-aaaa) [Second](20260207-143055-a3f7)"
      end
      vim.api.nvim_win_get_cursor = function()
        return { 1, 32 } -- Cursor on second link
      end
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/file.md"
      end

      search_module.detect_vault = function()
        return "/home/user/notes"
      end

      vim.fn.executable = function(cmd)
        if cmd == "rg" then
          return 1
        end
        return 0
      end
      vim.fn.systemlist = function(cmd)
        if cmd[1] == "rg" then
          return { "/home/user/notes/Second Note.md" }
        end
        return {}
      end
      vim.v.shell_error = 0

      local edit_called = false
      local edit_file = nil
      vim.cmd = function(cmd)
        if cmd:match("^edit ") then
          edit_called = true
          edit_file = cmd:sub(6)
        end
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      follow.follow_link(config, search_module)
      assert.is_true(edit_called)
      assert.equal("/home/user/notes/Second Note.md", edit_file)
    end)

    it("should use fallback to first link when cursor not on link", function()
      vim.api.nvim_get_current_line = function()
        return "text [First](20260207-111111-aaaa) [Second](20260207-143055-a3f7)"
      end
      vim.api.nvim_win_get_cursor = function()
        return { 1, 2 } -- Cursor on "text", not on either link
      end
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/file.md"
      end

      search_module.detect_vault = function()
        return "/home/user/notes"
      end

      vim.fn.executable = function(cmd)
        if cmd == "rg" then
          return 1
        end
        return 0
      end
      vim.fn.systemlist = function(cmd)
        if cmd[1] == "rg" then
          return { "/home/user/notes/First Note.md" }
        end
        return {}
      end
      vim.v.shell_error = 0

      local edit_called = false
      local edit_file = nil
      vim.cmd = function(cmd)
        if cmd:match("^edit ") then
          edit_called = true
          edit_file = cmd:sub(6)
        end
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      follow.follow_link(config, search_module)
      assert.is_true(edit_called)
      assert.equal("/home/user/notes/First Note.md", edit_file)
    end)

    it("should not open file when user cancels picker", function()
      vim.api.nvim_get_current_line = function()
        return "Here is a [link](20260207-143055-a3f7)."
      end
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/file.md"
      end

      search_module.detect_vault = function()
        return "/home/user/notes"
      end

      vim.fn.executable = function(cmd)
        if cmd == "rg" then
          return 1
        end
        return 0
      end
      vim.fn.systemlist = function(cmd)
        if cmd[1] == "rg" then
          return {
            "/home/user/notes/My Note.md",
            "/home/user/backup/My Note.md",
          }
        end
        return {}
      end
      vim.v.shell_error = 0

      vim.ui.select = function(items, opts, callback)
        if callback then
          callback(nil, nil)
        end
      end

      local edit_called = false
      vim.cmd = function(cmd)
        if cmd:match("^edit ") then
          edit_called = true
        end
      end

      follow.follow_link(config, search_module)
      assert.is_false(edit_called)
    end)

    it("should find note via frontmatter ID", function()
      vim.api.nvim_get_current_line = function()
        return "Here is a [link](20260210-212427-yesu)."
      end
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/file.md"
      end

      search_module.detect_vault = function()
        return "/home/user/notes"
      end

      vim.fn.executable = function(cmd)
        if cmd == "rg" then
          return 1
        end
        return 0
      end
      vim.fn.systemlist = function(cmd)
        if cmd[1] == "rg" then
          return { "/home/user/notes/My Testing Note.md" }
        end
        return {}
      end
      vim.v.shell_error = 0

      local edit_called = false
      local edit_file = nil
      vim.cmd = function(cmd)
        if cmd:match("^edit ") then
          edit_called = true
          edit_file = cmd:sub(6)
        end
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      follow.follow_link(config, search_module)
      assert.is_true(edit_called)
      assert.equal("/home/user/notes/My Testing Note.md", edit_file)
    end)

    it("should follow link with bare ID URL", function()
      vim.api.nvim_get_current_line = function()
        return "[Testing](20260210-212427-yesu)"
      end
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/file.md"
      end

      search_module.detect_vault = function()
        return "/home/user/notes"
      end

      vim.fn.executable = function(cmd)
        if cmd == "rg" then
          return 1
        end
        return 0
      end
      vim.fn.systemlist = function(cmd)
        if cmd[1] == "rg" then
          return { "/home/user/notes/Testing.md" }
        end
        return {}
      end
      vim.v.shell_error = 0

      local edit_file = nil
      vim.cmd = function(cmd)
        if cmd:match("^edit ") then
          edit_file = cmd:sub(6)
        end
      end
      vim.fn.fnameescape = function(s)
        return s
      end

      follow.follow_link(config, search_module)
      assert.equal("/home/user/notes/Testing.md", edit_file)
    end)

  end)
end)
