---@file lua/config/commands.lua
---@description Commands — global utility commands for NvimEnterprise
---@module "config.commands"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see config.settings_manager User management commands (registered separately)
---@see config.colorscheme_manager Colorscheme commands (registered separately)
---@see config.extras_browser LazyVim extras browser UI
---@see core.settings Settings provider (all configuration reads)
---@see core.icons Icon provider (command descriptions, notifications)
---@see core.platform Platform detection (OS, arch, SSH, WSL, Docker, GUI)
---@see core.utils File I/O, string helpers, table utilities
---@see core.keymaps Keymap registry (audit, check_health)
---@see core.logger Structured logging (log file path)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  config/commands.lua — Advanced NvimEnterprise commands                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Commands Module (M.setup() called by config/init.lua)           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Information Commands:                                           │    ║
--- ║  │  ├─ :NvimInfo          Configuration summary (platform, UI, AI)  │    ║
--- ║  │  ├─ :NvimHealth        Run :checkhealth nvimenterprise           │    ║
--- ║  │  ├─ :NvimVersion       Version info (Neovim, Lua, config)        │    ║
--- ║  │  ├─ :NvimPerf          Startup performance (lazy.nvim stats)     │    ║
--- ║  │  ├─ :NvimLanguages     Enabled vs available languages            │    ║
--- ║  │  ├─ :NvimPlugins       Open lazy.nvim UI                         │    ║
--- ║  │  ├─ :NvimLspInfo       LSP & Mason info (floating window)        │    ║
--- ║  │  └─ :NvimCommands      Complete command reference (floating)     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Utility Commands:                                               │    ║
--- ║  │  ├─ :NvimRestart       Hot-restart Neovim (re-exec)              │    ║
--- ║  │  ├─ :NvimLogView       Open log file in buffer                   │    ║
--- ║  │  ├─ :NvimLogClear      Truncate log file                         │    ║
--- ║  │  └─ :NvimEditConfig    Open config dir in neo-tree               │    ║
--- ║  │                                                                  │    ║
--- ║  │  LazyVim Extras:                                                 │    ║
--- ║  │  └─ :NvimExtras        Browse & toggle extras (priority-sorted)  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Git Protocol:                                                   │    ║
--- ║  │  ├─ :NvimGitProtocol   Show/switch git protocol (https/ssh)      │    ║
--- ║  │  └─ :NvimGitConvert    Convert all plugin remotes to protocol    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymap Audit:                                                   │    ║
--- ║  │  ├─ :NvimAuditKeymaps  Audit all registered keymaps              │    ║
--- ║  │  ├─ :NvimKeymapsConflicts  Check keymap prefix conflicts         │    ║
--- ║  │  └─ :ListAllKeymaps    Show all keymaps (floating table)         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Deferred Registration:                                          │    ║
--- ║  │  └─ Colorscheme commands registered on VeryLazy event            │    ║
--- ║  │     (requires lazy.nvim to know all colorscheme plugins)         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Registered Elsewhere:                                           │    ║
--- ║  │  ├─ User commands → config/settings_manager.lua                  │    ║
--- ║  │  └─ Colorscheme commands → config/colorscheme_manager.lua        │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • All commands registered once in M.setup() (called by config/init)     ║
--- ║  • Floating windows use per-buffer keymaps (q/Esc to close)              ║
--- ║  • Colorscheme commands deferred to VeryLazy (needs plugin registry)     ║
--- ║  • Git convert skips protected plugins (lazy.nvim itself)                ║
--- ║  • NvimLspInfo groups Mason packages by category for readability         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local icons = require("core.icons")
local utils = require("core.utils")
local platform = require("core.platform")

---@class CommandsModule
local M = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Apply a highlight to a line range in a buffer.
---
--- Replacement for the deprecated `vim.api.nvim_buf_add_highlight()`.
--- Uses extmarks which are the recommended API since Neovim 0.11.
---@param buf integer Buffer handle
---@param ns integer Namespace id
---@param hl_group string Highlight group name
---@param line integer 0-indexed line number
---@param col_start integer Start column (0-indexed)
---@param col_end integer End column (-1 for end of line)
---@return nil
---@private
local function buf_add_hl(buf, ns, hl_group, line, col_start, col_end)
	local end_col = col_end
	if end_col == -1 then
		local buf_line = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1]
		end_col = buf_line and #buf_line or 0
	end
	vim.api.nvim_buf_set_extmark(buf, ns, line, col_start, {
		end_col = end_col,
		hl_group = hl_group,
	})
end

