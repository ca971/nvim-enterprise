---@file lua/langs/lua.lua
---@description Lua — LSP (lua_ls), formatter, linter, DAP, treesitter & buffer-local keymaps
---@module "langs.lua"
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
---@see langs.rust               Rust language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/lua.lua — Lua language support                                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("lua") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "lua"):                      │    ║
--- ║  │  ├─ LSP          lua_ls  (sumneko Lua Language Server)           │    ║
--- ║  │  │               + lazydev.nvim for Neovim API types             │    ║
--- ║  │  │               + luvit-meta for vim.uv type annotations        │    ║
--- ║  │  ├─ Formatter    stylua (conform.nvim)                           │    ║
--- ║  │  ├─ Linter       selene (nvim-lint)                              │    ║
--- ║  │  ├─ Treesitter   lua · luadoc · luap parsers                     │    ║
--- ║  │  ├─ DAP          one-small-step-for-vimkind (Neovim Lua debug)   │    ║
--- ║  │  └─ Extras       lazydev.nvim (Neovim-specific completions)      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file (luajit/lua)  R  Source in Neovim      │    ║
--- ║  │  │            e  Execute line/selection (in-process eval)        │    ║
--- ║  │  ├─ TEST      t  Run tests (plenary/busted/mini.test)            │    ║
--- ║  │  ├─ DEBUG     d  Debug (DAP / one-small-step-for-vimkind)        │    ║
--- ║  │  ├─ REPL      c  Interactive REPL (luajit/lua/nvim fallback)     │    ║
--- ║  │  ├─ INSPECT   i  vim.inspect() cursor/selection                  │    ║
--- ║  │  ├─ MODULE    x  Reload module          p  Clear module cache    │    ║
--- ║  │  └─ DOCS      h  Help for word          s  Lua/Neovim docs       │    ║
--- ║  │               a  Neovim API docs (context-aware)                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  lua_ls workspace.library resolution:                            │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  $VIMRUNTIME/lua          (Neovim runtime Lua files)     │    │    ║
--- ║  │  │  $VIMRUNTIME/lua/vim      (vim.* namespace)              │    │    ║
--- ║  │  │  $VIMRUNTIME/lua/vim/lsp  (vim.lsp.* namespace)          │    │    ║
--- ║  │  │  stdpath("config")/lua    (user config files)            │    │    ║
--- ║  │  │  stdpath("data")/lazy     (plugin sources, for types)    │    │    ║
--- ║  │  │  lazydev.nvim             (dynamic: vim.uv, LazySpec)    │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  DAP integration flow:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. one-small-step-for-vimkind loads on ft = "lua"       │    │    ║
--- ║  │  │  2. Registers dap.adapters.nlua (server on 127.0.0.1)    │    │    ║
--- ║  │  │  3. dap.configurations.lua → attach to running Neovim    │    │    ║
--- ║  │  │  4. Debug Neovim Lua code with breakpoints + stepping    │    │    ║
--- ║  │  │  5. All core DAP keymaps become active:                  │    │    ║
--- ║  │  │     <leader>dc · <leader>db · F5 · F9 · etc.             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType lua):                               ║
--- ║  • colorcolumn=120, textwidth=120   (stylua default line width)          ║
--- ║  • tabstop=2, shiftwidth=2          (match stylua indent_width)          ║
--- ║  • expandtab=false                  (tabs, matching stylua defaults)     ║
--- ║  • Treesitter folding               (foldmethod=expr, foldlevel=99)      ║
--- ║                                                                          ║
--- ║  Test runner detection (priority order):                                 ║
--- ║  1. plenary.nvim  — for *_spec.lua / *_test.lua files                    ║
--- ║  2. busted         — standalone Lua test framework                       ║
--- ║  3. mini.test      — mini.nvim test runner                               ║
--- ║                                                                          ║
--- ║  Module reload:                                                          ║
--- ║  • <leader>lx clears package.loaded[module] + re-requires                ║
--- ║  • <leader>lp clears ALL user modules (core.*, plugins.*, langs.*)       ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Lua support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("lua") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Lua Nerd Font icon (trailing whitespace stripped)
local lua_icon = icons.lang.lua:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Lua buffers.
-- The group is buffer-local and only visible when filetype == "lua".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("lua", "Lua", lua_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Lua interpreter detection, module name resolution, and in-process
-- Lua code evaluation. All functions are module-local and not
-- exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the best available Lua interpreter.
---
--- Prefers LuaJIT (the runtime used by Neovim) over standard Lua
--- for maximum compatibility with Neovim-targeted code.
---
--- ```lua
--- local lua = get_lua()
--- if lua then vim.cmd.terminal(lua .. " script.lua") end
--- ```
---
---@return string|nil interpreter Executable name (`"luajit"` or `"lua"`), or `nil` if none found
---@private
local function get_lua()
	if vim.fn.executable("luajit") == 1 then return "luajit" end
	if vim.fn.executable("lua") == 1 then return "lua" end
	return nil
end

--- Detect the Lua module name from the current file path.
---
--- Searches Neovim runtime paths and CWD for a `lua/` directory,
--- then converts the relative path to a dot-separated module name.
--- Strips `init.lua` suffixes for package-style modules.
---
--- ```lua
--- -- With file: ~/.config/nvim/lua/core/utils.lua
--- get_module_name()   --> "core.utils"
---
--- -- With file: ~/.config/nvim/lua/plugins/init.lua
--- get_module_name()   --> "plugins"
--- ```
---
---@return string|nil module_name Dot-separated module name, or `nil` if undetectable
---@private
local function get_module_name()
	local file = vim.fn.expand("%:p")

	-- ── Search in all Lua package paths ──────────────────────────
	for _, dir in ipairs(vim.api.nvim_list_runtime_paths()) do
		local lua_dir = dir .. "/lua/"
		if file:sub(1, #lua_dir) == lua_dir then
			local module = file:sub(#lua_dir + 1):gsub("%.lua$", ""):gsub("/", ".")
			return (module:gsub("%.init$", ""))
		end
	end

	-- ── Fallback: try relative to cwd ────────────────────────────
	local cwd_lua = vim.fn.getcwd() .. "/lua/"
	if file:sub(1, #cwd_lua) == cwd_lua then
		local module = file:sub(#cwd_lua + 1):gsub("%.lua$", ""):gsub("/", ".")
		return (module:gsub("%.init$", ""))
	end

	return nil
end

--- Evaluate a Lua code string in the running Neovim instance.
---
--- Compiles the code via `loadstring()`, executes it with `pcall()`,
--- and displays the result (or error) via `vim.notify()`. Tries
--- `return <code>` first so expressions produce visible output,
--- then falls back to raw execution for statements.
---
--- For large outputs (> 5 lines), opens a scratch float window
--- instead of a notification to avoid flooding.
---
--- ```lua
--- eval_lua("vim.fn.getcwd()")          --> notification with CWD path
--- eval_lua("print('hello')")           --> "OK (no return value)"
--- eval_lua("invalid syntax !!!")       --> syntax error notification
--- ```
---
---@param code string Lua source code to evaluate
---@param title? string Notification title prefix (default: `"Lua"`)
---@return nil
---@private
local function eval_lua(code, title)
	title = title or "Lua"
	if code == "" then
		vim.notify("Empty input", vim.log.levels.INFO, { title = title })
		return
	end

	-- Try as expression first ("return <code>"), then as statement
	local chunk, compile_err = loadstring("return " .. code)
	if not chunk then
		chunk, compile_err = loadstring(code)
	end

	if not chunk then
		vim.notify("Syntax error:\n" .. tostring(compile_err), vim.log.levels.ERROR, { title = title })
		return
	end

	local ok, result = pcall(chunk)
	if not ok then
		vim.notify("Runtime error:\n" .. tostring(result), vim.log.levels.ERROR, { title = title })
		return
	end

	if result == nil then
		vim.notify("OK (no return value)", vim.log.levels.INFO, { title = title })
		return
	end

	local inspected = vim.inspect(result)
	local lines = vim.split(inspected, "\n")

	if #lines > 5 then
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
		vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })
		vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
		local width = math.min(80, vim.o.columns - 4)
		local height = math.min(#lines, vim.o.lines - 6)
		vim.api.nvim_open_win(buf, true, {
			relative = "cursor",
			row = 1,
			col = 0,
			width = width,
			height = height,
			style = "minimal",
			border = "rounded",
			title = " " .. lua_icon .. " result ",
			title_pos = "center",
		})
	else
		vim.notify(inspected, vim.log.levels.INFO, { title = title })
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN & SOURCE
--
-- File execution via external interpreter (luajit/lua) and
-- in-process sourcing within the running Neovim instance.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current file with the detected Lua interpreter.
---
--- Saves the buffer before execution. Prefers `luajit` over `lua`
--- for compatibility with Neovim-targeted code.
keys.lang_map("lua", "n", "<leader>lr", function()
	local lua = get_lua()
	if not lua then
		vim.notify("No Lua interpreter found (luajit, lua)", vim.log.levels.ERROR, { title = "Lua" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal(lua .. " " .. vim.fn.shellescape(file))
end, { desc = icons.ui.Play .. " Run file" })

--- Source the current file in the running Neovim instance.
---
--- Executes `:source %` which loads the file into the current
--- Neovim Lua state. Useful for reloading config modules without
--- restarting Neovim.
keys.lang_map("lua", "n", "<leader>lR", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local ok, err = pcall(vim.cmd.source, file)
	if ok then
		vim.notify("Sourced: " .. vim.fn.expand("%:t"), vim.log.levels.INFO, { title = "Lua" })
	else
		vim.notify("Source error:\n" .. tostring(err), vim.log.levels.ERROR, { title = "Lua" })
	end
end, { desc = lua_icon .. " Source in Neovim" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EXECUTE
--
-- In-process Lua code evaluation via loadstring() + pcall().
-- Code runs in the current Neovim Lua state with full access to
-- vim.*, require(), and all loaded modules.
-- ═══════════════════════════════════════════════════════════════════════════

--- Execute the current line as Lua code in Neovim.
---
--- Strips leading whitespace, evaluates via `eval_lua()`, and
--- displays the result (or error) in a notification.
keys.lang_map("lua", "n", "<leader>le", function()
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	eval_lua(line, "Lua")
end, { desc = lua_icon .. " Execute current line" })

--- Execute the visual selection as Lua code in Neovim.
---
--- Yanks the selection into register `z`, then evaluates the
--- code via `eval_lua()`. Supports multi-line selections.
keys.lang_map("lua", "v", "<leader>le", function()
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code ~= "" then eval_lua(code, "Lua") end
end, { desc = lua_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INSPECT
--
-- vim.inspect() integration for exploring Lua values interactively.
-- Supports both cursor-word and visual-selection evaluation.
-- Large outputs open in a floating scratch window instead of
-- a notification to avoid truncation.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show `vim.inspect()` of the expression under cursor.
---
--- Evaluates the `<cWORD>` under the cursor as a Lua expression
--- and displays the inspected result. For large outputs (> 5 lines),
--- opens a floating scratch window with Lua syntax highlighting.
keys.lang_map("lua", "n", "<leader>li", function()
	local word = vim.fn.expand("<cWORD>")
	if word == "" then
		vim.notify("No expression under cursor", vim.log.levels.INFO, { title = "Lua" })
		return
	end
	eval_lua(word, "Lua: " .. word:sub(1, 40))
end, { desc = icons.diagnostics.Info .. " Inspect under cursor" })

--- Show `vim.inspect()` of the visual selection.
---
--- Yanks the selection, evaluates it as a Lua expression, and
--- displays the inspected result in a notification.
keys.lang_map("lua", "v", "<leader>li", function()
	vim.cmd('noautocmd normal! "zy')
	local expr = vim.fn.getreg("z")
	if expr ~= "" then eval_lua(expr, "Lua: inspect") end
end, { desc = icons.diagnostics.Info .. " Inspect selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — MODULE MANAGEMENT
--
-- Utilities for managing Lua's module cache (package.loaded).
-- Essential for Neovim config development where modules need
-- to be reloaded without restarting the editor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Reload the Lua module corresponding to the current file.
---
--- Determines the module name from the file path (via `get_module_name()`),
--- clears it from `package.loaded`, and re-requires it. Notifies on
--- success, failure, or if the module was not cached.
keys.lang_map("lua", "n", "<leader>lx", function()
	local module = get_module_name()
	if not module then
		vim.notify("Cannot determine module name from file path", vim.log.levels.WARN, { title = "Lua" })
		return
	end

	if not package.loaded[module] then
		vim.notify("Module not cached: " .. module, vim.log.levels.INFO, { title = "Lua" })
		return
	end

	package.loaded[module] = nil
	local ok, err = pcall(require, module)
	if ok then
		vim.notify("Reloaded: " .. module, vim.log.levels.INFO, { title = "Lua" })
	else
		vim.notify("Reload failed:\n" .. tostring(err), vim.log.levels.ERROR, { title = "Lua" })
	end
end, { desc = icons.ui.Refresh .. " Reload module" })

--- Clear all user module cache.
---
--- Removes all modules matching `core.*`, `plugins.*`, `langs.*`,
--- and `config.*` from `package.loaded`. Displays a summary of
--- cleared module names sorted alphabetically.
---
--- Useful after editing multiple config files — forces all modules
--- to be re-loaded from disk on next `require()`.
keys.lang_map("lua", "n", "<leader>lp", function()
	---@type string[]
	local cleared = {}

	for name, _ in pairs(package.loaded) do
		if name:match("^core%.") or name:match("^plugins%.") or name:match("^langs%.") or name:match("^config%.") then
			package.loaded[name] = nil
			cleared[#cleared + 1] = name
		end
	end

	table.sort(cleared)

	if #cleared == 0 then
		vim.notify("No user modules in cache", vim.log.levels.INFO, { title = "Lua" })
	else
		local summary = string.format("Cleared %d module(s):\n  %s", #cleared, table.concat(cleared, "\n  "))
		vim.notify(summary, vim.log.levels.INFO, { title = "Lua" })
	end
end, { desc = icons.ui.Close .. " Clear module cache" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TESTING
--
-- Test execution with auto-detection of the test framework.
-- Supports three runners in priority order:
-- 1. plenary.nvim (for Neovim plugin tests with *_spec.lua files)
-- 2. busted (standalone Lua test framework)
-- 3. mini.test (mini.nvim test runner)
-- ═══════════════════════════════════════════════════════════════════════════

--- Run tests — auto-detects plenary, busted, or mini.test.
---
--- Detection strategy (first match wins):
--- 1. **plenary.nvim** — if the file ends in `_spec.lua` or `_test.lua`
---    and plenary is installed → `:PlenaryBustedFile`
--- 2. **busted** — if the `busted` binary is available → runs in terminal
---    (auto-discovers the corresponding spec file if needed)
--- 3. **mini.test** — if `mini.test` is loadable → `MiniTest.run_file()`
--- 4. **None found** → notification with install instructions
keys.lang_map("lua", "n", "<leader>lt", function()
	local file = vim.fn.expand("%:p")
	local filename = vim.fn.expand("%:t")

	-- ── 1. Plenary test harness ──────────────────────────────────
	if filename:match("_spec%.lua$") or filename:match("_test%.lua$") then
		local has_plenary = pcall(require, "plenary")
		if has_plenary then
			vim.cmd("PlenaryBustedFile " .. vim.fn.fnameescape(file))
			return
		end
	end

	-- ── 2. Busted ────────────────────────────────────────────────
	if vim.fn.executable("busted") == 1 then
		---@type string
		local test_file = file
		if not filename:match("_spec%.lua$") then
			local spec_file = vim.fn.expand("%:p:r") .. "_spec.lua"
			if vim.fn.filereadable(spec_file) == 1 then test_file = spec_file end
		end
		vim.cmd.split()
		vim.cmd.terminal("busted " .. vim.fn.shellescape(test_file))
		return
	end

	-- ── 3. Mini.test ─────────────────────────────────────────────
	local has_mini_test = pcall(require, "mini.test")
	if has_mini_test then
		require("mini.test").run_file(file)
		return
	end

	-- ── 4. Nothing found ─────────────────────────────────────────
	vim.notify(
		"No test runner found.\n"
			.. "Supported: plenary (*_spec.lua), busted, mini.test\n"
			.. "Install: luarocks install busted",
		vim.log.levels.WARN,
		{ title = "Lua" }
	)
end, { desc = icons.dev.Test .. " Run tests" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
--
-- Opens an interactive Lua REPL in a terminal split.
-- Falls back to launching a minimal Neovim instance with Lua
-- if no external interpreter is available.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open an interactive Lua REPL in a terminal split.
---
--- Prefers `luajit` or `lua` for a standard REPL experience.
--- Falls back to launching a clean Neovim instance with Lua
--- mode if no external interpreter is found.
keys.lang_map("lua", "n", "<leader>lc", function()
	local lua = get_lua()
	vim.cmd.split()
	if lua then
		vim.cmd.terminal(lua)
	else
		vim.cmd.terminal("nvim --clean -c 'lua vim.cmd(\"startinsert\")'")
	end
end, { desc = icons.ui.Terminal .. " REPL" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via one-small-step-for-vimkind.
--
-- <leader>ld starts or continues a debug session. The adapter
-- (nlua) attaches to the running Neovim instance, allowing
-- breakpoints and stepping through Lua code loaded by Neovim.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Uses the `nlua` adapter (one-small-step-for-vimkind) which
--- attaches to the running Neovim instance for debugging Lua
--- code in-process. Supports breakpoints, stepping, variable
--- inspection, and expression evaluation.
keys.lang_map("lua", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Lua" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (DAP)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Neovim help integration, Lua/Neovim documentation links, and
-- context-aware API reference lookup.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open Neovim `:help` for the word under cursor.
---
--- Tries multiple help tag patterns to maximize the chance of
--- finding relevant documentation:
--- 1. `vim.<word>` — vim namespace functions
--- 2. `<word>`     — direct match
--- 3. `lua-<word>` — Lua-specific help topics
--- 4. `api-<word>` — API documentation
--- 5. `nvim_<word>` — Neovim API functions
---
--- Notifies if no help tag matches any pattern.
keys.lang_map("lua", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then
		vim.notify("No word under cursor", vim.log.levels.INFO, { title = "Lua" })
		return
	end

	---@type string[]
	local patterns = {
		"vim." .. word,
		word,
		"lua-" .. word,
		"api-" .. word,
		"nvim_" .. word,
	}

	for _, pattern in ipairs(patterns) do
		local ok = pcall(vim.cmd.help, pattern)
		if ok then return end
	end

	vim.notify("No help found for: " .. word, vim.log.levels.INFO, { title = "Lua" })
end, { desc = icons.ui.Note .. " Help for word" })

--- Open Lua/Neovim documentation in the browser.
---
--- Presents a list of curated resources via `vim.ui.select()`:
--- 1. Lua 5.1 Reference Manual — the Lua version used by Neovim
--- 2. LuaJIT Documentation — JIT compiler documentation
--- 3. Neovim Lua Guide — official guide for Neovim Lua integration
--- 4. Neovim API Reference — complete C API bindings
--- 5. vim.* Functions — Lua-side vim namespace reference
---
--- Opens the selected URL in the system browser via `vim.ui.open()`.
keys.lang_map("lua", "n", "<leader>ls", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Lua 5.1 Reference Manual", url = "https://www.lua.org/manual/5.1/" },
		{ name = "LuaJIT Documentation", url = "https://luajit.org/luajit.html" },
		{ name = "Neovim Lua Guide", url = "https://neovim.io/doc/user/lua-guide.html" },
		{ name = "Neovim API Reference", url = "https://neovim.io/doc/user/api.html" },
		{ name = "vim.* Functions", url = "https://neovim.io/doc/user/lua.html" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = lua_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Lua/Neovim docs" })

--- Open Neovim API reference with context-aware detection.
---
--- Scans the current line for API call patterns:
--- - `vim.api.nvim_*` — C API bindings (e.g. `nvim_buf_set_lines`)
--- - `vim.fn.*`       — Vimscript function wrappers
--- - `vim.*`          — Lua-side vim namespace
---
--- If a pattern is found, opens the corresponding `:help` topic.
--- Falls back to the general `:help api` page.
keys.lang_map("lua", "n", "<leader>la", function()
	local line = vim.api.nvim_get_current_line()
	---@type string|nil
	local api_func = line:match("vim%.api%.(nvim_%w+)") or line:match("vim%.fn%.(%w+)") or line:match("vim%.(%w+)")

	if api_func then
		local ok = pcall(vim.cmd.help, api_func)
		if ok then return end
		ok = pcall(vim.cmd.help, "vim." .. api_func)
		if ok then return end
	end

	vim.cmd.help("api")
end, { desc = icons.diagnostics.Info .. " Neovim API docs" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Lua-specific alignment presets for mini.align:
-- • lua_assignments — align variable assignments on "="
-- • lua_table       — align table fields on "="
--
-- Registered dynamically when the first Lua buffer is opened.
-- The `is_language_loaded` check makes this idempotent.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("lua") then
		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			lua_assignments = {
				description = "Align Lua variable assignments on '='",
				icon = lua_icon,
				split_pattern = "=",
				category = "scripting",
				lang = "lua",
				filetypes = { "lua" },
			},
			lua_table = {
				description = "Align Lua table fields on '='",
				icon = lua_icon,
				split_pattern = "=",
				category = "scripting",
				lang = "lua",
				filetypes = { "lua" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("lua", "lua_assignments")
		align_registry.mark_language_loaded("lua")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("lua", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("lua_assignments"), {
			desc = lua_icon .. " Align Lua assignments",
		})

		keys.lang_map("lua", { "n", "x" }, "<leader>aT", align_registry.make_align_fn("lua_table"), {
			desc = lua_icon .. " Align Lua table fields",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Lua-specific
-- parts (servers, formatters, linters, parsers, DAP adapter).
--
-- Loading strategy:
-- ┌──────────────────────────┬────────────────────────────────────────┐
-- │ Plugin                   │ How it lazy-loads for Lua              │
-- ├──────────────────────────┼────────────────────────────────────────┤
-- │ nvim-lspconfig           │ opts merge (lua_ls server added)       │
-- │ lazydev.nvim             │ ft = "lua" (true lazy load)            │
-- │ luvit-meta               │ lazy = true (loaded by lazydev)        │
-- │ mason.nvim               │ opts merge (tools → ensure_installed)  │
-- │ conform.nvim             │ opts merge (formatters_by_ft.lua)      │
-- │ nvim-lint                │ opts merge (linters_by_ft.lua)         │
-- │ nvim-treesitter          │ opts merge (parsers → ensure_installed)│
-- │ one-small-step-for-vimkind│ ft = "lua" (true lazy load)           │
-- └──────────────────────────┴────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Lua
return {
	-- ── LSP SERVER (lua_ls) ────────────────────────────────────────────────
	-- sumneko/lua_ls: the standard Lua Language Server.
	-- Provides completions, diagnostics, go-to-definition, hover,
	-- rename, and inlay hints for Lua and Neovim-specific APIs.
	--
	-- Workspace library includes:
	--   • Neovim runtime (vim.*, vim.api.*, vim.fn.*)
	--   • User config directory (core.*, plugins.*, langs.*)
	--   • Plugin sources from lazy.nvim data directory
	--   • Dynamic types via lazydev.nvim (vim.uv, LazySpec, etc.)
	--
	-- Built-in formatting is DISABLED — stylua via conform.nvim
	-- is the authoritative formatter for this config.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				lua_ls = {
					settings = {
						Lua = {
							runtime = {
								version = "LuaJIT",
								path = vim.split(package.path, ";"),
							},
							workspace = {
								checkThirdParty = false,
								library = {
									vim.fn.expand("$VIMRUNTIME/lua"),
									vim.fn.expand("$VIMRUNTIME/lua/vim"),
									vim.fn.expand("$VIMRUNTIME/lua/vim/lsp"),
									vim.fn.stdpath("config") .. "/lua",
									vim.fn.stdpath("config") .. "/lua/types.lua",
									vim.fn.stdpath("data") .. "/lazy",
								},
							},
							completion = {
								callSnippet = "Replace",
							},
							diagnostics = {
								disable = { "missing-fields" },
								globals = { "vim", "LazyVim", "NvimConfig" },
							},
							format = {
								enable = false,
							},
							hint = {
								enable = true,
								arrayIndex = "Disable",
								setType = true,
							},
							telemetry = {
								enable = false,
							},
						},
					},
				},
			},
		},
		init = function()
			-- ── Buffer-local options for Lua files ───────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "lua" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = false
					opt.number = true
					opt.relativenumber = true
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
				end,
			})
		end,
	},

	-- ── LAZYDEV (Neovim Lua types, docs, completion) ───────────────────────
	-- Provides Neovim-specific type annotations and completions
	-- for lua_ls. Dynamically injects type stubs for:
	--   • vim.uv (libuv bindings via luvit-meta)
	--   • LazySpec (lazy.nvim plugin spec types)
	--
	-- Loaded exclusively on ft = "lua" — zero cost for other filetypes.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"folke/lazydev.nvim",
		ft = "lua",
		opts = {
			library = {
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
				{ path = "lazy.nvim", words = { "LazySpec" } },
			},
		},
	},

	-- ── LUVIT-META (libuv type annotations) ────────────────────────────────
	-- Provides type definitions for the `vim.uv` namespace (libuv
	-- bindings). Loaded lazily by lazydev.nvim only when `vim.uv`
	-- is referenced in the current file.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"Bilal2453/luvit-meta",
		lazy = true,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures Lua tooling is installed via Mason:
	--   • lua-language-server — sumneko Lua LSP (lua_ls)
	--   • stylua              — opinionated Lua formatter
	--   • selene              — Lua linter (stricter than lua_ls diagnostics)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"stylua",
				"selene",
				"lua-language-server",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- stylua: opinionated Lua formatter (Rust-based, fast).
	-- Enforces consistent indentation (tabs), quote style, call
	-- parentheses, and line width. Configured via `.stylua.toml`.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				lua = { "stylua" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- selene: a blazing-fast Lua linter written in Rust.
	-- Catches bugs that lua_ls diagnostics miss: unused variables,
	-- shadowed variables, incorrect standard library usage, etc.
	-- Configured via `selene.toml` and `vim.toml` (for vim globals).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				lua = { "selene" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- lua:    syntax highlighting, folding, text objects, indentation
	-- luadoc: LuaDoc comment parsing (@param, @return, @class, etc.)
	-- luap:   Lua pattern syntax highlighting in string.match/gsub/etc.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"lua",
				"luadoc",
				"luap",
			},
		},
	},

	-- ── ONE-SMALL-STEP-FOR-VIMKIND (Neovim Lua debugger) ──────────────────
	-- Enables DAP-based debugging of Lua code running inside Neovim.
	-- The adapter (`nlua`) connects to the running Neovim instance
	-- as a debug server, allowing:
	--   • Breakpoints in any Lua file loaded by Neovim
	--   • Step into/over/out of function calls
	--   • Variable inspection and watch expressions
	--   • Evaluate Lua expressions in the debug console
	--
	-- Loaded exclusively on ft = "lua" — zero cost for other filetypes.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"jbyuki/one-small-step-for-vimkind",
		lazy = true,
		ft = { "lua" },
		dependencies = {
			"mfussenegger/nvim-dap",
		},
		config = function()
			local dap = require("dap")

			--- DAP adapter for Neovim Lua debugging.
			---
			--- Connects to the running Neovim instance as a debug server
			--- on localhost (configurable host/port).
			---
			---@param callback fun(adapter: table) DAP callback to receive adapter config
			---@param dap_config table DAP launch/attach configuration
			dap.adapters.nlua = function(callback, dap_config)
				callback({
					type = "server",
					host = dap_config.host or "127.0.0.1",
					port = dap_config.port or 8086,
				})
			end

			--- Default DAP configuration for Lua files.
			---
			--- Attaches to the running Neovim instance — the user must
			--- first call `require("osv").launch({ port = 8086 })` in
			--- the Neovim instance to start the debug server.
			dap.configurations.lua = {
				{
					type = "nlua",
					request = "attach",
					name = "Attach to running Neovim instance",
				},
			}
		end,
	},

	-- ── NEOTEST (Lua/Plenary adapter) ─────────────────────────────────
	{
		"nvim-neotest/neotest",
		optional = true,
		dependencies = {
			{ "nvim-neotest/neotest-plenary", lazy = true },
		},
		opts = function(_, opts)
			opts.adapters = opts.adapters or {}
			table.insert(opts.adapters, require("neotest-plenary"))
		end,
	},
}
