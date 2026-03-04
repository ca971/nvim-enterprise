---@file lua/plugins/tools/toggleterm.lua
---@description ToggleTerm — multi-terminal management with float, horizontal, vertical layouts and platform-aware shell detection
---@module "plugins.tools.toggleterm"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (plugins.toggleterm.enabled, editor.terminal_shell, ui.float_border)
---@see core.platform Platform singleton (is_windows for shell detection)
---@see core.icons Centralized icon definitions (ui.Terminal)
---@see plugins.tools Developer tools aggregator
---@see plugins.tools.lazygit LazyGit integration (complementary, uses snacks terminal)
---
---@see https://github.com/akinsho/toggleterm.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/tools/toggleterm.lua — Multi-terminal management                ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Features:                                                       │    ║
--- ║  │  ├─ Float, horizontal, vertical terminal layouts                 │    ║
--- ║  │  ├─ Persistent terminal sessions (survive buffer switches)       │    ║
--- ║  │  ├─ Numbered terminals (up to 4 simultaneous terms)              │    ║
--- ║  │  ├─ Send current line or visual selection to terminal            │    ║
--- ║  │  ├─ Platform-aware shell detection (pwsh on Windows)             │    ║
--- ║  │  ├─ Custom shell override via editor.terminal_shell setting      │    ║
--- ║  │  ├─ Terminal-mode window navigation (<C-h/j/k/l>)                │    ║
--- ║  │  └─ <Esc><Esc> to exit terminal mode                             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Shell resolution:                                               │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  1. editor.terminal_shell setting (explicit override)      │  │    ║
--- ║  │  │  2. "pwsh" on Windows (platform detection)                 │  │    ║
--- ║  │  │  3. vim.o.shell (system default fallback)                  │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Layout sizing:                                                  │    ║
--- ║  │  ├─ Float: 85% width × 80% height, centered, bordered            │    ║
--- ║  │  ├─ Horizontal: 15 lines fixed height                            │    ║
--- ║  │  └─ Vertical: 40% of total columns                               │    ║
--- ║  │                                                                  │    ║
--- ║  │  on_open keymaps (buffer-local, terminal mode):                  │    ║
--- ║  │  ├─ <C-h/j/k/l> → window navigation without leaving terminal     │    ║
--- ║  │  └─ <Esc><Esc>   → exit terminal mode to normal mode             │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    <C-\>         Toggle terminal (any mode)            (n, t)            ║
--- ║    <leader>tf    Float terminal                        (n)               ║
--- ║    <leader>th    Horizontal terminal                   (n)               ║
--- ║    <leader>tv    Vertical terminal                     (n)               ║
--- ║    <leader>t1    Terminal #1                            (n)              ║
--- ║    <leader>t2    Terminal #2                            (n)              ║
--- ║    <leader>t3    Terminal #3                            (n)              ║
--- ║    <leader>t4    Terminal #4                            (n)              ║
--- ║    <leader>ts    Send line to terminal                  (n)              ║
--- ║    <leader>tS    Send selection to terminal             (v)              ║
--- ║                                                                          ║
--- ║  Terminal-mode keymaps (set in on_open, buffer-local):                   ║
--- ║    <C-h>         Switch to left window                 (t)               ║
--- ║    <C-j>         Switch to window below                (t)               ║
--- ║    <C-k>         Switch to window above                (t)               ║
--- ║    <C-l>         Switch to right window                (t)               ║
--- ║    <Esc><Esc>    Exit terminal mode                    (t)               ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  ├─ <C-\> is a DIFFERENT key from <C-/> / <C-_> (used by snacks)         ║
--- ║  │  — no conflict between toggleterm and snacks terminal                 ║
--- ║  ├─ opts is a function (not table) — defers platform detection to        ║
--- ║  │  first use, avoiding require("core.platform") at spec eval time       ║
--- ║  ├─ on_open sets buffer-local terminal keymaps — they only exist         ║
--- ║  │  while the terminal is open                                           ║
--- ║  ├─ persist_mode = true — terminal remembers insert/normal state         ║
--- ║  ├─ persist_size = true — layout dimensions survive toggle cycles        ║
--- ║  ├─ shade_terminals = true — visual distinction from code buffers        ║
--- ║  ├─ Float title centered with terminal icon for consistency              ║
--- ║  └─ winbar disabled — terminal doesn't need breadcrumbs                  ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • cmd + keys loading (zero startup cost)                                ║
--- ║  • Shell detection deferred to opts() function (not at require time)     ║
--- ║  • Float dimensions computed dynamically (responsive to window resize)   ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Uses pcall for settings access — degrades gracefully during
-- bootstrap when core modules may not be available yet.
-- ═══════════════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok and not settings:is_plugin_enabled("toggleterm") then return {} end

-- ═══════════════════════════════════════════════════════════════════════
-- SAFE REQUIRES
--
-- Icons loaded via pcall with fallback table. Ensures keymaps
-- display correctly even during bootstrap.
-- ═══════════════════════════════════════════════════════════════════════

local icons_ok, icons = pcall(require, "core.icons")

if not icons_ok or not icons then icons = {
	ui = { Terminal = "󰞷" },
} end

--- Safely get an icon from a table with a fallback value.
---
---@param tbl table|nil Icon group table
---@param key string Icon key within the group
---@param fallback string Fallback string if key is missing
---@return string icon The icon string
---@private
local function icon(tbl, key, fallback)
	if type(tbl) == "table" and tbl[key] ~= nil then return tbl[key] end
	return fallback or ""
end

---@type table
local ui = icons.ui or {}

-- ═══════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════

