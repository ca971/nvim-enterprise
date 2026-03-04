---@file lua/langs/ruby.lua
---@description Ruby — LSP, formatter, linter, treesitter, DAP & buffer-local keymaps
---@module "langs.ruby"
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
---@see langs.prisma             Prisma language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/ruby.lua — Ruby language support                                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("ruby") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "ruby"):                     │    ║
--- ║  │  ├─ LSP          ruby_lsp  (completions, diagnostics, actions)   │    ║
--- ║  │  ├─ Formatter    rubocop   (via conform.nvim)                    │    ║
--- ║  │  ├─ Linter       rubocop   (via nvim-lint)                       │    ║
--- ║  │  ├─ Treesitter   ruby · embedded_template (ERB) parsers          │    ║
--- ║  │  ├─ DAP          rdbg      (ruby/debug gem, NOT Mason-managed)   │    ║
--- ║  │  └─ Extras       Rails sub-group · test/source switcher          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file             R  Run with arguments      │    ║
--- ║  │  │            e  Execute line/selection                          │    ║
--- ║  │  ├─ TEST      t  Run tests (rspec/minitest)                      │    ║
--- ║  │  │            T  Test file/line (cursor position)                │    ║
--- ║  │  ├─ DEBUG     d  Debug (rdbg via DAP continue)                   │    ║
--- ║  │  ├─ REPL      c  REPL (pry > rails console > irb)                │    ║
--- ║  │  ├─ TOOLS     x  Rubocop auto-correct  b  Bundle install         │    ║
--- ║  │  │            s  Switch test ↔ source                            │    ║
--- ║  │  ├─ DOCS      h  Ruby docs (ri / browser)                        │    ║
--- ║  │  │            i  Gem info (gem info / rubygems.org)              │    ║
--- ║  │  └─ RAILS     a  Rails sub-group (only in Rails projects)        │    ║
--- ║  │     ├─ as  Server (bin/rails server)                             │    ║
--- ║  │     ├─ ac  Console (bin/rails console)                           │    ║
--- ║  │     ├─ ag  Generate (prompted)                                   │    ║
--- ║  │     ├─ am  Migrate picker (5 actions)                            │    ║
--- ║  │     ├─ ar  Routes (bin/rails routes)                             │    ║
--- ║  │     └─ ad  DB operations picker (4 actions)                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Ruby interpreter resolution:                                    │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. ruby  → system PATH executable check                 │    │    ║
--- ║  │  │  2. nil   → user notification with error                 │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Test runner auto-detection:                                     │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Gemfile contains "rspec" → bundle exec rspec         │    │    ║
--- ║  │  │  2. Gemfile exists           → bundle exec rake test     │    │    ║
--- ║  │  │  3. rspec executable         → rspec                     │    │    ║
--- ║  │  │  4. fallback                 → ruby -Itest <file>        │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  REPL resolution:                                                │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. pry executable   → pry (enhanced REPL)               │    │    ║
--- ║  │  │  2. Rails project    → bin/rails console                 │    │    ║
--- ║  │  │  3. fallback         → irb (standard REPL)               │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Test ↔ Source switching:                                        │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  _spec.rb → app/ or lib/ (strips spec/ prefix)           │    │    ║
--- ║  │  │  _test.rb → app/ (strips test/ prefix)                   │    │    ║
--- ║  │  │  .rb      → spec/ (adds _spec.rb suffix)                 │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  DAP integration flow:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. nvim-dap loads on ft = "ruby"                        │    │    ║
--- ║  │  │  2. Configures dap.adapters.ruby → rdbg (gem debug)      │    │    ║
--- ║  │  │  3. Adds 4 dap.configurations.ruby:                      │    │    ║
--- ║  │  │     • Launch current file                                │    │    ║
--- ║  │  │     • Launch with arguments                              │    │    ║
--- ║  │  │     • Rails server (debug)                               │    │    ║
--- ║  │  │     • RSpec current file                                 │    │    ║
--- ║  │  │  4. All core DAP keymaps become active:                  │    │    ║
--- ║  │  │     <leader>dc · <leader>db · F5 · F9 · etc.             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType ruby):                              ║
--- ║  • colorcolumn=120                 (Ruby community convention)           ║
--- ║  • tabstop=2, shiftwidth=2         (2-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .rb, .rake, .gemspec, .ru → ruby                                      ║
--- ║  • Gemfile, Rakefile, Guardfile, Vagrantfile → ruby                      ║
--- ║  • .pryrc, .irbrc → ruby                                                 ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Ruby support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("ruby") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Ruby Nerd Font icon (trailing whitespace stripped)
local rb_icon = icons.lang.ruby:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Ruby buffers.
-- The group is buffer-local and only visible when filetype == "ruby".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("ruby", "Ruby", rb_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the Ruby interpreter in PATH.
---
--- ```lua
--- local ruby = get_ruby()
--- if ruby then
---   vim.cmd.terminal(ruby .. " script.rb")
--- end
--- ```
---
---@return string|nil path The `ruby` command if executable, or `nil` if not found
---@private
local function get_ruby()
	if vim.fn.executable("ruby") == 1 then return "ruby" end
	return nil
end

--- Notify the user that no Ruby interpreter was found.
---
--- Centralizes the error notification to avoid repetition across
--- all keymaps that require a Ruby binary.
---
---@return nil
---@private
local function notify_no_ruby()
	vim.notify("Ruby not found", vim.log.levels.ERROR, { title = "Ruby" })
end

--- Detect whether the current project is a Rails application.
---
--- Checks for:
--- 1. `bin/rails` executable (standard Rails binstub)
--- 2. `Gemfile` containing the word "rails"
---
--- NOTE: The Gemfile check uses `vim.fn.search()` which searches
--- the current buffer, not the Gemfile. This is a heuristic that
--- works when the Gemfile is open, but may give false negatives
--- otherwise. Consider improving with `vim.fn.readfile()` if needed.
---
---@return boolean is_rails `true` if the project appears to be a Rails app
---@private
local function is_rails()
	return vim.fn.filereadable("bin/rails") == 1
		or (vim.fn.filereadable("Gemfile") == 1 and vim.fn.search("rails", "n") > 0)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- File execution and line/selection evaluation via the Ruby interpreter.
-- All keymaps open a terminal split for output.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current Ruby file in a terminal split.
---
--- Saves the buffer before execution. Uses the system `ruby`
--- interpreter detected by `get_ruby()`.
keys.lang_map("ruby", "n", "<leader>lr", function()
	local ruby = get_ruby()
	if not ruby then
		notify_no_ruby()
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(ruby .. " " .. vim.fn.shellescape(vim.fn.expand("%:p")))
end, { desc = icons.ui.Play .. " Run file" })

--- Run the current Ruby file with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then passes them
--- to `ruby` after the file path. Aborts silently if the user
--- cancels the prompt.
keys.lang_map("ruby", "n", "<leader>lR", function()
	local ruby = get_ruby()
	if not ruby then
		notify_no_ruby()
		return
	end
	vim.cmd("silent! write")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal(ruby .. " " .. vim.fn.shellescape(vim.fn.expand("%:p")) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Execute the current line as a Ruby one-liner.
---
--- Strips leading whitespace before passing to `ruby -e`.
--- Skips silently if the line is empty.
keys.lang_map("ruby", "n", "<leader>le", function()
	local ruby = get_ruby()
	if not ruby then
		notify_no_ruby()
		return
	end
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	if line == "" then return end
	vim.cmd.split()
	vim.cmd.terminal(ruby .. " -e " .. vim.fn.shellescape(line))
end, { desc = rb_icon .. " Execute current line" })

--- Execute the visual selection as Ruby code.
---
--- Yanks the selection into register `z`, then passes it to
--- `ruby -e` in a terminal split.
keys.lang_map("ruby", "v", "<leader>le", function()
	local ruby = get_ruby()
	if not ruby then
		notify_no_ruby()
		return
	end
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code == "" then return end
	vim.cmd.split()
	vim.cmd.terminal(ruby .. " -e " .. vim.fn.shellescape(code))
end, { desc = rb_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution with auto-detection of the test framework.
-- Supports RSpec (via Gemfile or standalone) and Minitest (via rake).
-- Single-file testing uses cursor position for RSpec line filtering.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite with the auto-detected test runner.
---
--- Detection order:
--- 1. Gemfile with `rspec` → `bundle exec rspec`
--- 2. Gemfile without rspec → `bundle exec rake test`
--- 3. `rspec` executable → `rspec`
--- 4. Fallback → `ruby -Itest <file>`
keys.lang_map("ruby", "n", "<leader>lt", function()
	vim.cmd("silent! write")

	---@type string
	local cmd
	if vim.fn.filereadable("Gemfile") == 1 then
		if vim.fn.system("grep -q rspec Gemfile 2>/dev/null; echo $?"):gsub("%s+", "") == "0" then
			cmd = "bundle exec rspec"
		else
			cmd = "bundle exec rake test"
		end
	elseif vim.fn.executable("rspec") == 1 then
		cmd = "rspec"
	else
		cmd = "ruby -Itest " .. vim.fn.shellescape(vim.fn.expand("%:p"))
	end

	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Test .. " Run tests" })

--- Run tests for the current file, optionally at the cursor line.
---
--- For RSpec files (`_spec.rb`): runs with `:<line>` suffix for
--- precise test targeting. For other test files: runs the whole
--- file with `ruby -Itest`.
keys.lang_map("ruby", "n", "<leader>lT", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	---@type integer
	local line = vim.api.nvim_win_get_cursor(0)[1]

	---@type string
	local cmd
	if file:match("_spec%.rb$") then
		cmd = "bundle exec rspec " .. vim.fn.shellescape(file) .. ":" .. line
	else
		cmd = "ruby -Itest " .. vim.fn.shellescape(file)
	end

	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Test .. " Test file/line" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via nvim-dap and the rdbg adapter.
--
-- <leader>ld starts or continues a debug session. The adapter (rdbg)
-- is configured by the nvim-dap spec below when the filetype loads.
-- Both <leader>ld (lang) and <leader>dc (core dap) work in Ruby files.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Saves the buffer, then calls `dap.continue()` which either resumes
--- a paused session or launches a new one using the Ruby adapter (rdbg).
---
--- Requires the `debug` gem to be installed:
--- ```sh
--- gem install debug
--- ```
keys.lang_map("ruby", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Ruby" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (rdbg)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
--
-- Opens an interactive Ruby REPL in a terminal split.
-- Auto-selects the best available REPL: pry > rails console > irb.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a Ruby REPL in a terminal split.
---
--- Resolution order:
--- 1. `pry` → enhanced REPL with syntax highlighting and debugging
--- 2. Rails project → `bin/rails console` (includes app context)
--- 3. Fallback → `irb` (standard Ruby REPL)
keys.lang_map("ruby", "n", "<leader>lc", function()
	---@type string
	local cmd
	if vim.fn.executable("pry") == 1 then
		cmd = "pry"
	elseif is_rails() then
		cmd = "bin/rails console"
	else
		cmd = "irb"
	end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Terminal .. " REPL" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Development utilities: Rubocop auto-correction, Bundler, and
-- test/source file switching.
-- ═══════════════════════════════════════════════════════════════════════════

--- Auto-correct the current file with Rubocop.
---
--- Runs `rubocop -A` (aggressive auto-correct) in-place on the
--- current file, then reloads the buffer to reflect changes.
keys.lang_map("ruby", "n", "<leader>lx", function()
	vim.cmd("silent! write")
	vim.fn.system("rubocop -A " .. vim.fn.shellescape(vim.fn.expand("%:p")))
	vim.cmd.edit()
	vim.notify("Rubocop auto-corrected", vim.log.levels.INFO, { title = "Ruby" })
end, { desc = rb_icon .. " Rubocop fix" })

--- Run `bundle install` in a terminal split.
---
--- Installs all gems specified in the project's Gemfile.
keys.lang_map("ruby", "n", "<leader>lb", function()
	vim.cmd.split()
	vim.cmd.terminal("bundle install")
end, { desc = icons.ui.Package .. " Bundle install" })

--- Switch between test and source files.
---
--- Applies heuristic path transformations:
--- - `spec/*_spec.rb` → `app/*.rb` or `lib/*.rb`
--- - `test/*_test.rb` → `app/*.rb`
--- - `app/*.rb` or `lib/*.rb` → `spec/*_spec.rb`
---
--- Notifies the user if no matching file is found on disk.
keys.lang_map("ruby", "n", "<leader>ls", function()
	local file = vim.fn.expand("%:p")

	---@type string|nil
	local target
	if file:match("_spec%.rb$") then
		-- spec → source (try app/ first, then lib/)
		target = file:gsub("spec/", "app/"):gsub("_spec%.rb$", ".rb")
		if vim.fn.filereadable(target) ~= 1 then target = file:gsub("spec/", "lib/"):gsub("_spec%.rb$", ".rb") end
	elseif file:match("_test%.rb$") then
		-- test → source
		target = file:gsub("test/", "app/"):gsub("_test%.rb$", ".rb")
	else
		-- source → spec (try app/ first, then lib/)
		target = file:gsub("app/", "spec/"):gsub("%.rb$", "_spec.rb")
		if vim.fn.filereadable(target) ~= 1 then target = file:gsub("lib/", "spec/"):gsub("%.rb$", "_spec.rb") end
	end

	if target and vim.fn.filereadable(target) == 1 then
		vim.cmd.edit(target)
	else
		vim.notify("No matching file", vim.log.levels.INFO, { title = "Ruby" })
	end
end, { desc = rb_icon .. " Switch test ↔ source" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to Ruby documentation via `ri` (Ruby Interactive) and
-- gem metadata. Falls back to browser-based documentation when CLI
-- tools are not available.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show Ruby documentation for the word under cursor.
---
--- Uses `ri` (Ruby Interactive documentation) if available, otherwise
--- opens `ruby-doc.org` in the system browser with a search query.
--- Skips silently if the cursor is not on a word.
keys.lang_map("ruby", "n", "<leader>lh", function()
	---@type string
	local word = vim.fn.expand("<cword>")
	if word == "" then return end

	if vim.fn.executable("ri") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("ri " .. vim.fn.shellescape(word))
	else
		vim.ui.open("https://ruby-doc.org/search.html?q=" .. word)
	end
end, { desc = icons.ui.Note .. " Ruby docs (ri)" })

--- Show gem information for the word under cursor.
---
--- Runs `gem info <word>` and displays the result (truncated to
--- 800 chars) in a notification. If the gem is not found locally,
--- opens `rubygems.org` in the system browser with a search query.
keys.lang_map("ruby", "n", "<leader>li", function()
	---@type string
	local word = vim.fn.expand("<cword>")
	if word == "" then return end

	local result = vim.fn.system("gem info " .. word .. " 2>/dev/null")
	if vim.v.shell_error == 0 and result ~= "" then
		vim.notify(result:sub(1, 800), vim.log.levels.INFO, { title = "gem: " .. word })
	else
		vim.ui.open("https://rubygems.org/search?query=" .. word)
	end
end, { desc = icons.diagnostics.Info .. " Gem info" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RAILS SUB-GROUP
--
-- Rails-specific commands under the <leader>la prefix.
-- The parent keymap (<leader>la) acts as a guard that notifies
-- the user if the project is not a Rails application.
-- All sub-keymaps use `bin/rails` (binstub) for correct Bundler context.
-- ═══════════════════════════════════════════════════════════════════════════

--- Rails sub-group entry point.
---
--- Checks if the current project is a Rails application.
--- Displays a notification if not — individual sub-keymaps
--- still work regardless (they just run `bin/rails` commands).
keys.lang_map("ruby", "n", "<leader>la", function()
	if not is_rails() then vim.notify("Not a Rails project", vim.log.levels.INFO, { title = "Ruby" }) end
end, { desc = icons.ui.Rocket .. " Rails" })

--- Start the Rails development server.
---
--- Runs `bin/rails server` in a terminal split.
keys.lang_map("ruby", "n", "<leader>las", function()
	vim.cmd.split()
	vim.cmd.terminal("bin/rails server")
end, { desc = icons.dev.Server .. " Server" })

--- Open the Rails console.
---
--- Runs `bin/rails console` in a terminal split, providing
--- an IRB session with the full Rails application context loaded.
keys.lang_map("ruby", "n", "<leader>lac", function()
	vim.cmd.split()
	vim.cmd.terminal("bin/rails console")
end, { desc = icons.ui.Terminal .. " Console" })

--- Run a Rails generator with user-provided arguments.
---
--- Prompts for generator arguments (e.g. `model User name:string`),
--- then executes `bin/rails generate <args>`. Aborts silently if
--- the user cancels the prompt.
keys.lang_map("ruby", "n", "<leader>lag", function()
	vim.ui.input({ prompt = "Generate (e.g. model User name:string): " }, function(args)
		if not args or args == "" then return end
		vim.cmd.split()
		vim.cmd.terminal("bin/rails generate " .. args)
	end)
end, { desc = icons.ui.Plus .. " Generate" })

--- Open the Rails migration commands picker.
---
--- Presents 5 database migration operations:
--- - `db:migrate`         — Run pending migrations
--- - `db:rollback`        — Rollback the last migration
--- - `db:seed`            — Load seed data
--- - `db:reset`           — Drop, recreate, migrate, and seed
--- - `db:migrate:status`  — Show migration status
keys.lang_map("ruby", "n", "<leader>lam", function()
	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "migrate", cmd = "bin/rails db:migrate" },
		{ name = "rollback", cmd = "bin/rails db:rollback" },
		{ name = "seed", cmd = "bin/rails db:seed" },
		{ name = "reset", cmd = "bin/rails db:reset" },
		{ name = "status", cmd = "bin/rails db:migrate:status" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = "Migration:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = icons.dev.Database .. " Migrate" })

--- Show all Rails routes in a terminal split.
---
--- Runs `bin/rails routes` which outputs the full routing table
--- including HTTP method, path, controller#action, and named helpers.
keys.lang_map("ruby", "n", "<leader>lar", function()
	vim.cmd.split()
	vim.cmd.terminal("bin/rails routes")
end, { desc = icons.ui.List .. " Routes" })

--- Open the Rails database operations picker.
---
--- Presents 4 database management operations:
--- - `db:create`       — Create the database
--- - `db:drop`         — Drop the database
--- - `db:schema:load`  — Load schema from `db/schema.rb`
--- - `db:schema:dump`  — Dump current schema to `db/schema.rb`
keys.lang_map("ruby", "n", "<leader>lad", function()
	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "create", cmd = "bin/rails db:create" },
		{ name = "drop", cmd = "bin/rails db:drop" },
		{ name = "schema:load", cmd = "bin/rails db:schema:load" },
		{ name = "schema:dump", cmd = "bin/rails db:schema:dump" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = "DB:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = icons.dev.Database .. " DB operations" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Ruby-specific alignment presets for mini.align:
-- • ruby_hash   — align hash rocket entries on "=>"
-- • ruby_symbol — align symbol key pairs on ":"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("ruby") then
		---@type string Alignment preset icon from icons.app
		local ruby_align_icon = icons.app.Ruby

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			ruby_hash = {
				description = "Align Ruby hash on '=>'",
				icon = ruby_align_icon,
				split_pattern = "=>",
				category = "scripting",
				lang = "ruby",
				filetypes = { "ruby" },
			},
			ruby_symbol = {
				description = "Align Ruby symbol pairs on ':'",
				icon = ruby_align_icon,
				split_pattern = ":",
				category = "scripting",
				lang = "ruby",
				filetypes = { "ruby" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("ruby", "ruby_hash")
		align_registry.mark_language_loaded("ruby")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("ruby", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("ruby_hash"), {
			desc = ruby_align_icon .. "  Align Ruby hash",
		})
		keys.lang_map("ruby", { "n", "x" }, "<leader>aT", align_registry.make_align_fn("ruby_symbol"), {
			desc = ruby_align_icon .. "  Align Ruby symbols",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Ruby-specific
-- parts (servers, formatters, linters, parsers, adapters).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Ruby                   │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (ruby_lsp server added)          │
-- │ mason.nvim         │ opts merge (ruby-lsp + rubocop ensured)     │
-- │ conform.nvim       │ opts merge (formatters_by_ft.ruby)          │
-- │ nvim-lint          │ opts merge (linters_by_ft.ruby)             │
-- │ nvim-treesitter    │ opts merge (ruby + ERB parsers ensured)     │
-- │ nvim-dap           │ ft = "ruby" (true lazy load, rdbg adapter)  │
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- DAP note:
-- • rdbg is NOT available via Mason — install manually: `gem install debug`
-- • The adapter uses a server-based connection on port 38698
-- • Guard checks prevent duplicate adapter/configuration registration
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Ruby
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- ruby_lsp: Shopify's Ruby LSP (completions, diagnostics, formatting,
	-- code actions, document symbols, semantic highlighting)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				ruby_lsp = {},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					rb = "ruby",
					rake = "ruby",
					gemspec = "ruby",
					ru = "ruby",
				},
				filename = {
					["Gemfile"] = "ruby",
					["Rakefile"] = "ruby",
					["Guardfile"] = "ruby",
					["Vagrantfile"] = "ruby",
					[".pryrc"] = "ruby",
					[".irbrc"] = "ruby",
				},
			})

			-- ── Buffer-local options for Ruby files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "ruby" },
				callback = function()
					local opt = vim.opt_local

					opt.wrap = false
					opt.colorcolumn = "120"

					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true

					opt.number = true
					opt.relativenumber = true

					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures ruby-lsp and rubocop are installed via Mason.
	-- NOTE: rdbg (debug gem) is NOT available via Mason — install
	-- manually with `gem install debug`.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"ruby-lsp",
				"rubocop",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- Rubocop as formatter via conform.nvim.
	-- Enforces Ruby community style guide conventions.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				ruby = { "rubocop" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- Rubocop as linter via nvim-lint (complements the LSP).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				ruby = { "rubocop" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- ruby:              syntax highlighting, folding, text objects
	-- embedded_template: ERB template support (.erb files)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"ruby",
				"embedded_template",
			},
		},
	},

	-- ── DAP — RUBY DEBUGGER ────────────────────────────────────────────────
	-- rdbg (ruby/debug gem) is the standard Ruby debug adapter.
	-- It's NOT available via Mason — install manually:
	--   gem install debug
	--
	-- The adapter uses a server-based connection (host: 127.0.0.1,
	-- port: 38698). rdbg starts the debug server and connects Neovim
	-- as a DAP client.
	--
	-- Custom configurations added:
	--   1. Launch current file        — debug the active buffer
	--   2. Launch with arguments      — prompts for CLI args
	--   3. Rails server (debug)       — debug bin/rails server
	--   4. RSpec current file         — debug tests via bundle exec rspec
	--
	-- After loading, ALL core DAP keymaps work in Ruby files:
	--   <leader>dc, <leader>db, <leader>di, <leader>do, F5, F9, etc.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-dap",
		optional = true,
		ft = "ruby",
		config = function()
			local dap = require("dap")

			-- ── Adapter registration (guarded) ───────────────────────
			if not dap.adapters.ruby then
				dap.adapters.ruby = function(callback, config)
					callback({
						type = "server",
						host = "127.0.0.1",
						port = config.port or 38698,
						executable = {
							command = "rdbg",
							args = {
								"-n",
								"--open",
								"--port",
								tostring(config.port or 38698),
								"-c",
								"--",
								"ruby",
								config.program,
							},
						},
					})
				end
			end

			-- ── Launch configurations (guarded) ──────────────────────
			if not dap.configurations.ruby then
				dap.configurations.ruby = {
					--- Debug the current file.
					{
						type = "ruby",
						request = "attach",
						name = "Launch current file",
						program = "${file}",
						port = 38698,
					},
					--- Debug the current file with user-provided arguments.
					{
						type = "ruby",
						request = "attach",
						name = "Launch with arguments",
						program = "${file}",
						port = 38698,
						args = function()
							local input = vim.fn.input("Arguments: ")
							return vim.split(input, " ", { trimempty = true })
						end,
					},
					--- Debug the Rails development server.
					{
						type = "ruby",
						request = "attach",
						name = "Rails server (debug)",
						program = "bin/rails",
						port = 38698,
						args = { "server" },
					},
					--- Debug RSpec tests for the current file.
					{
						type = "ruby",
						request = "attach",
						name = "RSpec (current file)",
						program = "bundle",
						port = 38698,
						args = function()
							return { "exec", "rspec", vim.fn.expand("%:p") }
						end,
					},
				}
			end
		end,
	},
}
