# claudespace.nvim — Development Instructions

## Project Overview
Neovim distribution with deep Claude AI integration. Built on kickstart.nvim patterns,
using vim.pack (Neovim 0.12 built-in) as the plugin manager. No lazy.nvim dependency.

## Architecture
- `init.lua` — bootstrap: loads options → keymaps → plugins → claude modules
- `lua/claudespace/options.lua` — vim.opt settings
- `lua/claudespace/keymaps.lua` — base keymaps (no plugin dependencies)
- `lua/claudespace/plugins/` — plugin setup (one file per category)
- `lua/claudespace/claude/` — Claude integration modules
- `lua/custom/` — machine-local overrides (gitignored)

## Plugin Manager
Use `vim.pack.add { 'https://github.com/...' }` to add plugins.
Lock file: `nvim-pack-lock.json`. Update: `:lua vim.pack.update()`.

## Key Conventions
- All Claude keymaps use `<leader>c` prefix
- Git keymaps use `<leader>g` prefix
- Terminal keymaps use `<leader>t` prefix
- No comments explaining WHAT code does, only WHY if non-obvious

## Claude Modules
Each module in `lua/claudespace/claude/` is self-contained:
- registers its own keymaps
- calls `claude --print` CLI for one-shot generations
- uses `claude-multi.nvim` for interactive sessions

## Testing Changes
Run with: `NVIM_APPNAME=claudespace nvim` (uses ~/.config/claudespace as config dir,
or symlink this repo there for development).
