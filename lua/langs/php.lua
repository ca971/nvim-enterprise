---@file lua/langs/php.lua
---@description PHP — LSP (intelephense), formatter, linter, treesitter, DAP & buffer-local keymaps
---@module "langs.php"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.javascript         JavaScript language support (web ecosystem peer)
---@see langs.python             Python language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/php.lua — PHP language support                                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("php") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "php" / "blade"):            │    ║
--- ║  │  ├─ LSP          intelephense (PHP 8.3, auto-import, telemetry)  │    ║
--- ║  │  │               Completions, diagnostics, refactoring, hover    │    ║
--- ║  │  ├─ Formatter    pint (Laravel) / php-cs-fixer (generic)         │    ║
--- ║  │  │               blade-formatter (Blade templates)               │    ║
--- ║  │  ├─ Linter       phpstan (nvim-lint)                             │    ║
--- ║  │  ├─ Treesitter   php · phpdoc · blade parsers                    │    ║
--- ║  │  ├─ DAP          php-debug-adapter (Xdebug integration)          │    ║
--- ║  │  └─ Extras       laravel.nvim · neotest-pest · neotest-phpunit   │    ║
--- ║  │                  vim-blade · vim-dotenv                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file              R  Run with arguments     │    ║
--- ║  │  │            e  Execute line/selection                          │    ║
--- ║  │  ├─ TEST      t  Run tests (PHPUnit/Pest)                        │    ║
--- ║  │  │            T  Test method under cursor                        │    ║
--- ║  │  ├─ DEBUG     d  Debug (DAP/Xdebug)                              │    ║
--- ║  │  ├─ REPL      c  REPL (tinker/psysh/php -a)                      │    ║
--- ║  │  ├─ SERVER    s  PHP built-in dev server                         │    ║
--- ║  │  ├─ TOOLS     x  Clear OPcache          v  PHP version info      │    ║
--- ║  │  ├─ DOCS      i  Class info (hover)     h  PHP docs (browser)    │    ║
--- ║  │  ├─ COMPOSER  m  → Composer sub-group                            │    ║
--- ║  │  │              mi  Install             mu  Update               │    ║
--- ║  │  │              mr  Require package      md  Dump autoload       │    ║
--- ║  │  └─ ARTISAN   a  → Artisan sub-group (Laravel only)              │    ║
--- ║  │                 as  Serve               am  Make (model/ctrl/…)  │    ║
--- ║  │                 ag  Migrate              ar  Route list          │    ║
--- ║  │                 ac  Cache clear           at  Tinker             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Test runner detection:                                          │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. vendor/bin/pest    → Pest (Laravel-native)           │    │    ║
--- ║  │  │  2. vendor/bin/phpunit → PHPUnit (classic)               │    │    ║
--- ║  │  │  3. sail test          → Laravel Sail (Docker)           │    │    ║
--- ║  │  │  4. None               → notification                    │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  REPL resolution:                                                │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Laravel project → php artisan tinker                 │    │    ║
--- ║  │  │  2. psysh available → psysh (enhanced REPL)              │    │    ║
--- ║  │  │  3. Fallback        → php -a (built-in interactive)      │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  DAP integration flow:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. php-debug-adapter installed via Mason                │    │    ║
--- ║  │  │  2. mason-nvim-dap auto-configures dap.adapters.php      │    │    ║
--- ║  │  │  3. Xdebug must be configured in php.ini:                │    │    ║
--- ║  │  │     xdebug.mode = debug                                  │    │    ║
--- ║  │  │     xdebug.start_with_request = yes                      │    │    ║
--- ║  │  │  4. dap.continue() starts listening for Xdebug           │    │    ║
--- ║  │  │  5. All core DAP keymaps become active:                  │    │    ║
--- ║  │  │     <leader>dc · <leader>db · F5 · F9 · etc.             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType php/blade):                         ║
--- ║  • colorcolumn=120, textwidth=120   (PSR-12 line length)                 ║
--- ║  • tabstop=4, shiftwidth=4          (PSR-12 indentation)                 ║
--- ║  • expandtab=true                   (spaces, never tabs — PSR-12)        ║
--- ║  • Treesitter folding               (foldmethod=expr, foldlevel=99)      ║
--- ║                                                                          ║
--- ║  Laravel detection:                                                      ║
--- ║  • `artisan` file in CWD → Laravel project                               ║
--- ║  • Artisan keymaps only active in Laravel projects                       ║
--- ║  • laravel.nvim conditionally loaded (cond: artisan exists)              ║
--- ║                                                                          ║
--- ║  Conditional tooling (composer-dependent):                               ║
--- ║  • pint, php-cs-fixer, phpstan only added to Mason if composer avail     ║
--- ║  • intelephense + php-debug-adapter always installed (standalone)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .php, .phps          → php                                            ║
--- ║  • .blade.php            → blade                                         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if PHP support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("php") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string PHP Nerd Font icon (trailing whitespace stripped)
local php_icon = icons.lang.php:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for PHP buffers.
-- The group is buffer-local and only visible when filetype == "php".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("php", "PHP", php_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- PHP interpreter detection, Laravel project detection, PHP tag
-- stripping, and notification utilities. All functions are
-- module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the PHP interpreter.
---
--- ```lua
--- local php = get_php()
--- if php then vim.cmd.terminal(php .. " script.php") end
--- ```
---
---@return string|nil php `"php"` if available, `nil` otherwise
---@private
local function get_php()
	if vim.fn.executable("php") == 1 then return "php" end
	return nil
end

--- Notify the user that PHP is not found in `$PATH`.
---
--- Centralizes the error notification to avoid repetition across
--- all keymaps that require the PHP binary.
---
---@return nil
---@private
local function notify_no_php()
	vim.notify("PHP not found", vim.log.levels.ERROR, { title = "PHP" })
end

--- Check if the current project is a Laravel project.
---
--- Laravel projects are identified by the presence of an `artisan`
--- file in the current working directory.
---
--- ```lua
--- if is_laravel() then ... end
--- ```
---
---@return boolean is_laravel `true` if `artisan` file exists in CWD
---@private
local function is_laravel()
	return vim.fn.filereadable("artisan") == 1
end

--- Check for Laravel and notify if not detected.
---
--- Combines the `is_laravel()` check with a notification, used as
--- a guard in all Artisan keymaps to avoid repetition.
---
--- ```lua
--- if not check_laravel() then return end
--- ```
---
---@return boolean is_laravel `true` if in a Laravel project, `false` with notification
---@private
local function check_laravel()
	if is_laravel() then return true end
	vim.notify("Not a Laravel project (no artisan file)", vim.log.levels.INFO, { title = "PHP" })
	return false
end

--- Strip PHP opening tags from a code string.
---
--- Removes `<?php` and `<?` prefixes (with optional whitespace)
--- from code before passing it to `php -r` for evaluation.
---
--- ```lua
--- strip_php_tags("<?php echo 'hello';")  --> "echo 'hello';"
--- strip_php_tags("echo 'hello';")         --> "echo 'hello';"
--- ```
---
---@param code string PHP code that may contain opening tags
---@return string stripped Code with opening tags removed
---@private
local function strip_php_tags(code)
	return code:gsub("^<%?php%s*", ""):gsub("^<%?%s*", "")
end

--- Run an artisan command in a terminal split.
---
--- Guards against non-Laravel projects, then opens a terminal
--- split with the artisan command.
---
--- ```lua
--- run_artisan("serve")
--- run_artisan("migrate:fresh --seed")
--- ```
---
---@param subcommand string Artisan subcommand (e.g. `"serve"`, `"tinker"`)
---@return boolean launched `true` if launched, `false` if not a Laravel project
---@private
local function run_artisan(subcommand)
	if not check_laravel() then return false end
	vim.cmd.split()
	vim.cmd.terminal("php artisan " .. subcommand)
	return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- File execution and line/selection evaluation.
-- PHP opening tags (<?php, <?) are automatically stripped when
-- evaluating lines/selections via `php -r`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current PHP file in a terminal split.
---
--- Saves the buffer before execution.
keys.lang_map("php", "n", "<leader>lr", function()
	local php = get_php()
	if not php then
		notify_no_php()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	vim.cmd.split()
	vim.cmd.terminal(php .. " " .. file)
end, { desc = icons.ui.Play .. " Run file" })

--- Run the current PHP file with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then executes in a
--- terminal split. Aborts silently if the user cancels the prompt.
keys.lang_map("php", "n", "<leader>lR", function()
	local php = get_php()
	if not php then
		notify_no_php()
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal(php .. " " .. file .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Execute the current line as PHP code.
---
--- Strips PHP opening tags (`<?php`, `<?`) before passing to
--- `php -r`. Skips silently if the line is empty after stripping.
keys.lang_map("php", "n", "<leader>le", function()
	local php = get_php()
	if not php then
		notify_no_php()
		return
	end
	local line = strip_php_tags(vim.api.nvim_get_current_line():gsub("^%s+", ""))
	if line == "" then return end
	vim.cmd.split()
	vim.cmd.terminal(php .. " -r " .. vim.fn.shellescape(line))
end, { desc = php_icon .. " Execute current line" })

--- Execute the visual selection as PHP code.
---
--- Yanks the selection into register `z`, strips PHP opening tags,
--- then passes it to `php -r` in a terminal split.
keys.lang_map("php", "v", "<leader>le", function()
	local php = get_php()
	if not php then
		notify_no_php()
		return
	end
	vim.cmd('noautocmd normal! "zy')
	local code = strip_php_tags(vim.fn.getreg("z"))
	if code == "" then return end
	vim.cmd.split()
	vim.cmd.terminal(php .. " -r " .. vim.fn.shellescape(code))
end, { desc = php_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution with auto-detection of the test runner.
-- Supports Pest (Laravel-native), PHPUnit (classic), and
-- Laravel Sail (Docker-based). Test-under-cursor uses treesitter
-- to detect the method name for `--filter`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite (auto-detects Pest, PHPUnit, or Sail).
---
--- Detection strategy (first match wins):
--- 1. `vendor/bin/pest`    → Pest (Laravel-native, BDD-style)
--- 2. `vendor/bin/phpunit` → PHPUnit (classic xUnit)
--- 3. Laravel + `sail`     → `sail test` (Docker environment)
--- 4. None found           → notification
keys.lang_map("php", "n", "<leader>lt", function()
	vim.cmd("silent! write")

	---@type string|nil
	local cmd
	if vim.fn.filereadable("vendor/bin/pest") == 1 then
		cmd = "vendor/bin/pest --colors=always"
	elseif vim.fn.filereadable("vendor/bin/phpunit") == 1 then
		cmd = "vendor/bin/phpunit --colors=always"
	elseif is_laravel() and vim.fn.executable("sail") == 1 then
		cmd = "sail test"
	end

	if not cmd then
		vim.notify("No test runner found (PHPUnit/Pest)", vim.log.levels.WARN, { title = "PHP" })
		return
	end

	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Test .. " Run tests" })

--- Run the test method under cursor.
---
--- Uses treesitter to walk up the AST from the cursor position until
--- a `method_declaration` node is found, then extracts its name for
--- the `--filter` argument. Falls back to running all tests if no
--- method is found.
keys.lang_map("php", "n", "<leader>lT", function()
	vim.cmd("silent! write")

	-- ── Detect test method via treesitter ─────────────────────────
	---@type TSNode|nil
	local node = vim.treesitter.get_node()
	---@type string|nil
	local method_name = nil

	while node do
		if node:type() == "method_declaration" then
			local name_node = node:field("name")[1]
			if name_node then method_name = vim.treesitter.get_node_text(name_node, 0) end
			break
		end
		node = node:parent()
	end

	---@type string
	local filter = method_name and (" --filter=" .. vim.fn.shellescape(method_name)) or ""

	---@type string|nil
	local cmd
	if vim.fn.filereadable("vendor/bin/pest") == 1 then
		cmd = "vendor/bin/pest --colors=always" .. filter
	elseif vim.fn.filereadable("vendor/bin/phpunit") == 1 then
		cmd = "vendor/bin/phpunit --colors=always" .. filter
	end

	if not cmd then
		vim.notify("No test runner found", vim.log.levels.WARN, { title = "PHP" })
		return
	end

	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Test .. " Test under cursor" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via php-debug-adapter (Xdebug).
--
-- <leader>ld starts or continues a debug session. The adapter is
-- auto-configured by mason-nvim-dap. Xdebug must be enabled in
-- php.ini for debugging to work.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Saves the buffer, then calls `dap.continue()` which either resumes
--- a paused session or starts listening for an Xdebug connection.
---
--- Prerequisites:
--- - `php-debug-adapter` installed via Mason
--- - Xdebug configured in `php.ini`:
---   ```ini
---   xdebug.mode = debug
---   xdebug.start_with_request = yes
---   ```
keys.lang_map("php", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "PHP" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (Xdebug)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL & SERVER
--
-- Interactive REPL and PHP built-in development server.
-- REPL prefers Laravel Tinker → PsySH → php -a.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open an interactive PHP REPL in a terminal split.
---
--- Resolution order:
--- 1. Laravel project → `php artisan tinker` (enhanced, Eloquent-aware)
--- 2. `psysh` available → PsySH (better completion, docs, error handling)
--- 3. Fallback → `php -a` (built-in interactive mode, minimal features)
keys.lang_map("php", "n", "<leader>lc", function()
	---@type string
	local cmd
	if is_laravel() then
		cmd = "php artisan tinker"
	elseif vim.fn.executable("psysh") == 1 then
		cmd = "psysh"
	else
		cmd = "php -a"
	end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Terminal .. " REPL" })

--- Start the PHP built-in development server.
---
--- Prompts for a port number (default: 8000), then starts `php -S`
--- serving from the `public/` directory (Laravel convention) or
--- the current directory if `public/` doesn't exist.
keys.lang_map("php", "n", "<leader>ls", function()
	local php = get_php()
	if not php then
		notify_no_php()
		return
	end

	---@type string
	local docroot = vim.fn.isdirectory("public") == 1 and "public" or "."

	vim.ui.input({ prompt = "Port: ", default = "8000" }, function(port)
		if not port then return end
		vim.cmd.split()
		vim.cmd.terminal(string.format("%s -S localhost:%s -t %s", php, port, docroot))
		vim.notify("Server: http://localhost:" .. port, vim.log.levels.INFO, { title = "PHP" })
	end)
end, { desc = icons.dev.Server .. " Serve" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- PHP runtime information and OPcache management.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show PHP version and loaded extensions.
---
--- Displays `php -v` output plus the first 30 loaded extensions
--- from `php -m` in a single notification.
keys.lang_map("php", "n", "<leader>lv", function()
	local php = get_php()
	if not php then
		notify_no_php()
		return
	end
	local version = vim.fn.system(php .. " -v"):gsub("\n$", "")
	local extensions = vim.fn.system(php .. " -m 2>/dev/null | head -30"):gsub("\n$", "")
	vim.notify(version .. "\n\nLoaded extensions:\n" .. extensions, vim.log.levels.INFO, { title = "PHP" })
end, { desc = icons.diagnostics.Info .. " PHP version info" })

--- Clear the PHP OPcache.
---
--- Runs `php -r "opcache_reset();"` to invalidate all cached
--- opcode. Useful during development when class/function changes
--- are not reflected due to OPcache.
keys.lang_map("php", "n", "<leader>lx", function()
	local php = get_php()
	if not php then
		notify_no_php()
		return
	end
	vim.fn.system(php .. ' -r "opcache_reset();"')
	vim.notify("OPcache cleared", vim.log.levels.INFO, { title = "PHP" })
end, { desc = icons.ui.Refresh .. " Clear opcode cache" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- LSP hover for class info and php.net documentation lookup
-- using the underscore-to-hyphen convention for function names.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show class/method info via LSP hover.
---
--- Displays the signature, type info, and PHPDoc documentation
--- for the symbol under the cursor in a floating window.
keys.lang_map("php", "n", "<leader>li", function()
	vim.lsp.buf.hover()
end, { desc = icons.diagnostics.Info .. " Class info" })

--- Open php.net documentation for the function under cursor.
---
--- PHP documentation URLs use hyphens instead of underscores
--- for function names (e.g. `array_map` → `array-map`).
--- Opens the corresponding php.net manual page in the browser.
keys.lang_map("php", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then return end
	local doc_name = word:gsub("_", "-")
	vim.ui.open("https://www.php.net/manual/en/function." .. doc_name .. ".php")
end, { desc = icons.ui.Note .. " PHP docs" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COMPOSER SUB-GROUP
--
-- Package management via Composer. All commands run in a terminal
-- split for real-time output.
-- ═══════════════════════════════════════════════════════════════════════════

--- Register the Composer sub-group placeholder for which-key.
---
--- This no-op keymap exists solely to create a labeled group in
--- which-key's popup menu under `<leader>lm`.
keys.lang_map("php", "n", "<leader>lm", function() end, {
	desc = icons.ui.Package .. " Composer",
})

--- Install all Composer dependencies.
---
--- Runs `composer install` which reads `composer.json` and installs
--- all required packages into `vendor/`.
keys.lang_map("php", "n", "<leader>lmi", function()
	vim.cmd.split()
	vim.cmd.terminal("composer install")
end, { desc = icons.ui.Package .. " Install" })

--- Update all Composer dependencies.
---
--- Runs `composer update` which updates all packages to the latest
--- versions allowed by `composer.json` constraints.
keys.lang_map("php", "n", "<leader>lmu", function()
	vim.cmd.split()
	vim.cmd.terminal("composer update")
end, { desc = icons.ui.Refresh .. " Update" })

--- Add a new Composer dependency.
---
--- Prompts for the package name (e.g. `laravel/framework`), then
--- runs `composer require <package>`. Aborts silently if cancelled.
keys.lang_map("php", "n", "<leader>lmr", function()
	vim.ui.input({ prompt = "Package: " }, function(pkg)
		if not pkg or pkg == "" then return end
		vim.cmd.split()
		vim.cmd.terminal("composer require " .. pkg)
	end)
end, { desc = icons.ui.Plus .. " Require package" })

--- Regenerate the Composer autoloader.
---
--- Runs `composer dump-autoload -o` which rebuilds the optimized
--- class map. Required after adding new classes without Composer.
keys.lang_map("php", "n", "<leader>lmd", function()
	vim.cmd.split()
	vim.cmd.terminal("composer dump-autoload -o")
end, { desc = icons.ui.Refresh .. " Dump autoload" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — ARTISAN SUB-GROUP (LARAVEL)
--
-- Laravel Artisan CLI commands for development workflows.
-- All Artisan keymaps are guarded by `check_laravel()` — they
-- silently abort with a notification outside Laravel projects.
--
-- Supports: serve, make (19 types), migrate (5 variants),
-- route:list, cache:clear (4 caches), and tinker.
-- ═══════════════════════════════════════════════════════════════════════════

--- Register the Artisan sub-group placeholder for which-key.
---
--- Guards against non-Laravel projects. The empty function acts
--- as a group placeholder — which-key intercepts the prefix.
keys.lang_map("php", "n", "<leader>la", function()
	check_laravel()
end, {
	desc = icons.ui.Rocket .. " Artisan (Laravel)",
})

--- Start the Laravel development server.
---
--- Runs `php artisan serve` which starts a local development server
--- on port 8000 (configurable via `--port`).
keys.lang_map("php", "n", "<leader>las", function()
	run_artisan("serve")
end, { desc = icons.dev.Server .. " Serve" })

--- Create a new Laravel component via `artisan make:*`.
---
--- Presents a list of 19 component types (model, controller,
--- migration, middleware, etc.) via `vim.ui.select()`, then
--- prompts for the component name.
keys.lang_map("php", "n", "<leader>lam", function()
	if not check_laravel() then return end

	---@type string[]
	local types = {
		"model",
		"controller",
		"migration",
		"middleware",
		"request",
		"resource",
		"command",
		"event",
		"listener",
		"job",
		"mail",
		"notification",
		"policy",
		"provider",
		"seeder",
		"factory",
		"test",
		"component",
		"livewire",
	}

	vim.ui.select(types, { prompt = "Make:" }, function(type)
		if not type then return end
		vim.ui.input({ prompt = "Name: " }, function(name)
			if not name or name == "" then return end
			run_artisan("make:" .. type .. " " .. name)
		end)
	end)
end, { desc = icons.ui.Plus .. " Make" })

--- Run database migrations via `artisan migrate`.
---
--- Presents a list of migration variants:
--- - `migrate` — run pending migrations
--- - `migrate:fresh` — drop all tables + migrate
--- - `migrate:fresh --seed` — drop + migrate + seed
--- - `migrate:rollback` — rollback last batch
--- - `migrate:status` — show migration status
keys.lang_map("php", "n", "<leader>lag", function()
	if not check_laravel() then return end

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "migrate", cmd = "migrate" },
		{ name = "migrate:fresh", cmd = "migrate:fresh" },
		{ name = "migrate:fresh --seed", cmd = "migrate:fresh --seed" },
		{ name = "migrate:rollback", cmd = "migrate:rollback" },
		{ name = "migrate:status", cmd = "migrate:status" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = "Migration:" },
		function(_, idx)
			if idx then run_artisan(actions[idx].cmd) end
		end
	)
end, { desc = icons.dev.Database .. " Migrate" })

--- Show all registered routes via `artisan route:list`.
keys.lang_map("php", "n", "<leader>lar", function()
	run_artisan("route:list")
end, { desc = icons.ui.List .. " Route list" })

--- Clear all Laravel caches.
---
--- Runs four cache-clearing commands in sequence:
--- 1. `cache:clear` — application cache
--- 2. `config:clear` — configuration cache
--- 3. `view:clear` — compiled Blade templates
--- 4. `route:clear` — route cache
keys.lang_map("php", "n", "<leader>lac", function()
	if not check_laravel() then return end
	vim.cmd.split()
	vim.cmd.terminal(
		"php artisan cache:clear"
			.. " && php artisan config:clear"
			.. " && php artisan view:clear"
			.. " && php artisan route:clear"
	)
end, { desc = icons.ui.Close .. " Cache clear" })

--- Open Laravel Tinker REPL.
---
--- Tinker is Laravel's REPL built on PsySH, with full access
--- to Eloquent models, facades, and the application container.
keys.lang_map("php", "n", "<leader>lat", function()
	run_artisan("tinker")
end, { desc = icons.ui.Terminal .. " Tinker" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers PHP-specific alignment presets for mini.align:
-- • php_array — align array entries on "=>"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("php") then
		---@type string Alignment preset icon from icons.app
		local php_align_icon = icons.app.Php

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			php_array = {
				description = "Align PHP array entries on '=>'",
				icon = php_align_icon,
				split_pattern = "=>",
				category = "scripting",
				lang = "php",
				filetypes = { "php" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("php", "php_array")
		align_registry.mark_language_loaded("php")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("php", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("php_array"), {
			desc = php_align_icon .. "  Align PHP array",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the PHP-specific
-- parts (servers, formatters, linters, parsers, DAP, Laravel tools).
--
-- Loading strategy:
-- ┌────────────────────────┬──────────────────────────────────────────┐
-- │ Plugin                 │ How it lazy-loads for PHP                │
-- ├────────────────────────┼──────────────────────────────────────────┤
-- │ nvim-lspconfig         │ opts merge (intelephense server added)  │
-- │ mason.nvim             │ opts fn (tools conditional on composer) │
-- │ conform.nvim           │ opts merge (formatters_by_ft.php)       │
-- │ nvim-lint              │ opts merge (linters_by_ft.php)          │
-- │ nvim-treesitter        │ opts merge (parsers → ensure_installed) │
-- │ mason-nvim-dap         │ opts merge (php adapter added)          │
-- │ neotest                │ opts fn (pest/phpunit adapter added)    │
-- │ laravel.nvim           │ ft + cond (artisan file check)          │
-- │ vim-blade              │ ft = "blade" (true lazy load)           │
-- └────────────────────────┴──────────────────────────────────────────┘
--
-- Conditional tooling:
-- • composer available → pint, php-cs-fixer, phpstan added to Mason
-- • composer absent    → only intelephense + php-debug-adapter
-- • vendor/bin/pest    → neotest-pest adapter
-- • vendor/bin/phpunit → neotest-phpunit adapter (fallback)
-- • artisan exists     → laravel.nvim loaded
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for PHP
return {
	-- ── LSP SERVER (intelephense) ──────────────────────────────────────────
	-- intelephense: premium PHP language server with broad framework
	-- support (Laravel, Symfony, WordPress, Drupal, etc.).
	-- Provides completions, diagnostics, refactoring, go-to-definition,
	-- hover, code actions, and workspace symbol search.
	--
	-- Settings:
	--   • maxSize = 5MB (handles large vendor files)
	--   • phpVersion = "8.3" (latest stable PHP)
	--   • fullyQualifyGlobalConstantsAndFunctions = true (explicit imports)
	--   • telemetry disabled
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				intelephense = {
					settings = {
						intelephense = {
							files = {
								maxSize = 5000000,
							},
							environment = {
								phpVersion = "8.3",
							},
							completion = {
								fullyQualifyGlobalConstantsAndFunctions = true,
							},
							telemetry = {
								enabled = false,
							},
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					php = "php",
					phps = "php",
					blade = "blade",
				},
				pattern = {
					[".*%.blade%.php"] = "blade",
				},
			})

			-- ── Buffer-local options for PHP files ───────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "php", "blade" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120
					opt.tabstop = 4
					opt.shiftwidth = 4
					opt.softtabstop = 4
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

	-- ── MASON TOOLS (conditional on composer) ──────────────────────────────
	-- Standalone tools (always installed):
	--   • intelephense       — PHP LSP server
	--   • php-debug-adapter  — DAP adapter for Xdebug
	--
	-- Composer-dependent tools (only if composer is available):
	--   • pint               — Laravel code style fixer
	--   • php-cs-fixer       — generic PHP code style fixer
	--   • phpstan            — static analysis tool
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}
			-- Always installable (standalone binaries)
			vim.list_extend(opts.ensure_installed, {
				"intelephense",
				"php-debug-adapter",
			})
			-- Require composer for installation
			if vim.fn.executable("composer") == 1 then
				vim.list_extend(opts.ensure_installed, {
					"pint",
					"php-cs-fixer",
					"phpstan",
				})
			end
		end,
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- php:   pint (Laravel style) → php_cs_fixer (fallback)
	-- blade: blade-formatter (Blade template formatter)
	--
	-- pint is Laravel's opinionated code style fixer (wraps php-cs-fixer
	-- with Laravel-specific rules). Falls through to php_cs_fixer for
	-- non-Laravel projects.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				php = { "pint", "php_cs_fixer" },
				blade = { "blade-formatter" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- phpstan: PHP static analysis tool. Catches bugs that type hints
	-- and runtime testing miss: type mismatches, dead code, incorrect
	-- return types, undefined methods/properties, etc.
	-- Configured via `phpstan.neon` in the project root.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				php = { "phpstan" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- php:    syntax highlighting, folding, text objects, indentation
	-- phpdoc: PHPDoc comment parsing (@param, @return, @var, etc.)
	-- blade:  Laravel Blade template syntax (directives, components)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"php",
				"phpdoc",
				"blade",
			},
		},
	},

	-- ── BLADE SUPPORT (Laravel templates) ──────────────────────────────────
	-- Provides Blade template syntax highlighting for files that
	-- the treesitter parser may not fully cover (older directives,
	-- custom components, etc.).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"jwalton512/vim-blade",
		ft = { "blade" },
	},

	-- ── NEOTEST (PHP adapters) ─────────────────────────────────────────────
	-- Auto-detects the test runner:
	--   • vendor/bin/pest    → neotest-pest (Pest/BDD style)
	--   • vendor/bin/phpunit → neotest-phpunit (classic xUnit)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-neotest/neotest",
		optional = true,
		dependencies = {
			"V13Axel/neotest-pest",
			"olimorris/neotest-phpunit",
		},
		opts = function(_, opts)
			opts.adapters = opts.adapters or {}
			if vim.fn.filereadable("vendor/bin/pest") == 1 then
				opts.adapters[#opts.adapters + 1] = require("neotest-pest")
			else
				opts.adapters[#opts.adapters + 1] = require("neotest-phpunit")
			end
		end,
	},

	-- ── LARAVEL.NVIM ───────────────────────────────────────────────────────
	-- Enhanced Laravel support: Artisan commands, route navigation,
	-- view resolution, and .env management.
	--
	-- Conditionally loaded: only when CWD contains `artisan` file.
	-- Zero cost outside of Laravel projects.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"adalessa/laravel.nvim",
		lazy = true,
		ft = { "php", "blade" },
		cond = function()
			return vim.fn.filereadable("artisan") == 1
		end,
		dependencies = {
			"nvim-telescope/telescope.nvim",
			"tpope/vim-dotenv",
			"MunifTanjim/nui.nvim",
		},
		opts = {},
	},

	-- ── DAP (PHP debugger) ─────────────────────────────────────────────────
	-- php-debug-adapter: VS Code PHP Debug extension for DAP.
	-- Connects to Xdebug for step debugging, breakpoints,
	-- variable inspection, and expression evaluation.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "php" },
		},
	},
}
