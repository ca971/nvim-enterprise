---@file lua/langs/javascript.lua
---@description JavaScript — LSP, formatter, linter, treesitter, DAP & buffer-local keymaps
---@module "langs.javascript"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.typescript         TypeScript language support (shared vtsls LSP)
---@see langs.python             Python language support (same architecture)
---@see langs.java               Java language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/javascript.lua — JavaScript language support                      ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("javascript") → {} if off   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "javascript"):               │    ║
--- ║  │  ├─ LSP          vtsls  (TypeScript/JavaScript language server)  │    ║
--- ║  │  │               Fast completions, imports, inlay hints          │    ║
--- ║  │  ├─ Formatter    prettier (conform.nvim)                         │    ║
--- ║  │  ├─ Linter       eslint_d (nvim-lint)                            │    ║
--- ║  │  ├─ Treesitter   javascript · jsdoc · jsx parsers                │    ║
--- ║  │  ├─ DAP          js-debug-adapter (Chrome/Node debugging)        │    ║
--- ║  │  └─ Runtime      node / bun (auto-detected)                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file (node/bun)  R  Run with arguments      │    ║
--- ║  │  │            e  Execute line/selection                          │    ║
--- ║  │  ├─ TEST      t  Run tests            T  Test current file       │    ║
--- ║  │  ├─ DEBUG     d  Debug (DAP)                                     │    ║
--- ║  │  ├─ REPL      c  Node/Bun REPL                                   │    ║
--- ║  │  ├─ TOOLS     x  ESLint fix           o  Organize imports        │    ║
--- ║  │  │            s  Switch test ↔ source                            │    ║
--- ║  │  ├─ DOCS      h  MDN docs             i  Package info            │    ║
--- ║  │  └─ PKG       m  → Package manager sub-group                     │    ║
--- ║  │                 mi  Install            mu  Update                │    ║
--- ║  │                 ma  Add package         md  Dev dependency       │    ║
--- ║  │                 mr  Run script          ms  Script picker        │    ║
--- ║  │                                                                  │    ║
--- ║  │  DAP integration flow:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. js-debug-adapter installed via Mason                 │    │    ║
--- ║  │  │  2. mason-nvim-dap auto-configures dap.adapters.js       │    │    ║
--- ║  │  │  3. dap.continue() launches Node.js / Chrome debugger    │    │    ║
--- ║  │  │  4. Supports:                                            │    │    ║
--- ║  │  │     • Node.js launch + attach                            │    │    ║
--- ║  │  │     • Chrome DevTools Protocol                           │    │    ║
--- ║  │  │     • Source map support                                 │    │    ║
--- ║  │  │  5. All core DAP keymaps become active:                  │    │    ║
--- ║  │  │     <leader>dc · <leader>db · F5 · F9 · etc.             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType javascript/javascriptreact):        ║
--- ║  • colorcolumn=100               (common JS style guides)                ║
--- ║  • tabstop=2, shiftwidth=2       (JS/React community standard)           ║
--- ║  • expandtab=true                (spaces, never tabs)                    ║
--- ║  • Treesitter folding            (foldmethod=expr, foldlevel=99)         ║
--- ║                                                                          ║
--- ║  Package manager detection:                                              ║
--- ║  • bun.lockb         → bun                                               ║
--- ║  • pnpm-lock.yaml    → pnpm                                              ║
--- ║  • yarn.lock         → yarn                                              ║
--- ║  • (fallback)        → npm                                               ║
--- ║                                                                          ║
--- ║  Runtime detection:                                                      ║
--- ║  • bun (preferred if available — faster startup)                         ║
--- ║  • node (fallback — universally available)                               ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .js, .mjs, .cjs   → javascript                                        ║
--- ║  • .jsx               → javascriptreact                                  ║
--- ║  • .npmrc             → dosini                                           ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if JavaScript support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("javascript") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string JavaScript Nerd Font icon (trailing whitespace stripped)
local js_icon = icons.lang.javascript:gsub("%s+$", "")

