---@file lua/langs/typescript.lua
---@description TypeScript — LSP, formatter, linter, treesitter, DAP & buffer-local keymaps
---@module "langs.typescript"
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
---@see langs.lua                Lua language support (same architecture)
---@see langs.rust               Rust language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/typescript.lua — TypeScript language support                      ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("typescript") → {} if off   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = typescript/typescriptreact):     │    ║
--- ║  │  ├─ LSP          vtsls          (TypeScript language server)     │    ║
--- ║  │  ├─ Formatter    prettier       (opinionated code formatter)     │    ║
--- ║  │  ├─ Linter       eslint_d       (fast ESLint daemon)             │    ║
--- ║  │  ├─ Treesitter   typescript · tsx parsers                        │    ║
--- ║  │  ├─ DAP          js-debug-adapter (Node.js / Chrome debugger)    │    ║
--- ║  │  └─ Extras       vtsls TS version selector                       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file (tsx/bun)     R  Run with arguments    │    ║
--- ║  │  │            e  Execute selection (visual)                      │    ║
--- ║  │  ├─ BUILD     b  Type check (tsc --noEmit)                       │    ║
--- ║  │  ├─ TEST      t  Run tests (npm/bun)    T  Test current file     │    ║
--- ║  │  ├─ DEBUG     d  Debug (DAP continue)                            │    ║
--- ║  │  ├─ REPL      c  REPL (tsx / node)                               │    ║
--- ║  │  ├─ TOOLS     x  ESLint fix              o  Organize imports     │    ║
--- ║  │  │            a  Add missing imports     e  Remove unused imports│    ║
--- ║  │  │            s  Switch test ↔ source    v  Select TS version    │    ║
--- ║  │  └─ DOCS      h  TypeScript docs         i  Package info (npm)   │    ║
--- ║  │                                                                  │    ║
--- ║  │  DAP integration flow:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. js-debug-adapter installed via Mason                 │    │    ║
--- ║  │  │  2. mason-nvim-dap auto-configures pwa-node adapter      │    │    ║
--- ║  │  │  3. dap.continue() presents available configurations     │    │    ║
--- ║  │  │  4. All core DAP keymaps become active:                  │    │    ║
--- ║  │  │     <leader>dc · <leader>db · F5 · F9 · etc.             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType typescript/typescriptreact):        ║
--- ║  • colorcolumn=100, textwidth=100  (common TS project line length)       ║
--- ║  • tabstop=2, shiftwidth=2         (standard TS/JS indentation)          ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .ts, .mts, .cts → typescript                                          ║
--- ║  • .tsx → typescriptreact                                                ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if TypeScript support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("typescript") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string TypeScript Nerd Font icon (trailing whitespace stripped)
local ts_icon = icons.lang.typescript:gsub("%s+$", "")

