---@file lua/langs/nix.lua
---@description Nix — LSP, formatter, linter, treesitter & buffer-local keymaps
---@module "langs.nix"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.utils               Shared utility functions (`has_executable`)
---@see core.mini-align-registry Alignment preset registration system
---@see langs.python             Python language support (same architecture)
---@see langs.docker             Docker language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/nix.lua — Nix language support                                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("nix") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "nix"):                      │    ║
--- ║  │  ├─ LSP          nil_ls (Nix language server — completions,      │    ║
--- ║  │  │                       diagnostics, flake support)             │    ║
--- ║  │  ├─ Formatter    nixpkgs-fmt (via conform.nvim + nil_ls)         │    ║
--- ║  │  ├─ Linter       statix (anti-pattern linter, if available)      │    ║
--- ║  │  │               deadnix (unused binding detector, if available) │    ║
--- ║  │  ├─ Treesitter   nix parser                                      │    ║
--- ║  │  ├─ DAP          — (not applicable for Nix)                      │    ║
--- ║  │  └─ Extras       flake commands, nix search, garbage collection  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ BUILD     b  nix build             r  nix run                │    ║
--- ║  │  │            e  nix eval (expression prompt)                    │    ║
--- ║  │  ├─ REPL      c  nix repl (with flake context if available)      │    ║
--- ║  │  │            d  nix develop (dev shell)                         │    ║
--- ║  │  ├─ FLAKE     t  flake check           s  flake show             │    ║
--- ║  │  │            u  flake update                                    │    ║
--- ║  │  ├─ SEARCH    p  nix search nixpkgs                              │    ║
--- ║  │  ├─ LINT      l  statix (lint)         x  deadnix (unused)       │    ║
--- ║  │  │            g  nix-collect-garbage -d                          │    ║
--- ║  │  └─ DOCS      i  Nix info (tools)      h  Documentation          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Flake detection:                                                │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Checks for flake.nix in CWD                          │    │    ║
--- ║  │  │  2. If found: nix build/run/repl use flake commands      │    │    ║
--- ║  │  │  3. If not:   fallback to legacy nix-build / nixpkgs#    │    │    ║
--- ║  │  │  4. Flake-only commands (check/show/update/develop)      │    │    ║
--- ║  │  │     warn if no flake.nix is present                      │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType nix):                               ║
--- ║  • colorcolumn=100, textwidth=100 (Nix convention)                       ║
--- ║  • tabstop=2, shiftwidth=2        (Nix standard: 2-space indent)         ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • commentstring="# %s"          (shell-style comments)                  ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .nix → nix                                                            ║
--- ║  • flake.lock → json                                                     ║
--- ║                                                                          ║
--- ║  NOTE: nil_ls (nix LSP) is typically installed via nix itself, not       ║
--- ║  Mason. Only nixpkgs-fmt is managed by Mason as a formatter tool.        ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Nix support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("nix") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")
local has_executable = require("core.utils").has_executable

---@type string Nix Nerd Font icon (trailing whitespace stripped)
local nix_icon = icons.lang.nix:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Nix buffers.
-- The group is buffer-local and only visible when filetype == "nix".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("nix", "Nix", nix_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the nix binary is available in PATH.
---
--- Notifies the user with an error if nix is not found.
---
--- ```lua
--- if not check_nix() then return end
--- ```
---
---@return boolean available `true` if `nix` is executable, `false` otherwise
---@private
local function check_nix()
	if not has_executable("nix") then
		vim.notify("nix not found in PATH", vim.log.levels.ERROR, { title = "Nix" })
		return false
	end
	return true
end

--- Detect if the current project has a `flake.nix` file.
---
--- Checks for `flake.nix` in the current working directory.
--- This determines whether to use flake-based or legacy nix commands.
---
--- ```lua
--- if has_flake() then
---   vim.cmd.terminal("nix build")
--- else
---   vim.cmd.terminal("nix-build " .. file)
--- end
--- ```
---
---@return boolean has_flake `true` if `flake.nix` exists in CWD
---@private
local function has_flake()
	return vim.fn.filereadable(vim.fn.getcwd() .. "/flake.nix") == 1
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — BUILD / RUN
--
-- Nix build and evaluation commands. Uses flake commands when a flake.nix
-- is detected, otherwise falls back to legacy nix-build.
-- ═══════════════════════════════════════════════════════════════════════════

--- Build the current Nix project or file.
---
--- Saves the buffer, then executes:
--- • `nix build` if `flake.nix` is present
--- • `nix-build <file>` otherwise (legacy)
keys.lang_map("nix", "n", "<leader>lb", function()
	if not check_nix() then return end
	vim.cmd("silent! write")
	local cmd
	if has_flake() then
		cmd = "nix build"
	else
		local file = vim.fn.expand("%:p")
		cmd = "nix-build " .. vim.fn.shellescape(file)
	end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Build .. " Build" })

