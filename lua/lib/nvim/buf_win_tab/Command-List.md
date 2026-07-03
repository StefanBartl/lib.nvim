# Overview of commands in the `lib.nvim.buf_win_tab` module

## Table of content

  - [ASCII overview](#ascii-overview)
  - [lib.nvim.buf_win_tab.buffer_utils](#libbuf_win_tabbuffer_utils)
  - [lib.nvim.buf_win_tab.windows_utils](#libbuf_win_tabwindows_utils)
  - [lib.nvim.buf_win_tab.tabs_utils](#libbuf_win_tabtabs_utils)
  - [lib.nvim.buf_win_tab.neotree](#libbuf_win_tabneotree)

---

## ASCII overview

buf_win_tab/
├─ buffer_utils
│  ├─ DEFAULT_EXCLUDE_FILETYPES : string[]
│  ├─ count_listed_buffers() -> integer
│  ├─ get_buffer_info(bufnr) -> table
│  ├─ count_real_listed_buffers(exclude_filetypes?: string[]) -> integer
│  ├─ list_all_buffers_info() -> table[]
│  ├─ list_listed_buffers_info() -> table[]
│  ├─ format_buffers_table(buftable: table[]) -> string
│  ├─ print_buffers_table(buftable: table[]) -> nil
│  ├─ collect_all_buffer_info() -> table
│  └─ print_summary() -> nil
│
├─ windows_utils
│  ├─ count_listed_buffers() -> integer
│  ├─ list_all_buffers_info() -> table[]
│  ├─ get_listed_buffer_ids() -> integer[]
│  ├─ get_buffers_grouped_by_filetype() -> table<string, integer[]>
│  ├─ get_current_buffer_info() -> table
│  ├─ get_tabpage_buffers(tabnr?: integer) -> integer[]
│  ├─ format_buffers_report() -> string
│  ├─ collect_all_state() -> table
│  └─ show_aggregated_state(silent?: boolean) -> string|nil
│
├─ tabs
│  ├─ list_tabs() -> TabInfo[]
│  ├─ format_tab_one_line(info: TabInfo) -> string
│  ├─ print_tabs(tabs?: TabInfo[]) -> nil
│  ├─ get_current_tab() -> TabInfo?
│  ├─ get_tab_by_number(tabnr: integer) -> TabInfo?
│  ├─ is_single_tab() -> boolean
│  └─ collect_report() -> table
│
└─ neotree
   ├─ find_neotree_window() -> number|nil
   ├─ open_neotree_and_focus(neotree_cmd?: string) -> boolean
   ├─ setup_autotree_on_last_close(opts?: table) -> nil
   ├─ only_nonfile_listed_buffers() -> boolean
   └─ open_neotree_if_last_buffer() -> boolean



## lib.nvim.buf_win_tab.buffer_utils

| Name                        | Signature                                   | Description                                                                                        |
| --------------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `DEFAULT_EXCLUDE_FILETYPES` | `string[]`                                  | Default list of filetypes/buffer names excluded when counting "real" user buffers.                 |
| `count_listed_buffers`      | `() -> integer`                             | Counts all listed buffers.                                                                         |
| `get_buffer_info`           | `() -> table`                               | Returns metadata for a buffer.                                                                     |
| `count_real_listed_buffers` | `(exclude_filetypes?: string[]) -> integer` | Counts listed buffers, excluding plugin/ephemeral buffers.                                         |
| `list_all_buffers_info`     | `() -> table[]`                             | Returns an array of metadata for all buffers.                                                      |
| `list_listed_buffers_info`  | `() -> table[]`                             | Returns an array of metadata for all listed buffers.                                               |
| `format_buffers_table`      | `(buftable: table[]) -> string`             | Formats a buffer table into a human-readable multi-line string.                                    |
| `print_buffers_table`       | `(buftable: table[]) -> nil`                | Prints a buffer table to the command line.                                                         |
| `collect_all_buffer_info`   | `() -> table`                               | Collects all buffer information, including counts and formatted lists.                             |
| `print_summary`             | `() -> nil`                                 | Prints a compact summary of the current buffers.                                                   |

---

## lib.nvim.buf_win_tab.windows_utils

| Name                              | Signature                        | Description                                                            |                                                        |
| --------------------------------- | -------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------ |
| `count_listed_buffers`            | `() -> integer`                  | Counts all listed buffers (platform-agnostic).                        |                                                        |
| `list_all_buffers_info`           | `() -> table[]`                  | Returns metadata for all buffers, normalized.                         |                                                        |
| `get_listed_buffer_ids`           | `() -> integer[]`                | Returns a list of all listed buffer IDs.                              |                                                        |
| `get_buffers_grouped_by_filetype` | `() -> table<string, integer[]>` | Groups buffer IDs by filetype.                                        |                                                        |
| `get_current_buffer_info`         | `() -> table`                    | Returns information about the current buffer.                         |                                                        |
| `get_tabpage_buffers`             | `(tabnr?: integer) -> integer[]` | Returns buffer IDs for a tabpage (or the current tab when nil).       |                                                        |
| `format_buffers_report`           | `() -> string`                   | Formats a compact report of all buffers.                             |                                                        |
| `collect_all_state`               | `() -> table`                    | Collects various state information about buffers, tabs, platform.     |                                                        |
| `show_aggregated_state`           | `(silent?: boolean) -> string    | nil`                                                                   | Prints aggregated state, optionally only as a string.  |

---

## lib.nvim.buf_win_tab.tabs_utils

| Name                  | Signature                      | Description                                                        |
| --------------------- | ------------------------------ | ------------------------------------------------------------------ |
| `list_tabs`           | `() -> TabInfo[]`              | Returns a list of all tabpages with window and buffer info.        |
| `format_tab_one_line` | `(info: TabInfo) -> string`    | Formats a TabInfo into a compact one-line description.             |
| `print_tabs`          | `(tabs?: TabInfo[]) -> nil`    | Pretty-prints the tabs via `vim.notify`.                          |
| `get_current_tab`     | `() -> TabInfo?`               | Returns the TabInfo of the current tabpage.                        |
| `get_tab_by_number`   | `(tabnr: integer) -> TabInfo?` | Returns the TabInfo for a specific tab number.                     |
| `is_single_tab`       | `() -> boolean`                | Checks whether only one tab is open.                               |
| `collect_report`      | `() -> table`                  | Collects structured information about all tabs.                    |

---

## lib.nvim.buf_win_tab.neotree

| Name                           | Signature                           | Description                                                                     |                                                 |
| ------------------------------ | ----------------------------------- | ------------------------------------------------------------------------------- | ----------------------------------------------- |
| `find_neotree_window`          | `() -> number                       | nil`                                                                            | Finds a Neo-tree window ID, if present.         |
| `open_neotree_and_focus`       | `(neotree_cmd?: string) -> boolean` | Runs a Neo-tree command and focuses the window.                                 |                                                 |
| `setup_autotree_on_last_close` | `(opts?: table) -> nil`             | Autocommand that opens Neo-tree when the last "real" buffers are closed.        |                                                 |
| `only_nonfile_listed_buffers`  | `() -> boolean`                     | Checks whether only non-file buffers are listed.                               |                                                 |
| `open_neotree_if_last_buffer`  | `() -> boolean`                     | Opens Neo-tree when the last file buffer was closed.                            |                                                 |

---
