# claudespace.nvim

> A full IDE experience inside Neovim, with Claude AI at the core — not a plugin you add, but the environment you work in.

## Why claudespace?

**Claude is first-class, not bolted on.** Sessions are bound to workspaces, context is injected automatically, commit messages are generated from diffs, code review lands in quickfix. Claude knows where you are and what you're doing.

**You own every pixel.** No barbar, no neo-tree, no lualine. The tabline, file tree, statusline, winbar, and directory dashboard are all plain Lua — readable, forkable, and fast.

**Zero plugin manager overhead.** Uses `vim.pack`, the package manager built into Neovim 0.12. No lazy.nvim bootstrap, no startup time tax.

**Workspaces are real.** Save a named snapshot of your layout, open files, buffer groups, terminal slots, and Claude session. Switch projects in one keypress, come back exactly where you left off.

---

## Features

### AI (Claude)
- Multi-session Claude — several independent sessions as tabs
- Commit message generation — conventional commits from staged diff via `claude --print`
- Inline code editing — select, describe change, preview diff, apply
- Test generation — auto-detects Go / Rust / Python / JS framework
- Code review — findings as float + quickfix list with line numbers
- PR description — title + body from commits and diff vs base branch
- Workspace context injection — auto-writes `.claude/WORKSPACE.md` (git status, recent files, README excerpt); Claude reads it on session start

### Workspace
- Named workspaces with full persistence: layout, open files, buffer groups, Claude session ID
- Home screen on bare `nvim` — workspace list with git branches, recent files
- Per-workspace terminals (`<leader>w1/2/3`) bound to workspace cwd
- Project templates — scaffold Go / TypeScript / Python / Rust / Lua plugin with `tasks.json`

### TUI
- Chrome-style buffer groups — coloured, collapsible, persistent per directory
- Custom file tree — git status icons, gitignore dimming, file operations (create / rename / delete / yank path)
- Directory dashboard — replaces netrw; shows git log, README excerpt, workspace info
- LSP outline panel — document symbols in a right-side split, cursor-synced
- Winbar breadcrumb — `dir/file` with distinct background stripe
- Notifications center — full history of `vim.notify` calls, dismissable
- Quick marks — 5 per-workspace file bookmarks, instant jump
- Command palette — all claudespace actions via `<leader>P`

### Git
- Staging UI — view status, stage/unstage files, view diff, commit (with Claude message), push
- Git status icons in file tree (modified / added / deleted / untracked / ignored)
- Gitsigns — inline hunk indicators and hunk navigation

### Development
- Task runner — reads `tasks.json` or `.tasks.lua` from project root, runs in terminal split
- Test runner UI — detects framework, runs tests, shows pass/fail summary panel
- LSP, Treesitter, nvim-cmp — standard modern stack via `vim.pack`

---

## Requirements

- **Neovim ≥ 0.12** (vim.pack required)
- **`claude` CLI** installed and authenticated (`claude --version`)
- **A Nerd Font** in your terminal (icons)
- Git in `$PATH`

---

## Installation

```bash
git clone https://github.com/kriuchkov/claudespace.nvim ~/.config/nvim
nvim
```

Plugins install automatically on first launch via `vim.pack`.

### Development (separate config)

```bash
git clone https://github.com/kriuchkov/claudespace.nvim ~/claudespace.nvim
ln -s ~/claudespace.nvim ~/.config/claudespace
NVIM_APPNAME=claudespace nvim
```

### Verify

```bash
bash scripts/check.sh        # syntax + module load + unit tests
```

```
:checkhealth claudespace     # inside Neovim
```

---

## Keymaps

### Claude

| Key | Action |
|-----|--------|
| `<leader>cc` | Open Claude in current window |
| `<leader>cn` | New Claude session |
| `<leader>ch` / `<leader>cl` | Previous / next session |
| `<leader>cs` | Session picker (Telescope) |
| `<leader>ca` | Agents panel |
| `<leader>cm` | Open / create CLAUDE.md |
| `<leader>ce` | Edit selection with Claude (visual) |
| `<leader>ct` | Generate tests |
| `<leader>cr` | Code review |
| `<leader>ci` | Inject workspace context into Claude session |

### Git

| Key | Action |
|-----|--------|
| `<leader>gs` | Git staging UI (stage / unstage / diff / commit / push) |
| `<leader>gc` | Generate commit message from staged diff |
| `<leader>gp` | Generate PR description |

### Workspace

| Key | Action |
|-----|--------|
| `<leader>ww` | Save current workspace |
| `<leader>ws` | Switch workspace |
| `<leader>wl` | List workspaces |
| `<leader>wh` | Home screen |
| `<leader>wd` | Delete workspace |
| `<leader>wt` | New project from template |
| `<leader>w1/2/3` | Per-workspace terminal slots |

### Navigation

| Key | Action |
|-----|--------|
| `\` | File tree toggle |
| `<A-,>` / `<A-.>` | Prev / next buffer |
| `<A-1..5>` | Jump to buffer by index |
| `<A-c>` | Close buffer |
| `<leader>ff/fg/fr/fb` | Find files / grep / recent / buffers |
| `<leader>M` | Marks panel |
| `<leader>m1-5` | Set mark N |
| `<leader>j1-5` | Jump to mark N |
| `<leader>P` | Command palette |
| `<leader>N` | Notifications history |

### Tasks & Tests

| Key | Action |
|-----|--------|
| `<leader>rr` | Pick and run task |
| `<leader>rb/rt/rl/rx` | Build / test / lint / run |
| `<leader>ru` | Run tests + show results panel |

### Diagnostics & Panels

| Key | Action |
|-----|--------|
| `<leader>xx` | Diagnostics panel |
| `<leader>xb` | Buffer diagnostics |
| `<leader>xo` | LSP outline panel |

---

## Architecture

```
lua/
├── claude-multi/            # bundled multi-session Claude manager
└── claudespace/
    ├── options.lua          # vim.opt settings
    ├── keymaps.lua          # base keymaps
    ├── health.lua           # :checkhealth claudespace
    ├── plugins/
    │   ├── ui.lua           # all UI wiring
    │   ├── core.lua         # telescope, treesitter, lsp, cmp
    │   ├── git.lua          # gitsigns
    │   └── claude.lua       # claude-multi setup
    ├── claude/
    │   ├── commit.lua       # <leader>gc
    │   ├── inline.lua       # <leader>ce
    │   ├── tests.lua        # <leader>ct
    │   ├── review.lua       # <leader>cr
    │   ├── pr.lua           # <leader>gp
    │   ├── agents.lua       # <leader>ca
    │   ├── sessions.lua     # <leader>cs
    │   └── context.lua      # workspace context → .claude/WORKSPACE.md
    ├── tabline.lua          # Chrome-style buffer groups
    ├── filetree.lua         # file tree (no neo-tree)
    ├── statusline.lua       # statusline (no lualine)
    ├── winbar.lua           # breadcrumb winbar
    ├── dirdash.lua          # directory dashboard (no netrw)
    ├── workspace.lua        # workspace save / load / switch
    ├── layout.lua           # window layout persistence
    ├── home.lua             # startup home screen
    ├── tasks.lua            # task runner
    ├── outline.lua          # LSP outline panel
    ├── notify.lua           # notifications center
    ├── marks.lua            # per-workspace quick marks
    ├── palette.lua          # command palette
    ├── git_ui.lua           # git staging UI
    ├── test_ui.lua          # test runner + results panel
    └── templates.lua        # project scaffolding templates
```
