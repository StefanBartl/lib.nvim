-- TESTS/git_remote_spec.lua — lib.nvim.git.remote: parse_remote, host_kind,
-- build. Pure string parsing/formatting, no git process and no fixture
-- needed -- moved here verbatim from gitsuite.nvim's
-- TESTS/gitsuite/browse_url_spec.lua (GS-16), which covered the same code
-- before it moved.

return function(H)
  local remote = require("lib.nvim.git.remote")

  -- ── parse_remote ─────────────────────────────────────────────────────────
  H.ok(
    vim.deep_equal(
      remote.parse_remote("https://github.com/StefanBartl/gitsuite.nvim.git"),
      { host = "github.com", owner = "StefanBartl", repo = "gitsuite.nvim" }
    ),
    "parse_remote: an https URL"
  )

  H.ok(
    vim.deep_equal(
      remote.parse_remote("https://gitlab.com/owner/repo"),
      { host = "gitlab.com", owner = "owner", repo = "repo" }
    ),
    "parse_remote: an https URL without a trailing .git"
  )

  H.ok(
    vim.deep_equal(
      remote.parse_remote("git@codeberg.org:owner/repo.git"),
      { host = "codeberg.org", owner = "owner", repo = "repo" }
    ),
    "parse_remote: an SSH shorthand URL (git@host:owner/repo.git)"
  )

  H.ok(
    vim.deep_equal(
      remote.parse_remote("ssh://git@github.com/owner/repo.git"),
      { host = "github.com", owner = "owner", repo = "repo" }
    ),
    "parse_remote: an ssh:// URL"
  )

  H.eq(remote.parse_remote("not a remote url"), nil, "parse_remote: nil for garbage input")

  -- ── host_kind ────────────────────────────────────────────────────────────
  H.eq(remote.host_kind("github.com", {}), "github", "host_kind: github.com built in")
  H.eq(remote.host_kind("gitlab.com", {}), "gitlab", "host_kind: gitlab.com built in")
  H.eq(remote.host_kind("codeberg.org", {}), "codeberg", "host_kind: codeberg.org built in")
  H.eq(
    remote.host_kind("git.example.org", { ["git.example.org"] = "gitlab" }),
    "gitlab",
    "host_kind: looks up a self-hosted instance from the given hosts table"
  )
  H.eq(
    remote.host_kind("unknown.example.org", {}),
    nil,
    "host_kind: nil for an unrecognized, unconfigured host"
  )

  -- ── build ────────────────────────────────────────────────────────────────
  local gh_remote = { host = "github.com", owner = "StefanBartl", repo = "gitsuite.nvim" }

  H.eq(
    remote.build("github", gh_remote, "main", nil),
    "https://github.com/StefanBartl/gitsuite.nvim",
    "build: the repo root when rel_path is nil"
  )

  H.eq(
    remote.build("github", gh_remote, "main", "README.md"),
    "https://github.com/StefanBartl/gitsuite.nvim/blob/main/README.md",
    "build: a github file URL with no line anchor"
  )

  H.eq(
    remote.build("github", gh_remote, "main", "README.md", 5),
    "https://github.com/StefanBartl/gitsuite.nvim/blob/main/README.md#L5",
    "build: a github file URL with a single-line anchor"
  )

  H.eq(
    remote.build("github", gh_remote, "main", "README.md", 5, 9),
    "https://github.com/StefanBartl/gitsuite.nvim/blob/main/README.md#L5-L9",
    "build: a github file URL with a range anchor"
  )

  H.eq(
    remote.build("github", gh_remote, "main", "README.md", 5, 5),
    "https://github.com/StefanBartl/gitsuite.nvim/blob/main/README.md#L5",
    "build: collapses an equal first/last range to a single-line anchor"
  )

  local gitlab_remote = { host = "gitlab.com", owner = "owner", repo = "repo" }
  H.eq(
    remote.build("gitlab", gitlab_remote, "main", "src/x.lua", 1, 3),
    "https://gitlab.com/owner/repo/-/blob/main/src/x.lua#L1-L3",
    "build: a gitlab file URL (different grammar: /-/blob/)"
  )

  local codeberg_remote = { host = "codeberg.org", owner = "owner", repo = "repo" }
  H.eq(
    remote.build("codeberg", codeberg_remote, "main", "src/x.lua"),
    "https://codeberg.org/owner/repo/src/branch/main/src/x.lua",
    "build: a codeberg file URL (different grammar: /src/branch/)"
  )

  -- A tracked file or branch name can legitimately contain a space, '#' or
  -- '?' (all valid on a POSIX filesystem) -- unescaped, any of the three
  -- would truncate or misdirect the URL (a browser reads '#'/'?' as the
  -- fragment/query separator). Each path segment is percent-encoded, '/'
  -- itself left alone so a subdirectory (or a branch containing one) still
  -- reads as a real path rather than a literal "%2F".
  H.eq(
    remote.build("github", gh_remote, "main", "docs/notes #1.md"),
    "https://github.com/StefanBartl/gitsuite.nvim/blob/main/docs/notes%20%231.md",
    "build: percent-encodes '#' and a space in a file name, keeps '/' as the separator"
  )

  H.eq(
    remote.build("github", gh_remote, "feature/x?y", "a.lua"),
    "https://github.com/StefanBartl/gitsuite.nvim/blob/feature/x%3Fy/a.lua",
    "build: percent-encodes '?' in a branch name, but keeps its own real '/' namespace separator intact"
  )
end
