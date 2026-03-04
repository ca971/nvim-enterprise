---@file lua/langs/dart.lua
---@description Dart & Flutter — LSP (dartls), formatter, analyzer, DAP, Flutter CLI
---@module "langs.dart"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps               Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons                 Icon provider (`lang.dart`, `ui`, `dev`, `diagnostics`)
---@see core.mini-align-registry   Alignment preset registration for Dart params/maps
---@see langs.typescript           TypeScript support (similar web/mobile framework pattern)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/dart.lua — Dart & Flutter language support                        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("dart") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Detection layers:                                               │    ║
--- ║  │  ├─ Project     pubspec.yaml (Dart) / flutter: key (Flutter)     │    ║
--- ║  │  ├─ SDK         dart > flutter SDK embedded dart (PATH)          │    ║
--- ║  │  └─ Filetype    .dart → dart                                     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = "dart"):                         │    ║
--- ║  │  ├─ LSP         dartls (via flutter-tools.nvim)                  │    ║
--- ║  │  ├─ Formatter   dart format (built-in, via LSP)                  │    ║
--- ║  │  ├─ Linter      dart analyze (built-in, via LSP)                 │    ║
--- ║  │  ├─ Treesitter  dart parser                                      │    ║
--- ║  │  ├─ DAP         dart debugger (via flutter-tools.nvim)           │    ║
--- ║  │  └─ Flutter     flutter-tools.nvim (hot reload, devices, etc.)   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (buffer-local, <leader>l group, 16 bindings):           │    ║
--- ║  │  ├─ RUN         r  Run (dart/flutter)    R  Run with arguments   │    ║
--- ║  │  ├─ TEST        t  Run all tests         T  Test current file    │    ║
--- ║  │  ├─ DEBUG       d  Debug (DAP / flutter --debug)                 │    ║
--- ║  │  ├─ REPL        c  REPL / DartPad                                │    ║
--- ║  │  ├─ BUILD       b  Build (flutter/dart compile)                  │    ║
--- ║  │  ├─ PUB         p  Pub commands (7 actions)                      │    ║
--- ║  │  ├─ FLUTTER     f  Flutter commands (14 actions)                 │    ║
--- ║  │  ├─ QUALITY     a  Analyze              s  Fix (dart fix)        │    ║
--- ║  │  │              g  Code generation (build_runner)                │    ║
--- ║  │  └─ DOCS        i  Project info          h  Documentation        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Flutter project detection:                                      │    ║
--- ║  │  ├─ Check pubspec.yaml exists in cwd                             │    ║
--- ║  │  └─ Parse for "flutter:" key → is_flutter = true                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Dart SDK resolution:                                            │    ║
--- ║  │  ├─ 1. dart binary in PATH                                       │    ║
--- ║  │  └─ 2. Flutter SDK embedded dart (<flutter>/bin/dart)            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Test file resolution:                                           │    ║
--- ║  │  ├─ Current file ends with _test.dart → use as-is                │    ║
--- ║  │  └─ Otherwise: lib/foo.dart → test/foo_test.dart                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Pub commands (7 actions):                                       │    ║
--- ║  │  ├─ get · upgrade · outdated · deps                              │    ║
--- ║  │  ├─ add… · remove… (interactive name prompt)                     │    ║
--- ║  │  └─ publish --dry-run                                            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Flutter commands (14 actions):                                  │    ║
--- ║  │  ├─ Run · Hot reload · Hot restart · Quit                        │    ║
--- ║  │  ├─ Devices · Emulators · Dev tools · Outline                    │    ║
--- ║  │  ├─ Build (APK/iOS/web) · Clean · Doctor                         │    ║
--- ║  │  └─ Create… (interactive name prompt)                            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Build targets (Flutter):                                        │    ║
--- ║  │  apk · appbundle · ios · web · linux · macos · windows           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Mini.align integration:                                         │    ║
--- ║  │  ├─ Preset: dart_params (align named parameters on ':')          │    ║
--- ║  │  ├─ Preset: dart_map (align map literal entries on ':')          │    ║
--- ║  │  ├─ <leader>aL  Align Dart params                                │    ║
--- ║  │  └─ <leader>aT  Align Dart map                                   │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (set on FileType dart):                                  ║
--- ║  • 2 spaces, expandtab        (Dart style guide indentation)             ║
--- ║  • colorcolumn=80              (Dart effective style: 80 columns)        ║
--- ║  • commentstring="// %s"      (Dart single-line comment syntax)          ║
--- ║  • treesitter foldexpr         (foldmethod=expr, foldlevel=99)           ║
--- ║                                                                          ║
--- ║  flutter-tools.nvim features:                                            ║
--- ║  • Widget guides (visual indentation lines for widget trees)             ║
--- ║  • Closing tags (inline comments for widget closing brackets)            ║
--- ║  • LSP color provider (inline color previews)                            ║
--- ║  • Statusline decorations (app version, connected device)                ║
--- ║  • DAP integration (run_via_dap for breakpoint debugging)                ║
--- ║                                                                          ║
--- ║  Documentation references (6):                                           ║
--- ║  ├─ Dart Docs · Dart API Reference                                       ║
--- ║  ├─ Flutter Docs · Flutter Widget Catalog                                ║
--- ║  └─ pub.dev (packages) · DartPad (online IDE)                            ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Dart support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("dart") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Dart Nerd Font icon (trailing whitespace stripped)
local dart_icon = icons.lang.dart:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group as "󰣖 Dart" in which-key for dart buffers.
-- All lang_map() calls below bind into this group.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("dart", "Dart", dart_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — PROJECT & SDK DETECTION
--
-- Dart projects may be pure Dart (pubspec.yaml) or Flutter (pubspec.yaml
-- with a "flutter:" section). Many keymaps adapt their behavior based
-- on this distinction (e.g. `dart run` vs `flutter run`).
--
-- The Dart SDK can be installed standalone or bundled with the Flutter SDK.
-- The helper resolves the `dart` binary from either location.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect if the current project is a Flutter project.
---
--- Checks for `pubspec.yaml` in cwd, then parses its content for
--- the `flutter:` configuration key. A Flutter project always has
--- `pubspec.yaml` with a `flutter:` section.
---
--- ```lua
--- if is_flutter() then
---   vim.cmd.terminal("flutter run")
--- else
---   vim.cmd.terminal("dart run main.dart")
--- end
--- ```
---
---@return boolean is_flutter `true` if a Flutter project is detected
---@private
local function is_flutter()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/pubspec.yaml") ~= 1 then return false end
	local content = table.concat(vim.fn.readfile(cwd .. "/pubspec.yaml"), "\n")
	return content:match("flutter:") ~= nil
end

--- Get the path to the Dart executable.
---
--- Resolution order:
--- 1. `dart` binary in PATH (standalone Dart SDK)
--- 2. Flutter SDK embedded dart — derives `<flutter_sdk>/bin/dart` from
---    the `flutter` binary location
---
--- ```lua
--- local dart = get_dart()
--- if dart then
---   vim.cmd.terminal(dart .. " run main.dart")
--- end
--- ```
---
---@return string|nil dart_path Path to the dart executable, or `nil` if not found
---@private
local function get_dart()
	if vim.fn.executable("dart") == 1 then return "dart" end
	-- Flutter SDK includes dart at <flutter>/bin/dart
	if vim.fn.executable("flutter") == 1 then
		local flutter_path = vim.fn.exepath("flutter")
		local dart_path = vim.fn.fnamemodify(flutter_path, ":h") .. "/dart"
		if vim.fn.executable(dart_path) == 1 then return dart_path end
	end
	return nil
end

--- Notify the user that the Dart SDK was not found.
---
---@return nil
---@private
local function notify_no_dart()
	vim.notify("dart not found in PATH", vim.log.levels.ERROR, { title = "Dart" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- Execution adapts to the project type:
-- ├─ Flutter project → flutter run (or FlutterRun via flutter-tools.nvim)
-- └─ Pure Dart       → dart run <file>
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current project or file.
---
--- For Flutter projects, prefers the `:FlutterRun` command from
--- flutter-tools.nvim (provides hot reload integration), falling
--- back to `flutter run` in a terminal.
---
--- For pure Dart projects, runs the current file with `dart run`.
keys.lang_map("dart", "n", "<leader>lr", function()
	vim.cmd("silent! write")
	if is_flutter() then
		if vim.fn.exists(":FlutterRun") == 2 then
			vim.cmd("FlutterRun")
		else
			vim.cmd.split()
			vim.cmd.terminal("flutter run")
		end
	else
		local dart = get_dart()
		if not dart then
			notify_no_dart()
			return
		end
		local file = vim.fn.expand("%:p")
		vim.cmd.split()
		vim.cmd.terminal(dart .. " run " .. vim.fn.shellescape(file))
	end
end, { desc = icons.ui.Play .. " Run" })

--- Run the current file with user-provided arguments.
---
--- Always uses `dart run` (not Flutter) since Flutter run doesn't
--- accept file-level arguments in the same way.
keys.lang_map("dart", "n", "<leader>lR", function()
	vim.cmd("silent! write")
	local dart = get_dart()
	if not dart then
		notify_no_dart()
		return
	end
	local file = vim.fn.expand("%:p")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal(dart .. " run " .. vim.fn.shellescape(file) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution adapts to the project type:
-- ├─ Flutter → flutter test
-- └─ Dart   → dart test
--
-- Test file resolution for single-file testing:
-- ├─ File ends with _test.dart → use as-is
-- └─ Otherwise: lib/foo.dart → test/foo_test.dart
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite.
---
--- Uses `flutter test` for Flutter projects, `dart test` for pure Dart.
keys.lang_map("dart", "n", "<leader>lt", function()
	vim.cmd("silent! write")
	if is_flutter() then
		vim.cmd.split()
		vim.cmd.terminal("flutter test")
	else
		local dart = get_dart()
		if dart then
			vim.cmd.split()
			vim.cmd.terminal(dart .. " test")
		end
	end
end, { desc = icons.dev.Test .. " Run tests" })

--- Run tests for the current file.
---
--- If the current file is already a test file (`*_test.dart`), runs
--- it directly. Otherwise, derives the test file path by replacing
--- `lib/` with `test/` and appending `_test` before the extension:
--- `lib/src/utils.dart` → `test/src/utils_test.dart`
---
--- Notifies if the derived test file doesn't exist.
keys.lang_map("dart", "n", "<leader>lT", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	-- ── Derive test file path ─────────────────────────────────────────
	---@type string
	local test_file = file
	if not file:match("_test%.dart$") then test_file = file:gsub("/lib/", "/test/"):gsub("%.dart$", "_test.dart") end

	if vim.fn.filereadable(test_file) == 1 then
		if is_flutter() then
			vim.cmd.split()
			vim.cmd.terminal("flutter test " .. vim.fn.shellescape(test_file))
		else
			local dart = get_dart()
			if dart then
				vim.cmd.split()
				vim.cmd.terminal(dart .. " test " .. vim.fn.shellescape(test_file))
			end
		end
	else
		vim.notify("Test file not found: " .. vim.fn.fnamemodify(test_file, ":t"), vim.log.levels.WARN, { title = "Dart" })
	end
end, { desc = icons.dev.Test .. " Test file" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- Debug integration adapts to the project type:
-- ├─ Flutter → FlutterRun --debug (or flutter run --debug)
-- └─ Dart   → nvim-dap with dart adapter
--
-- For pure Dart, constructs a DAP launch configuration dynamically
-- using the resolved Dart SDK path.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start a debug session.
---
--- For Flutter: uses `:FlutterRun --debug` which enables the Flutter
--- DevTools debugger and connects to the running app.
---
--- For pure Dart: launches nvim-dap with a dynamically constructed
--- configuration that resolves the Dart SDK path from the `dart`
--- binary location (`<dart>/../../` → SDK root).
keys.lang_map("dart", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	if is_flutter() then
		if vim.fn.exists(":FlutterRun") == 2 then
			vim.cmd("FlutterRun --debug")
		else
			vim.cmd.split()
			vim.cmd.terminal("flutter run --debug")
		end
	else
		local ok, dap = pcall(require, "dap")
		if not ok then
			vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Dart" })
			return
		end
		local dart = get_dart()
		if dart then
			dap.run({
				type = "dart",
				request = "launch",
				name = "Debug " .. vim.fn.expand("%:t"),
				program = vim.fn.expand("%:p"),
				dartSdkPath = vim.fn.fnamemodify(vim.fn.exepath(dart), ":h:h"),
			})
		end
	end
end, { desc = icons.dev.Debug .. " Debug" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
--
-- Opens an interactive Dart session or falls back to DartPad (browser).
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a Dart REPL or DartPad in the browser.
---
--- If `dart` is available, runs `dart run` in a terminal split (which
--- starts the Dart VM in interactive mode). Falls back to opening
--- DartPad (https://dartpad.dev/) in the default browser.
keys.lang_map("dart", "n", "<leader>lc", function()
	local dart = get_dart()
	if dart then
		vim.cmd.split()
		vim.cmd.terminal(dart .. " run")
	else
		vim.ui.open("https://dartpad.dev/")
	end
end, { desc = icons.ui.Terminal .. " REPL / DartPad" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PUB
--
-- Dart package manager (pub) commands. All commands use the detected
-- `dart` binary. Interactive actions (add, remove) prompt for a
-- package name.
--
-- Available actions (7):
-- ├─ pub get            — resolve and download dependencies
-- ├─ pub upgrade        — upgrade dependencies to latest compatible
-- ├─ pub outdated       — show outdated dependencies
-- ├─ pub deps           — show dependency tree
-- ├─ pub add…           — add a package (prompts for name)
-- ├─ pub remove…        — remove a package (prompts for name)
-- └─ pub publish --dry-run — validate package before publishing
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Dart pub command palette.
---
--- Presents 7 pub commands. Actions marked with `prompt = true`
--- will ask for a package name before executing.
keys.lang_map("dart", "n", "<leader>lp", function()
	local dart = get_dart()
	if not dart then return end

	---@type { name: string, cmd: string, prompt?: boolean }[]
	local actions = {
		{ name = "pub get", cmd = dart .. " pub get" },
		{ name = "pub upgrade", cmd = dart .. " pub upgrade" },
		{ name = "pub outdated", cmd = dart .. " pub outdated" },
		{ name = "pub deps", cmd = dart .. " pub deps" },
		{ name = "pub add…", cmd = dart .. " pub add", prompt = true },
		{ name = "pub remove…", cmd = dart .. " pub remove", prompt = true },
		{ name = "pub publish --dry-run", cmd = dart .. " pub publish --dry-run" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = dart_icon .. " Pub:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]
			if action.prompt then
				vim.ui.input({ prompt = "Package: " }, function(pkg)
					if not pkg or pkg == "" then return end
					vim.cmd.split()
					vim.cmd.terminal(action.cmd .. " " .. vim.fn.shellescape(pkg))
				end)
			else
				vim.cmd.split()
				vim.cmd.terminal(action.cmd)
			end
		end
	)
end, { desc = icons.ui.Package .. " Pub commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FLUTTER
--
-- Flutter-specific commands. Only available in Flutter projects
-- (detected via is_flutter()). Commands are divided into:
-- ├─ Neovim commands (nvim = true) → use flutter-tools.nvim if loaded
-- └─ CLI commands (nvim = false) → run in terminal split
--
-- Interactive commands (prompt = true) ask for a name before executing.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Flutter command palette.
---
--- Presents 14 Flutter commands covering the full development lifecycle.
--- Neovim-native commands (via flutter-tools.nvim) provide better
--- integration (hot reload, device management) than CLI equivalents.
---
--- Guards against non-Flutter projects with an early notification.
keys.lang_map("dart", "n", "<leader>lf", function()
	if not is_flutter() then
		vim.notify("Not a Flutter project", vim.log.levels.INFO, { title = "Dart" })
		return
	end

	---@type { name: string, cmd: string, nvim: boolean, prompt?: boolean }[]
	local actions = {
		-- ── Neovim commands (flutter-tools.nvim) ──────────────────────
		{ name = "Run", cmd = "FlutterRun", nvim = true },
		{ name = "Hot reload", cmd = "FlutterReload", nvim = true },
		{ name = "Hot restart", cmd = "FlutterRestart", nvim = true },
		{ name = "Quit", cmd = "FlutterQuit", nvim = true },
		{ name = "Devices", cmd = "FlutterDevices", nvim = true },
		{ name = "Emulators", cmd = "FlutterEmulators", nvim = true },
		{ name = "Dev tools", cmd = "FlutterDevTools", nvim = true },
		{ name = "Outline toggle", cmd = "FlutterOutlineToggle", nvim = true },
		-- ── CLI commands ──────────────────────────────────────────────
		{ name = "Build APK", cmd = "flutter build apk", nvim = false },
		{ name = "Build iOS", cmd = "flutter build ios", nvim = false },
		{ name = "Build web", cmd = "flutter build web", nvim = false },
		{ name = "Clean", cmd = "flutter clean", nvim = false },
		{ name = "Doctor", cmd = "flutter doctor -v", nvim = false },
		{ name = "Create…", cmd = "flutter create", nvim = false, prompt = true },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = dart_icon .. " Flutter:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]
			if action.nvim and vim.fn.exists(":" .. action.cmd) == 2 then
				vim.cmd(action.cmd)
			elseif action.prompt then
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
end, { desc = dart_icon .. " Flutter commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — QUALITY (ANALYZE / FIX / CODEGEN)
--
-- Dart's built-in static analysis, automated fix tool, and code
-- generation via build_runner.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run `dart analyze` for static analysis.
---
--- Saves the buffer, then runs the Dart analyzer which checks for
--- type errors, unused imports, missing overrides, and style violations.
keys.lang_map("dart", "n", "<leader>la", function()
	local dart = get_dart()
	if not dart then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(dart .. " analyze")
end, { desc = dart_icon .. " Analyze" })

--- Apply automated fixes via `dart fix --apply`.
---
--- Runs `dart fix --apply` which applies all available automated fixes
--- (deprecated API migrations, lint suggestions, etc.). Reloads the
--- buffer after fixes are applied and shows the output in a notification.
keys.lang_map("dart", "n", "<leader>ls", function()
	local dart = get_dart()
	if not dart then return end
	vim.cmd("silent! write")
	local result = vim.fn.system(dart .. " fix --apply 2>&1")
	vim.cmd.edit()
	vim.notify(result, vim.log.levels.INFO, { title = "dart fix" })
end, { desc = dart_icon .. " Fix (dart fix)" })

--- Run code generation via build_runner.
---
--- Executes `dart run build_runner build --delete-conflicting-outputs`
--- which triggers all registered code generators (json_serializable,
--- freezed, injectable, etc.). The `--delete-conflicting-outputs` flag
--- cleans stale generated files automatically.
keys.lang_map("dart", "n", "<leader>lg", function()
	local dart = get_dart()
	if not dart then return end
	vim.cmd.split()
	vim.cmd.terminal(dart .. " run build_runner build --delete-conflicting-outputs")
end, { desc = dart_icon .. " Code generation" })

--- Build the project.
---
--- For Flutter projects: presents a target selection (7 platforms)
--- via `vim.ui.select()`, then runs `flutter build <target>`.
---
--- For pure Dart: compiles the current file to a native executable
--- via `dart compile exe`.
---
--- Flutter build targets:
--- `apk` · `appbundle` · `ios` · `web` · `linux` · `macos` · `windows`
keys.lang_map("dart", "n", "<leader>lb", function()
	if not is_flutter() then
		local dart = get_dart()
		if dart then
			vim.cmd.split()
			vim.cmd.terminal(dart .. " compile exe " .. vim.fn.shellescape(vim.fn.expand("%:p")))
		end
		return
	end

	---@type string[]
	local targets = { "apk", "appbundle", "ios", "web", "linux", "macos", "windows" }
	vim.ui.select(targets, { prompt = dart_icon .. " Build target:" }, function(target)
		if not target then return end
		vim.cmd.split()
		vim.cmd.terminal("flutter build " .. target)
	end)
end, { desc = icons.dev.Build .. " Build" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INFO / DOCUMENTATION
--
-- Project introspection and external documentation access.
-- Info displays Dart SDK version, Flutter detection, and Flutter
-- SDK version (if available).
-- ═══════════════════════════════════════════════════════════════════════════

--- Show Dart and Flutter project information.
---
--- Displays:
--- - Dart SDK version (from `dart --version`)
--- - Flutter project detection status
--- - Flutter SDK version (from `flutter --version`, if available)
keys.lang_map("dart", "n", "<leader>li", function()
	---@type string[]
	local info = { dart_icon .. " Dart Info:", "" }
	local dart = get_dart()
	if dart then
		---@type string
		local version = vim.fn.system(dart .. " --version 2>&1"):gsub("%s+$", "")
		info[#info + 1] = "  " .. version
	end

	info[#info + 1] = "  Flutter: " .. (is_flutter() and "✓" or "✗")

	if vim.fn.executable("flutter") == 1 then
		---@type string
		local fv = vim.fn.system("flutter --version 2>/dev/null"):match("Flutter ([%d%.]+)") or "?"
		info[#info + 1] = "  Flutter SDK: " .. fv
	end

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Dart" })
end, { desc = icons.diagnostics.Info .. " Project info" })

--- Open Dart or Flutter documentation in the default browser.
---
--- Presents 6 curated reference links via `vim.ui.select()`:
--- 1. Dart Docs          — language guides and tutorials
--- 2. Dart API Reference — dart:core, dart:async, etc.
--- 3. Flutter Docs       — framework documentation
--- 4. Flutter Widgets    — widget catalog with examples
--- 5. pub.dev            — Dart/Flutter package registry
--- 6. DartPad            — online Dart/Flutter IDE
keys.lang_map("dart", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Dart Docs", url = "https://dart.dev/guides" },
		{ name = "Dart API Reference", url = "https://api.dart.dev/" },
		{ name = "Flutter Docs", url = "https://docs.flutter.dev/" },
		{ name = "Flutter Widget Catalog", url = "https://docs.flutter.dev/ui/widgets" },
		{ name = "pub.dev (packages)", url = "https://pub.dev/" },
		{ name = "DartPad", url = "https://dartpad.dev/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = dart_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Dart-specific alignment presets when mini.align is available.
-- Loaded once per session (guarded by is_language_loaded).
--
-- Presets:
-- ├─ dart_params — align named parameters on ':' in widget constructors
-- │  Example:
-- │    Container(
-- │      width   : 100,
-- │      height  : 200,
-- │      color   : Colors.blue,
-- │    )
-- └─ dart_map — align Map literal entries on ':'
--    Example:
--      {'name'  : 'Alice',
--       'age'   : 30}
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("dart") then
		---@type string Alignment preset icon from icons.lang
		local align_icon = icons.lang.dart

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			dart_params = {
				description = "Align Dart named parameters on ':'",
				icon = align_icon,
				split_pattern = ":",
				category = "domain",
				lang = "dart",
				filetypes = { "dart" },
			},
			dart_map = {
				description = "Align Dart map literal entries on ':'",
				icon = align_icon,
				split_pattern = ":",
				category = "domain",
				lang = "dart",
				filetypes = { "dart" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("dart", "dart_params")
		align_registry.mark_language_loaded("dart")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("dart", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("dart_params"), {
			desc = align_icon .. "  Align Dart params",
		})
		keys.lang_map("dart", { "n", "x" }, "<leader>aT", align_registry.make_align_fn("dart_map"), {
			desc = align_icon .. "  Align Dart map",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations.
--
-- NOTE: Dart LSP (dartls) is managed by flutter-tools.nvim, not
-- nvim-lspconfig directly. flutter-tools.nvim handles the LSP
-- lifecycle, including SDK path resolution and Flutter-specific
-- features (hot reload, device management, widget guides).
--
-- Loading strategy:
-- ┌─────────────────────┬─────────────────────────────────────────────┐
-- │ Plugin              │ How it lazy-loads for Dart                  │
-- ├─────────────────────┼─────────────────────────────────────────────┤
-- │ flutter-tools.nvim  │ ft = "dart" (manages dartls lifecycle)      │
-- │ nvim-lspconfig      │ init only (filetype + buffer opts, no LSP)  │
-- │ nvim-treesitter     │ opts merge (dart parser to ensure_installed)│
-- └─────────────────────┴─────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Dart
return {
	-- ── FLUTTER-TOOLS (LSP + Flutter integration) ──────────────────────
	-- flutter-tools.nvim manages the dartls LSP server lifecycle and
	-- provides Flutter-specific features. This replaces the standard
	-- nvim-lspconfig dartls configuration.
	--
	-- Features:
	-- • Widget guides — visual indentation lines for nested widgets
	-- • Closing tags — inline `// Container` comments at closing brackets
	-- • LSP color provider — inline color swatches for Color() values
	-- • Statusline — app version and connected device info
	-- • DAP — run_via_dap enables breakpoint debugging
	--
	-- LSP settings:
	-- • showTodos — highlight TODO/FIXME comments in diagnostics
	-- • completeFunctionCalls — auto-insert parentheses on completion
	-- • renameFilesWithClasses — prompt to rename file when class renamed
	-- • enableSnippets — LSP-provided code snippets
	-- • updateImportsOnRename — auto-update imports on file rename
	-- ────────────────────────────────────────────────────────────────────
	{
		"akinsho/flutter-tools.nvim",
		lazy = true,
		ft = { "dart" },
		dependencies = {
			"nvim-lua/plenary.nvim",
			"stevearc/dressing.nvim",
		},
		opts = {
			ui = {
				border = "rounded",
			},
			decorations = {
				statusline = {
					app_version = true,
					device = true,
				},
			},
			widget_guides = {
				enabled = true,
			},
			closing_tags = {
				enabled = true,
				highlight = "Comment",
				prefix = "// ",
			},
			lsp = {
				color = {
					enabled = true,
				},
				settings = {
					showTodos = true,
					completeFunctionCalls = true,
					renameFilesWithClasses = "prompt",
					enableSnippets = true,
					updateImportsOnRename = true,
				},
			},
			debugger = {
				enabled = true,
				run_via_dap = true,
			},
		},
	},

	-- ── FILETYPE DETECTION & BUFFER OPTIONS ────────────────────────────
	-- No LSP server is configured here — dartls is managed by
	-- flutter-tools.nvim above. This entry handles only filetype
	-- registration and buffer option setup.
	-- ────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		init = function()
			-- ── Filetype detection ──────────────────────────────────
			vim.filetype.add({
				extension = {
					dart = "dart",
				},
			})

			-- ── Buffer-local options for Dart files ───────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "dart" },
				callback = function()
					local opt = vim.opt_local

					-- ── Layout ────────────────────────────────────────
					opt.wrap = false
					opt.colorcolumn = "80"
					opt.textwidth = 80

					-- ── Indentation (Dart effective style: 2 spaces) ─
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true

					-- ── Line numbers ──────────────────────────────────
					opt.number = true
					opt.relativenumber = true

					-- ── Folding (treesitter-based) ────────────────────
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99

					-- ── Comments ──────────────────────────────────────
					opt.commentstring = "// %s"
				end,
				desc = "NvimEnterprise: Dart buffer options",
			})
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────
	-- dart: syntax highlighting, folding, text objects, and indentation
	-- for .dart files. Also powers widget tree structure detection.
	-- ────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"dart",
			},
		},
	},
}
