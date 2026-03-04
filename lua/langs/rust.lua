---@file lua/langs/rust.lua
---@description Rust — LSP (rustaceanvim), formatter, linter, treesitter, DAP & buffer-local keymaps
---@module "langs.rust"
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
--- ║  langs/rust.lua — Rust language support                                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("rust") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "rust"):                     │    ║
--- ║  │  ├─ LSP          rust-analyzer (via rustaceanvim, NOT lspconfig) │    ║
--- ║  │  ├─ Formatter    rustfmt (via conform.nvim / cargo fmt)          │    ║
--- ║  │  ├─ Linter       clippy (via rust-analyzer checkOnSave)          │    ║
--- ║  │  ├─ Treesitter   rust · toml parsers                             │    ║
--- ║  │  ├─ DAP          codelldb (via Mason + rustaceanvim debuggables) │    ║
--- ║  │  └─ Extras       crates.nvim (Cargo.toml intelligence)           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  cargo run             R  cargo run --release    │    ║
--- ║  │  ├─ BUILD     b  cargo build           B  cargo build --release  │    ║
--- ║  │  │            c  cargo check                                     │    ║
--- ║  │  ├─ TEST      t  cargo test            T  Test under cursor      │    ║
--- ║  │  │            p  cargo bench                                     │    ║
--- ║  │  ├─ DEBUG     d  Debug (rustaceanvim debuggables / DAP)          │    ║
--- ║  │  ├─ TOOLS     x  Clippy fix            e  Expand macro           │    ║
--- ║  │  │            a  cargo add (dependency) o  Open Cargo.toml       │    ║
--- ║  │  │            v  Explain error          j  Join lines            │    ║
--- ║  │  │            s  Switch test ↔ source                            │    ║
--- ║  │  └─ DOCS      h  Docs.rs               i  Crate info (crates.io) │    ║
--- ║  │                                                                  │    ║
--- ║  │  DAP integration flow:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. mason-nvim-dap ensures "codelldb" adapter installed  │    │    ║
--- ║  │  │  2. rustaceanvim configures dap.adapters for codelldb    │    │    ║
--- ║  │  │  3. <leader>ld → :RustLsp debuggables (if available)     │    │    ║
--- ║  │  │     OR dap.continue() as fallback                        │    │    ║
--- ║  │  │  4. All core DAP keymaps become active:                  │    │    ║
--- ║  │  │     <leader>dc · <leader>db · F5 · F9 · etc.             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  rustaceanvim features:                                          │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  • Replaces nvim-lspconfig for Rust (manages its own     │    │    ║
--- ║  │  │    rust-analyzer lifecycle)                              │    │    ║
--- ║  │  │  • :RustLsp expandMacro — inline macro expansion         │    │    ║
--- ║  │  │  • :RustLsp explainError — detailed error explanations   │    │    ║
--- ║  │  │  • :RustLsp joinLines — smart line joining               │    │    ║
--- ║  │  │  • :RustLsp debuggables — DAP launch config picker       │    │    ║
--- ║  │  │  • Inlay hints (lifetime elision, type hints)            │    │    ║
--- ║  │  │  • checkOnSave with clippy                               │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied via rustaceanvim ft = "rust"):                  ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║  • clippy checkOnSave             (diagnostics on every save)            ║
--- ║  • All features enabled           (cargo.allFeatures = true)             ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .rs → rust (handled by Neovim built-in)                               ║
--- ║  • Cargo.toml → toml (crates.nvim intelligence)                          ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Rust support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("rust") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Rust Nerd Font icon (trailing whitespace stripped)
local rs_icon = icons.lang.rust:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Rust buffers.
-- The group is buffer-local and only visible when filetype == "rust".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("rust", "Rust", rs_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN / BUILD
--
-- Cargo execution and build commands.
-- All keymaps save the buffer before execution.
-- Supports both debug and release profiles.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the project with `cargo run` (debug profile).
---
--- Saves the buffer, then executes in a terminal split.
keys.lang_map("rust", "n", "<leader>lr", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("cargo run")
end, { desc = icons.ui.Play .. " Cargo run" })

--- Run the project with `cargo run --release` (optimized).
---
--- Saves the buffer, then compiles with optimizations and runs
--- in a terminal split.
keys.lang_map("rust", "n", "<leader>lR", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("cargo run --release")
end, { desc = icons.ui.Play .. " Cargo run (release)" })

--- Build the project with `cargo build` (debug profile).
---
--- Saves the buffer, then compiles in a terminal split.
keys.lang_map("rust", "n", "<leader>lb", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("cargo build")
end, { desc = icons.dev.Build .. " Cargo build" })

--- Build the project with `cargo build --release` (optimized).
---
--- Saves the buffer, then compiles with release optimizations
--- in a terminal split.
keys.lang_map("rust", "n", "<leader>lB", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("cargo build --release")
end, { desc = icons.dev.Build .. " Cargo build (release)" })

--- Type-check the project with `cargo check`.
---
--- Faster than a full build — only performs type checking and
--- borrow checking without code generation.
keys.lang_map("rust", "n", "<leader>lc", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("cargo check")
end, { desc = rs_icon .. " Cargo check" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via `cargo test`. Supports full-suite, single-function,
-- and benchmark testing. Uses treesitter to detect the function name
-- under cursor for targeted test runs.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run all tests with `cargo test`.
---
--- Uses `--nocapture` to display `println!` output during tests.
keys.lang_map("rust", "n", "<leader>lt", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("cargo test -- --nocapture")
end, { desc = icons.dev.Test .. " Cargo test" })

--- Run the test function under the cursor.
---
--- Uses treesitter to walk up the AST from the cursor position until
--- a `function_item` node is found, then extracts its name for the
--- cargo test filter. Falls back with a notification if no function
--- is found.
keys.lang_map("rust", "n", "<leader>lT", function()
	vim.cmd("silent! write")

	---@type TSNode|nil
	local node = vim.treesitter.get_node()
	---@type string|nil
	local func_name = nil

	while node do
		if node:type() == "function_item" then
			local name_node = node:field("name")[1]
			if name_node then func_name = vim.treesitter.get_node_text(name_node, 0) end
			break
		end
		node = node:parent()
	end

	if func_name then
		vim.cmd.split()
		vim.cmd.terminal("cargo test " .. func_name .. " -- --nocapture")
	else
		vim.notify("No test function found under cursor", vim.log.levels.INFO, { title = "Rust" })
	end
end, { desc = icons.dev.Test .. " Test under cursor" })

--- Run benchmarks with `cargo bench`.
---
--- Executes all benchmark tests defined with `#[bench]` or
--- via criterion / divan crates.
keys.lang_map("rust", "n", "<leader>lp", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("cargo bench")
end, { desc = icons.dev.Benchmark .. " Benchmark" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via rustaceanvim and codelldb.
--
-- <leader>ld prefers rustaceanvim's `:RustLsp debuggables` which
-- presents a picker of all debuggable targets (binaries, tests,
-- examples). Falls back to raw dap.continue() if rustaceanvim
-- is not loaded.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start a debug session for the current Rust project.
---
--- Resolution strategy:
--- 1. `:RustLsp debuggables` — rustaceanvim picker (preferred)
--- 2. `dap.continue()` — raw DAP fallback
---
--- Saves the buffer before launching.
keys.lang_map("rust", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	if vim.fn.exists(":RustLsp") == 2 then
		vim.cmd.RustLsp("debuggables")
		return
	end
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Rust" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (DAP)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Rust-specific development tools: clippy auto-fix, macro expansion,
-- dependency management, error explanations, and file navigation.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run clippy with auto-fix on the project.
---
--- Executes `cargo clippy --fix --allow-dirty --allow-staged` which
--- automatically applies safe lint fixes. The `--allow-dirty` and
--- `--allow-staged` flags permit fixing even with uncommitted changes.
keys.lang_map("rust", "n", "<leader>lx", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("cargo clippy --fix --allow-dirty --allow-staged")
end, { desc = rs_icon .. " Clippy fix" })

--- Expand the macro under the cursor.
---
--- Delegates to `:RustLsp expandMacro` which shows the fully expanded
--- macro output in a scratch buffer. Requires rustaceanvim to be loaded.
keys.lang_map("rust", "n", "<leader>le", function()
	if vim.fn.exists(":RustLsp") == 2 then
		vim.cmd.RustLsp("expandMacro")
	else
		vim.notify("rustaceanvim not loaded", vim.log.levels.WARN, { title = "Rust" })
	end
end, { desc = rs_icon .. " Expand macro" })

--- Add a dependency with `cargo add`.
---
--- Prompts for the crate name, then runs `cargo add <crate>` in a
--- terminal split. The crate is added to `[dependencies]` in Cargo.toml.
keys.lang_map("rust", "n", "<leader>la", function()
	vim.ui.input({ prompt = "Crate name: " }, function(crate)
		if not crate or crate == "" then return end
		vim.cmd.split()
		vim.cmd.terminal("cargo add " .. crate)
	end)
end, { desc = icons.ui.Plus .. " Add dependency" })

--- Open the nearest `Cargo.toml` file.
---
--- Searches upward from the current file using Neovim's `findfile()`.
--- Notifies the user if no Cargo.toml is found in the directory hierarchy.
keys.lang_map("rust", "n", "<leader>lo", function()
	local cargo = vim.fn.findfile("Cargo.toml", ".;")
	if cargo ~= "" then
		vim.cmd.edit(cargo)
	else
		vim.notify("Cargo.toml not found", vim.log.levels.WARN, { title = "Rust" })
	end
end, { desc = rs_icon .. " Open Cargo.toml" })

--- Explain the error under the cursor with detailed context.
---
--- Delegates to `:RustLsp explainError` which shows the full error
--- explanation (similar to `rustc --explain E0XXX`). Requires
--- rustaceanvim to be loaded.
keys.lang_map("rust", "n", "<leader>lv", function()
	if vim.fn.exists(":RustLsp") == 2 then
		vim.cmd.RustLsp("explainError")
	else
		vim.notify("rustaceanvim not loaded", vim.log.levels.WARN, { title = "Rust" })
	end
end, { desc = rs_icon .. " Explain error" })

--- Join lines using rust-analyzer's smart join.
---
--- Delegates to `:RustLsp joinLines` which intelligently joins lines
--- respecting Rust syntax (e.g., unwrapping match arms, combining
--- use statements).
keys.lang_map("rust", "n", "<leader>lj", function()
	if vim.fn.exists(":RustLsp") == 2 then vim.cmd.RustLsp("joinLines") end
end, { desc = rs_icon .. " Join lines" })

--- Switch between test and source files.
---
--- Heuristic:
--- • In `/tests/` → navigate to `/src/` (strip `_test` suffix)
--- • In `/src/`   → navigate to `/tests/` (add `_test` suffix)
---
--- Notifies the user if the target file does not exist.
keys.lang_map("rust", "n", "<leader>ls", function()
	local file = vim.fn.expand("%:p")

	---@type string|nil
	local target
	if file:match("/tests/") then
		target = file:gsub("/tests/", "/src/"):gsub("_test%.rs$", ".rs")
	elseif file:match("/src/") then
		target = file:gsub("/src/", "/tests/"):gsub("%.rs$", "_test.rs")
	end

	if target and vim.fn.filereadable(target) == 1 then
		vim.cmd.edit(target)
	else
		vim.notify("No matching file", vim.log.levels.INFO, { title = "Rust" })
	end
end, { desc = rs_icon .. " Switch test ↔ source" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to Rust documentation and crate search
-- via the system browser. Contextual search based on word under cursor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open docs.rs documentation in the system browser.
---
--- If the cursor is on a word, searches docs.rs for that term.
--- Otherwise opens the Rust standard library documentation.
keys.lang_map("rust", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word ~= "" then
		vim.ui.open("https://docs.rs/search?q=" .. word)
	else
		vim.ui.open("https://doc.rust-lang.org/std/")
	end
end, { desc = icons.ui.Note .. " Docs.rs" })

--- Open crates.io in the system browser.
---
--- If the cursor is on a word, searches crates.io for matching crates.
--- Otherwise opens the crates.io homepage.
keys.lang_map("rust", "n", "<leader>li", function()
	local word = vim.fn.expand("<cword>")
	if word ~= "" then
		vim.ui.open("https://crates.io/search?q=" .. word)
	else
		vim.ui.open("https://crates.io")
	end
end, { desc = icons.diagnostics.Info .. " Crate info" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Rust-specific alignment presets for mini.align:
-- • rust_struct — align struct field definitions on ":"
-- • rust_match  — align match arm bodies on "=>"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("rust") then
		---@type string Alignment preset icon from icons.app
		local align_icon = icons.app.Rust

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			rust_struct = {
				description = "Align Rust struct fields on ':'",
				icon = align_icon,
				split_pattern = ":",
				category = "systems",
				lang = "rust",
				filetypes = { "rust" },
			},
			rust_match = {
				description = "Align Rust match arms on '=>'",
				icon = align_icon,
				split_pattern = "=>",
				category = "systems",
				lang = "rust",
				filetypes = { "rust" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("rust", "rust_struct")
		align_registry.mark_language_loaded("rust")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("rust", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("rust_struct"), {
			desc = align_icon .. "  Align Rust struct",
		})
		keys.lang_map("rust", { "n", "x" }, "<leader>aT", align_registry.make_align_fn("rust_match"), {
			desc = align_icon .. "  Align Rust match",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Rust-specific
-- parts (rustaceanvim, formatters, parsers, adapters).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Rust                   │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ rustaceanvim                            │ ft = "rust" (manages its own rust-analyzer)  │
-- │ mason.nvim                             │ opts merge (codelldb added to ensure_installed│
-- │ conform.nvim                           │ opts merge (rustfmt for ft rust)             │
-- │ nvim-treesitter                        │ opts merge (rust/toml parsers added)         │
-- │ crates.nvim                            │ event = BufRead Cargo.toml (Cargo.toml intel)│
-- │ mason-nvim-dap                         │ opts merge (codelldb adapter)                │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Rust does NOT use nvim-lspconfig. rustaceanvim manages its own
-- rust-analyzer instance, providing tighter integration with DAP, macro
-- expansion, and other Rust-specific features. Do not add rust-analyzer
-- to any lspconfig server configuration.
-- ═══════════════════════════════════════════════════════════════════════════

---@type string Diagnostics provider: "rust-analyzer" (default) or "bacon"
local diagnostics = vim.g.nvimenterprise_rust_diagnostics or "rust-analyzer"

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Rust
return {
	-- ── RUSTACEANVIM (LSP + DAP + Tools) ───────────────────────────────────
	-- Replaces nvim-lspconfig for Rust. Manages its own rust-analyzer
	-- lifecycle and provides:
	-- • rust-analyzer LSP with full feature support
	-- • DAP integration via codelldb (debuggables picker)
	-- • :RustLsp commands (expandMacro, explainError, joinLines, etc.)
	-- • Inlay hints (lifetime elision, type inference)
	-- • checkOnSave with clippy for real-time linting
	--
	-- Configuration:
	-- • cargo.allFeatures = true      — enable all cargo features
	-- • cargo.loadOutDirsFromCheck    — resolve OUT_DIR for proc macros
	-- • cargo.buildScripts.enable     — support build.rs scripts
	-- • check.command = "clippy"      — use clippy for checkOnSave
	-- • procMacro.enable = true       — expand procedural macros
	-- • inlayHints.lifetimeElisionHints = "always" — show elided lifetimes
	-- • files.watcher = "client"      — avoid Roots Scanned hanging
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mrcjkb/rustaceanvim",
		version = "^5",
		ft = { "rust" },
		config = function()
			vim.g.rustaceanvim = {
				server = {
					default_settings = {
						["rust-analyzer"] = {
							cargo = {
								allFeatures = true,
								loadOutDirsFromCheck = true,
								buildScripts = {
									enable = true,
								},
							},
							diagnostics = {
								enable = diagnostics == "rust-analyzer",
							},
							checkOnSave = true,
							check = { command = "clippy" },
							procMacro = { enable = true },
							inlayHints = {
								lifetimeElisionHints = { enable = "always" },
							},
						},
						files = {
							exclude = {
								".direnv",
								".git",
								".jj",
								".github",
								".gitlab",
								"bin",
								"node_modules",
								"target",
								"venv",
								".venv",
							},
							watcher = "client",
						},
					},
				},
			}
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures codelldb is installed via Mason for DAP debugging.
	-- rust-analyzer itself is managed by rustaceanvim (not Mason).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"codelldb",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- rustfmt: the official Rust formatter. Enforces the style defined
	-- in rustfmt.toml or .rustfmt.toml (or defaults if none exists).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				rust = { "rustfmt" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- rust: syntax highlighting, folding, text objects for Rust source
	-- toml:  Cargo.toml, rustfmt.toml, clippy.toml configuration files
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"rust",
				"toml",
			},
		},
	},

	-- ── CRATES.NVIM (Cargo.toml intelligence) ─────────────────────────────
	-- Provides inline crate version information, completions, and
	-- code actions for Cargo.toml files:
	-- • Version hints (latest, compatible, yanked)
	-- • Completion for crate names and features
	-- • LSP hover and code actions for dependency management
	-- ───────────────────────────────────────────────────────────────────────
	{
		"Saecki/crates.nvim",
		event = { "BufRead Cargo.toml" },
		opts = {
			completion = {
				crates = {
					enabled = true,
				},
				cmp = { enabled = true },
			},
			lsp = {
				enabled = true,
				actions = true,
				completion = true,
				hover = true,
			},
		},
	},

	-- ── DAP — RUST DEBUGGER ────────────────────────────────────────────────
	-- mason-nvim-dap ensures the codelldb adapter is managed by Mason.
	-- rustaceanvim automatically configures the DAP adapter and provides
	-- the `:RustLsp debuggables` command for target selection.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "codelldb" },
		},
	},
}
