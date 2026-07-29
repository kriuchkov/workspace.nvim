# workspace.nvim

### Neovim, rebuilt as a multi-repo **workspace** IDE.

Not a plugin pack — an **environment** built around real workspaces: many repos under one root, an active-repo context that Git, the tree, find, and tasks all follow, named layout snapshots you switch in a keystroke, and a fixed region shell so the editor never splits by accident. The tabline, tree, statusline, source-control panel, markdown preview, and the dark/light theme are all plain, forkable Lua — **no lazy.nvim, no neo-tree, no lualine, no external colorscheme.** Built on `vim.pack` (Neovim 0.12).

Optional, headless **Claude Code helpers** (commit messages, review, PR text, generate, fix) are included but never in the way — they shell out to the official `claude` CLI only when you invoke them.

![workspace demo](docs/demo.gif)

```
top bar  ┃ tabs (buffer groups)
─────────╂───────────────────────────────
 left    ┃                        ┃ right
 activity┃      center            ┃ outline
 bar +   ┃   (the one content     ┃  / TOC
 panels  ┃    window)             ┃
─────────╂───────────────────────────────
 status  ┃ mode · repo · git · diagnostics · position
```

> **One region layout.** Everything opens in a single center window — files and buffers — so the editor never splits by accident.

## Try it in 60 seconds

```bash
git clone https://github.com/kriuchkov/workspace.nvim
cd workspace.nvim
scripts/demo.sh go       # or: rust  — opens a real project in workspace
```

The GIF above is the [`orbit`](demo/workspace) demo: a real multi-repo workspace (Go + Rust services, a shared package, a frontend, deploy). Two smaller single-repo [demos](demo) (Go & Rust) come with tasks, tests and a `CLAUDE.md` — poke at LSP, the test runner, markdown preview, the theme toggle, and the AI helpers immediately. See [demo/README.md](demo/README.md) for the guided tour.

## Why workspace?

**Workspaces are real.** Save a named snapshot of your layout, open files, and buffer groups; switch projects in one keypress and come back exactly where you left off. A workspace can span many repos under one root — a **multi-repo manifest** names them, and one is always the **active repo** that Git, the tree, find, and the task runner follow.

**A real region layout.** One fixed shell: **top bar** (tabs) · **left / center / right** (activity bar + panels, the single content window, outline/TOC) · **status bar**. Every file and buffer opens in the one center window — nothing splits the editor by accident.

**You own every pixel.** No barbar, no neo-tree, no lualine, no external colorscheme. The tabline, file tree, statusline, winbar, markdown preview, and the dark+light theme are all plain Lua — readable, forkable, and fast.

**Zero plugin-manager overhead.** Uses `vim.pack`, the package manager built into Neovim 0.12. No lazy.nvim bootstrap, no startup-time tax.

**AI when you want it, invisible when you don't.** The optional helpers speak Claude Code's structured `stream-json` protocol, so answers stream in live, tool activity is visible, and you see exact cost and turn counts per run — and can cancel a long job (`<leader>cx`). Nothing runs unless you ask.

---

## Features

### Workspace (multi-repo)
- Named workspaces with full persistence: layout, open files, buffer groups, active repo
- Multi-repo manifest (`.workspace/workspace.json`) with an **active repo**; Git, tree, find and tasks are all repo-aware
- Repos overview + repo info card; per-repo terminal in the active repo's cwd
- Home screen on bare `nvim` — workspace list with git branches and recent files
- Project templates — scaffold Go / TypeScript / Python / Rust / Lua plugin with `tasks.json`

### Editor & UI
- **Own dark + light theme** that follows the terminal — Neovim's OSC 11 detection and OS light/dark notifications switch it live; toggle with `<leader>ub`
- **Region shell** — top tabs / left+right panels / center content / status bar
- **Chrome-style buffer groups** — coloured, collapsible, persistent per directory
- **Markdown preview** (in-buffer, no plugins) — headings, tables aligned to the widest cell, `<details>/<summary>` folds, GitHub callouts, task lists, TOC panel, link navigation, zen/focus reading mode
- Custom **file tree** — repo roots, git status icons, gitignore dimming, diagnostic badges, create/move/rename/delete with open-buffer sync
- **Activity bar** (VS Code-style) — Explorer, Search, Git, Outline, Diagnostics, Tasks and more; press `?` to reveal each icon's hotkey
- **Fuzzy finder** (no telescope) — files, live grep, buffers, recent, help, all with a preview pane; fuzzy ranking via Neovim's built-in `matchfuzzypos`, async via `vim.system`; also backs `vim.ui.select`
- **JSON tools** — `<leader>=` pretty-formats a buffer via `jq`; `<leader>uj` shows it pretty read-only (file untouched)
- **Keymap cheatsheet** (`<leader>?`) built from your live `<leader>` maps, plus a native **which-key** popup (pause on `<leader>`, no plugin)
- **Directory dashboard** (replaces netrw), **LSP outline** panel, **winbar** breadcrumb, **notifications** center, per-workspace **quick marks**, **command palette**

