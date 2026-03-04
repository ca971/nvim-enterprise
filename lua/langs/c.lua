---@file lua/langs/c.lua
---@description C — Compiler, LSP (clangd), formatter, linter, DAP, CMake integration
---@module "langs.c"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps               Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons                 Icon provider (`lang.c`, `app.Cpp`, `ui`, `dev`, `diagnostics`)
---@see core.mini-align-registry   Alignment preset registration for C struct/define
---@see langs.cpp                  C++ support (shared clangd, clang-format, codelldb)
---@see langs.rust                 Rust support (similar systems-level toolchain pattern)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/c.lua — C language support                                        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("c") → {} if off            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Detection layers:                                               │    ║
--- ║  │  ├─ Compiler    gcc > clang > cc (PATH-based resolution)         │    ║
--- ║  │  ├─ Build sys   Makefile / CMakeLists.txt (auto-detected)        │    ║
--- ║  │  ├─ Compile DB  compile_commands.json (root or build/)           │    ║
--- ║  │  └─ Filetype    .c → c, .h → c (overridable via modeline)        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = "c"):                            │    ║
--- ║  │  ├─ LSP         clangd (background-index, clang-tidy, IWYU)      │    ║
--- ║  │  │              + clangd_extensions (AST, symbols, type hier.)   │    ║
--- ║  │  ├─ Formatter   clang-format (LLVM style, 4-space indent)        │    ║
--- ║  │  ├─ Linter      cppcheck (warning, style, perf, portability)     │    ║
--- ║  │  ├─ Treesitter  c · doxygen · make · cmake parsers               │    ║
--- ║  │  ├─ DAP         codelldb (via mason-nvim-dap)                    │    ║
--- ║  │  └─ CMake       cmake-tools.nvim (conditional on CMakeLists.txt) │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (buffer-local, <leader>l group, 20 bindings):           │    ║
--- ║  │  ├─ COMPILE     r  Compile + run       R  Run with arguments     │    ║
--- ║  │  │              c  Compile (debug -g)   C  Compile (optimized)   │    ║
--- ║  │  │              b  Build (make)                                  │    ║
--- ║  │  ├─ NAVIGATE    s  Switch header/source                          │    ║
--- ║  │  ├─ INTEL       i  Symbol info          h  Man page (§2/3)       │    ║
--- ║  │  ├─ PREPROC     e  Preprocess (macros)  a  Assembly output       │    ║
--- ║  │  ├─ TEST/PROF   t  Run tests            p  Valgrind (memcheck)   │    ║
--- ║  │  ├─ TOOLS       o  compile_commands.json x  Clang-tidy fix       │    ║
--- ║  │  ├─ DEBUG       d  Debug (codelldb)                              │    ║
--- ║  │  └─ CMAKE       m  → CMake sub-group                             │    ║
--- ║  │     ├─ mc  Configure              mb  Build                      │    ║
--- ║  │     ├─ mr  Run                    ms  Select target              │    ║
--- ║  │     ├─ mk  Clean                  mt  Select build type          │    ║
--- ║  │     └─     (Debug/Release/RelWithDebInfo/MinSizeRel)             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Header/source switch strategy (3-tier fallback):                │    ║
--- ║  │  ├─ 1. :ClangdSwitchSourceHeader (clangd_extensions command)     │    ║
--- ║  │  ├─ 2. textDocument/switchSourceHeader (clangd LSP method)       │    ║
--- ║  │  └─ 3. Manual .c ↔ .h extension toggle (last resort)             │    ║
--- ║  │                                                                  │    ║
--- ║  │  compile_commands.json generation strategy:                      │    ║
--- ║  │  ├─ CMakeLists.txt → cmake -B build -DCMAKE_EXPORT_...           │    ║
--- ║  │  ├─ Makefile + bear → bear -- make                               │    ║
--- ║  │  └─ Neither → error with install instructions                    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Mini.align integration:                                         │    ║
--- ║  │  ├─ Preset: c_struct  (align struct members)                     │    ║
--- ║  │  ├─ Preset: c_define  (align #define macros)                     │    ║
--- ║  │  ├─ <leader>aL  Align C struct                                   │    ║
--- ║  │  └─ <leader>aT  Align C #define                                  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (set on FileType c):                                     ║
--- ║  • 4 spaces, expandtab        (LLVM / kernel-friendly indentation)       ║
--- ║  • colorcolumn=80              (C89/C99 convention: 80 columns)          ║
--- ║  • treesitter foldexpr         (foldmethod=expr, foldlevel=99)           ║
--- ║                                                                          ║
--- ║  clangd flags:                                                           ║
--- ║  • --background-index          (index project files in background)       ║
--- ║  • --clang-tidy                (enable clang-tidy diagnostics)           ║
--- ║  • --header-insertion=iwyu     (include-what-you-use suggestions)        ║
--- ║  • --completion-style=detailed (show full signature completions)         ║
--- ║  • --function-arg-placeholders (insert argument placeholders)            ║
--- ║  • --fallback-style=llvm       (fallback formatting style)               ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if C support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("c") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")
local has_executable = require("core.utils").has_executable

---@type string C Nerd Font icon (trailing whitespace stripped)
local c_icon = icons.lang.c:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group as " C" in which-key for C buffers.
-- All lang_map() calls below bind into this group.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("c", "C", c_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — COMPILER DETECTION
--
-- C compilation requires a compiler on the system PATH. This helper
-- detects the best available compiler in preference order:
-- gcc (most common on Linux) → clang (macOS default) → cc (POSIX alias).
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the best available C compiler.
---
--- Resolution order:
--- 1. `gcc`   — GNU Compiler Collection (most common on Linux)
--- 2. `clang` — LLVM Clang (macOS default, also common on Linux)
--- 3. `cc`    — POSIX alias (may point to either gcc or clang)
---
--- ```lua
--- local cc = get_cc()
--- if cc then
---   vim.cmd.terminal(cc .. " -o output source.c")
--- end
--- ```
---
---@return string|nil compiler Compiler command name, or `nil` if none found
---@private
local function get_cc()
	if has_executable("gcc") then return "gcc" end
	if has_executable("clang") then return "clang" end
	if has_executable("cc") then return "cc" end
	return nil
end

--- Notify the user that no C compiler was found.
---
--- Centralizes the error notification to avoid repetition across
--- all keymaps that require a compiler binary.
---
---@return nil
---@private
local function notify_no_cc()
	vim.notify("No C compiler found (gcc, clang, cc)", vim.log.levels.ERROR, { title = "C" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COMPILE & RUN
--
-- Single-file compilation and execution. Supports debug builds (with -g
-- for DAP compatibility) and optimized builds (with -O2 and NDEBUG).
--
-- Compilation flags:
-- ├─ Debug:     -Wall -Wextra -Wpedantic -g -std=c17
-- ├─ Optimized: -Wall -Wextra -O2 -DNDEBUG -std=c17
-- └─ Quick run: -Wall -Wextra -g (compile + immediate execution)
--
-- Output binary: same name as source file without extension
-- (e.g. main.c → main)
-- ═══════════════════════════════════════════════════════════════════════════

--- Compile and immediately run the current file.
---
--- Uses debug flags (`-Wall -Wextra -g`) for a quick compile-and-run
--- cycle. The output binary is placed alongside the source file with
--- the extension stripped. Both compilation and execution happen in
--- a single chained shell command.
keys.lang_map("c", "n", "<leader>lr", function()
	local cc = get_cc()
	if not cc then
		notify_no_cc()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local output = vim.fn.expand("%:p:r")
	vim.cmd.split()
	vim.cmd.terminal(
		string.format(
			"%s -Wall -Wextra -g -o %s %s && %s",
			cc,
			vim.fn.shellescape(output),
			vim.fn.shellescape(file),
			vim.fn.shellescape(output)
		)
	)
end, { desc = icons.ui.Play .. " Run file" })

--- Run a previously compiled binary with user-provided arguments.
---
--- Checks that the binary exists (derived from the current filename
--- without extension). If not found, prompts the user to compile first.
keys.lang_map("c", "n", "<leader>lR", function()
	local output = vim.fn.expand("%:p:r")
	if vim.fn.filereadable(output) ~= 1 then
		vim.notify("Compile first: <leader>lc", vim.log.levels.WARN, { title = "C" })
		return
	end
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal(vim.fn.shellescape(output) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Compile the current file with debug symbols.
---
--- Uses strict warning flags and the C17 standard:
--- `-Wall -Wextra -Wpedantic -g -std=c17`
---
--- The `-g` flag generates DWARF debug info required by DAP (codelldb).
--- Output binary is placed alongside the source file.
keys.lang_map("c", "n", "<leader>lc", function()
	local cc = get_cc()
	if not cc then
		notify_no_cc()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local output = vim.fn.expand("%:p:r")
	vim.cmd.split()
	vim.cmd.terminal(
		string.format(
			"%s -Wall -Wextra -Wpedantic -g -std=c17 -o %s %s",
			cc,
			vim.fn.shellescape(output),
			vim.fn.shellescape(file)
		)
	)
end, { desc = c_icon .. " Compile (debug -g)" })

--- Compile the current file with optimizations.
---
--- Uses `-O2` optimization level and `-DNDEBUG` to disable `assert()`.
--- This produces a release-quality binary without debug symbols.
--- Not suitable for DAP debugging.
keys.lang_map("c", "n", "<leader>lC", function()
	local cc = get_cc()
	if not cc then
		notify_no_cc()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local output = vim.fn.expand("%:p:r")
	vim.cmd.split()
	vim.cmd.terminal(
		string.format(
			"%s -Wall -Wextra -O2 -DNDEBUG -std=c17 -o %s %s",
			cc,
			vim.fn.shellescape(output),
			vim.fn.shellescape(file)
		)
	)
end, { desc = c_icon .. " Compile (optimized -O2)" })

--- Build the project using Make.
---
--- Requires a `Makefile` or `makefile` in the current working directory.
--- Saves the buffer before invoking `make` in a terminal split.
keys.lang_map("c", "n", "<leader>lb", function()
	if vim.fn.filereadable("Makefile") ~= 1 and vim.fn.filereadable("makefile") ~= 1 then
		vim.notify("No Makefile found in cwd", vim.log.levels.WARN, { title = "C" })
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("make")
end, { desc = icons.dev.Build .. " Build (make)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — NAVIGATION
--
-- Header/source switching using a 3-tier fallback strategy:
-- 1. clangd_extensions command (:ClangdSwitchSourceHeader)
-- 2. clangd LSP method (textDocument/switchSourceHeader)
-- 3. Manual .c ↔ .h extension toggle (last resort)
-- ═══════════════════════════════════════════════════════════════════════════

--- Switch between header (.h) and source (.c) files.
---
--- Uses a 3-tier fallback strategy:
--- 1. `:ClangdSwitchSourceHeader` — fastest, requires clangd_extensions.nvim
--- 2. `textDocument/switchSourceHeader` — direct LSP method call to clangd
--- 3. Manual toggle — swaps `.c` ↔ `.h` extension and checks file existence
---
--- The manual fallback handles simple single-directory layouts. For complex
--- projects with separate `src/` and `include/` directories, tiers 1-2
--- provide accurate results via clangd's compilation database.
keys.lang_map("c", "n", "<leader>ls", function()
	-- ── Tier 1: clangd_extensions command ─────────────────────────────
	if vim.fn.exists(":ClangdSwitchSourceHeader") == 2 then
		vim.cmd("ClangdSwitchSourceHeader")
		return
	end

	-- ── Tier 2: clangd LSP method ─────────────────────────────────────
	local clients = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })
	if #clients > 0 then
		local params = { uri = vim.uri_from_bufnr(0) }
		clients[1]:request("textDocument/switchSourceHeader", params, function(err, result)
			if not err and result then
				vim.cmd.edit(vim.uri_to_fname(result))
			else
				vim.notify("No alternate file found", vim.log.levels.INFO, { title = "C" })
			end
		end, 0)
		return
	end

	-- ── Tier 3: manual .c ↔ .h toggle ────────────────────────────────
	local ext = vim.fn.expand("%:e")
	---@type string|nil
	local alt = ext == "c" and "h" or (ext == "h" and "c" or nil)
	if alt then
		local target = vim.fn.expand("%:p:r") .. "." .. alt
		if vim.fn.filereadable(target) == 1 then
			vim.cmd.edit(target)
		else
			vim.notify("File not found: " .. target, vim.log.levels.INFO, { title = "C" })
		end
	end
end, { desc = c_icon .. " Switch header/source" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CODE INTELLIGENCE
--
-- Symbol information and man page lookup for C library functions.
-- Man page lookup tries section 3 (library) first, then section 2
-- (syscalls), then falls back to any section.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show symbol information under cursor.
---
--- Prefers `:ClangdSymbolInfo` from clangd_extensions.nvim which shows
--- detailed type info, USR, and definition location. Falls back to
--- standard LSP hover if the extension is not loaded.
keys.lang_map("c", "n", "<leader>li", function()
	if vim.fn.exists(":ClangdSymbolInfo") == 2 then
		vim.cmd("ClangdSymbolInfo")
	else
		vim.lsp.buf.hover()
	end
end, { desc = icons.diagnostics.Info .. " Symbol info" })

--- Look up the C library function under cursor in man pages.
---
--- Section resolution order:
--- 1. Section 3 — C library functions (`printf`, `malloc`, `fopen`)
--- 2. Section 2 — System calls (`read`, `write`, `fork`, `mmap`)
--- 3. Any section — Fallback for non-standard entries
---
--- Uses `pcall()` for each attempt to gracefully handle missing pages.
keys.lang_map("c", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then
		vim.notify("No word under cursor", vim.log.levels.INFO, { title = "C" })
		return
	end
	-- ── Section 3 (library functions) first ───────────────────────────
	local ok = pcall(vim.cmd, "Man 3 " .. word)
	if not ok then
		-- ── Section 2 (syscalls) ──────────────────────────────────────
		ok = pcall(vim.cmd, "Man 2 " .. word)
		if not ok then
			-- ── Any section ───────────────────────────────────────────
			pcall(vim.cmd, "Man " .. word)
		end
	end
end, { desc = icons.ui.Note .. " Man page (§2/3)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PREPROCESSING & ASSEMBLY
--
-- Low-level inspection tools for understanding the C compilation pipeline:
-- ├─ Preprocess (-E):  expand macros, includes, and conditional compilation
-- └─ Assembly (-S):    generate human-readable Intel-syntax assembly output
-- ═══════════════════════════════════════════════════════════════════════════

--- Preprocess the current file (expand all macros and includes).
---
--- Runs `cc -E <file>` which outputs the fully preprocessed translation
--- unit to the terminal. Useful for debugging macro expansions,
--- `#include` chains, and conditional compilation (`#ifdef`).
keys.lang_map("c", "n", "<leader>le", function()
	local cc = get_cc()
	if not cc then
		notify_no_cc()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal(string.format("%s -E %s", cc, vim.fn.shellescape(file)))
end, { desc = c_icon .. " Preprocess (expand macros)" })

--- Generate assembly output for the current file.
---
--- Runs `cc -S -masm=intel` to produce Intel-syntax assembly (more
--- readable than AT&T syntax). The `.s` file is generated alongside
--- the source and its contents are displayed via `cat`.
---
--- Useful for understanding compiler optimizations, cache-friendly
--- code patterns, and low-level performance analysis.
keys.lang_map("c", "n", "<leader>la", function()
	local cc = get_cc()
	if not cc then
		notify_no_cc()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local asm_file = vim.fn.expand("%:p:r") .. ".s"
	vim.cmd.split()
	vim.cmd.terminal(
		string.format(
			"%s -S -masm=intel -o %s %s && cat %s",
			cc,
			vim.fn.shellescape(asm_file),
			vim.fn.shellescape(file),
			vim.fn.shellescape(asm_file)
		)
	)
end, { desc = c_icon .. " Assembly output" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TESTING & PROFILING
--
-- Test execution and memory analysis.
--
-- Test runner resolution:
-- ├─ cmake-tools.nvim  → :CMakeRunTest (if plugin loaded)
-- ├─ CTest             → ctest in build/ (if CTestTestfile.cmake exists)
-- ├─ Makefile           → make test (if Makefile exists)
-- └─ None              → error notification
--
-- Memory profiling uses Valgrind with full leak checking, reachable
-- block detection, and origin tracking for uninitialized values.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run tests using the best available test runner.
---
--- Resolution order:
--- 1. `cmake-tools.nvim` `:CMakeRunTest` — integrated CMake test runner
--- 2. CTest via `build/CTestTestfile.cmake` — `ctest --output-on-failure`
--- 3. Make target — `make test`
--- 4. Error notification if no runner is found
keys.lang_map("c", "n", "<leader>lt", function()
	-- ── Strategy 1: cmake-tools.nvim ──────────────────────────────────
	if vim.fn.exists(":CMakeRun") == 2 then
		vim.cmd("CMakeRunTest")
		return
	end

	-- ── Strategy 2: CTest ─────────────────────────────────────────────
	if vim.fn.filereadable("build/CTestTestfile.cmake") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("cd build && ctest --output-on-failure")
		return
	end

	-- ── Strategy 3: Make ──────────────────────────────────────────────
	if vim.fn.filereadable("Makefile") == 1 or vim.fn.filereadable("makefile") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("make test")
		return
	end

	vim.notify("No test runner found (Makefile, CTest)", vim.log.levels.WARN, { title = "C" })
end, { desc = icons.dev.Test .. " Run tests" })

--- Run Valgrind memory check on the compiled binary.
---
--- Requires:
--- 1. A compiled binary (same name as source without extension)
--- 2. Valgrind installed on the system
---
--- Valgrind flags:
--- - `--leak-check=full`       — report all memory leaks with details
--- - `--show-reachable=yes`    — also show blocks still reachable at exit
--- - `--track-origins=yes`     — track origins of uninitialized values
---
--- NOTE: Compile with `-g` (debug) for meaningful source-level output.
keys.lang_map("c", "n", "<leader>lp", function()
	local output = vim.fn.expand("%:p:r")
	if vim.fn.filereadable(output) ~= 1 then
		vim.notify("Compile first: <leader>lc", vim.log.levels.WARN, { title = "C" })
		return
	end
	if vim.fn.executable("valgrind") ~= 1 then
		vim.notify("Install valgrind for memory checking", vim.log.levels.WARN, { title = "C" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("valgrind --leak-check=full --show-reachable=yes --track-origins=yes " .. vim.fn.shellescape(output))
end, { desc = icons.ui.Bug .. " Valgrind (memory check)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Development utilities: compile_commands.json generation and
-- clang-tidy automated fixes.
--
-- compile_commands.json is required by clangd for accurate
-- cross-translation-unit analysis, include path resolution,
-- and macro definition awareness.
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate `compile_commands.json` for clangd LSP.
---
--- Strategy:
--- 1. `CMakeLists.txt` found → `cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`
---    + symlink `build/compile_commands.json` to project root
--- 2. `Makefile` found + `bear` installed → `bear -- make`
---    (Bear intercepts compiler calls to generate the database)
--- 3. Neither → error with install instructions
---
--- `compile_commands.json` enables clangd to resolve includes, macros,
--- and compiler flags correctly across the entire project.
keys.lang_map("c", "n", "<leader>lo", function()
	if vim.fn.filereadable("CMakeLists.txt") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && ln -sf build/compile_commands.json .")
		vim.notify("Generating via cmake…", vim.log.levels.INFO, { title = "C" })
	elseif vim.fn.filereadable("Makefile") == 1 or vim.fn.filereadable("makefile") == 1 then
		if vim.fn.executable("bear") == 1 then
			vim.cmd.split()
			vim.cmd.terminal("bear -- make")
		else
			vim.notify(
				"Install bear: brew install bear\nor use cmake with -DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
				vim.log.levels.WARN,
				{ title = "C" }
			)
		end
	else
		vim.notify("No CMakeLists.txt or Makefile found", vim.log.levels.WARN, { title = "C" })
	end
end, { desc = icons.ui.Gear .. " Generate compile_commands.json" })

--- Apply clang-tidy automated fixes to the current file.
---
--- Auto-detects `compile_commands.json` in either the project root
--- or `build/` subdirectory. Without a compilation database, clang-tidy
--- may produce false positives due to missing include paths.
---
--- Uses `--fix` flag which modifies the file in-place. The buffer
--- should be reloaded (`:edit`) after fixes are applied.
keys.lang_map("c", "n", "<leader>lx", function()
	if vim.fn.executable("clang-tidy") ~= 1 then
		vim.notify("Install clang-tidy", vim.log.levels.WARN, { title = "C" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	---@type string
	local compile_db = ""
	if vim.fn.filereadable("compile_commands.json") == 1 then
		compile_db = "-p " .. vim.fn.getcwd()
	elseif vim.fn.filereadable("build/compile_commands.json") == 1 then
		compile_db = "-p build"
	end

	vim.cmd.split()
	vim.cmd.terminal(string.format("clang-tidy --fix %s %s", compile_db, vim.fn.shellescape(file)))
end, { desc = c_icon .. " Clang-tidy fix" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via codelldb (LLVM debug adapter).
-- Requires a binary compiled with `-g` (debug symbols).
-- After loading, all core DAP keymaps work:
-- <leader>dc, <leader>db, <leader>di, <leader>do, F5, F9, etc.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Saves the buffer, then calls `dap.continue()` which either resumes
--- a paused session or launches a new one using the codelldb adapter.
--- Requires nvim-dap and codelldb to be installed via Mason.
---
--- NOTE: The binary must be compiled with `-g` for source-level
--- debugging. Use `<leader>lc` (compile debug) before debugging.
keys.lang_map("c", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "C" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (codelldb)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CMAKE SUB-GROUP
--
-- CMake project management keymaps under <leader>lm prefix.
-- Integrates with cmake-tools.nvim when available, falls back to
-- direct cmake CLI commands otherwise.
--
-- Build types supported: Debug, Release, RelWithDebInfo, MinSizeRel
--
-- cmake-tools.nvim provides:
-- ├─ :CMakeGenerate        → cmake -B build
-- ├─ :CMakeBuild           → cmake --build build
-- ├─ :CMakeRun             → run selected launch target
-- ├─ :CMakeSelectLaunchTarget → pick target from available executables
-- ├─ :CMakeClean           → cmake --build build --target clean
-- └─ :CMakeSelectBuildType → switch Debug/Release/etc.
-- ═══════════════════════════════════════════════════════════════════════════

--- CMake sub-group placeholder.
---
--- This is a no-op keymap that serves as the which-key group header
--- for the `<leader>lm` CMake sub-group.
keys.lang_map("c", "n", "<leader>lm", function() end, {
	desc = icons.ui.Gear .. " CMake",
})

--- CMake: configure and generate build system.
---
--- Prefers `cmake-tools.nvim` `:CMakeGenerate` if available, otherwise
--- falls back to direct `cmake -B build` with compile commands export.
keys.lang_map("c", "n", "<leader>lmc", function()
	if vim.fn.exists(":CMakeGenerate") == 2 then
		vim.cmd("CMakeGenerate")
	elseif vim.fn.executable("cmake") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON")
	else
		vim.notify("cmake not found", vim.log.levels.WARN, { title = "C" })
	end
end, { desc = icons.ui.Gear .. " Configure" })

--- CMake: build the project.
---
--- Prefers `cmake-tools.nvim` `:CMakeBuild` if available, otherwise
--- falls back to `cmake --build build`.
keys.lang_map("c", "n", "<leader>lmb", function()
	if vim.fn.exists(":CMakeBuild") == 2 then
		vim.cmd("CMakeBuild")
	elseif vim.fn.executable("cmake") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("cmake --build build")
	else
		vim.notify("cmake not found", vim.log.levels.WARN, { title = "C" })
	end
end, { desc = icons.dev.Build .. " Build" })

--- CMake: run the selected launch target.
---
--- Requires `cmake-tools.nvim` to be loaded. Use `<leader>lms` to
--- select the target first.
keys.lang_map("c", "n", "<leader>lmr", function()
	if vim.fn.exists(":CMakeRun") == 2 then
		vim.cmd("CMakeRun")
	else
		vim.notify("cmake-tools.nvim not loaded", vim.log.levels.WARN, { title = "C" })
	end
end, { desc = icons.ui.Play .. " Run" })

--- CMake: select the launch target from available executables.
---
--- Requires `cmake-tools.nvim` to be loaded. Opens a picker to choose
--- which built executable to run with `<leader>lmr`.
keys.lang_map("c", "n", "<leader>lms", function()
	if vim.fn.exists(":CMakeSelectLaunchTarget") == 2 then
		vim.cmd("CMakeSelectLaunchTarget")
	else
		vim.notify("cmake-tools.nvim not loaded", vim.log.levels.WARN, { title = "C" })
	end
end, { desc = icons.ui.Target .. " Select target" })

--- CMake: clean the build directory.
---
--- Prefers `cmake-tools.nvim` `:CMakeClean` if available, otherwise
--- falls back to `cmake --build build --target clean`.
keys.lang_map("c", "n", "<leader>lmk", function()
	if vim.fn.exists(":CMakeClean") == 2 then
		vim.cmd("CMakeClean")
	elseif vim.fn.executable("cmake") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("cmake --build build --target clean")
	else
		vim.notify("cmake not found", vim.log.levels.WARN, { title = "C" })
	end
end, { desc = icons.ui.Close .. " Clean" })

--- CMake: select the build type.
---
--- Prefers `cmake-tools.nvim` `:CMakeSelectBuildType` if available.
--- Falls back to a `vim.ui.select()` picker with 4 standard CMake
--- build types, then reconfigures with the selected type.
---
--- Build types:
--- - `Debug`          — no optimization, full debug symbols
--- - `Release`        — full optimization, no debug symbols
--- - `RelWithDebInfo` — optimization + debug symbols (best of both)
--- - `MinSizeRel`     — optimize for binary size
keys.lang_map("c", "n", "<leader>lmt", function()
	if vim.fn.exists(":CMakeSelectBuildType") == 2 then
		vim.cmd("CMakeSelectBuildType")
	else
		---@type string[]
		local build_types = { "Debug", "Release", "RelWithDebInfo", "MinSizeRel" }
		vim.ui.select(build_types, { prompt = "Build type:" }, function(choice)
			if choice then
				vim.cmd.split()
				vim.cmd.terminal("cmake -B build -DCMAKE_BUILD_TYPE=" .. choice .. " -DCMAKE_EXPORT_COMPILE_COMMANDS=ON")
			end
		end)
	end
end, { desc = icons.ui.List .. " Build type" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers C-specific alignment presets when mini.align is available.
-- Loaded once per session (guarded by is_language_loaded).
--
-- Presets:
-- ├─ c_struct  — align struct member declarations by whitespace
-- └─ c_define  — align #define macro values by whitespace
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("c") then
		---@type string Alignment preset icon from icons.app
		local align_icon = icons.app.Cpp

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			c_struct = {
				description = "Align C struct members",
				icon = align_icon,
				split_pattern = "%s+",
				category = "systems",
				lang = "c",
				filetypes = { "c" },
			},
			c_define = {
				description = "Align C #define macros",
				icon = align_icon,
				split_pattern = "%s+",
				category = "systems",
				lang = "c",
				filetypes = { "c" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("c", "c_struct")
		align_registry.mark_language_loaded("c")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("c", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("c_struct"), {
			desc = align_icon .. "  Align C struct",
		})
		keys.lang_map("c", { "n", "x" }, "<leader>aT", align_registry.make_align_fn("c_define"), {
			desc = align_icon .. "  Align C #define",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the C-specific
-- parts (servers, formatters, linters, parsers, adapters).
--
-- Loading strategy:
-- ┌─────────────────────┬─────────────────────────────────────────────┐
-- │ Plugin              │ How it lazy-loads for C                     │
-- ├─────────────────────┼─────────────────────────────────────────────┤
-- │ nvim-lspconfig      │ opts merge (clangd added to servers)        │
-- │ clangd_extensions   │ ft = { "c", "cpp", "objc", "objcpp" }      │
-- │ mason.nvim          │ opts merge (tools added to ensure_installed)│
-- │ conform.nvim        │ opts merge (formatters_by_ft.c)             │
-- │ nvim-lint           │ opts fn (conditional cppcheck registration) │
-- │ nvim-treesitter     │ opts merge (parsers added to ensure_install)│
-- │ cmake-tools.nvim    │ ft + cond (only if CMakeLists.txt exists)   │
-- │ mason-nvim-dap      │ opts merge (codelldb to ensure_installed)   │
-- └─────────────────────┴─────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for C
return {
	-- ── LSP SERVER (clangd) ────────────────────────────────────────────
	-- clangd: C/C++ language server from the LLVM project providing
	-- code completion, diagnostics, go-to-definition, cross-references,
	-- include management, and integrated clang-tidy checks.
	--
	-- Key flags:
	-- • --background-index:          index all files in the background
	-- • --clang-tidy:                enable clang-tidy diagnostics inline
	-- • --header-insertion=iwyu:     suggest include-what-you-use headers
	-- • --completion-style=detailed: show full function signatures
	-- • --function-arg-placeholders: insert argument placeholders
	-- • --fallback-style=llvm:       use LLVM style when no .clang-format
	-- ────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				clangd = {
					cmd = {
						"clangd",
						"--background-index",
						"--clang-tidy",
						"--header-insertion=iwyu",
						"--completion-style=detailed",
						"--function-arg-placeholders",
						"--fallback-style=llvm",
					},
					init_options = {
						usePlaceholders = true,
						completeUnimported = true,
						clangdFileStatus = true,
					},
				},
			},
		},
		init = function()
			-- ── Filetype detection ──────────────────────────────────
			-- Default .h files to C filetype. In mixed C/C++ projects,
			-- use a modeline or .clang-tidy to override when needed.
			vim.filetype.add({
				extension = {
					h = "c",
				},
			})

			-- ── Buffer-local options for C files ─────────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "c" },
				callback = function()
					local opt = vim.opt_local

					-- ── Layout ────────────────────────────────────────
					opt.wrap = false
					opt.colorcolumn = "80"
					opt.textwidth = 80

					-- ── Indentation (LLVM style: 4 spaces) ───────────
					opt.tabstop = 4
					opt.shiftwidth = 4
					opt.softtabstop = 4
					opt.expandtab = true

					-- ── Line numbers ──────────────────────────────────
					opt.number = true
					opt.relativenumber = true

					-- ── Folding (treesitter-based) ────────────────────
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
				end,
				desc = "NvimEnterprise: C buffer options",
			})
		end,
	},

	-- ── CLANGD EXTENSIONS ──────────────────────────────────────────────
	-- Provides AST visualization, symbol info, type hierarchy,
	-- and memory usage reports. Lazy-loaded on C/C++/ObjC filetypes.
	--
	-- role_icons/kind_icons use icons from core/icons.lua for
	-- consistent visual language across the configuration.
	-- ────────────────────────────────────────────────────────────────────
	{
		"p00f/clangd_extensions.nvim",
		lazy = true,
		ft = { "c", "cpp", "objc", "objcpp" },
		opts = {
			ast = {
				role_icons = {
					type = icons.kinds.Class,
					declaration = icons.kinds.Function,
					expression = icons.kinds.Variable,
					statement = icons.kinds.Keyword,
					specifier = icons.kinds.Property,
					["template argument"] = icons.kinds.TypeParameter,
				},
				kind_icons = {
					Compound = icons.kinds.Struct,
					Recovery = icons.diagnostics.Error,
					TranslationUnit = icons.kinds.Module,
					PackExpansion = icons.ui.Ellipsis,
					TemplateTypeParm = icons.kinds.TypeParameter,
					TemplateTemplateParm = icons.kinds.TypeParameter,
					TemplateParamObject = icons.kinds.TypeParameter,
				},
			},
			memory_usage = {
				border = "rounded",
			},
			symbol_info = {
				border = "rounded",
			},
		},
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────
	-- Ensures clang-format (formatter) and codelldb (DAP adapter) are
	-- installed and managed by Mason.
	--
	-- NOTE: clangd itself is typically installed via the system package
	-- manager (apt, brew) rather than Mason, as it depends on LLVM.
	-- ────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"clang-format",
				"codelldb",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────
	-- clang-format with LLVM base style and project-specific overrides.
	-- If a `.clang-format` or `_clang-format` file exists in the
	-- project root, it takes precedence over the inline style config.
	--
	-- Inline style: LLVM base, 4-space indent, 80-column limit.
	-- ────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				c = { "clang-format" },
			},
			formatters = {
				["clang-format"] = {
					prepend_args = {
						"--style={BasedOnStyle: llvm, IndentWidth: 4, ColumnLimit: 80}",
					},
				},
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────
	-- cppcheck: static analysis tool for C/C++ (conditional registration).
	--
	-- Only registers the linter if cppcheck is available on the system
	-- PATH. This prevents nvim-lint errors in environments without it.
	--
	-- Enabled checks: warning, style, performance, portability.
	-- Suppressed: missingIncludeSystem (noisy with system headers).
	--
	-- NOTE: Uses opts function (not table) to conditionally merge
	-- and to configure custom linter args.
	-- ────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = function(_, opts)
			if vim.fn.executable("cppcheck") == 1 then
				opts.linters_by_ft = opts.linters_by_ft or {}
				opts.linters_by_ft.c = { "cppcheck" }

				opts.linters = opts.linters or {}
				opts.linters.cppcheck = {
					args = {
						"--enable=warning,style,performance,portability",
						"--suppress=missingIncludeSystem",
						"--inline-suppr",
						"--quiet",
						"--template=gcc",
					},
				}
			end
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────
	-- c:       syntax highlighting, folding, text objects, indentation
	-- doxygen: doc comment highlighting (/** ... */ style)
	-- make:    Makefile syntax highlighting
	-- cmake:   CMakeLists.txt syntax highlighting
	-- ────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"c",
				"doxygen",
				"make",
				"cmake",
			},
		},
	},

	-- ── CMAKE TOOLS ────────────────────────────────────────────────────
	-- cmake-tools.nvim: integrated CMake project management.
	-- Conditionally loaded only if CMakeLists.txt exists in the project.
	--
	-- Provides Neovim commands for configure, build, run, clean,
	-- target selection, and build type switching. Also integrates
	-- with DAP for CMake-aware debug sessions.
	--
	-- Default DAP configuration uses codelldb adapter.
	-- ────────────────────────────────────────────────────────────────────
	{
		"Civitasv/cmake-tools.nvim",
		lazy = true,
		ft = { "c", "cpp", "cmake" },
		cond = function()
			return vim.fn.filereadable("CMakeLists.txt") == 1
		end,
		dependencies = {
			"nvim-lua/plenary.nvim",
		},
		opts = {
			cmake_command = "cmake",
			cmake_build_directory = "build",
			cmake_generate_options = {
				"-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
			},
			cmake_build_options = {},
			cmake_console_size = 10,
			cmake_show_console = "always",
			cmake_dap_configuration = {
				name = "CMake Debug",
				type = "codelldb",
				request = "launch",
				stopOnEntry = false,
				runInTerminal = true,
				console = "integratedTerminal",
			},
		},
	},

	-- ── DAP — CODELLDB ADAPTER ─────────────────────────────────────────
	-- Ensures the codelldb debug adapter is installed via Mason.
	-- codelldb supports C, C++, Rust, and other LLVM-based languages.
	--
	-- After loading, all core DAP keymaps work in C files:
	-- <leader>dc, <leader>db, <leader>di, <leader>do, F5, F9, etc.
	-- ────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "codelldb" },
		},
	},
}
