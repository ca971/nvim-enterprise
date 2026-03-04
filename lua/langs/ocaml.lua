---@file lua/langs/ocaml.lua
---@description OCaml — LSP (ocamllsp), formatter, treesitter & buffer-local keymaps
---@module "langs.ocaml"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.haskell            Haskell language support (functional programming peer)
---@see langs.rust               Rust language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/ocaml.lua — OCaml language support                                ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("ocaml") → {} if off        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "ocaml"):                    │    ║
--- ║  │  ├─ LSP          ocamllsp (via opam, conditional on opam avail)  │    ║
--- ║  │  │               Completions, diagnostics, code lens, refactor   │    ║
--- ║  │  ├─ Formatter    ocamlformat (conform.nvim, conditional)         │    ║
--- ║  │  ├─ Treesitter   ocaml parser                                    │    ║
--- ║  │  └─ Build tool   dune (build, test, exec, clean, fmt, promote)   │    ║
--- ║  │                  opam (package manager)                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run (dune exec / ocaml fallback)                │    ║
--- ║  │  │            R  Run with arguments                              │    ║
--- ║  │  ├─ BUILD     b  Dune build            l  Dune clean             │    ║
--- ║  │  ├─ TEST      t  Dune test                                       │    ║
--- ║  │  ├─ REPL      c  OCaml REPL (utop preferred)                     │    ║
--- ║  │  ├─ TOOLS     s  Switch .ml ↔ .mli                               │    ║
--- ║  │  │            p  Opam commands picker                            │    ║
--- ║  │  │            d  Dune commands picker                            │    ║
--- ║  │  └─ DOCS      i  Project info           h  Documentation picker  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Opam commands picker:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Install…       → opam install <pkg>                     │    │    ║
--- ║  │  │  Remove…        → opam remove <pkg>                      │    │    ║
--- ║  │  │  Update         → opam update                            │    │    ║
--- ║  │  │  Upgrade        → opam upgrade                           │    │    ║
--- ║  │  │  List installed → opam list                              │    │    ║
--- ║  │  │  Switch list    → opam switch list                       │    │    ║
--- ║  │  │  Show env       → opam env                               │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Dune commands picker:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  build · test · clean · exec . · fmt · promote           │    │    ║
--- ║  │  │  init project…  (prompts for name)                       │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType ocaml):                             ║
--- ║  • colorcolumn=80, textwidth=80    (OCaml community standard)            ║
--- ║  • tabstop=2, shiftwidth=2         (OCaml standard indentation)          ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="(* %s *)"        (OCaml block comment)                 ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Conditional tooling (opam-dependent):                                   ║
--- ║  • ocamllsp:    only configured if `opam` is in $PATH                    ║
--- ║  • ocamlformat: only configured if `ocamlformat` is in $PATH             ║
--- ║  • Mason tools: only added to ensure_installed if `opam` is available    ║
--- ║  This allows OCaml support without requiring the full opam ecosystem     ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .ml, .mli            → ocaml (source + interface)                     ║
--- ║  • .mll, .mly           → ocaml (ocamllex + ocamlyacc)                   ║
--- ║  • dune, dune-project   → dune                                           ║
--- ║  • dune-workspace       → dune                                           ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if OCaml support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("ocaml") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string OCaml Nerd Font icon (trailing whitespace stripped)
local ocaml_icon = icons.lang.ocaml:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for OCaml buffers.
-- The group is buffer-local and only visible when filetype == "ocaml".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("ocaml", "OCaml", ocaml_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Dune availability check, notification, command execution, and
-- generic picker utility. All functions are module-local and not
-- exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the `dune` build tool is available in `$PATH`.
---
--- Dune is OCaml's standard build system. Most commands in this
--- module require it, with fallback to raw `ocaml` for simple scripts.
---
--- ```lua
--- if not has_dune() then return end
--- ```
---
---@return boolean available `true` if `dune` is executable, `false` otherwise
---@private
local function has_dune()
	return vim.fn.executable("dune") == 1
end

--- Notify the user that `dune` is not available.
---
--- Centralizes the warning notification to avoid repetition across
--- all keymaps that require the `dune` build tool.
---
---@return nil
---@private
local function notify_no_dune()
	vim.notify("dune not found", vim.log.levels.WARN, { title = "OCaml" })
end

--- Run a dune command in a terminal split.
---
--- Checks that `dune` is available, optionally saves the buffer,
--- then opens a horizontal split with a terminal running the command.
---
--- ```lua
--- run_dune("build", true)    --> save, then "dune build"
--- run_dune("clean")          --> "dune clean" (no save)
--- run_dune("exec . -- -v")   --> "dune exec . -- -v"
--- ```
---
---@param subcommand string Dune subcommand and arguments (e.g. `"build"`, `"exec ."`)
---@param save? boolean If `true`, save the current buffer before running (default: `false`)
---@return boolean launched `true` if the command was launched, `false` if dune is missing
---@private
local function run_dune(subcommand, save)
	if not has_dune() then
		notify_no_dune()
		return false
	end
	if save then vim.cmd("silent! write") end
	vim.cmd.split()
	vim.cmd.terminal("dune " .. subcommand)
	return true
end

--- Run a generic action picker with optional prompt support.
---
--- Presents a list of actions via `vim.ui.select()`. Each action
--- can have a fixed command or a prompt for user input (package
--- name, project name, etc.).
---
--- ```lua
--- run_picker("Opam:", { { name = "Update", cmd = "opam update" } })
--- ```
---
---@param prompt string Picker title (e.g. `"Opam:"`)
---@param actions { name: string, cmd: string, prompt: boolean|nil }[] Action list
---@return nil
---@private
local function run_picker(prompt, actions)
	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = ocaml_icon .. " " .. prompt },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]

			if action.prompt then
				local input_prompt = action.name:match("project") and "Name: " or "Package: "
				vim.ui.input({ prompt = input_prompt }, function(name)
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
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — BUILD / RUN
--
-- Project execution and compilation via dune.
-- Falls back to raw `ocaml` interpreter for standalone scripts
-- when dune is not available.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current OCaml project or file.
---
--- Strategy:
--- 1. Dune available → `dune exec .` (runs the default executable)
--- 2. No dune, `ocaml` available → interpret the current file directly
--- 3. Neither → error notification
keys.lang_map("ocaml", "n", "<leader>lr", function()
	vim.cmd("silent! write")

	if has_dune() then
		vim.cmd.split()
		vim.cmd.terminal("dune exec .")
		return
	end

	-- ── Fallback: raw ocaml interpreter ──────────────────────────
	if vim.fn.executable("ocaml") ~= 1 then
		vim.notify("ocaml not found", vim.log.levels.ERROR, { title = "OCaml" })
		return
	end
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	vim.cmd.split()
	vim.cmd.terminal("ocaml " .. file)
end, { desc = icons.ui.Play .. " Run" })

--- Run a dune executable with user-provided arguments.
---
--- Prompts for the executable name (default: `.` for the main
--- executable) and arguments via `vim.ui.input()`. The arguments
--- are passed after `--` to separate dune options from program args.
---
--- Aborts silently if the user cancels either prompt.
keys.lang_map("ocaml", "n", "<leader>lR", function()
	if not has_dune() then
		notify_no_dune()
		return
	end
	vim.cmd("silent! write")

	vim.ui.input({ prompt = "Executable: ", default = "." }, function(exe)
		if not exe or exe == "" then return end
		vim.ui.input({ prompt = "Arguments: " }, function(args)
			if args == nil then return end
			vim.cmd.split()
			vim.cmd.terminal("dune exec " .. exe .. " -- " .. args)
		end)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Build the project via `dune build`.
---
--- Saves the buffer before building. Notifies if dune is not found.
keys.lang_map("ocaml", "n", "<leader>lb", function()
	run_dune("build", true)
end, { desc = icons.dev.Build .. " Dune build" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST / CLEAN
--
-- Test execution and build artifact cleanup via dune.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the test suite via `dune test`.
---
--- Executes all test stanzas defined in `dune` files throughout
--- the project. Saves the buffer before testing.
keys.lang_map("ocaml", "n", "<leader>lt", function()
	run_dune("test", true)
end, { desc = icons.dev.Test .. " Dune test" })

--- Clean build artifacts via `dune clean`.
---
--- Removes the `_build/` directory and all compiled artifacts.
--- Does not save the buffer (no need — cleaning doesn't depend on source).
keys.lang_map("ocaml", "n", "<leader>ll", function()
	run_dune("clean")
end, { desc = ocaml_icon .. " Dune clean" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL / NAVIGATION
--
-- Interactive REPL (prefers utop over ocaml) and .ml ↔ .mli
-- file switching for interface/implementation pairs.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open an OCaml REPL in a terminal split.
---
--- Prefers `utop` (enhanced REPL with auto-completion, type display,
--- and syntax highlighting) over the bare `ocaml` toplevel.
---
--- Notifies if neither REPL is available.
keys.lang_map("ocaml", "n", "<leader>lc", function()
	---@type string
	local repl = vim.fn.executable("utop") == 1 and "utop" or "ocaml"
	if vim.fn.executable(repl) ~= 1 then
		vim.notify("No OCaml REPL found (utop, ocaml)", vim.log.levels.ERROR, { title = "OCaml" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal(repl)
end, { desc = icons.ui.Terminal .. " REPL (utop)" })

--- Switch between `.ml` (implementation) and `.mli` (interface) files.
---
--- OCaml convention separates interfaces (`.mli`) from implementations
--- (`.ml`). This keymap toggles between the two for the current module.
---
--- Notifies if the target file does not exist or the current file
--- is not an `.ml` or `.mli` file.
keys.lang_map("ocaml", "n", "<leader>ls", function()
	local ext = vim.fn.expand("%:e")

	---@type string|nil
	local alt
	if ext == "ml" then
		alt = "mli"
	elseif ext == "mli" then
		alt = "ml"
	else
		vim.notify("Not an .ml or .mli file", vim.log.levels.INFO, { title = "OCaml" })
		return
	end

	local target = vim.fn.expand("%:p:r") .. "." .. alt
	if vim.fn.filereadable(target) == 1 then
		vim.cmd.edit(target)
	else
		vim.notify("File not found: " .. target, vim.log.levels.INFO, { title = "OCaml" })
	end
end, { desc = ocaml_icon .. " Switch .ml/.mli" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — OPAM / DUNE COMMANDS
--
-- Comprehensive pickers for opam (package management) and dune
-- (build system) operations, presented via vim.ui.select().
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the opam commands picker.
---
--- Presents common opam operations via `vim.ui.select()`:
--- - Install/Remove: prompt for package name
--- - Update/Upgrade: run immediately
--- - List/Switch/Env: informational commands
---
--- Requires `opam` to be installed. Notifies if not found.
keys.lang_map("ocaml", "n", "<leader>lp", function()
	if vim.fn.executable("opam") ~= 1 then
		vim.notify("opam not found", vim.log.levels.WARN, { title = "OCaml" })
		return
	end

	---@type { name: string, cmd: string, prompt: boolean|nil }[]
	local actions = {
		{ name = "Install…", cmd = "opam install", prompt = true },
		{ name = "Remove…", cmd = "opam remove", prompt = true },
		{ name = "Update", cmd = "opam update" },
		{ name = "Upgrade", cmd = "opam upgrade" },
		{ name = "List installed", cmd = "opam list" },
		{ name = "Switch list", cmd = "opam switch list" },
		{ name = "Show env", cmd = "opam env" },
	}

	run_picker("Opam:", actions)
end, { desc = icons.ui.Package .. " Opam" })

--- Open the dune commands picker.
---
--- Presents common dune operations via `vim.ui.select()`:
--- - build, test, clean, exec, fmt, promote: run immediately
--- - init project…: prompt for project name
---
--- Requires `dune` to be installed. Notifies if not found.
keys.lang_map("ocaml", "n", "<leader>ld", function()
	if not has_dune() then
		notify_no_dune()
		return
	end

	---@type { name: string, cmd: string, prompt: boolean|nil }[]
	local actions = {
		{ name = "build", cmd = "dune build" },
		{ name = "test", cmd = "dune test" },
		{ name = "clean", cmd = "dune clean" },
		{ name = "exec .", cmd = "dune exec ." },
		{ name = "fmt", cmd = "dune fmt" },
		{ name = "promote", cmd = "dune promote" },
		{ name = "init project…", cmd = "dune init project", prompt = true },
	}

	run_picker("Dune:", actions)
end, { desc = ocaml_icon .. " Dune commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- OCaml toolchain info display and curated documentation links
-- for the OCaml ecosystem.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show OCaml toolchain and environment information.
---
--- Displays a summary notification containing:
--- - OCaml version (from `ocaml --version`)
--- - Tool availability checklist (ocaml, dune, opam, utop, ocamlformat, ocamllsp)
--- - Current working directory
keys.lang_map("ocaml", "n", "<leader>li", function()
	---@type string[]
	local info = { ocaml_icon .. " OCaml Info:", "" }

	-- ── Version ──────────────────────────────────────────────────
	if vim.fn.executable("ocaml") == 1 then
		local version = vim.fn.system("ocaml --version 2>/dev/null"):gsub("%s+$", "")
		info[#info + 1] = "  Version: " .. version
	end

	-- ── Tool availability ────────────────────────────────────────
	---@type string[]
	local tools = { "ocaml", "dune", "opam", "utop", "ocamlformat", "ocamllsp" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	info[#info + 1] = "  CWD:     " .. vim.fn.getcwd()

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "OCaml" })
end, { desc = icons.diagnostics.Info .. " Project info" })

--- Open OCaml documentation in the browser.
---
--- Presents a list of curated OCaml ecosystem resources via
--- `vim.ui.select()`:
--- 1. OCaml Manual — official language reference
--- 2. OCaml API — standard library documentation
--- 3. Real World OCaml — practical programming guide
--- 4. Dune Docs — build system documentation
--- 5. opam packages — package registry
--- 6. OCaml Discuss — community forum
---
--- Opens the selected URL in the system browser via `vim.ui.open()`.
keys.lang_map("ocaml", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "OCaml Manual", url = "https://v2.ocaml.org/manual/" },
		{ name = "OCaml API", url = "https://v2.ocaml.org/api/" },
		{ name = "Real World OCaml", url = "https://dev.realworldocaml.org/" },
		{ name = "Dune Docs", url = "https://dune.readthedocs.io/" },
		{ name = "opam packages", url = "https://opam.ocaml.org/packages/" },
		{ name = "OCaml Discuss", url = "https://discuss.ocaml.org/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = ocaml_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers OCaml-specific alignment presets for mini.align:
-- • ocaml_record — align record fields on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("ocaml") then
		---@type string Alignment preset icon from icons.lang
		local ocaml_align_icon = icons.lang.ocaml

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			ocaml_record = {
				description = "Align OCaml record fields on '='",
				icon = ocaml_align_icon,
				split_pattern = "=",
				category = "functional",
				lang = "ocaml",
				filetypes = { "ocaml" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("ocaml", "ocaml_record")
		align_registry.mark_language_loaded("ocaml")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("ocaml", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("ocaml_record"), {
			desc = ocaml_align_icon .. "  Align OCaml record",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the OCaml-specific
-- parts (servers, formatters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for OCaml                  │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts fn (ocamllsp added if opam available)  │
-- │ mason.nvim         │ opts fn (tools added if opam available)     │
-- │ conform.nvim       │ opts fn (ocamlformat if binary available)   │
-- │ nvim-lint          │ NOT used (ocamllsp provides all diagnostics)│
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: OCaml tooling is conditionally configured based on opam
-- availability. The `opts` functions (not tables) check for opam
-- at config time, allowing graceful degradation when the OCaml
-- toolchain is partially installed.
--
-- Conditional logic:
-- • opam available → ocamllsp + ocamlformat added to Mason + LSP
-- • opam absent   → only treesitter parser, no LSP or formatter
-- • ocamlformat available → conform formatter configured
-- • ocamlformat absent   → no formatter (LSP formatting only)
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for OCaml
return {
	-- ── LSP SERVER (conditional on opam) ───────────────────────────────────
	-- ocamllsp: the OCaml Language Server Protocol implementation.
	-- Provides completions, diagnostics, go-to-definition, hover,
	-- code lens, and type annotations.
	--
	-- Only configured when `opam` is available — ocamllsp is typically
	-- installed via `opam install ocaml-lsp-server`.
	--
	-- Uses `opts` as a function (not table) to conditionally add the
	-- server at config time.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = function(_, opts)
			if vim.fn.executable("opam") == 1 then
				opts.servers = opts.servers or {}
				opts.servers.ocamllsp = {
					settings = {
						codelens = { enable = true },
					},
				}
			end
		end,
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					ml = "ocaml",
					mli = "ocaml",
					mll = "ocaml",
					mly = "ocaml",
				},
				filename = {
					["dune"] = "dune",
					["dune-project"] = "dune",
					["dune-workspace"] = "dune",
				},
			})

			-- ── Buffer-local options for OCaml files ─────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "ocaml" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "80"
					opt.textwidth = 80
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true
					opt.number = true
					opt.relativenumber = true
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
					opt.commentstring = "(* %s *)"
				end,
			})
		end,
	},

	-- ── MASON TOOLS (conditional on opam) ──────────────────────────────────
	-- Only installs OCaml tools via Mason when opam is available,
	-- since ocamllsp and ocamlformat depend on the opam ecosystem.
	--
	-- Tools:
	--   • ocaml-lsp    — OCaml Language Server (ocamllsp)
	--   • ocamlformat  — opinionated OCaml code formatter
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}
			if vim.fn.executable("opam") == 1 then
				vim.list_extend(opts.ensure_installed, {
					"ocaml-lsp",
					"ocamlformat",
				})
			end
		end,
	},

	-- ── FORMATTER (conditional on ocamlformat) ─────────────────────────────
	-- ocamlformat: opinionated OCaml code formatter.
	-- Configured via `.ocamlformat` file in the project root.
	-- Only added to conform when the binary is available.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = function(_, opts)
			if vim.fn.executable("ocamlformat") == 1 then
				opts.formatters_by_ft = opts.formatters_by_ft or {}
				opts.formatters_by_ft.ocaml = { "ocamlformat" }
			end
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- ocaml: syntax highlighting, folding, text objects, indentation.
	-- OCaml's complex syntax (pattern matching, functors, module types,
	-- polymorphic variants, GADTs) benefits from treesitter parsing.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"ocaml",
			},
		},
	},
}