### Git
- **Multi-repo source control** — a VS Code-style panel: every workspace repo with its branch and dirty/ahead/behind, nested under group dirs like the tree; pick one and its staging view (stage/unstage, diff, commit, push) opens in the center window; `F` fast-forward-pulls every repo at once
- Git status icons in the file tree; gitsigns inline hunks; Lazygit

### Development
- **Task runner** (`tasks.json` / `.tasks.lua`) — runs in the active repo, with a **pass/fail winbar banner** (green ✓ / red ✗ by exit code) and coloured output; test runner UI with a results panel
- **Scoped live grep** — ripgrep regex plus on-the-fly `--glob` scoping to a file type or a single service (`*.go`, `!*_test.go`, `services/vega/**`), no extra plugins
- LSP, Treesitter, nvim-cmp, DAP — the modern stack via `vim.pack`

### AI helpers (optional, via Claude Code)
Headless, on-demand — each runs `claude --print --output-format stream-json` and returns to the editor. No terminal, no background sessions.
- **Commit messages** — conventional commits from the staged diff (`<leader>gc`)
- **Code review** — findings as a float + quickfix list with line numbers (`<leader>cgr`)
- **PR description** — title + body from commits and the diff vs the base branch (`<leader>cgp`)
- **Generate** — tests, docs, code at cursor, multi-file compose (auto-detects Go / Rust / Python / JS)
- **Inline editing** — select, describe the change, preview the diff, apply (`<leader>cge`)
- **Fix / explain** — fix the diagnostic under the cursor (`<leader>cf`), explain code (`<leader>ck`)
- **Commands** — run your `.claude/commands/*.md` with their argument prompts (`<leader>cC`)
- **Structured runner** — tokens stream live, tool activity shown, exact cost / turn count, cancel anytime (`<leader>cx`)

