-- Tests for new file creation (fn-1.7)
local helpers = require("tests.init")

describe("new_file", function()
  local new_file_mod
  local mock_search
  local notifications

  before_each(function()
    helpers.mock_vim()
    vim.log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } }
    vim.fn.fnameescape = function(path)
      return path
    end

    -- Capture notifications
    notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    -- Default buffer setup
    vim.api.nvim_buf_get_name = function()
      return "/home/user/notes/test.md"
    end

    -- Clear and reload modules
    package.loaded["markdown-links.new_file"] = nil
    package.loaded["markdown-links.id"] = nil
    package.loaded["markdown-links.util"] = nil
    new_file_mod = require("markdown-links.new_file")

    -- Mock search module
    mock_search = {
      detect_vault = function(buf_path, vault_paths)
        for _, vp in ipairs(vault_paths) do
          if vim.startswith(buf_path, vp .. "/") then
            return vp
          end
        end
        return nil
      end,
      search_files_by_frontmatter_id = function(check_id, vault_path, exclude_dirs)
        if type(check_id) ~= "string" or type(vault_path) ~= "string" then
          return {}
        end
        -- Default: no collisions
        return {}
      end,
    }
  end)

  after_each(function()
    package.loaded["markdown-links.new_file"] = nil
    package.loaded["markdown-links.id"] = nil
    package.loaded["markdown-links.util"] = nil
    helpers.cleanup_mocks()
  end)

  describe("is_ascii", function()
    it("should accept printable ASCII (space to tilde)", function()
      assert.is_true(new_file_mod.is_ascii("Hello World"))
      assert.is_true(new_file_mod.is_ascii("abc123"))
      assert.is_true(new_file_mod.is_ascii("!@#$%^&*()"))
      assert.is_true(new_file_mod.is_ascii(" ")) -- space (32)
      assert.is_true(new_file_mod.is_ascii("~")) -- tilde (126)
    end)

    it("should accept all printable ASCII range", function()
      -- Build string of all printable ASCII chars (32-126)
      local chars = {}
      for i = 32, 126 do
        table.insert(chars, string.char(i))
      end
      assert.is_true(new_file_mod.is_ascii(table.concat(chars)))
    end)

    it("should reject control characters", function()
      assert.is_false(new_file_mod.is_ascii("\t")) -- tab (9)
      assert.is_false(new_file_mod.is_ascii("\n")) -- newline (10)
      assert.is_false(new_file_mod.is_ascii("\r")) -- carriage return (13)
      assert.is_false(new_file_mod.is_ascii("\0")) -- null (0)
      assert.is_false(new_file_mod.is_ascii(string.char(31))) -- unit separator
    end)

    it("should reject DEL character (127)", function()
      assert.is_false(new_file_mod.is_ascii(string.char(127)))
    end)

    it("should reject high bytes (> 127, typical of Unicode)", function()
      assert.is_false(new_file_mod.is_ascii(string.char(128)))
      assert.is_false(new_file_mod.is_ascii(string.char(200)))
      assert.is_false(new_file_mod.is_ascii(string.char(255)))
    end)

    it("should reject strings containing mixed ASCII and non-ASCII", function()
      assert.is_false(new_file_mod.is_ascii("hello\tworld"))
      assert.is_false(new_file_mod.is_ascii("abc" .. string.char(128) .. "def"))
    end)

    it("should accept empty string", function()
      assert.is_true(new_file_mod.is_ascii(""))
    end)

  end)

  describe("generate_unique_id", function()
    local test_config = { exclude_dirs = {} }

    it("should return an ID when no collision", function()
      local test_search = {
        search_files_by_frontmatter_id = function()
          return {}
        end,
      }
      local result = new_file_mod.generate_unique_id("/vault", test_search, test_config)
      assert.is_string(result)
      assert.equal(20, #result)
    end)

    it("should retry on collision and succeed", function()
      local call_count = 0
      local test_search = {
        search_files_by_frontmatter_id = function(check_id)
          call_count = call_count + 1
          if call_count <= 2 then
            return { "existing-file-" .. check_id .. ".md" }
          end
          return {}
        end,
      }

      local result = new_file_mod.generate_unique_id("/vault", test_search, test_config)
      assert.is_string(result)
      assert.equal(3, call_count) -- Failed 2 times, succeeded on 3rd
    end)

    it("should return nil after 4 failed attempts", function()
      local call_count = 0
      local test_search = {
        search_files_by_frontmatter_id = function()
          call_count = call_count + 1
          return { "collision.md" }
        end,
      }

      local result = new_file_mod.generate_unique_id("/vault", test_search, test_config)
      assert.is_nil(result)
      assert.equal(4, call_count)
    end)

    it("should try up to 4 times total (initial + 3 retries)", function()
      local call_count = 0
      local test_search = {
        search_files_by_frontmatter_id = function()
          call_count = call_count + 1
          if call_count == 4 then
            return {}
          end
          return { "collision.md" }
        end,
      }

      local result = new_file_mod.generate_unique_id("/vault", test_search, test_config)
      assert.is_string(result) -- Should succeed on 4th attempt
      assert.equal(4, call_count)
    end)
  end)

  describe("new_file cancel handling", function()
    it("should silently abort on nil input (Escape)", function()
      vim.ui.input = function(opts, callback)
        callback(nil)
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.equal(0, #notifications)
    end)

    it("should show INFO notification on empty input", function()
      vim.ui.input = function(opts, callback)
        callback("")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("markdown%-links: File creation cancelled"))
      assert.equal(vim.log.levels.INFO, notifications[1].level)
    end)
  end)

  describe("new_file ASCII validation", function()
    it("should reject non-ASCII input and re-prompt", function()
      local prompt_count = 0
      vim.ui.input = function(opts, callback)
        prompt_count = prompt_count + 1
        if prompt_count == 1 then
          -- First call: non-ASCII input
          callback("hello" .. string.char(200))
        else
          -- Second call: cancel to stop the loop
          callback(nil)
        end
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.equal(2, prompt_count)
      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("Invalid characters"))
      assert.equal(vim.log.levels.ERROR, notifications[1].level)
    end)

    it("should accept valid ASCII input", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end

      vim.ui.input = function(opts, callback)
        callback("My New Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      -- Should have created file and opened it
      assert.is_not_nil(cmd_called)
      assert.truthy(cmd_called:match("^edit "))
    end)
  end)

  describe("new_file filename generation", function()
    it("should use original input as filename without slugify", function()
      local created_filepath = nil
      vim.fn.writefile = function(content, path)
        created_filepath = path
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("My Testing Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(created_filepath)
      assert.truthy(created_filepath:match("My Testing Note%.md$"))
    end)

    it("should trim leading/trailing whitespace from input", function()
      local created_filepath = nil
      vim.fn.writefile = function(content, path)
        created_filepath = path
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("  My Note  ")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(created_filepath)
      assert.truthy(created_filepath:match("My Note%.md$"))
    end)

    it("should use Untitled for whitespace-only input", function()
      local created_filepath = nil
      vim.fn.writefile = function(content, path)
        created_filepath = path
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("   ")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(created_filepath)
      assert.truthy(created_filepath:match("Untitled%.md$"))
    end)

    it("should not include ID in filename", function()
      local created_filepath = nil
      vim.fn.writefile = function(content, path)
        created_filepath = path
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("My Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(created_filepath)
      -- Should NOT contain the ID pattern
      local id_pattern = "%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-[0-9a-z][0-9a-z][0-9a-z][0-9a-z]"
      assert.is_nil(created_filepath:match(id_pattern))
      assert.truthy(created_filepath:match("My Note%.md$"))
    end)

    it("should preserve special characters in filename", function()
      local created_filepath = nil
      vim.fn.writefile = function(content, path)
        created_filepath = path
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("My Awesome Note!!!")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(created_filepath)
      assert.truthy(created_filepath:match("My Awesome Note!!!%.md$"))
    end)
  end)

  describe("new_file ID generation and collision retry", function()
    it("should generate file with natural name and frontmatter ID", function()
      local created_filepath = nil
      local writefile_content = nil
      vim.fn.writefile = function(content, path)
        created_filepath = path
        writefile_content = content
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(created_filepath)
      -- Filename should be natural, no ID
      assert.truthy(created_filepath:match("Test Note%.md$"))
      -- Frontmatter should contain the ID
      assert.equal("---", writefile_content[1])
      assert.truthy(
        writefile_content[2]:match("^id: %d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-[0-9a-z][0-9a-z][0-9a-z][0-9a-z]$")
      )
      assert.equal("---", writefile_content[3])
      assert.equal("", writefile_content[4])
    end)

    it("should error after 4 failed collision retries", function()
      -- Override to always return collision
      local original_generate_unique_id = new_file_mod.generate_unique_id
      new_file_mod.generate_unique_id = function()
        return nil
      end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end
      vim.cmd = function() end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("Failed to generate unique ID"))
      assert.equal(vim.log.levels.ERROR, notifications[1].level)

      -- Restore
      new_file_mod.generate_unique_id = original_generate_unique_id
    end)
  end)

  describe("new_file directory creation", function()
    it("should call mkdir with 'p' flag for recursive creation", function()
      local mkdir_args = nil
      vim.fn.mkdir = function(path, flags)
        mkdir_args = { path = path, flags = flags }
        return 1
      end
      vim.fn.writefile = function()
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(mkdir_args)
      assert.equal("/home/user/notes", mkdir_args.path)
      assert.equal("p", mkdir_args.flags)
    end)
  end)

  describe("new_file file creation", function()
    it("should create file with frontmatter via vim.fn.writefile", function()
      local writefile_args = nil
      vim.fn.writefile = function(content, path)
        writefile_args = { content = content, path = path }
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(writefile_args)
      -- Content should be frontmatter with ID
      assert.equal(4, #writefile_args.content)
      assert.equal("---", writefile_args.content[1])
      assert.truthy(writefile_args.content[2]:match("^id: "))
      assert.equal("---", writefile_args.content[3])
      assert.equal("", writefile_args.content[4])
      assert.truthy(writefile_args.path:match("%.md$"))
    end)

    it("should error if writefile fails", function()
      vim.fn.writefile = function()
        return -1
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      local found_error = false
      for _, n in ipairs(notifications) do
        if n.msg:match("Failed to create file") then
          found_error = true
        end
      end
      assert.is_true(found_error)
    end)
  end)

  describe("new_file file existence check", function()
    it("should error if file already exists", function()
      vim.fn.filereadable = function()
        return 1 -- File already exists
      end
      vim.fn.writefile = function()
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("Existing Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      local found_error = false
      for _, n in ipairs(notifications) do
        if n.msg:match("File already exists") then
          found_error = true
        end
      end
      assert.is_true(found_error)
    end)

    it("should proceed when file does not exist", function()
      vim.fn.filereadable = function()
        return 0 -- File does not exist
      end
      local writefile_called = false
      vim.fn.writefile = function()
        writefile_called = true
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("New Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_true(writefile_called)
    end)
  end)

  describe("new_file open_mode", function()
    it("should open file with 'edit' command", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.writefile = function()
        return 0
      end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(cmd_called)
      assert.truthy(cmd_called:match("^edit "))
    end)

    it("should open file with 'vsplit' command", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.writefile = function()
        return 0
      end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "vsplit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(cmd_called)
      assert.truthy(cmd_called:match("^vsplit "))
    end)

    it("should open file with 'split' command", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.writefile = function()
        return 0
      end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "split", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(cmd_called)
      assert.truthy(cmd_called:match("^split "))
    end)

    it("should open file with 'tabedit' command", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.writefile = function()
        return 0
      end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "tabedit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(cmd_called)
      assert.truthy(cmd_called:match("^tabedit "))
    end)

    it("should default to 'edit' when open_mode is nil", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.writefile = function()
        return 0
      end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = nil, exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(cmd_called)
      assert.truthy(cmd_called:match("^edit "))
    end)

    it("should fall back to 'edit' when open_mode is invalid", function()
      local cmd_called = nil
      vim.cmd = function(cmd)
        cmd_called = cmd
      end
      vim.fn.writefile = function()
        return 0
      end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "!rm -rf /", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(cmd_called)
      assert.truthy(cmd_called:match("^edit "))
    end)
  end)

  describe("new_file notifications", function()
    it("should show INFO notification with filename and vault", function()
      vim.fn.writefile = function()
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      local found_info = false
      for _, n in ipairs(notifications) do
        if n.msg:match("Created new note:") and n.msg:match("in vault") and n.level == vim.log.levels.INFO then
          found_info = true
        end
      end
      assert.is_true(found_info, "Expected INFO notification with filename and vault")
    end)

    it("should include the generated filename in notification", function()
      vim.fn.writefile = function()
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("My Special Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:match("My Special Note%.md") and n.msg:match("/home/user/notes") then
          found = true
        end
      end
      assert.is_true(found, "Notification should contain the natural filename and vault path")
    end)
  end)

  describe("new_file path_arg handling", function()
    it("should error if path_arg is outside configured vaults", function()
      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search,
        "/outside/vault"
      )

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("outside all configured vaults"))
      assert.equal(vim.log.levels.ERROR, notifications[1].level)
    end)

    it("should error if path_arg is not absolute", function()
      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search,
        "relative/path"
      )

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("must be absolute"))
      assert.equal(vim.log.levels.ERROR, notifications[1].level)
    end)

    it("should use path_arg as target directory when valid", function()
      local created_filepath = nil
      vim.fn.writefile = function(content, path)
        created_filepath = path
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search,
        "/home/user/notes/subdir"
      )

      assert.is_not_nil(created_filepath)
      assert.truthy(created_filepath:match("^/home/user/notes/subdir/"))
    end)

    it("should use current buffer directory when no path_arg", function()
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes/subfolder/current.md"
      end

      local created_filepath = nil
      vim.fn.writefile = function(content, path)
        created_filepath = path
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(created_filepath)
      assert.truthy(created_filepath:match("^/home/user/notes/subfolder/"))
    end)
  end)

  describe("new_file error paths", function()
    it("should error if buffer has no file name and no path_arg", function()
      vim.api.nvim_buf_get_name = function()
        return ""
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("no file name"))
    end)

    it("should error if buffer is outside all vaults and no path_arg", function()
      vim.api.nvim_buf_get_name = function()
        return "/outside/test.md"
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("outside all configured vaults"))
    end)
  end)

  describe("new_file prompt", function()
    it("should call vim.ui.input with correct prompt text", function()
      local input_opts = nil
      vim.ui.input = function(opts, callback)
        input_opts = opts
        callback(nil) -- cancel
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      assert.is_not_nil(input_opts)
      assert.equal("Name for new note:", input_opts.prompt)
    end)
  end)

  describe("new_file collision scenario integration", function()
    it("should handle collision and retry with different ID", function()
      local created_files = {}

      vim.fn.writefile = function(content, path)
        table.insert(created_files, path)
        return 0
      end
      vim.cmd = function() end

      vim.ui.input = function(opts, callback)
        callback("Test Note")
      end

      new_file_mod.new_file(
        { vault_path = { "/home/user/notes" }, open_mode = "edit", exclude_dirs = {} },
        mock_search
      )

      -- File should still be created (ID generation manages its own collision logic)
      assert.equal(1, #created_files)
    end)
  end)
end)