--- Create a floating window with the given lines and close keymaps.
---
--- Used by :NvimCommands, :NvimLspInfo, :ListAllKeymaps to display
--- read-only information in a centered floating window.
---@param lines string[] Lines to display
---@param opts table Options: width, height, title, filetype, border
---@return integer buf Buffer handle
---@return integer win Window handle
---@private
local function create_info_float(lines, opts)
	opts = opts or {}
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = opts.filetype or "nviminfo"

	local width = opts.width or 80
	local height = opts.height or math.min(#lines, math.floor(vim.o.lines * 0.85))
	local ui_info = vim.api.nvim_list_uis()[1]

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((ui_info.width - width) / 2),
		row = math.floor((ui_info.height - height) / 2),
		style = "minimal",
		border = opts.border or "rounded",
		title = opts.title,
		title_pos = opts.title and "center" or nil,
	})

	vim.wo[win].winblend = 0
	vim.wo[win].cursorline = true

	-- Close keymaps
	local close = function()
		if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
	end
	vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })

	return buf, win
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SETUP
--
-- Registers all NvimEnterprise commands. Called once by config/init.lua
-- after lazy.setup() completes. Each command is documented with its
-- purpose and usage in the command description.
-- ═══════════════════════════════════════════════════════════════════════════

--- Register all NvimEnterprise global commands.
---@return nil
function M.setup()
	local settings = require("core.settings")

	-- ═══════════════════════════════════════════════════════════════════
	-- INFORMATION COMMANDS
	-- ═══════════════════════════════════════════════════════════════════

	-- ── :NvimInfo ────────────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimInfo", function()
		local lines = {}

		--- Add a formatted info line.
		---@param icon string Icon prefix
		---@param label string Label (left-aligned)
		---@param value string Value (right side)
		local function add(icon, label, value)
			table.insert(lines, string.format("  %s %-20s %s", icon, label, value))
		end

		table.insert(lines, "")
		table.insert(lines, "  " .. icons.misc.Neovim .. " NvimEnterprise v" .. _G.NvimConfig.version)
		table.insert(lines, string.rep("─", 55))

		-- ── Platform ─────────────────────────────────────────────────
		add(icons.ui.Gear, "OS:", platform.os .. " (" .. platform.arch .. ")")
		local envs = {}
		if platform.is_ssh then table.insert(envs, "SSH") end
		if platform.is_wsl then table.insert(envs, "WSL") end
		if platform.is_docker then table.insert(envs, "Docker") end
		if platform.is_proxmox then table.insert(envs, "Proxmox") end
		if platform.is_gui then table.insert(envs, "GUI") end
		--stylua: ignore start
		add(icons.ui.Terminal, "Environment:", #envs > 0 and table.concat(envs, ", ") or "Local")
		add(icons.ui.Folder, "Config:", platform.config_dir)
		add(icons.ui.Lock, "Git protocol:", settings:get("performance.git_protocol", "https"):upper())
		add(icons.ui.Gear, "OS:", platform:get_os_icon() .. " " .. platform.os:upper())
		add(icons.ui.Terminal, "Multiplexer:", platform.is_tmux and "Tmux" or (platform.is_zellij and "Zellij" or "None"))
		--stylua: ignore end

		-- ── User ─────────────────────────────────────────────────────
		table.insert(lines, "")
		add(icons.ui.User, "Active user:", settings:get("active_user", "default"))

		-- ── UI ───────────────────────────────────────────────────────
		local cs = settings:get("ui.colorscheme", "habamax")
		local cs_style = settings:get("ui.colorscheme_style", "")
		add("", "Colorscheme:", cs .. (cs_style ~= "" and (" (" .. cs_style .. ")") or ""))

		-- ── Languages ────────────────────────────────────────────────
		table.insert(lines, "")
		local langs = settings:get("languages.enabled", {})
		add(icons.misc.Treesitter, "Languages:", #langs .. " enabled")
		if #langs > 0 then
			local lang_str = table.concat(langs, ", ")
			if #lang_str > 45 then
				local half = math.ceil(#langs / 2)
				table.insert(lines, "    " .. table.concat(vim.list_slice(langs, 1, half), ", "))
				table.insert(lines, "    " .. table.concat(vim.list_slice(langs, half + 1), ", "))
			else
				table.insert(lines, "    " .. lang_str)
			end
		end

		-- ── LazyVim Extras ───────────────────────────────────────────
		table.insert(lines, "")
		local extras_enabled = settings:get("lazyvim_extras.enabled", false)
		local extras_list = settings:get("lazyvim_extras.extras", {})
		local lazyvim_extras_raw = settings:get("lazyvim_extras", {})
		for _, id in ipairs(lazyvim_extras_raw) do
			if type(id) == "string" then
				local found = false
				for _, existing in ipairs(extras_list) do
					if existing == id then
						found = true
						break
					end
				end
				if not found then table.insert(extras_list, id) end
			end
		end

		if extras_enabled and #extras_list > 0 then
			add(icons.misc.Lazy, "LazyVim Extras:", string.format("%d enabled (priority-sorted)", #extras_list))
			local short_names = {}
			for _, id in ipairs(extras_list) do
				local short = id:match("lazyvim%.plugins%.extras%.(.+)") or id
				table.insert(short_names, short)
			end
			local current_line = "    "
			for i, extra_name in ipairs(short_names) do
				local separator = (i < #short_names) and ", " or ""
				if #current_line + #extra_name + #separator > 58 then
					table.insert(lines, current_line)
					current_line = "    " .. extra_name .. separator
				else
					current_line = current_line .. extra_name .. separator
				end
			end
			if #current_line > 4 then table.insert(lines, current_line) end
		else
			add(icons.misc.Lazy, "LazyVim Extras:", "none enabled")
		end

		-- ── AI ────────────────────────────────────────────────────────
		table.insert(lines, "")
		if settings:get("ai.enabled", false) then
			add(icons.misc.AI, "AI:", "enabled (" .. settings:get("ai.provider", "none") .. ")")
			add("", "Continue:", settings:get("ai.continue_completion", false) and "yes" or "no")
		else
			add(icons.misc.AI, "AI:", "disabled")
		end

		-- ── Performance ──────────────────────────────────────────────
		table.insert(lines, "")
		local lazy_ok, lazy = pcall(require, "lazy")
		if lazy_ok then
			local stats = lazy.stats()
			add(icons.misc.Lazy, "Plugins:", string.format("%d total, %d loaded", stats.count, stats.loaded))
			add(icons.ui.Rocket, "Startup:", string.format("%.2fms", stats.startuptime))
		end

		-- ── Neovim ───────────────────────────────────────────────────
		table.insert(lines, "")
		local v = vim.version()
		add(icons.misc.Neovim, "Neovim:", string.format("v%d.%d.%d", v.major, v.minor, v.patch))
		add("", "Lua:", jit and jit.version or _VERSION)
		table.insert(lines, "")

		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = icons.misc.Neovim .. " NvimEnterprise Info" })
	end, {
		nargs = 0,
		desc = icons.misc.Neovim .. " Show configuration summary",
	})

	-- ── :NvimHealth ──────────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimHealth", function()
		vim.cmd("checkhealth nvimenterprise")
	end, {
		nargs = 0,
		desc = icons.diagnostics.Info .. " Run NvimEnterprise health check",
	})

	-- ── :NvimVersion ─────────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimVersion", function()
		local v = vim.version()
		vim.notify(
			string.format(
				"%s NvimEnterprise v%s\n%s Neovim v%d.%d.%d\n%s Lua: %s",
				icons.misc.Neovim,
				_G.NvimConfig.version,
				icons.misc.Vim,
				v.major,
				v.minor,
				v.patch,
				icons.ui.Code,
				jit and jit.version or _VERSION
			),
			vim.log.levels.INFO,
			{ title = "Version" }
		)
	end, {
		nargs = 0,
		desc = "Show NvimEnterprise version",
	})

	-- ── :NvimPerf ────────────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimPerf", function()
		local lazy_ok, lazy = pcall(require, "lazy")
		if not lazy_ok then
			vim.notify("lazy.nvim not loaded", vim.log.levels.WARN)
			return
		end

		local stats = lazy.stats()
		local lines = {
			string.format("%s Startup Performance", icons.ui.Rocket),
			string.rep("─", 40),
			string.format("  Total startup: %.2fms", stats.startuptime),
			string.format("  Plugins total: %d", stats.count),
			string.format("  Plugins loaded: %d (%.0f%%)", stats.loaded, (stats.loaded / stats.count) * 100),
			string.format("  Plugins lazy: %d", stats.count - stats.loaded),
			"",
			"  Run :Lazy profile for detailed breakdown",
			"  Run :StartupTime for full profiling",
		}

		vim.notify(
			table.concat(lines, "\n"),
			vim.log.levels.INFO,
			{ title = icons.ui.Rocket .. " NvimEnterprise Performance" }
		)
	end, {
		nargs = 0,
		desc = icons.ui.Rocket .. " Show startup performance",
	})

	-- ── :NvimLanguages ───────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimLanguages", function()
		local raw = settings:get("languages.enabled", {})
		local enabled = {}
		if type(raw) == "table" then enabled = raw end

		local langs_dir = platform:path_join(platform.config_dir, "lua", "langs")
		local all_langs = {}
		if utils.dir_exists(langs_dir) then
			local glob = vim.fn.globpath(langs_dir, "*.lua", false, true)
			for _, filepath in ipairs(glob) do
				local filename = vim.fn.fnamemodify(filepath, ":t")
				if filename ~= "init.lua" and filename ~= "_template.lua" then
					local lang_name = filename:gsub("%.lua$", "")
					all_langs[#all_langs + 1] = lang_name
				end
			end
		end
		table.sort(all_langs)

		local enabled_count = #enabled
		local total_count = #all_langs

		local lines = { "Languages:", "" }
		for _, lang in ipairs(all_langs) do
			local is_enabled = utils.tbl_contains(enabled, lang)
			local marker = is_enabled and (icons.ui.Check .. " ") or "   "
			lines[#lines + 1] = marker .. lang
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = string.format("%d/%d enabled", enabled_count, total_count)

		vim.notify(
			table.concat(lines, "\n"),
			vim.log.levels.INFO,
			{ title = icons.misc.Treesitter .. " NvimEnterprise Languages" }
		)
	end, {
		nargs = 0,
		desc = icons.misc.Treesitter .. " Show language status",
	})

	-- ── :NvimPlugins ─────────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimPlugins", function()
		local lazy_ok = pcall(require, "lazy")
		if lazy_ok then
			vim.cmd("Lazy")
		else
			vim.notify("lazy.nvim not loaded", vim.log.levels.WARN)
		end
	end, {
		nargs = 0,
		desc = icons.misc.Lazy .. " Open plugin manager",
	})

	-- ── :NvimLspInfo ─────────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimLspInfo", function()
		local lines = {}

		table.insert(
			lines,
			"  ══════════════════════════════════════════════"
		)
		table.insert(lines, "   " .. icons.misc.Lsp .. " LSP & Mason Info")
		table.insert(
			lines,
			"  ══════════════════════════════════════════════"
		)
		table.insert(lines, "")

		-- ── Active LSP clients ───────────────────────────────────────
		local clients = vim.lsp.get_clients()
		if #clients > 0 then
			table.insert(lines, "  " .. icons.ui.Play .. " Active LSP Clients (" .. #clients .. ")")
			table.insert(lines, "")
			local seen = {}
			for _, client in ipairs(clients) do
				if not seen[client.name] then
					seen[client.name] = true
					local bufs = vim.lsp.get_buffers_by_client_id(client.id) or {}
					table.insert(
						lines,
						"    " .. icons.ui.Check .. " " .. client.name .. "  (id: " .. client.id .. ", bufs: " .. #bufs .. ")"
					)
				end
			end
		else
			table.insert(lines, "  " .. icons.diagnostics.Info .. " No active LSP clients")
			table.insert(lines, "    Open a file to start LSP servers")
		end
		table.insert(lines, "")

		-- ── Mason installed packages ─────────────────────────────────
		local mason_ok, mason_reg = pcall(require, "mason-registry")
		if mason_ok then
			local installed = mason_reg.get_installed_packages()
			table.insert(lines, "  " .. icons.misc.Mason .. " Mason Packages (" .. #installed .. ")")
			table.insert(lines, "")

			-- Group by category
			local categories = {}
			for _, pkg in ipairs(installed) do
				local cats = pkg.spec.categories or { "other" }
				local cat = cats[1] or "other"
				if not categories[cat] then categories[cat] = {} end
				table.insert(categories[cat], pkg.name)
			end

			local cat_names = vim.tbl_keys(categories)
			table.sort(cat_names)

			local cat_icons = {
				["LSP"] = icons.ui.Check,
				["Formatter"] = icons.ui.Pencil,
				["Linter"] = icons.diagnostics.Warn,
				["DAP"] = icons.ui.Bug,
			}

			for _, cat in ipairs(cat_names) do
				local names = categories[cat]
				table.sort(names)
				local ci = cat_icons[cat] or icons.ui.Circle
				table.insert(lines, "    " .. cat .. ":")
				for _, pkg_name in ipairs(names) do
					table.insert(lines, "      " .. ci .. " " .. pkg_name)
				end
				table.insert(lines, "")
			end
		else
			table.insert(lines, "  " .. icons.diagnostics.Warn .. " Mason not available")
			table.insert(lines, "")
		end

		-- ── Configured LSP servers ───────────────────────────────────
		local lspconfig_ok, lspconfig = pcall(require, "lspconfig")
		if lspconfig_ok then
			local available_servers = lspconfig.util.available_servers()
			if #available_servers > 0 then
				table.insert(lines, "  " .. icons.misc.Lsp .. " Configured Servers (" .. #available_servers .. ")")
				table.insert(lines, "")
				table.sort(available_servers)
				for _, server_name in ipairs(available_servers) do
					local active = false
					for _, client in ipairs(clients) do
						if client.name == server_name then
							active = true
							break
						end
					end
					local status = active and (icons.ui.Check .. " ") or (icons.ui.Circle .. " ")
					table.insert(lines, "    " .. status .. server_name)
				end
				table.insert(lines, "")
			end
		end

		-- ── Neovim LSP log ───────────────────────────────────────────
		table.insert(lines, "  " .. icons.misc.Vim .. " Neovim LSP")
		table.insert(lines, "")
		table.insert(lines, "    Log: " .. vim.lsp.get_log_path())
		table.insert(lines, "")
		table.insert(
			lines,
			"  ──────────────────────────────────────────────"
		)
		table.insert(lines, "  Press q or <Esc> to close")

		-- ── Create floating window ───────────────────────────────────
		local buf = create_info_float(lines, {
			width = 56,
			filetype = "NvimLspInfo",
			border = settings:get("ui.float_border", "rounded"),
			title = " " .. icons.misc.Lsp .. " LSP Info ",
		})

		-- ── Highlights ───────────────────────────────────────────────
		local ns = vim.api.nvim_create_namespace("nvim_lsp_info")
		for i, line in ipairs(lines) do
			if line:match("══") or line:match("──") then
				buf_add_hl(buf, ns, "FloatBorder", i - 1, 0, -1)
			elseif line:match("LSP & Mason") then
				buf_add_hl(buf, ns, "Title", i - 1, 0, -1)
			elseif
				line:match("Active LSP")
				or line:match("Mason Packages")
				or line:match("Configured Servers")
				or line:match("Neovim LSP")
			then
				buf_add_hl(buf, ns, "Special", i - 1, 0, -1)
			elseif line:match(icons.ui.Check) then
				buf_add_hl(buf, ns, "DiagnosticOk", i - 1, 0, -1)
			elseif line:match("No active") or line:match("Open a file") or line:match("not available") then
				buf_add_hl(buf, ns, "DiagnosticWarn", i - 1, 0, -1)
			elseif line:match("Press q") or line:match("Log:") then
				buf_add_hl(buf, ns, "Comment", i - 1, 0, -1)
			elseif line:match("^%s+%u%a+:$") then
				buf_add_hl(buf, ns, "Function", i - 1, 0, -1)
			end
		end
	end, {
		nargs = 0,
		desc = icons.misc.Lsp .. " Show LSP & Mason info",
	})

	-- ── :NvimCommands ────────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimCommands", function()
		local lines = {
			" " .. icons.misc.Neovim .. " Nvim Enterprise — All Commands",
			"",
			" ── User Management ──────────────────────────────────────────────────────────",
			"  :UserCreate [name] [profile]      Create user (profiles: minimal, developer,",
			"                                    writer, devops, presenter)",
			"  :UserSwitch [name]                Hot-swap active user (with metadata)",
			"  :UserDelete <name>                Delete a user namespace",
			"  :UserClone <source> <target>      Clone a namespace to a new one",
			"  :UserList                         List all user namespaces",
			"  :UserEdit [name]                  Edit user settings",
			"  :UserInfo [name]                  Show detailed user info (metadata, size)",
			"",
			" ── User Advanced ────────────────────────────────────────────────────────────",
			"  :UserExport [name] [path]         Export namespace to JSON file",
			"  :UserImport <file> [name]         Import namespace from JSON file",
			"  :UserDiff [a] [b]                 Compare settings between two users",
			"  :UserLock [name]                  Protect namespace against deletion",
			"  :UserUnlock [name]                Remove deletion protection",
			"  :UserHealth [name]                Check namespace integrity",
			"  :UserStats                        Show global user statistics",
			"  :UserProfiles                     List available profiles",
			"",
			" ── Auto-Switch ──────────────────────────────────────────────────────────────",
			"  .nvimuser                         Place in project root with a username",
			"                                    to auto-switch on directory change",
			"",
			" ── Configuration ────────────────────────────────────────────────────────────",
			"  :Settings                         Open root settings.lua",
			"  :SettingsReload                   Reload settings from disk",
			"",
			" ── Colorscheme ──────────────────────────────────────────────────────────────",
			"  :ColorschemeSwitch                Interactive multi-step picker",
			"  :ColorschemeSet <name> [opts]     Direct: name [style] [bg] [variant]",
			"  :ColorschemeList                  Show all with variants + active marker",
			"",
			"  Examples:",
			"    :ColorschemeSet catppuccin mocha",
			"    :ColorschemeSet tokyonight storm",
			"    :ColorschemeSet gruvbox-material soft dark material",
			"    :ColorschemeSet everforest medium dark",
			"    :ColorschemeSet nightfox carbonfox",
			"    :ColorschemeSet github-theme dark_dimmed",
			"",
			" ── Information ──────────────────────────────────────────────────────────────",
			"  :NvimInfo                         Show configuration summary",
			"  :NvimHealth                       Run health check",
			"  :NvimVersion                      Show version info",
			"  :NvimPerf                         Show startup performance",
			"  :NvimLanguages                    Show language status",
			"  :NvimPlugins                      Open plugin manager (Lazy)",
			"  :NvimLspInfo                      Show LSP & Mason info",
			"  :NvimCommands                     Show this command list",
			"",
			" ── Utilities ────────────────────────────────────────────────────────────────",
			"  :NvimRestart                      Restart Neovim",
			"  :NvimLogView                      View log file",
			"  :NvimLogClear                     Clear log file",
			"  :NvimEditConfig                   Browse config in file explorer",
			"",
			" ── LazyVim Extras ───────────────────────────────────────────────────────────",
			"  :NvimExtras                       Browse & toggle LazyVim extras",
			"                                    (auto priority-sorted on save)",
			"",
			" ── Git Protocol ─────────────────────────────────────────────────────────────",
			"  :NvimGitProtocol                  Show current Git protocol",
			"  :NvimGitProtocol <ssh|https>      Switch Git protocol for new clones",
			"  :NvimGitConvert                   Convert all existing plugins to protocol",
			"",
			" ── Keymap Audit ─────────────────────────────────────────────────────────────",
			"  :NvimAuditKeymaps                 Audit all registered keymaps",
			"  :NvimKeymapsConflicts             Check keymap prefix conflicts",
			"  :ListAllKeymaps                   Show all keymaps in floating table",
			"",
			" ── Plugin Commands ──────────────────────────────────────────────────────────",
			"  :Lazy                             Plugin manager (lazy.nvim)",
			"  :Mason                            LSP/formatter/linter installer",
			"  :Lint                             Trigger linting for current file",
			"  :ConformInfo                      Show formatter info",
			"  :TSInstallInfo                    Show treesitter parser status",
			"",
			" ── Key Shortcuts ────────────────────────────────────────────────────────────",
			"  <leader>sk                        Search all keymaps",
			"  <leader>sC                        Search all commands",
			"  <leader>uC                        Colorscheme picker",
			"  <leader>gg                        Lazygit",
			"  <leader>e                         File explorer (Neo-tree)",
			"  <leader>ff                        Find files",
			"  <leader>/                         Grep search",
			"  <leader>lx                        LazyVim extras browser",
			"",
			" Press q or <Esc> to close",
		}

		local buf = create_info_float(lines, {
			width = 80,
			filetype = "nvimcommands",
			border = settings:get("ui.float_border", "rounded"),
			title = " " .. icons.misc.Neovim .. " Commands ",
		})

		-- ── Highlights ───────────────────────────────────────────────
		local ns = vim.api.nvim_create_namespace("nvim_commands")
		for i, line in ipairs(lines) do
			if line:match("^%s*──") then
				buf_add_hl(buf, ns, "Title", i - 1, 0, -1)
			elseif line:match("NvimEnterprise") or line:match("Nvim Enterprise") then
				buf_add_hl(buf, ns, "Special", i - 1, 0, -1)
			elseif line:match("^%s+:") then
				local cmd_end = line:find("%s%s") or #line
				buf_add_hl(buf, ns, "Function", i - 1, 0, cmd_end)
			elseif line:match("^%s+<") then
				local key_end = line:find("%s%s") or #line
				buf_add_hl(buf, ns, "Keyword", i - 1, 0, key_end)
			elseif line:match("auto priority") or line:match("auto%-switch") or line:match("%.nvimuser") then
				buf_add_hl(buf, ns, "DiagnosticHint", i - 1, 0, -1)
			elseif line:match("Press") then
				buf_add_hl(buf, ns, "Comment", i - 1, 0, -1)
			end
		end
	end, {
		nargs = 0,
		desc = icons.ui.List .. " Show all NvimEnterprise commands",
	})

	-- ═══════════════════════════════════════════════════════════════════
	-- UTILITY COMMANDS
	-- ═══════════════════════════════════════════════════════════════════

	-- ── :NvimRestart ─────────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimRestart", function()
		vim.cmd("silent! wall")
		vim.notify(icons.ui.Rocket .. " Restarting Neovim...", vim.log.levels.INFO, { title = "NvimEnterprise" })
		vim.defer_fn(function()
			local args = vim.v.argv
			vim.fn.jobstart(args, { detach = true })
			vim.cmd("qa!")
		end, 200)
	end, {
		nargs = 0,
		desc = icons.ui.Rocket .. " Hot-restart Neovim",
	})

	-- ── :NvimLogView ─────────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimLogView", function()
		local log_path = vim.fn.stdpath("state") .. "/nvimenterprise.log"
		if utils.file_exists(log_path) then
			vim.cmd("edit " .. log_path)
		else
			vim.notify("No log file found", vim.log.levels.INFO, { title = "NvimEnterprise" })
		end
	end, {
		nargs = 0,
		desc = icons.ui.File .. " View NvimEnterprise log file",
	})

	-- ── :NvimLogClear ────────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimLogClear", function()
		local log_path = vim.fn.stdpath("state") .. "/nvimenterprise.log"
		if utils.file_exists(log_path) then
			utils.write_file(log_path, "")
			vim.notify(icons.ui.Check .. " Log file cleared", vim.log.levels.INFO, { title = "NvimEnterprise" })
		else
			vim.notify("No log file to clear", vim.log.levels.INFO, { title = "NvimEnterprise" })
		end
	end, {
		nargs = 0,
		desc = icons.ui.BoldClose .. " Clear NvimEnterprise log file",
	})

	-- ── :NvimEditConfig ──────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimEditConfig", function()
		vim.cmd("cd " .. platform.config_dir)
		vim.cmd("Neotree reveal " .. platform.config_dir)
	end, {
		nargs = 0,
		desc = icons.ui.Gear .. " Open NvimEnterprise config in file explorer",
	})

	-- ═══════════════════════════════════════════════════════════════════
	-- LAZYVIM EXTRAS
	-- ═══════════════════════════════════════════════════════════════════

	-- ── :NvimExtras ──────────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimExtras", function()
		local browser = require("config.extras_browser")
		browser:show()
	end, {
		nargs = 0,
		desc = icons.misc.Lazy .. " Browse & toggle LazyVim extras (priority-sorted)",
	})

	-- ═══════════════════════════════════════════════════════════════════
	-- GIT PROTOCOL
	-- ═══════════════════════════════════════════════════════════════════

	-- ── :NvimGitProtocol ─────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimGitProtocol", function(cmd)
		local arg = utils.trim(cmd.args):lower()
		local current = settings:get("performance.git_protocol", "https")

		-- Show current protocol if no arg
		if arg == "" then
			vim.notify(
				string.format("%s Git protocol: %s\n\nUsage: :NvimGitProtocol <https|ssh>", icons.ui.Lock, current:upper()),
				vim.log.levels.INFO,
				{ title = "NvimEnterprise" }
			)
			return
		end

		-- Validate arg
		if arg ~= "https" and arg ~= "ssh" then
			vim.notify(
				"Invalid protocol. Use: :NvimGitProtocol <https|ssh>",
				vim.log.levels.ERROR,
				{ title = "NvimEnterprise" }
			)
			return
		end

		if arg == current then
			vim.notify(string.format("Already using %s", arg:upper()), vim.log.levels.INFO, { title = "NvimEnterprise" })
			return
		end

		-- Update settings.lua on disk
		local path = platform:path_join(platform.config_dir, "settings.lua")
		local content, read_err = utils.read_file(path)
		if not content then
			vim.notify("Cannot read settings.lua: " .. (read_err or ""), vim.log.levels.ERROR)
			return
		end

		local new_content, count = content:gsub('(git_protocol%s*=%s*)"[^"]*"', '%1"' .. arg .. '"')

		if count == 0 then
			vim.notify(
				"Could not find 'git_protocol' in settings.lua.\nAdd it manually under performance = { ... }",
				vim.log.levels.WARN,
				{ title = "NvimEnterprise" }
			)
			return
		end

		local write_ok, write_err = utils.write_file(path, new_content)
		if not write_ok then
			vim.notify("Cannot write settings.lua: " .. (write_err or ""), vim.log.levels.ERROR)
			return
		end

		-- Update in-memory settings
		settings:all().performance.git_protocol = arg

		vim.notify(
			string.format(
				"%s Git protocol switched to %s\n\n"
					.. "  %s New plugin clones will use %s\n"
					.. "  %s Existing plugins keep their current remote\n"
					.. "  %s To convert existing: :NvimGitConvert",
				icons.ui.Check,
				arg:upper(),
				icons.ui.Check,
				arg:upper(),
				icons.ui.Fire,
				icons.ui.Rocket
			),
			vim.log.levels.INFO,
			{ title = "NvimEnterprise — Git Protocol" }
		)
	end, {
		nargs = "?",
		desc = icons.ui.Lock .. " Show or switch git protocol (https/ssh)",
		complete = function()
			return { "https", "ssh" }
		end,
	})

	-- ── :NvimGitConvert ──────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimGitConvert", function()
		local protocol = settings:get("performance.git_protocol", "https")
		local lazy_dir = vim.fn.stdpath("data") .. "/lazy"

		if not utils.dir_exists(lazy_dir) then
			vim.notify("Lazy directory not found", vim.log.levels.ERROR)
			return
		end

		--- Plugins that should NEVER have their remote converted.
		--- lazy.nvim manages its own git state.
		---@type table<string, boolean>
		local skip_plugins = {
			["lazy.nvim"] = true,
		}

		local dirs = utils.list_dir(lazy_dir, "directory")
		local converted = 0
		local skipped = 0
		local convert_errors = 0

		for _, dir in ipairs(dirs) do
			if skip_plugins[dir] then
				skipped = skipped + 1
				goto continue
			end

			local repo_path = platform:path_join(lazy_dir, dir)
			local git_dir = platform:path_join(repo_path, ".git")

			if utils.dir_exists(git_dir) then
				local result = vim.fn.system({
					"git",
					"-C",
					repo_path,
					"remote",
					"get-url",
					"origin",
				})
				result = utils.trim(result)

				if vim.v.shell_error == 0 and result ~= "" then
					local new_url = result

					if protocol == "ssh" then
						new_url = result:gsub("https://github%.com/", "git@github.com:")
					else
						new_url = result:gsub("git@github%.com:", "https://github.com/")
					end

					if new_url ~= result then
						vim.fn.system({
							"git",
							"-C",
							repo_path,
							"remote",
							"set-url",
							"origin",
							new_url,
						})
						if vim.v.shell_error == 0 then
							converted = converted + 1
						else
							convert_errors = convert_errors + 1
						end
					end
				end
			end

			::continue::
		end

		vim.notify(
			string.format(
				"%s Converted %d plugin remotes to %s\n" .. "  %s %d skipped (protected)\n%s",
				icons.ui.Check,
				converted,
				protocol:upper(),
				icons.ui.Lock,
				skipped,
				convert_errors > 0 and string.format("  %s %d errors", icons.diagnostics.Error, convert_errors) or ""
			),
			vim.log.levels.INFO,
			{ title = "NvimEnterprise — Git Convert" }
		)
	end, {
		nargs = 0,
		desc = icons.ui.Rocket .. " Convert all plugin remotes to current git protocol",
	})

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAP AUDIT
	-- ═══════════════════════════════════════════════════════════════════

	-- ── :ListAllKeymaps ──────────────────────────────────────────────
	vim.api.nvim_create_user_command("ListAllKeymaps", function()
		local modes = { "n", "i", "v", "x", "t" }
		local keymaps = {}
		for _, mode in ipairs(modes) do
			local maps = vim.api.nvim_get_keymap(mode)
			for _, km in ipairs(maps) do
				table.insert(keymaps, {
					mode = mode,
					lhs = km.lhs,
					desc = km.desc or "(no desc)",
					rhs = km.rhs or "<Lua>",
				})
			end
		end

		local lines = {
			"Mode | Key                | Description                     | Source / Action",
			string.rep("─", 100),
		}

		for _, km in ipairs(keymaps) do
			local source = km.rhs or "<Lua Callback>"
			local desc = (km.desc or "(no desc)"):sub(1, 40)
			table.insert(
				lines,
				string.format("%s | %-18s | %-31s | %s", km.mode, km.lhs:gsub("%s+", "<Space>"), desc, source)
			)
		end

		create_info_float(lines, {
			width = math.floor(vim.o.columns * 0.85),
			height = math.floor(vim.o.lines * 0.85),
			filetype = "keymap_list",
			border = settings:get("ui.float_border", "rounded"),
		})
	end, {
		nargs = 0,
		desc = "List all keymaps in floating window",
	})

	-- ── :NvimAuditKeymaps ────────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimAuditKeymaps", function()
		require("core.keymaps").audit()
	end, {
		nargs = 0,
		desc = icons.ui.Keymap .. " Audit all registered keymaps",
	})

	-- ── :NvimKeymapsConflicts ────────────────────────────────────────
	vim.api.nvim_create_user_command("NvimKeymapsConflicts", function()
		require("core.keymaps").check_health()
	end, {
		nargs = 0,
		desc = icons.ui.Keymap .. " Check keymap prefix conflicts",
	})

	-- ═══════════════════════════════════════════════════════════════════
	-- DEFERRED REGISTRATION
	--
	-- Colorscheme commands must be registered AFTER lazy.nvim finishes
	-- loading so that all colorscheme plugins are known. The VeryLazy
	-- event fires after lazy.setup() completes and the UI is ready.
	-- ═══════════════════════════════════════════════════════════════════

	vim.api.nvim_create_autocmd("User", {
		pattern = "VeryLazy",
		once = true,
		callback = function()
			local cs_ok, cs_manager = pcall(require, "config.colorscheme_manager")
			if cs_ok and cs_manager and cs_manager.register_commands then cs_manager:register_commands() end
		end,
	})
end

return M
