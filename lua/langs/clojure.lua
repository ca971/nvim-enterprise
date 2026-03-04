---@file lua/langs/clojure.lua
---@description Clojure — REPL-driven development, LSP, linter, Conjure, paredit
---@module "langs.clojure"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps               Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons                 Icon provider (`lang.clojure`, `ui`, `dev`, `diagnostics`)
---@see core.mini-align-registry   Alignment preset registration for Clojure maps/let
---@see langs.java                 Java support (shared JVM ecosystem)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/clojure.lua — Clojure language support                            ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("clojure") → {} if off      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Detection layers:                                               │    ║
--- ║  │  ├─ Project type  deps.edn > project.clj > build.boot > bb.edn   │    ║
--- ║  │  ├─ Filetype      .clj .cljs .cljc .cljd .edn .bb → clojure      │    ║
--- ║  │  └─ CLI tools     clj > lein > bb > boot (fallback chain)        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = "clojure"):                      │    ║
--- ║  │  ├─ LSP         clojure-lsp (completions, refactoring, cljfmt)   │    ║
--- ║  │  ├─ Formatter   clojure-lsp embedded cljfmt (via LSP format)     │    ║
--- ║  │  ├─ Linter      clj-kondo (nvim-lint)                            │    ║
--- ║  │  ├─ Treesitter  clojure parser                                   │    ║
--- ║  │  ├─ REPL        Conjure (nREPL auto-connect, HUD log)            │    ║
--- ║  │  └─ Editing     nvim-paredit (structural s-expression editing)   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (buffer-local, <leader>l group, 16 bindings):           │    ║
--- ║  │  ├─ RUN         r  Run file              R  Run with arguments   │    ║
--- ║  │  ├─ REPL        c  REPL (clj/lein)       j  Jack-in (nREPL)      │    ║
--- ║  │  ├─ EVAL        e  Eval form (n/v)       E  Eval buffer          │    ║
--- ║  │  ├─ TEST        t  Run tests             T  Test namespace       │    ║
--- ║  │  ├─ DOCS        d  Doc for word          s  Source for word      │    ║
--- ║  │  │              h  Clojure reference (browser)                   │    ║
--- ║  │  ├─ TOOLS       p  Deps tree             l  Lint (clj-kondo)     │    ║
--- ║  │  └─ INFO        i  Project info                                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Project type detection (4 build tools):                         │    ║
--- ║  │  ├─ deps.edn    → Clojure CLI (tools.deps)                       │    ║
--- ║  │  ├─ project.clj → Leiningen                                      │    ║
--- ║  │  ├─ build.boot  → Boot                                           │    ║
--- ║  │  └─ bb.edn      → Babashka (scripting runtime)                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Conjure integration:                                            │    ║
--- ║  │  ├─ Auto-connects to nREPL on buffer open                        │    ║
--- ║  │  ├─ HUD log window (SE anchor, 42% width)                        │    ║
--- ║  │  ├─ Tree-sitter form extraction                                  │    ║
--- ║  │  ├─ Eval highlight (150ms timeout)                               │    ║
--- ║  │  └─ <localleader> prefix for Conjure-native keymaps              │    ║
--- ║  │                                                                  │    ║
--- ║  │  Jack-in nREPL command (deps.edn):                               │    ║
--- ║  │  clj -Sdeps '{:deps {nrepl/nrepl {:mvn/version "1.1.1"}          │    ║
--- ║  │              cider/cider-nrepl {:mvn/version "0.47.1"}}}'        │    ║
--- ║  │      -M -m nrepl.cmdline                                         │    ║
--- ║  │      --middleware '["cider.nrepl/cider-middleware"]'             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Mini.align integration:                                         │    ║
--- ║  │  ├─ Preset: clojure_map (align map pairs by whitespace)          │    ║
--- ║  │  ├─ Preset: clojure_let (align let bindings by whitespace)       │    ║
--- ║  │  ├─ <leader>aL  Align Clojure map                                │    ║
--- ║  │  └─ <leader>aT  Align Clojure let                                │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (set on FileType clojure):                               ║
--- ║  • 2 spaces, expandtab        (Lisp indentation convention)              ║
--- ║  • lisp=true + lispwords      (Vim built-in Lisp indent support)         ║
--- ║  • colorcolumn=100             (Clojure community line length)           ║
--- ║  • commentstring=";; %s"      (Clojure comment syntax)                   ║
--- ║  • treesitter foldexpr         (foldmethod=expr, foldlevel=99)           ║
--- ║                                                                          ║
--- ║  Documentation references (4):                                           ║
--- ║  ├─ ClojureDocs · Clojure Cheatsheet                                     ║
--- ║  └─ ClojureScript · Clojars (package registry)                           ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Clojure support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("clojure") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Clojure Nerd Font icon (trailing whitespace stripped)
local clj_icon = icons.lang.clojure:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group as " Clojure" in which-key for
-- clojure buffers. All lang_map() calls below bind into this group.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("clojure", "Clojure", clj_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — PROJECT DETECTION
--
-- Clojure has multiple build tools, each with its own project file
-- and CLI interface. These helpers detect the project type and resolve
-- the correct CLI command for running, testing, and REPL operations.
--
-- Detection priority:
-- ├─ deps.edn    → Clojure CLI (tools.deps) — modern standard
-- ├─ project.clj → Leiningen — most established, feature-rich
-- ├─ build.boot  → Boot — pipeline-based build system
-- └─ bb.edn      → Babashka — fast scripting runtime (GraalVM)
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the Clojure project type from build files in cwd.
---
--- Checks for build tool configuration files in priority order.
--- Returns `nil` if no recognized project file is found.
---
--- ```lua
--- local ptype = detect_project()
--- if ptype == "deps" then ... end
--- ```
---
---@return "deps"|"lein"|"boot"|"bb"|nil project_type Detected project type, or `nil`
---@private
local function detect_project()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/deps.edn") == 1 then
		return "deps"
	elseif vim.fn.filereadable(cwd .. "/project.clj") == 1 then
		return "lein"
	elseif vim.fn.filereadable(cwd .. "/build.boot") == 1 then
		return "boot"
	elseif vim.fn.filereadable(cwd .. "/bb.edn") == 1 then
		return "bb"
	end
	return nil
end

--- Resolve the run command prefix and label for the detected project.
---
--- Maps project types to their respective CLI run commands:
--- - `deps`  → `"clj -M "`
--- - `lein`  → `"lein run "`
--- - `bb`    → `"bb "`
--- - `boot`  → `"boot "`
--- - `nil`   → fallback to `"clj "` if available, else `nil`
---
--- ```lua
--- local cmd, label = run_cmd()
--- if cmd then
---   vim.cmd.terminal(cmd .. file)
--- end
--- ```
---
---@return string|nil cmd Command prefix (with trailing space), or `nil` if no CLI found
---@return string|nil label Human-readable label for notifications
---@private
local function run_cmd()
	local ptype = detect_project()
	if ptype == "deps" then
		return "clj -M ", "deps.edn"
	elseif ptype == "lein" then
		return "lein run ", "Leiningen"
	elseif ptype == "bb" then
		return "bb ", "Babashka"
	elseif ptype == "boot" then
		return "boot ", "Boot"
	end
	-- ── Fallback: bare clj ───────────────────────────────────────────
	if vim.fn.executable("clj") == 1 then return "clj ", "clj" end
	return nil, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- File execution using the auto-detected project CLI.
-- The run command adapts to deps.edn, Leiningen, Babashka, or Boot.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current Clojure file.
---
--- Auto-detects the project type and uses the appropriate CLI.
--- Saves the buffer before execution and notifies which runner is used.
keys.lang_map("clojure", "n", "<leader>lr", function()
	local cmd, label = run_cmd()
	if not cmd then
		vim.notify("No Clojure CLI found (clj, lein, bb)", vim.log.levels.ERROR, { title = "Clojure" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal(cmd .. vim.fn.shellescape(file))
	vim.notify("Running with " .. label, vim.log.levels.INFO, { title = "Clojure" })
end, { desc = icons.ui.Play .. " Run file" })

--- Run the current file with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, showing the detected
--- runner label in the prompt. Aborts silently if cancelled.
keys.lang_map("clojure", "n", "<leader>lR", function()
	local cmd, label = run_cmd()
	if not cmd then
		vim.notify("No Clojure CLI found", vim.log.levels.ERROR, { title = "Clojure" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.ui.input({ prompt = "Arguments (" .. label .. "): " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal(cmd .. vim.fn.shellescape(file) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL / CONJURE
--
-- Interactive REPL management and Conjure integration.
--
-- Conjure is the primary evaluation engine. It auto-connects to
-- nREPL servers and provides inline evaluation, HUD log window,
-- and tree-sitter-aware form extraction.
--
-- Jack-in starts an nREPL server with CIDER middleware, which
-- Conjure auto-detects and connects to.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open an interactive REPL for the current project.
---
--- REPL command resolution:
--- - `deps`  → `clj` (bare Clojure REPL)
--- - `lein`  → `lein repl` (nREPL-based)
--- - `bb`    → `bb nrepl-server` (Babashka nREPL)
--- - Other   → `clj` if available, else `lein repl`
keys.lang_map("clojure", "n", "<leader>lc", function()
	local ptype = detect_project()
	---@type string
	local cmd
	if ptype == "deps" then
		cmd = "clj"
	elseif ptype == "lein" then
		cmd = "lein repl"
	elseif ptype == "bb" then
		cmd = "bb nrepl-server"
	else
		cmd = vim.fn.executable("clj") == 1 and "clj" or "lein repl"
	end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Terminal .. " REPL" })

--- Jack-in: start an nREPL server with CIDER middleware.
---
--- For `deps.edn` projects, injects nREPL and CIDER dependencies
--- via `-Sdeps` and starts the nREPL command-line server with the
--- CIDER middleware stack. Conjure auto-connects once the server
--- is ready.
---
--- For `project.clj` projects, uses `lein repl` which includes
--- nREPL support out of the box.
---
--- Requires either `deps.edn` or `project.clj` in the project root.
keys.lang_map("clojure", "n", "<leader>lj", function()
	local ptype = detect_project()
	---@type string
	local cmd
	if ptype == "deps" then
		cmd = 'clj -Sdeps \'{:deps {nrepl/nrepl {:mvn/version "1.1.1"}'
			.. ' cider/cider-nrepl {:mvn/version "0.47.1"}}}\''
			.. " -M -m nrepl.cmdline"
			.. " --middleware '[\"cider.nrepl/cider-middleware\"]'"
	elseif ptype == "lein" then
		cmd = "lein repl"
	else
		vim.notify("Jack-in requires deps.edn or project.clj", vim.log.levels.WARN, { title = "Clojure" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
	vim.notify("nREPL starting — Conjure will auto-connect", vim.log.levels.INFO, { title = "Clojure" })
end, { desc = clj_icon .. " Jack-in (nREPL)" })

--- Eval the current form at cursor via Conjure.
---
--- Delegates to `:ConjureEvalCurrentForm` which uses tree-sitter
--- to determine the form boundaries. Notifies if Conjure is not loaded.
keys.lang_map("clojure", "n", "<leader>le", function()
	if vim.fn.exists(":ConjureEvalCurrentForm") == 2 then
		vim.cmd("ConjureEvalCurrentForm")
	else
		vim.notify("Conjure not loaded — open a REPL first", vim.log.levels.INFO, { title = "Clojure" })
	end
end, { desc = clj_icon .. " Eval form" })

--- Eval the entire buffer via Conjure.
---
--- Delegates to `:ConjureEvalBuf` which sends all forms in the buffer
--- to the connected nREPL session for evaluation.
keys.lang_map("clojure", "n", "<leader>lE", function()
	if vim.fn.exists(":ConjureEvalBuf") == 2 then
		vim.cmd("ConjureEvalBuf")
	else
		vim.notify("Conjure not loaded", vim.log.levels.INFO, { title = "Clojure" })
	end
end, { desc = clj_icon .. " Eval buffer" })

--- Eval the visual selection via Conjure.
---
--- Delegates to `:ConjureEvalVisual` which sends the selected text
--- to the connected nREPL session.
keys.lang_map("clojure", "v", "<leader>le", function()
	if vim.fn.exists(":ConjureEvalVisual") == 2 then
		vim.cmd("ConjureEvalVisual")
	else
		vim.notify("Conjure not loaded", vim.log.levels.INFO, { title = "Clojure" })
	end
end, { desc = clj_icon .. " Eval selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via the project CLI or Conjure.
-- Full-suite tests use the project's test alias/profile.
-- Namespace tests use Conjure when available, with a CLI fallback
-- that extracts the namespace from the `(ns ...)` form.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite.
---
--- Uses the project-appropriate test command:
--- - `deps`  → `clj -M:test` (requires `:test` alias in deps.edn)
--- - `lein`  → `lein test`
--- - Other   → `clj -M:test` (fallback)
keys.lang_map("clojure", "n", "<leader>lt", function()
	local ptype = detect_project()
	---@type string
	local cmd
	if ptype == "deps" then
		cmd = "clj -M:test"
	elseif ptype == "lein" then
		cmd = "lein test"
	else
		cmd = "clj -M:test"
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Test .. " Run tests" })

--- Test the current namespace.
---
--- Strategy:
--- 1. If Conjure is loaded: eval the buffer first, then run
---    `:ConjureCljRunCurrentNsTests` (via `vim.schedule` to ensure
---    eval completes before test execution)
--- 2. Fallback: parse the first 10 lines for `(ns <name>)` form,
---    extract the namespace name, and run `clj -M:test -n <ns>`
---
--- The namespace pattern `%(ns%s+([%w%.%-]+)` matches standard
--- Clojure namespace declarations including dotted and hyphenated names.
keys.lang_map("clojure", "n", "<leader>lT", function()
	-- ── Strategy 1: Conjure eval + test ───────────────────────────────
	if vim.fn.exists(":ConjureEvalBuf") == 2 then
		vim.cmd("ConjureEvalBuf")
		vim.schedule(function()
			if vim.fn.exists(":ConjureCljRunCurrentNsTests") == 2 then vim.cmd("ConjureCljRunCurrentNsTests") end
		end)
		return
	end

	-- ── Strategy 2: parse ns form + CLI ───────────────────────────────
	local lines = vim.api.nvim_buf_get_lines(0, 0, 10, false)
	---@type string|nil
	local ns_name
	for _, line in ipairs(lines) do
		ns_name = line:match("%(ns%s+([%w%.%-]+)")
		if ns_name then break end
	end

	if ns_name then
		local cmd = string.format("clj -M:test -n %s", vim.fn.shellescape(ns_name))
		vim.cmd.split()
		vim.cmd.terminal(cmd)
	else
		vim.notify("Cannot detect namespace", vim.log.levels.WARN, { title = "Clojure" })
	end
end, { desc = icons.dev.Test .. " Test namespace" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Documentation lookup via Conjure (connected REPL) or CLI fallback.
-- Conjure provides richer output via the nREPL info/doc ops.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show documentation for the symbol under cursor.
---
--- Prefers Conjure's `:ConjureDocWord` which queries the connected
--- nREPL session for `clojure.repl/doc` output. Falls back to
--- running `clj -e '(clojure.repl/doc <word>)'` in a terminal.
keys.lang_map("clojure", "n", "<leader>ld", function()
	if vim.fn.exists(":ConjureDocWord") == 2 then
		vim.cmd("ConjureDocWord")
	else
		local word = vim.fn.expand("<cword>")
		if word ~= "" then
			vim.cmd.split()
			vim.cmd.terminal("clj -e '(clojure.repl/doc " .. word .. ")'")
		end
	end
end, { desc = icons.ui.Note .. " Doc for word" })

--- Show source code for the symbol under cursor.
---
--- Prefers Conjure's `:ConjureDefWord` which queries the nREPL
--- session. Falls back to `clj -e '(clojure.repl/source <word>)'`.
keys.lang_map("clojure", "n", "<leader>ls", function()
	if vim.fn.exists(":ConjureDefWord") == 2 then
		vim.cmd("ConjureDefWord")
	else
		local word = vim.fn.expand("<cword>")
		if word ~= "" then
			vim.cmd.split()
			vim.cmd.terminal("clj -e '(clojure.repl/source " .. word .. ")'")
		end
	end
end, { desc = icons.ui.Code .. " Source for word" })

--- Open Clojure documentation in the default browser.
---
--- Presents 4 curated reference links via `vim.ui.select()`:
--- 1. ClojureDocs       — community examples and documentation
--- 2. Clojure Cheatsheet — quick reference for core functions
--- 3. ClojureScript     — ClojureScript compiler documentation
--- 4. Clojars           — Clojure/Java package registry
keys.lang_map("clojure", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Clojure Docs", url = "https://clojuredocs.org/" },
		{ name = "Clojure Cheatsheet", url = "https://clojure.org/api/cheatsheet" },
		{ name = "ClojureScript", url = "https://clojurescript.org/" },
		{ name = "Clojars (packages)", url = "https://clojars.org/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = clj_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Clojure reference" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Development utilities: dependency tree inspection, linting,
-- and project information.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show the project dependency tree.
---
--- Uses the project-appropriate command:
--- - `deps`  → `clj -Stree` (tools.deps tree resolver)
--- - `lein`  → `lein deps :tree` (Leiningen dependency report)
--- - Other   → `clj -Stree` (fallback)
keys.lang_map("clojure", "n", "<leader>lp", function()
	local ptype = detect_project()
	---@type string
	local cmd
	if ptype == "deps" then
		cmd = "clj -Stree"
	elseif ptype == "lein" then
		cmd = "lein deps :tree"
	else
		cmd = "clj -Stree"
	end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Package .. " Deps tree" })

--- Run clj-kondo linter on the current file.
---
--- Saves the buffer before execution. clj-kondo provides fast static
--- analysis for Clojure, ClojureScript, and EDN files.
keys.lang_map("clojure", "n", "<leader>ll", function()
	if vim.fn.executable("clj-kondo") ~= 1 then
		vim.notify("Install: brew install clj-kondo", vim.log.levels.WARN, { title = "Clojure" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("clj-kondo --lint " .. vim.fn.shellescape(file))
end, { desc = clj_icon .. " Lint (clj-kondo)" })

--- Show Clojure project information.
---
--- Displays:
--- - Detected project type (deps/lein/boot/bb/unknown)
--- - Current working directory
--- - Tool availability: clj, lein, bb, clj-kondo
keys.lang_map("clojure", "n", "<leader>li", function()
	local ptype = detect_project()

	---@type string[]
	local info = { clj_icon .. " Project Info:", "" }
	info[#info + 1] = "  Type: " .. (ptype or "unknown")
	info[#info + 1] = "  CWD:  " .. vim.fn.getcwd()

	---@type string[]
	local tools = { "clj", "lein", "bb", "clj-kondo" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		---@type string
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Clojure" })
end, { desc = icons.diagnostics.Info .. " Project info" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Clojure-specific alignment presets when mini.align is
-- available. Loaded once per session (guarded by is_language_loaded).
--
-- Presets:
-- ├─ clojure_map — align hash-map key-value pairs by whitespace
-- │  Example: {:name  "Alice"
-- │            :age   30
-- │            :email "alice@example.com"}
-- └─ clojure_let — align let binding pairs by whitespace
--    Example: (let [x     1
--                   total (+ x 2)])
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("clojure") then
		---@type string Alignment preset icon from icons.lang
		local align_icon = icons.lang.clojure

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			clojure_map = {
				description = "Align Clojure map pairs",
				icon = align_icon,
				split_pattern = "%s+",
				category = "jvm",
				lang = "clojure",
				filetypes = { "clojure" },
			},
			clojure_let = {
				description = "Align Clojure let bindings",
				icon = align_icon,
				split_pattern = "%s+",
				category = "functional",
				lang = "clojure",
				filetypes = { "clojure" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("clojure", "clojure_map")
		align_registry.mark_language_loaded("clojure")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("clojure", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("clojure_map"), {
			desc = align_icon .. "  Align Clojure map",
		})
		keys.lang_map("clojure", { "n", "x" }, "<leader>aT", align_registry.make_align_fn("clojure_let"), {
			desc = align_icon .. "  Align Clojure let",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Clojure-specific
-- parts (servers, linters, parsers, REPL tools).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Clojure                │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (clojure_lsp added to servers)    │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ nvim-lint          │ opts merge (linters_by_ft.clojure)           │
-- │ nvim-treesitter    │ opts merge (clojure parser to ensure_install)│
-- │ conjure            │ ft = "clojure" (true lazy load)              │
-- │ nvim-paredit       │ ft = "clojure" (true lazy load)              │
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: No formatter spec is included because clojure-lsp embeds
-- cljfmt and provides formatting via the standard LSP textDocument/
-- formatting interface.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Clojure
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────
	-- clojure-lsp: comprehensive Clojure language server providing
	-- completions, refactoring, diagnostics, code actions, and embedded
	-- cljfmt formatting. Works with Clojure, ClojureScript, and EDN.
	--
	-- NOTE: clojure-lsp provides formatting via LSP, so no separate
	-- conform.nvim configuration is needed for Clojure.
	-- ────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				clojure_lsp = {
					settings = {},
				},
			},
		},
		init = function()
			-- ── Filetype detection ──────────────────────────────────
			-- Map all Clojure-family extensions to the "clojure" filetype.
			-- Includes:
			-- • .clj   — Clojure source
			-- • .cljs  — ClojureScript source
			-- • .cljc  — Clojure reader conditionals (cross-platform)
			-- • .cljd  — ClojureDart source
			-- • .edn   — Extensible Data Notation (config/data files)
			-- • .bb    — Babashka scripts
			vim.filetype.add({
				extension = {
					clj = "clojure",
					cljs = "clojure",
					cljc = "clojure",
					cljd = "clojure",
					edn = "clojure",
					bb = "clojure",
				},
			})

			-- ── Buffer-local options for Clojure files ────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "clojure" },
				callback = function()
					local opt = vim.opt_local

					-- ── Layout ────────────────────────────────────────
					opt.wrap = false
					opt.colorcolumn = "100"
					opt.textwidth = 100

					-- ── Indentation (Lisp convention: 2 spaces) ──────
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true

					-- ── Lisp-aware indentation ────────────────────────
					-- Vim's built-in lisp indent mode recognizes special
					-- forms listed in lispwords and applies Lisp-style
					-- indentation (body forms align under the first arg).
					opt.lisp = true
					opt.lispwords:append({
						-- Core special forms
						"defn",
						"defmacro",
						"defmethod",
						"defmulti",
						"defonce",
						"defprotocol",
						"defrecord",
						"deftype",
						-- Binding forms
						"let",
						"when",
						"when-let",
						"when-not",
						"if-let",
						"if-not",
						"cond",
						"condp",
						"case",
						-- Function/loop forms
						"fn",
						"loop",
						"for",
						"doseq",
						"dotimes",
						-- Testing forms
						"testing",
						"deftest",
						"are",
						-- Error handling
						"try",
						"catch",
						-- core.async
						"go",
						"go-loop",
						"thread",
					})

					-- ── Line numbers ──────────────────────────────────
					opt.number = true
					opt.relativenumber = true

					-- ── Folding (treesitter-based) ────────────────────
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99

					-- ── Comments ──────────────────────────────────────
					opt.commentstring = ";; %s"
				end,
				desc = "NvimEnterprise: Clojure buffer options",
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────
	-- Ensures clojure-lsp and clj-kondo are installed and managed
	-- by Mason.
	--
	-- NOTE: clj-kondo is also used internally by clojure-lsp for
	-- analysis, but having it separately allows standalone linting
	-- via nvim-lint and the <leader>ll keymap.
	-- ────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"clojure-lsp",
				"clj-kondo",
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────
	-- clj-kondo: fast static analysis for Clojure/ClojureScript/EDN.
	-- Provides inline diagnostics via nvim-lint that complement the
	-- LSP diagnostics from clojure-lsp.
	-- ────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				clojure = { "clj-kondo" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────
	-- clojure: syntax highlighting, folding, form extraction,
	-- text objects, and indentation for .clj/.cljs/.cljc/.edn files.
	-- Also powers Conjure's tree-sitter form detection.
	-- ────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"clojure",
			},
		},
	},

	-- ── CONJURE (Interactive REPL client) ──────────────────────────────
	-- Conjure provides interactive REPL-driven development for Clojure.
	-- Lazy-loaded on ft = "clojure".
	--
	-- Configuration (via vim.g global variables):
	-- • Mapping prefix: <localleader> (for Conjure-native keymaps)
	-- • HUD log: enabled, SE-anchored, 42% width
	-- • Tree-sitter: form extraction enabled
	-- • nREPL: auto-connect + auto-require enabled
	-- • Highlight: eval result flash (150ms timeout)
	-- ────────────────────────────────────────────────────────────────────
	{
		"Olical/conjure",
		ft = { "clojure" },
		init = function()
			-- ── Conjure global configuration ──────────────────────────
			-- These must be set before Conjure loads (hence init, not config)
			vim.g["conjure#mapping#prefix"] = "<localleader>"
			vim.g["conjure#log#wrap"] = true
			vim.g["conjure#log#hud#enabled"] = true
			vim.g["conjure#log#hud#width"] = 0.42
			vim.g["conjure#log#hud#anchor"] = "SE"
			vim.g["conjure#extract#tree_sitter#enabled"] = true
			vim.g["conjure#client#clojure#nrepl#connection#auto_repl#enabled"] = true
			vim.g["conjure#client#clojure#nrepl#eval#auto_require"] = true
			vim.g["conjure#highlight#enabled"] = true
			vim.g["conjure#highlight#timeout"] = 150
		end,
	},

	-- ── PAREDIT (Structural editing) ───────────────────────────────────
	-- nvim-paredit provides structural editing for s-expressions:
	-- slurp, barf, raise, splice, wrap, and more. Essential for
	-- efficient Lisp/Clojure editing without manually tracking parens.
	--
	-- Lazy-loaded on ft = "clojure". Uses default keymaps which
	-- follow the Emacs paredit conventions.
	-- ────────────────────────────────────────────────────────────────────
	{
		"julienvincent/nvim-paredit",
		ft = { "clojure" },
		opts = {
			use_default_keys = true,
			indent = {
				enabled = true,
			},
		},
	},
}
