-- Tests for vault detection and file search (fn-1.4)
local helpers = require("tests.init")

describe("search", function()
  local search

  before_each(function()
    helpers.mock_vim()
    vim.log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } }
    -- Clear cached module to get fresh state
    package.loaded["markdown-links.search"] = nil
    search = require("markdown-links.search")
  end)

  after_each(function()
    package.loaded["markdown-links.search"] = nil
    helpers.cleanup_mocks()
  end)

  describe("detect_vault", function()
    it("should detect vault when buffer is inside a single vault", function()
      local result = search.detect_vault("/home/user/notes/file.md", { "/home/user/notes" })
      assert.equal("/home/user/notes", result)
    end)

    it("should return nil when buffer is outside all vaults", function()
      local result = search.detect_vault("/home/user/other/file.md", { "/home/user/notes" })
      assert.is_nil(result)
    end)

    it("should return longest match for nested vaults", function()
      local vaults = { "/home/user/notes", "/home/user/notes/work" }
      local result = search.detect_vault("/home/user/notes/work/project.md", vaults)
      assert.equal("/home/user/notes/work", result)
    end)

    it("should return longest match regardless of vault order", function()
      -- Reverse order: longer vault listed first
      local vaults = { "/home/user/notes/work", "/home/user/notes" }
      local result = search.detect_vault("/home/user/notes/work/project.md", vaults)
      assert.equal("/home/user/notes/work", result)
    end)

    it("should match shorter vault when file is not in nested vault", function()
      local vaults = { "/home/user/notes", "/home/user/notes/work" }
      local result = search.detect_vault("/home/user/notes/personal/diary.md", vaults)
      assert.equal("/home/user/notes", result)
    end)

    it("should not match vault path that is a prefix but not a directory boundary", function()
      -- /home/user/notes-extra should NOT match /home/user/notes
      local result = search.detect_vault("/home/user/notes-extra/file.md", { "/home/user/notes" })
      assert.is_nil(result)
    end)

    it("should handle multiple non-nested vaults", function()
      local vaults = { "/home/user/notes", "/home/user/work" }
      local result = search.detect_vault("/home/user/work/todo.md", vaults)
      assert.equal("/home/user/work", result)
    end)

    it("should return nil for empty vault_paths list", function()
      local result = search.detect_vault("/home/user/notes/file.md", {})
      assert.is_nil(result)
    end)

    it("should normalize paths via vim.fs.normalize", function()
      -- Our mock vim.fs.normalize expands ~ to home
      local home = os.getenv("HOME") or "/home/user"
      local result = search.detect_vault(home .. "/notes/file.md", { home .. "/notes" })
      assert.equal(home .. "/notes", result)
    end)

    it("should handle deeply nested file paths", function()
      local result = search.detect_vault("/home/user/notes/a/b/c/d/file.md", { "/home/user/notes" })
      assert.equal("/home/user/notes", result)
    end)

    it("should not match when buffer_path equals vault_path exactly (no trailing slash)", function()
      -- A buffer path that IS the vault directory itself should not match
      -- because we check for vault_path .. "/" prefix
      local result = search.detect_vault("/home/user/notes", { "/home/user/notes" })
      assert.is_nil(result)
    end)
  end)

  describe("search_vault", function()
    describe("tool selection", function()
      it("should use fd if available", function()
        local captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "fd" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return {}
        end
        vim.v.shell_error = 0

        search.search_vault("/home/user/notes", {})
        assert.is_not_nil(captured_cmd)
        assert.equal("fd", captured_cmd[1])
      end)

      it("should fall back to fdfind when fd is not available", function()
        local captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "fdfind" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return {}
        end
        vim.v.shell_error = 0

        search.search_vault("/home/user/notes", {})
        assert.is_not_nil(captured_cmd)
        assert.equal("fdfind", captured_cmd[1])
      end)

      it("should return empty table and notify when fd/fdfind is not available", function()
        vim.fn.executable = function(cmd)
          return 0
        end
        local notified = false
        vim.notify = function(msg, level)
          notified = true
          assert.matches("fd/fdfind not found", msg)
        end

        local result = search.search_vault("/home/user/notes", {})
        assert.same({}, result)
        assert.is_true(notified)
      end)
    end)

    describe("fd command building", function()
      local captured_cmd

      before_each(function()
        captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "fd" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return {}
        end
        vim.v.shell_error = 0
      end)

      it("should build command as argument list (not string)", function()
        search.search_vault("/home/user/notes", {})
        assert.is_table(captured_cmd)
      end)

      it("should include --extension md flag", function()
        search.search_vault("/home/user/notes", {})
        local has_extension = false
        for i, arg in ipairs(captured_cmd) do
          if arg == "--extension" and captured_cmd[i + 1] == "md" then
            has_extension = true
            break
          end
        end
        assert.is_true(has_extension, "Should include --extension md")
      end)

      it("should include --no-ignore and --hidden flags", function()
        search.search_vault("/home/user/notes", {})
        assert.is_true(vim.tbl_contains(captured_cmd, "--no-ignore"))
        assert.is_true(vim.tbl_contains(captured_cmd, "--hidden"))
      end)

      it("should include --exclude for each exclude_dirs entry", function()
        search.search_vault("/home/user/notes", { ".git", ".obsidian", "node_modules" })
        local exclude_count = 0
        for i, arg in ipairs(captured_cmd) do
          if arg == "--exclude" then
            exclude_count = exclude_count + 1
          end
        end
        assert.equal(3, exclude_count)
      end)

      it("should place exclude dir names after --exclude flags", function()
        search.search_vault("/home/user/notes", { ".git", ".obsidian" })
        local excludes = {}
        for i, arg in ipairs(captured_cmd) do
          if arg == "--exclude" and captured_cmd[i + 1] then
            table.insert(excludes, captured_cmd[i + 1])
          end
        end
        assert.same({ ".git", ".obsidian" }, excludes)
      end)

      it("should include vault_path as last argument", function()
        search.search_vault("/home/user/notes", {})
        assert.equal("/home/user/notes", captured_cmd[#captured_cmd])
      end)

      it("should include dot pattern before vault path", function()
        search.search_vault("/home/user/notes", {})
        assert.equal(".", captured_cmd[#captured_cmd - 1])
      end)
    end)

    describe("result handling", function()
      before_each(function()
        vim.fn.executable = function(cmd)
          if cmd == "fd" then
            return 1
          end
          return 0
        end
        vim.v.shell_error = 0
      end)

      it("should return file paths from systemlist", function()
        vim.fn.systemlist = function(cmd)
          return {
            "/home/user/notes/my-note-20260207-143055-a3f7.md",
            "/home/user/notes/another-20260208-100000-b2e8.md",
          }
        end

        local result = search.search_vault("/home/user/notes", {})
        assert.equal(2, #result)
        assert.equal("/home/user/notes/my-note-20260207-143055-a3f7.md", result[1])
        assert.equal("/home/user/notes/another-20260208-100000-b2e8.md", result[2])
      end)

      it("should return absolute file paths", function()
        vim.fn.systemlist = function(cmd)
          return { "/home/user/notes/file.md" }
        end

        local result = search.search_vault("/home/user/notes", {})
        assert.equal(1, #result)
        assert.is_truthy(result[1]:sub(1, 1) == "/", "Path should be absolute")
      end)

      it("should filter out empty strings from results", function()
        vim.fn.systemlist = function(cmd)
          return {
            "/home/user/notes/file.md",
            "",
            "/home/user/notes/other.md",
            "",
          }
        end

        local result = search.search_vault("/home/user/notes", {})
        assert.equal(2, #result)
      end)

      it("should return empty table on shell error", function()
        vim.fn.systemlist = function(cmd)
          return { "some error output" }
        end
        vim.v.shell_error = 1

        local result = search.search_vault("/home/user/notes", {})
        assert.same({}, result)
      end)

      it("should handle nil exclude_dirs by defaulting to empty table", function()
        vim.fn.systemlist = function(cmd)
          return {}
        end
        -- Should not error
        assert.has_no.errors(function()
          search.search_vault("/home/user/notes", nil)
        end)
      end)

    end)

    describe("search_files_by_frontmatter_id", function()
      it("finds file using rg", function()
        local captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "rg" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return { "/vault/My Note.md" }
        end
        vim.v.shell_error = 0

        local result = search.search_files_by_frontmatter_id("20260207-143055-a3f7", "/vault", {})
        assert.equal(1, #result)
        assert.equal("rg", captured_cmd[1])
        assert.is_true(vim.tbl_contains(captured_cmd, "-l"))
      end)

      it("returns empty table and notifies if rg not available", function()
        vim.fn.executable = function()
          return 0
        end
        local notified = false
        vim.notify = function(msg, level)
          notified = true
          assert.matches("rg not found in PATH", msg)
        end
        local result = search.search_files_by_frontmatter_id("20260207-143055-a3f7", "/vault", {})
        assert.same({}, result)
        assert.is_true(notified)
      end)

      it("returns empty table on shell error", function()
        vim.fn.executable = function(cmd)
          if cmd == "rg" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function()
          return { "error output" }
        end
        vim.v.shell_error = 1

        local result = search.search_files_by_frontmatter_id("20260207-143055-a3f7", "/vault", {})
        assert.same({}, result)
      end)

      it("builds command as argument list not string", function()
        local captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "rg" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return {}
        end
        vim.v.shell_error = 0

        search.search_files_by_frontmatter_id("20260207-143055-a3f7", "/vault; rm -rf /", {})
        assert.is_table(captured_cmd)
      end)

      it("respects exclude_dirs for rg", function()
        local captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "rg" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return {}
        end
        vim.v.shell_error = 0

        search.search_files_by_frontmatter_id("20260207-143055-a3f7", "/vault", { ".git", ".obsidian" })
        local globs = {}
        for i, arg in ipairs(captured_cmd) do
          if arg == "--glob" then
            table.insert(globs, captured_cmd[i + 1])
          end
        end
        assert.equal(2, #globs)
        assert.equal("!.git", globs[1])
        assert.equal("!.obsidian", globs[2])
      end)

      it("filters out empty strings from results", function()
        vim.fn.executable = function(cmd)
          if cmd == "rg" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function()
          return { "/vault/note.md", "", "/vault/other.md", "" }
        end
        vim.v.shell_error = 0

        local result = search.search_files_by_frontmatter_id("20260207-143055-a3f7", "/vault", {})
        assert.equal(2, #result)
      end)
    end)

    describe("frontmatter search pattern", function()
      it("should use anchored pattern ^id: ID$ for rg", function()
        local captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "rg" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return {}
        end
        vim.v.shell_error = 0

        search.search_files_by_frontmatter_id("20260207-143055-a3f7", "/vault", {})
        -- Pattern should be the 4th argument (after rg, -l, -m1)
        local pattern = nil
        for i, arg in ipairs(captured_cmd) do
          if arg == "-m1" then
            pattern = captured_cmd[i + 1]
            break
          end
        end
        assert.is_not_nil(pattern, "Should have a pattern argument after -m1")
        assert.equal("^id: 20260207-143055-a3f7$", pattern)
      end)

      it("should include -l and -m1 flags for rg", function()
        local captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "rg" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return {}
        end
        vim.v.shell_error = 0

        search.search_files_by_frontmatter_id("20260207-143055-a3f7", "/vault", {})
        assert.is_true(vim.tbl_contains(captured_cmd, "-l"))
        assert.is_true(vim.tbl_contains(captured_cmd, "-m1"))
      end)

      it("should construct pattern with ^ and $ anchors to prevent partial matches", function()
        -- The pattern passed to rg/grep should have ^ (start) and $ (end) anchors.
        -- This ensures "id: ID" in the middle of a line won't produce false positives.
        -- We verify the pattern string contains the correct anchors.
        local captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "rg" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return {}
        end
        vim.v.shell_error = 0

        search.search_files_by_frontmatter_id("20260207-143055-a3f7", "/vault", {})

        -- Find the pattern argument
        local pattern = nil
        for i, arg in ipairs(captured_cmd) do
          if arg == "-m1" then
            pattern = captured_cmd[i + 1]
            break
          end
        end

        assert.is_not_nil(pattern)
        -- Verify ^ anchor at start
        assert.equal("^", pattern:sub(1, 1), "Pattern should start with ^ anchor")
        -- Verify $ anchor at end
        assert.equal("$", pattern:sub(-1), "Pattern should end with $ anchor")
        -- Verify the ID is in the pattern
        assert.truthy(pattern:find("20260207%-143055%-a3f7", 1, false), "Pattern should contain the ID")
      end)

      it("should handle nil exclude_dirs by defaulting to empty table", function()
        local captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "rg" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return {}
        end
        vim.v.shell_error = 0

        -- Call with nil exclude_dirs
        assert.has_no.errors(function()
          search.search_files_by_frontmatter_id("20260207-143055-a3f7", "/vault", nil)
        end)
        assert.is_not_nil(captured_cmd)
        -- Should not have any --glob exclusions (nil defaults to {})
        local has_glob = false
        for _, arg in ipairs(captured_cmd) do
          if arg == "--glob" then
            has_glob = true
          end
        end
        assert.is_false(has_glob)
      end)
    end)

    describe("security", function()
      it("should pass command as argument list to systemlist, not a string", function()
        local captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "fd" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return {}
        end
        vim.v.shell_error = 0

        search.search_vault("/home/user/notes", {})
        assert.is_table(captured_cmd, "Command should be a table (argument list), not a string")
        assert.is_not.equal("string", type(captured_cmd), "Command must not be a string")
      end)

      it("should not concatenate user-controlled values into shell strings", function()
        local captured_cmd = nil
        vim.fn.executable = function(cmd)
          if cmd == "fd" then
            return 1
          end
          return 0
        end
        vim.fn.systemlist = function(cmd)
          captured_cmd = cmd
          return {}
        end
        vim.v.shell_error = 0

        -- Use a vault path with shell-injection characters
        search.search_vault("/home/user/notes; rm -rf /", { ".git; echo pwned" })
        -- The command should be a list, so shell metacharacters are just literal strings
        assert.is_table(captured_cmd)
        -- Verify the vault path is passed as a single element, not split
        assert.equal("/home/user/notes; rm -rf /", captured_cmd[#captured_cmd])
      end)

    end)
  end)
end)