---@type string[] Filetypes covered by this language module
local ts_ft = { "typescript", "typescriptreact" }

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUPS
--
-- Registers the <leader>l group label for TypeScript buffers.
-- Both "typescript" and "typescriptreact" filetypes get the same label.
-- The groups are buffer-local and only visible in matching buffers.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("typescript", "TypeScript", ts_icon)
keys.lang_group("typescriptreact", "TypeScript", ts_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the project's package manager from its lockfile.
---
--- Resolution order:
--- 1. `bun.lockb`       → bun
--- 2. `pnpm-lock.yaml`  → pnpm
--- 3. `yarn.lock`       → yarn
--- 4. fallback          → npm
---
--- ```lua
--- local pm = get_pm()   -- "bun" | "pnpm" | "yarn" | "npm"
--- ```
---
---@return string pm Package manager command name
---@private
local function get_pm()
	if vim.fn.filereadable("bun.lockb") == 1 then return "bun" end
	if vim.fn.filereadable("pnpm-lock.yaml") == 1 then return "pnpm" end
	if vim.fn.filereadable("yarn.lock") == 1 then return "yarn" end
	return "npm"
end

--- Detect the best available TypeScript runner.
---
--- Resolution order:
--- 1. `tsx`      — fast esbuild-based TS executor (recommended)
--- 2. `bun`      — Bun runtime (native TS support)
--- 3. `ts-node`  — classic TS runner (slower, requires tsconfig)
--- 4. `deno run` — Deno runtime
---
--- ```lua
--- local runner = get_runner()
--- if runner then
---   vim.cmd.terminal(runner .. " script.ts")
--- end
--- ```
---
---@return string|nil runner Command to execute TypeScript files, or `nil` if none found
---@private
local function get_runner()
	if vim.fn.executable("tsx") == 1 then return "tsx" end
	if vim.fn.executable("bun") == 1 then return "bun" end
	if vim.fn.executable("ts-node") == 1 then return "ts-node" end
	if vim.fn.executable("deno") == 1 then return "deno run" end
	return nil
end

--- Notify the user that no TypeScript runner was found.
---
--- Centralizes the error notification to avoid repetition across
--- all keymaps that require a TS runner binary.
---
---@return nil
---@private
local function notify_no_runner()
	vim.notify("No TypeScript runner found (install tsx: npm i -g tsx)", vim.log.levels.WARN, { title = "TypeScript" })
end

--- Execute an LSP code action by its kind string.
---
--- Sends a `textDocument/codeAction` request filtered by `kind`,
--- waits synchronously for the response (3 s timeout), and applies
--- any workspace edits returned by the language server.
---
--- Used to implement organize-imports, add-missing-imports, and
--- remove-unused-imports without relying on server-specific commands.
---
--- ```lua
--- lsp_code_action("source.organizeImports")
--- lsp_code_action("source.addMissingImports")
--- lsp_code_action("source.removeUnused")
--- ```
---
---@param kind string LSP CodeActionKind (e.g. `"source.organizeImports"`)
---@return nil
---@private
local function lsp_code_action(kind)
	local params = vim.lsp.util.make_range_params()
	params.context = { only = { kind } }
	local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 3000)
	for _, res in pairs(result or {}) do
		for _, r in pairs(res.result or {}) do
			if r.edit then vim.lsp.util.apply_workspace_edit(r.edit, "utf-16") end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- File execution and selection evaluation.
-- All keymaps open a terminal split for output.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current TypeScript file in a terminal split.
---
--- Saves the buffer before execution. Uses the detected TypeScript
--- runner from `get_runner()` (tsx → bun → ts-node → deno).
keys.lang_map(ts_ft, "n", "<leader>lr", function()
	local runner = get_runner()
	if not runner then
		notify_no_runner()
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(runner .. " " .. vim.fn.shellescape(vim.fn.expand("%:p")))
end, { desc = icons.ui.Play .. " Run file" })

