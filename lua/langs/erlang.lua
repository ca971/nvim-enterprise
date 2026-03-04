---@file lua/langs/erlang.lua
---@description Erlang — LSP, formatter, treesitter & buffer-local keymaps
---@module "langs.erlang"
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
---@see langs.python             Python language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/erlang.lua — Erlang language support                              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("erlang") → {} if off       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "erlang"):                   │    ║
--- ║  │  ├─ LSP          erlangls (ErlangLS — completions, diagnostics)  │    ║
--- ║  │  ├─ Formatter    erlfmt (if available, via conform.nvim)         │    ║
--- ║  │  ├─ Linter       dialyzer (via rebar3 or standalone)             │    ║
--- ║  │  ├─ Treesitter   erlang parser                                   │    ║
--- ║  │  ├─ DAP          — (not configured)                              │    ║
--- ║  │  └─ Extras       rebar3 integration (build, test, deps, release) │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Compile & run file    R  Run with arguments     │    ║
--- ║  │  ├─ SHELL     c  Erlang shell (erl)    s  Rebar3 shell           │    ║
--- ║  │  ├─ BUILD     b  Rebar3 compile                                  │    ║
--- ║  │  ├─ TEST      t  EUnit tests           T  Common test (ct)       │    ║
--- ║  │  ├─ ANALYSIS  d  Dialyzer (rebar3 or standalone)                 │    ║
--- ║  │  ├─ DEPS      p  Deps management (picker)                        │    ║
--- ║  │  ├─ RELEASE   l  Rebar3 release                                  │    ║
--- ║  │  ├─ COMMANDS  m  Rebar3 commands (comprehensive picker)          │    ║
--- ║  │  └─ DOCS      i  Module info (OTP version, tools)                │    ║
--- ║  │               h  Documentation (browser)                         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Dialyzer resolution:                                            │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. rebar3 available → rebar3 dialyzer (project PLT)     │    │    ║
--- ║  │  │  2. standalone dialyzer → dialyzer <file> (single file)  │    │    ║
--- ║  │  │  3. neither → notification with install instructions     │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType erlang):                            ║
--- ║  • colorcolumn=100, textwidth=100 (Erlang convention)                    ║
--- ║  • tabstop=4, shiftwidth=4        (Erlang standard indentation)          ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • commentstring="%% %s"          (Erlang comments)                      ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .erl, .hrl → erlang (source + headers)                                ║
--- ║  • .app, .escript → erlang                                               ║
--- ║  • rebar.config, rebar.config.script, rebar.lock → erlang                ║
--- ║  • sys.config, vm.args → erlang                                          ║
--- ║                                                                          ║
--- ║  NOTE: erlangls and erlfmt are conditionally configured based on         ║
--- ║  rebar3/erlfmt availability. In a pure OTP environment without           ║
--- ║  rebar3, only the standalone erlc/erl keymaps are fully functional.      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Erlang support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("erlang") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Erlang Nerd Font icon (trailing whitespace stripped)
local erl_icon = icons.lang.erlang:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Erlang buffers.
-- The group is buffer-local and only visible when filetype == "erlang".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("erlang", "Erlang", erl_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that rebar3 is available in PATH.
---
--- Rebar3 is the standard Erlang build tool. Many keymaps in this
--- module depend on it for compilation, testing, and dependency
--- management.
---
--- ```lua
--- if has_rebar3() then
---   vim.cmd.terminal("rebar3 compile")
--- end
--- ```
---
---@return boolean available `true` if `rebar3` is executable
---@private
local function has_rebar3()
	return vim.fn.executable("rebar3") == 1
end

--- Notify the user that rebar3 is not found.
---
--- Centralizes the warning notification to avoid repetition across
--- all keymaps that require rebar3.
---
---@return nil
---@private
local function notify_no_rebar3()
	vim.notify("rebar3 not found", vim.log.levels.WARN, { title = "Erlang" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN / COMPILE
--
-- File compilation and execution via erlc and erl.
-- Supports both simple module execution and custom function calls
-- with arguments.
-- ═══════════════════════════════════════════════════════════════════════════

--- Compile and run the current Erlang file.
---
--- Saves the buffer, then:
--- 1. `cd` to the file's directory
--- 2. Compiles with `erlc <file>` (produces `.beam`)
--- 3. Runs `erl -noshell -s <module> -s init stop`
---
--- The module name is derived from the filename (without `.erl` extension).
--- Requires `erlc` to be available in PATH.
keys.lang_map("erlang", "n", "<leader>lr", function()
	if vim.fn.executable("erlc") ~= 1 then
		vim.notify("erlc not found — install Erlang/OTP", vim.log.levels.ERROR, { title = "Erlang" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local module = vim.fn.expand("%:t:r")
	local dir = vim.fn.expand("%:p:h")
	vim.cmd.split()
	vim.cmd.terminal(
		string.format(
			"cd %s && erlc %s && erl -noshell -s %s -s init stop",
			vim.fn.shellescape(dir),
			vim.fn.shellescape(file),
			module
		)
	)
end, { desc = icons.ui.Play .. " Run file" })

--- Run a specific function with optional arguments.
---
--- Prompts for:
--- 1. Function name (default: `main`)
--- 2. Arguments as an Erlang term (optional)
---
--- Constructs an `erl -noshell -eval` command that calls
--- `Module:Function(Args)` then stops the VM.
keys.lang_map("erlang", "n", "<leader>lR", function()
	if vim.fn.executable("erl") ~= 1 then
		vim.notify("erl not found", vim.log.levels.ERROR, { title = "Erlang" })
		return
	end
	vim.cmd("silent! write")
	local module = vim.fn.expand("%:t:r")

	vim.ui.input({ prompt = "Function to run: ", default = "main" }, function(func)
		if not func or func == "" then return end
		vim.ui.input({ prompt = "Args (erlang term): " }, function(args)
			---@type string
			local erl_cmd
			if args and args ~= "" then
				erl_cmd = string.format("erl -noshell -eval '%s:%s(%s), init:stop().'", module, func, args)
			else
				erl_cmd = string.format("erl -noshell -eval '%s:%s(), init:stop().'", module, func)
			end
			vim.cmd.split()
			vim.cmd.terminal(erl_cmd)
		end)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SHELL
--
-- Interactive Erlang shells for REPL-driven development.
-- Supports both bare erl and rebar3 shell (project-aware).
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a bare Erlang shell.
---
--- Launches `erl` in a terminal split. This is a standalone BEAM VM
--- without project context (use rebar3 shell for project modules).
keys.lang_map("erlang", "n", "<leader>lc", function()
	if vim.fn.executable("erl") ~= 1 then
		vim.notify("erl not found", vim.log.levels.ERROR, { title = "Erlang" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("erl")
end, { desc = icons.ui.Terminal .. " Erlang shell" })

--- Open a rebar3 shell with project modules loaded.
---
--- Launches `rebar3 shell` which compiles the project and starts
--- an Erlang shell with all application modules available.
--- Requires rebar3 to be installed.
keys.lang_map("erlang", "n", "<leader>ls", function()
	if not has_rebar3() then
		notify_no_rebar3()
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("rebar3 shell")
end, { desc = erl_icon .. " Rebar3 shell" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — BUILD / TEST
--
-- Rebar3 build and test commands. Supports EUnit (unit tests),
-- Common Test (integration tests), and Dialyzer (type analysis).
-- ═══════════════════════════════════════════════════════════════════════════

--- Compile the project with `rebar3 compile`.
---
--- Saves the buffer before compiling.
keys.lang_map("erlang", "n", "<leader>lb", function()
	if not has_rebar3() then
		notify_no_rebar3()
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("rebar3 compile")
end, { desc = icons.dev.Build .. " Rebar3 compile" })

--- Run EUnit tests with `rebar3 eunit`.
---
--- EUnit is Erlang's built-in unit testing framework.
--- Saves the buffer before running.
keys.lang_map("erlang", "n", "<leader>lt", function()
	if not has_rebar3() then
		notify_no_rebar3()
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("rebar3 eunit")
end, { desc = icons.dev.Test .. " EUnit tests" })

--- Run Common Test suite with `rebar3 ct`.
---
--- Common Test is Erlang's integration/system testing framework,
--- used for larger test suites with setup/teardown phases.
--- Saves the buffer before running.
keys.lang_map("erlang", "n", "<leader>lT", function()
	if not has_rebar3() then
		notify_no_rebar3()
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("rebar3 ct")
end, { desc = icons.dev.Test .. " Common test" })

--- Run Dialyzer type analysis.
---
--- Resolution strategy:
--- 1. `rebar3 dialyzer` — uses project PLT (preferred)
--- 2. `dialyzer <file>` — standalone single-file analysis
--- 3. Notification if neither is available
keys.lang_map("erlang", "n", "<leader>ld", function()
	if has_rebar3() then
		vim.cmd.split()
		vim.cmd.terminal("rebar3 dialyzer")
		return
	end
	if vim.fn.executable("dialyzer") ~= 1 then
		vim.notify("dialyzer not found", vim.log.levels.WARN, { title = "Erlang" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("dialyzer " .. vim.fn.shellescape(vim.fn.expand("%:p")))
end, { desc = erl_icon .. " Dialyzer" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEPS / RELEASE / COMMANDS
--
-- Rebar3 dependency management, release building, and comprehensive
-- command picker for all rebar3 tasks.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a rebar3 dependency management picker.
---
--- Available actions:
--- • Get deps      — fetch all dependencies
--- • Upgrade deps  — upgrade to latest compatible versions
--- • Deps tree     — display dependency tree
--- • Lock deps     — lock current versions
--- • Unlock deps   — remove version locks
keys.lang_map("erlang", "n", "<leader>lp", function()
	if not has_rebar3() then
		notify_no_rebar3()
		return
	end

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "Get deps", cmd = "rebar3 get-deps" },
		{ name = "Upgrade deps", cmd = "rebar3 upgrade" },
		{ name = "Deps tree", cmd = "rebar3 tree" },
		{ name = "Lock deps", cmd = "rebar3 lock" },
		{ name = "Unlock deps", cmd = "rebar3 unlock" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = erl_icon .. " Deps:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = icons.ui.Package .. " Deps" })

--- Build an OTP release with `rebar3 release`.
---
--- Creates a self-contained release package with the Erlang runtime,
--- application code, and all dependencies.
keys.lang_map("erlang", "n", "<leader>ll", function()
	if not has_rebar3() then
		notify_no_rebar3()
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("rebar3 release")
end, { desc = erl_icon .. " Release" })

--- Open a comprehensive rebar3 commands picker.
---
--- Available actions:
--- • compile, clean                — build management
--- • eunit, ct                     — testing
--- • dialyzer, xref                — static analysis
--- • shell                         — interactive REPL
--- • release, tar                  — packaging
--- • edoc                          — documentation generation
--- • new app…, new lib…            — project scaffolding (prompt for name)
keys.lang_map("erlang", "n", "<leader>lm", function()
	if not has_rebar3() then
		notify_no_rebar3()
		return
	end

	---@type { name: string, cmd: string, prompt?: boolean }[]
	local actions = {
		{ name = "compile", cmd = "rebar3 compile" },
		{ name = "clean", cmd = "rebar3 clean" },
		{ name = "eunit", cmd = "rebar3 eunit" },
		{ name = "ct", cmd = "rebar3 ct" },
		{ name = "dialyzer", cmd = "rebar3 dialyzer" },
		{ name = "xref", cmd = "rebar3 xref" },
		{ name = "shell", cmd = "rebar3 shell" },
		{ name = "release", cmd = "rebar3 release" },
		{ name = "tar", cmd = "rebar3 tar" },
		{ name = "edoc", cmd = "rebar3 edoc" },
		{ name = "new app…", cmd = "rebar3 new app", prompt = true },
		{ name = "new lib…", cmd = "rebar3 new lib", prompt = true },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = erl_icon .. " Rebar3:" },
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
end, { desc = erl_icon .. " Rebar3 commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Erlang/OTP information and quick access to documentation
-- via the system browser.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show Erlang/OTP information and tool availability.
---
--- Displays:
--- • OTP release version (if erl is available)
--- • Tool availability matrix (erl, erlc, rebar3, dialyzer, erlfmt)
keys.lang_map("erlang", "n", "<leader>li", function()
	---@type string[]
	local info = { erl_icon .. " Erlang Info:", "" }

	if vim.fn.executable("erl") == 1 then
		local version = vim.fn
			.system("erl -eval 'io:format(\"~s\", [erlang:system_info(otp_release)]), halt().' -noshell 2>/dev/null")
			:gsub("%s+$", "")
		info[#info + 1] = "  OTP:     " .. version
	end

	---@type string[]
	local tools = { "erl", "erlc", "rebar3", "dialyzer", "erlfmt" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Erlang" })
end, { desc = icons.diagnostics.Info .. " Module info" })

--- Open Erlang documentation in the system browser.
---
--- Presents a picker with key reference pages:
--- • Erlang Docs           — official OTP documentation
--- • Learn You Some Erlang — comprehensive tutorial
--- • Rebar3 Docs           — build tool documentation
--- • Hex.pm                — package registry (shared with Elixir)
keys.lang_map("erlang", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Erlang Docs", url = "https://www.erlang.org/docs" },
		{ name = "Learn You Some Erlang", url = "https://learnyousomeerlang.com/" },
		{ name = "Rebar3 Docs", url = "https://rebar3.org/docs/" },
		{ name = "Hex.pm (packages)", url = "https://hex.pm/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = erl_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Erlang-specific alignment presets for mini.align:
-- • erlang_record — align record field definitions on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("erlang") then
		---@type string Alignment preset icon from icons.lang
		local align_icon = icons.lang.erlang

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			erlang_record = {
				description = "Align Erlang record fields on '='",
				icon = align_icon,
				split_pattern = "=",
				category = "functional",
				lang = "erlang",
				filetypes = { "erlang" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("erlang", "erlang_record")
		align_registry.mark_language_loaded("erlang")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("erlang", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("erlang_record"), {
			desc = align_icon .. "  Align Erlang record",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Erlang-specific
-- parts (servers, formatters, parsers).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Erlang                 │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig                         │ opts fn merge (erlangls if rebar3 available) │
-- │ mason.nvim                             │ opts fn merge (erlang-ls if rebar3 available)│
-- │ conform.nvim                           │ opts fn merge (erlfmt if available)          │
-- │ nvim-treesitter                        │ opts merge (erlang parser added)             │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: erlangls and erlfmt are conditionally configured based on
-- rebar3/erlfmt availability. In a pure OTP environment without rebar3,
-- the LSP and formatter may not be active. Consider installing rebar3
-- for the full toolchain experience.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Erlang
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- erlangls: ErlangLS language server providing completions, diagnostics,
	-- go-to-definition, find-references, and refactoring support.
	-- Only configured if rebar3 is available (required for project analysis).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = function(_, opts)
			if vim.fn.executable("rebar3") == 1 then
				opts.servers = opts.servers or {}
				opts.servers.erlangls = {}
			end
		end,
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					erl = "erlang",
					hrl = "erlang",
					app = "erlang",
					escript = "erlang",
				},
				filename = {
					["rebar.config"] = "erlang",
					["rebar.config.script"] = "erlang",
					["rebar.lock"] = "erlang",
					["sys.config"] = "erlang",
					["vm.args"] = "erlang",
				},
			})

			-- ── Buffer-local options for Erlang files ────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "erlang" },
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
					opt.commentstring = "%% %s"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures erlang-ls is installed via Mason.
	-- Only extends ensure_installed if rebar3 is available.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}
			if vim.fn.executable("rebar3") == 1 then vim.list_extend(opts.ensure_installed, { "erlang-ls" }) end
		end,
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- erlfmt: the official Erlang formatter from WhatsApp/Meta.
	-- Only configured if erlfmt is available in PATH.
	-- An alternative is the built-in `erl_tidy` module.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = function(_, opts)
			if vim.fn.executable("erlfmt") == 1 then
				opts.formatters_by_ft = opts.formatters_by_ft or {}
				opts.formatters_by_ft.erlang = { "erlfmt" }
			end
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- erlang: syntax highlighting, folding, text objects and indentation
	--         for Erlang source files (.erl, .hrl).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"erlang",
			},
		},
	},
}
