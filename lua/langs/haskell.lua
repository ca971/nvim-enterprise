---@file lua/langs/haskell.lua
---@description Haskell — LSP (haskell-tools.nvim), formatter, linter, treesitter & buffer-local keymaps
---@module "langs.haskell"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.utils               Shared utility functions (`has_executable`)
---@see core.mini-align-registry Alignment preset registration system
---@see langs.python             Python language support (same architecture)
---@see langs.rust               Rust language support (similar plugin-managed LSP)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/haskell.lua — Haskell language support                            ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("haskell") → {} if off      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "haskell" / "lhaskell" /     │    ║
--- ║  │             "cabal"):                                            │    ║
--- ║  │  ├─ LSP          HLS (via haskell-tools.nvim, NOT lspconfig)     │    ║
--- ║  │  ├─ Formatter    fourmolu (preferred) / ormolu (fallback)        │    ║
--- ║  │  ├─ Linter       hlint (if available, via nvim-lint + keymap)    │    ║
--- ║  │  ├─ Treesitter   haskell parser                                  │    ║
--- ║  │  ├─ DAP          — (not configured)                              │    ║
--- ║  │  └─ Extras       haskell-tools.nvim (REPL, eval, hover)          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run (stack/cabal)     R  Run with arguments     │    ║
--- ║  │  ├─ BUILD     b  Build (stack/cabal)                             │    ║
--- ║  │  ├─ TEST      t  Test (stack/cabal)                              │    ║
--- ║  │  ├─ REPL      c  GHCi REPL            s  Load file in GHCi       │    ║
--- ║  │  ├─ LINT      l  hlint (current file)  x  Apply hlint suggestions│    ║
--- ║  │  ├─ EVAL      e  Eval expression (ghc -e)                        │    ║
--- ║  │  ├─ SEARCH    d  Hoogle search (local or browser)                │    ║
--- ║  │  ├─ PACKAGES  p  Package management (stack/cabal picker)         │    ║
--- ║  │  └─ DOCS      i  Project info (GHC, tools)                       │    ║
--- ║  │               h  Documentation (browser)                         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Build tool detection:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. stack.yaml in CWD + stack available → "stack"        │    │    ║
--- ║  │  │  2. *.cabal / cabal.project in CWD + cabal → "cabal"     │    │    ║
--- ║  │  │  3. stack available (no project file) → "stack"          │    │    ║
--- ║  │  │  4. cabal available (no project file) → "cabal"          │    │    ║
--- ║  │  │  5. nil — neither found                                  │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  haskell-tools.nvim integration:                                 │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  • Manages HLS lifecycle (replaces nvim-lspconfig)       │    │    ║
--- ║  │  │  • Provides ht.lsp.buf_eval_all (code lens evaluation)   │    │    ║
--- ║  │  │  • Provides ht.repl.toggle (GHCi REPL integration)       │    │    ║
--- ║  │  │  • HLS plugins: hlint, class, importLens, refineImports, │    │    ║
--- ║  │  │    tactics, moduleName, eval                             │    │    ║
--- ║  │  │  • formattingProvider = "fourmolu"                       │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType haskell/lhaskell):                  ║
--- ║  • colorcolumn=80, textwidth=80   (Haskell community convention)         ║
--- ║  • tabstop=2, shiftwidth=2        (Haskell standard: 2-space indent)     ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • commentstring="-- %s"          (Haskell line comments)                ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .hs → haskell                                                         ║
--- ║  • .lhs → lhaskell (literate Haskell)                                    ║
--- ║  • .cabal → cabal                                                        ║
--- ║                                                                          ║
--- ║  NOTE: haskell-tools.nvim manages its own HLS instance, similar to       ║
--- ║  how rustaceanvim handles rust-analyzer. Do not add HLS to any           ║
--- ║  lspconfig server configuration.                                         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Haskell support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("haskell") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")
local has_executable = require("core.utils").has_executable

