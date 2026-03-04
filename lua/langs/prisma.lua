---@file lua/langs/prisma.lua
---@description Prisma — LSP, formatter, treesitter & buffer-local keymaps
---@module "langs.prisma"
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
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/prisma.lua — Prisma ORM schema support                            ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("prisma") → {} if off       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "prisma"):                   │    ║
--- ║  │  ├─ LSP          prismals  (Prisma Language Server)              │    ║
--- ║  │  ├─ Formatter    prisma format (built-in CLI formatter)          │    ║
--- ║  │  ├─ Treesitter   prisma parser (syntax + folding)                │    ║
--- ║  │  └─ Extras       schema stats · commands picker · docs browser   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ GENERATE   r  Generate Prisma client                         │    ║
--- ║  │  ├─ MIGRATE    d  Migrate dev (named)   D  Migrate deploy        │    ║
--- ║  │  │             e  Reset database                                 │    ║
--- ║  │  ├─ STUDIO     s  Open Prisma Studio (background, port 5555)     │    ║
--- ║  │  ├─ DATABASE   p  DB push               P  DB pull (introspect)  │    ║
--- ║  │  │             t  DB seed                                        │    ║
--- ║  │  ├─ FORMAT     f  Format schema (prisma format)                  │    ║
--- ║  │  ├─ VALIDATE   v  Validate schema                                │    ║
--- ║  │  ├─ COMMANDS   c  Prisma commands picker (12 actions)            │    ║
--- ║  │  ├─ STATS      i  Schema stats (models/enums/fields/relations)   │    ║
--- ║  │  └─ DOCS       h  Documentation browser (Prisma docs links)      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Prisma CLI resolution:                                          │    ║
--- ║  │  ┌───────────────────────────────────────────────────────────┐   │    ║
--- ║  │  │  1. node_modules/.bin/prisma → npx prisma (project-local) │   │    ║
--- ║  │  │  2. prisma                   → global install             │   │    ║
--- ║  │  │  3. nil                      → user notification          │   │    ║
--- ║  │  └───────────────────────────────────────────────────────────┘   │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType prisma):                            ║
--- ║  • colorcolumn=100, textwidth=100  (Prisma schema convention)            ║
--- ║  • tabstop=2, shiftwidth=2         (2-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="// %s"           (Prisma uses // comments)             ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .prisma → prisma                                                      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Prisma support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("prisma") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Prisma Nerd Font icon (trailing whitespace stripped)
local prisma_icon = icons.lang.prisma:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Prisma buffers.
-- The group is buffer-local and only visible when filetype == "prisma".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("prisma", "Prisma", prisma_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the best available Prisma CLI binary.
---
--- Resolution order:
--- 1. `node_modules/.bin/prisma` → `npx prisma` (project-local, highest priority)
--- 2. `prisma`                   → global install
--- 3. `nil`                      → not found
---
--- ```lua
--- local cmd = get_prisma_cmd()
--- if cmd then
---   vim.cmd.terminal(cmd .. " generate")
--- end
--- ```
---
---@return string|nil cmd The Prisma CLI command string, or `nil` if not found
---@private
local function get_prisma_cmd()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/node_modules/.bin/prisma") == 1 then return "npx prisma" end
	if vim.fn.executable("prisma") == 1 then return "prisma" end
	return nil
end

--- Detect the Prisma CLI and notify the user if not found.
---
--- Wraps `get_prisma_cmd()` with a user-facing error notification.
--- All keymaps should call this instead of `get_prisma_cmd()` directly
--- to ensure consistent error messaging.
---
---@return string|nil cmd The Prisma CLI command string, or `nil` (with notification)
---@private
local function check_prisma()
	local cmd = get_prisma_cmd()
	if not cmd then
		vim.notify("prisma not found\nInstall: npm install prisma", vim.log.levels.WARN, { title = "Prisma" })
	end
	return cmd
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — GENERATE / MIGRATE
--
-- Client generation and database migration workflows.
-- All keymaps save the buffer before executing CLI commands.
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate the Prisma client from the current schema.
---
--- Saves the buffer, then runs `prisma generate` in a terminal split.
--- The generated client reflects all model/enum changes in the schema.
keys.lang_map("prisma", "n", "<leader>lr", function()
	local cmd = check_prisma()
	if not cmd then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " generate")
end, { desc = prisma_icon .. " Generate client" })

--- Run a named development migration.
---
--- Prompts for a migration name via `vim.ui.input()`, then executes
--- `prisma migrate dev --name <name>`. Aborts silently if the user
--- cancels the prompt or provides an empty name.
keys.lang_map("prisma", "n", "<leader>ld", function()
	local cmd = check_prisma()
	if not cmd then return end
	vim.cmd("silent! write")
	vim.ui.input({ prompt = "Migration name: " }, function(name)
		if not name or name == "" then return end
		vim.cmd.split()
		vim.cmd.terminal(cmd .. " migrate dev --name " .. vim.fn.shellescape(name))
	end)
end, { desc = icons.dev.Database .. " Migrate dev" })

--- Deploy pending migrations to production.
---
--- Runs `prisma migrate deploy` which applies all pending migrations
--- without creating new ones. Safe for production environments.
keys.lang_map("prisma", "n", "<leader>lD", function()
	local cmd = check_prisma()
	if not cmd then return end
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " migrate deploy")
end, { desc = icons.dev.Database .. " Migrate deploy" })

--- Reset the database (destructive operation).
---
--- Runs `prisma migrate reset` which drops the database, recreates it,
--- and applies all migrations from scratch. Use with caution.
keys.lang_map("prisma", "n", "<leader>le", function()
	local cmd = check_prisma()
	if not cmd then return end
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " migrate reset")
end, { desc = icons.diagnostics.Warn .. " Reset database" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — STUDIO / DATABASE
--
-- Prisma Studio GUI and direct database operations.
-- Studio runs as a detached background process on port 5555.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open Prisma Studio in the background.
---
--- Launches `prisma studio` as a detached job (does not block Neovim).
--- The Studio GUI is accessible at `http://localhost:5555`.
keys.lang_map("prisma", "n", "<leader>ls", function()
	local cmd = check_prisma()
	if not cmd then return end
	vim.fn.jobstart(cmd .. " studio", { detach = true })
	vim.notify("Prisma Studio at http://localhost:5555", vim.log.levels.INFO, { title = "Prisma" })
end, { desc = prisma_icon .. " Prisma Studio" })

--- Push the schema state to the database without migrations.
---
--- Runs `prisma db push` which synchronizes the database schema
--- with the Prisma schema file. Useful for prototyping (no migration
--- history is created).
keys.lang_map("prisma", "n", "<leader>lp", function()
	local cmd = check_prisma()
	if not cmd then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " db push")
end, { desc = icons.dev.Database .. " DB push" })

--- Pull (introspect) the database schema into the Prisma schema file.
---
--- Runs `prisma db pull` which reads the existing database structure
--- and updates the Prisma schema to reflect it. Useful for brownfield
--- projects or after manual database changes.
keys.lang_map("prisma", "n", "<leader>lP", function()
	local cmd = check_prisma()
	if not cmd then return end
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " db pull")
end, { desc = icons.dev.Database .. " DB pull (introspect)" })

