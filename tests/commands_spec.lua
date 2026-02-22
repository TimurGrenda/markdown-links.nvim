-- Tests for command registration (fn-1.8)
---@diagnostic disable: need-check-nil, undefined-field
local helpers = require("tests.init")

describe("commands", function()
  local captured_commands = {}

  -- Helper function to find a command by name
  local function find_command(name)
    for _, cmd in ipairs(captured_commands) do
      if cmd.name == name then
        return cmd
      end
    end
    return nil
  end

  before_each(function()
    helpers.mock_vim()
    captured_commands = {}

    -- Add vim.log.levels for notification level checks
    vim.log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } }

    -- Mock nvim_create_user_command to capture command registrations
    vim.api.nvim_create_user_command = function(name, callback, opts)
      table.insert(captured_commands, {
        name = name,
        callback = callback,
        opts = opts or {},
      })
    end

    -- Mock vim.notify (notifications are not asserted in these tests)
    vim.notify = function() end

    -- Clear cached modules to ensure fresh load
    package.loaded["markdown-links"] = nil
    package.loaded["plugin.markdown-links"] = nil
  end)

  after_each(function()
    helpers.cleanup_mocks()
    -- Reset the loaded guard (safely check if vim exists)
    if _G.vim and vim.g then
      vim.g.loaded_markdown_links = nil
    end
  end)

  describe("plugin loading guard", function()
    it("should set vim.g.loaded_markdown_links on load", function()
      -- Clear any existing value
      vim.g.loaded_markdown_links = nil
      assert.is_nil(vim.g.loaded_markdown_links)

      -- Load the plugin
      dofile("plugin/markdown-links.lua")

      -- Should be set to true
      assert.is_true(vim.g.loaded_markdown_links)
    end)

    it("should prevent double-loading via vim.g.loaded_markdown_links guard", function()
      -- First load - should register commands
      vim.g.loaded_markdown_links = nil
      dofile("plugin/markdown-links.lua")
      local first_load_count = #captured_commands
      assert.is_true(first_load_count > 0)

      -- Clear captured commands
      captured_commands = {}

      -- Second load - should not register commands due to guard
      dofile("plugin/markdown-links.lua")
      local second_load_count = #captured_commands

      -- Should not have registered any commands on second load
      assert.equal(0, second_load_count)
    end)
  end)

  describe("command registration", function()
    before_each(function()
      vim.g.loaded_markdown_links = nil
      dofile("plugin/markdown-links.lua")
    end)

    it("should register MLInsertLink command", function()
      local cmd = find_command("MLInsertLink")
      assert.is_not_nil(cmd, "MLInsertLink command should be registered")
    end)

    it("should register MLFollowLink command", function()
      local cmd = find_command("MLFollowLink")
      assert.is_not_nil(cmd, "MLFollowLink command should be registered")
    end)

    it("should register MLNewFile command", function()
      local cmd = find_command("MLNewFile")
      assert.is_not_nil(cmd, "MLNewFile command should be registered")
    end)

    it("should register MLInsertLink with range = true", function()
      local cmd = find_command("MLInsertLink")
      assert.is_not_nil(cmd, "MLInsertLink command not found")
      assert.is_true(cmd.opts.range, "MLInsertLink should have range = true")
    end)

    it("should register MLInsertLink with correct description", function()
      local cmd = find_command("MLInsertLink")
      assert.is_not_nil(cmd, "MLInsertLink command not found")
      assert.equal("Insert markdown link", cmd.opts.desc)
    end)

    it("should register MLFollowLink with correct description", function()
      local cmd = find_command("MLFollowLink")
      assert.is_not_nil(cmd, "MLFollowLink command not found")
      assert.equal("Follow link under cursor", cmd.opts.desc)
    end)

    it("should register MLNewFile with nargs = '?", function()
      local cmd = find_command("MLNewFile")
      assert.is_not_nil(cmd, "MLNewFile command not found")
      assert.equal("?", cmd.opts.nargs)
    end)

    it("should register MLNewFile with complete = 'dir'", function()
      local cmd = find_command("MLNewFile")
      assert.is_not_nil(cmd, "MLNewFile command not found")
      assert.equal("dir", cmd.opts.complete)
    end)

    it("should register MLNewFile with correct description", function()
      local cmd = find_command("MLNewFile")
      assert.is_not_nil(cmd, "MLNewFile command not found")
      assert.equal("Create new note", cmd.opts.desc)
    end)
  end)

  describe("lazy loading", function()
    it("should not require markdown-links at plugin load time", function()
      vim.g.loaded_markdown_links = nil

      -- Track if markdown-links is required
      local required_at_load = false
      local original_require = _G.require
      _G.require = function(modname)
        if modname == "markdown-links" then
          required_at_load = true
        end
        return original_require(modname)
      end

      -- Load plugin
      dofile("plugin/markdown-links.lua")

      -- Restore require
      _G.require = original_require

      -- Should NOT have required markdown-links at plugin load time
      assert.is_false(required_at_load, "markdown-links should not be required at plugin load time")
    end)

    it("should require markdown-links when command is executed", function()
      vim.g.loaded_markdown_links = nil

      -- Load plugin
      dofile("plugin/markdown-links.lua")

      -- Find MLInsertLink command
      local ml_insert_link = find_command("MLInsertLink")
      assert.is_not_nil(ml_insert_link)

      -- Track if markdown-links is required during command execution
      local required_during_exec = false
      local original_require = _G.require
      _G.require = function(modname)
        if modname == "markdown-links" then
          required_during_exec = true
          return {
            insert_link = function() end,
            follow_link = function() end,
            new_file = function() end,
          }
        end
        return original_require(modname)
      end

      -- Execute command callback
      ml_insert_link.callback({})

      -- Restore require
      _G.require = original_require

      -- Should have required markdown-links during execution
      assert.is_true(required_during_exec, "markdown-links should be required when command is executed")
    end)
  end)

  describe("command delegation", function()
    -- Setup guard is tested in init.lua tests; commands delegate directly to the API.
    before_each(function()
      vim.g.loaded_markdown_links = nil
      dofile("plugin/markdown-links.lua")
    end)

    it("should call insert_link when MLInsertLink is executed", function()
      local ml_insert_link = find_command("MLInsertLink")
      local insert_link_called = false

      local original_require = _G.require
      _G.require = function(modname)
        if modname == "markdown-links" then
          return {
            insert_link = function(from_range)
              insert_link_called = true
            end,
          }
        end
        return original_require(modname)
      end

      ml_insert_link.callback({ range = 0 })
      _G.require = original_require

      assert.is_true(insert_link_called)
    end)

    it("should call follow_link when MLFollowLink is executed", function()
      local ml_follow_link = find_command("MLFollowLink")
      local follow_link_called = false

      local original_require = _G.require
      _G.require = function(modname)
        if modname == "markdown-links" then
          return {
            follow_link = function()
              follow_link_called = true
            end,
          }
        end
        return original_require(modname)
      end

      ml_follow_link.callback()
      _G.require = original_require

      assert.is_true(follow_link_called)
    end)

    it("should call new_file when MLNewFile is executed", function()
      local ml_new_file = find_command("MLNewFile")
      local new_file_called = false

      local original_require = _G.require
      _G.require = function(modname)
        if modname == "markdown-links" then
          return {
            new_file = function()
              new_file_called = true
            end,
          }
        end
        return original_require(modname)
      end

      ml_new_file.callback({ args = "" })
      _G.require = original_require

      assert.is_true(new_file_called)
    end)

    it("should call add_frontmatter when MLAddFrontmatter is executed", function()
      local ml_add_fm = find_command("MLAddFrontmatter")
      local add_fm_called = false

      local original_require = _G.require
      _G.require = function(modname)
        if modname == "markdown-links" then
          return {
            add_frontmatter = function()
              add_fm_called = true
            end,
          }
        end
        return original_require(modname)
      end

      ml_add_fm.callback()
      _G.require = original_require

      assert.is_true(add_fm_called)
    end)
  end)

  describe("keymaps", function()
    it("should not define any keymaps at plugin load time", function()
      vim.g.loaded_markdown_links = nil

      -- Track any keymap definitions
      local keymaps_defined = {}
      local original_keymap_set = nil

      -- Create vim.keymap if it doesn't exist
      if not vim.keymap then
        vim.keymap = {}
      end

      original_keymap_set = vim.keymap.set
      vim.keymap.set = function(mode, lhs, _rhs, _opts)
        table.insert(keymaps_defined, { mode = mode, lhs = lhs })
      end

      -- Load plugin
      dofile("plugin/markdown-links.lua")

      -- Restore keymap.set
      vim.keymap.set = original_keymap_set

      -- Should not have defined any keymaps
      assert.equal(0, #keymaps_defined, "Plugin should not define any keymaps at load time")
    end)

    it("should not define keymaps on setup with default config", function()
      -- Clear modules
      package.loaded["markdown-links"] = nil
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil

      -- Track autocmd creation
      local autocmds_created = {}
      vim.api.nvim_create_augroup = function(name, _opts)
        return name
      end
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(autocmds_created, { event = event, opts = opts })
      end

      local ml = require("markdown-links")
      ml.setup()

      -- With default config (all keymaps false), no autocmd should be created
      local keymap_autocmds = {}
      for _, ac in ipairs(autocmds_created) do
        if ac.opts and ac.opts.group == "MarkdownLinksKeymaps" then
          table.insert(keymap_autocmds, ac)
        end
      end
      assert.equal(0, #keymap_autocmds, "No keymap autocommands with default config")
    end)

    it("should create BufEnter autocmd when keymaps are configured", function()
      -- Clear modules
      package.loaded["markdown-links"] = nil
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil
      package.loaded["markdown-links.search"] = nil

      -- Track autocmd creation
      local autocmds_created = {}
      vim.api.nvim_create_augroup = function(name, _opts)
        return name
      end
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(autocmds_created, { event = event, opts = opts })
      end

      local ml = require("markdown-links")
      ml.setup({ keymaps = { follow_link = "<CR>" } })

      -- Should have created a BufEnter autocmd
      local found = false
      for _, ac in ipairs(autocmds_created) do
        if ac.event == "BufEnter" and ac.opts and ac.opts.group == "MarkdownLinksKeymaps" then
          found = true
          assert.equal("*.md", ac.opts.pattern)
        end
      end
      assert.is_true(found, "Should create BufEnter autocmd for keymaps")
    end)

    it("should not create autocmd when keymaps = false", function()
      -- Clear modules
      package.loaded["markdown-links"] = nil
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil

      local autocmds_created = {}
      vim.api.nvim_create_augroup = function(name, _opts)
        return name
      end
      vim.api.nvim_create_autocmd = function(event, opts)
        table.insert(autocmds_created, { event = event, opts = opts })
      end

      local ml = require("markdown-links")
      ml.setup({ keymaps = false })

      local keymap_autocmds = {}
      for _, ac in ipairs(autocmds_created) do
        if ac.opts and ac.opts.group == "MarkdownLinksKeymaps" then
          table.insert(keymap_autocmds, ac)
        end
      end
      assert.equal(0, #keymap_autocmds, "No keymap autocommands when keymaps = false")
    end)

    it("should set buffer-local keymaps for buffers inside vault", function()
      -- Clear modules
      package.loaded["markdown-links"] = nil
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil
      package.loaded["markdown-links.search"] = nil

      -- Mock vault detection
      local vault_dir = helpers.create_temp_vault()
      vim.fn.isdirectory = function()
        return 1
      end

      -- Capture the autocmd callback
      local autocmd_callback = nil
      vim.api.nvim_create_augroup = function(name, _opts)
        return name
      end
      vim.api.nvim_create_autocmd = function(event, opts)
        if event == "BufEnter" and opts.group == "MarkdownLinksKeymaps" then
          autocmd_callback = opts.callback
        end
      end

      -- Track keymap.set calls
      local keymaps_set = {}
      vim.keymap.set = function(mode, lhs, rhs, opts)
        table.insert(keymaps_set, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
      end

      -- Mock buf_get_name to return a path inside vault
      vim.api.nvim_buf_get_name = function(_bufnr)
        return vault_dir .. "/note.md"
      end

      local ml = require("markdown-links")
      ml.setup({
        vault_path = vault_dir,
        keymaps = { follow_link = "<CR>", insert_link = "<leader>ml" },
      })

      -- Simulate BufEnter by calling the callback
      assert.is_not_nil(autocmd_callback, "Autocmd callback should be set")
      autocmd_callback({ buf = 1 })

      -- Should have set keymaps (follow_link in n, insert_link in n + v)
      assert.is_true(#keymaps_set >= 3, "Should set at least 3 keymaps (follow n, insert n, insert v)")

      -- Verify buffer-local option
      for _, km in ipairs(keymaps_set) do
        assert.equal(1, km.opts.buffer, "Keymaps should be buffer-local")
      end
    end)

    it("should use command string for visual mode insert_link keymap", function()
      -- Regression test: visual mode must use ":MLInsertLink<CR>" (string),
      -- NOT a function callback. A function callback runs while visual mode
      -- is still active, so '< and '> marks contain stale values from
      -- the previous selection instead of the current one.
      package.loaded["markdown-links"] = nil
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil
      package.loaded["markdown-links.search"] = nil

      local vault_dir = helpers.create_temp_vault()
      vim.fn.isdirectory = function()
        return 1
      end

      local autocmd_callback = nil
      vim.api.nvim_create_augroup = function(name, _opts)
        return name
      end
      vim.api.nvim_create_autocmd = function(event, opts)
        if event == "BufEnter" and opts.group == "MarkdownLinksKeymaps" then
          autocmd_callback = opts.callback
        end
      end

      local keymaps_set = {}
      vim.keymap.set = function(mode, lhs, rhs, opts)
        table.insert(keymaps_set, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
      end

      vim.api.nvim_buf_get_name = function(_bufnr)
        return vault_dir .. "/note.md"
      end

      local ml = require("markdown-links")
      ml.setup({
        vault_path = vault_dir,
        keymaps = { insert_link = "<leader>ml" },
      })

      autocmd_callback({ buf = 1 })

      -- Find the visual mode insert_link mapping
      local visual_mapping = nil
      for _, km in ipairs(keymaps_set) do
        if km.mode == "v" and km.lhs == "<leader>ml" then
          visual_mapping = km
          break
        end
      end

      assert.is_not_nil(visual_mapping, "Visual mode insert_link keymap should exist")
      assert.equal(
        "string",
        type(visual_mapping.rhs),
        "Visual mode rhs must be a string command, not a function (functions get stale '< '> marks)"
      )
      assert.equal(
        ":MLInsertLink<CR>",
        visual_mapping.rhs,
        "Visual mode should delegate to :MLInsertLink command for correct range handling"
      )
    end)

    it("should NOT set keymaps for buffers with empty path", function()
      -- Clear modules
      package.loaded["markdown-links"] = nil
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil
      package.loaded["markdown-links.search"] = nil

      local vault_dir = helpers.create_temp_vault()
      vim.fn.isdirectory = function()
        return 1
      end

      -- Capture the autocmd callback
      local autocmd_callback = nil
      vim.api.nvim_create_augroup = function(name, _opts)
        return name
      end
      vim.api.nvim_create_autocmd = function(event, opts)
        if event == "BufEnter" and opts.group == "MarkdownLinksKeymaps" then
          autocmd_callback = opts.callback
        end
      end

      -- Track keymap.set calls
      local keymaps_set = {}
      vim.keymap.set = function(mode, lhs, _rhs, opts)
        table.insert(keymaps_set, { mode = mode, lhs = lhs, opts = opts })
      end

      -- Mock buf_get_name to return empty string (unnamed buffer)
      vim.api.nvim_buf_get_name = function(_bufnr)
        return ""
      end

      local ml = require("markdown-links")
      ml.setup({
        vault_path = vault_dir,
        keymaps = { follow_link = "<CR>" },
      })

      -- Simulate BufEnter
      assert.is_not_nil(autocmd_callback)
      autocmd_callback({ buf = 1 })

      -- Should NOT have set any keymaps (empty buf_path causes early return)
      assert.equal(0, #keymaps_set, "Should not set keymaps for unnamed buffers")
    end)

    it("should set new_file keymap when configured", function()
      -- Clear modules
      package.loaded["markdown-links"] = nil
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil
      package.loaded["markdown-links.search"] = nil

      local vault_dir = helpers.create_temp_vault()
      vim.fn.isdirectory = function()
        return 1
      end

      local autocmd_callback = nil
      vim.api.nvim_create_augroup = function(name, _opts)
        return name
      end
      vim.api.nvim_create_autocmd = function(event, opts)
        if event == "BufEnter" and opts.group == "MarkdownLinksKeymaps" then
          autocmd_callback = opts.callback
        end
      end

      local keymaps_set = {}
      vim.keymap.set = function(mode, lhs, rhs, opts)
        table.insert(keymaps_set, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
      end

      vim.api.nvim_buf_get_name = function(_bufnr)
        return vault_dir .. "/note.md"
      end

      local ml = require("markdown-links")
      ml.setup({
        vault_path = vault_dir,
        keymaps = { new_file = "<leader>mn" },
      })

      assert.is_not_nil(autocmd_callback)
      autocmd_callback({ buf = 1 })

      -- Should have set the new_file keymap in normal mode
      local found_new_file = false
      for _, km in ipairs(keymaps_set) do
        if km.mode == "n" and km.lhs == "<leader>mn" then
          found_new_file = true
          assert.is_function(km.rhs)
          assert.equal(1, km.opts.buffer)
        end
      end
      assert.is_true(found_new_file, "Should set new_file keymap")
    end)

    it("should set add_frontmatter keymap when configured", function()
      -- Clear modules
      package.loaded["markdown-links"] = nil
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil
      package.loaded["markdown-links.search"] = nil

      local vault_dir = helpers.create_temp_vault()
      vim.fn.isdirectory = function()
        return 1
      end

      local autocmd_callback = nil
      vim.api.nvim_create_augroup = function(name, _opts)
        return name
      end
      vim.api.nvim_create_autocmd = function(event, opts)
        if event == "BufEnter" and opts.group == "MarkdownLinksKeymaps" then
          autocmd_callback = opts.callback
        end
      end

      local keymaps_set = {}
      vim.keymap.set = function(mode, lhs, rhs, opts)
        table.insert(keymaps_set, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
      end

      vim.api.nvim_buf_get_name = function(_bufnr)
        return vault_dir .. "/note.md"
      end

      local ml = require("markdown-links")
      ml.setup({
        vault_path = vault_dir,
        keymaps = { add_frontmatter = "<leader>mf" },
      })

      assert.is_not_nil(autocmd_callback)
      autocmd_callback({ buf = 1 })

      -- Should have set the add_frontmatter keymap in normal mode
      local found_add_fm = false
      for _, km in ipairs(keymaps_set) do
        if km.mode == "n" and km.lhs == "<leader>mf" then
          found_add_fm = true
          assert.is_function(km.rhs)
          assert.equal(1, km.opts.buffer)
        end
      end
      assert.is_true(found_add_fm, "Should set add_frontmatter keymap")
    end)

    it("should set all 4 keymaps when all configured", function()
      -- Clear modules
      package.loaded["markdown-links"] = nil
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil
      package.loaded["markdown-links.search"] = nil

      local vault_dir = helpers.create_temp_vault()
      vim.fn.isdirectory = function()
        return 1
      end

      local autocmd_callback = nil
      vim.api.nvim_create_augroup = function(name, _opts)
        return name
      end
      vim.api.nvim_create_autocmd = function(event, opts)
        if event == "BufEnter" and opts.group == "MarkdownLinksKeymaps" then
          autocmd_callback = opts.callback
        end
      end

      local keymaps_set = {}
      vim.keymap.set = function(mode, lhs, rhs, opts)
        table.insert(keymaps_set, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
      end

      vim.api.nvim_buf_get_name = function(_bufnr)
        return vault_dir .. "/note.md"
      end

      local ml = require("markdown-links")
      ml.setup({
        vault_path = vault_dir,
        keymaps = {
          follow_link = "<CR>",
          insert_link = "<leader>ml",
          new_file = "<leader>mn",
          add_frontmatter = "<leader>mf",
        },
      })

      assert.is_not_nil(autocmd_callback)
      autocmd_callback({ buf = 1 })

      -- follow_link (n) + insert_link (n + v) + new_file (n) + add_frontmatter (n) = 5 keymaps
      assert.equal(5, #keymaps_set, "Should set 5 keymaps (follow n, insert n+v, new_file n, add_fm n)")
    end)

    it("should NOT set keymaps for buffers outside vault", function()
      -- Clear modules
      package.loaded["markdown-links"] = nil
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil
      package.loaded["markdown-links.search"] = nil

      local vault_dir = helpers.create_temp_vault()
      vim.fn.isdirectory = function()
        return 1
      end

      -- Capture the autocmd callback
      local autocmd_callback = nil
      vim.api.nvim_create_augroup = function(name, _opts)
        return name
      end
      vim.api.nvim_create_autocmd = function(event, opts)
        if event == "BufEnter" and opts.group == "MarkdownLinksKeymaps" then
          autocmd_callback = opts.callback
        end
      end

      -- Track keymap.set calls
      local keymaps_set = {}
      vim.keymap.set = function(mode, lhs, _rhs, opts)
        table.insert(keymaps_set, { mode = mode, lhs = lhs, opts = opts })
      end

      -- Mock buf_get_name to return a path OUTSIDE vault
      vim.api.nvim_buf_get_name = function(_bufnr)
        return "/some/other/dir/note.md"
      end

      local ml = require("markdown-links")
      ml.setup({
        vault_path = vault_dir,
        keymaps = { follow_link = "<CR>" },
      })

      -- Simulate BufEnter
      assert.is_not_nil(autocmd_callback)
      autocmd_callback({ buf = 1 })

      -- Should NOT have set any keymaps
      assert.equal(0, #keymaps_set, "Should not set keymaps for buffers outside vault")
    end)
  end)

  describe("command callbacks", function()
    before_each(function()
      vim.g.loaded_markdown_links = nil
      dofile("plugin/markdown-links.lua")
    end)

    it("should pass path argument to new_file when provided", function()
      -- Find MLNewFile command
      local ml_new_file = find_command("MLNewFile")

      local received_path = nil

      -- Mock require to capture path argument
      local original_require = _G.require
      _G.require = function(modname)
        if modname == "markdown-links" then
          return {
            new_file = function(path)
              received_path = path
            end,
          }
        end
        return original_require(modname)
      end

      -- Execute command with path argument
      ml_new_file.callback({ args = "/path/to/notes" })

      -- Restore require
      _G.require = original_require

      -- Should have passed the path
      assert.equal("/path/to/notes", received_path)
    end)

    it("should pass nil to new_file when no path argument provided", function()
      -- Find MLNewFile command
      local ml_new_file = find_command("MLNewFile")

      local received_path = "not-nil"

      -- Mock require to capture path argument
      local original_require = _G.require
      _G.require = function(modname)
        if modname == "markdown-links" then
          return {
            new_file = function(path)
              received_path = path
            end,
          }
        end
        return original_require(modname)
      end

      -- Execute command with empty args
      ml_new_file.callback({ args = "" })

      -- Restore require
      _G.require = original_require

      -- Should have passed nil
      assert.is_nil(received_path)
    end)

    it("should handle whitespace-only args as nil", function()
      -- Find MLNewFile command
      local ml_new_file = find_command("MLNewFile")

      local received_path = "not-nil"

      -- Mock require to capture path argument
      local original_require = _G.require
      _G.require = function(modname)
        if modname == "markdown-links" then
          return {
            new_file = function(path)
              received_path = path
            end,
          }
        end
        return original_require(modname)
      end

      -- Execute command with whitespace-only args
      -- Note: Neovim strips trailing whitespace, so this tests the edge case
      ml_new_file.callback({ args = "   " })

      -- Restore require
      _G.require = original_require

      -- Whitespace-only args should be treated as empty and converted to nil
      assert.is_nil(received_path)
    end)
  end)
end)
