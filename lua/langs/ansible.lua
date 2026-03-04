---@file lua/langs/ansible.lua
---@description Ansible — Playbook execution, vault, galaxy, LSP, formatter, linter
---@module "langs.ansible"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps               Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons                 Icon provider (`lang.ansible`, `dev`, `ui`, `diagnostics`)
---@see core.mini-align-registry   Alignment preset registration for Ansible YAML
---@see langs.python               Python support (Ansible runtime dependency)
---@see langs.yaml                 YAML support (shared treesitter / formatter tooling)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/ansible.lua — Ansible automation language support                 ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("ansible") → {} if off      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Detection layers:                                               │    ║
--- ║  │  ├─ Filetype    yaml.ansible (pattern-based heuristic)           │    ║
--- ║  │  ├─ Patterns    playbooks/, roles/*/tasks/, group_vars/, etc.    │    ║
--- ║  │  ├─ Inventory   12 candidate paths (auto-detected for -i flag)   │    ║
--- ║  │  └─ Galaxy reqs requirements.yml in project root, roles/, colls/ │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = "yaml.ansible"):                 │    ║
--- ║  │  ├─ LSP         ansiblels (ansible-language-server)              │    ║
--- ║  │  ├─ Formatter   prettier (YAML formatting via conform.nvim)      │    ║
--- ║  │  ├─ Linter      ansible-lint (nvim-lint)                         │    ║
--- ║  │  └─ Treesitter  yaml · json parsers                              │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (buffer-local, <leader>l group, 15 bindings):           │    ║
--- ║  │  ├─ RUN         r  Run playbook         R  Run with extra args   │    ║
--- ║  │  │              c  Check mode (dry run)  s  Syntax check         │    ║
--- ║  │  ├─ TAGS        t  List tags             T  List tasks           │    ║
--- ║  │  ├─ VAULT       v  Encrypt               V  Decrypt              │    ║
--- ║  │  │              w  View (read-only)                              │    ║
--- ║  │  ├─ DOCS        d  ansible-doc (module)  h  Browser docs         │    ║
--- ║  │  ├─ INVENTORY   i  Inventory graph       p  Ping hosts           │    ║
--- ║  │  ├─ GALAXY      g  Galaxy actions (install, list, init)          │    ║
--- ║  │  └─ LINT        l  ansible-lint                                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Inventory auto-detection (12 candidate paths):                  │    ║
--- ║  │  ├─ inventory/ inventory/hosts inventory/hosts.{yml,yaml,ini}    │    ║
--- ║  │  ├─ inventory.{yml,yaml,ini}                                     │    ║
--- ║  │  └─ hosts hosts.{yml,yaml,ini}                                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Galaxy actions (dynamic + static):                              │    ║
--- ║  │  ├─ Dynamic: auto-detect requirements files → install actions    │    ║
--- ║  │  │  ├─ requirements.{yml,yaml}            → role install         │    ║
--- ║  │  │  ├─ collections/requirements.{yml,yaml} → collection install  │    ║
--- ║  │  │  └─ roles/requirements.{yml,yaml}       → role install        │    ║
--- ║  │  └─ Static: install/list/init roles and collections              │    ║
--- ║  │                                                                  │    ║
--- ║  │  Filetype detection patterns (9):                                │    ║
--- ║  │  ├─ playbooks/*.yml      → yaml.ansible                          │    ║
--- ║  │  ├─ roles/*/tasks/*.yml  → yaml.ansible                          │    ║
--- ║  │  ├─ roles/*/handlers/*   → yaml.ansible                          │    ║
--- ║  │  ├─ roles/*/defaults/*   → yaml.ansible                          │    ║
--- ║  │  ├─ roles/*/vars/*       → yaml.ansible                          │    ║
--- ║  │  ├─ roles/*/meta/*       → yaml.ansible                          │    ║
--- ║  │  ├─ inventory/*.yml      → yaml.ansible                          │    ║
--- ║  │  ├─ group_vars/*.yml     → yaml.ansible                          │    ║
--- ║  │  └─ host_vars/*.yml      → yaml.ansible                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Mini.align integration:                                         │    ║
--- ║  │  ├─ Preset: ansible_vars (align on ':')                          │    ║
--- ║  │  └─ <leader>aL  Align Ansible vars / task options                │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (set on FileType yaml.ansible):                          ║
--- ║  • 2 spaces, expandtab        (YAML standard indentation)                ║
--- ║  • colorcolumn=120             (Ansible style guide line length)         ║
--- ║  • conceallevel=0              (show all characters, no hiding)          ║
--- ║  • treesitter foldexpr         (foldmethod=expr, foldlevel=99)           ║
--- ║  • commentstring="# %s"       (YAML comment syntax)                      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Ansible support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("ansible") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Ansible Nerd Font icon (trailing whitespace stripped)
local ans_icon = icons.lang.ansible:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group as " Ansible" in which-key for
-- yaml.ansible buffers. All lang_map() calls below bind into this group.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("yaml.ansible", "Ansible", ans_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — EXECUTABLE GUARDS
--
-- Ansible ships multiple CLI tools (ansible-playbook, ansible-vault,
-- ansible-galaxy, ansible-inventory, ansible-doc). Each keymap must
-- verify the required tool is installed before execution.
--
-- These helpers centralize the executable check + notification pattern
-- to avoid repetition across 15+ keymap callbacks.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if an Ansible CLI tool is available on the system PATH.
---
--- If the tool is not found, displays a warning notification with
--- install instructions and returns `false`, allowing callers to
--- use a simple guard pattern:
---
--- ```lua
--- if not check_tool("ansible-playbook") then return end
--- ```
---
---@param tool string Executable name to check (e.g. `"ansible-playbook"`)
---@return boolean available `true` if the tool is found in PATH
---@private
local function check_tool(tool)
	if vim.fn.executable(tool) == 1 then return true end
	vim.notify("Install ansible: pip install ansible", vim.log.levels.WARN, { title = "Ansible" })
	return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — INVENTORY DETECTION
--
-- Ansible commands accept an optional `-i <inventory>` flag. These
-- helpers scan the project for common inventory file locations and
-- build the CLI flag automatically.
--
-- Detection scans 12 candidate paths in priority order, covering:
-- ├─ Directory-based:  inventory/, inventory/hosts
-- ├─ YAML-based:       inventory/hosts.yml, inventory.yml, hosts.yml
-- ├─ INI-based:        inventory/hosts.ini, inventory.ini, hosts.ini
-- └─ Legacy:           hosts (bare filename)
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the inventory file or directory in the current project.
---
--- Scans 12 common inventory locations relative to `cwd` in priority
--- order. Returns the first match (file or directory).
---
---@return string|nil path Absolute path to the inventory, or `nil` if not found
---@private
local function detect_inventory()
	---@type string[]
	local candidates = {
		"inventory",
		"inventory/hosts",
		"inventory/hosts.yml",
		"inventory/hosts.yaml",
		"inventory/hosts.ini",
		"inventory.yml",
		"inventory.yaml",
		"inventory.ini",
		"hosts",
		"hosts.yml",
		"hosts.yaml",
		"hosts.ini",
	}

	local cwd = vim.fn.getcwd()
	for _, f in ipairs(candidates) do
		local path = cwd .. "/" .. f
		if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then return path end
	end
	return nil
end

--- Build the `-i <inventory>` CLI flag string.
---
--- Returns the flag with a trailing space if an inventory is found,
--- or an empty string if no inventory is detected (lets Ansible use
--- its default inventory resolution).
---
--- ```lua
--- local inv = inventory_flag()
--- vim.cmd.terminal("ansible-playbook " .. inv .. file)
--- -- With inventory:    "ansible-playbook -i /path/to/inventory playbook.yml"
--- -- Without inventory: "ansible-playbook playbook.yml"
--- ```
---
---@return string flag `-i <path> ` or `""` (empty string)
---@private
local function inventory_flag()
	local inv = detect_inventory()
	if inv then return "-i " .. vim.fn.shellescape(inv) .. " " end
	return ""
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- Playbook execution commands. All commands auto-detect the inventory
-- via inventory_flag() and save the buffer before execution.
--
-- Execution modes:
-- ├─ Normal run:   ansible-playbook <file>
-- ├─ With args:    ansible-playbook <file> <user-provided args>
-- ├─ Check mode:   ansible-playbook --check --diff <file>  (dry run)
-- └─ Syntax check: ansible-playbook --syntax-check <file>  (parse only)
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current playbook.
---
--- Saves the buffer, auto-detects inventory, then executes
--- `ansible-playbook [-i inventory] <file>` in a terminal split.
keys.lang_map("yaml.ansible", "n", "<leader>lr", function()
	if not check_tool("ansible-playbook") then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local inv = inventory_flag()
	vim.cmd.split()
	vim.cmd.terminal("ansible-playbook " .. inv .. vim.fn.shellescape(file))
end, { desc = icons.ui.Play .. " Run playbook" })

--- Run the current playbook with user-provided extra arguments.
---
--- Prompts for additional CLI arguments (e.g. `--limit webservers`,
--- `--tags deploy`, `-e var=value`). Aborts silently if the user
--- cancels the prompt.
keys.lang_map("yaml.ansible", "n", "<leader>lR", function()
	if not check_tool("ansible-playbook") then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local inv = inventory_flag()
	vim.ui.input({ prompt = "Extra arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal("ansible-playbook " .. inv .. vim.fn.shellescape(file) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Run the playbook in check mode (dry run) with diff output.
---
--- Uses `--check` (simulate changes without applying) combined with
--- `--diff` (show file content changes). Essential for validating
--- playbooks before production deployment.
keys.lang_map("yaml.ansible", "n", "<leader>lc", function()
	if not check_tool("ansible-playbook") then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local inv = inventory_flag()
	vim.cmd.split()
	vim.cmd.terminal("ansible-playbook --check --diff " .. inv .. vim.fn.shellescape(file))
end, { desc = ans_icon .. " Check mode (dry run)" })

--- Syntax-check the current playbook without executing.
---
--- Uses `--syntax-check` which parses the YAML and validates task
--- structure, module names, and variable references. Faster than
--- `--check` as it doesn't connect to any hosts.
keys.lang_map("yaml.ansible", "n", "<leader>ls", function()
	if not check_tool("ansible-playbook") then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local inv = inventory_flag()
	vim.cmd.split()
	vim.cmd.terminal("ansible-playbook --syntax-check " .. inv .. vim.fn.shellescape(file))
end, { desc = ans_icon .. " Syntax check" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TAGS / TASKS
--
-- Playbook introspection: list tags and tasks without execution.
-- Useful for understanding complex playbooks and selecting specific
-- tags to run with `--tags` or `--skip-tags`.
-- ═══════════════════════════════════════════════════════════════════════════

--- List all tags defined in the current playbook.
---
--- Runs `ansible-playbook --list-tags` which outputs all available
--- tags without executing any tasks.
keys.lang_map("yaml.ansible", "n", "<leader>lt", function()
	if not check_tool("ansible-playbook") then return end
	local file = vim.fn.expand("%:p")
	local inv = inventory_flag()
	vim.cmd.split()
	vim.cmd.terminal("ansible-playbook --list-tags " .. inv .. vim.fn.shellescape(file))
end, { desc = icons.ui.List .. " List tags" })

--- List all tasks defined in the current playbook.
---
--- Runs `ansible-playbook --list-tasks` which outputs the task names
--- in execution order, including role tasks. Useful for reviewing
--- execution flow before running.
keys.lang_map("yaml.ansible", "n", "<leader>lT", function()
	if not check_tool("ansible-playbook") then return end
	local file = vim.fn.expand("%:p")
	local inv = inventory_flag()
	vim.cmd.split()
	vim.cmd.terminal("ansible-playbook --list-tasks " .. inv .. vim.fn.shellescape(file))
end, { desc = icons.ui.List .. " List tasks" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — VAULT
--
-- Ansible Vault operations for managing encrypted secrets.
-- All operations work on the current file.
--
-- Operations:
-- ├─ Encrypt: convert plaintext → encrypted (AES-256)
-- ├─ Decrypt: convert encrypted → plaintext (destructive!)
-- └─ View:    display decrypted content without modifying the file
-- ═══════════════════════════════════════════════════════════════════════════

--- Encrypt the current file with Ansible Vault.
---
--- Saves the buffer, then runs `ansible-vault encrypt` which replaces
--- the file content with AES-256 encrypted data. Prompts for a vault
--- password interactively in the terminal.
---
--- WARNING: This modifies the file in-place. The buffer will need to
--- be reloaded (`:edit`) to see the encrypted content.
keys.lang_map("yaml.ansible", "n", "<leader>lv", function()
	if not check_tool("ansible-vault") then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("ansible-vault encrypt " .. vim.fn.shellescape(file))
end, { desc = ans_icon .. " Vault encrypt" })

--- Decrypt the current file with Ansible Vault.
---
--- Saves the buffer, then runs `ansible-vault decrypt` which replaces
--- the encrypted content with plaintext. Prompts for the vault password.
---
--- WARNING: This exposes secrets in plaintext on disk. Use `vault view`
--- for read-only inspection when possible.
keys.lang_map("yaml.ansible", "n", "<leader>lV", function()
	if not check_tool("ansible-vault") then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("ansible-vault decrypt " .. vim.fn.shellescape(file))
end, { desc = ans_icon .. " Vault decrypt" })

--- View decrypted content of a vault-encrypted file (read-only).
---
--- Runs `ansible-vault view` which decrypts and displays the content
--- in the terminal without modifying the file on disk. This is the
--- safest way to inspect vault-encrypted variables.
keys.lang_map("yaml.ansible", "n", "<leader>lw", function()
	if not check_tool("ansible-vault") then return end
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("ansible-vault view " .. vim.fn.shellescape(file))
end, { desc = ans_icon .. " Vault view" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Module documentation via `ansible-doc` (offline, terminal-based)
-- and browser-based Ansible documentation access.
--
-- ansible-doc detection strategy:
-- 1. Try to match FQCN on the current line (e.g. ansible.builtin.copy)
-- 2. Fall back to the word under cursor (e.g. copy, apt, file)
-- 3. If both fail, prompt the user for a module name
-- ═══════════════════════════════════════════════════════════════════════════

--- Show `ansible-doc` for the module under cursor or on the current line.
---
--- Detection strategy:
--- 1. Scan the current line for an FQCN pattern (`namespace.collection.module`,
---    e.g. `ansible.builtin.copy`, `community.general.ufw`)
--- 2. Fall back to `<cword>` for short module names (e.g. `apt`, `copy`)
--- 3. If neither yields a result, prompt for manual input
---
--- The FQCN pattern `[%w_]+%.[%w_]+%.[%w_]+` matches the standard
--- Ansible namespace.collection.module naming convention.
keys.lang_map("yaml.ansible", "n", "<leader>ld", function()
	if not check_tool("ansible-doc") then return end

	local line = vim.api.nvim_get_current_line()

	-- ── Strategy 1: match FQCN on current line ───────────────────────
	---@type string|nil
	local module = line:match("([%w_]+%.[%w_]+%.[%w_]+)")

	-- ── Strategy 2: word under cursor (short module name) ────────────
	if not module then module = vim.fn.expand("<cword>") end

	-- ── Strategy 3: prompt for manual input ──────────────────────────
	if not module or module == "" then
		vim.ui.input({ prompt = "Module name: " }, function(input)
			if not input or input == "" then return end
			vim.cmd.split()
			vim.cmd.terminal("ansible-doc " .. vim.fn.shellescape(input))
		end)
		return
	end

	vim.cmd.split()
	vim.cmd.terminal("ansible-doc " .. vim.fn.shellescape(module))
end, { desc = icons.ui.Note .. " ansible-doc (module)" })

--- Open Ansible documentation in the default browser.
---
--- Navigates to the latest stable Ansible documentation at
--- `https://docs.ansible.com/ansible/latest/`.
keys.lang_map("yaml.ansible", "n", "<leader>lh", function()
	vim.ui.open("https://docs.ansible.com/ansible/latest/")
end, { desc = icons.ui.Note .. " Documentation (browser)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INVENTORY
--
-- Inventory inspection and host connectivity testing.
-- Both commands auto-detect the inventory file via detect_inventory().
-- ═══════════════════════════════════════════════════════════════════════════

--- Display the inventory as a tree graph.
---
--- Runs `ansible-inventory --graph` which outputs a hierarchical view
--- of all groups and hosts. Auto-appends `-i <inventory>` if an
--- inventory file is detected in the project.
keys.lang_map("yaml.ansible", "n", "<leader>li", function()
	if not check_tool("ansible-inventory") then return end
	local inv = detect_inventory()
	---@type string
	local cmd = "ansible-inventory --graph"
	if inv then cmd = cmd .. " -i " .. vim.fn.shellescape(inv) end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.List .. " Inventory graph" })

--- Ping hosts in the inventory to verify connectivity.
---
--- Prompts for a host pattern (default: `"all"`) and runs
--- `ansible <pattern> -m ping`. Uses the auto-detected inventory.
---
--- Common patterns: `all`, `webservers`, `db*`, `192.168.1.0/24`
keys.lang_map("yaml.ansible", "n", "<leader>lp", function()
	if not check_tool("ansible") then return end
	local inv = inventory_flag()
	vim.ui.input({ prompt = "Host pattern (default: all): ", default = "all" }, function(pattern)
		if not pattern or pattern == "" then return end
		vim.cmd.split()
		vim.cmd.terminal("ansible " .. vim.fn.shellescape(pattern) .. " -m ping " .. inv)
	end)
end, { desc = ans_icon .. " Ping hosts" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — GALAXY
--
-- Ansible Galaxy role and collection management.
--
-- The action list is built dynamically: first, the project is scanned
-- for requirements files (6 candidate paths), and install actions are
-- generated for each found file. Then, static always-available actions
-- are appended (install by name, list, init).
--
-- Requirements file detection:
-- ├─ requirements.{yml,yaml}             → role install
-- ├─ collections/requirements.{yml,yaml} → collection install
-- └─ roles/requirements.{yml,yaml}       → role install
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Ansible Galaxy action menu.
---
--- Builds a dynamic action list by:
--- 1. Scanning 6 candidate paths for requirements files and generating
---    contextual install commands (`-r <file>`)
--- 2. Appending 6 static actions: install/list/init for roles and collections
---
--- Actions requiring a name (install by name, init) prompt via
--- `vim.ui.input()` before execution.
keys.lang_map("yaml.ansible", "n", "<leader>lg", function()
	if not check_tool("ansible-galaxy") then return end

	---@type { name: string, cmd: string, prompt?: boolean }[]
	local actions = {}

	-- ── Dynamic: detect requirements files ────────────────────────────
	---@type { file: string, kind: string }[]
	local req_candidates = {
		{ file = "requirements.yml", kind = "role" },
		{ file = "requirements.yaml", kind = "role" },
		{ file = "collections/requirements.yml", kind = "collection" },
		{ file = "collections/requirements.yaml", kind = "collection" },
		{ file = "roles/requirements.yml", kind = "role" },
		{ file = "roles/requirements.yaml", kind = "role" },
	}

	for _, req in ipairs(req_candidates) do
		if vim.fn.filereadable(req.file) == 1 then
			if req.kind == "collection" then
				actions[#actions + 1] = {
					name = "Install collections (" .. req.file .. ")",
					cmd = "ansible-galaxy collection install -r " .. vim.fn.shellescape(req.file),
				}
			else
				actions[#actions + 1] = {
					name = "Install roles (" .. req.file .. ")",
					cmd = "ansible-galaxy install -r " .. vim.fn.shellescape(req.file),
				}
			end
		end
	end

	-- ── Static: always-available actions ──────────────────────────────
	---@type { name: string, cmd: string, prompt?: boolean }[]
	local static_actions = {
		{ name = "Install a role…", cmd = "ansible-galaxy role install", prompt = true },
		{ name = "Install a collection…", cmd = "ansible-galaxy collection install", prompt = true },
		{ name = "List installed roles", cmd = "ansible-galaxy role list" },
		{ name = "List installed collections", cmd = "ansible-galaxy collection list" },
		{ name = "Init new role…", cmd = "ansible-galaxy role init", prompt = true },
		{ name = "Init new collection…", cmd = "ansible-galaxy collection init", prompt = true },
	}

	for _, a in ipairs(static_actions) do
		actions[#actions + 1] = a
	end

	-- ── Present selection ─────────────────────────────────────────────
	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = ans_icon .. " Galaxy:" },
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
end, { desc = icons.ui.Package .. " Galaxy" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — LINT
--
-- Standalone ansible-lint execution for the current file.
-- Complements the nvim-lint integration (which runs automatically)
-- by providing a full terminal output with context.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run ansible-lint on the current file in a terminal split.
---
--- Saves the buffer before execution. Provides full-context output
--- including rule explanations, which complements the inline
--- diagnostics from the nvim-lint integration.
keys.lang_map("yaml.ansible", "n", "<leader>ll", function()
	if not check_tool("ansible-lint") then
		vim.notify("Install: pip install ansible-lint", vim.log.levels.WARN, { title = "Ansible" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("ansible-lint " .. vim.fn.shellescape(file))
end, { desc = ans_icon .. " Lint (ansible-lint)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Ansible-specific alignment presets when mini.align is
-- available. Loaded once per session (guarded by is_language_loaded).
--
-- Preset: ansible_vars — align Ansible variable definitions and task
-- options on the ':' character (YAML key-value separator).
-- Applies to both yaml.ansible and ansible filetypes.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("ansible") then
		---@type string Alignment preset icon from icons.dev
		local ansible_icon = icons.dev.Ansible

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			ansible_vars = {
				description = "Align Ansible vars / task options on ':'",
				icon = ansible_icon,
				split_pattern = ":",
				category = "devops",
				lang = "ansible",
				filetypes = { "yaml.ansible", "ansible" },
			},
		})

		-- ── Set default filetype mappings ─────────────────────────────
		-- Both "ansible" and "yaml.ansible" filetypes are mapped
		-- to the same preset for consistency.
		align_registry.set_ft_mapping("ansible", "ansible_vars")
		align_registry.set_ft_mapping("yaml.ansible", "ansible_vars")
		align_registry.mark_language_loaded("ansible")

		-- ── Alignment keymap ─────────────────────────────────────────
		keys.lang_map("ansible", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("ansible_vars"), {
			desc = ansible_icon .. "  Align Ansible vars",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Ansible-specific
-- parts (servers, formatters, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Ansible                │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (ansiblels added to servers)      │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.yaml.ansible)   │
-- │ nvim-lint          │ opts merge (linters_by_ft.yaml.ansible)      │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed)│
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Ansible
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────
	-- ansiblels: Ansible Language Server providing completions for
	-- module names, module options, Jinja2 filters, and role/collection
	-- references. Includes built-in ansible-lint integration.
	--
	-- Key settings:
	-- • useFullyQualifiedCollectionNames: enforce FQCN for all modules
	-- • validation.lint.enabled: run ansible-lint through the LSP
	-- • completion.provideRedirectModules: suggest module redirects
	-- ────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				ansiblels = {
					settings = {
						ansible = {
							ansible = {
								useFullyQualifiedCollectionNames = true,
							},
							validation = {
								enabled = true,
								lint = {
									enabled = true,
									path = "ansible-lint",
								},
							},
							python = {
								interpreterPath = "python3",
							},
							completion = {
								provideRedirectModules = true,
								provideModuleOptionAliases = true,
							},
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype detection ──────────────────────────────────
			-- Ansible YAML files use the compound filetype "yaml.ansible"
			-- which inherits YAML treesitter/indent support while enabling
			-- Ansible-specific LSP and linting.
			--
			-- Pattern matching covers the standard Ansible project layout:
			-- playbooks/, roles/*/tasks|handlers|defaults|vars|meta/,
			-- inventory/, group_vars/, host_vars/
			vim.filetype.add({
				pattern = {
					[".*/playbooks?/.+%.ya?ml"] = "yaml.ansible",
					[".*/roles/.+/tasks/.+%.ya?ml"] = "yaml.ansible",
					[".*/roles/.+/handlers/.+%.ya?ml"] = "yaml.ansible",
					[".*/roles/.+/defaults/.+%.ya?ml"] = "yaml.ansible",
					[".*/roles/.+/vars/.+%.ya?ml"] = "yaml.ansible",
					[".*/roles/.+/meta/.+%.ya?ml"] = "yaml.ansible",
					[".*/inventory/.+%.ya?ml"] = "yaml.ansible",
					[".*/group_vars/.+%.ya?ml"] = "yaml.ansible",
					[".*/host_vars/.+%.ya?ml"] = "yaml.ansible",
				},
				filename = {
					["ansible.cfg"] = "ini",
				},
			})

			-- ── Buffer-local options for Ansible YAML files ──────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "yaml.ansible" },
				callback = function()
					local opt = vim.opt_local

					-- ── Layout ────────────────────────────────────────
					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120
					opt.conceallevel = 0

					-- ── Indentation (YAML standard: 2 spaces) ────────
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
				desc = "NvimEnterprise: Ansible YAML buffer options",
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────
	-- Ensures Ansible Language Server, ansible-lint, and Prettier are
	-- installed and managed by Mason.
	-- ────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"ansible-language-server",
				"ansible-lint",
				"prettier",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────
	-- Prettier for Ansible YAML files. Prettier auto-detects YAML syntax
	-- and handles Jinja2 template strings within YAML values.
	-- ────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				["yaml.ansible"] = { "prettier" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────
	-- ansible-lint via nvim-lint for inline diagnostics.
	-- Complements the LSP's built-in lint integration with additional
	-- rules and configurable profiles (.ansible-lint config file).
	--
	-- NOTE: Uses "ansible_lint" (underscore) as the linter name per
	-- nvim-lint's naming convention.
	-- ────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				["yaml.ansible"] = { "ansible_lint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────
	-- yaml: syntax highlighting, folding, indentation for Ansible files
	-- json: ansible-lint config (.ansible-lint.json), Galaxy metadata
	--       (galaxy.yml → JSON schema), inventory plugins
	-- ────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"yaml",
				"json",
			},
		},
	},
}
