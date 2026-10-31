# Design pattern modules

`lib.lua.patterns.*` (editor-independent) and `lib.nvim.patterns.*` (needs the editor). Catalogue, stages and
the rules for when to use a pattern: [../patterns.md](../patterns.md). Each module has a `README.md` next to its
source with the worked example and the "when it helps / when it does not" section.

Both namespaces have a lazy aggregator: `require("lib.lua.patterns").result` is
`require("lib.lua.patterns.result")`.

Conventions: `obj:method()` is a method call on a table made by the module; `->` marks return values; a
trailing `?` marks an optional parameter.

## `lib.lua.patterns.*` — mechanism

- **result** — `ok(v)`, `err(e)`, `from_pair(value, err)`, `from_pcall(fn, ...)`, `is_result(x)`;
  `r:is_ok()`, `r:map(fn)`, `r:map_err(fn)`, `r:and_then(fn)`, `r:unwrap_or(d)`, `r:unwrap()`, `r:to_pair() -> value, err`.
- **specification** — `new(fn)`, `all(list)`, `any(list)`; `s:is_satisfied_by(x)` (also `s(x)`), `s:and_(o)`, `s:or_(o)`, `s:not_()`.
- **middleware** — `new()`; `chain:use(stage)`, `chain:run(ctx, final?)`. A stage is `fn(ctx, next)`.
- **circuit_breaker** — `new({ threshold?, reset_ms?, now?, on_change? })`; `b:call(fn, ...) -> ok, value_or_err`,
  `b:state() -> "closed"|"open"|"half_open"`, `b:reset()`.
- **state_machine** — `new({ initial, transitions?, on_enter?, on_exit?, ctx? })`; `sm:fire(event, ...) -> ok, state_or_reason`,
  `sm:can(event)`, `sm:is(s)`, `sm:state()`, `sm:on_change(fn) -> unsubscribe`.
- **object_pool** — `new({ create, reset?, destroy?, max? })`; `p:acquire()`, `p:release(obj)`, `p:with(fn)`, `p:clear()`, `p:stats()`.
- **event_bus** — `new()`; `b:on(topic, fn) -> unsubscribe`, `b:once(topic, fn)`, `b:emit(topic, ...) -> called, errors`,
  `b:count(topic)`, `b:clear(topic?)`.

## `lib.lua.patterns.*` — creational

- **builder** — `new(schema) -> constructor`; `b:<field>(v)`, `b:set(name, v)`, `b:get(name)`, `b:build() -> product | nil, err`.
- **factory_method** — `new(ctors?, { default? })`; `f:register(kind, ctor)`, `f:create(kind, ...)`, `f:kinds()`.
- **prototype** — `new(template)`, `deepcopy(v)`; `p:clone(overrides?)`.
- **singleton** — `new(factory)`; `s:get()`, `s:is_created()`, `s:reset()`.
- **abstract_factory** — `new(families)`; `f:names()`, `f:family(name)`, `f:create(name, product, ...)`. *(idea)*

## `lib.lua.patterns.*` — structural

- **adapter** — `new(interface, adaptee, map?) -> table`.
- **bridge** — `new(abstraction, impl, required?) -> table`. *(idea)*
- **composite** — `new(children?)`; `g:add(child)`, `g:remove(child)`, `g:size()`, `g:call(method, ...) -> results, errors`.
- **decorator** — `wrap(fn, ...decorators)`, `before(hook)`, `after(hook)`, `guard(pred, otherwise?)`, `timed(sink, clock?)`.
- **facade** — `new(spec) -> table` with `names()` and `loaded()`; entries are a module path, `"module:function"` or a function.
- **flyweight** — `new(make, { key?, weak? })`; `f:get(...)`, `f:size()`, `f:clear()`. *(idea)*

## `lib.lua.patterns.*` — behavioral

- **chain_of_responsibility** — `new()`; `c:add(name, fn, { first? })`, `c:remove(name)`, `c:names()`,
  `c:handle(request, ...) -> handled, result, handler_name, errors`.
- **command** — `history({ limit? })`; `h:run(cmd, ...)`, `h:undo() -> name|nil`, `h:redo() -> name|nil`, `h:can_undo()`,
  `h:can_redo()`, `h:names()`, `h:clear()`. A command is `{ name?, run, undo? }`.
- **interpreter** — `new(rules) -> eval(node, env)`. *(idea)*
- **iterator** — `of(list)`, `range(first, last, step?)`, `from_fn(next_fn)`; `it:next()`, `it:peek()`, `it:has_next()`,
  `it:map(fn)`, `it:filter(pred)`, `it:take(n)`, `it:drop(n)`, `it:collect()`, `it:each(fn)`, `it:reduce(fn, init)`, `it:iter()`.
- **mediator** — `new()`; `m:register(name, component)`, `m:unregister(name)`, `m:send(from, to, message, ...)`,
  `m:broadcast(from, message, ...) -> reached, errors`, `m:names()`.
- **state** — `new({ states, initial, fields? }) -> object` with `set_state(name)`, `current_state()`, `is_state(name)`
  plus the methods of the current state.
- **strategy** — `new(strategies, { default? })`; `s:register(name, fn)`, `s:use(name)`, `s:selected()`, `s:run(...)`,
  `s:call(name, ...)`, `s:names()`.
- **template_method** — `define({ steps, run }) -> { implement(impl) -> function }`.
- **visitor** — `new(handlers, { kind?, default? }) -> visit(node, ...)`, `walk(root, children, fn)`. *(idea)*

## `lib.lua.patterns.*` — modern

- **dependency_injection** — `new(parent?)`; `c:provide(name, factory, { transient? })`, `c:value(name, v)`, `c:has(name)`,
  `c:resolve(name)`, `c:child()`.
- **repository** — `memory() -> store`, `new(store)`; `r:get(id)`, `r:save(id, v)`, `r:remove(id)`, `r:all()`,
  `r:find(pred)`, `r:filter(pred)`, `r:count()`. A store is `{ get, put, delete, all }`. *(idea)*
- **reducer** — `store(reduce, initial)`, `combine(slices)`; `s:state()`, `s:dispatch(action) -> ok, state_or_err`,
  `s:subscribe(fn) -> unsubscribe`.
- **unit_of_work** — `new(store)`; `u:add(id, v)`, `u:change(id, v)`, `u:remove(id)`, `u:pending()`, `u:rollback()`,
  `u:commit() -> ok, err, failed_step`. *(idea)*
- **saga** — `run(steps, ctx?) -> ok, ctx_or_err, report`. A step is `{ name?, run, compensate? }`. *(idea)*

## `lib.nvim.patterns.*`

- **throttle** — `new(fn, ms, { leading?, trailing? }) -> { call, cancel, flush }`.
- **retry_backoff** — `run(task, opts)` where `task(attempt, done)`; `delay(attempt, opts) -> ms`.
  Options: `max_attempts`, `base_ms`, `factor`, `max_ms`, `jitter`, `should_retry`, `on_done`, `sleep`.
