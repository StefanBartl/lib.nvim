# Design pattern collection

A catalogue of the classic (Gang of Four) and common modern design patterns, with a place for each in `lib.nvim`: either a pointer to the existing module that already is the pattern, or a small tested reference implementation, or — where the pattern gives little in Lua — a documented idea.

It serves three purposes:

1. **Building blocks.** The same mechanism (event bus, circuit breaker, state machine, …) is written once, tested once, and typed once.
2. **Visibility.** A `require` of a module named after the pattern tells the reader which pattern is in use.
3. **Idea pool.** Patterns are collected even when they look impractical right now. Every module says honestly when it is not worth using in Lua.

> Status: **catalogue and plan** (stage 1). The `impl`/`idea` modules are added in later stages; rows marked *planned* do not exist yet. Existing modules are **not** renamed — the catalogue points at them.

## Stages

| Stage | Meaning | Module |
| --- | --- | --- |
| `reuse` | lib.nvim already has the pattern as a feature module; the catalogue links to it. No second name. | existing module |
| `impl` | Small, tested reference implementation, classless where possible (closures, module tables), LuaLS types in `@types/`. | new `lib.lua.patterns.*` / `lib.nvim.patterns.*` |
| `idea` | The pattern is rarely useful in Lua or has no user yet. Still implemented minimally with an example; the README states **`Status: idea pool`** and why it may bring no benefit. | new, as `impl` |

43 patterns: 9 `reuse`, 26 `impl`, 8 `idea`.

## Naming and placement

- Editor-independent patterns: `lib.lua.patterns.<name>`. Anything that needs `vim` (timers, autocmds, buffers): `lib.nvim.patterns.<name>`.
- `<name>` is the pattern name in snake_case (`chain_of_responsibility`, `template_method`).
- One module per directory with `init.lua`, a README from the [template](patterns-template.md), tests in `TESTS/`, types in `@types/` (see [conventions](conventions.md)).
- Lua note: many patterns need no class. Observer is an event table or an autocmd, Strategy is a function table, Facade is the module API, Singleton is the module table itself. The READMEs show the classless form first.

## Catalogue

### Creational (GoF)

