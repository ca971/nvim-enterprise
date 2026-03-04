---@file lua/langs/zig.lua
---@description Zig — LSP, formatter, treesitter, DAP & buffer-local keymaps
---@module "langs.zig"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.rust               Rust language support (same systems-level architecture)
---@see langs.c                  C language support (shared DAP adapter: codelldb)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/zig.lua — Zig language support                                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("zig") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "zig"):                      │    ║
--- ║  │  ├─ LSP          zls          (Zig Language Server)              │    ║
--- ║  │  ├─ Formatter    zigfmt       (zig fmt, built-in via zls)        │    ║
--- ║  │  ├─ Linter       zls          (via LSP diagnostics + warn_style) │    ║
--- ║  │  ├─ Treesitter   zig parser                                      │    ║
--- ║  │  └─ DAP          codelldb / lldb-vscode (native debugger)        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run (build run / zig run)  R  Run with args     │    ║
--- ║  │  │            c  Quick run (single file)                         │    ║
--- ║  │  ├─ BUILD     b  Build (build / build-exe)                       │    ║
--- ║  │  ├─ TEST      t  Test (build test / zig test) T  Test at cursor  │    ║
--- ║  │  ├─ DEBUG     d  Debug (codelldb / lldb / gdb fallback)          │    ║
--- ║  │  ├─ EMIT      e  Emit assembly               a  Emit LLVM IR     │    ║
--- ║  │  ├─ DEPS      p  Fetch dependencies           s  Build steps     │    ║
--- ║  │  ├─ FORMAT    f  Format (zig fmt)                                │    ║
--- ║  │  └─ DOCS      i  Zig info                    h  Documentation    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Build system detection:                                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  has_build_zig() checks CWD for build.zig                │    │    ║
--- ║  │  │  When detected (project mode):                           │    │    ║
--- ║  │  │  • Run    → zig build run [-- args]                      │    │    ║
--- ║  │  │  • Build  → zig build                                    │    │    ║
--- ║  │  │  • Test   → zig build test                               │    │    ║
--- ║  │  │  • Debug  → zig build + launch zig-out/bin/*             │    │    ║
--- ║  │  │  When absent (single-file mode):                         │    │    ║
--- ║  │  │  • Run    → zig run <file> [-- args]                     │    │    ║
--- ║  │  │  • Build  → zig build-exe <file>                         │    │    ║
--- ║  │  │  • Test   → zig test <file>                              │    │    ║
--- ║  │  │  • Debug  → zig build-exe <file> + lldb/gdb              │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  DAP integration flow:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Try nvim-dap with codelldb (Mason) or lldb-vscode    │    │    ║
--- ║  │  │  2. If nvim-dap unavailable → fallback to terminal       │    │    ║
--- ║  │  │     lldb or gdb with debug-info binary                   │    │    ║
--- ║  │  │  3. All core DAP keymaps become active when dap loads:   │    │    ║
--- ║  │  │     <leader>dc · <leader>db · F5 · F9 · etc.             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType zig):                               ║
--- ║  • colorcolumn=100, textwidth=100  (Zig community convention)            ║
--- ║  • tabstop=4, shiftwidth=4         (Zig standard: 4-space indent)        ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring=// %s             (Zig line comment format)             ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .zig, .zon → zig                                                      ║
--- ║  • build.zig, build.zig.zon → zig                                        ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Zig support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("zig") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Zig Nerd Font icon (trailing whitespace stripped)
local zig_icon = icons.lang.zig:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Zig buffers.
-- The group is buffer-local and only visible when filetype == "zig".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("zig", "Zig", zig_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the `zig` compiler is available on the system.
---
--- Notifies the user with an error if the binary is not found.
--- Used as a guard in all keymaps that invoke the Zig toolchain.
---
--- ```lua
--- if not check_zig() then return end
--- vim.fn.system("zig build")
--- ```
---
---@return boolean available `true` if `zig` is executable
---@private
local function check_zig()
	if vim.fn.executable("zig") == 1 then return true end
	vim.notify("zig not found in PATH", vim.log.levels.ERROR, { title = "Zig" })
	return false
end

--- Detect whether the current project has a `build.zig` file.
---
--- When present, Zig commands use the build system (`zig build run`,
--- `zig build test`, etc.). When absent, commands operate on single
--- files (`zig run <file>`, `zig test <file>`, etc.).
---
--- ```lua
--- if has_build_zig() then
---   vim.cmd.terminal("zig build run")
--- else
---   vim.cmd.terminal("zig run " .. file)
--- end
--- ```
---
---@return boolean has_build `true` if `build.zig` exists in CWD
---@private
local function has_build_zig()
	return vim.fn.filereadable(vim.fn.getcwd() .. "/build.zig") == 1
end

--- Notify the user that no `build.zig` was found.
---
--- Centralizes the notification for keymaps that require a build
--- system (fetch deps, build steps).
---
---@return nil
---@private
local function notify_no_build_zig()
	vim.notify("No build.zig found", vim.log.levels.INFO, { title = "Zig" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN / BUILD
--
-- File execution and project build commands.
-- Automatically switches between project mode (build.zig) and
-- single-file mode based on `has_build_zig()`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current Zig project or file.
---
--- - **Project mode** (`build.zig` present) → `zig build run`
--- - **Single-file mode**                   → `zig run <file>`
---
--- Saves the buffer before execution.
keys.lang_map("zig", "n", "<leader>lr", function()
	if not check_zig() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	if has_build_zig() then
		vim.cmd.terminal("zig build run")
	else
		vim.cmd.terminal("zig run " .. vim.fn.shellescape(vim.fn.expand("%:p")))
	end
end, { desc = icons.ui.Play .. " Run" })

--- Run with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then executes:
--- - **Project mode**    → `zig build run -- <args>`
--- - **Single-file mode** → `zig run <file> -- <args>`
---
--- Aborts silently if the user cancels the prompt.
keys.lang_map("zig", "n", "<leader>lR", function()
	if not check_zig() then return end
	vim.cmd("silent! write")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		if has_build_zig() then
			vim.cmd.terminal("zig build run -- " .. args)
		else
			vim.cmd.terminal("zig run " .. vim.fn.shellescape(vim.fn.expand("%:p")) .. " -- " .. args)
		end
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Build the current project or compile a single file.
---
--- - **Project mode** (`build.zig` present) → `zig build`
--- - **Single-file mode**                   → `zig build-exe <file>`
---
--- Saves the buffer before building.
keys.lang_map("zig", "n", "<leader>lb", function()
	if not check_zig() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	if has_build_zig() then
		vim.cmd.terminal("zig build")
	else
		vim.cmd.terminal("zig build-exe " .. vim.fn.shellescape(vim.fn.expand("%:p")))
	end
end, { desc = icons.dev.Build .. " Build" })

--- Quick-run the current file as a Zig script.
---
--- Always uses `zig run <file>` regardless of build.zig presence.
--- Useful for running standalone scripts or playground files in a
--- project that has a build system.
keys.lang_map("zig", "n", "<leader>lc", function()
	if not check_zig() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("zig run " .. vim.fn.shellescape(vim.fn.expand("%:p")))
end, { desc = icons.ui.Terminal .. " Quick run" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via the Zig build system or single-file test runner.
-- Supports test filtering by name extracted from the current line.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite.
---
--- - **Project mode** (`build.zig` present) → `zig build test`
--- - **Single-file mode**                   → `zig test <file>`
---
--- Saves the buffer before execution.
keys.lang_map("zig", "n", "<leader>lt", function()
	if not check_zig() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	if has_build_zig() then
		vim.cmd.terminal("zig build test")
	else
		vim.cmd.terminal("zig test " .. vim.fn.shellescape(vim.fn.expand("%:p")))
	end
end, { desc = icons.dev.Test .. " Test" })

--- Run the test under the cursor.
---
--- Parses the current line for a Zig test declaration pattern
--- `test "name" {` and extracts the test name. Uses `--test-filter`
--- to run only the matching test.
---
--- Falls back to a warning notification if no test declaration is
--- found on the current line.
keys.lang_map("zig", "n", "<leader>lT", function()
	if not check_zig() then return end
	vim.cmd("silent! write")

	local line = vim.api.nvim_get_current_line()
	---@type string|nil
	local test_name = line:match('test%s+"(.-)"%s*{')

	if not test_name then
		vim.notify("No test found under cursor", vim.log.levels.WARN, { title = "Zig" })
		return
	end

	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("zig test " .. vim.fn.shellescape(file) .. " --test-filter " .. vim.fn.shellescape(test_name))
end, { desc = icons.dev.Test .. " Test under cursor" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via codelldb (Mason) or lldb-vscode, with a terminal
-- fallback to lldb / gdb when nvim-dap is not available.
--
-- Build system detection determines how the debug binary is produced:
-- - Project mode:    `zig build` → launch `zig-out/bin/*`
-- - Single-file:     `zig build-exe <file>` → launch `<file_stem>`
-- ═══════════════════════════════════════════════════════════════════════════

--- Start a debug session for the current project or file.
---
--- **Strategy 1: nvim-dap with codelldb**
--- - Builds the project, finds the executable in `zig-out/bin/`
--- - Launches a `codelldb` DAP session
---
--- **Strategy 2: terminal fallback (no nvim-dap)**
--- - Builds with debug info
--- - Opens lldb (preferred) or gdb in a terminal split
---
--- Saves the buffer before building.
keys.lang_map("zig", "n", "<leader>ld", function()
	if not check_zig() then return end
	vim.cmd("silent! write")

	local ok, dap = pcall(require, "dap")
	if not ok then
		-- ── Fallback: terminal debugger ──────────────────────────
		---@type string
		local debugger = vim.fn.executable("lldb") == 1 and "lldb" or "gdb"
		vim.cmd.split()
		if has_build_zig() then
			vim.cmd.terminal("zig build && " .. debugger .. " ./zig-out/bin/*")
		else
			local file = vim.fn.expand("%:p")
			local out = vim.fn.expand("%:p:r")
			vim.cmd.terminal(
				"zig build-exe " .. vim.fn.shellescape(file) .. " && " .. debugger .. " " .. vim.fn.shellescape(out)
			)
		end
		return
	end

	-- ── Strategy 1: DAP with codelldb ────────────────────────────
	if has_build_zig() then
		vim.fn.system("zig build")
		---@type string[]
		local exes = vim.fn.glob("zig-out/bin/*", false, true)
		if #exes > 0 then
			dap.run({
				type = "codelldb",
				request = "launch",
				name = "Debug (zig build)",
				program = exes[1],
				cwd = vim.fn.getcwd(),
			})
		else
			vim.notify("No executable found in zig-out/bin/", vim.log.levels.WARN, { title = "Zig" })
		end
	else
		vim.notify("Single-file DAP not yet configured — use terminal fallback", vim.log.levels.INFO, { title = "Zig" })
	end
end, { desc = icons.dev.Debug .. " Debug" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EMIT / INSPECT
--
-- Low-level compiler output inspection: assembly and LLVM IR.
-- Useful for performance analysis and understanding code generation.
-- ═══════════════════════════════════════════════════════════════════════════

--- Emit x86-64 assembly for the current file.
---
--- Runs `zig build-exe -femit-asm -fno-emit-bin` and displays the
--- first 200 lines of assembly output in a terminal split.
keys.lang_map("zig", "n", "<leader>le", function()
	if not check_zig() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("zig build-exe " .. vim.fn.shellescape(file) .. " -femit-asm -fno-emit-bin 2>&1 | head -200")
end, { desc = zig_icon .. " Emit assembly" })

--- Emit LLVM IR for the current file.
---
--- Runs `zig build-exe -femit-llvm-ir -fno-emit-bin` and displays the
--- first 200 lines of IR output in a terminal split. Useful for
--- understanding optimisation passes and debugging codegen issues.
keys.lang_map("zig", "n", "<leader>la", function()
	if not check_zig() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("zig build-exe " .. vim.fn.shellescape(file) .. " -femit-llvm-ir -fno-emit-bin 2>&1 | head -200")
end, { desc = zig_icon .. " Emit LLVM IR" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEPENDENCIES / BUILD STEPS
--
-- Build system utilities: dependency fetching and build step listing.
-- Both require a `build.zig` file in the current working directory.
-- ═══════════════════════════════════════════════════════════════════════════

--- Fetch project dependencies via `zig build --fetch`.
---
--- Downloads all dependencies declared in `build.zig.zon` into the
--- global Zig cache. Requires a `build.zig` file.
keys.lang_map("zig", "n", "<leader>lp", function()
	if not check_zig() then return end
	if not has_build_zig() then
		notify_no_build_zig()
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("zig build --fetch")
end, { desc = icons.ui.Package .. " Fetch deps" })

--- List available build steps via `zig build --help`.
---
--- Displays all steps defined in `build.zig` along with their
--- descriptions. Requires a `build.zig` file.
keys.lang_map("zig", "n", "<leader>ls", function()
	if not check_zig() then return end
	if not has_build_zig() then
		notify_no_build_zig()
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("zig build --help")
end, { desc = zig_icon .. " Build steps" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FORMAT
--
-- Manual formatting via `zig fmt`. Also available automatically
-- through conform.nvim (configured in the specs below).
-- ═══════════════════════════════════════════════════════════════════════════

--- Format the current file with `zig fmt`.
---
--- Runs `zig fmt` in-place on the current file, then reloads the
--- buffer to reflect changes. This is the same formatter used by
--- zls and enforces the canonical Zig style.
keys.lang_map("zig", "n", "<leader>lf", function()
	if not check_zig() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.fn.system("zig fmt " .. vim.fn.shellescape(file))
	vim.cmd.edit()
	vim.notify("Formatted", vim.log.levels.INFO, { title = "Zig" })
end, { desc = zig_icon .. " Format" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Zig toolchain info display and external documentation browser access.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show Zig toolchain information.
---
--- Displays:
--- - Zig compiler version
--- - `build.zig` presence (✓ / ✗)
--- - Current working directory
--- - Tool availability: zig, zls, lldb, gdb
keys.lang_map("zig", "n", "<leader>li", function()
	if not check_zig() then return end

	local version = vim.fn.system("zig version 2>/dev/null"):gsub("%s+$", "")

	---@type string[]
	local info = {
		zig_icon .. " Zig Info:",
		"",
		"  Version:   " .. version,
		"  build.zig: " .. (has_build_zig() and "✓" or "✗"),
		"  CWD:       " .. vim.fn.getcwd(),
		"",
		"  Tools:",
	}

	---@type string[]
	local tools = { "zig", "zls", "lldb", "gdb" }
	for _, tool in ipairs(tools) do
		info[#info + 1] = "    " .. (vim.fn.executable(tool) == 1 and "✓" or "✗") .. " " .. tool
	end

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Zig" })
end, { desc = icons.diagnostics.Info .. " Zig info" })

--- Open Zig documentation in the browser.
---
--- Presents a `vim.ui.select()` menu with links to:
--- - Zig Language Reference
--- - Zig Standard Library
--- - Zig Learn (tutorials)
--- - Zig News (community)
--- - Zigistry (package registry)
---
--- If the cursor is on a word, prepends a "Search std: <word>"
--- option that links directly to the standard library search.
keys.lang_map("zig", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")

	---@class ZigDocRef
	---@field name string Display label for the documentation link
	---@field url string URL to open in the browser

	---@type ZigDocRef[]
	local refs = {
		{ name = "Zig Language Reference", url = "https://ziglang.org/documentation/master/" },
		{ name = "Zig Standard Library", url = "https://ziglang.org/documentation/master/std/" },
		{ name = "Zig Learn", url = "https://ziglearn.org/" },
		{ name = "Zig News", url = "https://zig.news/" },
		{ name = "Zig Packages (zigistry)", url = "https://zigistry.dev/" },
	}

	-- Prepend contextual std search if cursor is on a word
	if word ~= "" then
		table.insert(refs, 1, {
			name = "Search std: " .. word,
			url = "https://ziglang.org/documentation/master/std/#" .. word,
		})
	end

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = zig_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Zig-specific alignment presets for mini.align:
-- • zig_struct — align struct field declarations on ":"
-- • zig_assign — align assignments / const declarations on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("zig") then
		---@type string Alignment preset icon from icons.lang
		local zig_align_icon = icons.lang.zig

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			zig_struct = {
				description = "Align Zig struct fields on ':'",
				icon = zig_align_icon,
				split_pattern = ":",
				category = "systems",
				lang = "zig",
				filetypes = { "zig" },
			},
			zig_assign = {
				description = "Align Zig assignments on '='",
				icon = zig_align_icon,
				split_pattern = "=",
				category = "systems",
				lang = "zig",
				filetypes = { "zig" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("zig", "zig_struct")
		align_registry.mark_language_loaded("zig")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("zig", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("zig_struct"), {
			desc = zig_align_icon .. "  Align Zig struct",
		})
		keys.lang_map("zig", { "n", "x" }, "<leader>aT", align_registry.make_align_fn("zig_assign"), {
			desc = zig_align_icon .. "  Align Zig assign",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Zig-specific
-- parts (servers, formatters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Zig                     │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (zls server added on require)     │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.zig)            │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: No separate linter spec — zls provides real-time diagnostics
-- via LSP (including warn_style for style violations).
-- NOTE: DAP adapter (codelldb) is expected to be installed via Mason
-- by the C/C++ or Rust lang module, or manually.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Zig
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- zls: Zig Language Server
	-- Provides completions, diagnostics, hover, go-to-definition,
	-- format-on-save, import detection, and style warnings.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				zls = {
					settings = {
						zls = {
							enable_build_on_save = false,
							build_on_save_step = "check",
							enable_autofix = true,
							warn_style = true,
							enable_import_detection = true,
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					zig = "zig",
					zon = "zig",
				},
				filename = {
					["build.zig"] = "zig",
					["build.zig.zon"] = "zig",
				},
			})

			-- ── Buffer-local options for Zig files ───────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "zig" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "100"
					opt.textwidth = 100
					opt.tabstop = 4
					opt.shiftwidth = 4
					opt.softtabstop = 4
					opt.expandtab = true
					opt.number = true
					opt.relativenumber = true
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
					opt.commentstring = "// %s"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures zls is installed via Mason. The zig compiler itself must
	-- be installed system-wide (zigup, brew, or manual download).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"zls",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- zigfmt: the canonical Zig formatter (`zig fmt`), enforces the
	-- single official code style. Also available via the <leader>lf
	-- keymap and zls format-on-save.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				zig = { "zigfmt" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- zig: syntax highlighting, folding, text objects, and AST-based
	--      navigation for Zig source files
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"zig",
			},
		},
	},
}
