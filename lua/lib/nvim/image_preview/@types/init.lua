---@meta
---@module 'lib.nvim.image_preview.@types'

---Which in-Neovim image preview backend was detected.
---@alias Lib.ImagePreview.Provider "images.nvim"|"snacks"|"image.nvim"

--- `lib.nvim.image_preview` module surface.
---@class Lib.ImagePreview
---@field detect fun(): Lib.ImagePreview.Provider|nil # Which provider is available, if any. images.nvim preferred when several are installed.
---@field available fun(): boolean # Whether an in-Neovim preview is possible at all (`detect() ~= nil`).
---@field preview fun(path: string): boolean, string|nil # Preview `path` in a floating window using the detected provider.

return {}
