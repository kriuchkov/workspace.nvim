# nebula (shared Go package)

The shared greeting package used by the services in the **orbit** workspace.
Changes here ripple to every dependent repo.

- `nebula.go` — the `Greeter` type + `New` / `Hello`
- `nebula_test.go` — its tests

## Conventions
- Keep the API small and stable — services depend on it.
- 100% of exported functions are tested.
