-- Tests for config validation and setup (fn-1.1)
local helpers = require("tests.init")

describe("config", function()
  local config

  before_each(function()
    helpers.mock_vim()
    -- Clear any cached module to get fresh state
    package.loaded["markdown-links.config"] = nil
    config = require("markdown-links.config")
  end)

  after_each(function()
    package.loaded["markdown-links.config"] = nil
    helpers.cleanup_mocks()
  end)

  describe("defaults", function()
    it("should export a defaults table", function()
      assert.is_table(config.defaults)
    end)

    it("should have vault_path as empty table", function()
      assert.is_table(config.defaults.vault_path)
      assert.equal(0, #config.defaults.vault_path)
    end)

    it("should have open_mode as 'edit'", function()
      assert.equal("edit", config.defaults.open_mode)
    end)

    it("should have picker_display as 'title_with_path'", function()
      assert.equal("title_with_path", config.defaults.picker_display)
    end)

    it("should have exclude_dirs as table with .git and .obsidian", function()
      assert.is_table(config.defaults.exclude_dirs)
      assert.equal(2, #config.defaults.exclude_dirs)
      assert.equal(".git", config.defaults.exclude_dirs[1])
      assert.equal(".obsidian", config.defaults.exclude_dirs[2])
    end)

    it("should have keymaps as table with all false values", function()
      assert.is_table(config.defaults.keymaps)
      assert.is_false(config.defaults.keymaps.follow_link)
      assert.is_false(config.defaults.keymaps.insert_link)
      assert.is_false(config.defaults.keymaps.new_file)
      assert.is_false(config.defaults.keymaps.add_frontmatter)
    end)

    it("should have oil_create_hook as false", function()
      assert.is_false(config.defaults.oil_create_hook)
    end)

    it("should export all 6 config options", function()
      local keys = {}
      for k, _ in pairs(config.defaults) do
        keys[k] = true
      end
      assert.is_true(keys.vault_path)
      assert.is_true(keys.open_mode)
      assert.is_true(keys.picker_display)
      assert.is_true(keys.exclude_dirs)
      assert.is_true(keys.oil_create_hook)
      assert.is_true(keys.keymaps)
    end)
  end)

  describe("validate", function()
    -- vault_path validation
    describe("vault_path", function()
      it("should convert string vault_path to array", function()
        local vault = helpers.create_temp_vault()
        -- Mock isdirectory to return 1 for our temp vault
        vim.fn.isdirectory = function(_)
          return 1
        end
        local result = config.validate({ vault_path = vault })
        assert.is_table(result.vault_path)
        assert.equal(1, #result.vault_path)
      end)

      it("should accept table of strings for vault_path", function()
        local vault1 = helpers.create_temp_vault()
        local vault2 = helpers.create_temp_vault()
        vim.fn.isdirectory = function(_)
          return 1
        end
        local result = config.validate({ vault_path = { vault1, vault2 } })
        assert.is_table(result.vault_path)
        assert.equal(2, #result.vault_path)
      end)

      it("should expand ~ in vault_path via vim.fs.normalize", function()
        local home = os.getenv("HOME") or "/home/user"
        vim.fn.isdirectory = function(_)
          return 1
        end
        vim.fs.normalize = function(path)
          return path:gsub("^~", home)
        end
        local result = config.validate({ vault_path = "~/notes" })
        assert.is_table(result.vault_path)
        -- Should not start with ~
        assert.not_matches("^~", result.vault_path[1])
        -- Should start with home dir
        assert.matches("^" .. home:gsub("%-", "%%-"), result.vault_path[1])
      end)

      it("should accept vault_path that does not exist (existence checked lazily)", function()
        vim.fn.isdirectory = function(_)
          return 0
        end
        local result = config.validate({ vault_path = "/nonexistent/path" })
        assert.equal(1, #result.vault_path)
        assert.equal("/nonexistent/path", result.vault_path[1])
      end)

      it("missing_vaults should list nonexistent directories", function()
        vim.fn.isdirectory = function(path)
          return path == "/exists" and 1 or 0
        end
        local missing = config.missing_vaults({ "/exists", "/gone" })
        assert.same({ "/gone" }, missing)
      end)

      it("should accept empty vault_path table", function()
        local result = config.validate({ vault_path = {} })
        assert.is_table(result.vault_path)
        assert.equal(0, #result.vault_path)
      end)
    end)

    -- open_mode validation
    describe("open_mode", function()
      it("should accept valid open_mode values", function()
        local valid = { "edit", "vsplit", "split", "tabedit" }
        for _, mode in ipairs(valid) do
          local result = config.validate({ vault_path = {}, open_mode = mode })
          assert.equal(mode, result.open_mode)
        end
      end)

      it("should reject invalid open_mode value", function()
        local ok, err = pcall(config.validate, { vault_path = {}, open_mode = "badval" })
        assert.is_false(ok)
        assert.matches("open_mode", err)
        assert.matches("badval", err)
      end)
    end)

    -- exclude_dirs validation
    describe("exclude_dirs", function()
      it("should accept valid exclude_dirs table", function()
        local result = config.validate({
          vault_path = {},
          exclude_dirs = { ".git", "node_modules" },
        })
        assert.is_table(result.exclude_dirs)
        assert.equal(2, #result.exclude_dirs)
      end)

      it("should accept empty exclude_dirs", function()
        local result = config.validate({ vault_path = {}, exclude_dirs = {} })
        assert.is_table(result.exclude_dirs)
        assert.equal(0, #result.exclude_dirs)
      end)

    end)

    -- keymaps validation
    describe("keymaps", function()
      it("should default to table with all false values", function()
        local result = config.validate({ vault_path = {} })
        assert.is_table(result.keymaps)
        assert.is_false(result.keymaps.follow_link)
        assert.is_false(result.keymaps.insert_link)
        assert.is_false(result.keymaps.new_file)
        assert.is_false(result.keymaps.add_frontmatter)
      end)

      it("should accept false to disable all keymaps", function()
        local result = config.validate({ vault_path = {}, keymaps = false })
        assert.is_false(result.keymaps)
      end)

      it("should accept table with string values", function()
        local result = config.validate({
          vault_path = {},
          keymaps = { follow_link = "<CR>", insert_link = "<leader>ml" },
        })
        assert.is_table(result.keymaps)
        assert.equal("<CR>", result.keymaps.follow_link)
        assert.equal("<leader>ml", result.keymaps.insert_link)
        assert.is_false(result.keymaps.new_file)
        assert.is_false(result.keymaps.add_frontmatter)
      end)

      it("should accept table with mixed string and false values", function()
        local result = config.validate({
          vault_path = {},
          keymaps = { follow_link = "<CR>", insert_link = false },
        })
        assert.equal("<CR>", result.keymaps.follow_link)
        assert.is_false(result.keymaps.insert_link)
      end)

    end)

    -- nil keymaps should include add_frontmatter
    describe("nil keymaps fallback", function()
      it("should include add_frontmatter = false when keymaps is nil", function()
        local result = config.validate({ vault_path = {} })
        assert.is_table(result.keymaps)
        assert.is_false(result.keymaps.add_frontmatter)
      end)
    end)

    -- nil/missing values
    describe("nil and missing values", function()
      it("should pass validation with only vault_path", function()
        local result = config.validate({ vault_path = {} })
        assert.is_table(result)
      end)

      it("should preserve nil open_mode without error", function()
        local result = config.validate({ vault_path = {}, open_mode = nil })
        assert.is_table(result)
      end)
    end)
  end)
end)

describe("resolve_open_mode", function()
  local config

  before_each(function()
    helpers.mock_vim()
    package.loaded["markdown-links.config"] = nil
    config = require("markdown-links.config")
  end)

  after_each(function()
    package.loaded["markdown-links.config"] = nil
    helpers.cleanup_mocks()
  end)

  it("should return 'edit' for nil", function()
    assert.equal("edit", config.resolve_open_mode(nil))
  end)

  it("should return 'edit' for invalid mode", function()
    assert.equal("edit", config.resolve_open_mode("!rm -rf /"))
  end)

  it("should pass through valid modes", function()
    assert.equal("edit", config.resolve_open_mode("edit"))
    assert.equal("vsplit", config.resolve_open_mode("vsplit"))
    assert.equal("split", config.resolve_open_mode("split"))
    assert.equal("tabedit", config.resolve_open_mode("tabedit"))
  end)
end)

describe("init", function()
  local ml

  before_each(function()
    helpers.mock_vim()
    -- Add vim.log.levels for notification level checks
    vim.log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } }
    -- Clear cached modules
    package.loaded["markdown-links.config"] = nil
    package.loaded["markdown-links.init"] = nil
    package.loaded["markdown-links"] = nil
    ml = require("markdown-links")
  end)

  after_each(function()
    package.loaded["markdown-links.config"] = nil
    package.loaded["markdown-links.init"] = nil
    package.loaded["markdown-links"] = nil
    helpers.cleanup_mocks()
  end)

  describe("setup", function()
    it("should be callable with no arguments", function()
      -- With empty vault_path (default), no directory validation needed
      assert.has_no.errors(function()
        ml.setup()
      end)
    end)

    it("should mark plugin as setup", function()
      ml.setup()
      assert.is_not_nil(ml._get_config())
    end)

    it("should store validated config", function()
      ml.setup()
      local cfg = ml._get_config()
      assert.is_table(cfg)
      assert.equal("edit", cfg.open_mode)
      assert.equal("title_with_path", cfg.picker_display)
    end)

    it("should accept user config overrides", function()
      ml.setup({ open_mode = "vsplit" })
      local cfg = ml._get_config()
      assert.equal("vsplit", cfg.open_mode)
    end)

    it("should replace config on re-setup (not merge)", function()
      ml.setup({ open_mode = "vsplit" })
      local cfg1 = ml._get_config()
      assert.equal("vsplit", cfg1.open_mode)

      -- Re-setup with different config
      ml.setup({ open_mode = "split" })
      local cfg2 = ml._get_config()
      -- open_mode should be the new value
      assert.equal("split", cfg2.open_mode)
    end)

    it("should detect Telescope availability", function()
      -- Mock telescope as available
      helpers.mock_telescope()
      -- Need to clear and re-require to pick up telescope mock
      package.loaded["markdown-links.config"] = nil
      package.loaded["markdown-links.init"] = nil
      package.loaded["markdown-links"] = nil
      ml = require("markdown-links")
      ml.setup()
      assert.is_true(ml._has_telescope())
    end)

    it("should handle missing Telescope gracefully", function()
      -- Telescope is not mocked, so pcall(require, 'telescope') should fail
      package.loaded["telescope"] = nil
      ml.setup()
      assert.is_false(ml._has_telescope())
    end)

    it("should be callable multiple times", function()
      assert.has_no.errors(function()
        ml.setup()
        ml.setup({ open_mode = "vsplit" })
        ml.setup()
      end)
      assert.is_not_nil(ml._get_config())
    end)

    it("should reject non-table opts with a clear error", function()
      local ok, err = pcall(ml.setup, "bad")
      assert.is_false(ok)
      assert.matches("expects a table", err)
    end)
  end)

  describe("public API stubs", function()
    it("should export insert_link function", function()
      assert.is_function(ml.insert_link)
    end)

    it("should export follow_link function", function()
      assert.is_function(ml.follow_link)
    end)

    it("should export new_file function", function()
      assert.is_function(ml.new_file)
    end)

    it("should warn if insert_link called before setup", function()
      ml.insert_link()
      local notif = helpers.get_last_notification()
      assert.is_not_nil(notif)
      assert.matches("setup", notif.msg)
    end)

    it("should warn if follow_link called before setup", function()
      ml.follow_link()
      local notif = helpers.get_last_notification()
      assert.is_not_nil(notif)
      assert.matches("setup", notif.msg)
    end)

    it("should warn if new_file called before setup", function()
      ml.new_file()
      local notif = helpers.get_last_notification()
      assert.is_not_nil(notif)
      assert.matches("setup", notif.msg)
    end)

    it("should warn once about missing vault dirs on first use, not at setup", function()
      vim.fn.isdirectory = function(_)
        return 0
      end
      local notifications = {}
      vim.notify = function(msg, _)
        table.insert(notifications, msg)
      end

      ml.setup({ vault_path = "/gone" })
      assert.equal(0, #notifications)

      ml.follow_link()
      ml.follow_link()
      local warn_count = 0
      for _, msg in ipairs(notifications) do
        if msg:match("vault_path does not exist") then
          warn_count = warn_count + 1
        end
      end
      assert.equal(1, warn_count)
    end)
  end)

  describe("_get_config", function()
    it("should return nil before setup", function()
      assert.is_nil(ml._get_config())
    end)

    it("should return config after setup", function()
      ml.setup()
      assert.is_table(ml._get_config())
    end)
  end)
end)