> **On Claude Code.** These helpers are a thin **frontend for [Claude Code](https://www.anthropic.com/claude-code)**: they shell out to the official `claude` binary you already have installed and logged in, using documented flags (`--print`, `--output-format stream-json`) and your existing `~/.claude` config, `CLAUDE.md`, MCP servers and permission mode. No API keys, nothing reverse-engineered — every AI action stays within [Claude Code's Terms of Use](https://www.anthropic.com/legal/consumer-terms). They are entirely optional; `workspace` is a full editor without them.

---

## Requirements

- **Neovim ≥ 0.12** (vim.pack required)
- **A Nerd Font** in your terminal (icons)
- Git in `$PATH`
- A terminal that reports its background (OSC 11) for automatic dark/light — otherwise use `<leader>ub`
- *Optional:* the **`claude` CLI** installed and authenticated (`claude --version`), only for the AI helpers

---

## Installation

```bash
git clone https://github.com/kriuchkov/workspace.nvim ~/.config/nvim
nvim
```

Plugins install automatically on first launch via `vim.pack`.

### Development (separate config)

```bash
git clone https://github.com/kriuchkov/workspace.nvim ~/workspace.nvim
ln -s ~/workspace.nvim ~/.config/workspace
NVIM_APPNAME=workspace nvim
```

### Verify

```bash
bash scripts/check.sh        # syntax + module load + unit tests
```

```
:checkhealth workspace       # inside Neovim
```

---

## Keymaps

`<leader>` is `Space`.

### Workspace

| Key | Action |
|-----|--------|
| `<leader>wS` | Save workspace |
| `<leader>ws` | Switch workspace |
| `<leader>wl` | List workspaces |
| `<leader>wp` | Repos overview |
| `<leader>wT` | Terminal in the active repo |
| `<leader>wt` | New project from template |

### Git

| Key | Action |
|-----|--------|
| `<leader>gg` | Lazygit |
| `<leader>gc` | Generate commit message from staged diff |
| `<leader>gs` / `<leader>gS` | Stage hunk / stage buffer |
| `<leader>gr` / `<leader>gR` | Reset hunk / reset buffer |
| `<leader>gp` / `<leader>gu` | Preview hunk / undo stage |
| `<leader>gd` / `<leader>gD` | Diff index / close diff |
| `<leader>gh` / `<leader>gl` | File history / repo log |
| `<leader>gB` | Blame file |

### AI helpers (optional)

| Key | Action |
|-----|--------|
| `<leader>ck` | Explain code |
| `<leader>cf` | Fix diagnostic under cursor |
| `<leader>cge` | Edit selection (visual) |
| `<leader>cgc` | Generate at cursor |
| `<leader>cgd` | Generate docs |
| `<leader>cgm` | Multi-file compose |
| `<leader>cgt` | Generate tests (file / selection) |
| `<leader>cgr` | Review (file / selection) |
| `<leader>cgp` | Generate PR description |
| `<leader>c!` | Shell command → Claude |
| `<leader>cC` | Run a `.claude/commands/*.md` command |
| `<leader>cm` | Open / create `CLAUDE.md` |
| `<leader>cx` | Cancel running headless Claude jobs |
| `<leader>cA` (visual) | Send selection to a connected Claude Code |
| `<leader>cy` / `<leader>cY` | Accept / reject Claude Code inline diff |

### Tabs (top bar)

| Key | Action |
|-----|--------|
| `<A-,>` / `<A-.>` | Previous / next tab |
| `<A-1..9>` | Jump to tab by index |
| `<A-c>` | Close tab |
| `<A-w>` | Save & close tab |
| `<leader>tw` / `<leader>tq` | Close current / close whole group |
| `<leader>to` / `<leader>tx` | Close others / close all (keep pinned) |

### Markdown

| Key | Action |
|-----|--------|
| `<leader>mp` | Toggle preview |
| `<leader>mt` | TOC panel |
| `<leader>mf` | Focus current section |
| `]]` / `[[` | Next / previous heading |
| `]l` / `[l` | Next / previous link |
| `<CR>` / `gx` | Follow link (`#anchor` / URL / file) |

### Navigation & UI

| Key | Action |
|-----|--------|
| `\` | File tree toggle |
| `<leader>e` / `<leader>E` | Toggle / focus the activity bar (sidebar) |
| `<leader>ff` / `<leader>fg` / `<leader>fr` / `<leader>fb` | Find files / grep / recent / buffers |
| `<leader>fG` / `<leader>fR` | Live grep scoped by glob / in the active repo |
| `<leader>?` | Keymap cheatsheet (live `<leader>` maps, grouped) |
| `<leader>xx` / `<leader>xs` | Diagnostics panel / Symbols (outline) panel |
| `<leader>xo` | Outline panel |
| `<leader>z` | Zen / reading mode |
| `<leader>ub` | Toggle dark / light background (`:CSThemeToggle`) |
| `<leader>uw` | Toggle word wrap |
| `<leader>P` | Command palette |

---

## Architecture

```
lua/
└── workspace/
    ├── options.lua          # vim.opt settings
    ├── keymaps.lua          # base keymaps
    ├── health.lua           # :checkhealth workspace
    ├── shell.lua            # region layout: the single center content window
    ├── theme/
    │   ├── palette.lua      # dark + light semantic palettes
    │   └── init.lua         # applier, terminal-driven dark/light switch
    ├── plugins/
    │   ├── ui.lua           # theme + native which-key + icons
    │   ├── core.lua         # native fuzzy picker, treesitter, folds
    │   ├── lsp.lua          # LSP + cmp
    │   ├── langs.lua        # treesitter / language extras
    │   ├── git.lua          # gitsigns
    │   └── debug.lua        # DAP
    ├── claude/              # optional, headless AI helpers (no sessions)
    │   ├── runner.lua       # stream-json runner (cancelable, cost/turns)
    │   ├── util.lua         # spinner, floats, async run wrapper
    │   ├── codegen.lua      # edit / generate / tests / docs
    │   ├── git_ops.lua      # commit message / review / PR
    │   ├── assist.lua       # explain / shell → Claude
    │   ├── fix.lua          # fix diagnostic under cursor
    │   └── commands.lua     # run .claude/commands/*.md
    ├── tabline.lua          # top bar: Chrome-style buffer groups
    ├── sidebar.lua          # left activity bar + panels
    ├── picker.lua           # fuzzy picker (no telescope) + vim.ui.select
    ├── whichkey.lua         # leader-hints popup (no which-key.nvim)
    ├── filetree.lua         # file tree (no neo-tree), multi-repo aware
    ├── statusline.lua       # statusline (no lualine)
    ├── winbar.lua           # breadcrumb winbar
    ├── mdpreview.lua        # in-buffer markdown preview
    ├── mdtoc.lua            # markdown TOC panel
    ├── zen.lua              # zen / focus reading mode
    ├── repos.lua            # multi-repo manifest + active repo
    ├── workspace.lua        # workspace save / load / switch
    ├── layout.lua           # window layout persistence
    ├── home.lua             # startup home screen
    ├── dirdash.lua          # directory dashboard (no netrw)
    ├── outline.lua          # LSP outline panel
    ├── notify.lua           # notifications center
    ├── marks.lua            # per-workspace quick marks
    ├── palette.lua          # command palette
    ├── git_ui.lua           # git staging UI
    ├── tasks.lua            # task runner
    ├── test_ui.lua          # test runner + results panel
    └── templates.lua        # project scaffolding templates
```
