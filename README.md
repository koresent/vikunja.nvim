# vikunja.nvim

Neovim plugin for [Vikunja](https://vikunja.io/) task management with a multi-column Kanban board, Kitty Graphics Protocol image support, floating Markdown task editor, and keyboard-driven task organization.

---

## Features

- **Kanban Board**: Multi-column layout in a dedicated Neovim tab displaying all project buckets side-by-side.
- **Asynchronous**: Built on Neovim's `vim.system()`. HTTP requests run in the background and never block the editor.
- **Keyboard Navigation**:
  - `h` / `l`: Move focus between columns.
  - `j` / `k`: Jump between cards in the current column.
  - `H` / `L`: Move cards across buckets with optimistic UI updates and background API sync.
  - `J` / `K`: Reorder cards up or down using fractional indexing.
  - `m`: Move a card to any bucket via an interactive selector.
  - `<Space>`: Toggle task completion status.
- **Markdown Task Editor**:
  - `<CR>` opens a centered floating window with full Markdown syntax.
  - YAML frontmatter controls title, completion status, priority, and due dates.
  - Saves directly to Vikunja via `:w` or `<C-s>`.
  - Converts Vikunja HTML to clean Markdown and back on save.
- **Image & Attachment Support (Kitty Graphics Protocol)**:
  - Renders task attachments in Ghostty, Kitty, and WezTerm via `snacks.image`.
  - Shows image count badges (` 1`) on cards.
  - Press `i` on any card to view attachments in a floating preview window.
  - Renders inline image previews inside the Markdown editor (`![alt](path)`).
  - Press `I` to upload and attach local files to a task.
- **Credential Storage**:
  - Zero hardcoded tokens required.
  - Resolves tokens in priority order:
    1. `$VIKUNJA_TOKEN` environment variable.
    2. Local secret file `~/.local/share/vikunja/token` (`chmod 600`).
    3. Interactive prompt (`:VikunjaSetToken` or first launch prompt) with optional local persistence.

---

## Requirements

- Neovim >= 0.10.0
- `curl`
- Nerd Font (for status icons and checkboxes)
- _Optional (for image preview)_: A terminal supporting Kitty Graphics Protocol (Ghostty, Kitty, WezTerm) and [`folke/snacks.nvim`](https://github.com/folke/snacks.nvim).

---

## Installation

### lazy.nvim

```lua
return {
  {
    "koresent/vikunja.nvim",
    dependencies = {
      "folke/snacks.nvim", -- optional: for Kitty graphics image rendering
    },
    cmd = { "Vikunja", "VikunjaKanban", "VikunjaProjects", "VikunjaSetToken" },
    keys = {
      { "<leader>vk", "<cmd>VikunjaKanban<cr>", desc = "Vikunja Kanban" },
      { "<leader>vp", "<cmd>VikunjaProjects<cr>", desc = "Vikunja Projects" },
    },
    opts = {
      base_url = "https://vikunja.example.com/api/v1", -- or set $VIKUNJA_URL
    },
  },
}
```

---

## Configuration

```lua
require("vikunja").setup({
  -- Base URL of your Vikunja instance (e.g. "https://vikunja.example.com/api/v1").
  -- Can also be set via $VIKUNJA_URL environment variable.
  base_url = "",

  -- API token. Can also be set via:
  -- 1. $VIKUNJA_TOKEN environment variable
  -- 2. ~/.local/share/vikunja/token (chmod 600)
  -- 3. :VikunjaSetToken command
  token = nil,

  -- Path to local token file (defaults to ~/.local/share/vikunja/token).
  token_file = vim.fn.expand("~/.local/share/vikunja/token"),

  -- Default project ID to open on :Vikunja. If nil, opens first favorite or prompts.
  default_project_id = nil,

  -- Icons
  icons = {
    task = "󰄱 ",
    task_done = "󰄵 ",
    due = "󰥔 ",
    priority_low = "󰘄 ",
    priority_medium = "󰁪 ",
    priority_high = "󰀨 ",
    priority_urgent = "󰚌 ",
    subtasks = "󰙅 ",
    attachment = "󰁦 ",
  },

  -- Keymaps inside the Kanban board
  keymaps = {
    next_column = "l",
    prev_column = "h",
    next_card = "j",
    prev_card = "k",
    move_card_next = "L",
    move_card_prev = "H",
    reorder_down = "J",
    reorder_up = "K",
    move_to_bucket = "m",
    toggle_done = "<space>",
    create_task = "a",
    edit_task = "<CR>",
    quick_edit = "e",
    delete_task = "d",
    switch_project = "p",
    refresh = "r",
    help = "?",
    close = "q",
  },
})
```

---

## Keybindings

### Global Commands

- `:VikunjaKanban [project_id]` or `:Vikunja` — Open Kanban board.
- `:VikunjaProjects` — Select a Vikunja project from an interactive picker.
- `:VikunjaSetToken` — Interactively set or update the API token.

### Inside the Kanban Board

| Key       | Action                                                |
| --------- | ----------------------------------------------------- |
| `h` / `l` | Move focus to left / right column                     |
| `j` / `k` | Jump to next / previous card in column                |
| `H` / `L` | Move active card to left / right bucket               |
| `J` / `K` | Reorder active card down / up within bucket           |
| `m`       | Move active card to any bucket via picker             |
| `<Space>` | Toggle task completion status                         |
| `<CR>`    | Open task details in floating Markdown editor         |
| `e`       | Quick inline rename of task title                     |
| `i`       | View task image attachments (Kitty Graphics Protocol) |
| `I`       | Upload and attach local image file to task            |
| `a` / `o` | Create new task in active bucket                      |
| `d`       | Delete active task (with confirmation prompt)         |
| `p`       | Switch Vikunja project                                |
| `r`       | Refresh board from Vikunja API                        |
| `?`       | Toggle help cheat sheet                               |
| `q`       | Close Kanban board tab                                |
