---@file lua/langs/lean.lua
---@description Lean 4 — LSP (lean.nvim), treesitter & buffer-local keymaps
---@module "langs.lean"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.haskell            Haskell language support (functional programming peer)
---@see langs.python             Python language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/lean.lua — Lean 4 language support                                ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("lean") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "lean"):                     │    ║
--- ║  │  ├─ LSP          lean4 (managed by lean.nvim, NOT lspconfig)     │    ║
--- ║  │  │               Type checking, tactic hints, goal view          │    ║
--- ║  │  ├─ Treesitter   lean parser                                     │    ║
--- ║  │  ├─ Infoview     lean.nvim built-in (goal state, type info)      │    ║
--- ║  │  └─ Build tool   lake (Lean's build system / package manager)    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ BUILD     b  Lake build            r  Lake run (exe)         │    ║
--- ║  │  │            t  Lake test              c  Lake clean            │    ║
--- ║  │  │            p  Lake update deps                                │    ║
--- ║  │  ├─ LEAN      s  Insert sorry           g  Toggle infoview       │    ║
--- ║  │  └─ DOCS      i  Lean info              h  Documentation picker  │    ║
--- ║  │                                                                  │    ║
--- ║  │  lean.nvim integration:                                          │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. lean.nvim loads on ft = "lean"                       │    │    ║
--- ║  │  │  2. Manages lean4 LSP lifecycle internally               │    │    ║
--- ║  │  │     (NOT via lspconfig — lean.nvim handles setup)        │    │    ║
--- ║  │  │  3. Opens infoview panel automatically                   │    │    ║
--- ║  │  │     • Goal state display                                 │    │    ║
--- ║  │  │     • Type information                                   │    │    ║
--- ║  │  │     • Tactic suggestions                                 │    │    ║
--- ║  │  │  4. Provides lean-specific mappings:                     │    │    ║
--- ║  │  │     • Unicode abbreviation expansion                     │    │    ║
--- ║  │  │     • Tactic completion                                  │    │    ║
--- ║  │  │     • Proof term navigation                              │    │    ║
--- ║  │  │  5. cond = lean executable check (zero cost if absent)   │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType lean):                              ║
--- ║  • colorcolumn=100, textwidth=100  (Lean community standard)             ║
--- ║  • tabstop=2, shiftwidth=2         (Lean standard indentation)           ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="-- %s"           (Lean single-line comment)            ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║ 
--- ║                                                                          ║
--- ║  Lake (build system) commands:                                           ║
--- ║  • lake build   — compile the project                                    ║
--- ║  • lake exe     — run the project executable                             ║
--- ║  • lake test    — run the test suite                                     ║
--- ║  • lake clean   — remove build artifacts                                 ║
--- ║  • lake update  — update dependencies                                    ║
--- ║                                                                          ║
--- ║  Required external tools:                                                ║
--- ║  • lean  — the Lean 4 theorem prover / language                          ║
--- ║  • lake  — Lean's build system (bundled with lean)                       ║
--- ║  • elan  — Lean version manager (recommended, not required)              ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .lean  → lean                                                         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Lean support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("lean") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Lean Nerd Font icon (trailing whitespace stripped)
local lean_icon = icons.lang.lean:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Lean buffers.
-- The group is buffer-local and only visible when filetype == "lean".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("lean", "Lean", lean_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Lake availability check and command execution.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the `lake` build tool is available in `$PATH`.
---
--- Lake is Lean 4's official build system and package manager,
--- typically bundled with the Lean installation via `elan`.
---
--- ```lua
--- if not has_lake() then return end
--- ```
---
---@return boolean available `true` if `lake` is executable, `false` otherwise
---@private
local function has_lake()
	return vim.fn.executable("lake") == 1
end

--- Notify the user that `lake` is not available.
---
--- Centralizes the warning notification to avoid repetition across
--- all keymaps that require the `lake` build tool.
---
---@return nil
---@private
local function notify_no_lake()
	vim.notify("lake not found (install via elan)", vim.log.levels.WARN, { title = "Lean" })
end

--- Run a lake command in a terminal split.
---
--- Checks that `lake` is available, then opens a horizontal split
--- with a terminal running the given lake subcommand. Optionally
--- saves the current buffer before execution.
---
--- ```lua
--- run_lake("build", true)    --> save, then "lake build"
--- run_lake("clean")          --> "lake clean" (no save)
--- ```
---
---@param subcommand string Lake subcommand (e.g. `"build"`, `"test"`, `"clean"`)
---@param save? boolean If `true`, save the current buffer before running (default: `false`)
---@return nil
---@private
local function run_lake(subcommand, save)
	if not has_lake() then
		notify_no_lake()
		return
	end
	if save then
		vim.cmd("silent! write")
	end
	vim.cmd.split()
	vim.cmd.terminal("lake " .. subcommand)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — BUILD / RUN
--
-- Lake (Lean's build system) commands for compilation, execution,
-- testing, cleaning, and dependency management.
-- ═══════════════════════════════════════════════════════════════════════════

--- Build the Lean project via `lake build`.
---
--- Compiles all targets defined in `lakefile.lean`. Saves the
--- current buffer before building.
keys.lang_map("lean", "n", "<leader>lb", function()
	run_lake("build", true)
end, { desc = icons.dev.Build .. " Lake build" })

--- Run the project executable via `lake exe`.
---
--- Executes the default executable target defined in `lakefile.lean`.
--- Saves the current buffer before running.
keys.lang_map("lean", "n", "<leader>lr", function()
	run_lake("exe", true)
end, { desc = icons.ui.Play .. " Lake run" })

--- Run the test suite via `lake test`.
---
--- Executes all test targets defined in `lakefile.lean`. Saves
--- the current buffer before testing.
keys.lang_map("lean", "n", "<leader>lt", function()
	run_lake("test", true)
end, { desc = icons.dev.Test .. " Lake test" })

--- Clean build artifacts via `lake clean`.
---
--- Removes all compiled files and build caches. Does not save
--- the buffer (no need — cleaning doesn't depend on source).
keys.lang_map("lean", "n", "<leader>lc", function()
	run_lake("clean")
end, { desc = lean_icon .. " Lake clean" })

--- Update project dependencies via `lake update`.
---
--- Fetches and updates all dependencies defined in `lakefile.lean`
--- and `lean-toolchain`. Does not save the buffer.
keys.lang_map("lean", "n", "<leader>lp", function()
	run_lake("update")
end, { desc = icons.ui.Package .. " Lake update deps" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — LEAN-SPECIFIC
--
-- Lean theorem prover utilities: sorry insertion for admitting
-- goals during proof development, and infoview panel toggle.
-- ═══════════════════════════════════════════════════════════════════════════

--- Insert `sorry` at the cursor position.
---
--- `sorry` is Lean's built-in tactic for admitting (skipping) proof
--- obligations. Useful during interactive proof development to
--- temporarily satisfy the type checker while working on other goals.
---
--- In production code, `sorry` causes a warning — all `sorry` uses
--- should be replaced with actual proofs before finalizing.
keys.lang_map("lean", "n", "<leader>ls", function()
	vim.api.nvim_put({ "sorry" }, "c", true, true)
end, { desc = lean_icon .. " Insert sorry" })

--- Toggle the Lean infoview panel.
---
--- The infoview is lean.nvim's most powerful feature — it displays:
--- - **Goal state**: current proof obligations and hypotheses
--- - **Type info**: type of the expression under cursor
--- - **Tactic suggestions**: applicable tactics for the current goal
--- - **Error details**: expanded diagnostic information
---
--- Delegates to `lean.infoview.toggle()`. Falls back to a notification
--- if lean.nvim is not loaded.
keys.lang_map("lean", "n", "<leader>lg", function()
	local ok, infoview = pcall(require, "lean.infoview")
	if ok then
		infoview.toggle()
	else
		vim.notify("lean.nvim infoview not available", vim.log.levels.WARN, { title = "Lean" })
	end
end, { desc = lean_icon .. " Toggle infoview" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Lean toolchain info display and curated documentation links
-- for the Lean ecosystem and Mathlib.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show Lean toolchain and project information.
---
--- Displays a summary notification containing:
--- - Lean version (from `lean --version`)
--- - Tool availability checklist (lean, lake, elan)
--- - Current working directory
--- - Project status (lakefile.lean presence)
keys.lang_map("lean", "n", "<leader>li", function()
	---@type string[]
	local info = { lean_icon .. " Lean Info:", "" }

	-- ── Version ──────────────────────────────────────────────────
	if vim.fn.executable("lean") == 1 then
		local version = vim.fn.system("lean --version 2>/dev/null"):gsub("\n.*", "")
		info[#info + 1] = "  Version: " .. version
	end

	-- ── Tool availability ────────────────────────────────────────
	---@type string[]
	local tools = { "lean", "lake", "elan" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	-- ── Project status ───────────────────────────────────────────
	info[#info + 1] = "  CWD:     " .. vim.fn.getcwd()
	local has_lakefile = vim.fn.filereadable("lakefile.lean") == 1
	info[#info + 1] = "  Project: " .. (has_lakefile and "✓ lakefile.lean" or "✗ no lakefile.lean")

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Lean" })
end, { desc = icons.diagnostics.Info .. " Lean info" })

--- Open Lean documentation in the browser.
---
--- Presents a list of curated Lean ecosystem resources via
--- `vim.ui.select()`:
--- 1. Lean 4 Manual — official language reference
--- 2. Theorem Proving in Lean 4 — tutorial for proof assistants
--- 3. Mathematics in Lean — mathematical formalization guide
--- 4. Mathlib4 Docs — community math library documentation
--- 5. Lean Zulip — community discussion forum
---
--- Opens the selected URL in the system browser via `vim.ui.open()`.
keys.lang_map("lean", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Lean 4 Manual", url = "https://lean-lang.org/lean4/doc/" },
		{ name = "Theorem Proving in Lean 4", url = "https://lean-lang.org/theorem_proving_in_lean4/" },
		{ name = "Mathematics in Lean", url = "https://leanprover-community.github.io/mathematics_in_lean/" },
		{ name = "Mathlib4 Docs", url = "https://leanprover-community.github.io/mathlib4_docs/" },
		{ name = "Lean Zulip", url = "https://leanprover.zulipchat.com/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r) return r.name end, refs),
		{ prompt = lean_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Lean-specific alignment presets for mini.align:
-- • lean_def — align definitions on ":="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("lean") then
		---@type string Alignment preset icon from icons.lang
		local lean_align_icon = icons.lang.lean

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			lean_def = {
				description = "Align Lean definitions on ':='",
				icon = lean_align_icon,
				split_pattern = ":=",
				category = "functional",
				lang = "lean",
				filetypes = { "lean" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("lean", "lean_def")
		align_registry.mark_language_loaded("lean")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("lean", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("lean_def"), {
			desc = lean_align_icon .. "  Align Lean def",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Lean-specific
-- parts (lean.nvim plugin, treesitter parser).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Lean                   │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ lean.nvim          │ ft = "lean" (true lazy load, manages LSP)   │
-- │ nvim-lspconfig     │ NOT used for Lean (lean.nvim manages LSP)   │
-- │ mason.nvim         │ NOT used (lean installed via elan)           │
-- │ conform.nvim       │ NOT used (lean4 has built-in formatting)    │
-- │ nvim-lint          │ NOT used (lean4 LSP provides all diagnostics│
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Unlike most languages, Lean's toolchain is self-contained:
-- • LSP is managed by lean.nvim (not lspconfig)
-- • No separate formatter (lean4 LSP handles formatting)
-- • No separate linter (lean4 type checker IS the linter)
-- • Installation via elan (not Mason)
-- • The `cond` function ensures zero cost if lean is not installed
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Lean
return {
	-- ── LEAN.NVIM ──────────────────────────────────────────────────────────
	-- Julian/lean.nvim: comprehensive Lean 4 support for Neovim.
	-- Manages the entire Lean development experience:
	--   • LSP lifecycle (lean4 language server)
	--   • Infoview panel (goal state, type info, tactic hints)
	--   • Unicode abbreviation expansion (\alpha → α, etc.)
	--   • Tactic completion and proof navigation
	--
	-- Loaded exclusively on ft = "lean" — zero cost for non-Lean sessions.
	-- The `cond` function additionally checks that lean is installed,
	-- preventing errors when the binary is absent.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"Julian/lean.nvim",
		ft = { "lean" },
		cond = function()
			return vim.fn.executable("lean") == 1
		end,
		dependencies = {
			"neovim/nvim-lspconfig",
			"nvim-lua/plenary.nvim",
		},
		opts = {
			mappings = true,
			infoview = {
				autoopen = true,
				autopause = false,
				width = 50,
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					lean = "lean",
				},
			})

			-- ── Buffer-local options for Lean files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "lean" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "100"
					opt.textwidth = 100
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

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- lean: syntax highlighting, folding, text objects.
	-- Lean 4's syntax (tactics, term-mode proofs, Unicode operators,
	-- namespaces, attributes) benefits significantly from treesitter.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"lean",
			},
		},
	},
}
