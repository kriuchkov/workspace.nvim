# 🚀 claudespace — Go demo

A pocket-sized Go project to show off the editor. Toggle this preview with
`<leader>mp`, jump between links with `]l` / `[l`, follow one with `<CR>`.

> [!NOTE]
> Everything here is plain Lua under the hood — no neo-tree, no lualine, no
> external colorscheme. Flip the theme with `<leader>ub`.

## Files

| File | What it shows |
|------|---------------|
| [`greeter.go`](greeter.go) | a struct + methods — great for `gd`, `<leader>lm`, the reference lens |
| [`main.go`](main.go) | the entrypoint that uses `NewGreeter` |
| [`greeter_test.go`](greeter_test.go) | tests — run them with `<leader>ru` |

## Try it

- [ ] `\` — open the file tree
- [ ] `<leader>ru` — run the tests, watch the results panel
- [ ] `gd` on `Greeter` — jump to the definition
- [ ] `<leader>cC` — run the [`/review`](.claude/commands/review.md) command in the background
- [ ] `<leader>cn` — a Claude session in the bottom bar

<details>
<summary>Why a demo project?</summary>

So you can feel the LSP, tasks, markdown, theme, and Claude wiring on real,
buildable code — not screenshots. It's isolated in a throwaway git repo, so
poke at anything.

</details>

## Links

- Repo: [github.com/kriuchkov/claudespace.nvim](https://github.com/kriuchkov/claudespace.nvim)
- Project notes: [`CLAUDE.md`](CLAUDE.md)
