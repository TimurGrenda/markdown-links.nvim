-- markdown-links.nvim - Command registration
-- This file is loaded automatically by Neovim's plugin system

-- Guard against double-loading
if vim.g.loaded_markdown_links then
  return
end
vim.g.loaded_markdown_links = true

-- Define commands with lazy loading (require deferred to callbacks)

-- Each command delegates to init.lua public API which already guards with state.is_setup check
vim.api.nvim_create_user_command("MLInsertLink", function(opts)
  require("markdown-links").insert_link((opts.range or 0) > 0)
end, {
  range = true,
  desc = "Insert markdown link",
})

vim.api.nvim_create_user_command("MLFollowLink", function()
  require("markdown-links").follow_link()
end, {
  desc = "Follow link under cursor",
})

vim.api.nvim_create_user_command("MLAddFrontmatter", function()
  require("markdown-links").add_frontmatter()
end, {
  desc = "Add frontmatter ID to current file",
})

vim.api.nvim_create_user_command("MLNewFile", function(opts)
  local path_arg = opts.args:match("^%s*(.-)%s*$") -- trim whitespace
  require("markdown-links").new_file(path_arg ~= "" and path_arg or nil)
end, {
  nargs = "?",
  complete = "dir",
  desc = "Create new note",
})
