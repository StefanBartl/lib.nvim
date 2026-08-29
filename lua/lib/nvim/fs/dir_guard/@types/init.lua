---@meta
---@module 'lib.nvim.fs.dir_guard.@types'

---Options for a directory guard. The scope fields are passed straight to
---`lib.nvim.fs.chdir`, so the guard watches and restores exactly that scope.
---@class Lib.Fs.DirGuard.Opts : Lib.Fs.Chdir.Opts
---@field on_violation? fun(new_cwd: string, held: string): boolean? # Called when foreign code changed the cwd, before it is undone. Return `false` to accept the change and release the guard instead.
---@field on_error     fun(err: string)? # Called when restoring the held directory failed (e.g. it was deleted meanwhile).

---A live guard. All methods use dot syntax — the state lives in a closure,
---there is no implicit `self`.
---@class Lib.Fs.DirGuard.Handle
---@field path    fun(): string # The normalized directory currently being held.
---@field is_held fun(): boolean # False once released.
---@field update  fun(new_path: string): boolean, string? # Move the pin to another directory without releasing the guard.
---@field bypass  fun(fn: fun()): boolean, any # Run `fn` with the guard paused; the held directory is restored afterwards if `fn` moved it. Returns `pcall`'s result.
---@field release fun() # Stop guarding. Does not restore the previous directory.

---@class Lib.Fs.DirGuard
---@field hold fun(path: string, opts?: Lib.Fs.DirGuard.Opts): Lib.Fs.DirGuard.Handle?, string?