--- Run the current TypeScript file with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then executes in a
--- terminal split. Aborts silently if the user cancels the prompt.
keys.lang_map(ts_ft, "n", "<leader>lR", function()
	local runner = get_runner()
	if not runner then
		notify_no_runner()
		return
	end
	vim.cmd("silent! write")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal(runner .. " " .. vim.fn.shellescape(vim.fn.expand("%:p")) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Execute the visual selection as TypeScript code.
---
--- Yanks the selection into register `z`, then passes it to the
--- detected runner with `-e` flag in a terminal split.
keys.lang_map(ts_ft, "v", "<leader>le", function()
	local runner = get_runner()
	if not runner then
		notify_no_runner()
		return
	end
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code == "" then return end
	vim.cmd.split()
	vim.cmd.terminal(runner .. " -e " .. vim.fn.shellescape(code))
end, { desc = ts_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TYPE CHECK
--
-- TypeScript compiler invocation for type-checking only (no emit).
-- Uses `tsc --noEmit` with pretty-printed output.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run `tsc --noEmit` to type-check the entire project.
---
--- Opens a terminal split with the TypeScript compiler output.
--- Requires a `tsconfig.json` in the project root (or a parent dir).
keys.lang_map(ts_ft, "n", "<leader>lb", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("npx tsc --noEmit --pretty")
end, { desc = ts_icon .. " Type check (tsc)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via the project's configured test runner.
-- Supports vitest and jest, auto-detected by config file presence.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite using the project's package manager.
---
--- Detects the package manager via `get_pm()` and runs the `test`
--- script. For npm uses `npm run test`; for others (bun / pnpm /
--- yarn) uses `<pm> test` directly.
keys.lang_map(ts_ft, "n", "<leader>lt", function()
	vim.cmd("silent! write")
	local pm = get_pm()
	vim.cmd.split()
	vim.cmd.terminal(pm .. " " .. (pm == "npm" and "run " or "") .. "test")
end, { desc = icons.dev.Test .. " Run tests" })

--- Run tests for the current file only.
---
--- Auto-detects the test runner by config file presence:
--- - `vitest.config.ts` present → `npx vitest run <file>`
--- - fallback                   → `npx jest --no-coverage <file>`
keys.lang_map(ts_ft, "n", "<leader>lT", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local cmd
	if vim.fn.filereadable("vitest.config.ts") == 1 then
		cmd = "vitest run " .. vim.fn.shellescape(file)
	else
		cmd = "jest --no-coverage " .. vim.fn.shellescape(file)
	end
	vim.cmd.split()
	vim.cmd.terminal("npx " .. cmd)
end, { desc = icons.dev.Test .. " Test file" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via nvim-dap and js-debug-adapter.
--
-- <leader>ld starts or continues a debug session. The adapter
-- (js-debug-adapter / pwa-node) is auto-configured by mason-nvim-dap.
-- Both <leader>ld (lang) and <leader>dc (core dap) work in TS files.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Saves the buffer, then calls `dap.continue()` which either resumes
--- a paused session or launches a new one using the js-debug adapter.
keys.lang_map(ts_ft, "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "TypeScript" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (js)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
--
-- Opens an interactive TypeScript / JavaScript REPL in a terminal split.
-- Prefers tsx when available for native TypeScript support.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a TypeScript REPL in a terminal split.
---
--- Prefers `tsx` if available (native TS support, top-level await),
--- otherwise falls back to `node` (JavaScript only).
keys.lang_map(ts_ft, "n", "<leader>lc", function()
	---@type string
	local cmd = vim.fn.executable("tsx") == 1 and "tsx" or "node"
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Terminal .. " REPL" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Development utilities: ESLint fix, import management via LSP code
-- actions, test / source file switching, and TS version selection.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run ESLint fix on the current file.
---
--- Executes `eslint_d --fix` in-place on the current file, then
--- reloads the buffer to reflect changes. Requires `eslint_d` to
--- be installed globally (`npm i -g eslint_d`).
keys.lang_map(ts_ft, "n", "<leader>lx", function()
	if vim.fn.executable("eslint_d") ~= 1 then
		vim.notify("Install eslint_d: npm i -g eslint_d", vim.log.levels.WARN, { title = "TypeScript" })
		return
	end
	vim.cmd("silent! write")
	vim.fn.system("eslint_d --fix " .. vim.fn.shellescape(vim.fn.expand("%:p")))
	vim.cmd.edit()
	vim.notify("ESLint fixed", vim.log.levels.INFO, { title = "TypeScript" })
end, { desc = ts_icon .. " ESLint fix" })

--- Organize imports via LSP code action.
---
--- Sends a `source.organizeImports` code action request to the
--- attached TypeScript language server (vtsls). Groups and sorts
--- import statements according to the TS/ESLint configuration.
keys.lang_map(ts_ft, "n", "<leader>lo", function()
	lsp_code_action("source.organizeImports")
end, { desc = ts_icon .. " Organize imports" })

--- Add missing imports via LSP code action.
---
--- Sends a `source.addMissingImports` code action request to vtsls.
--- Auto-resolves unresolved identifiers using the project's type
--- declarations and `node_modules`.
keys.lang_map(ts_ft, "n", "<leader>la", function()
	lsp_code_action("source.addMissingImports")
	vim.notify("Missing imports added", vim.log.levels.INFO, { title = "TypeScript" })
end, { desc = ts_icon .. " Add missing imports" })

--- Remove unused imports via LSP code action.
---
--- Sends a `source.removeUnused` code action request to vtsls.
--- Removes import statements that are not referenced anywhere
--- in the current file.
keys.lang_map(ts_ft, "n", "<leader>le", function()
	lsp_code_action("source.removeUnused")
	vim.notify("Unused imports removed", vim.log.levels.INFO, { title = "TypeScript" })
end, { desc = ts_icon .. " Remove unused imports" })

--- Toggle between test file and source file.
---
--- Heuristic:
--- - If current file matches `*.test.*` or `*.spec.*` → strip the
---   test/spec suffix to find the source file.
--- - Otherwise → append `.test.<ext>` (tries `.spec.<ext>` as
---   fallback) to find the corresponding test file.
---
--- Opens the matching file if it exists; notifies otherwise.
keys.lang_map(ts_ft, "n", "<leader>ls", function()
	local file = vim.fn.expand("%:p")
	---@type string
	local target
	if file:match("%.test%.") or file:match("%.spec%.") then
		target = file:gsub("%.test(%.[jt]sx?)$", "%1"):gsub("%.spec(%.[jt]sx?)$", "%1")
	else
		local ext = vim.fn.expand("%:e")
		local base = vim.fn.expand("%:p:r")
		target = base .. ".test." .. ext
		if vim.fn.filereadable(target) ~= 1 then target = base .. ".spec." .. ext end
	end
	if vim.fn.filereadable(target) == 1 then
		vim.cmd.edit(target)
	else
		vim.notify("No matching file found", vim.log.levels.INFO, { title = "TypeScript" })
	end
end, { desc = ts_icon .. " Switch test ↔ source" })

--- Select the TypeScript version used by vtsls.
---
--- Delegates to `:VtsSelectTsVersion` if vtsls is loaded.
--- Allows switching between the workspace-local and bundled TS
--- versions for accurate type-checking.
keys.lang_map(ts_ft, "n", "<leader>lv", function()
	if vim.fn.exists(":VtsSelectTsVersion") == 2 then
		vim.cmd("VtsSelectTsVersion")
	else
		vim.notify("vtsls not loaded", vim.log.levels.INFO, { title = "TypeScript" })
	end
end, { desc = ts_icon .. " Select TS version" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to TypeScript documentation and npm package metadata
-- without leaving the editor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open TypeScript documentation for the word under cursor.
---
--- Opens the TypeScript website search in the default browser.
--- If the cursor is on an empty word, opens the documentation index
--- at typescriptlang.org/docs/.
keys.lang_map(ts_ft, "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word ~= "" then
		vim.ui.open("https://www.typescriptlang.org/search?q=" .. word)
	else
		vim.ui.open("https://www.typescriptlang.org/docs/")
	end
end, { desc = icons.ui.Note .. " TypeScript docs" })

--- Show npm package info for the word under cursor.
---
--- Runs `npm info <word>` and displays the result (truncated to
--- 1000 chars) in a notification. Useful for quickly checking
--- installed package versions and metadata.
keys.lang_map(ts_ft, "n", "<leader>li", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then return end
	local result = vim.fn.system("npm info " .. word .. " 2>/dev/null")
	if vim.v.shell_error == 0 and result ~= "" then
		vim.notify(result:sub(1, 1000), vim.log.levels.INFO, { title = "npm info: " .. word })
	else
		vim.notify("Package not found: " .. word, vim.log.levels.INFO, { title = "TypeScript" })
	end
end, { desc = icons.diagnostics.Info .. " Package info" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers TypeScript-specific alignment presets for mini.align:
-- • ts_object — align object / type properties on ":"
-- • ts_assign — align assignments / default params on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("typescript") then
		---@type string Alignment preset icon from icons.app
		local ts_align_icon = icons.app.Typescript

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			ts_object = {
				description = "Align TS / JS object properties on ':'",
				icon = ts_align_icon,
				split_pattern = ":",
				category = "web",
				lang = "typescript",
				filetypes = { "typescript", "typescriptreact" },
			},
			ts_assign = {
				description = "Align TS / JS assignments on '='",
				icon = ts_align_icon,
				split_pattern = "=",
				category = "web",
				lang = "typescript",
				filetypes = { "typescript", "typescriptreact" },
			},
		})

		-- ── Set default filetype mappings ────────────────────────────
		align_registry.set_ft_mapping("typescript", "ts_object")
		align_registry.set_ft_mapping("typescriptreact", "ts_object")
		align_registry.mark_language_loaded("typescript")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map(ts_ft, { "n", "x" }, "<leader>aL", align_registry.make_align_fn("ts_object"), {
			desc = ts_align_icon .. "  Align TS object",
		})
		keys.lang_map(ts_ft, { "n", "x" }, "<leader>aT", align_registry.make_align_fn("ts_assign"), {
			desc = ts_align_icon .. "  Align TS assign",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the TypeScript-specific
-- parts (servers, formatters, linters, parsers, adapters).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for TypeScript              │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (vtsls server added on require)   │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.typescript)     │
-- │ nvim-lint          │ opts merge (linters_by_ft.typescript)        │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- │ mason-nvim-dap     │ opts merge (js adapter in ensure_installed)  │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for TypeScript
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- vtsls: fast TypeScript language server (volar-compatible architecture)
	-- Provides completions, diagnostics, inlay hints, code actions,
	-- go-to-definition, and automatic import management.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				vtsls = {
					filetypes = { "typescript", "typescriptreact", "typescript.tsx" },
					settings = {
						typescript = {
							updateImportsOnFileMove = { enabled = "always" },
							suggest = { completeFunctionCalls = true },
							inlayHints = {
								parameterNames = { enabled = "all" },
								parameterTypes = { enabled = true },
								variableTypes = { enabled = true },
								propertyDeclarationTypes = { enabled = true },
								functionLikeReturnTypes = { enabled = true },
								enumMemberValues = { enabled = true },
							},
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					ts = "typescript",
					tsx = "typescriptreact",
					mts = "typescript",
					cts = "typescript",
				},
			})

			-- ── Buffer-local options for TypeScript files ────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "typescript", "typescriptreact" },
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
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures vtsls, prettier, eslint_d, and js-debug-adapter are
	-- installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"vtsls",
				"prettier",
				"eslint_d",
				"js-debug-adapter",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- Prettier: opinionated code formatter for TypeScript / TSX.
	-- Respects project-local .prettierrc / prettier.config.js.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				typescript = { "prettier" },
				typescriptreact = { "prettier" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- eslint_d: daemonized ESLint for near-instant linting feedback.
	-- Respects project-local .eslintrc / eslint.config.js (flat config).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				typescript = { "eslint_d" },
				typescriptreact = { "eslint_d" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- typescript: syntax highlighting, folding, text objects
	-- tsx:        JSX / TSX embedded syntax support
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"typescript",
				"tsx",
			},
		},
	},

	-- ── DAP — JAVASCRIPT / TYPESCRIPT DEBUGGER ─────────────────────────────
	-- mason-nvim-dap auto-configures the js-debug-adapter (vscode-js-debug):
	--   • dap.adapters["pwa-node"]   → Node.js debugging
	--   • dap.adapters["pwa-chrome"] → Chrome DevTools Protocol
	--
	-- After loading, ALL core DAP keymaps work in TypeScript files:
	--   <leader>dc, <leader>db, <leader>di, <leader>do, F5, F9, etc.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "js" },
		},
	},
}
