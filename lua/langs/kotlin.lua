---@file lua/langs/kotlin.lua
---@description Kotlin — LSP, formatter, linter, treesitter & buffer-local keymaps
---@module "langs.kotlin"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.java               Java language support (shared JVM ecosystem)
---@see langs.python             Python language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/kotlin.lua — Kotlin language support                              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("kotlin") → {} if off       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "kotlin"):                   │    ║
--- ║  │  ├─ LSP          kotlin_language_server (JetBrains)              │    ║
--- ║  │  │               Completions, diagnostics, go-to-def, refactor   │    ║
--- ║  │  ├─ Formatter    ktlint (conform.nvim)                           │    ║
--- ║  │  ├─ Linter       ktlint (nvim-lint)                              │    ║
--- ║  │  ├─ Treesitter   kotlin parser                                   │    ║
--- ║  │  └─ Debug        Gradle --debug-jvm (JVM remote debug)           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run (gradle/kotlinc)  R  Run with arguments     │    ║
--- ║  │  ├─ BUILD     b  Build (gradle/maven)                            │    ║
--- ║  │  ├─ TEST      t  Test (gradle/maven)   T  Test under cursor      │    ║
--- ║  │  ├─ DEBUG     d  Debug (--debug-jvm)                             │    ║
--- ║  │  ├─ REPL      c  Kotlin REPL (kotlinc)                           │    ║
--- ║  │  ├─ TOOLS     l  Lint (ktlint)          s  Format (ktlint -F)    │    ║
--- ║  │  │            g  Gradle commands picker                          │    ║
--- ║  │  └─ DOCS      i  Project info           h  Documentation picker  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Build system detection:                                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. build.gradle / build.gradle.kts  → "gradle"          │    │    ║
--- ║  │  │     Prefers ./gradlew wrapper when available             │    │    ║
--- ║  │  │  2. pom.xml                          → "maven"           │    │    ║
--- ║  │  │  3. kotlinc in $PATH                 → "kotlinc"         │    │    ║
--- ║  │  │     Single-file compile + run                            │    │    ║
--- ║  │  │  4. None                             → nil (warn user)   │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Gradle commands picker:                                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  build · clean · clean build · test · run                │    │    ║
--- ║  │  │  jar · shadowJar · dependencies · tasks                  │    │    ║
--- ║  │  │  check · assemble · publish · custom…                    │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType kotlin):                            ║
--- ║  • colorcolumn=120, textwidth=120  (Kotlin coding conventions)           ║
--- ║  • tabstop=4, shiftwidth=4         (Kotlin standard indentation)         ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="// %s"           (Kotlin single-line comment)          ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .kt, .kts            → kotlin                                         ║
--- ║  • build.gradle.kts     → kotlin                                         ║
--- ║  • settings.gradle.kts  → kotlin                                         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Kotlin support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("kotlin") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Kotlin Nerd Font icon (trailing whitespace stripped)
local kt_icon = icons.lang.kotlin:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Kotlin buffers.
-- The group is buffer-local and only visible when filetype == "kotlin".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("kotlin", "Kotlin", kt_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Build system detection, Gradle wrapper resolution, and command
-- execution utilities. All functions are module-local and not
-- exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the build system used by the current project.
---
--- Resolution order:
--- 1. `build.gradle` / `build.gradle.kts` → `"gradle"`
--- 2. `pom.xml`                           → `"maven"`
--- 3. `kotlinc` in `$PATH`               → `"kotlinc"` (single-file mode)
--- 4. None                                → `nil`
---
--- ```lua
--- local build = detect_build()
--- if build == "gradle" then ... end
--- ```
---
---@return "gradle"|"maven"|"kotlinc"|nil build Build system identifier
---@private
local function detect_build()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/build.gradle.kts") == 1
		or vim.fn.filereadable(cwd .. "/build.gradle") == 1
	then
		return "gradle"
	elseif vim.fn.filereadable(cwd .. "/pom.xml") == 1 then
		return "maven"
	elseif vim.fn.executable("kotlinc") == 1 then
		return "kotlinc"
	end
	return nil
end

--- Get the Gradle command, preferring the project wrapper.
---
--- Resolution order:
--- 1. `./gradlew` — project-local Gradle wrapper (pinned version)
--- 2. `gradle`    — system-wide Gradle installation
---
--- ```lua
--- local gc = gradle_cmd()   --> "./gradlew" or "gradle"
--- ```
---
---@return string cmd Gradle executable path or command name
---@private
local function gradle_cmd()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/gradlew") == 1 then
		return "./gradlew"
	end
	return "gradle"
end

--- Notify the user that no build system was detected.
---
--- Centralizes the warning notification to avoid repetition across
--- all keymaps that require a build system.
---
---@param context? string Additional context for the message (e.g. `"gradle, kotlinc"`)
---@return nil
---@private
local function notify_no_build(context)
	local tools = context or "gradle, maven, kotlinc"
	vim.notify(
		"No build system found (" .. tools .. ")",
		vim.log.levels.WARN,
		{ title = "Kotlin" }
	)
end

--- Run a Gradle task in a terminal split.
---
--- Resolves the Gradle command via `gradle_cmd()`, opens a horizontal
--- split, and runs the task. Used by keymaps and the Gradle commands
--- picker to avoid code duplication.
---
--- ```lua
--- run_gradle("build")           --> "./gradlew build"
--- run_gradle("test --tests 'Foo'")
--- ```
---
---@param task string Gradle task and arguments (e.g. `"build"`, `"test"`, `"run --args='foo'"`)
---@return nil
---@private
local function run_gradle(task)
	vim.cmd.split()
	vim.cmd.terminal(gradle_cmd() .. " " .. task)
end

--- Compile and run a single Kotlin file using kotlinc.
---
--- Compiles the file to a JAR with the Kotlin runtime included,
--- then executes it with `java -jar`. Optionally appends CLI
--- arguments to the `java` command.
---
--- ```lua
--- run_kotlinc_file("/path/to/Main.kt")          -- no args
--- run_kotlinc_file("/path/to/Main.kt", "-v 3")  -- with args
--- ```
---
---@param file string Absolute path to the `.kt` file
---@param args? string CLI arguments to pass to the compiled JAR
---@return nil
---@private
local function run_kotlinc_file(file, args)
	local jar = file:gsub("%.kt$", "") .. ".jar"
	local cmd = string.format(
		"kotlinc %s -include-runtime -d %s && java -jar %s",
		vim.fn.shellescape(file),
		vim.fn.shellescape(jar),
		vim.fn.shellescape(jar)
	)
	if args and args ~= "" then
		cmd = cmd .. " " .. args
	end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- Project execution using the detected build system.
-- Gradle projects use `gradle run`, standalone files use kotlinc
-- to compile to JAR then execute with `java -jar`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current Kotlin project or file.
---
--- Strategy:
--- 1. Gradle project → `gradle run`
--- 2. `kotlinc` available → compile to JAR with runtime, execute with `java -jar`
--- 3. Neither → notification
keys.lang_map("kotlin", "n", "<leader>lr", function()
	vim.cmd("silent! write")
	local build = detect_build()

	if build == "gradle" then
		run_gradle("run")
	elseif build == "kotlinc" then
		run_kotlinc_file(vim.fn.expand("%:p"))
	else
		notify_no_build("gradle, kotlinc")
	end
end, { desc = icons.ui.Play .. " Run" })

--- Run the current Kotlin project or file with user-provided arguments.
---
--- Strategy:
--- 1. Gradle project → `gradle run --args='<input>'`
--- 2. `kotlinc` available → compile to JAR, execute with args
---
--- Prompts for arguments via `vim.ui.input()`. Aborts silently
--- if the user cancels the prompt.
keys.lang_map("kotlin", "n", "<leader>lR", function()
	vim.cmd("silent! write")
	local build = detect_build()

	if build == "gradle" then
		vim.ui.input({ prompt = "Args (--args='...'): " }, function(args)
			if args == nil then return end
			run_gradle("run --args=" .. vim.fn.shellescape(args))
		end)
	elseif build == "kotlinc" then
		local file = vim.fn.expand("%:p")
		vim.ui.input({ prompt = "Arguments: " }, function(args)
			if args == nil then return end
			run_kotlinc_file(file, args)
		end)
	else
		notify_no_build("gradle, kotlinc")
	end
end, { desc = icons.ui.Play .. " Run with arguments" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — BUILD / TEST
--
-- Build and test execution via Gradle or Maven.
-- Test-under-cursor uses treesitter to detect the function name.
-- ═══════════════════════════════════════════════════════════════════════════

--- Build the project using the detected build system.
---
--- Strategy:
--- 1. Gradle → `gradle build`
--- 2. Maven  → `mvn compile`
--- 3. Neither → notification
keys.lang_map("kotlin", "n", "<leader>lb", function()
	vim.cmd("silent! write")
	local build = detect_build()

	if build == "gradle" then
		run_gradle("build")
	elseif build == "maven" then
		vim.cmd.split()
		vim.cmd.terminal("mvn compile")
	else
		notify_no_build()
	end
end, { desc = icons.dev.Build .. " Build" })

--- Run the full test suite via the build system.
---
--- Strategy:
--- 1. Gradle → `gradle test`
--- 2. Maven  → `mvn test`
--- 3. Neither → notification
keys.lang_map("kotlin", "n", "<leader>lt", function()
	vim.cmd("silent! write")
	local build = detect_build()

	if build == "gradle" then
		run_gradle("test")
	elseif build == "maven" then
		vim.cmd.split()
		vim.cmd.terminal("mvn test")
	else
		notify_no_build()
	end
end, { desc = icons.dev.Test .. " Test" })

--- Run the test under cursor via Gradle `--tests` filter.
---
--- Uses treesitter to walk up the AST from the cursor position
--- until a `function_declaration` node is found, then extracts
--- its name for the `--tests` filter. Notifies if no function
--- is found.
---
--- NOTE: The `--tests '*.funcName'` pattern matches any test class
--- containing that method name. For more precise filtering, use
--- the fully qualified class name.
keys.lang_map("kotlin", "n", "<leader>lT", function()
	vim.cmd("silent! write")

	---@type TSNode|nil
	local node = vim.treesitter.get_node()
	---@type string|nil
	local func_name = nil

	while node do
		if node:type() == "function_declaration" then
			local name_node = node:field("name")[1]
			if name_node then
				func_name = vim.treesitter.get_node_text(name_node, 0)
			end
			break
		end
		node = node:parent()
	end

	if func_name then
		run_gradle("test --tests '*." .. func_name .. "'")
	else
		vim.notify("No test function found under cursor", vim.log.levels.WARN, { title = "Kotlin" })
	end
end, { desc = icons.dev.Test .. " Test under cursor" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL / DEBUG
--
-- Kotlin interactive REPL and JVM remote debugging.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a Kotlin REPL in a terminal split.
---
--- Launches `kotlinc` in interactive mode. Requires the Kotlin
--- compiler to be installed and available in `$PATH`.
keys.lang_map("kotlin", "n", "<leader>lc", function()
	if vim.fn.executable("kotlinc") ~= 1 then
		vim.notify("kotlinc not found", vim.log.levels.WARN, { title = "Kotlin" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("kotlinc")
end, { desc = icons.ui.Terminal .. " Kotlin REPL" })

--- Start a JVM debug session via Gradle.
---
--- Runs `gradle run --debug-jvm` which starts the application with
--- JDWP (Java Debug Wire Protocol) listening on port 5005.
--- Connect a remote debugger (IntelliJ, VS Code, or nvim-dap with
--- a JDWP adapter) to complete the debug session.
---
--- Requires a Gradle project — notifies if not detected.
keys.lang_map("kotlin", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local build = detect_build()

	if build == "gradle" then
		run_gradle("run --debug-jvm")
	else
		vim.notify("Debug requires Gradle project", vim.log.levels.WARN, { title = "Kotlin" })
	end
end, { desc = icons.dev.Debug .. " Debug" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — GRADLE COMMANDS
--
-- Comprehensive Gradle task picker with support for all common
-- tasks plus a custom task input option. Only available when a
-- Gradle project is detected.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Gradle commands picker.
---
--- Presents a list of common Gradle tasks via `vim.ui.select()`:
--- - build, clean, clean build, test, run
--- - jar, shadowJar (fat JAR)
--- - dependencies, tasks, check, assemble, publish
--- - custom… (prompts for arbitrary task input)
---
--- Only available when a Gradle project is detected (build.gradle
--- or build.gradle.kts exists in CWD).
---
--- ```
--- ┌─  Gradle: ────────────┐
--- │  build                  │
--- │  clean                  │
--- │  clean build            │
--- │  test                   │
--- │  run                    │
--- │  jar                    │
--- │  shadowJar              │
--- │  dependencies           │
--- │  tasks                  │
--- │  check                  │
--- │  assemble               │
--- │  publish                │
--- │  custom…                │ ← prompts for task name
--- └─────────────────────────┘
--- ```
keys.lang_map("kotlin", "n", "<leader>lg", function()
	local build = detect_build()
	if build ~= "gradle" then
		vim.notify("Not a Gradle project", vim.log.levels.INFO, { title = "Kotlin" })
		return
	end

	---@type { name: string, task: string, prompt: boolean|nil }[]
	local actions = {
		{ name = "build", task = "build" },
		{ name = "clean", task = "clean" },
		{ name = "clean build", task = "clean build" },
		{ name = "test", task = "test" },
		{ name = "run", task = "run" },
		{ name = "jar", task = "jar" },
		{ name = "shadowJar", task = "shadowJar" },
		{ name = "dependencies", task = "dependencies" },
		{ name = "tasks", task = "tasks" },
		{ name = "check", task = "check" },
		{ name = "assemble", task = "assemble" },
		{ name = "publish", task = "publish" },
		{ name = "custom…", task = "", prompt = true },
	}

	vim.ui.select(
		vim.tbl_map(function(a) return a.name end, actions),
		{ prompt = kt_icon .. " Gradle:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]

			if action.prompt then
				vim.ui.input({ prompt = "Gradle task: " }, function(task)
					if not task or task == "" then return end
					run_gradle(task)
				end)
			else
				run_gradle(action.task)
			end
		end
	)
end, { desc = kt_icon .. " Gradle commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — LINT / FORMAT
--
-- Code quality tools via ktlint.
-- Linting displays diagnostics in a terminal split.
-- Formatting runs ktlint in-place with `-F` flag and reloads the buffer.
-- ═══════════════════════════════════════════════════════════════════════════

--- Lint the current file with ktlint.
---
--- Runs `ktlint <file>` in a terminal split, displaying all style
--- violations. Requires `ktlint` to be installed.
keys.lang_map("kotlin", "n", "<leader>ll", function()
	if vim.fn.executable("ktlint") ~= 1 then
		vim.notify("Install: brew install ktlint", vim.log.levels.WARN, { title = "Kotlin" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	vim.cmd.split()
	vim.cmd.terminal("ktlint " .. file)
end, { desc = kt_icon .. " Lint (ktlint)" })

--- Format the current file with ktlint in-place.
---
--- Runs `ktlint -F <file>` which auto-fixes all fixable style
--- violations. Reloads the buffer after formatting to reflect changes.
--- Reports errors if ktlint exits non-zero.
keys.lang_map("kotlin", "n", "<leader>ls", function()
	if vim.fn.executable("ktlint") ~= 1 then
		vim.notify("Install: brew install ktlint", vim.log.levels.WARN, { title = "Kotlin" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	local result = vim.fn.system("ktlint -F " .. file .. " 2>&1")
	vim.cmd.edit()
	if vim.v.shell_error == 0 then
		vim.notify("Formatted", vim.log.levels.INFO, { title = "Kotlin" })
	else
		vim.notify("ktlint error:\n" .. result, vim.log.levels.ERROR, { title = "Kotlin" })
	end
end, { desc = kt_icon .. " Format (ktlint)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Project info display and curated Kotlin ecosystem documentation
-- links accessible from the editor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show project and toolchain information.
---
--- Displays a summary notification containing:
--- - Detected build system (gradle/maven/kotlinc/none)
--- - Current working directory
--- - Kotlin SDK version (from `kotlinc -version`)
--- - Tool availability checklist (kotlinc, kotlin, gradle, ktlint)
keys.lang_map("kotlin", "n", "<leader>li", function()
	local build = detect_build()
	---@type string[]
	local info = { kt_icon .. " Kotlin Info:", "" }
	info[#info + 1] = "  Build: " .. (build or "none")
	info[#info + 1] = "  CWD:   " .. vim.fn.getcwd()

	-- ── SDK version ──────────────────────────────────────────────
	if vim.fn.executable("kotlinc") == 1 then
		local version = vim.fn.system("kotlinc -version 2>&1"):match("([%d%.]+)") or "?"
		info[#info + 1] = "  SDK:   " .. version
	end

	-- ── Tool availability ────────────────────────────────────────
	---@type string[]
	local tools = { "kotlinc", "kotlin", "gradle", "ktlint" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Kotlin" })
end, { desc = icons.diagnostics.Info .. " Project info" })

--- Open Kotlin documentation in the browser.
---
--- Presents a list of curated Kotlin ecosystem resources via
--- `vim.ui.select()`:
--- 1. Kotlin Docs — official language documentation
--- 2. Kotlin API Reference — stdlib API docs
--- 3. Kotlin Playground — online code editor
--- 4. Gradle Kotlin DSL — Gradle build scripts in Kotlin
--- 5. Maven Central — package repository search
---
--- Opens the selected URL in the system browser via `vim.ui.open()`.
keys.lang_map("kotlin", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Kotlin Docs", url = "https://kotlinlang.org/docs/home.html" },
		{ name = "Kotlin API Reference", url = "https://kotlinlang.org/api/latest/jvm/stdlib/" },
		{ name = "Kotlin Playground", url = "https://play.kotlinlang.org/" },
		{ name = "Gradle Kotlin DSL", url = "https://docs.gradle.org/current/userguide/kotlin_dsl.html" },
		{ name = "Maven Central", url = "https://search.maven.org/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r) return r.name end, refs),
		{ prompt = kt_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Kotlin-specific alignment presets for mini.align:
-- • kotlin_params — align named parameters on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("kotlin") then
		---@type string Alignment preset icon from icons.app
		local kotlin_align_icon = icons.app.Kotlin

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			kotlin_params = {
				description = "Align Kotlin named params on '='",
				icon = kotlin_align_icon,
				split_pattern = "=",
				category = "jvm",
				lang = "kotlin",
				filetypes = { "kotlin" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("kotlin", "kotlin_params")
		align_registry.mark_language_loaded("kotlin")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("kotlin", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("kotlin_params"), {
			desc = kotlin_align_icon .. "  Align Kotlin params",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Kotlin-specific
-- parts (servers, formatters, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Kotlin                 │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (kotlin_language_server added)    │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.kotlin)         │
-- │ nvim-lint          │ opts merge (linters_by_ft.kotlin)            │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Kotlin debugging uses Gradle's --debug-jvm (JDWP protocol),
-- not a dedicated DAP adapter. For DAP integration, consider using
-- the Java debug adapter with Kotlin sources.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Kotlin
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- kotlin_language_server: JetBrains' Kotlin Language Server.
	-- Provides completions, diagnostics, go-to-definition, references,
	-- rename, code actions, and symbol search for Kotlin projects.
	--
	-- Uses an empty config table — the server's defaults are well-suited
	-- for most Kotlin projects (Gradle, Maven, standalone).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				kotlin_language_server = {},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					kt = "kotlin",
					kts = "kotlin",
				},
				filename = {
					["build.gradle.kts"] = "kotlin",
					["settings.gradle.kts"] = "kotlin",
				},
			})

			-- ── Buffer-local options for Kotlin files ────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "kotlin" },
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
	-- Ensures Kotlin tooling is installed via Mason:
	--   • kotlin-language-server — JetBrains Kotlin LSP
	--   • ktlint                 — Kotlin linter and formatter
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"kotlin-language-server",
				"ktlint",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- ktlint: Pinterest's Kotlin linter with built-in formatter.
	-- Enforces the official Kotlin coding conventions and Android
	-- Kotlin Style Guide. Used for both linting and formatting.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				kotlin = { "ktlint" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- ktlint: same tool used for both linting and formatting.
	-- Reports style violations that may not be auto-fixable.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				kotlin = { "ktlint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- kotlin: syntax highlighting, folding, text objects, indentation.
	-- Kotlin's advanced syntax (extension functions, coroutines, DSL
	-- builders, nullable types) benefits from treesitter parsing.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"kotlin",
			},
		},
	},
}
