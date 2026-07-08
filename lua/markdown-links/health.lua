--- :checkhealth support for markdown-links
--- Run with :checkhealth markdown-links
---@module 'markdown-links.health'

local M = {}

function M.check()
  vim.health.start("markdown-links")

  -- External tools used by search.lua
  if vim.fn.executable("fd") == 1 or vim.fn.executable("fdfind") == 1 then
    vim.health.ok("fd/fdfind found in PATH")
  else
    vim.health.error("fd/fdfind not found in PATH (required for note search)")
  end

  if vim.fn.executable("rg") == 1 then
    vim.health.ok("rg found in PATH")
  else
    vim.health.error("rg not found in PATH (required for link following)")
  end

  local cfg = require("markdown-links")._get_config()
  if not cfg then
    vim.health.warn("setup() has not been called")
    return
  end
  vim.health.ok("setup() called")

  if #cfg.vault_path == 0 then
    vim.health.warn("no vault_path configured")
  end
  for _, path in ipairs(cfg.vault_path) do
    if vim.fn.isdirectory(path) == 1 then
      vim.health.ok("vault_path exists: " .. path)
    else
      vim.health.error("vault_path does not exist or is not a directory: " .. path)
    end
  end
end

return M