--- Safely read a setting value with pcall protection.
---
---@param key string Dot-separated settings path
---@param default any Fallback value
---@return any value The setting value or default
---@private
local function setting(key, default)
	if not settings_ok or not settings then return default end
	local ok, val = pcall(settings.get, settings, key, default)
	return ok and val or default
end

-- ═══════════════════════════════════════════════════════════════════════
-- ICONS
-- ═══════════════════════════════════════════════════════════════════════

---@type string Terminal icon for keymaps and float title
local term_icon = icon(ui, "Terminal", "󰞷")

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"akinsho/toggleterm.nvim",
	version = "*",
	cmd = {
		"ToggleTerm",
		"TermExec",
		"ToggleTermToggleAll",
		"ToggleTermSendCurrentLine",
		"ToggleTermSendVisualLines",
		"ToggleTermSendVisualSelection",
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAPS
	-- ═══════════════════════════════════════════════════════════════════

	keys = {
		-- ── Layout toggles ────────────────────────────────────────────
		{
			"<leader>tf",
			"<cmd>ToggleTerm direction=float<cr>",
			desc = term_icon .. " Float terminal",
		},
		{
			"<leader>th",
			"<cmd>ToggleTerm direction=horizontal<cr>",
			desc = term_icon .. " Horizontal terminal",
		},
		{
			"<leader>tv",
			"<cmd>ToggleTerm direction=vertical<cr>",
			desc = term_icon .. " Vertical terminal",
		},

		-- ── Numbered terminals ────────────────────────────────────────
		{
			"<leader>t1",
			"<cmd>1ToggleTerm<cr>",
			desc = term_icon .. " Terminal #1",
		},
		{
			"<leader>t2",
			"<cmd>2ToggleTerm<cr>",
			desc = term_icon .. " Terminal #2",
		},
		{
			"<leader>t3",
			"<cmd>3ToggleTerm<cr>",
			desc = term_icon .. " Terminal #3",
		},
		{
			"<leader>t4",
			"<cmd>4ToggleTerm<cr>",
			desc = term_icon .. " Terminal #4",
		},

		-- ── Global toggle ─────────────────────────────────────────────
		{
			"<C-\\>",
			"<cmd>ToggleTerm<cr>",
			mode = { "n", "t" },
			desc = term_icon .. " Toggle terminal",
		},

		-- ── Send to terminal ──────────────────────────────────────────
		{
			"<leader>ts",
			"<cmd>ToggleTermSendCurrentLine<cr>",
			desc = term_icon .. " Send line to terminal",
		},
		{
			"<leader>tS",
			"<cmd>ToggleTermSendVisualSelection<cr>",
			mode = "v",
			desc = term_icon .. " Send selection to terminal",
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	--
	-- opts is a function (not a table) to defer platform detection
	-- and shell resolution to first use. This avoids requiring
	-- core.platform at spec evaluation time.
	-- ═══════════════════════════════════════════════════════════════════

	opts = function()
		local platform_ok, platform = pcall(require, "core.platform")

		-- ── Shell resolution ──────────────────────────────────────────
		-- Priority: setting override → Windows pwsh → system default
		local shell = vim.o.shell
		if settings_ok then
			local custom_shell = setting("editor.terminal_shell", nil)
			if custom_shell then
				shell = custom_shell
			elseif platform_ok and platform and platform.is_windows then
				shell = "pwsh"
			end
		elseif platform_ok and platform and platform.is_windows then
			shell = "pwsh"
		end

		return {
			-- ── Size ──────────────────────────────────────────────────
			size = function(term)
				if term.direction == "horizontal" then
					return 15
				elseif term.direction == "vertical" then
					return math.floor(vim.o.columns * 0.4)
				end
			end,

			-- ── Behavior ──────────────────────────────────────────────
			open_mapping = [[<C-\>]],
			hide_numbers = true,
			start_in_insert = true,
			insert_mappings = true,
			terminal_mappings = true,
			persist_size = true,
			persist_mode = true,
			close_on_exit = true,
			auto_scroll = true,

			-- ── Default direction ─────────────────────────────────────
			direction = "float",

			-- ── Shell ─────────────────────────────────────────────────
			shell = shell,

			-- ── Shading ───────────────────────────────────────────────
			shade_filetypes = {},
			shade_terminals = true,
			shading_factor = 2,

			-- ── Float options ─────────────────────────────────────────
			float_opts = {
				border = setting("ui.float_border", "rounded"),
				winblend = 0,
				width = function()
					return math.floor(vim.o.columns * 0.85)
				end,
				height = function()
					return math.floor(vim.o.lines * 0.8)
				end,
				title = term_icon .. " Terminal",
				title_pos = "center",
			},

			-- ── Highlights ────────────────────────────────────────────
			highlights = {
				Normal = { link = "Normal" },
				NormalFloat = { link = "NormalFloat" },
				FloatBorder = { link = "FloatBorder" },
			},

			-- ── Window navigation from terminal mode ──────────────────
			-- Sets buffer-local keymaps when a terminal opens.
			-- Allows <C-h/j/k/l> to switch windows even in terminal
			-- mode, and <Esc><Esc> to exit terminal mode.
			---@param term table The toggleterm Terminal instance
			on_open = function(term)
				local opts = { buffer = term.bufnr, silent = true }
				vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-W>h]], opts)
				vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-W>j]], opts)
				vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-W>k]], opts)
				vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-W>l]], opts)
				vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], opts)
			end,

			-- ── Winbar ────────────────────────────────────────────────
			winbar = {
				enabled = false,
			},
		}
	end,
}
