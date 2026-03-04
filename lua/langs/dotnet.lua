---@file lua/langs/dotnet.lua
---@description C# / .NET — LSP, formatter, linter, treesitter, DAP & buffer-local keymaps
---@module "langs.dotnet"
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
---@see langs.docker             Docker language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/dotnet.lua — C# / .NET language support                           ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("dotnet") → {} if off       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "cs"):                       │    ║
--- ║  │  ├─ LSP          omnisharp (Roslyn-based C# intelligence)        │    ║
--- ║  │  ├─ Formatter    csharpier (opinionated C# formatter)            │    ║
--- ║  │  ├─ Linter       Roslyn analyzers via omnisharp LSP diagnostics  │    ║
--- ║  │  ├─ Treesitter   c_sharp parser                                  │    ║
--- ║  │  ├─ DAP          netcoredbg (CoreCLR debugger via Mason)         │    ║
--- ║  │  └─ Extras       neotest-dotnet                                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  dotnet run            R  Run with arguments     │    ║
--- ║  │  │            w  Watch run (hot-reload)                          │    ║
--- ║  │  ├─ BUILD     b  dotnet build          c  dotnet clean           │    ║
--- ║  │  ├─ TEST      t  dotnet test           T  Test under cursor      │    ║
--- ║  │  ├─ DEBUG     d  Debug (netcoredbg / coreclr)                    │    ║
--- ║  │  ├─ NUGET     p  Add NuGet package                               │    ║
--- ║  │  ├─ PROJECT   s  Solution info         n  New project            │    ║
--- ║  │  │            i  Project info                                    │    ║
--- ║  │  ├─ EF        e  Entity Framework migrations (picker)            │    ║
--- ║  │  └─ DOCS      h  Documentation (browser)                         │    ║
--- ║  │                                                                  │    ║
--- ║  │  DAP integration flow:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. mason-nvim-dap ensures "coreclr" adapter installed   │    │    ║
--- ║  │  │  2. netcoredbg provides CoreCLR debugging support        │    │    ║
--- ║  │  │  3. <leader>ld calls dap.continue() to start/resume      │    │    ║
--- ║  │  │  4. All core DAP keymaps become active:                  │    │    ║
--- ║  │  │     <leader>dc · <leader>db · F5 · F9 · etc.             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType cs):                                ║
--- ║  • colorcolumn=120, textwidth=120 (.NET convention)                      ║
--- ║  • tabstop=4, shiftwidth=4        (C# standard indentation)              ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • commentstring="// %s"          (C-style line comments)                ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .cs, .csx → cs                                                        ║
--- ║  • .razor → razor                                                        ║
--- ║  • *.csproj, *.fsproj → xml                                              ║
--- ║  • *.sln → solution                                                      ║
--- ║  • global.json → json, nuget.config → xml                                ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if .NET support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("dotnet") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string C# Nerd Font icon (trailing whitespace stripped)
local cs_icon = icons.lang.csharp:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for C# buffers.
-- The group is buffer-local and only visible when filetype == "cs".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("cs", "C#", cs_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the dotnet CLI is available in PATH.
---
--- Notifies the user with an error if the .NET SDK is not found.
---
--- ```lua
--- if not check_dotnet() then return end
--- ```
---
---@return boolean available `true` if `dotnet` is executable, `false` otherwise
---@private
local function check_dotnet()
	if vim.fn.executable("dotnet") ~= 1 then
		vim.notify("dotnet CLI not found — install .NET SDK", vim.log.levels.ERROR, { title = ".NET" })
		return false
	end
	return true
end

--- Detect the project or solution file in the current working directory.
---
--- Resolution order:
--- 1. `*.sln`    — solution file (highest priority)
--- 2. `*.csproj` — C# project file
--- 3. `*.fsproj` — F# project file
--- 4. `*.vbproj` — VB.NET project file
---
--- ```lua
--- local proj, kind = detect_project()
--- if kind == "sln" then
---   vim.cmd.terminal("dotnet sln list")
--- end
--- ```
---
---@return string|nil path Absolute path to the project/solution file, or `nil`
---@return string|nil kind File kind: `"sln"`, `"csproj"`, `"fsproj"`, `"vbproj"`, or `nil`
---@private
local function detect_project()
	local cwd = vim.fn.getcwd()

	-- ── Prefer solution file ─────────────────────────────────────────
	local sln = vim.fn.glob(cwd .. "/*.sln", false, true)
	if #sln > 0 then return sln[1], "sln" end

	-- ── Then project files ───────────────────────────────────────────
	for _, ext in ipairs({ "csproj", "fsproj", "vbproj" }) do
		local proj = vim.fn.glob(cwd .. "/*." .. ext, false, true)
		if #proj > 0 then return proj[1], ext end
	end

	return nil, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN / BUILD
--
-- Project execution and build commands.
-- All keymaps save the buffer before execution.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the project with `dotnet run`.
---
--- Saves the buffer, then executes in a terminal split.
keys.lang_map("cs", "n", "<leader>lr", function()
	if not check_dotnet() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("dotnet run")
end, { desc = icons.ui.Play .. " Run" })

--- Run the project with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then executes
--- `dotnet run -- <args>` in a terminal split. Aborts silently
--- if the user cancels the prompt.
keys.lang_map("cs", "n", "<leader>lR", function()
	if not check_dotnet() then return end
	vim.cmd("silent! write")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal("dotnet run -- " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Build the project with `dotnet build`.
---
--- Saves the buffer before building.
keys.lang_map("cs", "n", "<leader>lb", function()
	if not check_dotnet() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("dotnet build")
end, { desc = icons.dev.Build .. " Build" })

--- Clean build artifacts with `dotnet clean`.
keys.lang_map("cs", "n", "<leader>lc", function()
	if not check_dotnet() then return end
	vim.cmd.split()
	vim.cmd.terminal("dotnet clean")
end, { desc = cs_icon .. " Clean" })

--- Start watch mode with hot-reload.
---
--- Runs `dotnet watch run` which automatically rebuilds and restarts
--- the application when source files change.
keys.lang_map("cs", "n", "<leader>lw", function()
	if not check_dotnet() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("dotnet watch run")
end, { desc = cs_icon .. " Watch run" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via `dotnet test`. Supports both full-suite and
-- single-method testing. Uses treesitter to detect the method name
-- under cursor for the `--filter` flag.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run all tests with `dotnet test`.
---
--- Saves the buffer, then runs the full test suite with normal verbosity.
keys.lang_map("cs", "n", "<leader>lt", function()
	if not check_dotnet() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("dotnet test --verbosity normal")
end, { desc = icons.dev.Test .. " Run tests" })

--- Run the test method under the cursor.
---
--- Uses treesitter to walk up the AST from the cursor position until
--- a `method_declaration` node is found, then extracts its name for
--- the `--filter` flag. Notifies the user if no test method is found.
keys.lang_map("cs", "n", "<leader>lT", function()
	if not check_dotnet() then return end
	vim.cmd("silent! write")

	---@type TSNode|nil
	local node = vim.treesitter.get_node()
	---@type string|nil
	local method_name = nil

	while node do
		if node:type() == "method_declaration" then
			local name_node = node:field("name")[1]
			if name_node then method_name = vim.treesitter.get_node_text(name_node, 0) end
			break
		end
		node = node:parent()
	end

	if method_name then
		vim.cmd.split()
		vim.cmd.terminal("dotnet test --filter " .. vim.fn.shellescape(method_name) .. " --verbosity normal")
	else
		vim.notify("No test method found under cursor", vim.log.levels.WARN, { title = ".NET" })
	end
end, { desc = icons.dev.Test .. " Test under cursor" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via nvim-dap and netcoredbg.
--
-- <leader>ld starts or continues a debug session. The adapter (coreclr)
-- is pre-configured by mason-nvim-dap when the debugger is installed.
-- Both <leader>ld (lang) and <leader>dc (core dap) work in C# files.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Saves the buffer, then calls `dap.continue()` which either resumes
--- a paused session or launches a new one using the coreclr adapter
--- (netcoredbg).
keys.lang_map("cs", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = ".NET" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (coreclr)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — NUGET
--
-- NuGet package management from within the editor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Add a NuGet package to the project.
---
--- Prompts for:
--- 1. Package name (required)
--- 2. Version (optional — defaults to latest)
---
--- Runs `dotnet add package <name> [--version <ver>]` in a terminal split.
keys.lang_map("cs", "n", "<leader>lp", function()
	if not check_dotnet() then return end
	vim.ui.input({ prompt = "Package name: " }, function(pkg)
		if not pkg or pkg == "" then return end
		vim.ui.input({ prompt = "Version (empty = latest): " }, function(ver)
			local cmd = "dotnet add package " .. vim.fn.shellescape(pkg)
			if ver and ver ~= "" then cmd = cmd .. " --version " .. vim.fn.shellescape(ver) end
			vim.cmd.split()
			vim.cmd.terminal(cmd)
		end)
	end)
end, { desc = icons.ui.Package .. " NuGet add package" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SOLUTION / PROJECT
--
-- Solution and project management utilities.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show solution or project information.
---
--- Behavior depends on `detect_project()` result:
--- • Solution found → `dotnet sln list` (lists projects in solution)
--- • Project found  → `dotnet list package` (lists NuGet dependencies)
--- • Neither        → notification
keys.lang_map("cs", "n", "<leader>ls", function()
	if not check_dotnet() then return end
	local proj, kind = detect_project()
	if kind == "sln" then
		vim.cmd.split()
		vim.cmd.terminal("dotnet sln list")
	elseif proj then
		vim.cmd.split()
		vim.cmd.terminal("dotnet list package")
	else
		vim.notify("No solution or project file found", vim.log.levels.INFO, { title = ".NET" })
	end
end, { desc = cs_icon .. " Solution info" })

--- Create a new project from a template.
---
--- Presents a picker with common .NET project templates:
--- • console, classlib, web, webapi, mvc, razor
--- • blazorserver, blazorwasm, worker
--- • mstest, xunit, nunit, grpc
---
--- Prompts for the project name after template selection.
keys.lang_map("cs", "n", "<leader>ln", function()
	if not check_dotnet() then return end

	---@type string[]
	local templates = {
		"console",
		"classlib",
		"web",
		"webapi",
		"mvc",
		"razor",
		"blazorserver",
		"blazorwasm",
		"worker",
		"mstest",
		"xunit",
		"nunit",
		"grpc",
	}

	vim.ui.select(templates, { prompt = cs_icon .. " Template:" }, function(template)
		if not template then return end
		vim.ui.input({ prompt = "Project name: " }, function(name)
			if not name or name == "" then return end
			vim.cmd.split()
			vim.cmd.terminal("dotnet new " .. template .. " -n " .. vim.fn.shellescape(name))
		end)
	end)
end, { desc = cs_icon .. " New project" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — ENTITY FRAMEWORK
--
-- Entity Framework Core migration management via a picker interface.
-- Requires the `dotnet-ef` global tool to be installed.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open an Entity Framework migrations picker.
---
--- Available actions:
--- • Add migration…          — prompts for migration name
--- • Update database         — apply pending migrations
--- • List migrations         — show all migrations
--- • Remove last migration   — undo the last migration
--- • Drop database           — drop with `--force`
--- • Generate SQL script     — output migration SQL
keys.lang_map("cs", "n", "<leader>le", function()
	if not check_dotnet() then return end

	---@type { name: string, prompt: boolean, cmd: string }[]
	local actions = {
		{ name = "Add migration…", prompt = true, cmd = "dotnet ef migrations add" },
		{ name = "Update database", prompt = false, cmd = "dotnet ef database update" },
		{ name = "List migrations", prompt = false, cmd = "dotnet ef migrations list" },
		{ name = "Remove last migration", prompt = false, cmd = "dotnet ef migrations remove" },
		{ name = "Drop database", prompt = false, cmd = "dotnet ef database drop --force" },
		{ name = "Generate SQL script", prompt = false, cmd = "dotnet ef migrations script" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = cs_icon .. " EF Migrations:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]
			if action.prompt then
				vim.ui.input({ prompt = "Migration name: " }, function(name)
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
end, { desc = icons.dev.Database .. " EF migrations" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to .NET project metadata and Microsoft documentation
-- without leaving the editor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show .NET project information in a notification.
---
--- Displays:
--- • Project file name and type (sln/csproj/fsproj)
--- • Current working directory
--- • .NET SDK version
--- • Number of installed runtimes
keys.lang_map("cs", "n", "<leader>li", function()
	if not check_dotnet() then return end
	local proj, kind = detect_project()

	---@type string[]
	local info = {
		cs_icon .. " .NET Project Info:",
		"",
		"  Project: " .. (proj and vim.fn.fnamemodify(proj, ":t") or "not found"),
		"  Type:    " .. (kind or "unknown"),
		"  CWD:     " .. vim.fn.getcwd(),
	}

	local sdk_info = vim.fn.system("dotnet --version 2>/dev/null"):gsub("%s+$", "")
	info[#info + 1] = "  SDK:     " .. sdk_info

	local runtime_info = vim.fn.system("dotnet --list-runtimes 2>/dev/null")
	---@type integer
	local runtimes = 0
	for _ in runtime_info:gmatch("[^\r\n]+") do
		runtimes = runtimes + 1
	end
	info[#info + 1] = "  Runtimes: " .. runtimes

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = ".NET" })
end, { desc = icons.diagnostics.Info .. " Project info" })

--- Open .NET documentation in the system browser.
---
--- Presents a picker with key reference pages:
--- • C# Reference       — language specification and guides
--- • .NET API Browser    — framework API documentation
--- • ASP.NET Core        — web framework documentation
--- • Entity Framework    — ORM documentation
--- • NuGet Gallery       — package registry
keys.lang_map("cs", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "C# Reference", url = "https://learn.microsoft.com/en-us/dotnet/csharp/" },
		{ name = ".NET API Browser", url = "https://learn.microsoft.com/en-us/dotnet/api/" },
		{ name = "ASP.NET Core", url = "https://learn.microsoft.com/en-us/aspnet/core/" },
		{ name = "Entity Framework", url = "https://learn.microsoft.com/en-us/ef/core/" },
		{ name = "NuGet Gallery", url = "https://www.nuget.org/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = cs_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the .NET-specific
-- parts (servers, formatters, linters, parsers, adapters).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for .NET                   │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig                         │ opts fn merge (omnisharp if dotnet available)│
-- │ mason.nvim                             │ opts fn merge (tools if dotnet available)    │
-- │ conform.nvim                           │ opts fn merge (csharpier if dotnet available)│
-- │ nvim-treesitter                        │ opts merge (c_sharp parser)                  │
-- │ neotest                                │ opts fn merge (neotest-dotnet adapter)       │
-- │ mason-nvim-dap                         │ opts merge (coreclr adapter)                 │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Several specs use `opts = function(_, opts)` instead of plain
-- tables because they guard on `vim.fn.executable("dotnet") == 1` to
-- avoid installing tools when the .NET SDK is not present.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for .NET
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- omnisharp: Roslyn-based C# language server providing completions,
	-- diagnostics, refactoring, go-to-definition, and Roslyn analyzers.
	-- Only configured if the dotnet CLI is available.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = function(_, opts)
			if vim.fn.executable("dotnet") == 1 then
				opts.servers = opts.servers or {}
				opts.servers.omnisharp = {
					settings = {
						FormattingOptions = {
							EnableEditorConfigSupport = true,
							OrganizeImports = true,
						},
						RoslynExtensionsOptions = {
							EnableAnalyzersSupport = true,
							EnableImportCompletion = true,
							AnalyzeOpenDocumentsOnly = true,
						},
					},
				}
			end
		end,
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					cs = "cs",
					csx = "cs",
					razor = "razor",
				},
				filename = {
					["global.json"] = "json",
					["nuget.config"] = "xml",
				},
				pattern = {
					[".*%.csproj$"] = "xml",
					[".*%.fsproj$"] = "xml",
					[".*%.sln$"] = "solution",
				},
			})

			-- ── Buffer-local options for C# files ────────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "cs" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120
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
	-- Ensures omnisharp, netcoredbg and csharpier are installed via Mason.
	-- Only extends ensure_installed if the dotnet CLI is available.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}
			if vim.fn.executable("dotnet") == 1 then
				vim.list_extend(opts.ensure_installed, {
					"omnisharp",
					"netcoredbg",
					"csharpier",
				})
			end
		end,
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- csharpier: opinionated C# formatter (similar to Prettier for C#).
	-- Uses `dotnet-csharpier --write-stdout` for stdin/stdout formatting.
	-- Only configured if the dotnet CLI is available.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = function(_, opts)
			if vim.fn.executable("dotnet") == 1 then
				opts.formatters_by_ft = opts.formatters_by_ft or {}
				opts.formatters_by_ft.cs = { "csharpier" }
				opts.formatters = opts.formatters or {}
				opts.formatters.csharpier = {
					command = "dotnet-csharpier",
					args = { "--write-stdout" },
				}
			end
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- c_sharp: syntax highlighting, folding, text objects, and indentation
	--          for C# source files.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"c_sharp",
			},
		},
	},

	-- ── NEOTEST (.NET adapter) ─────────────────────────────────────────────
	-- Integrates dotnet test with neotest for inline test results,
	-- diagnostics, and DAP-based test debugging.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-neotest/neotest",
		optional = true,
		dependencies = {
			"Issafalcon/neotest-dotnet",
		},
		opts = function(_, opts)
			opts.adapters = opts.adapters or {}
			opts.adapters[#opts.adapters + 1] = require("neotest-dotnet")({
				dap = { justMyCode = false },
			})
		end,
	},

	-- ── DAP — .NET DEBUGGER ────────────────────────────────────────────────
	-- mason-nvim-dap ensures the coreclr adapter (netcoredbg) is managed
	-- by Mason. After installation, all core DAP keymaps work in C# files.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "coreclr" },
		},
	},
}
