# orbit workspace

A multi-repo claudespace workspace for the demo, shaped like a real monorepo.

- `services/vega` (Go) — HTTP greeting service, depends on `packages/nebula`
- `services/lyra` (Go) — averages scores, depends on `packages/nebula`
- `services/nova` (Rust) — formats notifications
- `packages/nebula` (Go) — shared greeting package
- `frontends/aurora` (Rust) — renders the greeting
- `deploy` — docker-compose that wires it together

`go.work` ties the Go modules together for gopls. Each repo has its own git
history, `CLAUDE.md`, and `tasks.json`.
