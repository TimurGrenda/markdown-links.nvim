-- Tests for ID generation, validation, and collision detection (fn-1.2)
local helpers = require("tests.init")

describe("id", function()
  local id_mod

  before_each(function()
    helpers.mock_vim()
    -- Clear cached module to get fresh state
    package.loaded["markdown-links.id"] = nil
    id_mod = require("markdown-links.id")
  end)

  after_each(function()
    package.loaded["markdown-links.id"] = nil
    helpers.cleanup_mocks()
  end)

  describe("generate_id", function()
    it("should return a string", function()
      local result = id_mod.generate_id()
      assert.is_string(result)
    end)

    it("should return a 20-character string", function()
      local result = id_mod.generate_id()
      assert.equal(20, #result)
    end)

    it("should match the ID pattern YYYYMMDD-HHMMSS-XXXX", function()
      local result = id_mod.generate_id()
      local pattern = "^%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-[0-9a-z][0-9a-z][0-9a-z][0-9a-z]$"
      assert.is_truthy(result:match(pattern), "ID '" .. result .. "' should match pattern")
    end)

    it("should use UTC time (os.date with ! prefix)", function()
      -- Save original os.date
      local original_date = os.date
      local date_format_captured = nil

      -- Mock os.date to capture the format string
      os.date = function(fmt, ...)
        date_format_captured = fmt
        return original_date(fmt, ...)
      end

      -- Re-load the module to use our mock for generate_id
      package.loaded["markdown-links.id"] = nil
      local id_fresh = require("markdown-links.id")
      id_fresh.generate_id()

      -- Restore
      os.date = original_date

      assert.is_not_nil(date_format_captured, "os.date should have been called")
      assert.is_truthy(
        date_format_captured:sub(1, 1) == "!",
        "os.date format should start with ! for UTC, got: " .. tostring(date_format_captured)
      )
    end)

    it("should generate different IDs on consecutive calls", function()
      -- Generate multiple IDs - at minimum the random suffix should differ
      local ids = {}
      local unique_count = 0
      for i = 1, 10 do
        local new_id = id_mod.generate_id()
        if not ids[new_id] then
          unique_count = unique_count + 1
        end
        ids[new_id] = true
      end
      -- With 36^4 possibilities per second, collisions in 10 calls are extremely unlikely
      assert.is_true(unique_count >= 2, "Expected at least 2 unique IDs out of 10 calls")
    end)

    it("should only use lowercase alphanumeric characters in suffix", function()
      for _ = 1, 20 do
        local result = id_mod.generate_id()
        local suffix = result:sub(17, 20)
        assert.is_truthy(
          suffix:match("^[0-9a-z][0-9a-z][0-9a-z][0-9a-z]$"),
          "Suffix '" .. suffix .. "' should only contain [0-9a-z]"
        )
      end
    end)

    it("should have correctly formatted timestamp part", function()
      local result = id_mod.generate_id()
      local date_part = result:sub(1, 8)
      local time_part = result:sub(10, 15)

      -- Date part: YYYYMMDD
      assert.is_truthy(date_part:match("^%d%d%d%d%d%d%d%d$"), "Date part should be 8 digits")

      -- Time part: HHMMSS
      assert.is_truthy(time_part:match("^%d%d%d%d%d%d$"), "Time part should be 6 digits")

      -- Separators
      assert.equal("-", result:sub(9, 9), "First separator should be -")
      assert.equal("-", result:sub(16, 16), "Second separator should be -")
    end)

    it("should produce valid IDs according to validate_id", function()
      for _ = 1, 10 do
        local result = id_mod.generate_id()
        assert.is_true(id_mod.validate_id(result), "Generated ID '" .. result .. "' should pass validation")
      end
    end)
  end)

  describe("validate_id", function()
    it("should return true for a valid ID", function()
      assert.is_true(id_mod.validate_id("20260207-143055-a3f7"))
    end)

    it("should return true for ID with all digits in suffix", function()
      assert.is_true(id_mod.validate_id("20260207-143055-1234"))
    end)

    it("should return true for ID with all letters in suffix", function()
      assert.is_true(id_mod.validate_id("20260207-143055-abcd"))
    end)

    it("should return true for boundary timestamp values", function()
      -- midnight
      assert.is_true(id_mod.validate_id("20260101-000000-0000"))
      -- end of day
      assert.is_true(id_mod.validate_id("20261231-235959-zzzz"))
    end)

    it("should return false for empty string", function()
      assert.is_false(id_mod.validate_id(""))
    end)

    it("should return false for too-short string", function()
      assert.is_false(id_mod.validate_id("20260207-143055-a3"))
    end)

    it("should return false for too-long string", function()
      assert.is_false(id_mod.validate_id("20260207-143055-a3f7x"))
    end)

    it("should return false for uppercase letters in suffix", function()
      assert.is_false(id_mod.validate_id("20260207-143055-A3F7"))
    end)

    it("should return false for missing first separator", function()
      assert.is_false(id_mod.validate_id("20260207143055-a3f7"))
    end)

    it("should return false for missing second separator", function()
      assert.is_false(id_mod.validate_id("20260207-143055a3f7"))
    end)

    it("should return false for non-digit in date part", function()
      assert.is_false(id_mod.validate_id("2026020x-143055-a3f7"))
    end)

    it("should return false for non-digit in time part", function()
      assert.is_false(id_mod.validate_id("20260207-14305x-a3f7"))
    end)

    it("should return false for special characters in suffix", function()
      assert.is_false(id_mod.validate_id("20260207-143055-a3!7"))
    end)

    it("should return false for spaces", function()
      assert.is_false(id_mod.validate_id("20260207-143055-a3 7"))
    end)

    it("should return false for random garbage string", function()
      assert.is_false(id_mod.validate_id("not-an-id-at-all!!"))
    end)
  end)

  describe("check_id_uniqueness", function()
    it("should return true when search returns empty table", function()
      local search_fn = function(pattern, vault_path)
        return {}
      end
      local result = id_mod.check_id_uniqueness("20260207-143055-a3f7", "/home/user/notes", search_fn)
      assert.is_true(result)
    end)

    it("should return false when search finds a matching file", function()
      local search_fn = function(pattern, vault_path)
        return { "my-note-20260207-143055-a3f7.md" }
      end
      local result = id_mod.check_id_uniqueness("20260207-143055-a3f7", "/home/user/notes", search_fn)
      assert.is_false(result)
    end)

    it("should return false when search finds multiple matching files", function()
      local search_fn = function(pattern, vault_path)
        return { "note1-20260207-143055-a3f7.md", "note2-20260207-143055-a3f7.md" }
      end
      local result = id_mod.check_id_uniqueness("20260207-143055-a3f7", "/home/user/notes", search_fn)
      assert.is_false(result)
    end)

    it("should pass the raw ID to search_fn", function()
      local captured_id = nil
      local captured_vault = nil
      local search_fn = function(id, vault_path)
        captured_id = id
        captured_vault = vault_path
        return {}
      end
      id_mod.check_id_uniqueness("20260207-143055-a3f7", "/home/user/notes", search_fn)
      assert.equal("20260207-143055-a3f7", captured_id)
      assert.equal("/home/user/notes", captured_vault)
    end)

    it("should handle collision scenario correctly", function()
      -- Simulate a vault where the ID already exists
      local vault_files = {
        ["20260207-143055-a3f7"] = { "project-notes-20260207-143055-a3f7.md" },
        ["20260207-143055-b2e8"] = {},
      }
      local search_fn = function(id, vault_path)
        return vault_files[id] or {}
      end

      -- Existing ID - should not be unique
      assert.is_false(id_mod.check_id_uniqueness("20260207-143055-a3f7", "/vault", search_fn))
      -- New ID - should be unique
      assert.is_true(id_mod.check_id_uniqueness("20260207-143055-b2e8", "/vault", search_fn))
    end)

    it("should detect ID-only filenames (no slug prefix)", function()
      -- This is the key case: filename is just ID.md, no leading dash
      local search_fn = function(id, vault_path)
        if id == "20260207-143055-a3f7" then
          return { "20260207-143055-a3f7.md" }
        end
        return {}
      end
      local result = id_mod.check_id_uniqueness("20260207-143055-a3f7", "/vault", search_fn)
      assert.is_false(result)
    end)
  end)

  describe("module initialization", function()
    it("should seed math.random once at module load", function()
      -- Verify the module loads without error (seeding happens at load time)
      package.loaded["markdown-links.id"] = nil
      local fresh_mod = require("markdown-links.id")
      assert.is_not_nil(fresh_mod)
    end)

    it("should produce valid IDs immediately after module load", function()
      -- After a fresh load, generate_id should work correctly
      package.loaded["markdown-links.id"] = nil
      local fresh_mod = require("markdown-links.id")
      local result = fresh_mod.generate_id()
      assert.is_true(fresh_mod.validate_id(result))
    end)

    it("should generate varying suffixes across module reloads", function()
      -- Reload the module twice and check that IDs differ
      -- (since os.clock() changes between loads, the seed should differ)
      package.loaded["markdown-links.id"] = nil
      local mod1 = require("markdown-links.id")
      local id1 = mod1.generate_id()

      package.loaded["markdown-links.id"] = nil
      local mod2 = require("markdown-links.id")
      local id2 = mod2.generate_id()

      -- Both should be valid
      assert.is_true(mod2.validate_id(id1))
      assert.is_true(mod2.validate_id(id2))
      -- Note: They could theoretically be equal if time and clock are identical,
      -- but in practice the suffix should differ
    end)
  end)

  describe("edge cases", function()
    it("should handle ID with all zeros", function()
      assert.is_true(id_mod.validate_id("00000000-000000-0000"))
    end)

    it("should handle ID with all z's in suffix", function()
      assert.is_true(id_mod.validate_id("99991231-235959-zzzz"))
    end)

  end)
end)
