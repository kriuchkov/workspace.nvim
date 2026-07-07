# claudespace.nvim

### Neovim, rebuilt as an AI-native IDE — a native frontend for Claude Code.

Not "Neovim + a Claude plugin." An **environment** where Claude is part of the editor: sessions live in a dock, past conversations are browsable and resumable, context is fed in automatically, and one keystroke drives Claude across every repo in your workspace. The tabline, tree, statusline, source-control panel, markdown preview, and the dark/light theme are all plain, forkable Lua — **no lazy.nvim, no neo-tree, no lualine, no external colorscheme.** Built on `vim.pack` (Neovim 0.12).

![claudespace demo](docs/demo.gif)

> **Built on Claude Code.** claudespace is a **wrapper around [Claude Code](https://www.anthropic.com/claude-code)** — it drives the official `claude` CLI through its documented interfaces (`--print`, `--output-format stream-json`, `--resume`) using *your* existing Claude Code login, `CLAUDE.md`, MCP servers, and permission settings. There is no reimplemented API and nothing is bypassed, so every AI action stays fully within [Claude Code's terms of use](https://www.anthropic.com/legal/consumer-terms). See [Built on Claude Code](#built-on-claude-code).

```
top bar  ┃ tabs (buffer groups)
─────────╂───────────────────────────────
 left    ┃                        ┃ right
 activity┃      center            ┃ outline
 bar +   ┃   (the one content     ┃  / TOC
 panels  ┃    window)             ┃
─────────╂───────────────────────────────
bottom   ┃ Claude sessions ¹ ² ³
```

> **One region layout.** Everything opens in a single center window — files, buffers, and Claude tabs — so the editor never splits by accident.

## Try it in 60 seconds

```bash
git clone https://github.com/kriuchkov/claudespace.nvim
cd claudespace.nvim
scripts/demo.sh go       # or: rust  — opens a real project in claudespace
```

The GIF above is the [`orbit`](demo/workspace) demo: a real multi-repo workspace (Go + Rust services, a shared package, a frontend, deploy). Two smaller single-repo [demos](demo) (Go & Rust) come with tasks, tests, a `CLAUDE.md`, and a `/review` command — poke at LSP, the test runner, markdown preview, the theme toggle, and Claude actions immediately. See [demo/README.md](demo/README.md) for the guided tour.

## Why claudespace?

**Claude Code, with a real IDE around it.** You already trust the `claude` CLI — claudespace gives it a home: multiple sessions in a dock, a browsable history of every past conversation, automatic project context, commit messages from diffs, and code review straight into the quickfix list. Claude always knows which repo you're in, and **Fleet** commands drive it across every repo in the workspace at once.

**Nothing is hidden.** The runner speaks Claude Code's structured `stream-json` protocol, so answers stream in live, tool activity is visible, and you see exact cost and turn counts per run — and can cancel a long job. No terminal scraping, no guessing when it's done.

**Your sessions are yours.** Every past conversation in `~/.claude/projects` is listed in the activity bar with a title and a transcript preview — resume it (`claude --resume`), read it, or delete it, without leaving the editor.

**A real region layout.** One fixed shell: **top bar** (tabs) · **left / center / right** (activity bar + panels, the single content window, outline/TOC) · **bottom bar** (Claude sessions). Every file, buffer, and Claude tab opens in the one center window — nothing splits the editor by accident.

**You own every pixel.** No barbar, no neo-tree, no lualine, no external colorscheme. The tabline, file tree, statusline, winbar, markdown preview, and the dark+light theme are all plain Lua — readable, forkable, and fast.

**Zero plugin manager overhead.** Uses `vim.pack`, the package manager built into Neovim 0.12. No lazy.nvim bootstrap, no startup time tax.

**Workspaces are real.** Save a named snapshot of your layout, open files, buffer groups, terminal slots, and Claude sessions — each session restored on its *own* conversation. Switch projects in one keypress, come back exactly where you left off.

---

## Built on Claude Code

claudespace does **not** talk to the Anthropic API directly. It is a **frontend for [Claude Code](https://www.anthropic.com/claude-code)** and shells out to the official `claude` binary you already have installed and logged in.

- **Same CLI, documented flags.** Interactive sessions run `claude` in a terminal buffer; background work uses `claude --print --output-format stream-json --verbose` and `--resume <id>` — all public, supported interfaces. Session history is read from your local `~/.claude/projects` transcript files.
- **Your setup, unchanged.** It reuses your existing Claude Code authentication, `~/.claude` config, project `CLAUDE.md`, MCP servers, permission mode, and slash commands. claudespace adds no API keys and stores no credentials of its own.
- **Nothing reverse-engineered or bypassed.** No reimplemented API, no scraping of internal state, no working around usage limits or permissions — a tool Claude Code denies is surfaced to you, not circumvented.
- **Terms of use.** Because every AI action is just the official CLI doing what you would do by hand, using claudespace stays entirely within [Claude Code's Terms of Use](https://www.anthropic.com/legal/consumer-terms) and whatever plan your `claude` login is on. A valid Claude Code installation and login are required; claudespace is independent, open editor tooling *around* it.

---

## Features

### AI (Claude)
- **Multi-session** — several independent Claude sessions in a bottom bar, numbered and clickable; restored on their own conversation (`--resume <id>`) after a restart
- **Session history** — an activity-bar panel of every past conversation in `~/.claude/projects`, newest first, with a title and a live transcript preview; press `⏎` to resume, `C-o` to read it in full, `C-d` to delete
- **Structured runner** — background commands run through Claude Code's `stream-json` protocol: tokens stream in live, tool activity is shown, and you get the real result plus exact cost / turn count — cancel anytime (`<leader>cx`)
- **Tasks** — an activity-bar launcher for your `.claude/commands/*.md`, with their descriptions and argument prompts (`⏎` runs, filling in the command's `argument-hint`)
- **Fleet / multi-repo** — broadcast a prompt to every repo, workspace-wide commit, cross-repo grep, scaffold `CLAUDE.md`, bump a shared package in dependents
- **Commit messages** — conventional commits from the staged diff via `claude --print`
- **Inline editing** — select, describe the change, preview the diff, apply
- **Generate** — tests, docs, code at cursor, multi-file compose (auto-detects Go / Rust / Python / JS)
- **Code review** — findings as a float + quickfix list with line numbers
- **PR description** — title + body from commits and the diff vs the base branch
- **Context** — inject workspace context (git status, recent files, README) into a session on demand; send diagnostics / terminal output / shell output too

### Workspace (multi-repo)
- Named workspaces with full persistence: layout, open files, buffer groups, Claude sessions
- Multi-repo manifest with an **active repo**; Git, tree, find, and Claude are all repo-aware
- Repos overview + repo info card; per-repo terminal in the active repo's cwd
- Home screen on bare `nvim` — workspace list with git branches and recent files
- Project templates — scaffold Go / TypeScript / Python / Rust / Lua plugin with `tasks.json`

### Editor & UI
- **Own dark + light theme** that follows the terminal — Neovim's OSC 11 detection and OS light/dark notifications switch it live; toggle with `<leader>ub`
- **Region shell** — top tabs / left+right panels / center content / bottom Claude bar
- **Chrome-style buffer groups** — coloured, collapsible, persistent per directory
- **Markdown preview** (in-buffer, no plugins) — headings, tables aligned to the widest cell, `<details>/<summary>` folds, GitHub callouts, task lists, TOC panel, link navigation, zen/focus reading mode
- Custom **file tree** — repo roots, git status icons, gitignore dimming, diagnostic badges, create/move/rename/delete with open-buffer sync
- **Activity bar** (VS Code-style) — Explorer, Search, Git, Outline, Diagnostics, Tasks, Sessions and more; press `?` to reveal each icon's hotkey
- **JSON tools** — `<leader>=` pretty-formats a buffer via `jq`; `<leader>uj` shows it pretty read-only (file untouched)
- **Keymap cheatsheet** (`<leader>?`) built from your live `<leader>` maps, plus which-key
- **Directory dashboard** (replaces netrw), **LSP outline** panel, **winbar** breadcrumb, **notifications** center, per-workspace **quick marks**, **command palette**

### Git
- **Multi-repo source control** — a VS Code-style panel: every workspace repo with its branch and dirty/ahead/behind, nested under group dirs like the tree; a repo that is also a container folds; pick one and its staging view (stage/unstage, diff, commit with a Claude message, push) opens in the center window; `F` fast-forward-pulls every repo at once
- Git status icons in the file tree; gitsigns inline hunks; Lazygit

### Development
- **Task runner** (`tasks.json` / `.tasks.lua`) — runs in the active repo, with a **pass/fail winbar banner** (green ✓ / red ✗ by exit code) and coloured output; test runner UI with a results panel
- **Scoped live grep** — ripgrep regex plus on-the-fly `--glob` scoping to a file type or a single service (`*.go`, `!*_test.go`, `services/vega/**`), no extra plugins
- LSP, Treesitter, nvim-cmp, DAP — the modern stack via `vim.pack`

---

## Requirements

- **Neovim ≥ 0.12** (vim.pack required)
- **`claude` CLI** installed and authenticated (`claude --version`)
- **A Nerd Font** in your terminal (icons)
- Git in `$PATH`
- A terminal that reports its background (OSC 11) for automatic dark/light — otherwise use `<leader>ub`

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

`<leader>` is `Space`. Alt keys work across regions, including inside the Claude terminal.

### Claude — sessions

| Key | Action |
|-----|--------|
| `<leader>cc` | Open / toggle Claude |
| `<leader>cn` | New session |
| `<leader>cu` | Resume a past conversation (`--resume` picker) |
| `<leader>cH` | Session history — browse `~/.claude/projects` (⏎ resume · C-o transcript · C-d delete) |
| `<leader>cx` | Cancel running headless Claude jobs (`:ClaudeCancel`) |
| `<leader>cs` | Session picker |
| `<leader>cR` | Rename session |
| `<leader>ch` / `<leader>cl` | Previous / next session |
| `<leader>c1`…`<leader>c9` | Jump to session N (numbers in the bottom bar) |
| `<A-h>` / `<A-l>` | Cycle sessions — works inside the Claude terminal |

### Claude — code & edits

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
| `<leader>gc` | Generate commit message from staged diff |

### Claude — context, agents & Fleet

| Key | Action |
|-----|--------|
| `<leader>cC` | Run a `.claude/commands/*.md` command (picker → background session) |
| `<leader>ca` | Agents panel |
| `<leader>cA` | Add to context… |
| `<leader>ci` | Inject workspace context |
| `<leader>cd` | Send diagnostics to Claude |
| `<leader>cT` | Send terminal output to Claude |
| `<leader>c!` | Shell command → Claude |
| `<leader>cm` | Open / create `CLAUDE.md` |
| `<leader>cwb` | Fleet: broadcast prompt to all repos |
| `<leader>cwc` | Fleet: workspace-wide commit |
| `<leader>cwg` | Fleet: cross-repo grep → Claude |
| `<leader>cwr` | Fleet: review diff (active repo) |
| `<leader>cws` | Fleet: scaffold `CLAUDE.md` (active repo) |
| `<leader>cwu` | Fleet: bump shared package in dependents |

### Git

| Key | Action |
|-----|--------|
| `<leader>gg` | Lazygit |
| `<leader>gc` | Generate commit message from staged diff (Claude) |
| `<leader>cgp` | Generate PR description (Claude) |
| `<leader>gs` / `<leader>gS` | Stage hunk / stage buffer |
| `<leader>gr` / `<leader>gR` | Reset hunk / reset buffer |
| `<leader>gp` / `<leader>gu` | Preview hunk / undo stage |
| `<leader>gd` / `<leader>gD` | Diff index / close diff |
| `<leader>gh` / `<leader>gl` | File history / repo log |
| `<leader>gB` | Blame file |

### Workspace

| Key | Action |
|-----|--------|
| `<leader>wS` | Save workspace |
| `<leader>ws` | Switch workspace |
| `<leader>wl` | List workspaces |
| `<leader>wp` | Repos overview |
| `<leader>wT` | Terminal in the active repo |
| `<leader>wt` | New project from template |

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
| `<leader>xo` | Outline panel |
| `<leader>z` | Zen / reading mode |
| `<leader>ub` | Toggle dark / light background (`:CSThemeToggle`) |
| `<leader>uw` | Toggle word wrap |
| `<leader>P` | Command palette |

---

## Architecture

```
lua/
└── claudespace/
    ├── options.lua          # vim.opt settings
    ├── keymaps.lua          # base keymaps
    ├── health.lua           # :checkhealth claudespace
    ├── shell.lua            # region layout: the single center content window
    ├── theme/
    │   ├── palette.lua      # dark + light semantic palettes
    │   └── init.lua         # applier, terminal-driven dark/light switch
    ├── plugins/
    │   ├── ui.lua           # theme + which-key + icons
    │   ├── core.lua         # base plugin set
    │   ├── lsp.lua          # LSP + cmp
    │   ├── langs.lua        # treesitter / language extras
    │   ├── git.lua          # gitsigns
    │   ├── debug.lua        # DAP
    │   └── claude.lua       # Claude integration wiring
    ├── claude/
    │   ├── sessions.lua     # session lifecycle (terminal buffers)
    │   ├── bottombar.lua    # Claude session bar (bottom float)
    │   ├── codegen.lua      # edit / generate / tests / docs
    │   ├── git_ops.lua      # commit message / review / PR
    │   ├── assist.lua       # explain / diagnostics / shell → Claude
    │   ├── fix.lua          # fix diagnostic under cursor
    │   ├── context.lua      # workspace context for Claude
    │   ├── workspace.lua    # Fleet: cross-repo Claude actions
    │   ├── agents.lua       # agents panel
    │   └── dashboard.lua    # Claude dashboard
    ├── tabline.lua          # top bar: Chrome-style buffer groups
    ├── sidebar.lua          # left activity bar + panels
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
