---@file lua/langs/gleam.lua
---@description Gleam — LSP (built-in), formatter, treesitter & buffer-local keymaps
---@module "langs.gleam"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.elixir             Elixir language support (same BEAM ecosystem)
---@see langs.erlang             Erlang language support (same BEAM ecosystem)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/gleam.lua — Gleam language support                                ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("gleam") → {} if off        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "gleam"):                    │    ║
--- ║  │  ├─ LSP          gleam lsp (built into gleam binary, NOT Mason)  │    ║
--- ║  │  ├─ Formatter    gleam format --stdin (via conform.nvim)         │    ║
--- ║  │  ├─ Linter       — (via LSP diagnostics)                         │    ║
--- ║  │  ├─ Treesitter   gleam parser                                    │    ║
--- ║  │  ├─ DAP          — (not applicable)                              │    ║
--- ║  │  └─ Extras       gleam CLI integration (build, test, deps, docs) │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  gleam run             R  Run with arguments     │    ║
--- ║  │  ├─ BUILD     b  gleam build           l  gleam check            │    ║
--- ║  │  ├─ TEST      t  gleam test                                      │    ║
--- ║  │  ├─ SHELL     c  gleam shell (Erlang REPL with project modules)  │    ║
--- ║  │  ├─ FORMAT    f  gleam format (whole project)                    │    ║
--- ║  │  ├─ DEPS      p  Deps management (picker: add, remove, update…)  │    ║
--- ║  │  └─ DOCS      d  Generate docs (gleam docs build)                │    ║
--- ║  │               i  Project info          h  Documentation          │    ║
--- ║  │                                                                  │    ║
--- ║  │  LSP integration:                                                │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Gleam ships its own LSP (`gleam lsp`)                │    │    ║
--- ║  │  │  2. NOT in Mason registry — started manually via         │    │    ║
--- ║  │  │     vim.lsp.start() on FileType autocmd                  │    │    ║
--- ║  │  │  3. Root dir detected from gleam.toml or .git            │    │    ║
--- ║  │  │  4. No separate lspconfig server entry needed            │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType gleam):                             ║
--- ║  • colorcolumn=80, textwidth=80   (Gleam community convention)           ║
--- ║  • tabstop=2, shiftwidth=2        (Gleam standard: 2-space indent)       ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • commentstring="// %s"          (Rust-style line comments)             ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .gleam → gleam                                                        ║
--- ║                                                                          ║
--- ║  NOTE: Both the LSP and formatter are built into the `gleam` binary.     ║
--- ║  No Mason tools are needed — only the gleam binary must be in PATH.      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Gleam support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("gleam") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Gleam Nerd Font icon (trailing whitespace stripped)
local gleam_icon = icons.lang.gleam:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Gleam buffers.
-- The group is buffer-local and only visible when filetype == "gleam".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("gleam", "Gleam", gleam_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the gleam binary is available in PATH.
---
--- Notifies the user with an error if gleam is not found.
--- The gleam binary provides the compiler, LSP, formatter, and
--- package manager — all in one tool.
---
--- ```lua
--- if not check_gleam() then return end
--- ```
---
---@return boolean available `true` if `gleam` is executable, `false` otherwise
---@private
local function check_gleam()
	if vim.fn.executable("gleam") ~= 1 then
		vim.notify("gleam not found in PATH", vim.log.levels.ERROR, { title = "Gleam" })
		return false
	end
	return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — BUILD / RUN
--
-- Gleam project execution and compilation via the gleam CLI.
-- All keymaps save the buffer before execution.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the project with `gleam run`.
---
--- Saves the buffer, then compiles and executes the project's
--- main module in a terminal split.
keys.lang_map("gleam", "n", "<leader>lr", function()
	if not check_gleam() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("gleam run")
end, { desc = icons.ui.Play .. " Run project" })

--- Run the project with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then executes
--- `gleam run -- <args>` in a terminal split. Aborts silently
--- if the user cancels the prompt.
keys.lang_map("gleam", "n", "<leader>lR", function()
	if not check_gleam() then return end
	vim.cmd("silent! write")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal("gleam run -- " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Build the project with `gleam build`.
---
--- Saves the buffer, then compiles all project modules.
keys.lang_map("gleam", "n", "<leader>lb", function()
	if not check_gleam() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("gleam build")
end, { desc = icons.dev.Build .. " Build" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST / CHECK
--
-- Test execution and type checking via the gleam CLI.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the test suite with `gleam test`.
---
--- Saves the buffer, then compiles and executes all test modules.
keys.lang_map("gleam", "n", "<leader>lt", function()
	if not check_gleam() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("gleam test")
end, { desc = icons.dev.Test .. " Test" })

--- Type-check the project with `gleam check`.
---
--- Faster than a full build — only performs type checking without
--- code generation. Saves the buffer before checking.
keys.lang_map("gleam", "n", "<leader>ll", function()
	if not check_gleam() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("gleam check")
end, { desc = icons.ui.Check .. " Check" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SHELL / FORMAT
--
-- Interactive REPL and project-wide formatting.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Gleam shell (Erlang REPL with project modules).
---
--- Launches `gleam shell` which starts an Erlang shell with all
--- project modules compiled and available for interactive evaluation.
keys.lang_map("gleam", "n", "<leader>lc", function()
	if not check_gleam() then return end
	vim.cmd.split()
	vim.cmd.terminal("gleam shell")
end, { desc = icons.ui.Terminal .. " Gleam shell" })

--- Format the entire project with `gleam format`.
---
--- Runs `gleam format` which formats all `.gleam` files in the project
--- according to the built-in opinionated style (no configuration).
keys.lang_map("gleam", "n", "<leader>lf", function()
	if not check_gleam() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("gleam format")
end, { desc = gleam_icon .. " Format project" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEPS
--
-- Gleam dependency management via the built-in package manager.
-- Uses Hex.pm as the package registry (shared with Elixir/Erlang).
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a dependency management picker.
---
--- Available actions:
--- • Add dep…        — prompts for package name, runs `gleam add`
--- • Remove dep…     — prompts for package name, runs `gleam remove`
--- • Update deps     — updates all dependencies to latest compatible
--- • List deps       — displays the dependency tree
--- • Download deps   — fetches dependencies without building
keys.lang_map("gleam", "n", "<leader>lp", function()
	if not check_gleam() then return end

	---@type { name: string, cmd: string, prompt?: boolean }[]
	local actions = {
		{ name = "Add dep…", cmd = "gleam add", prompt = true },
		{ name = "Remove dep…", cmd = "gleam remove", prompt = true },
		{ name = "Update deps", cmd = "gleam deps update" },
		{ name = "List deps", cmd = "gleam deps list" },
		{ name = "Download deps", cmd = "gleam deps download" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = gleam_icon .. " Deps:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]
			if action.prompt then
				vim.ui.input({ prompt = "Package: " }, function(name)
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
end, { desc = icons.ui.Package .. " Deps" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Documentation generation, project information, and quick access
-- to Gleam resources via the system browser.
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate project documentation with `gleam docs build`.
---
--- Builds HTML documentation for all public modules and functions
--- in the project. Output is written to `build/docs/`.
keys.lang_map("gleam", "n", "<leader>ld", function()
	if not check_gleam() then return end
	vim.cmd.split()
	vim.cmd.terminal("gleam docs build")
end, { desc = gleam_icon .. " Generate docs" })

--- Show Gleam project information in a notification.
---
--- Displays:
--- • Gleam version (if available)
--- • Current working directory
--- • Project presence (gleam.toml found or not)
keys.lang_map("gleam", "n", "<leader>li", function()
	---@type string[]
	local info = { gleam_icon .. " Gleam Info:", "" }

	if vim.fn.executable("gleam") == 1 then
		local version = vim.fn.system("gleam --version 2>/dev/null"):gsub("%s+$", "")
		info[#info + 1] = "  Version: " .. version
	end

	info[#info + 1] = "  CWD:     " .. vim.fn.getcwd()
	local has_toml = vim.fn.filereadable(vim.fn.getcwd() .. "/gleam.toml") == 1
	info[#info + 1] = "  Project: " .. (has_toml and "✓ gleam.toml" or "✗ no gleam.toml")

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Gleam" })
end, { desc = icons.diagnostics.Info .. " Project info" })

--- Open Gleam documentation in the system browser.
---
--- Presents a picker with key reference pages:
--- • Gleam Language Tour  — interactive tutorial
--- • Gleam Docs           — official documentation
--- • Gleam Stdlib         — standard library reference
--- • Hex.pm               — package registry (Gleam packages)
--- • Gleam GitHub         — source code and issues
keys.lang_map("gleam", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Gleam Language Tour", url = "https://tour.gleam.run/" },
		{ name = "Gleam Docs", url = "https://gleam.run/documentation/" },
		{ name = "Gleam Stdlib", url = "https://hexdocs.pm/gleam_stdlib/" },
		{ name = "Hex.pm (packages)", url = "https://hex.pm/packages?search=gleam" },
		{ name = "Gleam GitHub", url = "https://github.com/gleam-lang/gleam" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = gleam_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Gleam-specific alignment presets for mini.align:
-- • gleam_record — align record/custom type fields on ":"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("gleam") then
		---@type string Alignment preset icon from icons.lang
		local align_icon = icons.lang.gleam

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			gleam_record = {
				description = "Align Gleam record fields on ':'",
				icon = align_icon,
				split_pattern = ":",
				category = "functional",
				lang = "gleam",
				filetypes = { "gleam" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("gleam", "gleam_record")
		align_registry.mark_language_loaded("gleam")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("gleam", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("gleam_record"), {
			desc = align_icon .. "  Align Gleam record",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Gleam-specific
-- parts (manual LSP start, formatter, parser).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Gleam                  │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig                         │ init only (manual vim.lsp.start on FileType) │
-- │ conform.nvim                           │ opts fn merge (gleam format --stdin)         │
-- │ nvim-treesitter                        │ opts merge (gleam parser added)              │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Gleam ships its own LSP and formatter built into the `gleam`
-- binary. No Mason tools are needed. The LSP is started manually via
-- `vim.lsp.start()` in the FileType autocmd because it is not in the
-- Mason registry and does not have an nvim-lspconfig server definition.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Gleam
return {
	-- ── LSP (manual start — gleam lsp is built into the binary) ────────────
	-- Gleam's LSP is not in the Mason registry and not defined as an
	-- nvim-lspconfig server. Instead, we use `vim.lsp.start()` in a
	-- FileType autocmd to start the `gleam lsp` subprocess.
	--
	-- Root directory detection:
	-- 1. Walk upward from the buffer looking for `gleam.toml` or `.git`
	-- 2. Fallback to CWD if neither is found
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					gleam = "gleam",
				},
			})

			-- ── Buffer-local options + manual LSP start ──────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "gleam" },
				callback = function(args)
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
					opt.commentstring = "// %s"

					-- ── Start gleam LSP manually ─────────────────────
					if vim.fn.executable("gleam") == 1 then
						vim.lsp.start({
							name = "gleam",
							cmd = { "gleam", "lsp" },
							root_dir = vim.fs.dirname(vim.fs.find({ "gleam.toml", ".git" }, {
								upward = true,
								path = vim.api.nvim_buf_get_name(args.buf),
							})[1]) or vim.fn.getcwd(),
							filetypes = { "gleam" },
						})
					end
				end,
			})
		end,
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- gleam format: the built-in opinionated formatter (no configuration).
	-- Uses `gleam format --stdin` for stdin/stdout formatting via conform.
	-- Only configured if the gleam binary is available.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = function(_, opts)
			if vim.fn.executable("gleam") == 1 then
				opts.formatters_by_ft = opts.formatters_by_ft or {}
				opts.formatters_by_ft.gleam = { "gleam" }

				opts.formatters = opts.formatters or {}
				opts.formatters.gleam = {
					command = "gleam",
					args = { "format", "--stdin" },
					stdin = true,
				}
			end
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- gleam: syntax highlighting, folding, text objects and indentation
	--        for Gleam source files (.gleam).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"gleam",
			},
		},
	},
}
