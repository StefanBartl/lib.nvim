# `lib.nvim`

Namespace aggregator for the Neovim-specific helpers — adapters onto the
`vim` API. Accessing a key lazily loads the corresponding submodule:

```lua
local Nvim = require("lib.nvim")
Nvim.notify   -- == require("lib.nvim.notify")
Nvim.map      -- == require("lib.nvim.map")
Nvim.core     -- == require("lib.nvim.core")  (has_exec, simple_echo, …)
```

Direct requiring remains possible and is more tree-shake friendly:

```lua
local notify = require("lib.nvim.notify")
```

See the namespace table in [`doc/lib.nvim.txt`](../../../doc/lib.nvim.txt)
(section 4, `lib.nvim`) for the full module list this namespace covers.
