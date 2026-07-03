# `lib.lua.time.diff` – Time measurement with checkpoint tracking

## Table of content

- [`lib.lua.time.diff` – Time measurement with checkpoint tracking](#libtimediff-time-measurement-with-checkpoint-tracking)
  - [Overview](#overview)
  - [Statistics functions](#statistics-functions)
    - [Basic functions](#basic-functions)
    - [Advanced statistics](#advanced-statistics)
  - [Difference calculation between intervals](#difference-calculation-between-intervals)
    - [1. Between two checkpoints (index)](#1-between-two-checkpoints-index)
    - [2. Checkpoint against statistical values](#2-checkpoint-against-statistical-values)
    - [3. Between statistical values](#3-between-statistical-values)
    - [4. With raw time values](#4-with-raw-time-values)
    - [Supported keywords](#supported-keywords)
  - [Installation](#installation)
  - [Basic usage](#basic-usage)
    - [1. Start the timer](#1-start-the-timer)
    - [2. Set checkpoints](#2-set-checkpoints)
    - [3. Get the total time](#3-get-the-total-time)
    - [4. Intervals between checkpoints](#4-intervals-between-checkpoints)
  - [Dynamic properties for checkpoints](#dynamic-properties-for-checkpoints)
  - [Output of all checkpoints](#output-of-all-checkpoints)
    - [Standard format](#standard-format)
    - [Formatted table](#formatted-table)
  - [Iterator support](#iterator-support)
    - [Simple iterator (numeric values only)](#simple-iterator-numeric-values-only)
    - [Iterator with a custom label](#iterator-with-a-custom-label)
    - [Iterator with label and index](#iterator-with-label-and-index)
    - [Iterator with an override label](#iterator-with-an-override-label)
  - [Multiple independent timers](#multiple-independent-timers)
  - [API reference](#api-reference)
    - [Methods](#methods)
    - [Dynamic properties](#dynamic-properties)
  - [Error handling](#error-handling)
  - [Example: benchmark a function](#example-benchmark-a-function)
  - [Example: iterator with labels](#example-iterator-with-labels)
  - [Example: advanced statistics](#example-advanced-statistics)
  - [Example: performance analysis](#example-performance-analysis)
  - [Technical details](#technical-details)
    - [Statistics calculations](#statistics-calculations)
    - [Coefficient of variation (CV)](#coefficient-of-variation-cv)

---

## Overview

The `lib.lua.time.diff` module offers a simple, precise method to measure time intervals in Lua code. It uses `vim.uv.hrtime()` for nanosecond precision (default) and allows multiple measurement points within a time span.

Every call to `require("lib.lua.time.diff")` creates an independent timer instance with its own state.

**Default unit:** nanoseconds (ns). All methods can optionally accept another unit (`"ms"`, `"us"`, `"s"`).

## Statistics functions

The module offers extensive statistics about the measured intervals:

### Basic functions

```lua
local diff = require("lib.lua.time.diff")

-- Set multiple checkpoints
for i = 1, 5 do
  vim.fn.sleep(math.random(50, 150))
  diff.check()
end

-- Fastest interval
print("Fastest:", diff.fastest("ms"), "ms")

-- Longest interval
print("Longest:", diff.longest("ms"), "ms")

-- Average interval
print("Average:", diff.average("ms"), "ms")

-- Median interval
print("Median:", diff.median("ms"), "ms")
```

### Advanced statistics

```lua
-- Standard deviation
print("StdDev:", diff.stddev("ms"), "ms")

-- Coefficient of variation (in percent)
print("CV:", diff.cv(), "%")
```

---

## Difference calculation between intervals

The `calc_diff()` function is very flexible and can process various kinds of input:

### 1. Between two checkpoints (index)

```lua
local diff = require("lib.lua.time.diff")

diff.check()  -- Checkpoint 1
diff.check()  -- Checkpoint 2
diff.check()  -- Checkpoint 3

-- Difference between checkpoint 1 and 3
local delta = diff.calc_diff(1, 3, "ms")
print("Delta:", delta, "ms")
```

### 2. Checkpoint against statistical values

```lua
-- Checkpoint 2 against the average
local d1 = diff.calc_diff(2, "average", "ms")
print("Checkpoint 2 vs Average:", d1, "ms")

-- Checkpoint 1 against the fastest interval
local d2 = diff.calc_diff(1, "fastest", "ms")
print("Checkpoint 1 vs Fastest:", d2, "ms")

-- Checkpoint 3 against the longest interval
local d3 = diff.calc_diff(3, "longest", "ms")
print("Checkpoint 3 vs Longest:", d3, "ms")

-- Checkpoint 2 against the median
local d4 = diff.calc_diff(2, "median", "ms")
print("Checkpoint 2 vs Median:", d4, "ms")
```

### 3. Between statistical values

```lua
-- Difference between the fastest and longest interval
local range = diff.calc_diff("fastest", "longest", "ms")
print("Range:", range, "ms")

-- Average against median
local diff_avg_med = diff.calc_diff("average", "median", "ms")
print("Avg vs Median:", diff_avg_med, "ms")
```

### 4. With raw time values

```lua
-- Direct comparison with a time value in nanoseconds
local target = 100000000  -- 100ms in ns
local d5 = diff.calc_diff(1, target, "ms")
print("Checkpoint 1 vs 100ms:", d5, "ms")
```

### Supported keywords

| Keyword       | Aliases         | Meaning                  |
|---------------|-----------------|--------------------------|
| `"average"`   | `"avg"`         | average interval         |
| `"fastest"`   | `"min"`         | fastest interval         |
| `"longest"`   | `"max"`         | longest interval         |
| `"median"`    | `"med"`         | median interval          |

**Important:** `calc_diff()` always returns the **absolute value** of the difference (a positive number), regardless of the order of the arguments.

## Installation

The module lives under `lua/lib/time/diff/init.lua`. You import it as usual:

```lua
local diff = require("lib.lua.time.diff")
```

---

## Basic usage

### 1. Start the timer

```lua
local diff = require("lib.lua.time.diff")
diff.start()  -- Starts the time measurement
```

The timer starts automatically when the instance is created. `start()` can be used to reset the timer.

---

### 2. Set checkpoints

```lua
-- Code block 1 (default: nanoseconds)
local first_diff = diff.check()
print("First check:", first_diff, "ns")

-- Code block 2 (explicit milliseconds)
local second_diff = diff.check("ms")
print("Second check:", second_diff, "ms")

-- Code block 3 (microseconds)
local third_diff = diff.check("us")
print("Third check:", third_diff, "us")
```

Every call to `check()` returns the elapsed time since `start()`.

**Available units:**
- `"ns"` – nanoseconds (default)
- `"us"` – microseconds
- `"ms"` – milliseconds
- `"s"` – seconds

---

### 3. Get the total time

```lua
-- Default: nanoseconds
local total = diff.result()
print("Total time:", total, "ns")

-- Explicit milliseconds
local total_ms = diff.result("ms")
print("Total time:", total_ms, "ms")
```

Alternatively, you can use the last checkpoint time directly:

```lua
print("Total:", diff.last)  -- Always in nanoseconds
```

---

### 4. Intervals between checkpoints

You compute differences directly:

```lua
local delta = third_diff - first_diff
print("Time between the first and third check:", delta, "ns")
```

Or with dynamic properties:

```lua
print("Delta:", diff.third - diff.first, "ns")
```

---

## Dynamic properties for checkpoints

The module automatically creates properties for all existing checkpoints:

| Property      | Meaning                                      |
|---------------|----------------------------------------------|
| `diff.first`  | first checkpoint (if present)                |
| `diff.second` | second checkpoint (if present)               |
| `diff.third`  | third checkpoint (if present)                |
| `diff.fourth` | fourth checkpoint (if present)               |
| ...           | up to `tenth` (tenth checkpoint)             |
| `diff.last`   | last checkpoint (always present if >0)       |

**Important:** properties always return values in **nanoseconds**.

Example:

```lua
local diff = require("lib.lua.time.diff")

diff.check()  -- First checkpoint
diff.check()  -- Second checkpoint

print(diff.first)   -- First checkpoint in ns
print(diff.second)  -- Second checkpoint in ns
print(diff.last)    -- Last checkpoint in ns (same as second)

-- If only one checkpoint exists:
local diff2 = require("lib.lua.time.diff")
diff2.check()
print(diff2.first)  -- Works
print(diff2.second) -- nil (not present)
```

---

## Output of all checkpoints

### Standard format

```lua
-- Default: nanoseconds
print(diff.results())
-- Output: "Check 1: 12345678ns | Check 2: 23456789ns | ... | Total: 45678901ns | Fastest: 10000000ns | Longest: 15000000ns | Average: 12500000ns | Range: 5000000ns"

-- Explicit milliseconds
print(diff.results("ms"))
-- Output: "Check 1: 12.345ms | Check 2: 23.456ms | ... | Total: 45.678ms | Fastest: 10.000ms | Longest: 15.000ms | Average: 12.500ms | Range: 5.000ms"
```

Or with metatable magic:

```lua
print(diff())        -- Default: nanoseconds
print(diff("ms"))    -- Explicit milliseconds
```

### Formatted table

For better readability in `:messages` or notify windows:

```lua
-- Default: nanoseconds
print(diff.pretty())

-- Explicit milliseconds
print(diff.pretty("ms"))
```

Example output (milliseconds):

```
┌────────┬─────────────────┬─────────────────┐
│ Index  │  Elapsed (ms)   │   Delta (ms)    │
├────────┼─────────────────┼─────────────────┤
│      1 │       12.345    │       12.345    │
│      2 │       23.456    │       11.111    │
│      3 │       45.678    │       22.222    │
├────────┴─────────────────┴─────────────────┤
│ Total:     45.678ms                        │
├────────────────────────────────────────────┤
│ Statistics:                                │
├────────────────────────────────────────────┤
│ Fastest Δ:       11.111ms                  │
│ Longest Δ:       22.222ms                  │
│ Average Δ:       15.226ms                  │
│ Median Δ:        12.345ms                  │
│ Range:           11.111ms                  │
│ Std Dev:          5.555ms                  │
│ CV:              36.50%                    │
└────────────────────────────────────────────┘
```

---

## Iterator support

You can iterate sequentially through all checkpoints:

### Simple iterator (numeric values only)

```lua
diff.reset_iterator()  -- Jump back to the start

while true do
  local t = diff.next()  -- Default: ns
  if not t then break end
  print("Next checkpoint:", t, "ns")
end
```

### Iterator with a custom label

```lua
-- Set a label
diff.reset_iterator("Checkpoint")

while true do
  local output = diff.next(nil, "ms")  -- With a unit
  if not output then break end
  print(output)  -- "Checkpoint 12.345ms"
end
```

### Iterator with label and index

```lua
-- Enable label and index display
diff.reset_iterator("Checkpoint", true)

while true do
  local output = diff.next(nil, "ms")
  if not output then break end
  print(output)  -- "Checkpoint 1: 12.345ms"
end
```

### Iterator with an override label

```lua
diff.reset_iterator("Checkpoint", true)

-- First next() with the default label
print(diff.next(nil, "ms"))  -- "Checkpoint 1: 12.345ms"

-- Second next() with an override label
print(diff.next("Custom", "ms"))  -- "Custom 2: 23.456ms"

-- Third next() again with the default label
print(diff.next(nil, "ms"))  -- "Checkpoint 3: 45.678ms"
```

---

## Multiple independent timers

Every `require` call creates a new instance:

```lua
local timer1 = require("lib.lua.time.diff")
local timer2 = require("lib.lua.time.diff")

timer1.start()
-- ... code ...
timer1.check()

timer2.start()
-- ... other code ...
timer2.check()

print(timer1.result())  -- Independent of timer2
print(timer2.result())
```

---

## API reference

### Methods

| Method                          | Parameters                       | Returns          | Description                                       |
|---------------------------------|----------------------------------|------------------|---------------------------------------------------|
| `start()`                       | -                                | `nil`            | Starts or resets the timer                        |
| `check(unit?)`                  | `"ns"\|"us"\|"ms"\|"s"`          | `number`         | Sets a checkpoint, returns time since start       |
| `result(unit?)`                 | `"ns"\|"us"\|"ms"\|"s"`          | `number\|nil`    | Returns the total time (last checkpoint)          |
| `get(idx, unit?)`               | `integer, "ns"\|"us"\|"ms"\|"s"` | `number\|nil`    | Returns the time for checkpoint `idx`             |
| `next(label?, unit?)`           | `string?, "ns"\|"us"\|"ms"\|"s"` | `string\|number\|nil` | Returns the next checkpoint (iterator)       |
| `reset_iterator(label?, show?)` | `string?, boolean`               | `nil`            | Resets the iterator, optionally with label/index  |
| `results(unit?)`                | `"ns"\|"us"\|"ms"\|"s"`          | `string`         | Creates a summary of all checkpoints              |
| `pretty(unit?)`                 | `"ns"\|"us"\|"ms"\|"s"`          | `string`         | Creates a formatted table                         |

### Dynamic properties

| Property       | Type            | Description                   |
|----------------|-----------------|-------------------------------|
| `first`        | `number\|nil`   | first checkpoint (ns)         |
| `second`       | `number\|nil`   | second checkpoint (ns)        |
| `third`        | `number\|nil`   | third checkpoint (ns)         |
| `fourth`-`tenth` | `number\|nil` | fourth to tenth checkpoint (ns) |
| `last`         | `number\|nil`   | last checkpoint (ns)          |

**Important:** properties always return values in nanoseconds, regardless of the unit chosen in `check()`.

---

## Error handling

If `check()` is called without using `start()` first:

```lua
local diff = require("lib.lua.time.diff")
-- start() is called automatically, but on a manual reset:
diff.start()
diff.check()  -- OK
```

If an invalid unit is passed:

```lua
diff.check("invalid")  -- Error: "Invalid unit: invalid"
```

---

## Example: benchmark a function

```lua
local diff = require("lib.lua.time.diff")

diff.start()

-- Code block 1
for i = 1, 1000000 do
  math.sqrt(i)
end
local t1 = diff.check("ms")

-- Code block 2
for i = 1, 1000000 do
  math.sin(i)
end
local t2 = diff.check("ms")

print(diff.pretty("ms"))
print("Difference:", t2 - t1, "ms")

-- Or with properties
print("Delta:", diff.second - diff.first, "ns")  -- Properties are in ns!

-- Statistics
print("Fastest interval:", diff.fastest("ms"), "ms")
print("Longest interval:", diff.longest("ms"), "ms")
print("Average interval:", diff.average("ms"), "ms")
```

## Example: iterator with labels

```lua
local diff = require("lib.lua.time.diff")

-- Set three checkpoints
for i = 1, 3 do
  vim.fn.sleep(100)
  diff.check()
end

-- Iterator with label and index
diff.reset_iterator("Measurement", true)

while true do
  local output = diff.next(nil, "ms")
  if not output then break end
  print(output)
  -- Output:
  -- "Measurement 1: 100.123ms"
  -- "Measurement 2: 200.456ms"
  -- "Measurement 3: 300.789ms"
end
```

## Example: advanced statistics

```lua
local diff = require("lib.lua.time.diff")

-- Simulate variable execution times
for i = 1, 10 do
  vim.fn.sleep(math.random(50, 150))
  diff.check()
end

-- Detailed statistics
print(diff.pretty("ms"))

-- Retrieve individual values
print("\nDetailed analysis:")
print("Fastest:", diff.fastest("ms"), "ms")
print("Longest:", diff.longest("ms"), "ms")
print("Average:", diff.average("ms"), "ms")
print("Median:", diff.median("ms"), "ms")
print("StdDev:", diff.stddev("ms"), "ms")
print("CV:", diff.cv(), "%")

-- Compute differences
print("\nDifferences:")
print("Range (longest - fastest):", diff.calc_diff("fastest", "longest", "ms"), "ms")
print("Checkpoint 1 vs Average:", diff.calc_diff(1, "average", "ms"), "ms")
print("Checkpoint 5 vs Median:", diff.calc_diff(5, "median", "ms"), "ms")
```

## Example: performance analysis

```lua
local diff = require("lib.lua.time.diff")

-- Benchmark multiple operations
local operations = {
  "string concatenation",
  "table insertion",
  "math operations",
  "file I/O simulation"
}

for _, op in ipairs(operations) do
  -- Simulate the operation
  for i = 1, 100000 do
    math.sqrt(i)
  end
  diff.check()
end

print(diff.pretty("us"))  -- Output in microseconds

-- Find the slowest operation
local longest_idx = 1
local longest_val = diff.get(1)
for i = 2, #operations do
  local val = diff.get(i)
  if val > longest_val then
    longest_idx = i
    longest_val = val
  end
end

print("\nSlowest operation:", operations[longest_idx])
print("Time:", diff.get(longest_idx, "ms"), "ms")

-- Compare with the average
print("\nDeviation from the average:")
for i, op in ipairs(operations) do
  local dev = diff.calc_diff(i, "average", "ms")
  print(string.format("%s: %+.3fms", op, dev))
end
```

---

## Technical details

- **Precision**: nanoseconds (via `vim.uv.hrtime()`)
- **Default unit**: nanoseconds (ns)
- **Available units**: `"ns"`, `"us"`, `"ms"`, `"s"`
- **Return values**: floating-point number
- **Properties**: always in nanoseconds
- **Metatable**: supports `__call` and `__tostring` for direct invocation
- **Independence**: each instance has its own state
- **Dynamic properties**: up to 10 named checkpoints (`first` to `tenth`) + `last`
- **Statistics**: min/max/avg/median/stddev/CV are computed from the intervals between checkpoints

### Statistics calculations

**Intervals vs. checkpoints:**
- checkpoints are cumulative times since start
- intervals are differences between consecutive checkpoints
- statistics refer to intervals (deltas)

**Example:**
```lua
-- 3 checkpoints at 10ms, 25ms, 50ms
diff.check()  -- Checkpoint 1: 10ms (interval 1: 10ms)
diff.check()  -- Checkpoint 2: 25ms (interval 2: 15ms)
diff.check()  -- Checkpoint 3: 50ms (interval 3: 25ms)

-- Statistics refer to the intervals:
-- fastest = 10ms (interval 1)
-- longest = 25ms (interval 3)
-- average = (10 + 15 + 25) / 3 = 16.67ms
```

### Coefficient of variation (CV)

The CV expresses the relative dispersion in percent:
- CV = (standard deviation / mean) × 100
- low values (< 10%): consistent performance
- medium values (10-30%): moderate variation
- high values (> 30%): strongly fluctuating performance

---
