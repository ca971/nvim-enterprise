---@file lua/langs/python.lua
---@description Python — LSP, formatter, linter, treesitter, DAP, neotest & buffer-local keymaps
---@module "langs.python"
---@author ca971
---@license MIT
---@version 1.1.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see plugins.code.neotest     Core neotest config (adapters = {} — populated here)
---@see langs.lua                Lua language support (same architecture)
---@see langs.rust               Rust language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/python.lua — Python language support                              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("python") → {} if off       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "python"):                   │    ║
--- ║  │  ├─ LSP          basedpyright  (type checking + completions)     │    ║
--- ║  │  │               ruff          (fast lint/format language server)│    ║
--- ║  │  ├─ Formatter    ruff_organize_imports + ruff_format (conform)   │    ║
--- ║  │  ├─ Linter       ruff (nvim-lint)                                │    ║
--- ║  │  ├─ Treesitter   python · rst · toml · requirements parsers      │    ║
--- ║  │  ├─ DAP          debugpy (via nvim-dap-python + Mason)           │    ║
--- ║  │  ├─ Neotest      neotest-python (pytest adapter, optional)       │    ║
--- ║  │  └─ Extras       venv-selector                                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file             R  Run with arguments      │    ║
--- ║  │  │            e  Execute line/selection                          │    ║
--- ║  │  ├─ TEST      t  Run tests (pytest)   T  Test under cursor       │    ║
--- ║  │  ├─ DEBUG     d  Debug (continue)     D  Debug test method       │    ║
--- ║  │  │            D  Debug selection (visual)                        │    ║
--- ║  │  ├─ VENV      v  Select virtualenv                               │    ║
--- ║  │  ├─ REPL      c  IPython / Python REPL                           │    ║
--- ║  │  ├─ TOOLS     s  Sort imports         p  Pip install             │    ║
--- ║  │  │            x  Reload module        a  Type check (mypy)       │    ║
--- ║  │  └─ DOCS      i  Module info          h  Pydoc documentation     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Neotest integration:                                            │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  This file registers neotest-python as an adapter via    │    │    ║
--- ║  │  │  lazy.nvim spec merging (optional = true).               │    │    ║
--- ║  │  │  The adapter is only loaded when ft = "python" fires.    │    │    ║
--- ║  │  │  Core neotest UI/keymaps live in plugins/code/neotest.lua│    │    ║
--- ║  │  │  All <leader>n keymaps work once the adapter is loaded.  │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  DAP integration flow:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. nvim-dap-python loads on ft = "python"               │    │    ║
--- ║  │  │  2. Configures dap.adapters.python → debugpy (Mason)     │    │    ║
--- ║  │  │  3. Adds default + custom dap.configurations.python      │    │    ║
--- ║  │  │     • Launch with arguments                              │    │    ║
--- ║  │  │     • Launch module                                      │    │    ║
--- ║  │  │     • Django server                                      │    │    ║
--- ║  │  │     • FastAPI (uvicorn)                                  │    │    ║
--- ║  │  │  4. Enables test_method() / debug_selection()            │    │    ║
--- ║  │  │  5. All core DAP keymaps become active:                  │    │    ║
--- ║  │  │     <leader>dc · <leader>db · F5 · F9 · etc.             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType python):                            ║
--- ║  • colorcolumn=88, textwidth=88   (Black / PEP 8 line length)            ║
--- ║  • tabstop=4, shiftwidth=4        (PEP 8 indentation)                    ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .pyi, .pyw, .pyx → python                                             ║
--- ║  • Pipfile → toml, pyproject.toml → toml                                 ║
--- ║  • requirements*.txt → requirements                                      ║
--- ║                                                                          ║
--- ║  Changelog:                                                              ║
--- ║  • 1.1.0 — Neotest adapter registered via optional spec merge pattern    ║
--- ║            Header updated with neotest integration docs                  ║
--- ║            Loading strategy table updated                                ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Python support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("python") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Python Nerd Font icon (trailing whitespace stripped)
local py_icon = icons.lang.python:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Python buffers.
-- The group is buffer-local and only visible when filetype == "python".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("python", "Python", py_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the best available Python interpreter.
---
--- Resolution order:
--- 1. `$VIRTUAL_ENV/bin/python` — active virtualenv (highest priority)
--- 2. `python3`                 — system Python 3
--- 3. `python`                  — fallback (may be Python 2 on old systems)
---
--- ```lua
--- local py = get_python()
--- if py then
---   vim.cmd.terminal(py .. " script.py")
--- end
--- ```
---
---@return string|nil path Absolute path to the interpreter, or `nil` if none found
---@private
local function get_python()
	if vim.env.VIRTUAL_ENV then
		local venv_py = vim.env.VIRTUAL_ENV .. "/bin/python"
		if vim.fn.executable(venv_py) == 1 then return venv_py end
	end
	if vim.fn.executable("python3") == 1 then return "python3" end
	if vim.fn.executable("python") == 1 then return "python" end
	return nil
end

--- Notify the user that no Python interpreter was found.
---
--- Centralizes the error notification to avoid repetition across
--- all keymaps that require a Python binary.
---
---@return nil
---@private
local function notify_no_python()
	vim.notify("No Python interpreter found", vim.log.levels.ERROR, { title = "Python" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- File execution and line/selection evaluation.
-- All keymaps open a terminal split for output.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current Python file in a terminal split.
---
--- Saves the buffer before execution. Uses the detected Python
--- interpreter from `get_python()`.
keys.lang_map("python", "n", "<leader>lr", function()
	local python = get_python()
	if not python then
		notify_no_python()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal(python .. " " .. vim.fn.shellescape(file))
end, { desc = icons.ui.Play .. " Run file" })

--- Run the current Python file with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then executes in a
--- terminal split. Aborts silently if the user cancels the prompt.
keys.lang_map("python", "n", "<leader>lR", function()
	local python = get_python()
	if not python then
		notify_no_python()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal(python .. " " .. vim.fn.shellescape(file) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Execute the current line as a Python one-liner.
---
--- Strips leading whitespace before passing to `python -c`.
--- Skips silently if the line is empty.
keys.lang_map("python", "n", "<leader>le", function()
	local python = get_python()
	if not python then return end
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	if line == "" then return end
	vim.cmd.split()
	vim.cmd.terminal(python .. " -c " .. vim.fn.shellescape(line))
end, { desc = py_icon .. " Execute current line" })

--- Execute the visual selection as Python code.
---
--- Yanks the selection into register `z`, then passes it to
--- `python -c` in a terminal split.
keys.lang_map("python", "v", "<leader>le", function()
	local python = get_python()
	if not python then return end
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code == "" then return end
	vim.cmd.split()
	vim.cmd.terminal(python .. " -c " .. vim.fn.shellescape(code))
end, { desc = py_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via pytest. Supports both full-suite and single-function
-- testing. Uses treesitter to detect the function name under cursor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite with pytest.
---
--- Auto-detects the test runner configuration:
--- - `pyproject.toml` / `pytest.ini` / `setup.cfg` → `python -m pytest`
--- - `tox.ini` → `tox`
--- - Fallback → `python -m pytest`
keys.lang_map("python", "n", "<leader>lt", function()
	local python = get_python()
	if not python then return end
	vim.cmd("silent! write")

	local cmd
	if
		vim.fn.filereadable("pyproject.toml") == 1
		or vim.fn.filereadable("pytest.ini") == 1
		or vim.fn.filereadable("setup.cfg") == 1
	then
		cmd = python .. " -m pytest -v --tb=short"
	elseif vim.fn.filereadable("tox.ini") == 1 then
		cmd = "tox"
	else
		cmd = python .. " -m pytest -v --tb=short"
	end

	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Test .. " Run tests (pytest)" })

--- Run pytest for the function under the cursor.
---
--- Uses treesitter to walk up the AST from the cursor position until
--- a `function_definition` node is found, then extracts its name for
--- the `-k` filter. Falls back to running the entire file if no
--- function is found.
keys.lang_map("python", "n", "<leader>lT", function()
	local python = get_python()
	if not python then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	---@type TSNode|nil
	local node = vim.treesitter.get_node()
	---@type string|nil
	local func_name = nil

	while node do
		if node:type() == "function_definition" then
			local name_node = node:field("name")[1]
			if name_node then func_name = vim.treesitter.get_node_text(name_node, 0) end
			break
		end
		node = node:parent()
	end

	local cmd
	if func_name then
		cmd = string.format("%s -m pytest %s -v -k %s", python, vim.fn.shellescape(file), vim.fn.shellescape(func_name))
	else
		cmd = string.format("%s -m pytest %s -v", python, vim.fn.shellescape(file))
	end

	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Test .. " Test under cursor" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via nvim-dap and nvim-dap-python.
--
-- <leader>ld starts or continues a debug session. The adapter (debugpy)
-- is pre-configured by nvim-dap-python when the filetype loads.
-- Both <leader>ld (lang) and <leader>dc (core dap) work in Python files.
--
-- <leader>lD debugs the test method under the cursor (normal) or the
-- visual selection (visual). Uses nvim-dap-python's test_method() and
-- debug_selection() which auto-detect pytest/unittest.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Saves the buffer, then calls `dap.continue()` which either resumes
--- a paused session or launches a new one using the Python adapter.
keys.lang_map("python", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Python" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (debugpy)" })

--- Debug the test method under the cursor.
---
--- Delegates to `dap-python.test_method()` which auto-detects the
--- test framework (pytest / unittest) and sets up the correct launch
--- configuration.
keys.lang_map("python", "n", "<leader>lD", function()
	vim.cmd("silent! write")
	local ok, dap_python = pcall(require, "dap-python")
	if not ok then
		vim.notify("nvim-dap-python not available", vim.log.levels.WARN, { title = "Python" })
		return
	end
	dap_python.test_method()
end, { desc = icons.dev.Debug .. " Debug test method" })

--- Debug the visual selection.
---
--- Delegates to `dap-python.debug_selection()` which evaluates the
--- selected Python code under the debugger.
keys.lang_map("python", "v", "<leader>lD", function()
	local ok, dap_python = pcall(require, "dap-python")
	if not ok then
		vim.notify("nvim-dap-python not available", vim.log.levels.WARN, { title = "Python" })
		return
	end
	dap_python.debug_selection()
end, { desc = icons.dev.Debug .. " Debug selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — VIRTUAL ENVIRONMENT
--
-- Virtualenv selection via venv-selector.nvim (if available) or a
-- built-in fallback that scans common venv directories and pyenv.
-- ═══════════════════════════════════════════════════════════════════════════

--- Select and activate a Python virtual environment.
---
--- Resolution strategy:
--- 1. If `venv-selector.nvim` is installed → use `:VenvSelect` (Telescope UI)
--- 2. Fallback: scan common directories for virtualenvs
---    - CWD: `venv/`, `.venv/`, `env/`, `.env/`, `.virtualenvs/`
---    - pyenv: `$PYENV_ROOT/versions/*`
--- 3. Present found venvs via `vim.ui.select()`
--- 4. On selection: set `$VIRTUAL_ENV` and prepend to `$PATH`
keys.lang_map("python", "n", "<leader>lv", function()
	-- ── Strategy 1: venv-selector plugin ─────────────────────────────
	if vim.fn.exists(":VenvSelect") == 2 then
		vim.cmd("VenvSelect")
		return
	end

	-- ── Strategy 2: manual directory scanning ────────────────────────
	---@type string[]
	local venvs = {}
	---@type string[]
	local patterns = { "venv", ".venv", "env", ".env", ".virtualenvs" }
	local cwd = vim.fn.getcwd()

	for _, pat in ipairs(patterns) do
		local dir = cwd .. "/" .. pat
		if vim.fn.isdirectory(dir) == 1 then venvs[#venvs + 1] = dir end
	end

	-- ── Scan pyenv versions ──────────────────────────────────────────
	local pyenv_root = vim.env.PYENV_ROOT or (vim.env.HOME .. "/.pyenv")
	local pyenv_versions = pyenv_root .. "/versions"

	if vim.fn.isdirectory(pyenv_versions) == 1 then
		local handle = vim.loop.fs_scandir(pyenv_versions)
		if handle then
			while true do
				local name = vim.loop.fs_scandir_next(handle)
				if not name then break end
				venvs[#venvs + 1] = pyenv_versions .. "/" .. name
			end
		end
	end

	if #venvs == 0 then
		vim.notify("No virtual environments found", vim.log.levels.INFO, { title = "Python" })
		return
	end

	-- ── Present selection ────────────────────────────────────────────
	vim.ui.select(venvs, { prompt = py_icon .. " Select virtualenv:" }, function(choice)
		if not choice then return end
		vim.env.VIRTUAL_ENV = choice
		vim.env.PATH = choice .. "/bin:" .. vim.env.PATH
		vim.notify("Activated: " .. choice, vim.log.levels.INFO, { title = "Python" })
	end)
end, { desc = py_icon .. " Select virtualenv" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
--
-- Opens an interactive Python REPL in a terminal split.
-- Prefers IPython when available for a better interactive experience.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a Python REPL in a terminal split.
---
--- Prefers `ipython` if available (better completion, syntax highlighting),
--- otherwise falls back to the detected Python interpreter.
keys.lang_map("python", "n", "<leader>lc", function()
	---@type string
	local cmd
	if vim.fn.executable("ipython") == 1 then
		cmd = "ipython"
	else
		local python = get_python()
		cmd = python and python or "python3"
	end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Terminal .. " REPL" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Development utilities: import sorting, pip install, module reload,
-- and static type checking via mypy.
-- ═══════════════════════════════════════════════════════════════════════════

--- Sort imports using ruff's isort-compatible rule (`--select I`).
---
--- Runs ruff in-place on the current file, then reloads the buffer
--- to reflect changes. Requires `ruff` to be installed.
keys.lang_map("python", "n", "<leader>ls", function()
	if vim.fn.executable("ruff") == 1 then
		vim.cmd("silent! write")
		local file = vim.fn.expand("%:p")
		vim.fn.system("ruff check --select I --fix " .. vim.fn.shellescape(file))
		vim.cmd.edit()
		vim.notify("Imports sorted", vim.log.levels.INFO, { title = "Python" })
	else
		vim.notify("Install ruff: pip install ruff", vim.log.levels.WARN, { title = "Python" })
	end
end, { desc = py_icon .. " Sort imports" })

--- Install project dependencies from the first matching file.
---
--- Scans for (in order):
--- 1. `requirements.txt` → `pip install -r`
--- 2. `pyproject.toml`   → `pip install -e .`
--- 3. `setup.py`         → `pip install -e .`
--- 4. `Pipfile`          → `pipenv install`
keys.lang_map("python", "n", "<leader>lp", function()
	local python = get_python()
	if not python then return end

	---@type { file: string, cmd: string }[]
	local files = {
		{ file = "requirements.txt", cmd = python .. " -m pip install -r requirements.txt" },
		{ file = "pyproject.toml", cmd = python .. " -m pip install -e ." },
		{ file = "setup.py", cmd = python .. " -m pip install -e ." },
		{ file = "Pipfile", cmd = "pipenv install" },
	}

	for _, f in ipairs(files) do
		if vim.fn.filereadable(f.file) == 1 then
			vim.cmd.split()
			vim.cmd.terminal(f.cmd)
			return
		end
	end

	vim.notify("No requirements file found", vim.log.levels.WARN, { title = "Python" })
end, { desc = icons.ui.Package .. " Pip install" })

--- Attempt to reload the current file as a Python module.
---
--- Uses `importlib.import_module()` to check if the module (derived
--- from the filename) is currently loaded in `sys.modules`.
---
--- NOTE: This is a simple heuristic — it won't work for packages
--- with complex `__init__.py` hierarchies.
keys.lang_map("python", "n", "<leader>lx", function()
	local python = get_python()
	if not python then return end
	vim.cmd("silent! write")
	local module_name = vim.fn.expand("%:t:r")
	vim.cmd.split()
	vim.cmd.terminal(
		string.format(
			'%s -c "import importlib, sys; '
				.. "mod = '%s'; "
				.. "m = importlib.import_module(mod) if mod in sys.modules else None; "
				.. "print(f'Module {mod} reloaded' if m else f'{mod} not loaded')\"",
			python,
			module_name
		)
	)
end, { desc = icons.ui.Refresh .. " Reload module" })

--- Run mypy type checker on the current file.
---
--- Opens a terminal split with mypy output. Notifies the user
--- if mypy is not installed.
keys.lang_map("python", "n", "<leader>la", function()
	if vim.fn.executable("mypy") ~= 1 then
		vim.notify("Install mypy: pip install mypy", vim.log.levels.WARN, { title = "Python" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("mypy " .. vim.fn.shellescape(file))
end, { desc = py_icon .. " Type check (mypy)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to Python module metadata and pydoc documentation
-- without leaving the editor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show pip package info for the word under cursor.
---
--- Runs `pip show <word>` and displays the result in a notification.
--- Useful for quickly checking installed package versions and metadata.
keys.lang_map("python", "n", "<leader>li", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then return end
	local python = get_python() or "python3"
	local result = vim.fn.system(python .. " -m pip show " .. word .. " 2>/dev/null")
	if vim.v.shell_error == 0 and result ~= "" then
		vim.notify(result, vim.log.levels.INFO, { title = "pip show: " .. word })
	else
		vim.notify("Package not found: " .. word, vim.log.levels.INFO, { title = "Python" })
	end
end, { desc = icons.diagnostics.Info .. " Module info" })

--- Open pydoc documentation for the word under cursor.
---
--- Runs `python -m pydoc <word>` in a terminal split, providing
--- the same output as the interactive `help()` function.
keys.lang_map("python", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then return end
	local python = get_python() or "python3"
	vim.cmd.split()
	vim.cmd.terminal(python .. " -m pydoc " .. vim.fn.shellescape(word))
end, { desc = icons.ui.Note .. " Documentation (pydoc)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Python-specific alignment presets for mini.align:
-- • python_dict   — align dictionary entries on ":"
-- • python_kwargs — align keyword arguments on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("python") then
		---@type string Alignment preset icon from icons.app
		local py_align_icon = icons.app.Python

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			python_dict = {
				description = "Align Python dictionary entries on ':'",
				icon = py_align_icon,
				split_pattern = ":",
				category = "scripting",
				lang = "python",
				filetypes = { "python" },
			},
			python_kwargs = {
				description = "Align Python keyword arguments on '='",
				icon = py_align_icon,
				split_pattern = "=",
				category = "scripting",
				lang = "python",
				filetypes = { "python" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("python", "python_dict")
		align_registry.mark_language_loaded("python")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("python", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("python_dict"), {
			desc = py_align_icon .. "  Align Python dict",
		})
		keys.lang_map("python", { "n", "x" }, "<leader>aT", align_registry.make_align_fn("python_kwargs"), {
			desc = py_align_icon .. "  Align Python kwargs",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Python-specific
-- parts (servers, formatters, linters, parsers, adapters).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Python                 │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (servers added on require)        │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.python)         │
-- │ nvim-lint          │ opts merge (linters_by_ft.python)            │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- │ nvim-dap-python    │ ft = "python" (true lazy load)               │
-- │ venv-selector      │ ft = "python" (true lazy load)               │
-- │ neotest            │ optional = true (adapter injected via merge) │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Python
return {
	-- ── LSP SERVERS ────────────────────────────────────────────────────────
	-- basedpyright: fast type checker with auto-import completions
	-- ruff: extremely fast Python linter + formatter (Rust-based)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				basedpyright = {
					settings = {
						basedpyright = {
							analysis = {
								typeCheckingMode = "standard",
								autoImportCompletions = true,
								diagnosticSeverityOverrides = {
									reportMissingImports = "error",
									reportUnusedVariable = "warning",
									reportUnusedImport = "warning",
								},
							},
						},
					},
				},
				ruff = {
					cmd_env = { RUFF_TRACE = "messages" },
					init_options = {
						settings = {
							logLevel = "error",
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					pyi = "python",
					pyw = "python",
					pyx = "python",
				},
				filename = {
					[".python-version"] = "text",
					["Pipfile"] = "toml",
					["pyproject.toml"] = "toml",
				},
				pattern = {
					["requirements.*%.txt"] = "requirements",
					[".*/%.ruff%.toml"] = "toml",
				},
			})

			-- ── Buffer-local options for Python files ────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "python" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "88"
					opt.textwidth = 88
					opt.tabstop = 4
					opt.shiftwidth = 4
					opt.softtabstop = 4
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
	-- Ensures basedpyright, ruff, and debugpy are installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"basedpyright",
				"ruff",
				"debugpy",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- Runs ruff_organize_imports first (isort-compatible), then ruff_format.
	-- Both are sub-commands of the ruff binary (no extra install needed).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				python = { "ruff_organize_imports", "ruff_format" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- Ruff as a standalone linter via nvim-lint (complements the LSP).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				python = { "ruff" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- python:       syntax highlighting, folding, text objects
	-- rst:          reStructuredText (docstrings, Sphinx)
	-- toml:         pyproject.toml, ruff.toml
	-- requirements: requirements.txt highlighting
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"python",
				"rst",
				"toml",
				"requirements",
			},
		},
	},

	-- ── DAP — PYTHON DEBUGGER ──────────────────────────────────────────────
	-- nvim-dap-python configures:
	--   • dap.adapters.python → debugpy (prefers Mason-installed binary)
	--   • dap.configurations.python → default + custom launch configs
	--
	-- Custom configurations added:
	--   1. Launch with arguments    — prompts for CLI args
	--   2. Launch module            — prompts for module name
	--   3. Django server            — manage.py runserver --noreload
	--   4. FastAPI (uvicorn)        — prompts for app module (e.g. main:app)
	--
	-- After loading, ALL core DAP keymaps work in Python files:
	--   <leader>dc, <leader>db, <leader>di, <leader>do, F5, F9, etc.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-dap-python",
		ft = "python",
		dependencies = {
			"mfussenegger/nvim-dap",
		},
		config = function()
			-- ── Resolve debugpy path ─────────────────────────────────
			local debugpy_path = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"

			---@type string Python path for debugpy adapter
			local python_path
			if vim.fn.executable(debugpy_path) == 1 then
				python_path = debugpy_path
			else
				python_path = get_python() or "python3"
			end

			-- ── Initialize dap-python ────────────────────────────────
			local dap_python = require("dap-python")
			dap_python.setup(python_path)
			dap_python.test_runner = "pytest"

			-- ── Add custom launch configurations ─────────────────────
			local dap = require("dap")
			local configs = dap.configurations.python or {}

			-- Guard against duplicate registration on re-source
			---@type boolean
			local has_custom = false
			for _, cfg in ipairs(configs) do
				if cfg.name == "Launch with arguments" then
					has_custom = true
					break
				end
			end

			if not has_custom then
				--- Launch current file with user-provided CLI arguments.
				table.insert(configs, {
					type = "python",
					request = "launch",
					name = "Launch with arguments",
					program = "${file}",
					args = function()
						local input = vim.fn.input("Arguments: ")
						return vim.split(input, " ", { trimempty = true })
					end,
					console = "integratedTerminal",
				})

				--- Launch a Python module by name (e.g. `mypackage.cli`).
				table.insert(configs, {
					type = "python",
					request = "launch",
					name = "Launch module",
					module = function()
						return vim.fn.input("Module: ")
					end,
					console = "integratedTerminal",
				})

				--- Launch Django development server with reload disabled.
				table.insert(configs, {
					type = "python",
					request = "launch",
					name = "Django server",
					program = "${workspaceFolder}/manage.py",
					args = { "runserver", "--noreload" },
					django = true,
					console = "integratedTerminal",
				})

				--- Launch FastAPI via uvicorn with auto-reload.
				table.insert(configs, {
					type = "python",
					request = "launch",
					name = "FastAPI (uvicorn)",
					module = "uvicorn",
					args = function()
						local module = vim.fn.input("App module (e.g. main:app): ")
						return { module, "--reload" }
					end,
					console = "integratedTerminal",
				})

				dap.configurations.python = configs
			end
		end,
	},

	-- ── MASON-NVIM-DAP (adapter auto-install) ──────────────────────────────
	-- Ensures the Python DAP adapter is managed by Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "python" },
		},
	},

	-- ── VENV SELECTOR ──────────────────────────────────────────────────────
	-- Telescope-based virtualenv picker. Lazy-loaded on ft = "python".
	-- Scans common venv directories and provides a fuzzy-searchable list.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"linux-cultist/venv-selector.nvim",
		branch = "regexp",
		ft = { "python" },
		dependencies = {
			"nvim-telescope/telescope.nvim",
			"neovim/nvim-lspconfig",
		},
		opts = {
			name = { "venv", ".venv", "env", ".env" },
			auto_refresh = true,
		},
	},

	-- ── NEOTEST (Python adapter) ───────────────────────────────────────────
	-- Registers neotest-python into the core neotest adapters list.
	-- The adapter is only loaded when a Python file is opened.
	-- Core neotest UI/keymaps are in plugins/code/neotest.lua.
	--
	-- Pattern:
	--   optional = true   → only merges if neotest core is installed
	--   opts function     → appends adapter to opts.adapters table
	--   dependencies      → ensures neotest-python is available
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-neotest/neotest",
		optional = true,
		dependencies = {
			{ "nvim-neotest/neotest-python", lazy = true },
		},
		opts = function(_, opts)
			opts.adapters = opts.adapters or {}
			table.insert(
				opts.adapters,
				require("neotest-python")({
					dap = { justMyCode = false },
					runner = "pytest",
					args = { "--tb=short", "-q" },
				})
			)
		end,
	},
}
