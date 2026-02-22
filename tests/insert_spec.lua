--- Tests for markdown-links.insert module
local helpers = require("tests.init")

describe("insert", function()
  local insert
  local mock_search
  local notifications

  before_each(function()
    helpers.mock_vim()
    vim.log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } }

    -- Capture notifications
    notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    -- vim.fn extras needed by insert
    vim.fn.getpos = function()
      return { 0, 10, 5, 0 }
    end
    vim.fn.visualmode = function()
      return "v"
    end

    -- Default to normal mode
    vim.api.nvim_get_mode = function()
      return { mode = "n" }
    end
    vim.api.nvim_get_current_buf = function()
      return 1
    end
    vim.api.nvim_win_get_cursor = function()
      return { 10, 5 }
    end
    vim.api.nvim_buf_get_name = function()
      return "/home/user/notes/test.md"
    end
    vim.api.nvim_buf_set_text = function()
      return true
    end
    vim.api.nvim_win_set_cursor = function()
      return true
    end
    vim.api.nvim_buf_get_lines = function()
      return { "Some line content here for testing" }
    end

    -- Mock buffer as markdown
    vim.bo = setmetatable({}, {
      __index = function()
        return { filetype = "markdown" }
      end,
    })

    -- Clear and reload
    package.loaded["markdown-links.insert"] = nil
    insert = require("markdown-links.insert")

    -- Create temp vault with test files that have frontmatter IDs
    _G._insert_test_vault = helpers.create_temp_vault()
    local tv = _G._insert_test_vault
    os.execute("mkdir -p " .. tv .. "/Areas/health")
    helpers.create_test_note(tv, "My Note.md", "---\nid: 20260207-143055-a3f7\n---\nContent")
    helpers.create_test_note(tv .. "/Areas/health", "Workout Routine.md", "---\nid: 20260207-143200-b3f9\n---\nContent")

    -- Mock search module
    mock_search = {
      detect_vault = function()
        return tv
      end,
      search_vault = function()
        return {
          tv .. "/My Note.md",
          tv .. "/Areas/health/Workout Routine.md",
        }
      end,
    }
  end)

  after_each(function()
    package.loaded["markdown-links.insert"] = nil
    helpers.cleanup_mocks()
  end)

  describe("_get_relative_dir", function()
    it("should return directory relative to vault", function()
      local dir = insert._get_relative_dir("/home/user/notes/Areas/health/file.md", "/home/user/notes")
      assert.equal("Areas/health", dir)
    end)

    it("should return empty string for files at vault root", function()
      local dir = insert._get_relative_dir("/home/user/notes/file.md", "/home/user/notes")
      assert.equal("", dir)
    end)

    it("should return empty string when file is outside vault", function()
      local dir = insert._get_relative_dir("/other/path/file.md", "/home/user/notes")
      assert.equal("", dir)
    end)

  end)

  describe("_format_display", function()
    local vault = "/home/user/notes"
    local filepath = "/home/user/notes/Areas/health/Workout Routine.md"
    local root_filepath = "/home/user/notes/My Note.md"

    it("should format 'filename' mode as full filename", function()
      local display, ordinal = insert._format_display(filepath, vault, "filename")
      assert.equal("Workout Routine.md", display)
      assert.equal(filepath, ordinal)
    end)

    it("should format 'full_path' mode as dir/filename", function()
      local display, ordinal = insert._format_display(filepath, vault, "full_path")
      assert.equal("Areas/health/Workout Routine.md", display)
      assert.equal(filepath, ordinal)
    end)

    it("should format 'full_path' mode as just filename at vault root", function()
      local display = insert._format_display(root_filepath, vault, "full_path")
      assert.equal("My Note.md", display)
    end)

    it("should format 'filename_with_path' mode with padding and dir", function()
      local display = insert._format_display(filepath, vault, "filename_with_path")
      assert.truthy(display:match("^Workout Routine%.md"))
      assert.truthy(display:match("Areas/health/$"))
    end)

    it("should format 'title_with_path' (default) mode with title and dir", function()
      local display = insert._format_display(filepath, vault, "title_with_path")
      assert.truthy(display:match("^Workout Routine"))
      assert.truthy(display:match("Areas/health/$"))
    end)

    it("should use title_with_path as default for unknown mode", function()
      local display_default = insert._format_display(filepath, vault, "unknown_mode")
      local display_explicit = insert._format_display(filepath, vault, "title_with_path")
      assert.equal(display_explicit, display_default)
    end)

    it("should omit dir suffix for files at vault root", function()
      local display = insert._format_display(root_filepath, vault, "filename_with_path")
      assert.equal("My Note.md", display)
    end)

    it("should always return filepath as ordinal", function()
      local modes = {
        "filename",
        "full_path",
        "filename_with_path",
        "title_with_path",
      }
      for _, mode in ipairs(modes) do
        local _, ordinal = insert._format_display(filepath, vault, mode)
        assert.equal(filepath, ordinal, "ordinal mismatch for mode: " .. mode)
      end
    end)
  end)

  describe("insert_link error paths", function()
    it("should error if buffer is not markdown", function()
      vim.bo = setmetatable({}, {
        __index = function()
          return { filetype = "text" }
        end,
      })
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/test.txt"
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false)

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("Not a markdown file"))
      assert.equal(vim.log.levels.ERROR, notifications[1].level)
    end)

    it("should error if buffer has no filename", function()
      vim.api.nvim_buf_get_name = function()
        return ""
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false)

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("no file name"))
      assert.equal(vim.log.levels.ERROR, notifications[1].level)
    end)

    it("should error if buffer is outside all vaults", function()
      mock_search.detect_vault = function()
        return nil
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false)

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("outside all configured vaults"))
      assert.equal(vim.log.levels.ERROR, notifications[1].level)
    end)

    it("should warn if no files with IDs found", function()
      mock_search.search_vault = function()
        return { "/home/user/notes/plain-note.md" }
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false)

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("No markdown files with IDs"))
      assert.equal(vim.log.levels.WARN, notifications[1].level)
    end)
  end)

  describe("insert_link with vim.ui.select", function()
    it("should call vim.ui.select with formatted items", function()
      local select_called = false
      local select_items
      vim.ui.select = function(items, opts, cb)
        select_called = true
        select_items = items
      end

      insert.insert_link(
        { vault_path = { "/home/user/notes" }, exclude_dirs = {}, picker_display = "filename" },
        mock_search,
        false
      )

      assert.is_true(select_called)
      assert.equal(2, #select_items)
    end)

    it("should insert link at cursor when item selected", function()
      local set_text_args = nil
      vim.api.nvim_buf_set_text = function(buf, row, scol, erow, ecol, lines)
        set_text_args = { buf = buf, row = row, scol = scol, lines = lines }
      end

      vim.ui.select = function(items, opts, cb)
        -- Simulate selecting the first item
        cb(items[1], 1)
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false)

      assert.is_not_nil(set_text_args)
      assert.equal(1, set_text_args.buf)
      -- Cursor was at row 10 (1-indexed), so 0-indexed = 9
      assert.equal(9, set_text_args.row)
      -- Link should be in [Title](ID) format (bare ID, no .md)
      local link = set_text_args.lines[1]
      assert.truthy(link:match("^%[.+%]%(.*%)$"))
      -- URL should be just bare ID
      local url = link:match("%((.-)%)$")
      assert.truthy(url:match("^%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-[0-9a-z][0-9a-z][0-9a-z][0-9a-z]$"))
    end)

    it("should insert link on an empty line without error", function()
      -- Cursor on an empty line: row=1 (1-indexed), col=0
      vim.api.nvim_win_get_cursor = function()
        return { 1, 0 }
      end
      vim.api.nvim_buf_get_lines = function()
        return { "" }
      end

      local set_text_args = nil
      vim.api.nvim_buf_set_text = function(buf, row, scol, erow, ecol, lines)
        set_text_args = { buf = buf, row = row, scol = scol, ecol = ecol, lines = lines }
      end

      vim.ui.select = function(items, opts, cb)
        cb(items[1], 1)
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false)

      assert.is_not_nil(set_text_args)
      -- On empty line, col should be clamped to 0 (not 1)
      assert.equal(0, set_text_args.scol)
      assert.equal(0, set_text_args.ecol)
      -- Should still produce a valid link
      local link = set_text_args.lines[1]
      assert.truthy(link:match("^%[.+%]%(.*%)$"))
      -- No error notification
      assert.equal(0, #notifications)
    end)

    it("should do nothing when picker is cancelled", function()
      local set_text_called = false
      vim.api.nvim_buf_set_text = function()
        set_text_called = true
      end

      vim.ui.select = function(items, opts, cb)
        cb(nil, nil) -- cancelled
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false)

      assert.is_false(set_text_called)
    end)

    it("should notify on buffer set_text failure", function()
      vim.api.nvim_buf_set_text = function()
        error("buffer was closed")
      end

      vim.ui.select = function(items, opts, cb)
        cb(items[1], 1)
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false)

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("Failed to insert link"))
      assert.equal(vim.log.levels.ERROR, notifications[1].level)
    end)

    it("should sort picker items alphabetically", function()
      local tv = _G._insert_test_vault
      helpers.create_test_note(tv, "Zebra.md", "---\nid: 20260207-143055-a3f7\n---\n")
      helpers.create_test_note(tv, "Alpha.md", "---\nid: 20260207-143055-b3f9\n---\n")

      mock_search.search_vault = function()
        return {
          tv .. "/Zebra.md",
          tv .. "/Alpha.md",
        }
      end

      local select_items
      vim.ui.select = function(items, opts, cb)
        select_items = items
      end

      insert.insert_link(
        { vault_path = { tv }, exclude_dirs = {}, picker_display = "filename" },
        mock_search,
        false
      )

      assert.equal(2, #select_items)
      -- Alpha should come before Zebra
      assert.truthy(select_items[1]:match("^Alpha"))
      assert.truthy(select_items[2]:match("^Zebra"))
    end)
  end)

  describe("ID filtering", function()
    it("should filter out files without frontmatter IDs", function()
      local tv = _G._insert_test_vault
      helpers.create_test_note(tv, "plain-note.md", "Just content without frontmatter")

      mock_search.search_vault = function()
        return {
          tv .. "/My Note.md",
          tv .. "/plain-note.md",
          tv .. "/Areas/health/Workout Routine.md",
        }
      end

      local select_items
      vim.ui.select = function(items, opts, cb)
        select_items = items
      end

      insert.insert_link(
        { vault_path = { tv }, exclude_dirs = {}, picker_display = "filename" },
        mock_search,
        false
      )

      -- Only 2 files have frontmatter IDs, plain-note.md should be filtered out
      assert.equal(2, #select_items)
    end)
  end)

  describe("visual selection edge cases", function()
    it("should abort on multi-line visual selection", function()
      -- Simulate multi-line visual marks (different line numbers)
      vim.fn.getpos = function(mark)
        if mark == "'<" then
          return { 0, 5, 1, 0 }
        end
        if mark == "'>" then
          return { 0, 7, 10, 0 }
        end
        return { 0, 0, 0, 0 }
      end
      vim.api.nvim_buf_get_text = function()
        return { "some text" }
      end

      local set_text_called = false
      vim.api.nvim_buf_set_text = function()
        set_text_called = true
      end

      vim.ui.select = function(items, opts, cb)
        cb(items[1], 1)
      end

      -- Invoke with from_range=true to trigger visual selection path
      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false, true)

      -- Should have notified about multi-line and NOT inserted any link
      assert.is_false(set_text_called)
      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("Multi%-line selection"))
    end)

    it("should abort on invalid visual marks (zero line)", function()
      -- Simulate invalid marks (line number = 0)
      vim.fn.getpos = function(mark)
        return { 0, 0, 0, 0 }
      end

      local set_text_called = false
      vim.api.nvim_buf_set_text = function()
        set_text_called = true
      end

      vim.ui.select = function(items, opts, cb)
        cb(items[1], 1)
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false, true)

      -- Should have returned early without inserting (nil visual_text)
      assert.is_false(set_text_called)
    end)

    it("should abort when nvim_buf_get_text fails in visual selection", function()
      vim.fn.getpos = function(mark)
        if mark == "'<" then
          return { 0, 10, 5, 0 }
        end
        if mark == "'>" then
          return { 0, 10, 15, 0 }
        end
        return { 0, 0, 0, 0 }
      end
      vim.api.nvim_buf_get_text = function()
        error("Invalid buffer range")
      end

      local set_text_called = false
      vim.api.nvim_buf_set_text = function()
        set_text_called = true
      end

      vim.ui.select = function(items, opts, cb)
        cb(items[1], 1)
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false, true)

      -- Should have returned early without inserting
      assert.is_false(set_text_called)
    end)

    it("should abort when nvim_buf_get_text returns empty lines", function()
      vim.fn.getpos = function(mark)
        if mark == "'<" then
          return { 0, 10, 5, 0 }
        end
        if mark == "'>" then
          return { 0, 10, 15, 0 }
        end
        return { 0, 0, 0, 0 }
      end
      vim.api.nvim_buf_get_text = function()
        return {}
      end

      local set_text_called = false
      vim.api.nvim_buf_set_text = function()
        set_text_called = true
      end

      vim.ui.select = function(items, opts, cb)
        cb(items[1], 1)
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false, true)

      -- Should have returned early without inserting
      assert.is_false(set_text_called)
    end)
  end)

  describe("empty vault picker", function()
    it("should warn when vault has no files at all", function()
      mock_search.search_vault = function()
        return {}
      end

      local select_called = false
      vim.ui.select = function()
        select_called = true
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false)

      -- Should warn, not show picker
      assert.is_false(select_called)
      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("No markdown files with IDs"))
    end)

    it("should handle nvim_buf_get_name pcall failure", function()
      vim.api.nvim_buf_get_name = function()
        error("Invalid buffer")
      end

      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false)

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("no file name"))
    end)
  end)

  describe("link building", function()
    it("should build links with bare ID as URL", function()
      local title = "My Note"
      local note_id = "20260207-143055-a3f7"
      local link = string.format("[%s](%s)", title, note_id)
      assert.equal("[My Note](20260207-143055-a3f7)", link)
    end)

    it("should use visual text as title when invoked from range", function()
      local set_text_args = nil
      vim.api.nvim_buf_set_text = function(buf, row, scol, erow, ecol, lines)
        set_text_args = { lines = lines }
      end

      -- Simulate visual selection marks
      vim.fn.getpos = function(mark)
        if mark == "'<" then
          return { 0, 10, 5, 0 }
        end
        if mark == "'>" then
          return { 0, 10, 17, 0 }
        end
        return { 0, 0, 0, 0 }
      end
      vim.api.nvim_buf_get_text = function()
        return { "custom title" }
      end

      vim.ui.select = function(items, opts, cb)
        cb(items[1], 1)
      end

      -- Pass from_range=true instead of relying on nvim_get_mode
      insert.insert_link({
        vault_path = { "/home/user/notes" },
        exclude_dirs = {},

        picker_display = "title_with_path",
      }, mock_search, false, true)

      assert.is_not_nil(set_text_args)
      local link = set_text_args.lines[1]
      assert.truthy(link:match("^%[custom title%]"))
      -- URL should be bare ID
      local url = link:match("%((.-)%)$")
      assert.truthy(url:match("^%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-[0-9a-z][0-9a-z][0-9a-z][0-9a-z]$"))
    end)
  end)
end)