---@type string Haskell Nerd Font icon (trailing whitespace stripped)
local hs_icon = icons.lang.haskell:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Haskell buffers.
-- The group is buffer-local and only visible when filetype == "haskell".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("haskell", "Haskell", hs_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the Haskell build tool for the current project.
---
--- Resolution order:
--- 1. `stack.yaml` in CWD + `stack` available → `"stack"`
--- 2. `*.cabal` or `cabal.project` in CWD + `cabal` available → `"cabal"`
--- 3. `stack` available (no project file) → `"stack"` (default)
--- 4. `cabal` available (no project file) → `"cabal"` (fallback)
--- 5. Neither found → `nil`
---
--- ```lua
--- local tool = detect_build_tool()
--- if tool == "stack" then
---   vim.cmd.terminal("stack build")
--- end
--- ```
---
---@return "stack"|"cabal"|nil tool The detected build tool, or `nil`
---@private
local function detect_build_tool()
	local cwd = vim.fn.getcwd()

	-- ── Strategy 1: stack project file ───────────────────────────────
	if vim.fn.filereadable(cwd .. "/stack.yaml") == 1 and has_executable("stack") then
		return "stack"
	end

	-- ── Strategy 2: cabal project file ───────────────────────────────
	if
		(vim.fn.glob(cwd .. "/*.cabal") ~= "" or vim.fn.filereadable(cwd .. "/cabal.project") == 1)
		and has_executable("cabal")
	then
		return "cabal"
	end

	-- ── Strategy 3/4: available tool without project file ────────────
	if has_executable("stack") then return "stack" end
	if has_executable("cabal") then return "cabal" end

	return nil
end

--- Build a command string from the detected build tool and a subcommand.
---
--- Combines `detect_build_tool()` with the given subcommand (e.g. "run",
--- "build", "test"). Notifies the user if no build tool is found and
--- returns an empty string.
---
--- ```lua
--- local cmd = build_cmd("run")
--- if cmd ~= "" then
---   vim.cmd.terminal(cmd)  -- → "stack run" or "cabal run"
--- end
--- ```
---
---@param subcmd string The build tool subcommand (e.g. "run", "build", "test")
---@return string cmd The full command string, or `""` if no tool found
---@private
local function build_cmd(subcmd)
	local tool = detect_build_tool()
	if not tool then
		vim.notify("No build tool found (stack, cabal)", vim.log.levels.ERROR, { title = "Haskell" })
		return ""
	end
	return tool .. " " .. subcmd
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — BUILD / RUN
--
-- Haskell project execution and compilation via stack or cabal.
-- The build tool is auto-detected for each command.
-- All keymaps save the buffer before execution.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the project with the detected build tool.
---
--- Executes `stack run` or `cabal run` depending on the detected
--- build tool. Saves the buffer before execution.
keys.lang_map("haskell", "n", "<leader>lr", function()
	local cmd = build_cmd("run")
	if cmd == "" then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Play .. " Run" })

