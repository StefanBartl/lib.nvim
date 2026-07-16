---@meta
---@module 'lib.lua.time.format.@types'

---@alias LibTimeFormatStyle "iso"|"human"|"short"|"log"|"filename"|"unix"

---@class LibTimeFormatOpts
---@field utc boolean? When true, format in UTC instead of local time.

---@class LibTimeFormat
---@field format_timestamp fun(ts?: integer, fmt?: LibTimeFormatStyle, opts?: LibTimeFormatOpts): string
