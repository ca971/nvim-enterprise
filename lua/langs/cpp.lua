---@file lua/langs/cpp.lua
---@description C++ — Compiler, LSP (clangd), formatter, linter, DAP, CMake integration
---@module "langs.cpp"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps               Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons                 Icon provider (`lang.cpp`, `app.Cpp`, `ui`, `dev`)
---@see core.mini-align-registry   Alignment preset registration for C++ struct/class
---@see langs.c                    C support (shared clangd, clang-format, codelldb, cmake-tools)
---@see langs.cmake                CMake support (shared cmake-tools.nvim)
---@see langs.rust                 Rust support (similar systems-level toolchain pattern)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/cpp.lua — C++ language support                                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("cpp") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Detection layers:                                               │    ║
--- ║  │  ├─ Compiler    g++ > clang++ > c++ (PATH-based resolution)      │    ║
--- ║  │  ├─ Build sys   Makefile / CMakeLists.txt (auto-detected)        │    ║
--- ║  │  ├─ Compile DB  compile_commands.json (root or build/)           │    ║
--- ║  │  └─ Filetype    .cpp .cxx .cc .hpp .hxx .hh → cpp                │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = "cpp"):                          │    ║
--- ║  │  ├─ LSP         clangd (shared with C — background-index, tidy)  │    ║
--- ║  │  │              + clangd_extensions (AST, symbols, type hier.)   │    ║
--- ║  │  ├─ Formatter   clang-format (LLVM style, 4-space, 100-col)      │    ║
--- ║  │  ├─ Linter      cppcheck --language=c++ --std=c++20 (conditional)│    ║
--- ║  │  ├─ Treesitter  cpp · doxygen · make · cmake parsers             │    ║
--- ║  │  ├─ DAP         codelldb (via mason-nvim-dap)                    │    ║
--- ║  │  └─ CMake       cmake-tools.nvim (conditional on CMakeLists.txt) │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (buffer-local, <leader>l group, 20 bindings):           │    ║
--- ║  │  ├─ COMPILE     r  Compile + run       R  Run with arguments     │    ║
--- ║  │  │              c  Compile (debug -g)   C  Compile (optimized)   │    ║
--- ║  │  │              b  Build (make)                                  │    ║
--- ║  │  ├─ NAVIGATE    s  Switch header/source (3-tier fallback)        │    ║
--- ║  │  ├─ INTEL       i  Symbol info          h  Man / cppreference    │    ║
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
--- ║  │  └─ 3. Manual extension mapping (cpp↔hpp, cxx↔hxx, cc↔hh, etc.)  │    ║
--- ║  │                                                                  │    ║
--- ║  │  C++ vs C differences:                                           │    ║
--- ║  │  ├─ Standard: C++20 (vs C17)                                     │    ║
--- ║  │  ├─ Column limit: 100 (vs 80)                                    │    ║
--- ║  │  ├─ Header extensions: .hpp .hxx .hh (in addition to .h)         │    ║
--- ║  │  ├─ cppcheck: --language=c++ --std=c++20                         │    ║
--- ║  │  └─ cppreference browser search (C++ only)                       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Mini.align integration:                                         │    ║
--- ║  │  ├─ Preset: cpp_struct (align struct/class member declarations)  │    ║
--- ║  │  └─ <leader>aL  Align C++ struct                                 │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (set on FileType cpp):                                   ║
--- ║  • 4 spaces, expandtab        (LLVM style indentation)                   ║
--- ║  • colorcolumn=100             (modern C++ convention)                   ║
--- ║  • treesitter foldexpr         (foldmethod=expr, foldlevel=99)           ║
--- ║                                                                          ║
--- ║  clangd flags (shared with langs/c.lua):                                 ║
--- ║  • --background-index · --clang-tidy · --header-insertion=iwyu           ║
--- ║  • --completion-style=detailed · --function-arg-placeholders             ║
--- ║  • --fallback-style=llvm                                                 ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if C++ support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("cpp") then
	return {}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string C++ Nerd Font icon (trailing whitespace stripped)