--- Run the project with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then executes
--- `stack run -- <args>` or `cabal run -- <args>` in a terminal split.
keys.lang_map("haskell", "n", "<leader>lR", function()
	local cmd = build_cmd("run")
	if cmd == "" then return end
	vim.cmd("silent! write")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal(cmd .. " -- " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Build the project with `stack build` or `cabal build`.
---
--- Saves the buffer before building.
keys.lang_map("haskell", "n", "<leader>lb", function()
	local cmd = build_cmd("build")
	if cmd == "" then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Build .. " Build" })

--- Run the test suite with `stack test` or `cabal test`.
---
--- Saves the buffer before testing.
keys.lang_map("haskell", "n", "<leader>lt", function()
	local cmd = build_cmd("test")
	if cmd == "" then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Test .. " Test" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
--
-- Interactive GHCi sessions with build-tool awareness.
-- Supports both project-level REPL and file-specific loading.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a GHCi REPL with project context.
---
--- Resolution:
--- • stack → `stack ghci` (loads project modules)
--- • cabal → `cabal repl` (loads project modules)
--- • bare  → `ghci` (standalone)
keys.lang_map("haskell", "n", "<leader>lc", function()
	local tool = detect_build_tool()

	---@type string
	local cmd
	if tool == "stack" then
		cmd = "stack ghci"
	elseif tool == "cabal" then
		cmd = "cabal repl"
	elseif has_executable("ghci") then
		cmd = "ghci"
	else
		vim.notify("No GHCi found", vim.log.levels.ERROR, { title = "Haskell" })
		return
	end

	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Terminal .. " GHCi REPL" })

--- Load the current file in GHCi.
---
--- Resolution:
--- • stack → `stack ghci <file>`
--- • cabal → `cabal repl <file>`
--- • bare  → `ghci <file>`
---
--- Saves the buffer before loading.
keys.lang_map("haskell", "n", "<leader>ls", function()
	local file = vim.fn.expand("%:p")
	local tool = detect_build_tool()

	---@type string
	local cmd
	if tool == "stack" then
		cmd = "stack ghci " .. vim.fn.shellescape(file)
	elseif tool == "cabal" then
		cmd = "cabal repl " .. vim.fn.shellescape(file)
	elseif has_executable("ghci") then
		cmd = "ghci " .. vim.fn.shellescape(file)
	else
		vim.notify("No GHCi found", vim.log.levels.ERROR, { title = "Haskell" })
		return
	end

	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = hs_icon .. " Load file in GHCi" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — LINT
--
-- Static analysis via hlint. Supports both inspection and automatic
-- refactoring (applying suggestions in-place).
-- ═══════════════════════════════════════════════════════════════════════════

--- Run hlint on the current file.
---
--- Saves the buffer, then runs `hlint <file>` in a terminal split
--- to display all suggestions, warnings, and errors.
--- Notifies with installation instructions if hlint is not available.
keys.lang_map("haskell", "n", "<leader>ll", function()
	if not has_executable("hlint") then
		vim.notify("Install hlint: stack install hlint", vim.log.levels.WARN, { title = "Haskell" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("hlint " .. vim.fn.shellescape(file))
end, { desc = hs_icon .. " Lint (hlint)" })

--- Apply hlint suggestions automatically via `--refactor`.
---
--- Saves the buffer, then runs `hlint --refactor <file>` which
--- applies safe refactoring suggestions in-place. Requires the
--- `apply-refact` tool to be installed alongside hlint.
keys.lang_map("haskell", "n", "<leader>lx", function()
	if not has_executable("hlint") then
		vim.notify("Install hlint: stack install hlint", vim.log.levels.WARN, { title = "Haskell" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("hlint --refactor " .. vim.fn.shellescape(file))
end, { desc = hs_icon .. " Apply hlint suggestions" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EVAL / HOOGLE
--
-- Interactive expression evaluation and type/function search.
-- ═══════════════════════════════════════════════════════════════════════════

--- Evaluate a Haskell expression via `ghc -e`.
---
--- Prompts for an expression, then evaluates it using either
--- `stack exec -- ghc -e` or bare `ghc -e`. Displays the result
--- in a notification.
keys.lang_map("haskell", "n", "<leader>le", function()
	vim.ui.input({ prompt = "Haskell expression: " }, function(expr)
		if not expr or expr == "" then return end

		---@type string
		local cmd
		if has_executable("stack") then
			cmd = "stack exec -- ghc -e " .. vim.fn.shellescape(expr)
		elseif has_executable("ghc") then
			cmd = "ghc -e " .. vim.fn.shellescape(expr)
		else
			vim.notify("No GHC found", vim.log.levels.ERROR, { title = "Haskell" })
			return
		end

		local result = vim.fn.system(cmd)
		vim.notify(result, vim.log.levels.INFO, { title = "ghc -e" })
	end)
end, { desc = hs_icon .. " Eval expression" })

--- Search Hoogle for the word under cursor or a custom query.
---
--- Resolution:
--- 1. Uses the word under cursor (if non-empty)
--- 2. Otherwise prompts for a search query
---
--- If `hoogle` is installed locally, runs `hoogle search` in a
--- terminal split. Otherwise opens Hoogle in the system browser.
keys.lang_map("haskell", "n", "<leader>ld", function()
	local word = vim.fn.expand("<cword>")

	if word == "" then
		vim.ui.input({ prompt = "Hoogle search: " }, function(query)
			if not query or query == "" then return end
			word = query
		end)
		if word == "" then return end
	end

	if has_executable("hoogle") then
		vim.cmd.split()
		vim.cmd.terminal("hoogle search " .. vim.fn.shellescape(word))
	else
		vim.ui.open("https://hoogle.haskell.org/?hoogle=" .. vim.fn.escape(word, " "))
	end
end, { desc = hs_icon .. " Hoogle search" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PACKAGE MANAGEMENT
--
-- Build-tool-aware command picker for stack or cabal.
-- The available actions adapt based on the detected build tool.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a build-tool-specific command picker.
---
--- Adapts the available actions based on the detected build tool:
---
--- Stack commands:
--- • build, test, clean, install…, update
--- • list-dependencies, ghci, haddock, new project…
---
--- Cabal commands:
--- • build, test, clean, install…, update
--- • repl, haddock, init
keys.lang_map("haskell", "n", "<leader>lp", function()
	local tool = detect_build_tool()
	if not tool then
		vim.notify("No build tool found", vim.log.levels.WARN, { title = "Haskell" })
		return
	end

	---@type { name: string, cmd: string, prompt?: boolean }[]
	local actions
	if tool == "stack" then
		actions = {
			{ name = "build", cmd = "stack build" },
			{ name = "test", cmd = "stack test" },
			{ name = "clean", cmd = "stack clean" },
			{ name = "install…", cmd = "stack install", prompt = true },
			{ name = "update", cmd = "stack update" },
			{ name = "list-dependencies", cmd = "stack ls dependencies" },
			{ name = "ghci", cmd = "stack ghci" },
			{ name = "haddock", cmd = "stack haddock" },
			{ name = "new project…", cmd = "stack new", prompt = true },
		}
	else
		actions = {
			{ name = "build", cmd = "cabal build" },
			{ name = "test", cmd = "cabal test" },
			{ name = "clean", cmd = "cabal clean" },
			{ name = "install…", cmd = "cabal install", prompt = true },
			{ name = "update", cmd = "cabal update" },
			{ name = "repl", cmd = "cabal repl" },
			{ name = "haddock", cmd = "cabal haddock" },
			{ name = "init", cmd = "cabal init" },
		}
	end

	vim.ui.select(
		vim.tbl_map(function(a) return a.name end, actions),
		{ prompt = hs_icon .. " " .. tool .. ":" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]
			if action.prompt then
				vim.ui.input({ prompt = "Name: " }, function(name)
					if not name or name == "" then return end
					vim.cmd.split()
					vim.cmd.terminal(action.cmd .. " " .. vim.fn.shellescape(name))
				end)
			else
				vim.cmd.split()
				vim.cmd.terminal(action.cmd)
			end
		end
	)
end, { desc = icons.ui.Package .. " Package management" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Haskell project information and quick access to documentation
-- via the system browser.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show Haskell project and tool information in a notification.
---
--- Displays:
--- • Detected build tool (stack / cabal / none)
--- • GHC version (if available)
--- • Tool availability matrix (ghc, ghci, cabal, stack, hls,
---   hlint, hoogle, fourmolu, ormolu)
--- • Current working directory
keys.lang_map("haskell", "n", "<leader>li", function()
	---@type string[]
	local info = { hs_icon .. " Haskell Info:", "" }
	local tool = detect_build_tool()
	info[#info + 1] = "  Build tool: " .. (tool or "none")

	if has_executable("ghc") then
		local version = vim.fn.system("ghc --version 2>/dev/null"):gsub("%s+$", "")
		info[#info + 1] = "  GHC:        " .. version
	end

	---@type string[]
	local tools = { "ghc", "ghci", "cabal", "stack", "hls", "hlint", "hoogle", "fourmolu", "ormolu" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, t in ipairs(tools) do
		local status = has_executable(t) and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. t
	end
	info[#info + 1] = "  CWD:        " .. vim.fn.getcwd()

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Haskell" })
end, { desc = icons.diagnostics.Info .. " Project info" })

--- Open Haskell documentation in the system browser.
---
--- Presents a picker with key reference pages:
--- • Haskell Docs          — official documentation hub
--- • Hoogle                — type-signature-based search engine
--- • Hackage               — central package archive
--- • Stackage              — curated package snapshots
--- • Learn You a Haskell   — beginner-friendly tutorial
--- • Real World Haskell    — practical programming guide
--- • Haskell Wiki          — community wiki
--- • HLS Docs              — language server documentation
keys.lang_map("haskell", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Haskell Docs", url = "https://www.haskell.org/documentation/" },
		{ name = "Hoogle (search)", url = "https://hoogle.haskell.org/" },
		{ name = "Hackage (packages)", url = "https://hackage.haskell.org/" },
		{ name = "Stackage", url = "https://www.stackage.org/" },
		{ name = "Learn You a Haskell", url = "https://learnyouahaskell.com/" },
		{ name = "Real World Haskell", url = "https://book.realworldhaskell.org/" },
		{ name = "Haskell Wiki", url = "https://wiki.haskell.org/" },
		{ name = "HLS Docs", url = "https://haskell-language-server.readthedocs.io/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r) return r.name end, refs),
		{ prompt = hs_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Haskell-specific alignment presets for mini.align:
-- • haskell_types  — align type signatures on "::"
-- • haskell_record — align record field definitions on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("haskell") then
		---@type string Alignment preset icon from icons.app
		local align_icon = icons.app.Haskell

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			haskell_types = {
				description = "Align Haskell type signatures on '::'",
				icon = align_icon,
				split_pattern = "::",
				category = "functional",
				lang = "haskell",
				filetypes = { "haskell" },
			},
			haskell_record = {
				description = "Align Haskell record fields on '='",
				icon = align_icon,
				split_pattern = "=",
				category = "functional",
				lang = "haskell",
				filetypes = { "haskell" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("haskell", "haskell_types")
		align_registry.mark_language_loaded("haskell")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("haskell", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("haskell_types"), {
			desc = align_icon .. "  Align Haskell types",
		})
		keys.lang_map("haskell", { "n", "x" }, "<leader>aT", align_registry.make_align_fn("haskell_record"), {
			desc = align_icon .. "  Align Haskell record",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Haskell-specific
-- parts (haskell-tools.nvim, formatters, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Haskell                │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ haskell-tools.nvim                      │ ft = haskell/lhaskell/cabal (manages HLS)   │
-- │ mason.nvim                             │ opts fn merge (HLS + fourmolu if ghc avail)  │
-- │ conform.nvim                           │ opts fn merge (fourmolu or ormolu if avail)  │
-- │ nvim-lint                              │ opts fn merge (hlint if available)            │
-- │ nvim-treesitter                        │ opts merge (haskell parser added)            │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Haskell does NOT use nvim-lspconfig directly. haskell-tools.nvim
-- manages its own HLS instance, providing tighter integration with GHCi
-- REPL, code lens evaluation, and Haskell-specific features. Do not add
-- HLS to any lspconfig server configuration.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Haskell
return {
	-- ── HASKELL-TOOLS.NVIM (LSP + REPL + Tools) ───────────────────────────
	-- Replaces nvim-lspconfig for Haskell. Manages its own HLS lifecycle
	-- and provides:
	-- • HLS with full plugin support (hlint, tactics, eval, etc.)
	-- • GHCi REPL integration (toggle via ht.repl.toggle)
	-- • Code lens evaluation (ht.lsp.buf_eval_all)
	-- • Hover with rounded borders
	--
	-- Configuration:
	-- • formattingProvider = "fourmolu"  — preferred formatter
	-- • checkProject = true             — check entire project
	-- • repl.handler = "toggleterm"     — REPL via toggleterm
	-- • All HLS plugins enabled (hlint, class, importLens, etc.)
	--
	-- Conditionally loaded: only if `ghc` is available in PATH.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mrcjkb/haskell-tools.nvim",
		version = "^4",
		lazy = false,
		ft = { "haskell", "lhaskell", "cabal", "cabalproject" },
		cond = function()
			return has_executable("ghc")
		end,
		dependencies = {
			"neovim/nvim-lspconfig",
			"nvim-lua/plenary.nvim",
		},
		opts = {
			hls = {
				on_attach = function(_, bufnr)
					local ht = require("haskell-tools")
					vim.keymap.set("n", "<leader>le", ht.lsp.buf_eval_all, {
						buffer = bufnr,
						desc = hs_icon .. " Eval all code lenses",
					})
					vim.keymap.set("n", "<leader>lg", ht.repl.toggle, {
						buffer = bufnr,
						desc = hs_icon .. " Toggle GHCi REPL",
					})
				end,
				settings = {
					haskell = {
						formattingProvider = "fourmolu",
						checkProject = true,
						plugin = {
							hlint = { globalOn = true },
							class = { codeLensOn = true },
							importLens = { codeLensOn = true },
							refineImports = { codeLensOn = true },
							tactics = { codeLensOn = true },
							moduleName = { globalOn = true },
							eval = { globalOn = true },
						},
					},
				},
			},
			tools = {
				repl = {
					handler = "toggleterm",
					auto_focus = true,
				},
				hover = {
					border = "rounded",
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					hs = "haskell",
					lhs = "lhaskell",
					cabal = "cabal",
				},
			})

			-- ── Buffer-local options for Haskell files ───────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "haskell", "lhaskell" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "80"
					opt.textwidth = 80
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true
					opt.number = true
					opt.relativenumber = true
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
					opt.commentstring = "-- %s"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures HLS and fourmolu are installed via Mason.
	-- Only extends ensure_installed if GHC is available.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}
			if has_executable("ghc") then
				vim.list_extend(opts.ensure_installed, {
					"haskell-language-server",
					"fourmolu",
				})
			end
		end,
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- fourmolu: configurable Haskell formatter (preferred).
	-- ormolu:   opinionated formatter (fallback if fourmolu unavailable).
	-- Only one is configured based on runtime availability.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = function(_, opts)
			if has_executable("fourmolu") then
				opts.formatters_by_ft = opts.formatters_by_ft or {}
				opts.formatters_by_ft.haskell = { "fourmolu" }
			elseif has_executable("ormolu") then
				opts.formatters_by_ft = opts.formatters_by_ft or {}
				opts.formatters_by_ft.haskell = { "ormolu" }
			end
		end,
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- hlint: Haskell linter providing style suggestions, refactoring hints,
	-- and anti-pattern detection. Only configured if hlint is available.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = function(_, opts)
			if has_executable("hlint") then
				opts.linters_by_ft = opts.linters_by_ft or {}
				opts.linters_by_ft.haskell = { "hlint" }
			end
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- haskell: syntax highlighting, folding, text objects and indentation
	--          for Haskell source files (.hs, .lhs).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"haskell",
			},
		},
	},
}
