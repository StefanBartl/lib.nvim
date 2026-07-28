# `lib.nvim.store`

Persistent-storage namespace — currently a thin re-export of
[`lib.nvim.store.project`](./project/README.md).

## Usage

```lua
local store = require("lib.nvim.store")

store.project.save("cascade/anchors", { version = 1 })
```

Requiring the submodule directly is equally valid and stays tree-shake
friendly:

```lua
local project = require("lib.nvim.store.project")
```

See [`lib.nvim.store.project`](./project/README.md) for the actual save/load/
clear/stats API and its git-root-keyed, TTL-aware persistence behaviour.