local cpp_icon = icons.lang.cpp:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group as " C++" in which-key for cpp buffers.
-- All lang_map() calls below bind into this group.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("cpp", "C++", cpp_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — COMPILER DETECTION
--
-- C++ compilation requires a compiler on the system PATH. This helper
-- detects the best available C++ compiler in preference order:
-- g++ (most common on Linux) → clang++ (macOS default) → c++ (POSIX alias).
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the best available C++ compiler.
---
--- Resolution order:
--- 1. `g++`     — GNU C++ Compiler (most common on Linux)
--- 2. `clang++` — LLVM Clang++ (macOS default, also common on Linux)
--- 3. `c++`     — POSIX alias (may point to either g++ or clang++)
---
--- ```lua
--- local cxx = get_cxx()
--- if cxx then
---   vim.cmd.terminal(cxx .. " -std=c++20 -o output source.cpp")
--- end
--- ```
---
---@return string|nil compiler Compiler command name, or `nil` if none found
---@private
local function get_cxx()
	if vim.fn.executable("g++") == 1 then
		return "g++"
	end
	if vim.fn.executable("clang++") == 1 then
		return "clang++"
	end
	if vim.fn.executable("c++") == 1 then
		return "c++"
	end
	return nil
end

--- Notify the user that no C++ compiler was found.
---
--- Centralizes the error notification to avoid repetition across
--- all keymaps that require a compiler binary.
---
---@return nil
---@private
local function notify_no_cxx()
	vim.notify("No C++ compiler found (g++, clang++, c++)", vim.log.levels.ERROR, { title = "C++" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COMPILE & RUN
--
-- Single-file compilation and execution using C++20 standard.
-- Supports debug builds (with -g for DAP compatibility) and
-- optimized builds (with -O2 and NDEBUG).
--
-- Compilation flags:
-- ├─ Debug:     -Wall -Wextra -Wpedantic -g -std=c++20
-- ├─ Optimized: -Wall -Wextra -O2 -DNDEBUG -std=c++20
-- └─ Quick run: -Wall -Wextra -g -std=c++20 (compile + immediate execution)
--
-- Output binary: same name as source file without extension
-- (e.g. main.cpp → main)
-- ═══════════════════════════════════════════════════════════════════════════

--- Compile and immediately run the current file.
---
--- Uses debug flags (`-Wall -Wextra -g -std=c++20`) for a quick
--- compile-and-run cycle. Both compilation and execution happen in
--- a single chained shell command.
keys.lang_map("cpp", "n", "<leader>lr", function()
	local cxx = get_cxx()
	if not cxx then
		notify_no_cxx()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local output = vim.fn.expand("%:p:r")
	vim.cmd.split()
	vim.cmd.terminal(string.format(
		"%s -Wall -Wextra -g -std=c++20 -o %s %s && %s",
		cxx,
		vim.fn.shellescape(output),
		vim.fn.shellescape(file),
		vim.fn.shellescape(output)
	))
end, { desc = icons.ui.Play .. " Run file" })

--- Run a previously compiled binary with user-provided arguments.
---
--- Checks that the binary exists (derived from the current filename
--- without extension). If not found, prompts the user to compile first.
keys.lang_map("cpp", "n", "<leader>lR", function()
	local output = vim.fn.expand("%:p:r")
	if vim.fn.filereadable(output) ~= 1 then
		vim.notify("Compile first: <leader>lc", vim.log.levels.WARN, { title = "C++" })
		return
	end
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then
			return
		end
		vim.cmd.split()
		vim.cmd.terminal(vim.fn.shellescape(output) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Compile the current file with debug symbols.
---
--- Uses strict warning flags and the C++20 standard:
--- `-Wall -Wextra -Wpedantic -g -std=c++20`
---
--- The `-g` flag generates DWARF debug info required by DAP (codelldb).
keys.lang_map("cpp", "n", "<leader>lc", function()
	local cxx = get_cxx()
	if not cxx then
		notify_no_cxx()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local output = vim.fn.expand("%:p:r")
	vim.cmd.split()
	vim.cmd.terminal(string.format(
		"%s -Wall -Wextra -Wpedantic -g -std=c++20 -o %s %s",
		cxx,
		vim.fn.shellescape(output),
		vim.fn.shellescape(file)
	))
end, { desc = cpp_icon .. " Compile (debug -g)" })

--- Compile the current file with optimizations.
---
--- Uses `-O2` optimization level and `-DNDEBUG` to disable `assert()`.
--- Produces a release-quality binary without debug symbols.
--- Not suitable for DAP debugging.
keys.lang_map("cpp", "n", "<leader>lC", function()
	local cxx = get_cxx()
	if not cxx then
		notify_no_cxx()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local output = vim.fn.expand("%:p:r")
	vim.cmd.split()
	vim.cmd.terminal(string.format(
		"%s -Wall -Wextra -O2 -DNDEBUG -std=c++20 -o %s %s",
		cxx,
		vim.fn.shellescape(output),
		vim.fn.shellescape(file)
	))
end, { desc = cpp_icon .. " Compile (optimized -O2)" })

--- Build the project using Make.
---
--- Requires a `Makefile` or `makefile` in the current working directory.
--- Saves the buffer before invoking `make` in a terminal split.
keys.lang_map("cpp", "n", "<leader>lb", function()
	if vim.fn.filereadable("Makefile") ~= 1 and vim.fn.filereadable("makefile") ~= 1 then
		vim.notify("No Makefile found in cwd", vim.log.levels.WARN, { title = "C++" })
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("make")
end, { desc = icons.dev.Build .. " Build (make)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — NAVIGATION
--
-- Header/source switching using a 3-tier fallback strategy.
-- C++ has richer extension mappings than C due to the variety of
-- header/source conventions in the ecosystem.
--
-- Extension mappings (tier 3 fallback):
-- ├─ .cpp ↔ .hpp, .h
-- ├─ .cxx ↔ .hxx, .h
-- ├─ .cc  ↔ .hh, .h
-- ├─ .hpp ↔ .cpp, .cxx, .cc
-- ├─ .hxx ↔ .cxx, .cpp
-- ├─ .hh  ↔ .cc, .cpp
-- └─ .h   ↔ .cpp, .cxx, .cc, .c
-- ═══════════════════════════════════════════════════════════════════════════

--- Switch between header and source files.
---
--- Uses a 3-tier fallback strategy:
--- 1. `:ClangdSwitchSourceHeader` — fastest, requires clangd_extensions.nvim
--- 2. `textDocument/switchSourceHeader` — direct LSP method call to clangd
--- 3. Manual extension mapping — tries all common C++ extension pairs
---
--- The manual fallback handles the full C++ extension matrix:
--- `.cpp` ↔ `.hpp`/`.h`, `.cxx` ↔ `.hxx`/`.h`, `.cc` ↔ `.hh`/`.h`,
--- and all reverse mappings. Checks each candidate path for existence.
keys.lang_map("cpp", "n", "<leader>ls", function()
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
				vim.notify("No alternate file found", vim.log.levels.INFO, { title = "C++" })
			end
		end, 0)
		return
	end

	-- ── Tier 3: manual extension mapping ──────────────────────────────
	local ext = vim.fn.expand("%:e")
	---@type table<string, string[]> Extension → list of alternate extensions
	local alts = {
		cpp = { "hpp", "h" },
		cxx = { "hxx", "h" },
		cc = { "hh", "h" },
		hpp = { "cpp", "cxx", "cc" },
		hxx = { "cxx", "cpp" },
		hh = { "cc", "cpp" },
		h = { "cpp", "cxx", "cc", "c" },
	}

	local candidates = alts[ext]
	if candidates then
		local base = vim.fn.expand("%:p:r")
		for _, alt in ipairs(candidates) do
			local target = base .. "." .. alt
			if vim.fn.filereadable(target) == 1 then
				vim.cmd.edit(target)
				return
			end
		end
		vim.notify("No alternate file found", vim.log.levels.INFO, { title = "C++" })
	end
end, { desc = cpp_icon .. " Switch header/source" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CODE INTELLIGENCE
--
-- Symbol information and documentation lookup.
-- C++ adds cppreference.com browser search as an alternative to
-- man pages, since the C++ standard library documentation is
-- best served by cppreference.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show symbol information under cursor.
---
--- Prefers `:ClangdSymbolInfo` from clangd_extensions.nvim which shows
--- detailed type info, USR, and definition location. Falls back to
--- standard LSP hover if the extension is not loaded.
keys.lang_map("cpp", "n", "<leader>li", function()
	if vim.fn.exists(":ClangdSymbolInfo") == 2 then
		vim.cmd("ClangdSymbolInfo")
	else
		vim.lsp.buf.hover()
	end
end, { desc = icons.diagnostics.Info .. " Symbol info" })

--- Look up the word under cursor in man pages or cppreference.com.
---
--- Presents two options:
--- 1. **cppreference (search)** — opens a browser search on cppreference.com
---    for the word under cursor (best for STL types, algorithms, containers)
--- 2. **Man page** — tries sections 3 → 2 → any (best for POSIX/C functions)
---
--- If no word is under the cursor, shows a notification and returns.
keys.lang_map("cpp", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then
		vim.notify("No word under cursor", vim.log.levels.INFO, { title = "C++" })
		return
	end

	---@type { name: string, url?: string, action?: string }[]
	local refs = {
		{ name = "cppreference (search)", url = "https://en.cppreference.com/mwiki/index.php?search=" .. word },
		{ name = "Man page", action = "man" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = cpp_icon .. " Lookup '" .. word .. "':" },
		function(_, idx)
			if not idx then
				return
			end
			if refs[idx].url then
				vim.ui.open(refs[idx].url)
			elseif refs[idx].action == "man" then
				-- ── Section 3 (library) → 2 (syscalls) → any ─────────
				local ok = pcall(vim.cmd, "Man 3 " .. word)
				if not ok then
					ok = pcall(vim.cmd, "Man 2 " .. word)
					if not ok then
						pcall(vim.cmd, "Man " .. word)
					end
				end
			end
		end
	)
end, { desc = icons.ui.Note .. " Man / cppreference" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PREPROCESSING & ASSEMBLY
--
-- Low-level inspection tools for understanding the C++ compilation
-- pipeline. Uses C++20 standard for both preprocessing and assembly.
-- ═══════════════════════════════════════════════════════════════════════════

--- Preprocess the current file (expand all macros, includes, templates).
---
--- Runs `cxx -E -std=c++20 <file>` which outputs the fully preprocessed
--- translation unit. C++ preprocessing can be significantly larger than
--- C due to template instantiations and header-only libraries.
keys.lang_map("cpp", "n", "<leader>le", function()
	local cxx = get_cxx()
	if not cxx then
		notify_no_cxx()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal(string.format("%s -E -std=c++20 %s", cxx, vim.fn.shellescape(file)))
end, { desc = cpp_icon .. " Preprocess (expand macros)" })

--- Generate assembly output for the current file.
---
--- Runs `cxx -S -masm=intel -std=c++20` to produce Intel-syntax assembly.
--- C++ assembly includes name-mangled symbols; use `c++filt` to demangle.
keys.lang_map("cpp", "n", "<leader>la", function()
	local cxx = get_cxx()
	if not cxx then
		notify_no_cxx()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local asm_file = vim.fn.expand("%:p:r") .. ".s"
	vim.cmd.split()
	vim.cmd.terminal(string.format(
		"%s -S -masm=intel -std=c++20 -o %s %s && cat %s",
		cxx,
		vim.fn.shellescape(asm_file),
		vim.fn.shellescape(file),
		vim.fn.shellescape(asm_file)
	))
end, { desc = cpp_icon .. " Assembly output" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TESTING & PROFILING
--
-- Test execution and memory analysis. Identical to C module but with
-- C++ title in notifications.
--
-- Test runner resolution:
-- ├─ cmake-tools.nvim  → :CMakeRunTest (if plugin loaded)
-- ├─ CTest             → ctest in build/ (if CTestTestfile.cmake exists)
-- ├─ Makefile           → make test (if Makefile exists)
-- └─ None              → error notification
-- ═══════════════════════════════════════════════════════════════════════════

--- Run tests using the best available test runner.
---
--- Resolution order:
--- 1. `cmake-tools.nvim` `:CMakeRunTest`
--- 2. CTest via `build/CTestTestfile.cmake`
--- 3. Make target `make test`
--- 4. Error notification if no runner found
keys.lang_map("cpp", "n", "<leader>lt", function()
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

	vim.notify("No test runner found (Makefile, CTest)", vim.log.levels.WARN, { title = "C++" })
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
--- C++ smart pointers and RAII reduce but don't eliminate leak risks.
keys.lang_map("cpp", "n", "<leader>lp", function()
	local output = vim.fn.expand("%:p:r")
	if vim.fn.filereadable(output) ~= 1 then
		vim.notify("Compile first: <leader>lc", vim.log.levels.WARN, { title = "C++" })
		return
	end
	if vim.fn.executable("valgrind") ~= 1 then
		vim.notify("Install valgrind for memory checking", vim.log.levels.WARN, { title = "C++" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal(
		"valgrind --leak-check=full --show-reachable=yes --track-origins=yes " .. vim.fn.shellescape(output)
	)
end, { desc = icons.ui.Bug .. " Valgrind (memory check)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Development utilities: compile_commands.json generation and
-- clang-tidy automated fixes. Shared patterns with langs/c.lua.
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate `compile_commands.json` for clangd LSP.
---
--- Strategy:
--- 1. `CMakeLists.txt` → `cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON` + symlink
--- 2. `Makefile` + `bear` → `bear -- make`
--- 3. Neither → error with install instructions
keys.lang_map("cpp", "n", "<leader>lo", function()
	if vim.fn.filereadable("CMakeLists.txt") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && ln -sf build/compile_commands.json .")
		vim.notify("Generating via cmake…", vim.log.levels.INFO, { title = "C++" })
	elseif vim.fn.filereadable("Makefile") == 1 or vim.fn.filereadable("makefile") == 1 then
		if vim.fn.executable("bear") == 1 then
			vim.cmd.split()
			vim.cmd.terminal("bear -- make")
		else
			vim.notify(
				"Install bear: brew install bear\nor use cmake with -DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
				vim.log.levels.WARN,
				{ title = "C++" }
			)
		end
	else
		vim.notify("No CMakeLists.txt or Makefile found", vim.log.levels.WARN, { title = "C++" })
	end
end, { desc = icons.ui.Gear .. " Generate compile_commands.json" })

--- Apply clang-tidy automated fixes to the current file.
---
--- Auto-detects `compile_commands.json` in either the project root
--- or `build/` subdirectory for accurate analysis context.
keys.lang_map("cpp", "n", "<leader>lx", function()
	if vim.fn.executable("clang-tidy") ~= 1 then
		vim.notify("Install clang-tidy", vim.log.levels.WARN, { title = "C++" })
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
end, { desc = cpp_icon .. " Clang-tidy fix" })

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
---
--- NOTE: The binary must be compiled with `-g` for source-level
--- debugging. Use `<leader>lc` (compile debug) before debugging.
keys.lang_map("cpp", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "C++" })
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
-- Shared pattern with langs/c.lua — both register cmake-tools.nvim.
-- ═══════════════════════════════════════════════════════════════════════════

--- CMake sub-group placeholder (which-key group header).
keys.lang_map("cpp", "n", "<leader>lm", function() end, {
	desc = icons.ui.Gear .. " CMake",
})

--- CMake: configure and generate build system.
---
--- Prefers `cmake-tools.nvim` `:CMakeGenerate` if available, otherwise
--- falls back to direct `cmake -B build` with compile commands export.
keys.lang_map("cpp", "n", "<leader>lmc", function()
	if vim.fn.exists(":CMakeGenerate") == 2 then
		vim.cmd("CMakeGenerate")
	elseif vim.fn.executable("cmake") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON")
	else
		vim.notify("cmake not found", vim.log.levels.WARN, { title = "C++" })
	end
end, { desc = icons.ui.Gear .. " Configure" })

--- CMake: build the project.
keys.lang_map("cpp", "n", "<leader>lmb", function()
	if vim.fn.exists(":CMakeBuild") == 2 then
		vim.cmd("CMakeBuild")
	elseif vim.fn.executable("cmake") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("cmake --build build")
	else
		vim.notify("cmake not found", vim.log.levels.WARN, { title = "C++" })
	end
end, { desc = icons.dev.Build .. " Build" })

--- CMake: run the selected launch target.
---
--- Requires `cmake-tools.nvim` to be loaded.
keys.lang_map("cpp", "n", "<leader>lmr", function()
	if vim.fn.exists(":CMakeRun") == 2 then
		vim.cmd("CMakeRun")
	else
		vim.notify("cmake-tools.nvim not loaded", vim.log.levels.WARN, { title = "C++" })
	end
end, { desc = icons.ui.Play .. " Run" })

--- CMake: select the launch target from available executables.
keys.lang_map("cpp", "n", "<leader>lms", function()
	if vim.fn.exists(":CMakeSelectLaunchTarget") == 2 then
		vim.cmd("CMakeSelectLaunchTarget")
	else
		vim.notify("cmake-tools.nvim not loaded", vim.log.levels.WARN, { title = "C++" })
	end
end, { desc = icons.ui.Target .. " Select target" })

--- CMake: clean the build directory.
keys.lang_map("cpp", "n", "<leader>lmk", function()
	if vim.fn.exists(":CMakeClean") == 2 then
		vim.cmd("CMakeClean")
	elseif vim.fn.executable("cmake") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("cmake --build build --target clean")
	else
		vim.notify("cmake not found", vim.log.levels.WARN, { title = "C++" })
	end
end, { desc = icons.ui.Close .. " Clean" })

--- CMake: select the build type.
---
--- Build types:
--- - `Debug`          — no optimization, full debug symbols
--- - `Release`        — full optimization, no debug symbols
--- - `RelWithDebInfo` — optimization + debug symbols
--- - `MinSizeRel`     — optimize for binary size
keys.lang_map("cpp", "n", "<leader>lmt", function()
	if vim.fn.exists(":CMakeSelectBuildType") == 2 then
		vim.cmd("CMakeSelectBuildType")
	else
		---@type string[]
		local build_types = { "Debug", "Release", "RelWithDebInfo", "MinSizeRel" }
		vim.ui.select(build_types, { prompt = "Build type:" }, function(choice)
			if choice then
				vim.cmd.split()
				vim.cmd.terminal(
					"cmake -B build -DCMAKE_BUILD_TYPE=" .. choice .. " -DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
				)
			end
		end)
	end
end, { desc = icons.ui.List .. " Build type" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers C++-specific alignment presets when mini.align is available.
-- Loaded once per session (guarded by is_language_loaded).
--
-- Preset: cpp_struct — align struct and class member declarations
-- by whitespace. Useful for aligning member types and names:
--
-- Example:
--   int         count;
--   std::string name;
--   double      value;
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("cpp") then
		---@type string Alignment preset icon from icons.app
		local align_icon = icons.app.Cpp

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			cpp_struct = {
				description = "Align C++ struct / class members",
				icon = align_icon,
				split_pattern = "%s+",
				category = "systems",
				lang = "cpp",
				filetypes = { "cpp" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("cpp", "cpp_struct")
		align_registry.mark_language_loaded("cpp")

		-- ── Alignment keymap ─────────────────────────────────────────
		keys.lang_map("cpp", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("cpp_struct"), {
			desc = align_icon .. "  Align C++ struct",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the C++-specific
-- parts (servers, formatters, linters, parsers, adapters).
--
-- Many plugins are shared with langs/c.lua (clangd, clangd_extensions,
-- cmake-tools, codelldb). lazy.nvim's opts merge handles deduplication.
--
-- Loading strategy:
-- ┌─────────────────────┬─────────────────────────────────────────────┐
-- │ Plugin              │ How it lazy-loads for C++                   │
-- ├─────────────────────┼─────────────────────────────────────────────┤
-- │ nvim-lspconfig      │ opts merge (clangd added to servers)        │
-- │ clangd_extensions   │ ft = { "c", "cpp", "objc", "objcpp" }      │
-- │ mason.nvim          │ opts merge (tools added to ensure_installed)│
-- │ conform.nvim        │ opts merge (formatters_by_ft.cpp)           │
-- │ nvim-lint           │ opts fn (conditional cppcheck registration) │
-- │ nvim-treesitter     │ opts merge (parsers added to ensure_install)│
-- │ cmake-tools.nvim    │ ft + cond (only if CMakeLists.txt exists)   │
-- │ mason-nvim-dap      │ opts merge (codelldb to ensure_installed)   │
-- └─────────────────────┴─────────────────────────────────────────────┘
--
-- NOTE: clangd server configuration is shared with langs/c.lua.
-- lazy.nvim deep-merges opts tables, so the same server config
-- works for both C and C++ without conflict.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for C++
return {
	-- ── LSP SERVER (clangd — shared with C) ────────────────────────────
	-- clangd provides unified C/C++ language support. The same server
	-- instance handles both C and C++ files based on file extension
	-- and compile_commands.json settings.
	--
	-- See langs/c.lua for detailed flag documentation.
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
			-- ── Buffer-local options for C++ files ────────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "cpp" },
				callback = function()
					local opt = vim.opt_local

					-- ── Layout ────────────────────────────────────────
					opt.wrap = false
					opt.colorcolumn = "100"
					opt.textwidth = 100

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
				desc = "NvimEnterprise: C++ buffer options",
			})
		end,
	},

	-- ── CLANGD EXTENSIONS (shared with C) ──────────────────────────────
	-- Provides AST visualization, symbol info, type hierarchy, and
	-- memory usage reports. See langs/c.lua for icon configuration.
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
	-- Ensures clang-format and codelldb are installed and managed
	-- by Mason. Shared with langs/c.lua — lazy.nvim deduplicates.
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
	-- clang-format with LLVM base style for C++ files.
	-- Column limit is 100 (vs 80 for C) to accommodate longer C++
	-- identifiers (namespaces, templates, STL types).
	--
	-- If a `.clang-format` file exists in the project root, it takes
	-- precedence over the inline style configuration.
	-- ────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				cpp = { "clang-format" },
			},
			formatters = {
				["clang-format"] = {
					prepend_args = {
						"--style={BasedOnStyle: llvm, IndentWidth: 4, ColumnLimit: 100}",
					},
				},
			},
		},
	},

	-- ── LINTER (conditional) ───────────────────────────────────────────
	-- cppcheck with C++20 mode and extended static analysis.
	--
	-- Only registers if cppcheck is available on the system PATH.
	-- Uses `--language=c++` and `--std=c++20` to enable C++-specific
	-- checks (unlike langs/c.lua which uses default C mode).
	--
	-- Enabled checks: warning, style, performance, portability.
	-- Suppressed: missingIncludeSystem (noisy with system headers).
	-- ────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = function(_, opts)
			if vim.fn.executable("cppcheck") == 1 then
				opts.linters_by_ft = opts.linters_by_ft or {}
				opts.linters_by_ft.cpp = { "cppcheck" }

				opts.linters = opts.linters or {}
				opts.linters.cppcheck = {
					args = {
						"--language=c++",
						"--std=c++20",
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
	-- cpp:     syntax highlighting, folding, text objects, indentation
	-- doxygen: doc comment highlighting (/** ... */ and /// style)
	-- make:    Makefile syntax highlighting
	-- cmake:   CMakeLists.txt syntax highlighting
	-- ────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"cpp",
				"doxygen",
				"make",
				"cmake",
			},
		},
	},

	-- ── CMAKE TOOLS (shared with C) ────────────────────────────────────
	-- cmake-tools.nvim: integrated CMake project management.
	-- See langs/c.lua for detailed configuration documentation.
	-- lazy.nvim deduplicates shared specs.
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
	-- Ensures codelldb is installed via Mason. Shared with langs/c.lua.
	-- After loading, all core DAP keymaps work in C++ files.
	-- ────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "codelldb" },
		},
	},
}
