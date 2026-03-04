---@file lua/langs/java.lua
---@description Java — LSP (jdtls), formatter, linter, treesitter, DAP & buffer-local keymaps
---@module "langs.java"
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
--- ║  langs/java.lua — Java language support                                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("java") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "java"):                     │    ║
--- ║  │  ├─ LSP          jdtls  (via nvim-jdtls, NOT lspconfig)          │    ║
--- ║  │  │               Full IDE: completion, refactoring, imports      │    ║
--- ║  │  ├─ Formatter    google-java-format (conform.nvim)               │    ║
--- ║  │  ├─ Linter       checkstyle (nvim-lint)                          │    ║
--- ║  │  ├─ Treesitter   java · groovy parsers                           │    ║
--- ║  │  ├─ DAP          java-debug-adapter + java-test (via jdtls)      │    ║
--- ║  │  └─ Extras       nvim-jdtls (enhanced Java IDE support)          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file/project     b  Build project           │    ║
--- ║  │  ├─ TEST      t  Run tests            T  Test method (cursor)    │    ║
--- ║  │  ├─ DEBUG     d  Debug (jdtls/DAP)                               │    ║
--- ║  │  ├─ REPL      c  jshell REPL (JDK 9+)                            │    ║
--- ║  │  ├─ TOOLS     o  Organize imports     e  Extract variable        │    ║
--- ║  │  │            e  Extract method (v)    s  Switch test ↔ source   │    ║
--- ║  │  │            x  Clean project                                   │    ║
--- ║  │  ├─ DOCS      i  Class info (hover)   h  Javadoc browser         │    ║
--- ║  │  └─ BUILD     m  → Build tool sub-group                          │    ║
--- ║  │                 mb  Build              mc  Clean                 │    ║
--- ║  │                 mt  Test               mr  Run                   │    ║
--- ║  │                 md  Dependencies       mp  Package               │    ║
--- ║  │                                                                  │    ║
--- ║  │  DAP integration flow:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. nvim-jdtls loads on ft = "java"                      │    │    ║
--- ║  │  │  2. jdtls LSP starts with java-debug-adapter bundle      │    │    ║
--- ║  │  │  3. DAP adapter auto-registered by jdtls                 │    │    ║
--- ║  │  │  4. Available debug commands:                            │    │    ║
--- ║  │  │     • jdtls.test_class()          debug test class       │    │    ║
--- ║  │  │     • jdtls.test_nearest_method() debug test at cursor   │    │    ║
--- ║  │  │     • dap.continue()              standard DAP launch    │    │    ║
--- ║  │  │  5. All core DAP keymaps become active:                  │    │    ║
--- ║  │  │     <leader>dc · <leader>db · F5 · F9 · etc.             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType java):                              ║
--- ║  • colorcolumn=120                (Google Java Style line length)        ║
--- ║  • tabstop=4, shiftwidth=4        (Java standard indentation)            ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Build tool detection:                                                   ║
--- ║  • build.gradle / build.gradle.kts  → Gradle (prefers ./gradlew)         ║
--- ║  • pom.xml                          → Maven  (prefers ./mvnw)            ║
--- ║  • Neither                          → single-file javac + java           ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .jav                  → java                                          ║
--- ║  • settings.gradle       → groovy                                        ║
--- ║  • settings.gradle.kts   → kotlin                                        ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Java support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("java") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Java Nerd Font icon (trailing whitespace stripped)
local java_icon = icons.lang.java:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Java buffers.
-- The group is buffer-local and only visible when filetype == "java".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("java", "Java", java_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Build tool detection, command generation, and notification utilities.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the build tool used by the current project.
---
--- Resolution order:
--- 1. `build.gradle` / `build.gradle.kts` → `"gradle"`
--- 2. `pom.xml`                           → `"maven"`
--- 3. Neither                             → `nil`
---
--- ```lua
--- local tool = get_build_tool()
--- if tool == "gradle" then ... end
--- ```
---
---@return "gradle"|"maven"|nil tool Build tool identifier, or `nil` if none found
---@private
local function get_build_tool()
	if vim.fn.filereadable("build.gradle") == 1 or vim.fn.filereadable("build.gradle.kts") == 1 then return "gradle" end
	if vim.fn.filereadable("pom.xml") == 1 then return "maven" end
	return nil
end

--- Generate a build tool command for the given action.
---
--- Supports both Gradle and Maven with wrapper detection:
--- - Gradle: prefers `./gradlew` over system `gradle`
--- - Maven:  prefers `./mvnw` over system `mvn`
---
--- Action mapping:
--- ┌──────────┬───────────────────┬────────────────────┐
--- │ Action   │ Gradle            │ Maven              │
--- ├──────────┼───────────────────┼────────────────────┤
--- │ build    │ build             │ compile            │
--- │ clean    │ clean             │ clean              │
--- │ test     │ test              │ test               │
--- │ run      │ run               │ exec:java          │
--- │ package  │ jar               │ package            │
--- │ deps     │ dependencies      │ dependency:tree    │
--- └──────────┴───────────────────┴────────────────────┘
---
--- ```lua
--- local cmd = get_build_cmd("build")
--- if cmd then vim.cmd.terminal(cmd) end
--- ```
---
---@param action string Build action key (e.g. `"build"`, `"clean"`, `"test"`)
---@return string|nil cmd Full command string, or `nil` if no build tool found
---@private
local function get_build_cmd(action)
	local tool = get_build_tool()

	if tool == "gradle" then
		---@type string
		local wrapper = vim.fn.filereadable("gradlew") == 1 and "./gradlew" or "gradle"
		---@type table<string, string>
		local map = {
			build = "build",
			clean = "clean",
			test = "test",
			run = "run",
			package = "jar",
			deps = "dependencies",
		}
		return wrapper .. " " .. (map[action] or action)
	elseif tool == "maven" then
		---@type string
		local wrapper = vim.fn.filereadable("mvnw") == 1 and "./mvnw" or "mvn"
		---@type table<string, string>
		local map = {
			build = "compile",
			clean = "clean",
			test = "test",
			run = "exec:java",
			package = "package",
			deps = "dependency:tree",
		}
		return wrapper .. " " .. (map[action] or action)
	end

	return nil
end

--- Notify the user that no build tool was detected.
---
--- Centralizes the warning notification to avoid repetition across
--- all keymaps that require a build tool (Gradle or Maven).
---
---@return nil
---@private
local function notify_no_build_tool()
	vim.notify("No build tool found (gradle/maven)", vim.log.levels.WARN, { title = "Java" })
end

--- Execute a build tool action in a terminal split.
---
--- Resolves the command via `get_build_cmd()`, opens a horizontal
--- split with a terminal, and runs the command. If no build tool
--- is found, either calls the optional fallback function or
--- displays a warning notification.
---
--- ```lua
--- run_build_action("build")                        -- build or notify
--- run_build_action("run", function()               -- run with fallback
---     vim.cmd.terminal("javac " .. file)
--- end)
--- ```
---
---@param action string Build action key (e.g. `"build"`, `"test"`)
---@param fallback? fun() Optional function to call when no build tool is found
---@return nil
---@private
local function run_build_action(action, fallback)
	local cmd = get_build_cmd(action)
	if cmd then
		vim.cmd.split()
		vim.cmd.terminal(cmd)
	elseif fallback then
		fallback()
	else
		notify_no_build_tool()
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN & BUILD
--
-- Project execution and compilation. Automatically detects the build
-- tool (Gradle/Maven) and falls back to single-file javac+java for
-- standalone files without a build system.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current Java project or file.
---
--- With a build tool: delegates to `gradle run` or `mvn exec:java`.
--- Without: compiles the current file with `javac` and executes
--- the resulting class in a terminal split.
keys.lang_map("java", "n", "<leader>lr", function()
	vim.cmd("silent! write")
	run_build_action("run", function()
		local classname = vim.fn.expand("%:t:r")
		local dir = vim.fn.expand("%:p:h")
		vim.cmd.split()
		vim.cmd.terminal(
			string.format(
				"cd %s && javac %s && java %s",
				vim.fn.shellescape(dir),
				vim.fn.shellescape(vim.fn.expand("%:t")),
				classname
			)
		)
	end)
end, { desc = icons.ui.Play .. " Run" })

--- Build the project using the detected build tool.
---
--- Delegates to `gradle build` or `mvn compile`. Notifies if
--- no build tool is found in the project root.
keys.lang_map("java", "n", "<leader>lb", function()
	vim.cmd("silent! write")
	run_build_action("build")
end, { desc = icons.dev.Build .. " Build" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via build tool integration and jdtls.
-- Supports both full-suite testing and single-method testing.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite via the build tool.
---
--- Delegates to `gradle test` or `mvn test`. Notifies if no
--- build tool is found.
keys.lang_map("java", "n", "<leader>lt", function()
	vim.cmd("silent! write")
	run_build_action("test")
end, { desc = icons.dev.Test .. " Run tests" })

--- Run the test method nearest to the cursor.
---
--- Delegates to `jdtls.test_nearest_method()` which uses the
--- jdtls LSP to identify the test method at the cursor position
--- and execute it via the configured test runner (JUnit/TestNG).
--- Falls back to a notification if nvim-jdtls is not loaded.
keys.lang_map("java", "n", "<leader>lT", function()
	vim.cmd("silent! write")
	local ok, jdtls = pcall(require, "jdtls")
	if ok then
		jdtls.test_nearest_method()
	else
		vim.notify("nvim-jdtls not loaded", vim.log.levels.WARN, { title = "Java" })
	end
end, { desc = icons.dev.Test .. " Test method" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via nvim-jdtls and java-debug-adapter.
--
-- <leader>ld starts a debug session. Prefers jdtls.test_class() which
-- uses the java-debug-adapter bundle for full stepping. Falls back
-- to standard dap.continue() if jdtls is unavailable.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start a DAP debug session for the current class.
---
--- Strategy:
--- 1. If nvim-jdtls is loaded → `jdtls.test_class()` (full debug with
---    java-debug-adapter, supports breakpoints, stepping, evaluation)
--- 2. Fallback → `dap.continue()` (standard DAP, requires manual
---    adapter configuration)
--- 3. Neither available → notification
keys.lang_map("java", "n", "<leader>ld", function()
	local ok, jdtls = pcall(require, "jdtls")
	if ok then
		jdtls.test_class()
	else
		local dap_ok, dap = pcall(require, "dap")
		if dap_ok then
			dap.continue()
		else
			vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Java" })
		end
	end
end, { desc = icons.dev.Debug .. " Debug" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
--
-- Opens JShell (JDK 9+) in a terminal split for interactive
-- Java expression evaluation and prototyping.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a JShell REPL in a terminal split.
---
--- JShell (introduced in JDK 9) provides an interactive Java shell
--- for evaluating expressions, testing snippets, and exploring APIs
--- without creating a full project.
---
--- Notifies the user if `jshell` is not found (JDK < 9 or not in PATH).
keys.lang_map("java", "n", "<leader>lc", function()
	if vim.fn.executable("jshell") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("jshell")
	else
		vim.notify("jshell not found (requires JDK 9+)", vim.log.levels.WARN, { title = "Java" })
	end
end, { desc = icons.ui.Terminal .. " REPL (jshell)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- IDE-like refactoring and project utilities:
-- • Import organization (jdtls or LSP code action fallback)
-- • Variable/method extraction (jdtls or LSP code action fallback)
-- • Test ↔ source file switching (Maven/Gradle convention)
-- • Project cleaning via build tool
-- ═══════════════════════════════════════════════════════════════════════════

--- Organize imports in the current buffer.
---
--- Strategy:
--- 1. If nvim-jdtls is loaded → `jdtls.organize_imports()` (precise,
---    handles star imports, static imports ordering)
--- 2. Fallback → LSP `source.organizeImports` code action
keys.lang_map("java", "n", "<leader>lo", function()
	local ok, jdtls = pcall(require, "jdtls")
	if ok then
		jdtls.organize_imports()
	else
		local params = vim.lsp.util.make_range_params()
		params.context = { only = { "source.organizeImports" } }
		vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 3000)
	end
end, { desc = java_icon .. " Organize imports" })

--- Extract the expression under cursor into a local variable.
---
--- Delegates to `jdtls.extract_variable()` for precise AST-aware
--- extraction. Falls back to generic LSP code action if jdtls
--- is unavailable.
keys.lang_map("java", "n", "<leader>le", function()
	local ok, jdtls = pcall(require, "jdtls")
	if ok then
		jdtls.extract_variable()
	else
		vim.lsp.buf.code_action()
	end
end, { desc = java_icon .. " Extract variable" })

--- Extract the visual selection into a new method.
---
--- Delegates to `jdtls.extract_method(true)` for AST-aware method
--- extraction with automatic parameter detection. Falls back to
--- generic LSP code action if jdtls is unavailable.
keys.lang_map("java", "v", "<leader>le", function()
	local ok, jdtls = pcall(require, "jdtls")
	if ok then
		jdtls.extract_method(true)
	else
		vim.lsp.buf.code_action()
	end
end, { desc = java_icon .. " Extract method" })

--- Switch between test and source files.
---
--- Follows Maven/Gradle conventional directory layout:
--- - `src/main/java/…/Foo.java` ↔ `src/test/java/…/FooTest.java`
---
--- Handles both directions:
--- - From source → appends `Test` suffix, swaps `src/main/` → `src/test/`
--- - From test   → removes `Test` suffix, swaps `src/test/` → `src/main/`
---
--- Notifies if the target file does not exist.
keys.lang_map("java", "n", "<leader>ls", function()
	local file = vim.fn.expand("%:p")

	---@type string
	local target
	if file:match("Test%.java$") then
		target = file:gsub("Test%.java$", ".java"):gsub("src/test/", "src/main/")
	else
		target = file:gsub("%.java$", "Test.java"):gsub("src/main/", "src/test/")
	end

	if vim.fn.filereadable(target) == 1 then
		vim.cmd.edit(target)
	else
		vim.notify("File not found: " .. vim.fn.fnamemodify(target, ":t"), vim.log.levels.INFO, { title = "Java" })
	end
end, { desc = java_icon .. " Switch test ↔ source" })

--- Clean the project using the detected build tool.
---
--- Delegates to `gradle clean` or `mvn clean`. Notifies the user
--- if no build tool is found.
keys.lang_map("java", "n", "<leader>lx", function()
	run_build_action("clean")
end, { desc = icons.ui.Close .. " Clean project" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to class metadata (LSP hover) and Oracle Javadoc
-- documentation without leaving the editor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show class/method info via LSP hover.
---
--- Displays the signature, documentation, and type information
--- for the symbol under the cursor in a floating window.
keys.lang_map("java", "n", "<leader>li", function()
	vim.lsp.buf.hover()
end, { desc = icons.diagnostics.Info .. " Class info" })

--- Open Oracle Javadoc for the word under cursor.
---
--- Attempts to open the JDK 21 API documentation for the class
--- name under the cursor. Defaults to `java.lang.*` package path.
--- If the cursor is on an empty word, opens the API index page.
---
--- NOTE: This heuristic only works for `java.lang` classes.
--- For other packages, use the LSP hover or external doc tools.
keys.lang_map("java", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word ~= "" then
		vim.ui.open("https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/" .. word .. ".html")
	else
		vim.ui.open("https://docs.oracle.com/en/java/javase/21/docs/api/")
	end
end, { desc = icons.ui.Note .. " Javadoc" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — BUILD TOOL SUB-GROUP
--
-- Dedicated sub-menu under <leader>lm for granular build tool actions.
-- Provides direct access to build, clean, test, run, dependency tree,
-- and package operations without remembering CLI syntax.
--
-- All commands auto-detect Gradle vs Maven and prefer wrappers
-- (./gradlew, ./mvnw) when available.
-- ═══════════════════════════════════════════════════════════════════════════

--- Register the build tool sub-group placeholder for which-key.
---
--- This no-op keymap exists solely to create a labeled group in
--- which-key's popup menu under `<leader>lm`.
keys.lang_map("java", "n", "<leader>lm", function() end, {
	desc = icons.ui.Gear .. " Build tool",
})

--- Build tool sub-actions mapped under `<leader>lm<key>`.
---
--- Each entry generates a keymap that delegates to `run_build_action()`
--- with the corresponding build action key.
---
---@type { key: string, action: string, desc: string }[]
local build_actions = {
	{ key = "b", action = "build", desc = icons.dev.Build .. " Build" },
	{ key = "c", action = "clean", desc = icons.ui.Close .. " Clean" },
	{ key = "t", action = "test", desc = icons.dev.Test .. " Test" },
	{ key = "r", action = "run", desc = icons.ui.Play .. " Run" },
	{ key = "d", action = "deps", desc = icons.ui.List .. " Dependencies" },
	{ key = "p", action = "package", desc = icons.ui.Package .. " Package" },
}

for _, ba in ipairs(build_actions) do
	keys.lang_map("java", "n", "<leader>lm" .. ba.key, function()
		run_build_action(ba.action)
	end, { desc = ba.desc })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Java-specific alignment presets for mini.align:
-- • java_fields — align field declarations on whitespace
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("java") then
		---@type string Alignment preset icon from icons.app
		local java_align_icon = icons.app.Java

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			java_fields = {
				description = "Align Java field declarations",
				icon = java_align_icon,
				split_pattern = "%s+",
				category = "jvm",
				lang = "java",
				filetypes = { "java" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("java", "java_fields")
		align_registry.mark_language_loaded("java")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("java", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("java_fields"), {
			desc = java_align_icon .. "  Align Java fields",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Java-specific
-- parts (servers, formatters, linters, parsers, adapters).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Java                   │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-jdtls         │ ft = "java" (true lazy load, manages LSP)    │
-- │ nvim-lspconfig     │ NOT used for Java (jdtls manages itself)     │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.java)           │
-- │ nvim-lint          │ opts merge (linters_by_ft.java)              │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Unlike most languages, Java LSP is NOT configured via
-- nvim-lspconfig. The nvim-jdtls plugin handles jdtls setup
-- directly, providing enhanced features (code actions, refactoring,
-- DAP integration) that the generic lspconfig wrapper cannot.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Java
return {
	-- ── JDTLS (Java LSP + DAP) ────────────────────────────────────────────
	-- nvim-jdtls manages the entire jdtls lifecycle:
	--   • LSP server start/stop/restart
	--   • java-debug-adapter integration (DAP)
	--   • java-test integration (test runner)
	--   • Code actions: organize imports, extract method/variable
	--   • Workspace folder management
	--
	-- Loaded exclusively on ft = "java" — zero cost for non-Java sessions.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-jdtls",
		ft = { "java" },
		dependencies = {
			"mfussenegger/nvim-dap",
		},
	},

	-- ── LSPCONFIG (buffer options only) ────────────────────────────────────
	-- jdtls is NOT configured here — nvim-jdtls handles that.
	-- This spec only registers:
	--   • Filetype extensions (e.g. .jav → java)
	--   • Buffer-local options via FileType autocmd
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					jav = "java",
				},
				filename = {
					["settings.gradle"] = "groovy",
					["settings.gradle.kts"] = "kotlin",
				},
			})

			-- ── Buffer-local options for Java files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "java" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "120"
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
	-- Ensures all Java tooling is installed via Mason:
	--   • jdtls               — Java LSP server
	--   • java-debug-adapter  — DAP adapter for Java debugging
	--   • java-test           — JUnit/TestNG test runner integration
	--   • google-java-format  — opinionated Java formatter
	--   • checkstyle          — static analysis / linter
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"jdtls",
				"java-debug-adapter",
				"java-test",
				"google-java-format",
				"checkstyle",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- google-java-format: Google's opinionated Java formatter.
	-- Enforces the Google Java Style Guide (2-space indent, 100-char lines).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				java = { "google-java-format" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- checkstyle: static analysis tool that checks Java code against
	-- coding standards (Google Style, Sun conventions, or custom rules).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				java = { "checkstyle" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- java:   syntax highlighting, folding, text objects, indentation
	-- groovy: build.gradle syntax support
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"java",
				"groovy",
			},
		},
	},
}