--- Run a Nix derivation or package.
---
--- Behavior depends on flake detection:
--- • Flake found → `nix run` (runs the default app output)
--- • No flake   → prompts for an attribute path, then runs
---                `nix run nixpkgs#<attr>`
keys.lang_map("nix", "n", "<leader>lr", function()
	if not check_nix() then return end
	vim.cmd("silent! write")
	if has_flake() then
		vim.cmd.split()
		vim.cmd.terminal("nix run")
	else
		vim.ui.input({ prompt = "Attribute path: " }, function(attr)
			if not attr or attr == "" then return end
			vim.cmd.split()
			vim.cmd.terminal("nix run nixpkgs#" .. vim.fn.shellescape(attr))
		end)
	end
end, { desc = icons.ui.Play .. " Run" })

--- Evaluate a Nix expression interactively.
---
--- Prompts for an arbitrary Nix expression, evaluates it with
--- `nix eval --expr`, and displays the result in a notification.
keys.lang_map("nix", "n", "<leader>le", function()
	if not check_nix() then return end
	vim.ui.input({ prompt = "Nix expression: " }, function(expr)
		if not expr or expr == "" then return end
		local result = vim.fn.system("nix eval --expr " .. vim.fn.shellescape(expr) .. " 2>&1")
		vim.notify(result, vim.log.levels.INFO, { title = "nix eval" })
	end)
end, { desc = nix_icon .. " Eval expression" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL / DEVELOP
--
-- Interactive Nix REPL and development shell.
-- The REPL loads flake context when available for project-aware evaluation.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Nix REPL in a terminal split.
---
--- Uses `nix repl .#` when a `flake.nix` is found (loads all flake
--- outputs into scope), otherwise falls back to a bare `nix repl`.
keys.lang_map("nix", "n", "<leader>lc", function()
	if not check_nix() then return end
	local cmd = "nix repl"
	if has_flake() then cmd = "nix repl .#" end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Terminal .. " Nix REPL" })

--- Enter a Nix development shell.
---
--- Runs `nix develop` which activates the `devShell` output from the
--- flake, providing all build inputs in the environment. Requires a
--- `flake.nix` with a `devShells` output.
keys.lang_map("nix", "n", "<leader>ld", function()
	if not check_nix() then return end
	if not has_flake() then
		vim.notify("No flake.nix found", vim.log.levels.WARN, { title = "Nix" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("nix develop")
end, { desc = nix_icon .. " Develop shell" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FLAKE
--
-- Nix flake lifecycle operations: check, show, and update.
-- All flake commands require a `flake.nix` in the current directory
-- and notify the user if none is found.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run `nix flake check` to validate the flake.
---
--- Evaluates all flake outputs and runs any checks defined in
--- `checks.<system>`. Requires a `flake.nix` in CWD.
keys.lang_map("nix", "n", "<leader>lt", function()
	if not check_nix() then return end
	if not has_flake() then
		vim.notify("No flake.nix found", vim.log.levels.WARN, { title = "Nix" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("nix flake check")
end, { desc = icons.ui.Check .. " Flake check" })

--- Show the flake output tree with `nix flake show`.
---
--- Displays all outputs (packages, devShells, checks, apps, etc.)
--- in a tree format. Requires a `flake.nix` in CWD.
keys.lang_map("nix", "n", "<leader>ls", function()
	if not check_nix() then return end
	if not has_flake() then
		vim.notify("No flake.nix found", vim.log.levels.WARN, { title = "Nix" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("nix flake show")
end, { desc = nix_icon .. " Flake show" })

--- Update all flake inputs with `nix flake update`.
---
--- Re-resolves and locks all inputs (nixpkgs, home-manager, etc.)
--- to their latest revisions. Updates `flake.lock`.
--- Requires a `flake.nix` in CWD.
keys.lang_map("nix", "n", "<leader>lu", function()
	if not check_nix() then return end
	if not has_flake() then
		vim.notify("No flake.nix found", vim.log.levels.WARN, { title = "Nix" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("nix flake update")
end, { desc = icons.ui.Refresh .. " Flake update" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SEARCH
--
-- Package discovery via `nix search nixpkgs`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Search nixpkgs for a package by name or description.
---
--- Prompts for a search query, then runs `nix search nixpkgs <query>`
--- in a terminal split displaying matching packages with versions.
keys.lang_map("nix", "n", "<leader>lp", function()
	if not check_nix() then return end
	vim.ui.input({ prompt = "Search nixpkgs: " }, function(query)
		if not query or query == "" then return end
		vim.cmd.split()
		vim.cmd.terminal("nix search nixpkgs " .. vim.fn.shellescape(query))
	end)
end, { desc = icons.ui.Search .. " Search nixpkgs" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — LINT / ANALYSIS
--
-- Static analysis tools for Nix code quality:
-- • statix  — anti-pattern linter (suggests idiomatic alternatives)
-- • deadnix — detects unused bindings (let-in, function args, etc.)
-- Both tools are optional and checked for availability before use.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run statix linter on the current file.
---
--- Statix detects common Nix anti-patterns and suggests idiomatic
--- alternatives. Notifies with installation instructions if statix
--- is not available.
keys.lang_map("nix", "n", "<leader>ll", function()
	if not has_executable("statix") then
		vim.notify("Install: nix profile install nixpkgs#statix", vim.log.levels.WARN, { title = "Nix" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("statix check " .. vim.fn.shellescape(file))
end, { desc = nix_icon .. " Lint (statix)" })

--- Run deadnix to find unused bindings in the current file.
---
--- Deadnix detects unused `let` bindings, function arguments, and
--- `with` imports. Notifies with installation instructions if
--- deadnix is not available.
keys.lang_map("nix", "n", "<leader>lx", function()
	if not has_executable("deadnix") then
		vim.notify("Install: nix profile install nixpkgs#deadnix", vim.log.levels.WARN, { title = "Nix" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("deadnix " .. vim.fn.shellescape(file))
end, { desc = nix_icon .. " Deadnix" })

--- Garbage collect the Nix store.
---
--- Runs `nix-collect-garbage -d` which removes all old generations
--- and unreachable store paths. This is a destructive operation that
--- frees disk space but makes rollback to previous generations impossible.
keys.lang_map("nix", "n", "<leader>lg", function()
	if not check_nix() then return end
	vim.cmd.split()
	vim.cmd.terminal("nix-collect-garbage -d")
end, { desc = nix_icon .. " Garbage collect" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Nix project information and quick access to documentation
-- via the system browser.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show Nix project and tool information in a notification.
---
--- Displays:
--- • Current working directory
--- • Flake presence (✓ / ✗)
--- • Nix version (if available)
--- • Tool availability matrix (nix, nixpkgs-fmt, alejandra,
---   statix, deadnix, nil)
keys.lang_map("nix", "n", "<leader>li", function()
	---@type string[]
	local info = { nix_icon .. " Nix Info:", "" }
	info[#info + 1] = "  CWD:     " .. vim.fn.getcwd()
	info[#info + 1] = "  Flake:   " .. (has_flake() and "✓" or "✗")

	if has_executable("nix") then
		local version = vim.fn.system("nix --version 2>/dev/null"):gsub("%s+$", "")
		info[#info + 1] = "  Version: " .. version
	end

	---@type string[]
	local tools = { "nix", "nixpkgs-fmt", "alejandra", "statix", "deadnix", "nil" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Nix" })
end, { desc = icons.diagnostics.Info .. " Nix info" })

--- Open Nix documentation in the system browser.
---
--- Presents a picker with key reference pages:
--- • Nix Manual          — nix CLI and expression language reference
--- • Nixpkgs Manual      — package set conventions and helpers
--- • NixOS Wiki          — community-maintained wiki
--- • Nix Package Search  — web-based package search
--- • Nix Flakes          — flake system documentation
--- • nix.dev             — tutorials and best practices
keys.lang_map("nix", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Nix Manual", url = "https://nixos.org/manual/nix/stable/" },
		{ name = "Nixpkgs Manual", url = "https://nixos.org/manual/nixpkgs/stable/" },
		{ name = "NixOS Wiki", url = "https://nixos.wiki/" },
		{ name = "Nix Package Search", url = "https://search.nixos.org/packages" },
		{ name = "Nix Flakes", url = "https://nixos.wiki/wiki/Flakes" },
		{ name = "nix.dev", url = "https://nix.dev/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = nix_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Nix-specific alignment presets for mini.align:
-- • nix_attrs — align attribute set entries on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("nix") then
		---@type string Alignment preset icon from icons.lang
		local align_icon = icons.lang.nix

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			nix_attrs = {
				description = "Align Nix attribute set entries on '='",
				icon = align_icon,
				split_pattern = "=",
				category = "devops",
				lang = "nix",
				filetypes = { "nix" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("nix", "nix_attrs")
		align_registry.mark_language_loaded("nix")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("nix", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("nix_attrs"), {
			desc = align_icon .. "  Align Nix attrs",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Nix-specific
-- parts (servers, formatters, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Nix                    │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig                         │ opts fn merge (nil_ls if nix available)      │
-- │ mason.nvim                             │ opts fn merge (nixpkgs-fmt if nix available) │
-- │ conform.nvim                           │ opts merge (nixpkgs_fmt for ft nix)          │
-- │ nvim-lint                              │ opts fn merge (statix/deadnix if available)  │
-- │ nvim-treesitter                        │ opts merge (nix parser added)                │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: nil_ls (the Nix language server) is typically installed via nix
-- itself (`nix profile install nixpkgs#nil`), not via Mason. Only
-- nixpkgs-fmt is managed by Mason as a standalone formatter tool.
-- Statix and deadnix are also installed via nix and conditionally
-- registered as nvim-lint linters based on runtime availability.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Nix
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- nil_ls: Nix language server providing completions, diagnostics,
	-- go-to-definition, and flake-aware evaluation.
	--
	-- Configuration:
	-- • formatting.command = nixpkgs-fmt — delegates formatting to nixpkgs-fmt
	-- • flake.autoArchive = true         — auto-archive dirty inputs
	-- • flake.autoEvalInputs = true      — evaluate flake inputs for completions
	--
	-- Only configured if the nix binary is available.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = function(_, opts)
			if has_executable("nix") then
				opts.servers = opts.servers or {}
				opts.servers.nil_ls = {
					settings = {
						["nil"] = {
							formatting = {
								command = { "nixpkgs-fmt" },
							},
							nix = {
								flake = {
									autoArchive = true,
									autoEvalInputs = true,
								},
							},
						},
					},
				}
			end
		end,
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					nix = "nix",
				},
				filename = {
					["flake.lock"] = "json",
				},
			})

			-- ── Buffer-local options for Nix files ───────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "nix" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "100"
					opt.textwidth = 100
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true
					opt.number = true
					opt.relativenumber = true
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
					opt.commentstring = "# %s"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Only nixpkgs-fmt is managed by Mason. nil_ls, statix, and deadnix
	-- are typically installed via nix itself.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}
			if has_executable("nix") then vim.list_extend(opts.ensure_installed, { "nixpkgs-fmt" }) end
		end,
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- nixpkgs-fmt: the standard Nix formatter used by the nixpkgs repository.
	-- An alternative is alejandra (more opinionated), which can be swapped
	-- by changing this to { "alejandra" }.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				nix = { "nixpkgs_fmt" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- Conditionally registers statix and deadnix based on runtime
	-- availability. Both are optional tools installed via nix:
	-- • statix  — detects anti-patterns and suggests improvements
	-- • deadnix — finds unused let bindings, function args, and with imports
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = function(_, opts)
			---@type string[]
			local linters = {}
			if has_executable("statix") then linters[#linters + 1] = "statix" end
			if has_executable("deadnix") then linters[#linters + 1] = "deadnix" end
			if #linters > 0 then
				opts.linters_by_ft = opts.linters_by_ft or {}
				opts.linters_by_ft.nix = linters
			end
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- nix: syntax highlighting, folding, text objects and indentation
	--      for Nix expression language files (.nix).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"nix",
			},
		},
	},
}
