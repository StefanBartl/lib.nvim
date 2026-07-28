Resolves a user-provided log level into a valid `vim.log.levels` integer,
never raising: unresolvable input falls back to `default` (itself defaulting
to `vim.log.levels.WARN`).

- `nil` → `default`.
- A `number` in `0..5` is returned as-is (Neovim's `TRACE`..`OFF` range);
  outside that range it falls back to `default`.
- A `string` is matched case-insensitively against `TRACE`, `DEBUG`, `INFO`,
  `WARN`, `ERROR`, `OFF`; an unrecognized name falls back to `default`.
- Any other type (including a table, e.g. a `vim.log.levels.*` value passed by
  accident instead of the plain number) falls back to `default`.
