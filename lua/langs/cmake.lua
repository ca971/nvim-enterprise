---@file lua/langs/cmake.lua
---@description CMake — Build system management, LSP, formatter, linter, presets
---@module "langs.cmake"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps               Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons                 Icon provider (`lang.cmake`, `ui`, `dev`, `diagnostics`)
---@see core.mini-align-registry   Alignment preset registration for CMake set()
---@see langs.c                    C support (shared CMake tooling, compile_commands.json)
---@see langs.cpp                  C++ support (shared CMake tooling)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/cmake.lua — CMake build system support                            ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("cmake") → {} if off        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Detection layers:                                               │    ║
--- ║  │  ├─ Build dir   build > cmake-build-debug > cmake-build-release  │    ║
--- ║  │  │              > out/build (auto-detected, fallback: build)     │    ║
--- ║  │  ├─ Filetype    CMakeLists.txt, *.cmake, *.cmake.in → cmake      │    ║
--- ║  │  ├─ Presets     CMakePresets.json (--list-presets discovery)     │    ║
--- ║  │  └─ Targets     cmake --build <dir> --target help (dynamic)      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = "cmake"):                        │    ║
--- ║  │  ├─ LSP         cmake-language-server (conditional on Python)    │    ║
--- ║  │  ├─ Formatter   cmake-format (cmakelang, via conform.nvim)       │    ║
--- ║  │  ├─ Linter      cmakelint (nvim-lint)                            │    ║
--- ║  │  └─ Treesitter  cmake parser                                     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (buffer-local, <leader>l group, 12 bindings):           │    ║
--- ║  │  ├─ BUILD       c  Configure            b  Build (--parallel)    │    ║
--- ║  │  │              C  Clean                                         │    ║
--- ║  │  ├─ TEST/RUN    t  Test (ctest)          r  Run target           │    ║
--- ║  │  ├─ CONFIG      p  Select preset         s  Select build type    │    ║
--- ║  │  ├─ TOOLS       g  Generate compile_commands.json                │    ║
--- ║  │  │              i  Install               e  Edit CMakeCache      │    ║
--- ║  │  └─ DOCS        d  CMake help            h  Documentation        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Build directory detection (4 candidates):                       │    ║
--- ║  │  ├─ build/                  (CMake default)                      │    ║
--- ║  │  ├─ cmake-build-debug/     (CLion convention)                    │    ║
--- ║  │  ├─ cmake-build-release/   (CLion convention)                    │    ║
--- ║  │  └─ out/build/             (Visual Studio convention)            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Target discovery strategy:                                      │    ║
--- ║  │  ├─ 1. cmake --build <dir> --target help → parse target list     │    ║
--- ║  │  ├─ 2. Filter out meta-targets (all, clean, help)                │    ║
--- ║  │  ├─ 3. Present via vim.ui.select()                               │    ║
--- ║  │  └─ 4. Fallback: prompt for target name manually                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Mason install conditions:                                       │    ║
--- ║  │  ├─ cmake-language-server: requires Python 3.8–3.13              │    ║
--- ║  │  ├─ cmakelang + cmakelint: requires cmake in PATH                │    ║
--- ║  │  └─ Tools are conditionally added to ensure_installed            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Mini.align integration:                                         │    ║
--- ║  │  ├─ Preset: cmake_set (align set() arguments by whitespace)      │    ║
--- ║  │  └─ <leader>aL  Align CMake set                                  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (set on FileType cmake):                                 ║
--- ║  • 2 spaces, expandtab        (CMake convention)                         ║
--- ║  • colorcolumn=120             (CMake style guide line length)           ║
--- ║  • commentstring="# %s"       (CMake comment syntax)                     ║
--- ║  • treesitter foldexpr         (foldmethod=expr, foldlevel=99)           ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if CMake support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("cmake") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string CMake Nerd Font icon (trailing whitespace stripped)
local cmake_icon = icons.lang.cmake:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group as " CMake" in which-key for
-- cmake buffers. All lang_map() calls below bind into this group.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("cmake", "CMake", cmake_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — BUILD DIRECTORY & CMAKE GUARD
--
-- CMake commands need to know where the build directory is located.
-- Different IDEs and workflows use different conventions:
-- ├─ build/                — CMake default (cmake -B build)
-- ├─ cmake-build-debug/    — CLion convention
-- ├─ cmake-build-release/  — CLion convention
-- └─ out/build/            — Visual Studio convention
--
-- The detect function scans these in order and returns the first
-- existing directory, falling back to "build" if none exist yet.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the CMake build directory in the current project.
---
--- Scans 4 common build directory locations in priority order.
--- Returns the first existing directory, or `"build"` as fallback
--- (even if it doesn't exist yet — CMake will create it).
---
--- ```lua
--- local build = detect_build_dir()
--- vim.cmd.terminal("cmake --build " .. build)
--- ```
---
---@return string build_dir Relative path to the build directory
---@private
local function detect_build_dir()
	local cwd = vim.fn.getcwd()
	---@type string[]
	local candidates = { "build", "cmake-build-debug", "cmake-build-release", "out/build" }
	for _, dir in ipairs(candidates) do
		if vim.fn.isdirectory(cwd .. "/" .. dir) == 1 then return dir end
	end
	return "build"
end

--- Check if cmake is available on the system PATH.
---
--- Displays an error notification if not found and returns `false`,
--- allowing callers to use a simple guard pattern:
---
--- ```lua
--- if not check_cmake() then return end
--- ```
---
---@return boolean available `true` if cmake is found in PATH
---@private
local function check_cmake()
	if vim.fn.executable("cmake") ~= 1 then
		vim.notify("cmake not found in PATH", vim.log.levels.ERROR, { title = "CMake" })
		return false
	end
	return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CONFIGURE / BUILD
--
-- Core CMake workflow: configure (generate build system), build
-- (compile), test (ctest), run (execute target), and clean.
--
-- All commands auto-detect the build directory via detect_build_dir().
-- The configure command always exports compile_commands.json for
-- clangd LSP integration.
-- ═══════════════════════════════════════════════════════════════════════════

--- Configure the project (generate build system).
---
--- Runs `cmake -B <build_dir> -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`.
--- Creates the build directory if it doesn't exist. Always enables
--- compile_commands.json export for clangd integration.
keys.lang_map("cmake", "n", "<leader>lc", function()
	if not check_cmake() then return end
	local build = detect_build_dir()
	vim.cmd.split()
	vim.cmd.terminal("cmake -B " .. vim.fn.shellescape(build) .. " -DCMAKE_EXPORT_COMPILE_COMMANDS=ON")
end, { desc = cmake_icon .. " Configure" })

--- Build the project with parallel compilation.
---
--- Runs `cmake --build <build_dir> --parallel` which uses all
--- available CPU cores. Saves the buffer before building.
keys.lang_map("cmake", "n", "<leader>lb", function()
	if not check_cmake() then return end
	vim.cmd("silent! write")
	local build = detect_build_dir()
	vim.cmd.split()
	vim.cmd.terminal("cmake --build " .. vim.fn.shellescape(build) .. " --parallel")
end, { desc = icons.dev.Build .. " Build" })

--- Run CTest with output-on-failure.
---
--- Uses `ctest --test-dir <build_dir> --output-on-failure` which
--- only displays test output for failing tests, keeping the output
--- clean for successful runs.
keys.lang_map("cmake", "n", "<leader>lt", function()
	if not check_cmake() then return end
	local build = detect_build_dir()
	vim.cmd.split()
	vim.cmd.terminal("ctest --test-dir " .. vim.fn.shellescape(build) .. " --output-on-failure")
end, { desc = icons.dev.Test .. " Test (ctest)" })

--- Run a specific build target interactively.
---
--- Target discovery strategy:
--- 1. Run `cmake --build <dir> --target help` to list available targets
--- 2. Parse output for target names (lines matching `... <target>`)
--- 3. Filter out meta-targets: `all`, `clean`, `help`
--- 4. Present discovered targets via `vim.ui.select()`
--- 5. Fallback: if no targets found, prompt for manual input
---
--- After building the selected target, attempts to execute it from
--- the build directory (assumes the target produces an executable
--- with the same name).
keys.lang_map("cmake", "n", "<leader>lr", function()
	if not check_cmake() then return end
	local build = detect_build_dir()

	-- ── Discover targets ──────────────────────────────────────────────
	---@type string[]
	local targets = {}
	local result = vim.fn.system("cmake --build " .. vim.fn.shellescape(build) .. " --target help 2>/dev/null")
	if vim.v.shell_error == 0 and result ~= "" then
		for line in result:gmatch("[^\r\n]+") do
			---@type string|nil
			local target = line:match("^%.%.%.%s+(.+)$")
			if target and target ~= "all" and target ~= "clean" and target ~= "help" then targets[#targets + 1] = target end
		end
	end

	--- Build and run the selected target.
	---@param target string Target name to build and execute
	---@private
	local function build_and_run(target)
		vim.cmd.split()
		vim.cmd.terminal(
			"cmake --build "
				.. vim.fn.shellescape(build)
				.. " --target "
				.. vim.fn.shellescape(target)
				.. " && ./"
				.. build
				.. "/"
				.. target
		)
	end

	-- ── Present selection or prompt ───────────────────────────────────
	if #targets > 0 then
		vim.ui.select(targets, { prompt = cmake_icon .. " Run target:" }, function(target)
			if not target then return end
			build_and_run(target)
		end)
	else
		vim.ui.input({ prompt = "Target name: " }, function(target)
			if not target or target == "" then return end
			build_and_run(target)
		end)
	end
end, { desc = icons.ui.Play .. " Run target" })

--- Clean the build directory.
---
--- Runs `cmake --build <dir> --target clean` which removes all
--- build artifacts without deleting the CMake cache or configuration.
keys.lang_map("cmake", "n", "<leader>lC", function()
	if not check_cmake() then return end
	local build = detect_build_dir()
	vim.cmd.split()
	vim.cmd.terminal("cmake --build " .. vim.fn.shellescape(build) .. " --target clean")
end, { desc = cmake_icon .. " Clean" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PRESETS / BUILD TYPE
--
-- CMake presets (CMakePresets.json) provide named configurations for
-- configure, build, test, and package steps. Build types control
-- optimization level and debug symbol generation.
--
-- Build types:
-- ├─ Debug          — no optimization, full debug symbols (-O0 -g)
-- ├─ Release        — full optimization, no debug (-O3 -DNDEBUG)
-- ├─ RelWithDebInfo — optimization + debug (-O2 -g)
-- └─ MinSizeRel     — optimize for binary size (-Os -DNDEBUG)
-- ═══════════════════════════════════════════════════════════════════════════

--- Select and apply a CMake preset.
---
--- Runs `cmake --list-presets` to discover available presets from
--- `CMakePresets.json` or `CMakeUserPresets.json`. Parses the output
--- for quoted preset names and presents them via `vim.ui.select()`.
---
--- Presets provide reproducible configurations that can be shared
--- across team members and CI systems.
keys.lang_map("cmake", "n", "<leader>lp", function()
	if not check_cmake() then return end
	local result = vim.fn.system("cmake --list-presets 2>/dev/null")
	if vim.v.shell_error ~= 0 or result == "" then
		vim.notify("No CMakePresets.json found", vim.log.levels.INFO, { title = "CMake" })
		return
	end

	---@type string[]
	local presets = {}
	for line in result:gmatch("[^\r\n]+") do
		---@type string|nil
		local name = line:match('^%s+"(.+)"')
		if name then presets[#presets + 1] = name end
	end

	if #presets == 0 then
		vim.notify("No presets found", vim.log.levels.INFO, { title = "CMake" })
		return
	end

	vim.ui.select(presets, { prompt = cmake_icon .. " Configure preset:" }, function(preset)
		if not preset then return end
		vim.cmd.split()
		vim.cmd.terminal("cmake --preset " .. vim.fn.shellescape(preset))
	end)
end, { desc = cmake_icon .. " Select preset" })

--- Select and apply a CMake build type.
---
--- Presents the 4 standard CMake build types, then reconfigures the
--- project with the selected type. Always enables compile_commands.json
--- export for clangd.
---
--- Build types:
--- - `Debug`          — no optimization, full debug symbols
--- - `Release`        — full optimization, no debug symbols
--- - `RelWithDebInfo` — optimization + debug symbols (best of both)
--- - `MinSizeRel`     — optimize for binary size
keys.lang_map("cmake", "n", "<leader>ls", function()
	if not check_cmake() then return end
	---@type string[]
	local types = { "Debug", "Release", "RelWithDebInfo", "MinSizeRel" }
	local build = detect_build_dir()

	vim.ui.select(types, { prompt = cmake_icon .. " Build type:" }, function(bt)
		if not bt then return end
		vim.cmd.split()
		vim.cmd.terminal(
			"cmake -B " .. vim.fn.shellescape(build) .. " -DCMAKE_BUILD_TYPE=" .. bt .. " -DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
		)
	end)
end, { desc = cmake_icon .. " Select build type" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Development utilities: compile_commands.json generation, install,
-- and CMakeCache editing.
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate compile_commands.json and symlink to project root.
---
--- Runs `cmake -B <build_dir> -DCMAKE_EXPORT_COMPILE_COMMANDS=ON` then
--- creates a symlink from `<build_dir>/compile_commands.json` to the
--- project root. This allows clangd to find the compilation database
--- without explicit configuration.
keys.lang_map("cmake", "n", "<leader>lg", function()
	if not check_cmake() then return end
	local build = detect_build_dir()
	vim.cmd.split()
	vim.cmd.terminal(
		"cmake -B "
			.. vim.fn.shellescape(build)
			.. " -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && ln -sf "
			.. build
			.. "/compile_commands.json ."
	)
end, { desc = cmake_icon .. " Generate compile_commands" })

--- Install the built project.
---
--- Runs `cmake --install <build_dir>` which executes the install rules
--- defined in the CMakeLists.txt. May require elevated privileges
--- depending on the install prefix.
keys.lang_map("cmake", "n", "<leader>li", function()
	if not check_cmake() then return end
	local build = detect_build_dir()
	vim.cmd.split()
	vim.cmd.terminal("cmake --install " .. vim.fn.shellescape(build))
end, { desc = icons.ui.Package .. " Install" })

--- Open CMakeCache.txt for direct editing.
---
--- The CMake cache stores all configured variables (paths, options,
--- build type). Direct editing is useful for tweaking variables
--- without reconfiguring the entire project.
---
--- Notifies if the cache doesn't exist (project not yet configured).
keys.lang_map("cmake", "n", "<leader>le", function()
	local build = detect_build_dir()
	local cache = vim.fn.getcwd() .. "/" .. build .. "/CMakeCache.txt"
	if vim.fn.filereadable(cache) == 1 then
		vim.cmd.edit(cache)
	else
		vim.notify("CMakeCache.txt not found (configure first?)", vim.log.levels.WARN, { title = "CMake" })
	end
end, { desc = cmake_icon .. " Edit CMakeCache" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- CMake command documentation via the built-in `--help-command` flag
-- and browser-based reference access.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show CMake help for the command under cursor.
---
--- Runs `cmake --help-command <word>` which outputs the full
--- documentation for the given CMake command (e.g. `add_executable`,
--- `target_link_libraries`, `install`).
---
--- If no word is under the cursor, prompts for manual input.
keys.lang_map("cmake", "n", "<leader>ld", function()
	if not check_cmake() then return end
	local word = vim.fn.expand("<cword>")
	if word == "" then
		vim.ui.input({ prompt = "CMake command: " }, function(cmd)
			if not cmd or cmd == "" then return end
			vim.cmd.split()
			vim.cmd.terminal("cmake --help-command " .. vim.fn.shellescape(cmd))
		end)
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("cmake --help-command " .. vim.fn.shellescape(word))
end, { desc = icons.ui.Note .. " CMake help" })

--- Open CMake documentation in the default browser.
---
--- Navigates to the latest CMake documentation at
--- `https://cmake.org/cmake/help/latest/`.
keys.lang_map("cmake", "n", "<leader>lh", function()
	vim.ui.open("https://cmake.org/cmake/help/latest/")
end, { desc = icons.ui.Note .. " Documentation (browser)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers CMake-specific alignment presets when mini.align is
-- available. Loaded once per session (guarded by is_language_loaded).
--
-- Preset: cmake_set — align `set()` and `list()` command arguments
-- by whitespace, useful for aligning multi-line variable definitions.
--
-- Example:
--   set(SOURCES
--       main.c
--       utils.c
--       parser.c
--   )
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("cmake") then
		---@type string Alignment preset icon from icons.lang
		local align_icon = icons.lang.cmake

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			cmake_set = {
				description = "Align CMake set() arguments",
				icon = align_icon,
				split_pattern = "%s+",
				category = "devops",
				lang = "cmake",
				filetypes = { "cmake" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("cmake", "cmake_set")
		align_registry.mark_language_loaded("cmake")

		-- ── Alignment keymap ─────────────────────────────────────────
		keys.lang_map("cmake", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("cmake_set"), {
			desc = align_icon .. "  Align CMake set",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the CMake-specific
-- parts (servers, formatters, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for CMake                  │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (cmake added to servers)          │
-- │ mason.nvim         │ opts fn (conditional Python version check)   │
-- │ conform.nvim       │ opts merge (formatters_by_ft.cmake)          │
-- │ nvim-lint          │ opts merge (linters_by_ft.cmake)             │
-- │ nvim-treesitter    │ opts merge (cmake parser to ensure_installed)│
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Mason tool installation is conditional:
-- • cmake-language-server requires Python ≥ 3.8 and < 3.14
-- • cmakelang + cmakelint require cmake in PATH
-- This prevents install failures in environments that don't meet
-- the prerequisites.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for CMake
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────
	-- cmake-language-server: provides completions for CMake commands,
	-- variables, and targets. Includes built-in linting support that
	-- runs on file open and save.
	-- ────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				cmake = {
					settings = {
						cmake = {
							lint = {
								afterOpen = true,
								afterSave = true,
							},
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype detection ──────────────────────────────────
			-- CMake uses several file naming conventions:
			-- • CMakeLists.txt     — primary project definition file
			-- • *.cmake            — CMake module/script files
			-- • *.cmake.in         — template files (configure_file)
			-- • CMakePresets.json   — preset configuration (JSON)
			vim.filetype.add({
				filename = {
					["CMakeLists.txt"] = "cmake",
					["CMakePresets.json"] = "json",
					["CMakeUserPresets.json"] = "json",
				},
				extension = {
					cmake = "cmake",
				},
				pattern = {
					["%.cmake%.in$"] = "cmake",
				},
			})

			-- ── Buffer-local options for CMake files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "cmake" },
				callback = function()
					local opt = vim.opt_local

					-- ── Layout ────────────────────────────────────────
					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120

					-- ── Indentation (CMake convention: 2 spaces) ─────
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
					opt.commentstring = "# %s"
				end,
				desc = "NvimEnterprise: CMake buffer options",
			})
		end,
	},

	-- ── MASON TOOLS (conditional installation) ─────────────────────────
	-- cmake-language-server is a Python package that requires Python
	-- ≥ 3.8 and < 3.14 (due to dependency constraints). The opts
	-- function dynamically checks the Python version before adding
	-- it to ensure_installed.
	--
	-- cmakelang (provides cmake-format) and cmakelint are only added
	-- if cmake itself is available in PATH.
	--
	-- This conditional approach prevents Mason install failures in
	-- environments that don't meet the prerequisites.
	-- ────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}

			-- ── Check Python version compatibility ────────────────────
			---@type boolean
			local python_ok = false
			if vim.fn.executable("python3") == 1 then
				---@type string|nil
				local version = vim.fn.system("python3 --version 2>/dev/null"):match("(%d+%.%d+)")
				local major_minor = tonumber(version)
				if major_minor and major_minor >= 3.8 and major_minor < 3.14 then python_ok = true end
			end

			-- ── Conditionally add tools ───────────────────────────────
			if vim.fn.executable("cmake") == 1 then vim.list_extend(opts.ensure_installed, { "cmakelang", "cmakelint" }) end
			if python_ok and vim.fn.executable("cmake") == 1 then
				vim.list_extend(opts.ensure_installed, { "cmake-language-server" })
			end
		end,
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────
	-- cmake-format (from the cmakelang package) for consistent CMake
	-- file formatting. Handles command casing, argument alignment,
	-- and keyword spacing.
	-- ────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				cmake = { "cmake_format" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────
	-- cmakelint: static analysis for CMake files. Checks for common
	-- issues like deprecated commands, missing minimum version,
	-- and style violations.
	-- ────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				cmake = { "cmakelint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────
	-- cmake: syntax highlighting, folding, and indentation for
	-- CMakeLists.txt and .cmake files.
	-- ────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"cmake",
			},
		},
	},
}