| Pattern | Stage | Module | In Lua | Seen in the author's plugins |
| --- | --- | --- | --- | --- |
| [abstract_factory](https://refactoring.guru/design-patterns/abstract-factory) | `idea` | `lib.lua.patterns.abstract_factory` *(planned)* | A table of constructors that always come as a matching set (e.g. one theme = icons + highlights + borders). | `reposcope.nvim/lua/reposcope/controllers/provider_controller.lua:27` |
| [builder](https://refactoring.guru/design-patterns/builder) | `impl` | `lib.lua.patterns.builder` *(planned)* — see also `lib.nvim.bindings.usercmd.composer` (fluent builder) | Chained setters that collect options and a final `build()` that validates once. | `testing.nvim/lua/testing/core/result.lua:98`, `filetree.nvim/lua/filetree/features/system/file_clipboard/backend.lua:119` |
| [factory_method](https://refactoring.guru/design-patterns/factory-method) | `impl` | `lib.lua.patterns.factory_method` *(planned)* | A `new(kind, ...)` that picks the constructor from a table instead of an if/elseif chain. | `runtime-analysis.nvim/lua/runtime-analysis/telemetry/init.lua:376`, `testing.nvim/lua/testing/guard/init.lua:107` |
| [prototype](https://refactoring.guru/design-patterns/prototype) | `impl` | `lib.lua.patterns.prototype` *(planned)* — see also `lib.lua.class` (extend) | Create objects by cloning a template (`vim.deepcopy`, `setmetatable({}, {__index = proto})`). | `streamtap/extension/src/hook.js:471` |
| [singleton](https://refactoring.guru/design-patterns/singleton) | `impl` | `lib.lua.patterns.singleton` *(planned)* | In Lua a module table already is the singleton (`local M = {}`); this module only adds a lazy `once()` holder. | `runtime-analysis.nvim/lua/runtime-analysis/telemetry/init.lua:376`, `testing.nvim/lua/testing/statelock.lua:86` |

### Structural (GoF)

| Pattern | Stage | Module | In Lua | Seen in the author's plugins |
| --- | --- | --- | --- | --- |
| [adapter](https://refactoring.guru/design-patterns/adapter) | `impl` | `lib.lua.patterns.adapter` *(planned)* | Wrap a foreign API into the interface the caller expects (explorer providers, picker backends). | `runtime-analysis.nvim/lua/runtime-analysis/telemetry/lazy.lua:1`, `testing.nvim/lua/testing/dialect/busted.lua:439` |
| [bridge](https://refactoring.guru/design-patterns/bridge) | `idea` | `lib.lua.patterns.bridge` *(planned)* | Split an abstraction from its implementation so both vary independently. | `appkit/crates/appkit-hub/src/hub.rs:7`, `takt/crates/takt-backend/src/lib.rs:85` |
| [composite](https://refactoring.guru/design-patterns/composite) | `impl` | `lib.lua.patterns.composite` *(planned)* — see also `lib.nvim.progress` (fan-out handle) | Treat a group like one element: the same call on a node and on a list of nodes. | `testing.nvim/lua/testing/bindings/usrcmds.lua:611`, `docmap-desktop/src-tauri/src/menu.rs:110` |
| [decorator](https://refactoring.guru/design-patterns/decorator) | `impl` | `lib.lua.patterns.decorator` *(planned)* — see also `lib.strategies.telemetry_wrap` | Wrap a function or object to add behaviour (timing, logging, guards) without changing its API. | `runtime-analysis.nvim/lua/runtime-analysis/telemetry/registry.lua:111`, `testing.nvim/lua/testing/guard/patch.lua:33` |
| [facade](https://refactoring.guru/design-patterns/facade) | `impl` | `lib.lua.patterns.facade` *(planned)* — see also `lib.strategies.eager` (the lib aggregator) | One small module API in front of several submodules; the helper re-exports lazily. | `runtime-analysis.nvim/lua/runtime-analysis/init.lua:132`, `testing.nvim/lua/testing/cli.lua:838` |
| [flyweight](https://refactoring.guru/design-patterns/flyweight) | `idea` | `lib.lua.patterns.flyweight` *(planned)* | Share identical immutable state between many objects (interned strings/tables, shared wrappers). | `runtime-analysis.nvim/lua/runtime-analysis/telemetry/registry.lua:285`, `rules.nvim/lua/rules/util/sandbox.lua:40` |
| [proxy](https://refactoring.guru/design-patterns/proxy) | `reuse` | `lib.lua.lazy` | A stand-in with the same interface that controls access (lazy load, caching, counting). | `runtime-analysis.nvim/lua/runtime-analysis/telemetry/registry.lua:111`, `testing.nvim/lua/testing/guard/patch.lua:33` |

### Behavioral (GoF)

| Pattern | Stage | Module | In Lua | Seen in the author's plugins |
| --- | --- | --- | --- | --- |
| [chain_of_responsibility](https://refactoring.guru/design-patterns/chain-of-responsibility) | `impl` | `lib.lua.patterns.chain_of_responsibility` *(planned)* — see also `lib.nvim.bindings.autocmd.dispatcher` | An ordered list of handlers; the first one that claims the request ends the chain. | `testing.nvim/lua/testing/deps.lua:156`, `casedesk.nvim/lua/casedesk/ai/init.lua:626` |
| [command](https://refactoring.guru/design-patterns/command) | `impl` | `lib.lua.patterns.command` *(planned)* — see also `lib.nvim.bindings.usercmd.composer` | An action as data (`do`/`undo`, name, args) so it can be queued, logged or undone. | `runtime-analysis.nvim/lua/runtime-analysis/bindings/usrcmds.lua:1011`, `testing.nvim/lua/testing/bindings/usrcmds.lua:611` |
| [interpreter](https://refactoring.guru/design-patterns/interpreter) | `idea` | `lib.lua.patterns.interpreter` *(planned)* — see also `lib.lua.range` (tiny grammar) | Evaluate a small grammar by walking its parsed tree; mostly a parser plus an evaluator table. | `testing.nvim/lua/testing/args.lua:590` |
| [iterator](https://refactoring.guru/design-patterns/iterator) | `impl` | `lib.lua.patterns.iterator` *(planned)* | Walk a structure without exposing it: stateful `next()` objects and stateless `for` iterators. | `rules.nvim/lua/rules/engine/gate.lua:26`, `cmdlog.nvim/lua/cmdlog/ui/cycle.lua:9` |
| [mediator](https://refactoring.guru/design-patterns/mediator) | `impl` | `lib.lua.patterns.mediator` *(planned)* — see also `lib.nvim.bindings.autocmd.dispatcher` | Components talk to one coordinator instead of to each other. | `docmap.nvim/lua/docmap/bindings/autocmds.lua:45`, `filetree.nvim/lua/filetree/commands.lua:1` |
| [memento](https://refactoring.guru/design-patterns/memento) | `reuse` | `lib.nvim.checkpoint`, `lib.nvim.ui.kit.history` | Snapshot state so it can be restored (undo stack, file checkpoints, back/forward). | `testing.nvim/lua/testing/isolation/snapshot.lua:1`, `tasks.nvim/lua/tasks_nvim/mutate.lua:2334` |
| [observer](https://refactoring.guru/design-patterns/observer) | `reuse` | `lib.nvim.hooks` | Subscribers are notified on change; `on()` returns the unsubscribe function. | `runtime-analysis.nvim/lua/runtime-analysis/startup/init.lua:200`, `testing.nvim/lua/testing/state.lua:673` |
| [state](https://refactoring.guru/design-patterns/state) | `impl` | `lib.lua.patterns.state` *(planned)* | Behaviour switches with the current state object (a table of handlers per state). | `docmap-desktop/src-tauri/src/main.rs:1283`, `hover.nvim/lua/hover/preview/playback.lua:82` |
| [strategy](https://refactoring.guru/design-patterns/strategy) | `impl` | `lib.lua.patterns.strategy` *(planned)* — see also `lib.strategies` | Interchangeable algorithms behind one call; in Lua usually a function table with a fallback. | `runtime-analysis.nvim/lua/runtime-analysis/curl.lua:107`, `testing.nvim/lua/testing/report/init.lua:16` |
| [template_method](https://refactoring.guru/design-patterns/template-method) | `impl` | `lib.lua.patterns.template_method` *(planned)* — see also `lib.lua.class` | A fixed skeleton whose steps are overridable hooks. | `runtime-analysis.nvim/lua/runtime-analysis/runner.lua:84`, `testing.nvim/lua/testing/dialect/harness_conventions.lua:182` |
| [visitor](https://refactoring.guru/design-patterns/visitor) | `idea` | `lib.lua.patterns.visitor` *(planned)* | Add operations to a node structure from outside via a table of per-kind handlers. | - |

### Modern

| Pattern | Stage | Module | In Lua | Seen in the author's plugins |
| --- | --- | --- | --- | --- |
| registry | `reuse` | `lib.nvim.registry` | Keyed entries that register themselves; lookups answer in registration order. | `runtime-analysis.nvim/lua/runtime-analysis/telemetry/registry.lua:285`, `testing.nvim/lua/testing/dialect/init.lua:89` |
| dependency_injection | `impl` | `lib.lua.patterns.dependency_injection` *(planned)* | Pass collaborators in (constructor/`opts`) instead of requiring them inside; makes fakes trivial in tests. | `runtime-analysis.nvim/lua/runtime-analysis/env.lua:183`, `testing.nvim/lua/testing/run/pool.lua:115` |
| event_bus | `impl` | `lib.lua.patterns.event_bus` *(planned)* — see also `lib.nvim.hooks` | Pure-Lua publish/subscribe on named topics, without the editor. | `casedesk.nvim/lua/casedesk/tabgroup.lua:536`, `filetree.nvim/lua/filetree/features/infra/hooks_api/init.lua:71` |
| middleware | `impl` | `lib.lua.patterns.middleware` *(planned)* | A stage list where each stage gets `(ctx, next)`; request/response pipelines. | `testing.nvim/lua/testing/conformance/catalog.lua:14`, `casedesk.nvim/lua/casedesk/ai/init.lua:626` |
| repository | `idea` | `lib.lua.patterns.repository` *(planned)* — see also `lib.nvim.store` | Hide storage behind a collection-like API (`get`/`put`/`find`/`delete`). | `docmap-desktop/src-tauri/src/main.rs:594`, `cmdlog.nvim/lua/cmdlog/core/store.lua:46` |
| lazy_init | `reuse` | `lib.lua.lazy` | Create or load on first access, not at startup. | `runtime-analysis.nvim/lua/runtime-analysis/startup/init.lua:155`, `testing.nvim/lua/testing/dialect/init.lua:89` |
| null_object | `reuse` | `lib.lua.null` | A do-nothing stand-in instead of `nil` checks. | `runtime-analysis.nvim/lua/runtime-analysis/runner.lua:116`, `testing.nvim/lua/testing/guard/init.lua:38` |
| object_pool | `impl` | `lib.lua.patterns.object_pool` *(planned)* | Reuse expensive objects (scratch buffers, timers) via acquire/release. | `testing.nvim/lua/testing/run/pool.lua:163`, `gitsuite.nvim/lua/gitsuite/features/dashboard/view.lua:1244` |
| promise | `reuse` | `lib.nvim.async` | Futures/coroutine await for non-blocking flows. | `docmap-desktop/src/lib/status-cache.js:14`, `hover.nvim/lua/hover/init.lua:595` |
| debounce | `reuse` | `lib.nvim.debounce` | Collapse bursts of calls into one trailing call. | `runtime-analysis.nvim/lua/runtime-analysis/telemetry/init.lua:840`, `testing.nvim/lua/testing/run/watch.lua:162` |
| throttle | `impl` | `lib.nvim.patterns.throttle` *(planned)* — see also `lib.nvim.debounce` | At most one call per interval (leading and/or trailing). | `runtime-analysis.nvim/lua/runtime-analysis/telemetry/init.lua:840`, `testing.nvim/lua/testing/run/watch.lua:162` |
| circuit_breaker | `impl` | `lib.lua.patterns.circuit_breaker` *(planned)* | After N failures stop calling for a while (closed/open/half-open). | `rules.nvim/lua/rules/engine/checks/init.lua:51`, `ai.nvim/lua/ai/keys.lua:457` |
| retry_backoff | `impl` | `lib.nvim.patterns.retry_backoff` *(planned)* — see also `lib.nvim.cross.fs.mutate` (retry) | Retry with growing delay and a budget. | `my.nvim/lua/my/config/persist.lua:276`, `streamtap/extension/src/sink-link.js:341` |
| cache_aside | `reuse` | `lib.lua.memo`, `lib.nvim.cache` | Look in the cache first, compute and store on a miss. | `runtime-analysis.nvim/lua/runtime-analysis/statusline.lua:54`, `testing.nvim/lua/testing/cache/hash.lua:152` |
| specification | `impl` | `lib.lua.patterns.specification` *(planned)* | Rules as composable predicates (`and_`, `or_`, `not_`). | `docmap-desktop/src-tauri/src/server.rs:99`, `hover.nvim/lua/hover/switches.lua:48` |
| result | `impl` | `lib.lua.patterns.result` *(planned)* — see also `lib.lua.error` | Errors as values: `ok, err` pairs with helpers (`map`, `unwrap_or`). | `runtime-analysis.nvim/lua/runtime-analysis/runner.lua:116`, `testing.nvim/lua/testing/args.lua:590` |
| reducer | `impl` | `lib.lua.patterns.reducer` *(planned)* | State = reduce(state, action); the Elm/MVU architecture for UI state. | `gitsuite.nvim/lua/gitsuite/features/plugins/report_ui/model.lua:38` |
| state_machine | `impl` | `lib.lua.patterns.state_machine` *(planned)* | Declared states and transitions with guards; a table-driven cousin of State. | `docmap-desktop/src-tauri/src/main.rs:1283`, `hover.nvim/lua/hover/preview/playback.lua:82` |
| unit_of_work | `idea` | `lib.lua.patterns.unit_of_work` *(planned)* — see also `lib.lua.context_manager` | Collect changes and commit or roll back as one (bracket around a batch). | `tasks.nvim/lua/tasks_nvim/fsio.lua:68`, `docmap-desktop/src-tauri/src/main.rs:594` |
| saga | `idea` | `lib.lua.patterns.saga` *(planned)* | A multi-step process with a compensating step per action. | `tasks.nvim/lua/tasks_nvim/mutate.lua:2334` |

## By stage

- **reuse** (9): proxy, memento, observer, registry, lazy_init, null_object, promise, debounce, cache_aside
- **impl** (26): builder, factory_method, prototype, singleton, adapter, composite, decorator, facade, chain_of_responsibility, command, iterator, mediator, state, strategy, template_method, dependency_injection, event_bus, middleware, object_pool, throttle, circuit_breaker, retry_backoff, specification, result, reducer, state_machine
- **idea** (8): abstract_factory, bridge, flyweight, interpreter, visitor, repository, unit_of_work, saga

## Not in the catalogue

- **Module / Singleton as a module:** every `local M = {}` file is one; there is nothing to import.
- **Service Locator:** treated as an anti-pattern here; use dependency injection or the registry.
- **Active Record, MVC, MVVM:** architecture styles, not building blocks.

## Related

- [conventions](conventions.md), [modules](modules.md)
- Template for a pattern README: [patterns-template.md](patterns-template.md)
