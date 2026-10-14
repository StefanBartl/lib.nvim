-- TESTS/shell_quote_spec.lua — lib.nvim.cross.shell_quote (pure shell quoting)
-- Ported from terminal.nvim's quote_spec; the property and real-PowerShell specs stay there.

return function(H)
  local quote = require("lib.nvim.cross.shell_quote")
  local shells = dofile(
    vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/support/shell_models.lua"
  )

  -- A minimal luassert look-alike over the harness: the ported cases keep their text.
  -- It is also callable like the global `assert(value, message)`, which the ported file still uses.
  local plain_assert = _G.assert
  local assert = setmetatable({
    equals = function(expected, actual, msg)
      H.eq(actual, expected, msg)
    end,
    is_nil = function(v, msg)
      H.eq(v, nil, msg)
    end,
    truthy = function(v, msg)
      H.ok(v, msg)
    end,
    same = function(expected, actual, msg)
      H.ok(vim.deep_equal(expected, actual), (msg or "same") .. ": " .. vim.inspect(actual))
    end,
  }, {
    __call = function(_, ...)
      return plain_assert(...)
    end,
  })
  local path = {}
  local function describe(name, fn)
    path[#path + 1] = name
    fn()
    path[#path] = nil
  end
  local function it(name, fn)
    local ok, err = pcall(fn)
    if not ok then
      error(table.concat(path, " > ") .. " > " .. name .. ": " .. tostring(err), 0)
    end
  end

  -- Strings an attacker (or an unlucky file name) could use to break out of a quoted word.
  local HOSTILE = {
    "a b",
    "it's",
    'say "hi"',
    "$(whoami)",
    "`id`",
    "a;b",
    "a&b",
    "a|b",
    "a>b",
    "%PATH%",
    "$HOME",
    "-rf",
    "--flag=x",
    "",
    "ünïcödé",
    "back\\slash",
    "=ls", -- zsh replaces a bare =ls by the path of ls
  }

  describe("shell_quote", function()
    describe("shell_kind with arguments", function()
      it("finds the family in a command string", function()
        assert.equals("powershell", quote.shell_kind("pwsh -NoLogo"))
        assert.equals(
          "powershell",
          quote.shell_kind('"C:\\Program Files\\PowerShell\\7\\pwsh.exe" -NoLogo')
        )
        assert.equals("cmd", quote.shell_kind("cmd.exe /k"))
        assert.equals("posix", quote.shell_kind("bash -l"))
      end)

      it("does not mistake a path component that merely contains the name", function()
        assert.equals("posix", quote.shell_kind("/opt/mycmdtools/zsh"))
      end)
    end)

    describe("fish", function()
      it(
        "is recognised by name, path or command string, and not by a path component that contains it",
        function()
          assert.equals("fish", quote.shell_kind("fish"))
          assert.equals("fish", quote.shell_kind("/usr/bin/fish"))
          assert.equals("fish", quote.shell_kind("fish -l"))
          assert.equals("posix", quote.shell_kind("/opt/fisheye/zsh"))
        end
      )

      it("escapes the backslash and the quote: inside '...' fish reads both as escapes", function()
        assert.equals("'it\\'s'", quote.word("it's", "fish"))
        assert.equals("'a\\\\b'", quote.word("a\\b", "fish"))
        assert.equals("'\\\\'", quote.word("\\", "fish"))
        assert.equals("''", quote.word("", "fish"))
        assert.equals("plain", quote.word("plain", "fish"))
      end)

      it(
        "round-trips what POSIX quoting would break: a word that holds backslash and quote",
        function()
          for _, word in ipairs({ "\\'; touch x; '", "a\\", "\\\\", "it's \\ here", "x\\'y" }) do
            local line = quote.argv_to_line({ "echo", word }, "fish")
            assert.same({ "echo", word }, shells.fish(line), word)
          end
        end
      )
    end)

    describe("shell_kind", function()
      it("recognises the families from a name or a path", function()
        assert.equals("powershell", quote.shell_kind("pwsh"))
        assert.equals("powershell", quote.shell_kind("C:\\Program Files\\PowerShell\\7\\pwsh.exe"))
        assert.equals("powershell", quote.shell_kind("powershell.exe"))
        assert.equals("cmd", quote.shell_kind("C:\\Windows\\System32\\cmd.exe"))
        assert.equals("posix", quote.shell_kind("/usr/bin/zsh"))
        assert.equals("posix", quote.shell_kind(nil))
        assert.equals("posix", quote.shell_kind(""))
      end)
    end)

    describe("posix", function()
      it("leaves safe words alone and quotes the rest", function()
        assert.equals("ls", quote.word("ls", "posix"))
        assert.equals("/usr/bin/x_y-z.1", quote.word("/usr/bin/x_y-z.1", "posix"))
        assert.equals("'a b'", quote.word("a b", "posix"))
        assert.equals("''", quote.word("", "posix"))
      end)

      it("escapes an embedded single quote", function()
        assert.equals([['it'\''s']], quote.word("it's", "posix"))
      end)

      it(
        "leaves option-looking words bare: quoting cannot stop option parsing, `--` does",
        function()
          assert.equals("-rf", quote.word("-rf", "posix"))
          assert.equals("--flag=x", quote.word("--flag=x", "posix"))
          assert.equals("'--flag=a b'", quote.word("--flag=a b", "posix"))
        end
      )

      it(
        "makes every hostile word one shell word: safe characters only, or fully quoted",
        function()
          for _, w in ipairs(HOSTILE) do
            local q = quote.word(w, "posix")
            -- the bare set: `=` is safe everywhere but in the first place (zsh: =ls is a path)
            if q:find("^[%w%._/:@%%+,-][%w%._/:=@%%+,-]*$") == nil then
              assert.equals("'", q:sub(1, 1), w)
              assert.equals("'", q:sub(-1), w)
            end
          end
        end
      )

      it("quotes a word that STARTS with '=': zsh would replace =ls by the path of ls", function()
        assert.equals("'=ls'", quote.word("=ls", "posix"))
        assert.equals("'=nosuchcmd'", quote.word("=nosuchcmd", "posix"))
        assert.equals("'='", quote.word("=", "posix"))
        assert.equals("'==x'", quote.word("==x", "posix"))
        -- inside a word `=` is literal in every shell: it stays readable
        assert.equals("a=b", quote.word("a=b", "posix"))
        assert.equals("--flag=x", quote.word("--flag=x", "posix"))
        assert.equals("printf '=ls' tail", quote.argv_to_line({ "printf", "=ls", "tail" }, "posix"))
      end)

      it(
        "quotes a FIRST word that is not a plain program name; arguments keep their set",
        function()
          for _, kind in ipairs({ "posix", "fish" }) do
            -- `A=b echo INJECTED` runs INJECTED and eats the program word as an assignment
            assert.equals(
              "'A=b' echo INJECTED",
              quote.argv_to_line({ "A=b", "echo", "INJECTED" }, kind),
              kind
            )
            assert.equals(
              "'PATH=/tmp/evil' ls",
              quote.argv_to_line({ "PATH=/tmp/evil", "ls" }, kind)
            )
            assert.equals("'x=' y", quote.argv_to_line({ "x=", "y" }, kind), kind)
            -- `.` is source, `:` the null command, `%1` a job, `-` a precommand modifier in zsh
            for _, special in ipairs({ ".", ":", "%1", "-", "-x", "@x", "a:b", "a,b", "~" }) do
              assert.equals(
                "'" .. special .. "' x",
                quote.argv_to_line({ special, "x" }, kind),
                kind .. " " .. special
              )
            end
            assert.equals("''", quote.argv_to_line({ "" }, kind), kind)
            -- the same words as arguments need no quotes (`=` is literal there)
            assert.equals(
              "echo A=b a:b a,b",
              quote.argv_to_line({ "echo", "A=b", "a:b", "a,b" }, kind)
            )
            -- plain program names stay readable
            for _, name in ipairs({
              "git",
              "ls",
              "node18",
              "g++",
              "x_y-z.1",
              "/usr/bin/env",
              "./run.sh",
              "../bin/tool",
              "..",
              ".hidden",
              "a-b",
            }) do
              assert.equals(
                name .. " x",
                quote.argv_to_line({ name, "x" }, kind),
                kind .. " " .. name
              )
            end
          end
          -- the single-word form asks for the program rule through its third argument
          assert.equals("'A=b'", quote.word("A=b", "posix", true))
          assert.equals("A=b", quote.word("A=b", "posix"))
          assert.equals("'A=b'", quote.word("A=b", "fish", true))
          assert.equals("A=b", quote.word("A=b", "fish"))
        end
      )

      it(
        "quotes a reserved word as the FIRST word: `time -v make` is a keyword, not a program",
        function()
          for _, kind in ipairs({ "posix", "fish" }) do
            for _, word in ipairs({ "time", "if", "while", "select", "case", "else", "end", "not" }) do
              assert.equals(
                "'" .. word .. "' -v",
                quote.argv_to_line({ word, "-v" }, kind),
                kind .. " " .. word
              )
              -- an ARGUMENT of that name is only text
              assert.equals("echo " .. word, quote.argv_to_line({ "echo", word }, kind), kind)
            end
            -- not reserved, only similar: stays readable
            assert.equals("times -v", quote.argv_to_line({ "times", "-v" }, kind), kind)
            assert.equals("timeout 5", quote.argv_to_line({ "timeout", "5" }, kind), kind)
          end
        end
      )

      -- bash reads `time` first on a line as its keyword; the quoted word is the program. Registered
      -- only where bash exists and the machine is not Windows (a skipped case would count as not green).
      if vim.fn.has("win32") == 0 and shells.installed("bash") then
        it("bash runs a program called `time` instead of timing the next word", function()
          local dir = vim.fn.tempname()
          vim.fn.mkdir(dir, "p")
          local program = dir .. "/time"
          vim.fn.writefile({ "#!/bin/sh", 'echo "program-ran $*"' }, program)
          vim.uv.fs_chmod(program, 493) -- 0755
          local line = assert(quote.argv_to_line({ "time", "-v", "make" }, "posix"))
          local res = vim
            .system(
              { vim.fn.exepath("bash"), "-c", line },
              { clear_env = true, env = { PATH = dir .. ":/usr/bin:/bin" } }
            )
            :wait(10000)
          vim.fn.delete(dir, "rf")
          assert.equals(0, res.code, (res.stderr or "") .. "\n" .. line)
          assert.equals("program-ran -v make\n", res.stdout, line)
        end)
      end

      -- A shell exists on every Linux and macOS machine, not on a stock Windows one: registered only
      -- where it can run (a skipped case would count as not green).
      if vim.fn.has("win32") == 0 then
        it("sh runs a program called NAME=value instead of reading an assignment", function()
          local dir = vim.fn.tempname()
          vim.fn.mkdir(dir, "p")
          local program = dir .. "/A=b"
          vim.fn.writefile({ "#!/bin/sh", "echo program-ran" }, program)
          vim.uv.fs_chmod(program, 493) -- 0755
          local line = assert(quote.argv_to_line({ "A=b", "echo", "INJECTED" }, "posix"))
          -- PATH holds only the directory with the program and the system's own: an unquoted
          -- `A=b echo INJECTED` would set a variable and print INJECTED instead
          local res = vim
            .system(
              { "/bin/sh", "-c", line },
              { clear_env = true, env = { PATH = dir .. ":/usr/bin:/bin" } }
            )
            :wait(10000)
          vim.fn.delete(dir, "rf")
          assert.equals(0, res.code, (res.stderr or "") .. "\n" .. line)
          assert.equals("program-ran\n", res.stdout, line)
        end)
      end

      -- zsh exists on Linux and macOS machines, not on a stock Windows one: the case is registered
      -- only where it can run (a skipped case would count as not green).
      if shells.installed("zsh") then
        it("zsh reads every hostile word back as itself, =ls and =nosuchcmd included", function()
          local words =
            vim.list_extend(vim.deepcopy(HOSTILE), { "=nosuchcmd", "==", "a=b", "=a=b" })
          local argv = vim.list_extend({ "printf", "%s\\n" }, words)
          local line = assert(quote.argv_to_line(argv, "posix"))
          -- -f: no startup files of the machine; -c: the line is the whole script. A bare `=ls`
          -- (the old behaviour) makes zsh search the PATH for `ls` and for `nosuchcmd`: a short PATH
          -- keeps that fast where the machine's PATH is long or slow (WSL lists the Windows one).
          local zsh = { vim.fn.exepath("zsh"), "-f", "-c", line }
          local res =
            vim.system(zsh, { clear_env = true, env = { PATH = "/usr/bin:/bin" } }):wait(10000)
          assert.equals(0, res.code, (res.stderr or "") .. "\n" .. line)
          -- printf ends every word with a line break, and no word contains one
          local got = vim.split(res.stdout or "", "\n", { plain = true })
          table.remove(got)
          assert.same(words, got, line)
        end)
      end
    end)

    describe("powershell", function()
      it("doubles an embedded single quote", function()
        assert.equals("'it''s'", quote.word("it's", "powershell"))
      end)

      it("single-quotes $(...) and backticks so nothing expands", function()
        assert.equals("'$(whoami)'", quote.word("$(whoami)", "powershell"))
        assert.equals("'`id`'", quote.word("`id`", "powershell"))
      end)

      it("doubles the typographic single quotes PowerShell also treats as quotes", function()
        for _, q in ipairs({ "\226\128\152", "\226\128\153", "\226\128\154", "\226\128\155" }) do
          local w = quote.word("x" .. q .. ";Write-Output INJECTED;" .. q, "powershell")
          assert.equals("'x" .. q .. q .. ";Write-Output INJECTED;" .. q .. q .. "'", w)
        end
      end)

      it("quotes words that would splat, build an array or read as an alias", function()
        assert.equals("'@args'", quote.word("@args", "powershell"))
        assert.equals("'a,b'", quote.word("a,b", "powershell"))
        assert.equals("'%'", quote.word("%", "powershell"))
        assert.equals("'a+b'", quote.word("a+b", "powershell"))
      end)

      it("adds the call operator when the program word itself is quoted", function()
        local line = quote.argv_to_line({ "C:\\Program Files\\x.exe", "a b" }, "powershell")
        assert.equals("& 'C:\\Program Files\\x.exe' 'a b'", line)
        assert.equals("git status", quote.argv_to_line({ "git", "status" }, "powershell"))
      end)

      it(
        "quotes a program word that is a keyword or reads as a number, with the call operator",
        function()
          -- bare, `if x` is a ParserError and `7 x` is the number 7; `& 'if' x` runs the program
          for _, word in ipairs({ "if", "While", "for", "7", "0x10", "1kb", "7z", "exit" }) do
            assert.equals(
              "& '" .. word .. "' x",
              quote.argv_to_line({ word, "x" }, "powershell"),
              word
            )
            -- as an argument the same word is only text
            assert.equals("echo " .. word, quote.argv_to_line({ "echo", word }, "powershell"), word)
          end
          -- only the exact words: a name that merely starts like one is a name
          assert.equals("iftop x", quote.argv_to_line({ "iftop", "x" }, "powershell"))
          assert.equals("git7 x", quote.argv_to_line({ "git7", "x" }, "powershell"))
        end
      )

      it("refuses a word with a double quote: a program may receive it split or cut", function()
        -- Windows PowerShell 5.1 turns the first of these into three arguments, drops the quote of
        -- the second and swallows the third one's space.
        for _, word in ipairs({ 'x\\" --injected=1 "y', 'a"b', 'a" b', '"', 'say "hi"' }) do
          local w, err = quote.word(word, "powershell")
          assert.is_nil(w, word)
          assert.truthy(err and err:find("double quote", 1, true), err)
          assert.truthy(err and err:find("`direct = true`", 1, true), err)
          local line, line_err = quote.argv_to_line({ "git", "log", word }, "powershell")
          assert.is_nil(line, word)
          assert.truthy(line_err and line_err:find("argument 3: ", 1, true), line_err)
        end
      end)

      it(
        "refuses a word with white space that ends in a backslash: it swallows the next argument",
        function()
          local spaces = {
            " ",
            "\194\133", -- NEXT LINE
            "\194\160", -- NO-BREAK SPACE
            "\225\154\128", -- OGHAM SPACE MARK
            "\226\128\131", -- EM SPACE
            "\226\128\138", -- HAIR SPACE
            "\226\128\168", -- LINE SEPARATOR
            "\226\128\175", -- NARROW NO-BREAK SPACE
            "\226\129\159", -- MEDIUM MATHEMATICAL SPACE
            "\227\128\128", -- IDEOGRAPHIC SPACE
          }
          for _, space in ipairs(spaces) do
            for _, word in ipairs({
              "C:\\my" .. space .. "dir\\",
              "a" .. space .. "b\\\\",
              space .. "\\",
            }) do
              local w, err = quote.word(word, "powershell")
              assert.is_nil(w, vim.inspect(word))
              assert.truthy(err and err:find("backslash", 1, true), err)
              assert.truthy(err and err:find("`direct = true`", 1, true), err)
            end
          end
          local line = quote.argv_to_line({ "dir", "C:\\my dir\\", "tail" }, "powershell")
          assert.is_nil(line)
        end
      )

      it("keeps accepting the words every PowerShell hands over intact", function()
        -- a trailing backslash without white space is not wrapped in double quotes
        assert.equals("C:\\dir\\", quote.word("C:\\dir\\", "powershell"))
        -- white space with a backslash that is not the last character
        assert.equals("'C:\\my dir\\file'", quote.word("C:\\my dir\\file", "powershell"))
        assert.equals("'a\\ b'", quote.word("a\\ b", "powershell"))
        -- typographic double quotes are no quotes to the C runtime; neither is a letter whose UTF-8
        -- bytes end in 0xA0 (U+00E0) or the zero-width space next to the space separators
        assert.equals(
          "'a\226\128\156b c\226\128\157'",
          quote.word("a\226\128\156b c\226\128\157", "powershell")
        )
        assert.equals("'\195\160\\'", quote.word("\195\160\\", "powershell"))
        assert.equals("'a\226\128\139b\\'", quote.word("a\226\128\139b\\", "powershell"))
      end)

      it("refuses the empty word and `--%`: a real PowerShell drops both on the way", function()
        -- `grep '' file` would reach grep as `grep file`; `--%` is PowerShell's stop-parsing token
        -- and goes away even when it is quoted. Every other argument would move up one place.
        for _, word in ipairs({ "", "--%" }) do
          local w, err = quote.word(word, "powershell")
          assert.is_nil(w, word)
          assert.truthy(err and err:find("`direct = true`", 1, true), err)
          local line, line_err = quote.argv_to_line({ "grep", word, "file" }, "powershell")
          assert.is_nil(line, word)
          assert.truthy(line_err and line_err:find("argument 2: ", 1, true), line_err)
          -- the program word too
          assert.is_nil((quote.argv_to_line({ word, "x" }, "powershell")), word)
        end
        -- only the whole word is the token: neighbours of `--%` and a blank word are fine
        assert.equals("'--%x'", quote.word("--%x", "powershell"))
        assert.equals("'x--%'", quote.word("x--%", "powershell"))
        assert.equals("' '", quote.word(" ", "powershell"))
        -- the other families keep the empty word: they pass it on
        assert.equals("''", quote.word("", "posix"))
        assert.equals("''", quote.word("", "fish"))
        assert.equals('""', quote.word("", "cmd"))
      end)

      it("single-quotes a word that starts with '-' and holds ':' or '.' (-name:value)", function()
        -- Once a bare `--` is on the line PowerShell reads `-x:y` as a parameter with a value and
        -- hands the program `-x:` and `y`; `-I./include` arrives as `-I` and `./include`. Single
        -- quotes keep the word whole.
        for _, word in ipairs({
          "-x:y",
          "-p:80",
          "-ErrorAction:Stop",
          "-Dkey:value",
          "-o:out.txt",
          "-L:C:/lib",
          "-a-b:c",
          "--flag:x",
          "-:",
          "-I./include",
          "-a.",
          "-a.b",
          "-o.out",
          "-a/.",
          "-_.x",
          "-1.5",
          "--a.b",
          "-.",
        }) do
          assert.equals("'" .. word .. "'", quote.word(word, "powershell"), word)
        end
        -- a colon or dot elsewhere and a dash elsewhere stay bare, as do options without either
        assert.equals("C:/lib", quote.word("C:/lib", "powershell"))
        assert.equals("a-b:c", quote.word("a-b:c", "powershell"))
        assert.equals("a-b.c", quote.word("a-b.c", "powershell"))
        assert.equals("./include", quote.word("./include", "powershell"))
        assert.equals("x-y", quote.word("x-y", "powershell"))
        assert.equals("-rf", quote.word("-rf", "powershell"))
        assert.equals("--verbose", quote.word("--verbose", "powershell"))
        assert.equals("--no-color", quote.word("--no-color", "powershell"))
        assert.equals("-1", quote.word("-1", "powershell"))
        assert.equals("-a/b\\c", quote.word("-a/b\\c", "powershell"))
      end)
    end)

    describe("cmd", function()
      it("double-quotes unsafe words and doubles embedded quotes", function()
        assert.equals('"a b"', quote.word("a b", "cmd"))
        assert.equals('"say ""hi"""', quote.word('say "hi"', "cmd"))
        assert.equals('""', quote.word("", "cmd"))
      end)

      it("refuses a word with a percent sign: cmd.exe cannot quote it", function()
        local w, err = quote.word("%PATH%", "cmd")
        assert.is_nil(w)
        assert.truthy(err:find("%", 1, true))
        assert.is_nil((quote.argv_to_line({ "echo", "100%" }, "cmd")))
      end)

      it("doubles backslashes before the closing quote", function()
        assert.equals('"C:\\my dir\\\\"', quote.word("C:\\my dir\\", "cmd"))
      end)

      it("quotes a program word that cmd.exe would take apart: `/`, `,`, a leading `@`", function()
        -- `./tool.exe x` runs `.` with the switch `/tool.exe`; `a,b` is two words; `@` is the echo prefix
        for _, word in ipairs({ "./tool.exe", "sub/p.exe", "C:\\a\\Smith,John\\tool.exe", "@tool" }) do
          assert.equals('"' .. word .. '" x', quote.argv_to_line({ word, "x" }, "cmd"), word)
          -- as an argument the same word needs no quotes
          assert.equals("tool " .. word, quote.argv_to_line({ "tool", word }, "cmd"), word)
        end
        -- a program word without them stays readable
        assert.equals("tool.exe x", quote.argv_to_line({ "tool.exe", "x" }, "cmd"))
        assert.equals("C:\\x\\tool.exe x", quote.argv_to_line({ "C:\\x\\tool.exe", "x" }, "cmd"))
      end)

      it(
        "doubles backslashes in front of an EMBEDDED quote too (else the C runtime reads a literal quote)",
        function()
          assert.equals('"a\\\\"" b"', quote.word('a\\" b', "cmd"))
          -- the argument-injection word: it used to come out as three arguments
          local word = 'a\\" --injected=1 "b'
          local line = quote.argv_to_line({ "node", word }, "cmd")
          assert.same({ "node", word }, shells.msvcrt(line))
        end
      )
    end)

    describe("argv_to_line", function()
      it("joins quoted words with single spaces", function()
        local line = quote.argv_to_line({ "git", "commit", "-m", "a b" }, "posix")
        assert.equals("git commit -m 'a b'", line)
      end)

      it("refuses an empty argv and a non-table", function()
        local line, err = quote.argv_to_line({}, "posix")
        assert.is_nil(line)
        assert.truthy(err)
        -- Deliberately wrong type: the case checks the guard.
        ---@diagnostic disable-next-line: param-type-mismatch
        assert.is_nil((quote.argv_to_line(nil, "posix")))
      end)

      it("refuses TAB: readline completes INSIDE the quotes and closes them", function()
        local line, err = quote.argv_to_line({ "echo", "x\t; touch f #" }, "posix")
        assert.is_nil(line)
        assert.truthy(err:find("TAB", 1, true), err)
      end)

      it("refuses non-string words", function()
        -- Deliberately wrong type: the case checks the guard.
        ---@diagnostic disable-next-line: assign-type-mismatch
        local line, err = quote.argv_to_line({ "echo", 3 }, "posix")
        assert.is_nil(line)
        assert.truthy(err:find("argument 2", 1, true))
      end)

      it("refuses a hole in the list instead of dropping the words behind it", function()
        -- `opt` is nil: `ipairs` and `#` stop at the hole, and `--dry-run` would be lost -- the
        -- command that was meant to be a dry run is not
        local opt = nil
        local argv = { "git", "clean", "-fd", opt, "--dry-run" }
        for _, kind in ipairs({ "posix", "fish", "powershell", "cmd", "portable" }) do
          local line, err = quote.argv_to_line(argv, kind)
          assert.is_nil(line, kind)
          assert.truthy(err and err:find("argument 4", 1, true), kind .. ": " .. tostring(err))
        end
        -- a hole in front, and a list with only holes at the front
        assert.is_nil((quote.argv_to_line({ nil, "ls" }, "posix")))
        assert.equals(0, quote.arg_count({}))
        assert.equals(0, quote.arg_count("git"))
        assert.equals(5, quote.arg_count(argv))
        assert.equals(2, quote.arg_count({ "a", "b" }))
      end)

      it(
        "refuses control characters: a line break ends the command line, ESC is interpreted",
        function()
          for _, bad in ipairs({ "a\nb", "a\rb", "a\0b", "a\27[31mb", "a\127b", "a\tb" }) do
            for _, kind in ipairs({ "posix", "fish", "powershell", "cmd" }) do
              local line = quote.argv_to_line({ "echo", bad }, kind)
              assert.is_nil(line, ("%s / %q"):format(kind, bad))
            end
          end
        end
      )
    end)

    describe("portable", function()
      it(
        "refuses a word that starts with a dash and holds ':' or '.' (PowerShell splits it)",
        function()
          -- `-a:b` reaches a program as `-a:` and `b`, `-I./include` as `-I` and `./include`
          for _, word in ipairs({ "-a:b", "-x.", "-I./include", "-ErrorAction:Stop", "-1.5" }) do
            local line, err = quote.argv_to_line({ "prog", "--", word, "tail" }, "portable")
            assert.is_nil(line, word)
            assert.truthy(err and err:find("argument 3", 1, true), word .. ": " .. tostring(err))
          end
        end
      )

      it("still accepts what every shell reads the same way", function()
        assert.equals(
          "prog -v --version a-b:c ./x/y.lua",
          quote.argv_to_line({ "prog", "-v", "--version", "a-b:c", "./x/y.lua" }, "portable")
        )
      end)
    end)
  end)
end
