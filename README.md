# claudespace.nvim

A Neovim distribution with deep Claude AI integration.

## Features

- **Multi-session Claude** — multiple Claude sessions as barbar tabs
- **Commit message generation** — conventional commits from staged diff
- **Inline code editing** — select, describe change, preview diff, apply
- **Test generation** — for current file or selection, auto-detects framework
- **Code review** — findings as float + quickfix list with line numbers
- **PR description** — title + body from commits and diff vs base branch
- **Agent panel** — available agents from AGENTS.md + active sessions
- **Session picker** — Telescope fuzzy search across active Claude sessions
- **CLAUDE.md management** — open/create project instructions
- **Statusline** — shows active Claude session count (⚡2)
- **Dashboard** — startup screen with sessions, recent files, quick actions
- **Health check** — `:checkhealth claudespace` validates the environment

## Requirements

- Neovim ≥ 0.12
- `claude` CLI installed and authenticated
- A Nerd Font in your terminal

## Installation

```bash
git clone https://github.com/YOUR_USERNAME/claudespace.nvim ~/.config/nvim
nvim
```

## Keymaps

### Claude Sessions

| Key | Action |
|-----|--------|
| `<leader>cc` | Open Claude in current window |
| `<leader>cn` | New Claude session |
| `<leader>ch` / `<leader>cl` | Previous / next session |
| `<leader>cs` | Telescope session picker |
| `<leader>ca` | Agents panel (AGENTS.md + active sessions) |
| `<leader>cm` | Open / create CLAUDE.md |

### Code Operations (Claude)

| Key | Action |
|-----|--------|
| `<leader>ce` | Edit selection with Claude — diff preview (visual) |
| `<leader>ct` | Generate tests for file or selection |
| `<leader>cr` | Code review → float + quickfix list |

### Git (Claude)

| Key | Action |
|-----|--------|
| `<leader>gc` | Generate commit message from staged diff |
| `<leader>gp` | Generate PR description (title + body) |
| `<leader>gd` | DiffviewOpen |
| `<leader>gh` | File history |
| `<leader>lg` | LazyGit |

### Navigation

| Key | Action |
|-----|--------|
| `\` | File tree (neo-tree) |
| `<A-,>` / `<A-.>` | Prev / next buffer tab |
| `<A-1..5>` | Jump to buffer by index |
| `<A-c>` | Close buffer |
| `<Esc><Esc>` | Exit terminal mode |
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep |
| `<leader>fr` | Recent files |

### Diagnostics

| Key | Action |
|-----|--------|
| `<leader>xx` | Toggle diagnostics panel |
| `<leader>xb` | Buffer diagnostics |
| `<leader>xs` | Symbols |
| `<leader>xq` | Quickfix list |

## Verification

```bash
bash scripts/check.sh   # syntax + module load + unit tests
```

Inside Neovim:
```
:checkhealth claudespace
```

## Architecture

```
lua/
├── claude-multi/        # bundled multi-session manager
└── claudespace/
    ├── options.lua      # vim.opt settings
    ├── keymaps.lua      # base keymaps
    ├── health.lua       # :checkhealth claudespace
    ├── plugins/
    │   ├── ui.lua       # barbar, neo-tree, lualine, snacks
    │   ├── core.lua     # telescope, treesitter, lsp, cmp
    │   ├── git.lua      # diffview, lazygit, gitsigns
    │   ├── langs.lua    # rustaceanvim, go.nvim, toggleterm
    │   └── claude.lua   # claude-multi + claudecode setup
    └── claude/
        ├── commit.lua   # <leader>gc
        ├── inline.lua   # <leader>ce
        ├── tests.lua    # <leader>ct
        ├── review.lua   # <leader>cr
        ├── pr.lua       # <leader>gp
        ├── agents.lua   # <leader>ca
        ├── sessions.lua # <leader>cs
        ├── status.lua   # lualine component
        └── dashboard.lua # startup screen
```