---@type string[] Filetypes that this module applies to
local js_ft = { "javascript", "javascriptreact" }

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUPS
--
-- Registers the <leader>l group label for JavaScript buffers.
-- Both `javascript` and `javascriptreact` get the same group label
-- since JSX is a superset of JavaScript.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("javascript", "JavaScript", js_icon)
keys.lang_group("javascriptreact", "JavaScript", js_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Runtime detection, package manager resolution, and test runner
-- identification. All functions are module-local and not exposed
-- to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the best available JavaScript runtime.
---
--- Resolution order:
--- 1. `bun`  — preferred for its faster startup and native TS support
--- 2. `node` — universal fallback
---
--- ```lua
--- local runner = get_runner()   --> "bun" or "node"
--- ```
---
---@return string runner Runtime executable name (`"bun"` or `"node"`)
---@private
local function get_runner()
	if vim.fn.executable("bun") == 1 then return "bun" end
	return "node"
end

--- Detect the package manager used by the current project.
---
--- Resolution order (by lockfile):
--- 1. `bun.lockb`        → `"bun"`
--- 2. `pnpm-lock.yaml`   → `"pnpm"`
--- 3. `yarn.lock`         → `"yarn"`
--- 4. (fallback)          → `"npm"`
---
--- ```lua
--- local pm = get_pm()
--- vim.cmd.terminal(pm .. " install")
--- ```
---
---@return "bun"|"pnpm"|"yarn"|"npm" pm Package manager command name
---@private
local function get_pm()
	if vim.fn.filereadable("bun.lockb") == 1 then return "bun" end
	if vim.fn.filereadable("pnpm-lock.yaml") == 1 then return "pnpm" end
	if vim.fn.filereadable("yarn.lock") == 1 then return "yarn" end
	return "npm"
end

--- Detect the test runner from project configuration files.
---
--- Resolution order:
--- 1. `vitest.config.ts` / `vitest.config.js` → `"vitest run"`
--- 2. `jest.config.js` / `.ts` / `.mjs`       → `"jest"`
--- 3. (fallback)                               → `<pm> test`
---
--- ```lua
--- local cmd = get_test_cmd()   --> "vitest run" | "jest" | "npm test"
--- ```
---
---@return string cmd Test runner command string
---@private
local function get_test_cmd()
	if vim.fn.filereadable("vitest.config.ts") == 1 or vim.fn.filereadable("vitest.config.js") == 1 then
		return "vitest run"
	end

	if
		vim.fn.filereadable("jest.config.js") == 1
		or vim.fn.filereadable("jest.config.ts") == 1
		or vim.fn.filereadable("jest.config.mjs") == 1
	then
		return "jest"
	end

	local pm = get_pm()
	return pm .. " test"
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- File execution and line/selection evaluation.
-- Auto-detects bun vs node for optimal performance.
-- All keymaps open a terminal split for output.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current JavaScript file in a terminal split.
---
--- Saves the buffer before execution. Prefers `bun` over `node`
--- for its faster startup time and built-in TypeScript support.
keys.lang_map(js_ft, "n", "<leader>lr", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local runner = get_runner()
	vim.cmd.split()
	vim.cmd.terminal(runner .. " " .. vim.fn.shellescape(file))
end, { desc = icons.ui.Play .. " Run file" })

--- Run the current JavaScript file with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then executes in a
--- terminal split. Aborts silently if the user cancels the prompt.
keys.lang_map(js_ft, "n", "<leader>lR", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local runner = get_runner()
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal(runner .. " " .. vim.fn.shellescape(file) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Execute the current line as a JavaScript one-liner.
---
--- Strips leading whitespace before passing to `node -e`.
--- Skips silently if the line is empty.
keys.lang_map(js_ft, "n", "<leader>le", function()
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	if line == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("node -e " .. vim.fn.shellescape(line))
end, { desc = js_icon .. " Execute current line" })

--- Execute the visual selection as JavaScript code.
---
--- Yanks the selection into register `z`, then passes it to
--- `node -e` in a terminal split.
keys.lang_map(js_ft, "v", "<leader>le", function()
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("node -e " .. vim.fn.shellescape(code))
end, { desc = js_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via auto-detected test runner (vitest, jest, or
-- package manager fallback). Supports both full-suite and
-- single-file testing.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite via the package manager.
---
--- Delegates to `<pm> test` (or `npm run test` for npm).
--- The test runner itself (jest, vitest, etc.) is determined by
--- the project's package.json `test` script.
keys.lang_map(js_ft, "n", "<leader>lt", function()
	vim.cmd("silent! write")
	local pm = get_pm()
	vim.cmd.split()
	vim.cmd.terminal(pm .. " " .. (pm == "npm" and "run " or "") .. "test")
end, { desc = icons.dev.Test .. " Run tests" })

--- Run tests for the current file only.
---
--- Uses `get_test_cmd()` to detect the test runner, then passes
--- the current file path as an argument for targeted testing.
keys.lang_map(js_ft, "n", "<leader>lT", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local test_cmd = get_test_cmd()
	vim.cmd.split()
	vim.cmd.terminal(test_cmd .. " " .. vim.fn.shellescape(file))
end, { desc = icons.dev.Test .. " Test file" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via js-debug-adapter (Microsoft's VS Code debugger).
--
-- <leader>ld starts or continues a debug session. The adapter is
-- auto-configured by mason-nvim-dap and supports:
--   • Node.js launch and attach
--   • Chrome DevTools Protocol
--   • Source map resolution
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Saves the buffer, then calls `dap.continue()` which either resumes
--- a paused session or launches a new one using the JS adapter.
keys.lang_map(js_ft, "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "JavaScript" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (DAP)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
--
-- Opens an interactive JavaScript REPL in a terminal split.
-- Prefers Bun REPL when available for its faster startup and
-- built-in TypeScript support.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a JavaScript REPL in a terminal split.
---
--- Prefers `bun repl` if bun is available (faster, supports TS natively).
--- Falls back to `node` (standard Node.js REPL).
keys.lang_map(js_ft, "n", "<leader>lc", function()
	local runner = get_runner()
	---@type string
	local cmd = runner == "bun" and "bun repl" or "node"
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Terminal .. " REPL" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Development utilities: ESLint auto-fix, import organization,
-- and test ↔ source file switching.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run ESLint auto-fix on the current file.
---
--- Resolution order:
--- 1. `eslint_d` — daemon mode (instant, no cold-start penalty)
--- 2. `eslint`   — standard ESLint CLI
--- 3. Neither    — notification with install instructions
---
--- After fixing, reloads the buffer to reflect changes.
keys.lang_map(js_ft, "n", "<leader>lx", function()
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))

	if vim.fn.executable("eslint_d") == 1 then
		vim.fn.system("eslint_d --fix " .. file)
		vim.cmd.edit()
		vim.notify("ESLint fixed", vim.log.levels.INFO, { title = "JavaScript" })
	elseif vim.fn.executable("eslint") == 1 then
		vim.fn.system("eslint --fix " .. file)
		vim.cmd.edit()
		vim.notify("ESLint fixed", vim.log.levels.INFO, { title = "JavaScript" })
	else
		vim.notify("Install eslint_d: npm i -g eslint_d", vim.log.levels.WARN, { title = "JavaScript" })
	end
end, { desc = js_icon .. " ESLint fix" })

--- Organize imports via LSP code action.
---
--- Sends a `textDocument/codeAction` request filtered to
--- `source.organizeImports` only. Applies all resulting workspace
--- edits synchronously (3s timeout).
---
--- Works with any LSP that supports the `source.organizeImports`
--- code action kind (vtsls, eslint, etc.).
keys.lang_map(js_ft, "n", "<leader>lo", function()
	local params = vim.lsp.util.make_range_params()
	params.context = { only = { "source.organizeImports" } }

	local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 3000)
	if not result then return end

	for _, res in pairs(result) do
		for _, r in pairs(res.result or {}) do
			if r.edit then vim.lsp.util.apply_workspace_edit(r.edit, "utf-16") end
		end
	end
end, { desc = js_icon .. " Organize imports" })

--- Switch between test and source files.
---
--- Follows common JavaScript testing conventions:
--- - `foo.js` ↔ `foo.test.js` / `foo.spec.js`
--- - `foo.jsx` ↔ `foo.test.jsx` / `foo.spec.jsx`
--- - `__tests__/foo.js` ↔ `foo.js`
---
--- Handles both directions:
--- - From source → tries `.test.ext` first, then `.spec.ext`
--- - From test   → strips `.test`/`.spec` suffix, removes `__tests__/`
---
--- Notifies if the target file does not exist.
keys.lang_map(js_ft, "n", "<leader>ls", function()
	local file = vim.fn.expand("%:p")

	---@type string
	local target
	if file:match("%.test%.") or file:match("%.spec%.") then
		-- ── From test → source ───────────────────────────────────────
		target = file:gsub("%.test(%.[jt]sx?)$", "%1"):gsub("%.spec(%.[jt]sx?)$", "%1")
		target = target:gsub("__tests__/", "")
	else
		-- ── From source → test ───────────────────────────────────────
		local ext = vim.fn.expand("%:e")
		local base = vim.fn.expand("%:p:r")
		target = base .. ".test." .. ext
		if vim.fn.filereadable(target) ~= 1 then target = base .. ".spec." .. ext end
	end

	if vim.fn.filereadable(target) == 1 then
		vim.cmd.edit(target)
	else
		vim.notify("No matching file found", vim.log.levels.INFO, { title = "JavaScript" })
	end
end, { desc = js_icon .. " Switch test ↔ source" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to MDN Web Docs and npm/package manager metadata
-- without leaving the editor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open MDN Web Docs for the word under cursor.
---
--- Searches MDN for the identifier under the cursor (e.g. `Array`,
--- `Promise`, `fetch`). If the cursor is on an empty word, opens
--- the MDN JavaScript landing page.
keys.lang_map(js_ft, "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word ~= "" then
		vim.ui.open("https://developer.mozilla.org/en-US/search?q=" .. word)
	else
		vim.ui.open("https://developer.mozilla.org/en-US/docs/Web/JavaScript")
	end
end, { desc = icons.ui.Note .. " MDN docs" })

--- Show package info for the word under cursor.
---
--- Runs `<pm> info <word>` and displays the result (name, version,
--- description, dependencies) in a notification. Truncates output
--- to 1000 characters to avoid flooding the notification area.
keys.lang_map(js_ft, "n", "<leader>li", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then return end

	local pm = get_pm()
	---@type string
	local cmd = pm == "npm" and ("npm info " .. word) or (pm .. " info " .. word)
	local result = vim.fn.system(cmd .. " 2>/dev/null")

	if vim.v.shell_error == 0 and result ~= "" then
		vim.notify(result:sub(1, 1000), vim.log.levels.INFO, { title = pm .. " info: " .. word })
	else
		vim.notify("Package not found: " .. word, vim.log.levels.INFO, { title = "JavaScript" })
	end
end, { desc = icons.diagnostics.Info .. " Package info" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PACKAGE MANAGER SUB-GROUP
--
-- Dedicated sub-menu under <leader>lm for package management.
-- Auto-detects the package manager (npm/yarn/pnpm/bun) and
-- adapts commands accordingly.
--
-- The script picker reads package.json and presents all available
-- scripts via vim.ui.select() for fuzzy selection.
-- ═══════════════════════════════════════════════════════════════════════════

--- Register the package manager sub-group placeholder for which-key.
---
--- This no-op keymap exists solely to create a labeled group in
--- which-key's popup menu under `<leader>lm`.
keys.lang_map(js_ft, "n", "<leader>lm", function() end, {
	desc = icons.ui.Package .. " Package manager",
})

--- Install all project dependencies.
---
--- Runs `<pm> install` in a terminal split. Equivalent to:
--- - npm: `npm install`
--- - yarn: `yarn install`
--- - pnpm: `pnpm install`
--- - bun: `bun install`
keys.lang_map(js_ft, "n", "<leader>lmi", function()
	local pm = get_pm()
	vim.cmd.split()
	vim.cmd.terminal(pm .. " install")
end, { desc = icons.ui.Package .. " Install" })

--- Update all project dependencies.
---
--- Runs `<pm> update` in a terminal split.
keys.lang_map(js_ft, "n", "<leader>lmu", function()
	local pm = get_pm()
	vim.cmd.split()
	vim.cmd.terminal(pm .. " update")
end, { desc = icons.ui.Refresh .. " Update" })

--- Add a new production dependency.
---
--- Prompts for the package name, then runs the appropriate install
--- command for the detected package manager:
--- - npm: `npm install <pkg>`
--- - yarn/pnpm/bun: `<pm> add <pkg>`
---
--- Aborts silently if the user cancels the prompt or enters empty input.
keys.lang_map(js_ft, "n", "<leader>lma", function()
	local pm = get_pm()
	vim.ui.input({ prompt = "Package: " }, function(pkg)
		if not pkg or pkg == "" then return end
		---@type string
		local cmd = pm == "npm" and ("npm install " .. pkg) or (pm .. " add " .. pkg)
		vim.cmd.split()
		vim.cmd.terminal(cmd)
	end)
end, { desc = icons.ui.Plus .. " Add package" })

--- Add a new dev dependency.
---
--- Prompts for the package name, then runs the appropriate install
--- command with the `-D` (devDependencies) flag:
--- - npm: `npm install -D <pkg>`
--- - yarn/pnpm/bun: `<pm> add -D <pkg>`
---
--- Aborts silently if the user cancels the prompt or enters empty input.
keys.lang_map(js_ft, "n", "<leader>lmd", function()
	local pm = get_pm()
	vim.ui.input({ prompt = "Dev package: " }, function(pkg)
		if not pkg or pkg == "" then return end
		---@type string
		local cmd
		if pm == "npm" then
			cmd = "npm install -D " .. pkg
		else
			cmd = pm .. " add -D " .. pkg
		end
		vim.cmd.split()
		vim.cmd.terminal(cmd)
	end)
end, { desc = icons.ui.Plus .. " Dev dependency" })

--- Pick and run a script from package.json.
---
--- Reads `package.json`, extracts the `scripts` object, sorts the
--- keys alphabetically, and presents them via `vim.ui.select()`.
--- On selection, runs the script in a terminal split using the
--- detected package manager.
---
--- Notifies if package.json is missing or contains no scripts.
keys.lang_map(js_ft, "n", "<leader>lms", function()
	local pkg_json = vim.fn.readfile("package.json")
	if #pkg_json == 0 then
		vim.notify("No package.json found", vim.log.levels.WARN, { title = "JavaScript" })
		return
	end

	local ok, data = pcall(vim.json.decode, table.concat(pkg_json, "\n"))
	if not ok or not data.scripts then
		vim.notify("No scripts in package.json", vim.log.levels.INFO, { title = "JavaScript" })
		return
	end

	---@type string[]
	local scripts = vim.tbl_keys(data.scripts)
	table.sort(scripts)

	local pm = get_pm()
	vim.ui.select(scripts, { prompt = js_icon .. " Run script:" }, function(script)
		if not script then return end
		---@type string
		local cmd = pm == "npm" and ("npm run " .. script) or (pm .. " " .. script)
		vim.cmd.split()
		vim.cmd.terminal(cmd)
	end)
end, { desc = icons.ui.Play .. " Script picker" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers JavaScript-specific alignment presets for mini.align:
-- • js_object — align object properties on ":"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("javascript") then
		---@type string Alignment preset icon from icons.app
		local js_align_icon = icons.app.Javascript

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			js_object = {
				description = "Align JS object properties on ':'",
				icon = js_align_icon,
				split_pattern = ":",
				category = "web",
				lang = "javascript",
				filetypes = { "javascript", "javascriptreact" },
			},
		})

		-- ── Set default filetype mappings ────────────────────────────
		align_registry.set_ft_mapping("javascript", "js_object")
		align_registry.set_ft_mapping("javascriptreact", "js_object")
		align_registry.mark_language_loaded("javascript")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map(js_ft, { "n", "x" }, "<leader>aL", align_registry.make_align_fn("js_object"), {
			desc = js_align_icon .. "  Align JS object",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the JavaScript-specific
-- parts (servers, formatters, linters, parsers, adapters).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for JavaScript             │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (vtsls server added on require)   │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.javascript)     │
-- │ nvim-lint          │ opts merge (linters_by_ft.javascript)        │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- │ mason-nvim-dap     │ opts merge (js adapter added)                │
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: vtsls serves both JavaScript and TypeScript. If both languages
-- are enabled, the server is shared — no duplicate instances.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for JavaScript
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- vtsls: fast TypeScript/JavaScript language server (alternative to
	-- tsserver). Provides completions, diagnostics, code actions, inlay
	-- hints, and auto-import management.
	--
	-- Configured for JavaScript-specific filetypes here. If TypeScript
	-- is also enabled, the server instance is shared automatically.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				vtsls = {
					filetypes = { "javascript", "javascriptreact", "javascript.jsx" },
					settings = {
						javascript = {
							updateImportsOnFileMove = { enabled = "always" },
							suggest = { completeFunctionCalls = true },
							inlayHints = {
								parameterNames = { enabled = "literals" },
								variableTypes = { enabled = true },
								functionLikeReturnTypes = { enabled = true },
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
					js = "javascript",
					mjs = "javascript",
					cjs = "javascript",
					jsx = "javascriptreact",
				},
				filename = {
					[".npmrc"] = "dosini",
				},
			})

			-- ── Buffer-local options for JavaScript files ────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "javascript", "javascriptreact" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "100"
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
	-- Ensures all JavaScript tooling is installed via Mason:
	--   • vtsls             — TypeScript/JavaScript LSP server
	--   • prettier          — opinionated code formatter
	--   • eslint_d          — ESLint daemon (instant linting)
	--   • js-debug-adapter  — DAP adapter for Node.js/Chrome debugging
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
	-- prettier: opinionated code formatter supporting JS, JSX, JSON,
	-- CSS, HTML, and many more formats. The de-facto standard in the
	-- JavaScript ecosystem.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				javascript = { "prettier" },
				javascriptreact = { "prettier" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- eslint_d: ESLint running as a daemon process. Eliminates the cold-
	-- start penalty of ESLint by keeping a persistent process that handles
	-- all lint requests. 10-20x faster than spawning eslint per file.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				javascript = { "eslint_d" },
				javascriptreact = { "eslint_d" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- javascript: syntax highlighting, folding, text objects, indentation
	-- jsdoc:      JSDoc comment highlighting and structure
	-- jsx:        JSX/React template syntax support (embedded HTML in JS)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"javascript",
				"jsdoc",
				"jsx",
			},
		},
	},

	-- ── DAP (JavaScript debugger) ──────────────────────────────────────────
	-- js-debug-adapter: Microsoft's VS Code JavaScript debugger.
	-- Supports Node.js launch/attach and Chrome DevTools Protocol.
	-- Auto-configured by mason-nvim-dap on first use.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "js" },
		},
	},
	{
		"nvim-neotest/neotest",
		optional = true,
		dependencies = {
			{ "marilari88/neotest-vitest", lazy = true },
		},
		opts = function(_, opts)
			opts.adapters = opts.adapters or {}
			-- Guard duplicate (JS + TS both add vitest)
			for _, adapter in ipairs(opts.adapters) do
				if type(adapter) == "table" and adapter.name == "neotest-vitest" then return end
			end
			table.insert(opts.adapters, require("neotest-vitest"))
		end,
	},
}
