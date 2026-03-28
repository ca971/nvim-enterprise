---@file lua/langs/go.lua
---@description Go — LSP, formatter, linter, treesitter, DAP & buffer-local keymaps
---@module "langs.go"
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
--- ║  langs/go.lua — Go language support                                      ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("go") → {} if off           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "go"):                       │    ║
--- ║  │  ├─ LSP          gopls (completions, diagnostics, code lenses)   │    ║
--- ║  │  ├─ Formatter    goimports + gofumpt (via conform.nvim)          │    ║
--- ║  │  ├─ Linter       golangci-lint (via nvim-lint)                   │    ║
--- ║  │  ├─ Treesitter   go · gomod · gowork · gosum · gotmpl parsers    │    ║
--- ║  │  ├─ DAP          delve (via nvim-dap-go + Mason)                 │    ║
--- ║  │  └─ Extras       gomodifytags · impl · gotests · neotest-golang  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  go run               R  Run with arguments      │    ║
--- ║  │  ├─ BUILD     b  go build -v ./...                               │    ║
--- ║  │  ├─ TEST      t  go test (all)        T  Test under cursor       │    ║
--- ║  │  │            p  Benchmark            c  Coverage profile        │    ║
--- ║  │  ├─ DEBUG     d  Debug (delve)        D  Debug test (dap-go)     │    ║
--- ║  │  ├─ NAV       s  Switch test ↔ source                            │    ║
--- ║  │  ├─ TOOLS     e  go generate          x  go mod tidy             │    ║
--- ║  │  │            v  go vet               o  Organize imports        │    ║
--- ║  │  │            a  Add struct tags       A  Remove struct tags     │    ║
--- ║  │  │            f  Fill struct (gopls code action)                 │    ║
--- ║  │  └─ DOCS      i  go doc (under cursor) h  pkg.go.dev (browser)   │    ║
--- ║  │                                                                  │    ║
--- ║  │  DAP integration flow:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. nvim-dap-go loads on ft = "go"                       │    │    ║
--- ║  │  │  2. Configures dap.adapters.go → delve (Mason-installed) │    │    ║
--- ║  │  │  3. <leader>ld → dap.continue() (launch/attach)          │    │    ║
--- ║  │  │  4. <leader>lD → dap_go.debug_test() (test under cursor) │    │    ║
--- ║  │  │  5. All core DAP keymaps become active:                  │    │    ║
--- ║  │  │     <leader>dc · <leader>db · F5 · F9 · etc.             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  gopls features enabled:                                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  • gofumpt formatting (stricter than gofmt)              │    │    ║
--- ║  │  │  • Code lenses: gc_details, generate, test, tidy,        │    │    ║
--- ║  │  │    upgrade_dependency, vendor, run_govulncheck           │    │    ║
--- ║  │  │  • Inlay hints: variable types, literal fields, params   │    │    ║
--- ║  │  │  • Analyses: fieldalignment, nilness, shadow,            │    │    ║
--- ║  │  │    unusedparams, unusedwrite, useany                     │    │    ║
--- ║  │  │  • staticcheck integration                               │    │    ║
--- ║  │  │  • Semantic tokens                                       │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType go/gomod/gowork/gosum):             ║
--- ║  • colorcolumn=120, textwidth=120 (Go convention)                        ║
--- ║  • tabstop=4, shiftwidth=4        (Go standard: real tabs)               ║
--- ║  • expandtab=false                (TABS, not spaces — Go convention)     ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .go → go                                                              ║
--- ║  • .mod → gomod, .sum → gosum, .work → gowork                            ║
--- ║  • .tmpl → gotmpl                                                        ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Go support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("go") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Go Nerd Font icon (trailing whitespace stripped)
local go_icon = icons.lang.go:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Go buffers.
-- The group is buffer-local and only visible when filetype == "go".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("go", "Go", go_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN / BUILD
--
-- Go execution and build commands.
-- All keymaps save the buffer before execution.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current Go file with `go run`.
---
--- Saves the buffer, then executes the file in a terminal split.
keys.lang_map("go", "n", "<leader>lr", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("go run " .. vim.fn.shellescape(file))
end, { desc = icons.ui.Play .. " Run file" })

--- Run the current Go file with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then executes
--- `go run <file> <args>` in a terminal split. Aborts silently
--- if the user cancels the prompt.
keys.lang_map("go", "n", "<leader>lR", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal("go run " .. vim.fn.shellescape(file) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Build all packages with `go build -v ./...`.
---
--- Saves the buffer, then compiles all packages in the module.
--- The `-v` flag prints package names as they are compiled.
keys.lang_map("go", "n", "<leader>lb", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("go build -v ./...")
end, { desc = icons.dev.Build .. " Build" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via `go test`. Supports full-suite, single-function,
-- benchmark, and coverage testing. Uses treesitter to detect the test
-- function under cursor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run all tests in the module with `go test -v -race -count=1 ./...`.
---
--- Flags:
--- • `-v`       — verbose output (prints test names)
--- • `-race`    — enable race condition detector
--- • `-count=1` — disable test caching
keys.lang_map("go", "n", "<leader>lt", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("go test -v -race -count=1 ./...")
end, { desc = icons.dev.Test .. " Test all" })

--- Run the test function under the cursor.
---
--- Uses treesitter to walk up the AST from the cursor position until
--- a `function_declaration` node is found. Only matches functions
--- whose name starts with `Test`, `Benchmark`, or `Example` (Go
--- testing conventions). Falls back with a notification if no test
--- function is found.
keys.lang_map("go", "n", "<leader>lT", function()
	vim.cmd("silent! write")

	---@type TSNode|nil
	local node = vim.treesitter.get_node()
	---@type string|nil
	local func_name = nil

	while node do
		if node:type() == "function_declaration" then
			local name_node = node:field("name")[1]
			if name_node then
				local name = vim.treesitter.get_node_text(name_node, 0)
				if name:match("^Test") or name:match("^Benchmark") or name:match("^Example") then func_name = name end
			end
			break
		end
		node = node:parent()
	end

	if func_name then
		vim.cmd.split()
		vim.cmd.terminal("go test -v -run ^" .. func_name .. "$ " .. vim.fn.expand("%:p:h"))
	else
		vim.notify("No test function found under cursor", vim.log.levels.INFO, { title = "Go" })
	end
end, { desc = icons.dev.Test .. " Test under cursor" })

--- Run benchmark tests with `go test -bench=. -benchmem ./...`.
---
--- Executes all benchmark functions and includes memory allocation
--- statistics in the output.
keys.lang_map("go", "n", "<leader>lp", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("go test -bench=. -benchmem ./...")
end, { desc = icons.dev.Benchmark .. " Benchmark" })

--- Generate and display a test coverage profile.
---
--- Runs `go test -coverprofile` to collect coverage data, then
--- `go tool cover -func` to display per-function coverage percentages.
--- The coverage file is stored in a temporary location.
keys.lang_map("go", "n", "<leader>lc", function()
	vim.cmd("silent! write")
	local cover_file = vim.fn.tempname() .. ".cover"
	vim.cmd.split()
	vim.cmd.terminal(string.format("go test -coverprofile=%s ./... && go tool cover -func=%s", cover_file, cover_file))
end, { desc = icons.dev.Test .. " Coverage profile" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via nvim-dap and nvim-dap-go (delve).
--
-- <leader>ld starts or continues a debug session using the delve adapter.
-- <leader>lD debugs the test function under the cursor using dap-go's
-- test_method() which auto-detects the test name.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Saves the buffer, then calls `dap.continue()` which either resumes
--- a paused session or launches a new one using the delve adapter.
keys.lang_map("go", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Go" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (delve)" })

--- Debug the test function under the cursor.
---
--- Delegates to `dap-go.debug_test()` which auto-detects the
--- test function name and launches a delve debug session targeting
--- that specific test.
keys.lang_map("go", "n", "<leader>lD", function()
	vim.cmd("silent! write")
	local ok, dap_go = pcall(require, "dap-go")
	if not ok then
		vim.notify("dap-go not available", vim.log.levels.WARN, { title = "Go" })
		return
	end
	dap_go.debug_test()
end, { desc = icons.dev.Debug .. " Debug test" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — NAVIGATION
--
-- Quick file navigation between test and source files.
-- ═══════════════════════════════════════════════════════════════════════════

--- Switch between test and source files.
---
--- Heuristic:
--- • `*_test.go` → `*.go` (strip `_test` suffix)
--- • `*.go`      → `*_test.go` (add `_test` suffix)
---
--- Notifies the user if the target file does not exist.
keys.lang_map("go", "n", "<leader>ls", function()
	local file = vim.fn.expand("%:p")

	---@type string
	local target
	if file:match("_test%.go$") then
		target = file:gsub("_test%.go$", ".go")
	else
		target = file:gsub("%.go$", "_test.go")
	end

	if vim.fn.filereadable(target) == 1 then
		vim.cmd.edit(target)
	else
		vim.notify("File not found: " .. vim.fn.fnamemodify(target, ":t"), vim.log.levels.INFO, { title = "Go" })
	end
end, { desc = go_icon .. " Switch test ↔ source" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Go development utilities: code generation, module management,
-- vetting, import organization, struct tag manipulation, and
-- struct zero-value filling.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run `go generate ./...` to execute all `//go:generate` directives.
---
--- Saves the buffer before running.
keys.lang_map("go", "n", "<leader>le", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("go generate ./...")
end, { desc = go_icon .. " Generate" })

--- Run `go mod tidy` to clean up the module's dependency graph.
---
--- Adds missing dependencies and removes unused ones from `go.mod`
--- and `go.sum`.
keys.lang_map("go", "n", "<leader>lx", function()
	vim.cmd.split()
	vim.cmd.terminal("go mod tidy")
end, { desc = icons.ui.Refresh .. " Mod tidy" })

--- Run `go vet ./...` to report suspicious constructs.
---
--- Go vet examines source code for issues that the compiler may
--- not catch (printf format mismatches, unreachable code, etc.).
keys.lang_map("go", "n", "<leader>lv", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("go vet ./...")
end, { desc = go_icon .. " Vet" })

--- Organize imports via gopls code action.
---
--- Sends a synchronous `textDocument/codeAction` request to gopls
--- with `source.organizeImports` filter, then applies the workspace
--- edit to add missing imports and remove unused ones.
keys.lang_map("go", "n", "<leader>lo", function()
	local params = vim.lsp.util.make_range_params()
	params.context = { only = { "source.organizeImports" } }
	local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 3000)
	for _, res in pairs(result or {}) do
		for _, r in pairs(res.result or {}) do
			if r.edit then vim.lsp.util.apply_workspace_edit(r.edit, "utf-16") end
		end
	end
	vim.notify("Imports organized", vim.log.levels.INFO, { title = "Go" })
end, { desc = go_icon .. " Organize imports" })

--- Add struct tags using gomodifytags.
---
--- Presents a picker with common tag types:
--- • json, yaml, toml, xml, db, bson, mapstructure, json+yaml
---
--- Runs `gomodifytags -file <file> -line <line> -add-tags <tag>
--- -transform camelcase -w` on the current cursor line. Reloads
--- the buffer after modification.
---
--- Requires `gomodifytags` to be installed:
--- `go install github.com/fatih/gomodifytags@latest`
keys.lang_map("go", "n", "<leader>la", function()
	if vim.fn.executable("gomodifytags") ~= 1 then
		vim.notify("Install: go install github.com/fatih/gomodifytags@latest", vim.log.levels.WARN, { title = "Go" })
		return
	end

	---@type string[]
	local tags = { "json", "yaml", "toml", "xml", "db", "bson", "mapstructure", "json,yaml" }

	vim.ui.select(tags, { prompt = "Tag type:" }, function(tag)
		if not tag then return end
		local file = vim.fn.expand("%:p")
		local line = vim.api.nvim_win_get_cursor(0)[1]
		local cmd = string.format(
			"gomodifytags -file %s -line %d -add-tags %s -transform camelcase -w",
			vim.fn.shellescape(file),
			line,
			tag
		)
		vim.fn.system(cmd)
		vim.cmd.edit()
		vim.notify("Added " .. tag .. " tags", vim.log.levels.INFO, { title = "Go" })
	end)
end, { desc = go_icon .. " Add struct tags" })

--- Remove all struct tags from the struct at the current cursor line.
---
--- Runs `gomodifytags -file <file> -line <line> -clear-tags -w`.
--- Reloads the buffer after modification.
---
--- Requires `gomodifytags` to be installed.
keys.lang_map("go", "n", "<leader>lA", function()
	if vim.fn.executable("gomodifytags") ~= 1 then
		vim.notify("Install gomodifytags", vim.log.levels.WARN, { title = "Go" })
		return
	end
	local file = vim.fn.expand("%:p")
	local line = vim.api.nvim_win_get_cursor(0)[1]
	vim.fn.system(string.format("gomodifytags -file %s -line %d -clear-tags -w", vim.fn.shellescape(file), line))
	vim.cmd.edit()
	vim.notify("Tags removed", vim.log.levels.INFO, { title = "Go" })
end, { desc = go_icon .. " Remove struct tags" })

--- Fill a struct literal with zero values via gopls code action.
---
--- Sends a synchronous `textDocument/codeAction` request to gopls
--- with `refactor.rewrite` filter, then searches for a "fill"
--- action (e.g. "Fill struct" or "Fill switch"). Applies the edit
--- if found, otherwise notifies that no action is available.
keys.lang_map("go", "n", "<leader>lf", function()
	local params = vim.lsp.util.make_range_params()
	params.context = { only = { "refactor.rewrite" } }
	local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 3000)
	for _, res in pairs(result or {}) do
		for _, r in pairs(res.result or {}) do
			if r.title and r.title:match("[Ff]ill") then
				if r.edit then vim.lsp.util.apply_workspace_edit(r.edit, "utf-16") end
				vim.notify("Struct filled", vim.log.levels.INFO, { title = "Go" })
				return
			end
		end
	end
	vim.notify("No fill struct action available here", vim.log.levels.INFO, { title = "Go" })
end, { desc = go_icon .. " Fill struct" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to Go documentation via `go doc` and pkg.go.dev.
-- Supports contextual lookup for the word under cursor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show `go doc` output for the symbol under cursor.
---
--- Runs `go doc <word>` in a terminal split, displaying the
--- documentation for the identifier at the cursor position.
keys.lang_map("go", "n", "<leader>li", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("go doc " .. vim.fn.shellescape(word))
end, { desc = icons.diagnostics.Info .. " Go doc" })

--- Open Go documentation on pkg.go.dev in the system browser.
---
--- If the cursor is on a word, searches pkg.go.dev for that term.
--- Otherwise opens the Go standard library index.
keys.lang_map("go", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word ~= "" then
		vim.ui.open("https://pkg.go.dev/search?q=" .. word)
	else
		vim.ui.open("https://pkg.go.dev/std")
	end
end, { desc = icons.ui.Note .. " Go docs (pkg.go.dev)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Go-specific alignment presets for mini.align:
-- • go_struct      — align struct field declarations on whitespace
-- • go_struct_tags — align struct tags on backtick delimiter
-- • go_map         — align map literal entries on ":"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("go") then
		---@type string Alignment preset icon from icons.app
		local align_icon = icons.app.Go

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			go_struct = {
				description = "Align Go struct field declarations",
				icon = align_icon,
				split_pattern = "%s+",
				category = "domain",
				lang = "go",
				filetypes = { "go", "gomod", "gowork" },
			},
			go_struct_tags = {
				description = "Align Go struct tags on backtick",
				icon = align_icon,
				split_pattern = "%s+`",
				category = "domain",
				lang = "go",
				filetypes = { "go" },
			},
			go_map = {
				description = "Align Go map literal entries on ':'",
				icon = align_icon,
				split_pattern = ":",
				category = "domain",
				lang = "go",
				filetypes = { "go" },
			},
		})

		-- ── Set default filetype mappings ────────────────────────────
		align_registry.set_ft_mapping("go", "go_struct")
		align_registry.set_ft_mapping("gomod", "go_struct")
		align_registry.mark_language_loaded("go")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map({ "go", "gomod", "gowork" }, { "n", "x" }, "<leader>aL", align_registry.make_align_fn("go_struct"), {
			desc = align_icon .. "  Align Go struct",
		})
		keys.lang_map(
			{ "go", "gomod", "gowork" },
			{ "n", "x" },
			"<leader>aT",
			align_registry.make_align_fn("go_struct_tags"),
			{
				desc = align_icon .. "  Align Go tags",
			}
		)
		keys.lang_map({ "go", "gomod", "gowork" }, { "n", "x" }, "<leader>aM", align_registry.make_align_fn("go_map"), {
			desc = align_icon .. "  Align Go map",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Go-specific
-- parts (servers, formatters, linters, parsers, adapters).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Go                     │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig                         │ opts merge (gopls server added on require)   │
-- │ mason.nvim                             │ opts merge (8 tools added to ensure_installed│
-- │ conform.nvim                           │ opts merge (goimports + gofumpt for ft go)   │
-- │ nvim-lint                              │ opts merge (golangcilint for ft go)          │
-- │ nvim-treesitter                        │ opts merge (5 parsers added)                 │
-- │ neotest                                │ opts fn merge (neotest-golang adapter)       │
-- │ nvim-dap-go                            │ ft = "go" (true lazy load)                   │
-- │ mason-nvim-dap                         │ opts merge (delve adapter)                   │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Go
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- gopls: the official Go language server providing completions,
	-- diagnostics, code lenses, inlay hints, semantic tokens, and
	-- staticcheck integration.
	--
	-- Configuration highlights:
	-- • gofumpt = true           — stricter formatting than gofmt
	-- • codelenses (all enabled) — gc_details, generate, test, tidy, etc.
	-- • inlay hints (all)        — variable types, params, constants
	-- • analyses (all)           — fieldalignment, nilness, shadow, etc.
	-- • staticcheck = true       — additional static analysis checks
	-- • semanticTokens = true    — enhanced syntax highlighting
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				gopls = {
					settings = {
						gopls = {
							gofumpt = true,
							codelenses = {
								gc_details = true,
								generate = true,
								regenerate_cgo = true,
								run_govulncheck = true,
								test = true,
								tidy = true,
								upgrade_dependency = true,
								vendor = true,
							},
							hints = {
								assignVariableTypes = true,
								compositeLiteralFields = true,
								compositeLiteralTypes = true,
								constantValues = true,
								functionTypeParameters = true,
								parameterNames = true,
								rangeVariableTypes = true,
							},
							analyses = {
								fieldalignment = true,
								nilness = true,
								unusedparams = true,
								unusedwrite = true,
								useany = true,
								shadow = true,
							},
							usePlaceholders = true,
							completeUnimported = true,
							staticcheck = true,
							directoryFilters = {
								"-.git",
								"-.vscode",
								"-.idea",
								"-.venv",
								"-node_modules",
							},
							semanticTokens = true,
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					go = "go",
					mod = "gomod",
					sum = "gosum",
					work = "gowork",
					tmpl = "gotmpl",
				},
			})

			-- ── Buffer-local options for Go files ────────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "go", "gomod", "gowork", "gosum" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120
					opt.tabstop = 4
					opt.shiftwidth = 4
					opt.softtabstop = 4
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

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures the complete Go toolchain is installed via Mason:
	-- • gopls          — language server
	-- • gofumpt        — stricter formatter (superset of gofmt)
	-- • goimports      — auto-import organizer
	-- • golangci-lint  — meta-linter (runs 50+ linters)
	-- • delve          — debugger (DAP adapter)
	-- • gomodifytags   — struct tag manipulation
	-- • impl           — interface implementation generator
	-- • gotests         — test generation from functions
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"gopls",
				"gofumpt",
				"goimports",
				"golangci-lint",
				"delve",
				"gomodifytags",
				"impl",
				"gotests",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- goimports: organizes imports (adds missing, removes unused)
	-- gofumpt:  stricter formatting rules on top of gofmt
	-- Both run sequentially — imports first, then formatting.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				go = { "goimports", "gofumpt" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- golangci-lint: meta-linter that runs 50+ Go linters in parallel.
	-- Configured via .golangci.yml in the project root.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				go = { "golangcilint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- go:     syntax highlighting, folding, text objects for Go source
	-- gomod:  go.mod dependency files
	-- gowork: go.work workspace files
	-- gosum:  go.sum checksum files
	-- gotmpl: Go template files (html/template, text/template)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"go",
				"gomod",
				"gowork",
				"gosum",
				"gotmpl",
			},
		},
	},

	-- ── NEOTEST (Go adapter) ───────────────────────────────────────────────
	-- Integrates `go test` with neotest for inline test results,
	-- diagnostics, and DAP-based test debugging.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-neotest/neotest",
		optional = true,
		dependencies = {
			"fredrikaverpil/neotest-golang",
		},
		opts = function(_, opts)
			opts.adapters = opts.adapters or {}
			opts.adapters[#opts.adapters + 1] = require("neotest-golang")({
				dap_go_enabled = true,
			})
		end,
	},

	-- ── DAP — GO DEBUGGER ──────────────────────────────────────────────────
	-- nvim-dap-go configures:
	--   • dap.adapters.go → delve (Mason-installed)
	--   • dap.configurations.go → default launch configs
	--   • debug_test() for test-under-cursor debugging
	-- ───────────────────────────────────────────────────────────────────────
	{
		"leoluz/nvim-dap-go",
		ft = "go",
		dependencies = { "mfussenegger/nvim-dap" },
		config = function()
			require("dap-go").setup()
		end,
	},

	-- ── MASON-NVIM-DAP (adapter auto-install) ──────────────────────────────
	-- Ensures the delve DAP adapter is managed by Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "delve" },
		},
	},

	-- ── NEOTEST (Go adapter) ──────────────────────────────────────────
	{
		"nvim-neotest/neotest",
		optional = true,
		dependencies = {
			{ "nvim-neotest/neotest-go", lazy = true },
		},
		opts = function(_, opts)
			opts.adapters = opts.adapters or {}
			table.insert(
				opts.adapters,
				require("neotest-go")({
					recursive_run = true,
					args = { "-count=1", "-race" },
				})
			)
		end,
	},
}
