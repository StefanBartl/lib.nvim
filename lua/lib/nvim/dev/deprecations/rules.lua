---@module 'lib.nvim.dev.deprecations.rules'
--- The default rule table of `lib.nvim.dev.deprecations`: deprecated Neovim
--- Lua/API calls and what replaces them. Pure data, loaded on the first scan,
--- never at startup.
---@description
--- `pattern` is a Lua pattern matched against a line whose comments and string
--- contents are blanked out, so it only ever sees code. `%f[%w_]` / `%f[^%w_]`
--- frontiers keep `nvim_exec` from matching `nvim_exec2` or `nvim_exec_lua`.
--- `since` is the Neovim version that deprecated the call: a rule is only
--- active on a Neovim at least that new, because on an older one the
--- replacement may not exist yet. `unless` skips a line that already carries
--- the replacement as a fallback (`vim.uv or vim.loop`).
---
--- Deliberately left out: deprecations a line pattern cannot tell apart from
--- the current form (`vim.validate{...}` table form, `client.request` dot
--- calls, `vim.diagnostic.enable(bufnr)`), and anything that is a convention
--- rather than a Neovim deprecation (`vim.notify` -> a project notifier).

---@type Lib.Dev.Deprecations.Rule[]
return {
  -- 0.9 --------------------------------------------------------------------
  {
    id = "nvim_exec",
    pattern = "%f[%w_]nvim_exec%f[^%w_]",
    replacement = "nvim_exec2()",
    since = "0.9",
  },
  {
    id = "nvim_get_hl_by_name",
    pattern = "%f[%w_]nvim_get_hl_by_name%f[^%w_]",
    replacement = "nvim_get_hl(0, { name = ... })",
    since = "0.9",
  },
  {
    id = "nvim_get_hl_by_id",
    pattern = "%f[%w_]nvim_get_hl_by_id%f[^%w_]",
    replacement = "nvim_get_hl(0, { id = ... })",
    since = "0.9",
  },
  {
    id = "vim.treesitter.query.get_query",
    pattern = "vim%.treesitter%.query%.get_query%f[^%w_]",
    replacement = "vim.treesitter.query.get()",
    since = "0.9",
  },
  {
    id = "vim.treesitter.query.parse_query",
    pattern = "vim%.treesitter%.query%.parse_query%f[^%w_]",
    replacement = "vim.treesitter.query.parse()",
    since = "0.9",
  },
  {
    id = "vim.treesitter.query.get_node_text",
    pattern = "vim%.treesitter%.query%.get_node_text%f[^%w_]",
    replacement = "vim.treesitter.get_node_text()",
    since = "0.9",
  },
  {
    id = "vim.treesitter.get_node_at_pos",
    pattern = "vim%.treesitter%.get_node_at_pos%f[^%w_]",
    replacement = "vim.treesitter.get_node()",
    since = "0.9",
  },

  -- 0.10 -------------------------------------------------------------------
  {
    id = "vim.loop",
    pattern = "vim%.loop%f[^%w_]",
    replacement = "vim.uv",
    since = "0.10",
    unless = "vim%.uv",
  },
  {
    id = "nvim_buf_get_option",
    pattern = "%f[%w_]nvim_buf_get_option%f[^%w_]",
    replacement = "nvim_get_option_value(name, { buf = ... })",
    since = "0.10",
  },
  {
    id = "nvim_buf_set_option",
    pattern = "%f[%w_]nvim_buf_set_option%f[^%w_]",
    replacement = "nvim_set_option_value(name, value, { buf = ... })",
    since = "0.10",
  },
  {
    id = "nvim_win_get_option",
    pattern = "%f[%w_]nvim_win_get_option%f[^%w_]",
    replacement = "nvim_get_option_value(name, { win = ... })",
    since = "0.10",
  },
  {
    id = "nvim_win_set_option",
    pattern = "%f[%w_]nvim_win_set_option%f[^%w_]",
    replacement = "nvim_set_option_value(name, value, { win = ... })",
    since = "0.10",
  },
  {
    id = "nvim_get_option",
    pattern = "%f[%w_]nvim_get_option%f[^%w_]",
    replacement = "nvim_get_option_value(name, {})",
    since = "0.10",
  },
  {
    id = "nvim_set_option",
    pattern = "%f[%w_]nvim_set_option%f[^%w_]",
    replacement = "nvim_set_option_value(name, value, {})",
    since = "0.10",
  },
  {
    id = "vim.tbl_flatten",
    pattern = "vim%.tbl_flatten%f[^%w_]",
    replacement = "vim.iter(t):flatten(math.huge):totable()",
    since = "0.10",
  },
  {
    id = "vim.tbl_islist",
    pattern = "vim%.tbl_islist%f[^%w_]",
    replacement = "vim.islist()",
    since = "0.10",
  },
  {
    id = "vim.tbl_add_reverse_lookup",
    pattern = "vim%.tbl_add_reverse_lookup%f[^%w_]",
    replacement = "a plain loop (no replacement)",
    since = "0.10",
  },
  {
    id = "vim.lsp.get_active_clients",
    pattern = "vim%.lsp%.get_active_clients%f[^%w_]",
    replacement = "vim.lsp.get_clients()",
    since = "0.10",
  },
  {
    id = "vim.lsp.buf_get_clients",
    pattern = "vim%.lsp%.buf_get_clients%f[^%w_]",
    replacement = "vim.lsp.get_clients({ bufnr = ... })",
    since = "0.10",
  },
  {
    id = "vim.lsp.get_buffers_by_client_id",
    pattern = "vim%.lsp%.get_buffers_by_client_id%f[^%w_]",
    replacement = "vim.lsp.get_client_by_id(id).attached_buffers",
    since = "0.10",
  },
  {
    id = "vim.diagnostic.disable",
    pattern = "vim%.diagnostic%.disable%f[^%w_]",
    replacement = "vim.diagnostic.enable(false, filter)",
    since = "0.10",
  },
  {
    id = "vim.diagnostic.is_disabled",
    pattern = "vim%.diagnostic%.is_disabled%f[^%w_]",
    replacement = "not vim.diagnostic.is_enabled(filter)",
    since = "0.10",
  },

  -- 0.11 -------------------------------------------------------------------
  {
    id = "termopen",
    pattern = "%f[%w_]termopen%f[^%w_]",
    replacement = "jobstart(cmd, { term = true })",
    since = "0.11",
  },
  {
    id = "nvim_buf_add_highlight",
    pattern = "%f[%w_]nvim_buf_add_highlight%f[^%w_]",
    replacement = "vim.hl.range() / nvim_buf_set_extmark()",
    since = "0.11",
  },
  {
    id = "nvim_err_writeln",
    pattern = "%f[%w_]nvim_err_writeln%f[^%w_]",
    replacement = "nvim_echo(chunks, true, { err = true })",
    since = "0.11",
  },
  {
    id = "nvim_err_write",
    pattern = "%f[%w_]nvim_err_write%f[^%w_]",
    replacement = "nvim_echo(chunks, true, { err = true })",
    since = "0.11",
  },
  {
    id = "nvim_out_write",
    pattern = "%f[%w_]nvim_out_write%f[^%w_]",
    replacement = "nvim_echo(chunks, true, {})",
    since = "0.11",
  },
  {
    id = "vim.highlight",
    pattern = "vim%.highlight%f[^%w_]",
    replacement = "vim.hl",
    since = "0.11",
  },
  {
    id = "vim.lsp.util.jump_to_location",
    pattern = "vim%.lsp%.util%.jump_to_location%f[^%w_]",
    replacement = "vim.lsp.util.show_document(location, encoding, { focus = true })",
    since = "0.11",
  },
  {
    id = "vim.lsp.start_client",
    pattern = "vim%.lsp%.start_client%f[^%w_]",
    replacement = "vim.lsp.start()",
    since = "0.11",
  },
  {
    id = "vim.lsp.buf.execute_command",
    pattern = "vim%.lsp%.buf%.execute_command%f[^%w_]",
    replacement = "client:exec_cmd()",
    since = "0.11",
  },
  {
    id = "vim.diagnostic.goto_next",
    pattern = "vim%.diagnostic%.goto_next%f[^%w_]",
    replacement = "vim.diagnostic.jump({ count = 1 })",
    since = "0.11",
  },
  {
    id = "vim.diagnostic.goto_prev",
    pattern = "vim%.diagnostic%.goto_prev%f[^%w_]",
    replacement = "vim.diagnostic.jump({ count = -1 })",
    since = "0.11",
  },
  {
    id = "vim.diagnostic.get_next_pos",
    pattern = "vim%.diagnostic%.get_next_pos%f[^%w_]",
    replacement = "vim.diagnostic.get_next()",
    since = "0.11",
  },
  {
    id = "vim.diagnostic.get_prev_pos",
    pattern = "vim%.diagnostic%.get_prev_pos%f[^%w_]",
    replacement = "vim.diagnostic.get_prev()",
    since = "0.11",
  },
}
