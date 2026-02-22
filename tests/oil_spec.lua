-- Tests for Oil.nvim integration
local helpers = require("tests.init")

describe("oil", function()
  local oil_mod
  local mock_search
  local notifications

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

    -- Clear modules
    package.loaded["markdown-links.oil"] = nil
    package.loaded["markdown-links.new_file"] = nil
    package.loaded["markdown-links.id"] = nil
    package.loaded["markdown-links.util"] = nil
    package.loaded["oil"] = nil
    package.loaded["oil.util"] = nil

    -- Mock oil.util.parse_url
    package.loaded["oil.util"] = {
      parse_url = function(url)
        return url:match("^(.*://)(.*)$")
      end,
    }

    -- Mock search module
    mock_search = {
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
      search_files_by_frontmatter_id = function(check_id, vault_path, exclude_dirs)
        -- Frontmatter-based search - search files in vault and check their frontmatter
        if type(check_id) ~= "string" or type(vault_path) ~= "string" then
          return {}
        end
        -- Default: no collisions (return empty = unique ID)
        return {}
      end,
    }

    -- Reset ID generation for predictable tests
    package.loaded["markdown-links.id"] = nil
    local id_mod = require("markdown-links.id")
    local counter = 0
    id_mod.generate_id = function()
      counter = counter + 1
      return string.format("20250212-120000-%04d", counter)
    end
    id_mod.validate_id = function(id)
      return type(id) == "string" and id:match("^%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-[0-9a-z]+$") ~= nil
    end

    oil_mod = require("markdown-links.oil")
  end)

  after_each(function()
    package.loaded["markdown-links.oil"] = nil
    package.loaded["markdown-links.new_file"] = nil
    package.loaded["markdown-links.id"] = nil
    package.loaded["markdown-links.util"] = nil
    package.loaded["oil"] = nil
    package.loaded["oil.util"] = nil
    helpers.cleanup_mocks()
  end)

  describe("is_oil_available", function()
    it("should return true when oil is installed", function()
      package.loaded["oil"] = { get_current_dir = function() end }
      -- Reload to pick up the mock
      package.loaded["markdown-links.oil"] = nil
      oil_mod = require("markdown-links.oil")
      assert.is_true(oil_mod.is_oil_available())
    end)

    it("should return false when oil is not installed", function()
      package.loaded["oil"] = nil
      package.loaded["markdown-links.oil"] = nil
      oil_mod = require("markdown-links.oil")
      assert.is_false(oil_mod.is_oil_available())
    end)
  end)

  describe("add_frontmatter_to_file", function()
    it("should add frontmatter to empty file", function()
      local written_lines = nil
      vim.fn.writefile = function(lines, filepath)
        written_lines = lines
        return 0
      end

      local result = oil_mod.add_frontmatter_to_file("/tmp/test.md", "20250212-120000-abcd")

      assert.is_true(result)
      assert.equal("---", written_lines[1])
      assert.equal("id: 20250212-120000-abcd", written_lines[2])
      assert.equal("---", written_lines[3])
      assert.equal("", written_lines[4])
    end)

    it("should preserve existing content", function()
      -- Mock io.open to simulate file with existing content
      local mock_content = { "# My Note", "", "This is content." }
      local read_index = 0
      local file_mock = {
        read = function(self, fmt)
          if fmt == "*l" then
            read_index = read_index + 1
            return mock_content[read_index]
          end
          return nil
        end,
        close = function() end,
      }

      local orig_io_open = io.open
      io.open = function(path, mode)
        if mode == "r" then
          read_index = 0
          return file_mock
        end
        return orig_io_open(path, mode)
      end

      local written_lines = nil
      vim.fn.writefile = function(lines, filepath)
        written_lines = lines
        return 0
      end

      local result = oil_mod.add_frontmatter_to_file("/tmp/test.md", "20250212-120000-abcd")

      io.open = orig_io_open

      assert.is_true(result)
      -- Frontmatter comes first
      assert.equal("---", written_lines[1])
      assert.equal("id: 20250212-120000-abcd", written_lines[2])
      assert.equal("---", written_lines[3])
      assert.equal("", written_lines[4])
      -- Original content follows
      assert.equal("# My Note", written_lines[5])
      assert.equal("", written_lines[6])
      assert.equal("This is content.", written_lines[7])
    end)

    it("should create file if it does not exist", function()
      -- Mock io.open to return nil (file doesn't exist)
      local orig_io_open = io.open
      io.open = function(path, mode)
        if mode == "r" then
          return nil
        end
        return orig_io_open(path, mode)
      end

      local written_lines = nil
      vim.fn.writefile = function(lines, filepath)
        written_lines = lines
        return 0
      end

      local result = oil_mod.add_frontmatter_to_file("/tmp/test.md", "20250212-120000-abcd")

      io.open = orig_io_open

      assert.is_true(result)
      assert.equal("---", written_lines[1])
      assert.equal("id: 20250212-120000-abcd", written_lines[2])
      assert.equal("---", written_lines[3])
      assert.equal("", written_lines[4])
    end)

    it("should return false on writefile error", function()
      vim.fn.writefile = function(lines, filepath)
        return 1 -- Simulate error
      end

      local result = oil_mod.add_frontmatter_to_file("/tmp/test.md", "20250212-120000-abcd")

      assert.is_false(result)
      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("Failed to write frontmatter"))
    end)
  end)

  describe("setup_hook", function()
    it("should register only OilActionsPost autocmd", function()
      local autocmds_created = {}
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(autocmds_created, { event = event, pattern = opts.pattern, group = opts.group })
      end

      local test_config = {
        vault_path = { "/home/user/notes" },
        exclude_dirs = { ".git" },

      }

      oil_mod.setup_hook(test_config, mock_search)

      assert.equal(1, #autocmds_created)
      assert.equal("User", autocmds_created[1].event)
      assert.equal("OilActionsPost", autocmds_created[1].pattern)
    end)

    it("should add frontmatter to new markdown files in vaults", function()
      local registered_callback
      vim.api.nvim_create_autocmd = function(_, opts)
        registered_callback = opts.callback
      end

      local frontmatter_calls = {}
      oil_mod.add_frontmatter_to_file = function(filepath, id)
        table.insert(frontmatter_calls, { path = filepath, id = id })
        return true
      end

      local test_config = {
        vault_path = { "/home/user/notes" },
        exclude_dirs = { ".git" },

      }

      oil_mod.setup_hook(test_config, mock_search)

      local actions = {
        {
          type = "create",
          entry_type = "file",
          url = "oil:///home/user/notes/New Note.md",
        },
      }
      registered_callback({ data = { err = nil, actions = actions } })

      assert.equal(1, #frontmatter_calls)
      assert.equal("/home/user/notes/New Note.md", frontmatter_calls[1].path)
      assert.truthy(frontmatter_calls[1].id:match("^%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-[0-9a-z]+$"))
    end)

    it("should skip processing when OilActionsPost has an error", function()
      local registered_callback
      vim.api.nvim_create_autocmd = function(_, opts)
        registered_callback = opts.callback
      end

      local frontmatter_calls = {}
      oil_mod.add_frontmatter_to_file = function(filepath, id)
        table.insert(frontmatter_calls, { path = filepath, id = id })
        return true
      end

      local test_config = {
        vault_path = { "/home/user/notes" },
        exclude_dirs = { ".git" },

      }

      oil_mod.setup_hook(test_config, mock_search)

      local actions = {
        { type = "create", entry_type = "file", url = "oil:///home/user/notes/Note.md" },
      }
      registered_callback({ data = { err = "some error", actions = actions } })

      assert.equal(0, #frontmatter_calls) -- No frontmatter added on error
    end)

    it("should skip non-create actions", function()
      local registered_callback
      vim.api.nvim_create_autocmd = function(_, opts)
        registered_callback = opts.callback
      end

      local frontmatter_calls = {}
      oil_mod.add_frontmatter_to_file = function(filepath, id)
        table.insert(frontmatter_calls, { path = filepath, id = id })
        return true
      end

      local test_config = {
        vault_path = { "/home/user/notes" },
        exclude_dirs = { ".git" },

      }

      oil_mod.setup_hook(test_config, mock_search)

      local actions = {
        { type = "delete", entry_type = "file", url = "oil:///home/user/notes/old.md" },
      }
      registered_callback({ data = { err = nil, actions = actions } })

      assert.equal(0, #frontmatter_calls)
    end)

    it("should skip non-file entries", function()
      local registered_callback
      vim.api.nvim_create_autocmd = function(_, opts)
        registered_callback = opts.callback
      end

      local frontmatter_calls = {}
      oil_mod.add_frontmatter_to_file = function(filepath, id)
        table.insert(frontmatter_calls, { path = filepath, id = id })
        return true
      end

      local test_config = {
        vault_path = { "/home/user/notes" },
        exclude_dirs = { ".git" },

      }

      oil_mod.setup_hook(test_config, mock_search)

      local actions = {
        { type = "create", entry_type = "directory", url = "oil:///home/user/notes/subdir" },
      }
      registered_callback({ data = { err = nil, actions = actions } })

      assert.equal(0, #frontmatter_calls)
    end)

    it("should skip non-markdown files", function()
      local registered_callback
      vim.api.nvim_create_autocmd = function(_, opts)
        registered_callback = opts.callback
      end

      local frontmatter_calls = {}
      oil_mod.add_frontmatter_to_file = function(filepath, id)
        table.insert(frontmatter_calls, { path = filepath, id = id })
        return true
      end

      local test_config = {
        vault_path = { "/home/user/notes" },
        exclude_dirs = { ".git" },

      }

      oil_mod.setup_hook(test_config, mock_search)

      local actions = {
        { type = "create", entry_type = "file", url = "oil:///home/user/notes/readme.txt" },
      }
      registered_callback({ data = { err = nil, actions = actions } })

      assert.equal(0, #frontmatter_calls)
    end)

    it("should skip files outside configured vaults", function()
      local registered_callback
      vim.api.nvim_create_autocmd = function(_, opts)
        registered_callback = opts.callback
      end

      local frontmatter_calls = {}
      oil_mod.add_frontmatter_to_file = function(filepath, id)
        table.insert(frontmatter_calls, { path = filepath, id = id })
        return true
      end

      local test_config = {
        vault_path = { "/home/user/notes" },
        exclude_dirs = { ".git" },

      }

      oil_mod.setup_hook(test_config, mock_search)

      local actions = {
        { type = "create", entry_type = "file", url = "oil:///home/user/other/note.md" },
      }
      registered_callback({ data = { err = nil, actions = actions } })

      assert.equal(0, #frontmatter_calls)
    end)

    it("should handle multiple files in one action", function()
      local registered_callback
      vim.api.nvim_create_autocmd = function(_, opts)
        registered_callback = opts.callback
      end

      local frontmatter_calls = {}
      oil_mod.add_frontmatter_to_file = function(filepath, id)
        table.insert(frontmatter_calls, { path = filepath, id = id })
        return true
      end

      local test_config = {
        vault_path = { "/home/user/notes" },
        exclude_dirs = { ".git" },

      }

      oil_mod.setup_hook(test_config, mock_search)

      local actions = {
        { type = "create", entry_type = "file", url = "oil:///home/user/notes/Note One.md" },
        { type = "create", entry_type = "file", url = "oil:///home/user/notes/Note Two.md" },
      }
      registered_callback({ data = { err = nil, actions = actions } })

      assert.equal(2, #frontmatter_calls)
      assert.equal("/home/user/notes/Note One.md", frontmatter_calls[1].path)
      assert.equal("/home/user/notes/Note Two.md", frontmatter_calls[2].path)
    end)

    it("should handle mixed actions (only process valid markdown creates)", function()
      local registered_callback
      vim.api.nvim_create_autocmd = function(_, opts)
        registered_callback = opts.callback
      end

      local frontmatter_calls = {}
      oil_mod.add_frontmatter_to_file = function(filepath, id)
        table.insert(frontmatter_calls, { path = filepath, id = id })
        return true
      end

      local test_config = {
        vault_path = { "/home/user/notes" },
        exclude_dirs = { ".git" },

      }

      oil_mod.setup_hook(test_config, mock_search)

      local actions = {
        { type = "delete", entry_type = "file", url = "oil:///home/user/notes/old.md" },
        { type = "create", entry_type = "file", url = "oil:///home/user/notes/Fresh Note.md" },
        { type = "create", entry_type = "directory", url = "oil:///home/user/notes/subdir" },
        { type = "create", entry_type = "file", url = "oil:///home/user/notes/readme.txt" },
        { type = "create", entry_type = "file", url = "oil:///home/user/other/outside.md" },
      }

      registered_callback({ data = { err = nil, actions = actions } })

      assert.equal(1, #frontmatter_calls)
      assert.equal("/home/user/notes/Fresh Note.md", frontmatter_calls[1].path)
    end)

    it("should handle ID generation failure gracefully", function()
      local registered_callback
      vim.api.nvim_create_autocmd = function(_, opts)
        registered_callback = opts.callback
      end

      -- Make all IDs collide
      mock_search.search_files_by_frontmatter_id = function()
        return { "match.md" }
      end

      local frontmatter_calls = {}
      oil_mod.add_frontmatter_to_file = function(filepath, id)
        table.insert(frontmatter_calls, { path = filepath, id = id })
        return true
      end

      local test_config = {
        vault_path = { "/home/user/notes" },
        exclude_dirs = { ".git" },

      }

      oil_mod.setup_hook(test_config, mock_search)

      local actions = {
        { type = "create", entry_type = "file", url = "oil:///home/user/notes/Note.md" },
      }
      registered_callback({ data = { err = nil, actions = actions } })

      assert.equal(0, #frontmatter_calls)
      assert.equal(1, #notifications)
      assert.truthy(notifications[1].msg:match("Failed to generate unique ID"))
    end)
  end)
end)
