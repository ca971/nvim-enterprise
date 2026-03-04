---@file lua/langs/thrift.lua
---@description Thrift — treesitter, code generation & buffer-local keymaps
---@module "langs.thrift"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.python             Python language support (same architecture)
---@see langs.prisma             Prisma language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/thrift.lua — Apache Thrift IDL support                            ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("thrift") → {} if off       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "thrift"):                   │    ║
--- ║  │  ├─ LSP          none (no standard Thrift LS available)          │    ║
--- ║  │  ├─ Formatter    none (Thrift IDL has no standard formatter)     │    ║
--- ║  │  ├─ Linter       thrift --audit (built-in validation)            │    ║
--- ║  │  ├─ Treesitter   thrift parser (syntax highlighting)             │    ║
--- ║  │  └─ Extras       code generation (10 target languages)           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ GENERATE  g  Generate code (10-language picker)              │    ║
--- ║  │  ├─ VALIDATE  v  Validate / audit (thrift --audit)               │    ║
--- ║  │  ├─ COMMANDS  c  Commands picker (5 generators + validate)       │    ║
--- ║  │  ├─ INFO      i  Thrift compiler info (version + CWD)            │    ║
--- ║  │  └─ DOCS      h  Documentation browser (IDL spec, docs, GitHub)  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Thrift CLI resolution:                                          │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. thrift executable → thrift compiler                  │    │    ║
--- ║  │  │  2. nil               → user notification with error     │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Supported code generation targets (10):                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  go · java · py · cpp · js · rust · rb · csharp ·        │    │    ║
--- ║  │  │  erlang · ocaml                                          │    │    ║
--- ║  │  │                                                          │    │    ║
--- ║  │  │  Output directory: gen-<lang>/ (e.g. gen-go/, gen-java/) │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType thrift):                            ║
--- ║  • colorcolumn=100, textwidth=100  (Thrift convention)                   ║
--- ║  • tabstop=2, shiftwidth=2         (2-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="// %s"           (Thrift uses // comments)             ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .thrift → thrift                                                      ║
--- ║                                                                          ║
--- ║  Notable omissions:                                                      ║
--- ║  • No LSP — no standard Thrift language server exists                    ║
--- ║  • No formatter — Thrift IDL has no widely-adopted formatter             ║
--- ║  • No DAP — Thrift is an IDL, not a runtime language                     ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Thrift support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("thrift") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Thrift Nerd Font icon (trailing whitespace stripped)
local thrift_icon = icons.lang.thrift:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Thrift buffers.
-- The group is buffer-local and only visible when filetype == "thrift".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("thrift", "Thrift", thrift_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the Thrift compiler (`thrift`) is available in PATH.
---
--- Notifies the user with an error if `thrift` is not found.
--- All keymaps should call this before executing Thrift commands.
---
--- ```lua
--- if not check_thrift() then return end
--- vim.cmd.terminal("thrift --gen go file.thrift")
--- ```
---
---@return boolean available `true` if `thrift` is executable
---@private
local function check_thrift()
	if vim.fn.executable("thrift") ~= 1 then
		vim.notify(
			"thrift compiler not found in PATH",
			vim.log.levels.ERROR,
			{ title = "Thrift" }
		)
		return false
	end
	return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — GENERATE
--
-- Code generation from Thrift IDL files.
-- The Thrift compiler supports 10 target languages.
-- Generated code is output to `gen-<lang>/` directories.
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate code from the current Thrift file.
---
--- Presents a picker with 10 target languages:
--- go, java, py, cpp, js, rust, rb, csharp, erlang, ocaml.
---
--- Generated code is placed in `gen-<lang>/` in the CWD
--- (e.g. `gen-go/`, `gen-java/`).
keys.lang_map("thrift", "n", "<leader>lg", function()
	if not check_thrift() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	---@type string[]
	local targets = { "go", "java", "py", "cpp", "js", "rust", "rb", "csharp", "erlang", "ocaml" }

	vim.ui.select(targets, { prompt = thrift_icon .. " Target language:" }, function(lang)
		if not lang then return end
		vim.cmd.split()
		vim.cmd.terminal(
			string.format(
				"thrift --gen %s -out gen-%s %s",
				lang,
				lang,
				vim.fn.shellescape(file)
			)
		)
	end)
end, { desc = thrift_icon .. " Generate code" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — VALIDATE
--
-- Thrift IDL validation using the built-in `--audit` flag.
-- Reports pass/fail via notifications.
-- ═══════════════════════════════════════════════════════════════════════════

--- Validate the current Thrift file.
---
--- Runs `thrift --audit` which checks the IDL file for:
--- - Syntax errors
--- - Undefined type references
--- - Circular dependencies
--- - Deprecated constructs
---
--- Reports pass/fail via notifications (does not open a terminal).
keys.lang_map("thrift", "n", "<leader>lv", function()
	if not check_thrift() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("thrift --audit " .. vim.fn.shellescape(file) .. " 2>&1")

	if result == "" or result:match("^%s*$") then
		vim.notify("✓ Thrift file is valid", vim.log.levels.INFO, { title = "Thrift" })
	else
		vim.notify(result, vim.log.levels.WARN, { title = "Thrift" })
	end
end, { desc = icons.ui.Check .. " Validate" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COMMANDS PICKER
--
-- Unified command palette for common Thrift operations.
-- Combines the top 5 code generation targets with validation.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Thrift commands picker.
---
--- Presents 6 common operations:
--- - Generate Go / Java / Python / C++ / Rust
--- - Validate (audit)
---
--- For the full 10-language picker, use `<leader>lg` instead.
keys.lang_map("thrift", "n", "<leader>lc", function()
	if not check_thrift() then return end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "Generate Go",     cmd = "thrift --gen go -out gen-go " .. file },
		{ name = "Generate Java",   cmd = "thrift --gen java -out gen-java " .. file },
		{ name = "Generate Python", cmd = "thrift --gen py -out gen-py " .. file },
		{ name = "Generate C++",    cmd = "thrift --gen cpp -out gen-cpp " .. file },
		{ name = "Generate Rust",   cmd = "thrift --gen rust -out gen-rust " .. file },
		{ name = "Validate",        cmd = "thrift --audit " .. file },
	}

	vim.ui.select(
		vim.tbl_map(function(a) return a.name end, actions),
		{ prompt = thrift_icon .. " Thrift:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = thrift_icon .. " Commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INFO / DOCUMENTATION
--
-- Thrift compiler information and external documentation access.
-- Info displays the compiler version and CWD.
-- Documentation links open in the system browser via `vim.ui.open()`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Display Thrift compiler information.
---
--- Shows:
--- - Compiler version (from `thrift --version`)
--- - Current working directory
---
--- Displays "✗ thrift not found" if the compiler is not in PATH.
keys.lang_map("thrift", "n", "<leader>li", function()
	---@type string[]
	local info = { thrift_icon .. " Thrift Info:", "" }

	if vim.fn.executable("thrift") == 1 then
		---@type string
		local version = vim.fn.system("thrift --version 2>/dev/null"):gsub("%s+$", "")
		info[#info + 1] = "  Version: " .. version
	else
		info[#info + 1] = "  ✗ thrift not found"
	end

	info[#info + 1] = "  CWD:     " .. vim.fn.getcwd()

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Thrift" })
end, { desc = icons.diagnostics.Info .. " Thrift info" })

--- Open Thrift documentation in the system browser.
---
--- Presents a selection menu with links to key Thrift documentation
--- resources. The selected URL is opened via `vim.ui.open()`.
---
--- Available documentation links:
--- - Thrift IDL Spec (IDL language reference)
--- - Thrift Docs (general documentation)
--- - Thrift GitHub (Apache Thrift repository)
keys.lang_map("thrift", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Thrift IDL Spec", url = "https://thrift.apache.org/docs/idl" },
		{ name = "Thrift Docs",     url = "https://thrift.apache.org/docs/" },
		{ name = "Thrift GitHub",   url = "https://github.com/apache/thrift" },
	}

	vim.ui.select(
		vim.tbl_map(function(r) return r.name end, refs),
		{ prompt = thrift_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Thrift-specific alignment presets for mini.align:
-- • thrift_fields — align struct/service field definitions on whitespace
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("thrift") then
		---@type string Alignment preset icon from icons.lang
		local thrift_align_icon = icons.lang.thrift

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			thrift_fields = {
				description = "Align Thrift field definitions",
				icon = thrift_align_icon,
				split_pattern = "%s+",
				category = "domain",
				lang = "thrift",
				filetypes = { "thrift" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("thrift", "thrift_fields")
		align_registry.mark_language_loaded("thrift")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("thrift", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("thrift_fields"), {
			desc = thrift_align_icon .. "  Align Thrift fields",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Thrift-specific
-- parts (filetype detection, buffer options, treesitter parser).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Thrift                 │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ init only (filetype + buffer options)       │
-- │ nvim-treesitter    │ opts merge (thrift parser ensured)          │
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- Notable omissions:
-- • No LSP server — no standard Thrift language server exists.
--   The nvim-lspconfig spec provides filetype detection and buffer
--   options only.
-- • No Mason spec — the thrift compiler is typically installed via
--   system package managers (apt, brew, etc.), not Mason.
-- • No formatter — Thrift IDL has no widely-adopted code formatter.
-- • No linter spec — validation is done via `thrift --audit` keymap.
-- • No DAP — Thrift is an Interface Definition Language (IDL),
--   not a runtime language.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Thrift
return {
	-- ── FILETYPE + BUFFER OPTIONS ──────────────────────────────────────────
	-- nvim-lspconfig is used here ONLY for filetype registration and
	-- buffer-local options. No Thrift LSP server is configured.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					thrift = "thrift",
				},
			})

			-- ── Buffer-local options for Thrift files ────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "thrift" },
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

					opt.commentstring = "// %s"
				end,
			})
		end,
	},

	-- ── TREESITTER PARSER ──────────────────────────────────────────────────
	-- thrift: syntax highlighting for Thrift IDL files
	-- (structs, services, enums, typedefs, namespaces)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"thrift",
			},
		},
	},
}
