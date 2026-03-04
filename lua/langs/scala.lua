---@file lua/langs/scala.lua
---@description Scala — LSP (Metals), formatter, treesitter, DAP & buffer-local keymaps
---@module "langs.scala"
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
---@see langs.ruby               Ruby language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/scala.lua — Scala language support                                ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("scala") → {} if off        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "scala" / "sbt"):            │    ║
--- ║  │  ├─ LSP          Metals  (via nvim-metals, NOT nvim-lspconfig)   │    ║
--- ║  │  ├─ Formatter    scalafmt (via Metals LSP formatting)            │    ║
--- ║  │  ├─ Treesitter   scala parser (syntax + folding)                 │    ║
--- ║  │  ├─ DAP          Metals debug adapter (integrated)               │    ║
--- ║  │  └─ Extras       sbt commands · worksheet eval · build info      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run (build-tool aware)                          │    ║
--- ║  │  │            R  Run with arguments                              │    ║
--- ║  │  │            b  Compile                                         │    ║
--- ║  │  ├─ TEST      t  Run tests             T  Test under cursor      │    ║
--- ║  │  ├─ REPL      c  Scala REPL (sbt console > scala-cli > scala)    │    ║
--- ║  │  ├─ DEBUG     d  Debug (Metals / Scalafix)                       │    ║
--- ║  │  ├─ METALS    m  Metals commands picker (8 actions)              │    ║
--- ║  │  │            w  Worksheet eval (Metals feature)                 │    ║
--- ║  │  ├─ SBT       s  sbt commands picker (12 actions)                │    ║
--- ║  │  │            p  Reload / update dependencies                    │    ║
--- ║  │  ├─ INFO      i  Build info + tools availability                 │    ║
--- ║  │  └─ DOCS      h  Documentation browser (Scala docs, API,         │    ║
--- ║  │                  Metals, sbt, Maven Central)                     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Build tool auto-detection:                                      │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. build.sbt exists  → sbt (highest priority)           │    │    ║
--- ║  │  │  2. build.sc exists   → mill                             │    │    ║
--- ║  │  │  3. scala-cli in PATH → scala-cli                        │    │    ║
--- ║  │  │  4. nil               → user notification                │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  REPL resolution:                                                │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. sbt project     → sbt console                        │    │    ║
--- ║  │  │  2. scala-cli       → scala-cli repl                     │    │    ║
--- ║  │  │  3. scala in PATH   → scala                              │    │    ║
--- ║  │  │  4. nil             → user notification                  │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Metals integration:                                             │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  nvim-metals (NOT nvim-lspconfig) manages the Metals     │    │    ║
--- ║  │  │  server. It provides:                                    │    │    ║
--- ║  │  │  • LSP features (completions, diagnostics, hover, etc.)  │    │    ║
--- ║  │  │  • Build integration (import build, build targets)       │    │    ║
--- ║  │  │  • Worksheet evaluation (.worksheet.sc files)            │    │    ║
--- ║  │  │  • DAP adapter (integrated, no separate binary needed)   │    │    ║
--- ║  │  │  • Scalafix (code refactoring rules)                     │    │    ║
--- ║  │  │                                                          │    │    ║
--- ║  │  │  Metals commands exposed via <leader>lm picker:          │    │    ║
--- ║  │  │  • Import build · Restart server · Organize imports      │    │    ║
--- ║  │  │  • Run doctor · New file · Switch BSP · Super hierarchy  │    │    ║
--- ║  │  │  • Analyze stacktrace                                    │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType scala / sbt):                       ║
--- ║  • colorcolumn=120, textwidth=120  (Scala style guide)                   ║
--- ║  • tabstop=2, shiftwidth=2         (2-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="// %s"           (Scala uses // comments)              ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .scala       → scala                                                  ║
--- ║  • .sc          → scala (Ammonite scripts / worksheets)                  ║
--- ║  • .sbt         → sbt                                                    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Scala support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("scala") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Scala Nerd Font icon (trailing whitespace stripped)
local scala_icon = icons.lang.scala:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Scala buffers.
-- The group is buffer-local and only visible when filetype == "scala".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("scala", "Scala", scala_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the build tool used by the current Scala project.
---
--- Resolution order:
--- 1. `build.sbt` in CWD → `"sbt"` (highest priority, most common)
--- 2. `build.sc` in CWD  → `"mill"` (Mill build tool)
--- 3. `scala-cli` in PATH → `"scala-cli"` (lightweight runner)
--- 4. `nil`               → no build tool found
---
--- ```lua
--- local build = detect_build()
--- if build == "sbt" then
---   vim.cmd.terminal("sbt compile")
--- end
--- ```
---
---@return "sbt"|"mill"|"scala-cli"|nil build The detected build tool name, or `nil`
---@private
local function detect_build()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/build.sbt") == 1 then
		return "sbt"
	elseif vim.fn.filereadable(cwd .. "/build.sc") == 1 then
		return "mill"
	elseif vim.fn.executable("scala-cli") == 1 then
		return "scala-cli"
	end
	return nil
end

--- Notify the user that no Scala build tool was found.
---
--- Centralizes the warning notification to avoid repetition across
--- keymaps that require a build tool.
---
---@return nil
---@private
local function notify_no_build()
	vim.notify("No build tool found (sbt, mill, scala-cli)", vim.log.levels.WARN, { title = "Scala" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN / BUILD
--
-- Project execution and compilation using the auto-detected build tool.
-- Each keymap adapts its command to the active build tool.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current Scala project or file.
---
--- Adapts the run command to the detected build tool:
--- - **sbt** → `sbt run`
--- - **mill** → `mill _.run`
--- - **scala-cli** → `scala-cli run <file>`
--- - **none** → notification
keys.lang_map("scala", "n", "<leader>lr", function()
	vim.cmd("silent! write")
	local build = detect_build()

	if build == "sbt" then
		vim.cmd.split()
		vim.cmd.terminal("sbt run")
	elseif build == "mill" then
		vim.cmd.split()
		vim.cmd.terminal("mill _.run")
	elseif build == "scala-cli" then
		local file = vim.fn.expand("%:p")
		vim.cmd.split()
		vim.cmd.terminal("scala-cli run " .. vim.fn.shellescape(file))
	else
		notify_no_build()
	end
end, { desc = icons.ui.Play .. " Run" })

--- Run the current project with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then adapts the
--- command to the detected build tool:
--- - **sbt** → `sbt "run <args>"`
--- - **scala-cli** → `scala-cli run <file> -- <args>`
--- - **mill/none** → falls back to `sbt run`
---
--- Aborts silently if the user cancels the prompt.
keys.lang_map("scala", "n", "<leader>lR", function()
	vim.cmd("silent! write")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		local build = detect_build()

		---@type string
		local cmd
		if build == "sbt" then
			cmd = 'sbt "run ' .. args .. '"'
		elseif build == "scala-cli" then
			cmd = "scala-cli run " .. vim.fn.shellescape(vim.fn.expand("%:p")) .. " -- " .. args
		else
			cmd = "sbt run"
		end

		vim.cmd.split()
		vim.cmd.terminal(cmd)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Compile the current project.
---
--- Adapts the compile command to the detected build tool:
--- - **sbt** → `sbt compile`
--- - **mill** → `mill _.compile`
--- - **scala-cli** → `scala-cli compile <file>`
--- - **none** → notification
keys.lang_map("scala", "n", "<leader>lb", function()
	vim.cmd("silent! write")
	local build = detect_build()

	if build == "sbt" then
		vim.cmd.split()
		vim.cmd.terminal("sbt compile")
	elseif build == "mill" then
		vim.cmd.split()
		vim.cmd.terminal("mill _.compile")
	elseif build == "scala-cli" then
		vim.cmd.split()
		vim.cmd.terminal("scala-cli compile " .. vim.fn.shellescape(vim.fn.expand("%:p")))
	else
		notify_no_build()
	end
end, { desc = icons.dev.Build .. " Compile" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via the auto-detected build tool.
-- Supports full suite and single-test targeting via treesitter.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite.
---
--- Adapts the test command to the detected build tool:
--- - **sbt** → `sbt test`
--- - **mill** → `mill _.test`
--- - **scala-cli** → `scala-cli test <file>`
keys.lang_map("scala", "n", "<leader>lt", function()
	vim.cmd("silent! write")
	local build = detect_build()

	if build == "sbt" then
		vim.cmd.split()
		vim.cmd.terminal("sbt test")
	elseif build == "mill" then
		vim.cmd.split()
		vim.cmd.terminal("mill _.test")
	elseif build == "scala-cli" then
		vim.cmd.split()
		vim.cmd.terminal("scala-cli test " .. vim.fn.shellescape(vim.fn.expand("%:p")))
	end
end, { desc = icons.dev.Test .. " Test" })

--- Run the test under the cursor (sbt only).
---
--- Uses treesitter to walk up the AST from the cursor position
--- until a `function_definition` or `val_definition` node is found,
--- then extracts its name for the `-z` filter.
---
--- Falls back to a notification if no test name can be detected.
keys.lang_map("scala", "n", "<leader>lT", function()
	vim.cmd("silent! write")

	---@type TSNode|nil
	local node = vim.treesitter.get_node()
	---@type string|nil
	local test_name = nil

	while node do
		if node:type() == "function_definition" or node:type() == "val_definition" then
			local name_node = node:field("name")[1] or node:field("pattern")[1]
			if name_node then test_name = vim.treesitter.get_node_text(name_node, 0) end
			break
		end
		node = node:parent()
	end

	if test_name then
		vim.cmd.split()
		vim.cmd.terminal('sbt "testOnly -- -z ' .. test_name .. '"')
	else
		vim.notify("No test found under cursor", vim.log.levels.WARN, { title = "Scala" })
	end
end, { desc = icons.dev.Test .. " Test under cursor" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL / DEBUG
--
-- Interactive REPL and debug session management.
-- REPL auto-selects the best available tool.
-- Debug delegates to Metals' integrated DAP adapter.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a Scala REPL in a terminal split.
---
--- Resolution order:
--- 1. sbt project → `sbt console` (includes project classpath)
--- 2. `scala-cli` available → `scala-cli repl`
--- 3. `scala` available → `scala` (standard REPL)
--- 4. None found → notification
keys.lang_map("scala", "n", "<leader>lc", function()
	local build = detect_build()

	if build == "sbt" then
		vim.cmd.split()
		vim.cmd.terminal("sbt console")
	elseif vim.fn.executable("scala-cli") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("scala-cli repl")
	elseif vim.fn.executable("scala") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("scala")
	else
		vim.notify("No Scala REPL found", vim.log.levels.WARN, { title = "Scala" })
	end
end, { desc = icons.ui.Terminal .. " REPL" })

--- Run Scalafix via Metals.
---
--- Requires both `nvim-metals` and `nvim-dap` to be available.
--- Uses Metals' `run_scalafix()` which applies configured Scalafix
--- rules to the current file.
keys.lang_map("scala", "n", "<leader>ld", function()
	local ok, metals = pcall(require, "metals")
	if not ok then
		vim.notify("nvim-metals not available", vim.log.levels.WARN, { title = "Scala" })
		return
	end
	local ok_dap = pcall(require, "dap")
	if not ok_dap then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Scala" })
		return
	end
	metals.run_scalafix()
end, { desc = icons.dev.Debug .. " Debug (metals)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — METALS
--
-- Metals-specific commands and features.
-- All commands check for availability before execution to provide
-- clear error messages when Metals is not running.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Metals commands picker.
---
--- Presents 8 Metals commands in a selection menu.
--- Each command checks for availability via `vim.fn.exists(":cmd")`
--- before execution, providing a clear notification if Metals is
--- not running.
---
--- Available commands:
--- - Import build       — import/reimport the build definition
--- - Restart server     — restart the Metals LSP server
--- - Organize imports   — sort and clean imports
--- - Show build target  — run Metals doctor (diagnostics)
--- - New Scala file     — create a new file with package boilerplate
--- - Switch build server — switch between BSP servers (Bloop, sbt, etc.)
--- - Super method hierarchy — show method override chain
--- - Analyze stacktrace — parse and navigate a JVM stacktrace
keys.lang_map("scala", "n", "<leader>lm", function()
	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "Import build", cmd = "MetalsImportBuild" },
		{ name = "Restart server", cmd = "MetalsRestartServer" },
		{ name = "Organize imports", cmd = "MetalsOrganizeImports" },
		{ name = "Show build target", cmd = "MetalsRunDoctor" },
		{ name = "New Scala file", cmd = "MetalsNewScalaFile" },
		{ name = "Switch build server", cmd = "MetalsSwitchBsp" },
		{ name = "Super method hierarchy", cmd = "MetalsSuperMethodHierarchy" },
		{ name = "Analyze stacktrace", cmd = "MetalsAnalyzeStacktrace" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = scala_icon .. " Metals:" },
		function(_, idx)
			if not idx then return end
			if vim.fn.exists(":" .. actions[idx].cmd) == 2 then
				vim.cmd(actions[idx].cmd)
			else
				vim.notify("Command not available — is Metals running?", vim.log.levels.WARN, { title = "Scala" })
			end
		end
	)
end, { desc = scala_icon .. " Metals commands" })

--- Evaluate the current Scala worksheet.
---
--- Worksheets (`.worksheet.sc` files) are a Metals feature that
--- provides inline evaluation results. Requires Metals to be running
--- and the current file to be a worksheet.
keys.lang_map("scala", "n", "<leader>lw", function()
	if vim.fn.exists(":MetalsEvaluateWorksheet") == 2 then
		vim.cmd("MetalsEvaluateWorksheet")
	else
		vim.notify("Metals worksheet not available", vim.log.levels.INFO, { title = "Scala" })
	end
end, { desc = scala_icon .. " Worksheet eval" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SBT COMMANDS
--
-- sbt-specific command palette and dependency management.
-- Only available in sbt projects (checked by `detect_build()`).
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the sbt commands picker.
---
--- Presents 12 common sbt commands in a selection menu.
--- Only available in sbt projects — notifies if not detected.
---
--- Available commands:
--- - compile, clean, clean compile
--- - run, test, console
--- - package, assembly
--- - publish, publishLocal
--- - update, dependencyTree
keys.lang_map("scala", "n", "<leader>ls", function()
	local build = detect_build()
	if build ~= "sbt" then
		vim.notify("Not an sbt project", vim.log.levels.INFO, { title = "Scala" })
		return
	end

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "compile", cmd = "sbt compile" },
		{ name = "clean", cmd = "sbt clean" },
		{ name = "clean compile", cmd = "sbt clean compile" },
		{ name = "run", cmd = "sbt run" },
		{ name = "test", cmd = "sbt test" },
		{ name = "console", cmd = "sbt console" },
		{ name = "package", cmd = "sbt package" },
		{ name = "assembly", cmd = "sbt assembly" },
		{ name = "publish", cmd = "sbt publish" },
		{ name = "publishLocal", cmd = "sbt publishLocal" },
		{ name = "update", cmd = "sbt update" },
		{ name = "dependencyTree", cmd = "sbt dependencyTree" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = scala_icon .. " sbt:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = scala_icon .. " sbt commands" })

--- Reload and update project dependencies.
---
--- Adapts to the detected build tool:
--- - **sbt** → `sbt reload update` (reload build, then update deps)
--- - **mill** → `mill resolve _` (resolve all dependencies)
keys.lang_map("scala", "n", "<leader>lp", function()
	local build = detect_build()

	if build == "sbt" then
		vim.cmd.split()
		vim.cmd.terminal("sbt reload update")
	elseif build == "mill" then
		vim.cmd.split()
		vim.cmd.terminal("mill resolve _")
	end
end, { desc = icons.ui.Package .. " Reload / update" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INFO / DOCUMENTATION
--
-- Build environment information and external documentation access.
-- Info displays the detected build tool, CWD, and tool availability.
-- Documentation links open in the system browser via `vim.ui.open()`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Display Scala build environment information.
---
--- Shows:
--- - Detected build tool (sbt / mill / scala-cli / none)
--- - Current working directory
--- - Tool availability status for 7 common Scala tools
keys.lang_map("scala", "n", "<leader>li", function()
	local build = detect_build()

	---@type string[]
	local info = {
		scala_icon .. " Scala Info:",
		"",
		"  Build: " .. (build or "none"),
		"  CWD:   " .. vim.fn.getcwd(),
	}

	---@type string[]
	local tools = { "scala", "scalac", "sbt", "mill", "scala-cli", "scalafmt", "coursier" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		---@type string
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Scala" })
end, { desc = icons.diagnostics.Info .. " Build info" })

--- Open Scala documentation in the system browser.
---
--- Presents a selection menu with links to key Scala documentation
--- resources. The selected URL is opened via `vim.ui.open()` which
--- delegates to the system's default browser.
---
--- Available documentation links:
--- - Scala Docs (main documentation)
--- - Scala API (standard library reference)
--- - Metals Docs (LSP server documentation)
--- - sbt Reference (build tool documentation)
--- - Maven Central (dependency search)
keys.lang_map("scala", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Scala Docs", url = "https://docs.scala-lang.org/" },
		{ name = "Scala API", url = "https://www.scala-lang.org/api/current/" },
		{ name = "Metals Docs", url = "https://scalameta.org/metals/docs/" },
		{ name = "sbt Reference", url = "https://www.scala-sbt.org/1.x/docs/" },
		{ name = "Maven Central", url = "https://search.maven.org/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = scala_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Scala-specific alignment presets for mini.align:
-- • scala_fields — align val/case class field type annotations on ":"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("scala") then
		---@type string Alignment preset icon from icons.lang
		local scala_align_icon = icons.lang.scala

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			scala_fields = {
				description = "Align Scala val / case class fields",
				icon = scala_align_icon,
				split_pattern = ":",
				category = "jvm",
				lang = "scala",
				filetypes = { "scala" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("scala", "scala_fields")
		align_registry.mark_language_loaded("scala")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("scala", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("scala_fields"), {
			desc = scala_align_icon .. "  Align Scala fields",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Scala-specific
-- parts (Metals, parsers, filetype extensions, buffer options).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Scala                  │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-metals        │ ft = scala/sbt/java (true lazy load)        │
-- │ nvim-lspconfig     │ init only (filetype + buffer options)       │
-- │ nvim-treesitter    │ opts merge (scala parser ensured)           │
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- Architecture note:
-- • Metals is managed by nvim-metals (NOT nvim-lspconfig). The
--   nvim-lspconfig spec here only provides filetype detection and
--   buffer-local options — no server configuration.
-- • nvim-metals auto-initializes on FileType via an autocmd group.
-- • DAP is integrated into Metals — no separate adapter binary needed.
-- • LSP capabilities are provided by blink.cmp for completions.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Scala
return {
	-- ── NVIM-METALS (LSP + BUILD + DAP) ────────────────────────────────────
	-- Metals: Scala language server providing LSP, build integration,
	-- worksheet evaluation, and integrated DAP debugging.
	-- Loaded on ft = scala/sbt/java via autocmd.
	--
	-- Settings:
	-- • showImplicitArguments/Conversions — show implicit decorations
	-- • showInferredType — display inferred types inline
	-- • excludedPackages — hide Java-only API packages from completions
	-- • statusBarProvider — enable build status in statusline
	-- ───────────────────────────────────────────────────────────────────────
	{
		"scalameta/nvim-metals",
		ft = { "scala", "sbt", "java" },
		dependencies = {
			"nvim-lua/plenary.nvim",
			"mfussenegger/nvim-dap",
		},
		opts = function()
			local metals_config = require("metals").bare_config()

			metals_config.settings = {
				showImplicitArguments = true,
				showImplicitConversionsAndClasses = true,
				showInferredType = true,
				excludedPackages = {
					"akka.actor.typed.javadsl",
					"com.github.swagger.akka.javadsl",
				},
			}

			metals_config.init_options.statusBarProvider = "on"
			metals_config.capabilities = require("blink.cmp").get_lsp_capabilities()

			return metals_config
		end,
		config = function(self, metals_config)
			local nvim_metals_group = vim.api.nvim_create_augroup("nvim-metals", { clear = true })

			vim.api.nvim_create_autocmd("FileType", {
				pattern = self.ft,
				callback = function()
					require("metals").initialize_or_attach(metals_config)
				end,
				group = nvim_metals_group,
			})
		end,
	},

	-- ── FILETYPE + BUFFER OPTIONS ──────────────────────────────────────────
	-- nvim-lspconfig is used here ONLY for filetype registration and
	-- buffer-local options. Metals LSP is managed by nvim-metals above.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					scala = "scala",
					sc = "scala",
					sbt = "sbt",
				},
			})

			-- ── Buffer-local options for Scala / sbt files ───────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "scala", "sbt" },
				callback = function()
					local opt = vim.opt_local

					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120

					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
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

	-- ── TREESITTER PARSER ──────────────────────────────────────────────────
	-- scala: syntax highlighting, folding, text objects, indentation
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"scala",
			},
		},
	},
}