--- Seed the database with initial data.
---
--- Runs `prisma db seed` which executes the seed script defined
--- in `package.json` under `prisma.seed`.
keys.lang_map("prisma", "n", "<leader>lt", function()
	local cmd = check_prisma()
	if not cmd then return end
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " db seed")
end, { desc = icons.dev.Database .. " Seed" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FORMAT / VALIDATE
--
-- Schema formatting and validation using the Prisma CLI.
-- Format runs in-place and reloads the buffer.
-- Validate provides pass/fail feedback via notifications.
-- ═══════════════════════════════════════════════════════════════════════════

--- Format the current Prisma schema file.
---
--- Saves the buffer, runs `prisma format` in-place, then reloads
--- the buffer to reflect changes. Reports success or error via
--- notifications.
keys.lang_map("prisma", "n", "<leader>lf", function()
	local cmd = check_prisma()
	if not cmd then return end
	vim.cmd("silent! write")
	local result = vim.fn.system(cmd .. " format 2>&1")
	vim.cmd.edit()
	if vim.v.shell_error == 0 then
		vim.notify("Formatted", vim.log.levels.INFO, { title = "Prisma" })
	else
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "Prisma" })
	end
end, { desc = prisma_icon .. " Format" })

--- Validate the current Prisma schema.
---
--- Runs `prisma validate` and reports the result via notification.
--- Does not modify the schema file.
keys.lang_map("prisma", "n", "<leader>lv", function()
	local cmd = check_prisma()
	if not cmd then return end
	vim.cmd("silent! write")
	local result = vim.fn.system(cmd .. " validate 2>&1")
	if vim.v.shell_error == 0 then
		vim.notify("✓ Schema valid", vim.log.levels.INFO, { title = "Prisma" })
	else
		vim.notify("✗ Validation errors:\n" .. result, vim.log.levels.ERROR, { title = "Prisma" })
	end
end, { desc = icons.ui.Check .. " Validate" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COMMANDS PICKER
--
-- Unified command palette for all Prisma CLI operations.
-- Presents a fuzzy-searchable list via `vim.ui.select()`.
-- Some commands prompt for additional input (e.g. migration name).
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Prisma commands picker.
---
--- Presents all 12 available Prisma CLI commands in a selection menu.
--- Commands marked with `prompt = true` will ask for additional input
--- (e.g. migration name) before execution.
---
--- Available commands:
--- - generate, format, validate
--- - migrate dev, migrate deploy, migrate reset, migrate status
--- - db push, db pull, db seed
--- - studio, version
keys.lang_map("prisma", "n", "<leader>lc", function()
	local cmd = check_prisma()
	if not cmd then return end

	---@type { name: string, cmd: string, prompt?: boolean }[]
	local actions = {
		{ name = "generate", cmd = cmd .. " generate" },
		{ name = "format", cmd = cmd .. " format" },
		{ name = "validate", cmd = cmd .. " validate" },
		{ name = "migrate dev…", cmd = cmd .. " migrate dev --name", prompt = true },
		{ name = "migrate deploy", cmd = cmd .. " migrate deploy" },
		{ name = "migrate reset", cmd = cmd .. " migrate reset" },
		{ name = "migrate status", cmd = cmd .. " migrate status" },
		{ name = "db push", cmd = cmd .. " db push" },
		{ name = "db pull", cmd = cmd .. " db pull" },
		{ name = "db seed", cmd = cmd .. " db seed" },
		{ name = "studio", cmd = cmd .. " studio" },
		{ name = "version", cmd = cmd .. " version" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = prisma_icon .. " Prisma:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]
			if action.prompt then
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
end, { desc = prisma_icon .. " Prisma commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — STATS / DOCUMENTATION
--
-- Schema analysis and external documentation access.
-- Stats are computed by parsing the current buffer with pattern matching.
-- Documentation links open in the system browser via `vim.ui.open()`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Display schema statistics for the current Prisma file.
---
--- Parses the current buffer line-by-line to count:
--- - **Models**: lines matching `^model <name>`
--- - **Enums**: lines matching `^enum <name>`
--- - **Fields**: indented identifiers inside model blocks
--- - **Relations**: fields annotated with `@relation`
--- - **Total lines**: buffer line count
---
--- Results are displayed in a notification popup.
keys.lang_map("prisma", "n", "<leader>li", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	---@type integer
	local models = 0
	---@type integer
	local enums = 0
	---@type integer
	local fields = 0
	---@type integer
	local relations = 0
	---@type boolean
	local in_model = false

	for _, line in ipairs(lines) do
		if line:match("^model%s+") then
			models = models + 1
			in_model = true
		elseif line:match("^enum%s+") then
			enums = enums + 1
			in_model = false
		elseif line:match("^}") then
			in_model = false
		elseif in_model and line:match("^%s+%w+") then
			fields = fields + 1
			if line:match("@relation") then relations = relations + 1 end
		end
	end

	vim.notify(
		string.format(
			"%s Schema Stats:\n"
				.. "  Models:    %d\n"
				.. "  Enums:     %d\n"
				.. "  Fields:    %d\n"
				.. "  Relations: %d\n"
				.. "  Lines:     %d",
			prisma_icon,
			models,
			enums,
			fields,
			relations,
			#lines
		),
		vim.log.levels.INFO,
		{ title = "Prisma" }
	)
end, { desc = icons.diagnostics.Info .. " Schema stats" })

--- Open Prisma documentation in the system browser.
---
--- Presents a selection menu with links to key Prisma documentation
--- pages. The selected URL is opened via `vim.ui.open()` which
--- delegates to the system's default browser.
---
--- Available documentation links:
--- - Prisma Docs (main)
--- - Schema Reference
--- - Prisma Client API
--- - Prisma Migrate guide
keys.lang_map("prisma", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Prisma Docs", url = "https://www.prisma.io/docs" },
		{ name = "Schema Reference", url = "https://www.prisma.io/docs/reference/api-reference/prisma-schema-reference" },
		{ name = "Prisma Client API", url = "https://www.prisma.io/docs/reference/api-reference/prisma-client-reference" },
		{ name = "Prisma Migrate", url = "https://www.prisma.io/docs/concepts/components/prisma-migrate" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = prisma_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Prisma-specific alignment presets for mini.align:
-- • prisma_fields — align model field columns on whitespace
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("prisma") then
		---@type string Alignment preset icon from icons.lang
		local prisma_align_icon = icons.lang.prisma

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			prisma_fields = {
				description = "Align Prisma model fields",
				icon = prisma_align_icon,
				split_pattern = "%s+",
				category = "web",
				lang = "prisma",
				filetypes = { "prisma" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("prisma", "prisma_fields")
		align_registry.mark_language_loaded("prisma")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("prisma", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("prisma_fields"), {
			desc = prisma_align_icon .. "  Align Prisma fields",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Prisma-specific
-- parts (servers, parsers, filetype extensions, buffer options).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Prisma                 │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (prismals server added)           │
-- │ mason.nvim         │ opts merge (prisma-language-server ensured)  │
-- │ nvim-treesitter    │ opts merge (prisma parser ensured)           │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Prisma
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- prismals: Prisma Language Server (completions, diagnostics, hover,
	-- go-to-definition for models/enums/relations)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				prismals = {},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					prisma = "prisma",
				},
			})

			-- ── Buffer-local options for Prisma files ────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "prisma" },
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

					opt.commentstring = "// %s"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures prisma-language-server is installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"prisma-language-server",
			},
		},
	},

	-- ── TREESITTER PARSER ──────────────────────────────────────────────────
	-- prisma: syntax highlighting, folding, indentation
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"prisma",
			},
		},
	},
}
