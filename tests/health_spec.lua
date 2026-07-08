-- Tests for :checkhealth support (health.lua)
local helpers = require("tests.init")

describe("health", function()
  local health
  local reports

  local function clear_modules()
    package.loaded["markdown-links.health"] = nil
    package.loaded["markdown-links.config"] = nil
    package.loaded["markdown-links.init"] = nil
    package.loaded["markdown-links"] = nil
  end

  before_each(function()
    helpers.mock_vim()
    vim.log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } }
    -- Collect health report calls as { kind, message } pairs
    reports = {}
    vim.health = {
      start = function(name)
        table.insert(reports, { "start", name })
      end,
      ok = function(msg)
        table.insert(reports, { "ok", msg })
      end,
      warn = function(msg)
        table.insert(reports, { "warn", msg })
      end,
      error = function(msg)
        table.insert(reports, { "error", msg })
      end,
    }
    clear_modules()
    health = require("markdown-links.health")
  end)

  after_each(function()
    clear_modules()
    helpers.cleanup_mocks()
  end)

  local function find_report(kind, pattern)
    for _, r in ipairs(reports) do
      if r[1] == kind and r[2]:match(pattern) then
        return r
      end
    end
    return nil
  end

  it("should warn when setup() has not been called", function()
    health.check()
    assert.is_not_nil(find_report("warn", "setup%(%) has not been called"))
  end)

  it("should report ok for existing vault paths", function()
    require("markdown-links").setup({ vault_path = "/notes" })
    health.check()
    assert.is_not_nil(find_report("ok", "vault_path exists: /notes"))
  end)

  it("should report error for missing vault paths", function()
    require("markdown-links").setup({ vault_path = "/gone" })
    vim.fn.isdirectory = function(_)
      return 0
    end
    health.check()
    assert.is_not_nil(find_report("error", "vault_path does not exist.*: /gone"))
  end)

  it("should report ok for available fd and rg", function()
    health.check()
    assert.is_not_nil(find_report("ok", "fd/fdfind"))
    assert.is_not_nil(find_report("ok", "rg"))
  end)

  it("should report error when fd and rg are missing", function()
    vim.fn.executable = function(_)
      return 0
    end
    health.check()
    assert.is_not_nil(find_report("error", "fd/fdfind not found"))
    assert.is_not_nil(find_report("error", "rg not found"))
  end)

  it("should warn when no vault_path is configured", function()
    require("markdown-links").setup({})
    health.check()
    assert.is_not_nil(find_report("warn", "no vault_path configured"))
  end)
end)
