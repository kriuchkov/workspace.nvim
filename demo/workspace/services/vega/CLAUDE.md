# vega (Go service)

The HTTP greeting service in the **orbit** workspace. Depends on the shared
`orbit/nebula` package (`../../packages/nebula`).

- `main.go` — the server + `handler`
- `handler_test.go` — an httptest for the handler

## Conventions
- Keep handlers thin; put shared logic in `packages/nebula`.
- Every handler has a test.
