# markdown-links.nvim

A minimalist note-linking system for Neovim. Notes are connected through
unique frontmatter IDs, so files can be renamed or moved without breaking
links.

## How it works

Every note gets a YAML frontmatter block with a unique ID:

```markdown
---
id: 20260222-143000-a1b2
---

Your note content here.
```

Links between notes use the bare ID as the URL:

```markdown
See [Related Topic](20260222-143000-a1b2) for more details.
```

When you follow a link, the plugin searches your vault for the file whose
frontmatter contains that ID. Since the link target is an ID (not a file
path), you can rename or reorganize files freely.

The ID format is `YYYYMMDD-HHMMSS-XXXX` — a UTC timestamp plus 4 random
alphanumeric characters.

## Requirements

- Neovim >= 0.10
- [fd](https://github.com/sharkdp/fd) — for searching vault directories
- [ripgrep](https://github.com/BurntSushi/ripgrep) — for resolving IDs to files via frontmatter
- Optional: [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) — for a fuzzy picker (falls back to `vim.ui.select`)
- Optional: [oil.nvim](https://github.com/stevearc/oil.nvim) — for auto-adding frontmatter to new files

## Installation

### lazy.nvim

```lua
{
  "your-username/markdown-links.nvim",
  ft = "markdown",
  opts = {
    vault_path = "~/notes",
  },
}
```

### Manual

Clone the repository into your Neovim packages directory:

```
git clone https://github.com/your-username/markdown-links.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/markdown-links.nvim
```

Then add to your config:

```lua
require("markdown-links").setup({
  vault_path = "~/notes",
})
```

## Configuration

```lua
require("markdown-links").setup({
  -- Path to your note vault. String or list of strings.
  -- Paths are expanded on setup. Existence is not checked at startup —
  -- a missing directory produces a one-time warning on first use.
  vault_path = {},

  -- How to open files when following links.
  -- "edit", "vsplit", "split", or "tabedit"
  open_mode = "edit",

  -- How notes are displayed in the picker.
  -- "filename"         — just the filename
  -- "full_path"        — directory/filename
  -- "filename_with_path" — filename padded + directory
  -- "title_with_path"  — title (filename without .md) padded + directory
  picker_display = "title_with_path",

  -- Directories to exclude from vault search.
  exclude_dirs = { ".git", ".obsidian" },

  -- Auto-add frontmatter IDs to .md files created via Oil.nvim.
  -- Requires Oil.nvim to be installed; ignored otherwise.
  oil_create_hook = false,

  -- Keymaps scoped to vault buffers only.
  -- Set individual keys to a string (lhs) or false (disabled).
  -- Set the entire table to false to disable all keymaps.
  keymaps = {
    follow_link = false,
    insert_link = false,
    new_file = false,
    add_frontmatter = false,
  },
})
```

### Example with keymaps

```lua
require("markdown-links").setup({
  vault_path = "~/notes",
  open_mode = "edit",
  keymaps = {
    follow_link = "<CR>",
    insert_link = "<leader>mi",
    new_file = "<leader>mn",
    add_frontmatter = "<leader>mf",
  },
})
```

Keymaps are **vault-scoped** — they only activate in markdown buffers whose
file path is inside a configured vault directory.

## Commands

| Command            | Description                                  |
| ------------------ | -------------------------------------------- |
| `:MLFollowLink`    | Follow the link under the cursor             |
| `:MLInsertLink`    | Insert a link to a note (opens picker)       |
| `:MLNewFile [dir]` | Create a new note with a frontmatter ID      |
| `:MLAddFrontmatter`| Add a frontmatter ID to the current file     |

`:MLInsertLink` also works in visual mode — the selected text becomes the
link title.

`:MLNewFile` accepts an optional absolute directory path. Without it, the new
file is created in the current buffer's directory.

## Link following

When you run `:MLFollowLink`, the plugin:

1. Parses all markdown links on the current line (skipping image links)
2. Picks the link under the cursor, or the first link on the line
3. Strips any URL fragment (`#heading`)
4. Extracts the ID from the URL
5. Searches the vault for a file with a matching `id:` in its frontmatter
6. Opens the file (or shows a picker if multiple files match)

## Troubleshooting

Run `:checkhealth markdown-links` to verify your setup. It checks that
`fd`/`fdfind` and `rg` are in `PATH`, that `setup()` was called, and that
every configured `vault_path` exists.

A `vault_path` pointing to a missing directory (e.g. an unmounted drive)
does not block startup; the plugin warns once when you first use it.

## Oil.nvim integration

When `oil_create_hook = true`, any `.md` file you create through Oil's file
browser automatically gets a frontmatter block with a unique ID. This only
applies to files inside your configured vaults.
