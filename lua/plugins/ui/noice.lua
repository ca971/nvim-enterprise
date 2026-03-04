---@file lua/plugins/ui/noice.lua
---@description Noice — Enterprise-grade command line, notifications, and LSP UI
---@module "plugins.ui.noice"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Plugin enable/disable guard, float_border preference
---@see core.icons                 Icon provider (cmdline icons, keymap descriptions, format icons)
---@see config.colorscheme_manager ColorScheme autocmd triggers highlight refresh
---@see plugins.ui.lualine         Status components (noice_command, noice_mode) displayed in section C
---@see plugins.editor.telescope   Optional integration for message history picker
---@see plugins.lsp                LSP hover, signature, progress rendered through Noice
---@see plugins.completion.cmp     Documentation popup override via Noice
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ui/noice.lua — Command line & notification system               ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  noice.nvim (folke/noice.nvim)                                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  UI Overrides:                                                   │    ║
--- ║  │  ├─ Cmdline → floating popup (command palette style)             │    ║
--- ║  │  │  ├─ :command   → ChevronRight icon, vim lang                  │    ║
--- ║  │  │  ├─ /search ↓  → Search + ArrowDown, regex lang               │    ║
--- ║  │  │  ├─ ?search ↑  → Search + ArrowUp, regex lang                 │    ║
--- ║  │  │  ├─ :!shell    → Terminal icon, bash lang                     │    ║
--- ║  │  │  ├─ :lua       → Lua icon, lua lang                           │    ║
--- ║  │  │  ├─ :help      → Note icon                                    │    ║
--- ║  │  │  ├─ :%s/       → Pencil icon, regex lang                      │    ║
--- ║  │  │  └─ input      → Pencil icon, text lang                       │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Messages → notify (default), mini (transient), split (long)  │    ║
--- ║  │  ├─ Popupmenu → nui backend with kind icons                      │    ║
--- ║  │  └─ Notifications → replace + merge for dedup                    │    ║
--- ║  │                                                                  │    ║
--- ║  │  LSP Integration:                                                │    ║
--- ║  │  ├─ Hover documentation (bordered, scrollable)                   │    ║
--- ║  │  ├─ Signature help (auto-open with luasnip, throttled)           │    ║
--- ║  │  ├─ Progress (mini view, 30fps throttle, replace+merge)          │    ║
--- ║  │  ├─ Messages → notify view                                       │    ║
--- ║  │  └─ Markdown overrides (stylize, convert, cmp docs)              │    ║
--- ║  │                                                                  │    ║
--- ║  │  Views (8 custom configurations):                                │    ║
--- ║  │  ├─ cmdline_popup    — centered 40%, width 70                    │    ║
--- ║  │  ├─ cmdline_popupmenu — centered 50%, max 15 items               │    ║
--- ║  │  ├─ mini             — bottom-right, 3s timeout, winblend 15     │    ║
--- ║  │  ├─ hover            — offset (2,2), max 80×20, word wrap        │    ║
--- ║  │  ├─ split            — 40% height, q/Esc to close                │    ║
--- ║  │  ├─ popup            — centered 80%×60%, editor-relative         │    ║
--- ║  │  ├─ confirm          — centered, auto-size, zindex 210           │    ║
--- ║  │  └─ notify           — fallback to mini, replace+merge           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Smart Routes (20 rules):                                        │    ║
--- ║  │  ├─ Skip: written, fewer/more lines, yanked, search_count        │    ║
--- ║  │  │       Already at, search hit, No information, query,          │    ║
--- ║  │  │       No matching autocommands                                │    ║
--- ║  │  ├─ Mini: E486 (not found), wmsg, lsp progress, return_prompt    │    ║
--- ║  │  ├─ Split: messages > 15 lines (enter = true)                    │    ║
--- ║  │  ├─ Notify: macro recording (replace+merge, 2s timeout)          │    ║
--- ║  │  └─ Notify: error messages (level = ERROR)                       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Format Templates (8):                                           │    ║
--- ║  │  ├─ default, notify, details, telescope, telescope_preview       │    ║
--- ║  │  ├─ lsp_progress, lsp_progress_done, fidget                      │    ║
--- ║  │  └─ Done marker: ✓ icon from core.icons                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Presets:                                                        │    ║
--- ║  │  ├─ command_palette     — cmdline as centered popup              │    ║
--- ║  │  ├─ bottom_search       — search at bottom of screen             │    ║
--- ║  │  ├─ long_message_to_split — auto-split long outputs              │    ║
--- ║  │  ├─ inc_rename          — incremental rename UI                  │    ║
--- ║  │  └─ lsp_doc_border      — bordered LSP documentation             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Visual Layer (33 custom highlight groups):                      │    ║
--- ║  │  ├─ Cmdline:  Popup, Border, Title, Icon (5 variants)            │    ║
--- ║  │  ├─ Mini:     italic comment style on CursorLine bg              │    ║
--- ║  │  ├─ Hover:    NormalFloat bg with DiagnosticInfo border          │    ║
--- ║  │  ├─ Split:    Normal bg with Comment border                      │    ║
--- ║  │  ├─ Popup:    NormalFloat bg with Function border                │    ║
--- ║  │  ├─ Popupmenu: Pmenu bg, Special match highlight                 │    ║
--- ║  │  ├─ Confirm:  NormalFloat bg with DiagnosticWarn border          │    ║
--- ║  │  ├─ Format:   Title, Date, Event, Kind, Progress                 │    ║
--- ║  │  ├─ LSP:      Spinner, Title, Client                             │    ║
--- ║  │  └─ Misc:     Scrollbar, VirtualText                             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (12 bindings):                                          │    ║
--- ║  │  ├─ <S-Enter>     Redirect cmdline output to split               │    ║
--- ║  │  ├─ <leader>snl   Last message                                   │    ║
--- ║  │  ├─ <leader>snh   Message history                                │    ║
--- ║  │  ├─ <leader>sna   All messages                                   │    ║
--- ║  │  ├─ <leader>snd   Dismiss all notifications                      │    ║
--- ║  │  ├─ <leader>snt   Noice Telescope picker                         │    ║
--- ║  │  ├─ <leader>snp   LSP progress (filtered history)                │    ║
--- ║  │  ├─ <leader>sne   Errors only                                    │    ║
--- ║  │  ├─ <leader>sns   Noice stats / debug info                       │    ║
--- ║  │  ├─ <leader>snf   Filter messages by level (interactive)         │    ║
--- ║  │  ├─ <C-f>         Scroll LSP docs forward (4 lines)              │    ║
--- ║  │  └─ <C-b>         Scroll LSP docs backward (4 lines)             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Autocmds:                                                       │    ║
--- ║  │  └─ ColorScheme → re-apply all 33 highlight groups               │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Defensive Design:                                                       ║
--- ║  • All highlight extractions via pcall + cached per apply cycle          ║
--- ║  • Tokyo Night palette as ultimate color fallback                        ║
--- ║  • Telescope loaded lazily on first :Telescope noice call                ║
--- ║  • noice.lsp.scroll returns false to pass through to default C-f/C-b     ║
--- ║  • Notification replace+merge prevents flooding on rapid events          ║
--- ║  • Smart routes skip 10+ noise patterns to keep UI clean                 ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_plugin_enabled("noice") then return {} end

local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
--
-- Loaded on VeryLazy. Dependencies:
-- • nui.nvim:      required — popup/popupmenu backend
-- • telescope.nvim: optional — loaded on demand for message picker
-- ═══════════════════════════════════════════════════════════════════════════

return {
	"folke/noice.nvim",
	event = "VeryLazy",

	dependencies = {
		{ "MunifTanjim/nui.nvim", lazy = true },
		{ "nvim-telescope/telescope.nvim", optional = true },
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAPS
	--
	-- 12 bindings organized by function:
	-- • Cmdline:     redirect output to split
	-- • History:     last, all, filtered, errors, stats
	-- • Integration: Telescope picker, LSP progress
	-- • Navigation:  scroll LSP docs (C-f / C-b)
	-- ═══════════════════════════════════════════════════════════════════

	keys = {
		-- ── Cmdline redirect ──────────────────────────────────────────
		{
			"<S-Enter>",
			function()
				require("noice").redirect(vim.fn.getcmdline())
			end,
			mode = "c",
			desc = icons.ui.Terminal .. " Redirect cmdline",
		},

		-- ── Message history ───────────────────────────────────────────
		{
			"<leader>snl",
			function()
				require("noice").cmd("last")
			end,
			desc = icons.ui.History .. " Last message",
		},
		{
			"<leader>snh",
			function()
				require("noice").cmd("history")
			end,
			desc = icons.ui.History .. " Message history",
		},
		{
			"<leader>sna",
			function()
				require("noice").cmd("all")
			end,
			desc = icons.ui.List .. " All messages",
		},
		{
			"<leader>snd",
			function()
				require("noice").cmd("dismiss")
			end,
			desc = icons.ui.BoldClose .. " Dismiss all",
		},

		-- ── Telescope integration ─────────────────────────────────────
		-- Loads telescope lazily on first invocation, then registers
		-- the noice extension and opens the picker.
		{
			"<leader>snt",
			function()
				require("lazy").load({ plugins = { "telescope.nvim" } })
				require("telescope").load_extension("noice")
				vim.cmd("Telescope noice")
			end,
			desc = icons.ui.Telescope .. " Noice picker",
		},

		-- ── Filtered views ────────────────────────────────────────────
		{
			"<leader>snp",
			function()
				require("noice").cmd("history")
				vim.defer_fn(function()
					vim.fn.search("lsp", "w")
				end, 100)
			end,
			desc = icons.misc.Lsp .. " LSP progress",
		},
		{
			"<leader>sne",
			function()
				require("noice").cmd("errors")
			end,
			desc = icons.diagnostics.Error .. " Errors only",
		},
		{
			"<leader>sns",
			function()
				require("noice").cmd("stats")
			end,
			desc = icons.diagnostics.Info .. " Noice stats",
		},
		{
			"<leader>snf",
			function()
				local levels = { "trace", "debug", "info", "warn", "error" }
				vim.ui.select(levels, { prompt = icons.ui.Search .. " Filter by level:" }, function(level)
					if level then require("noice").cmd("history", { filter = { min_level = level } }) end
				end)
			end,
			desc = icons.ui.Search .. " Filter messages",
		},

		-- ── LSP doc scrolling ─────────────────────────────────────────
		-- Returns the original key if noice.lsp.scroll returns false
		-- (no scrollable window), allowing normal C-f/C-b behavior.
		{
			"<C-f>",
			function()
				if not require("noice.lsp").scroll(4) then return "<C-f>" end
			end,
			silent = true,
			expr = true,
			desc = "Scroll forward",
			mode = { "i", "n", "s" },
		},
		{
			"<C-b>",
			function()
				if not require("noice.lsp").scroll(-4) then return "<C-b>" end
			end,
			silent = true,
			expr = true,
			desc = "Scroll backward",
			mode = { "i", "n", "s" },
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	--
	-- Evaluated lazily at VeryLazy via function (not static table)
	-- because border_style depends on runtime settings:get().
	-- ═══════════════════════════════════════════════════════════════════

	---@return table opts Noice configuration table
	opts = function()
		local border_style = settings:get("ui.float_border", "rounded")

		return {
			-- ── Cmdline ───────────────────────────────────────────────
			cmdline = {
				enabled = true,
				view = "cmdline_popup",
				format = {
					cmdline = { pattern = "^:", icon = icons.ui.ChevronRight, lang = "vim", title = " Command " },
					search_down = {
						kind = "search",
						pattern = "^/",
						icon = icons.ui.Search .. " " .. icons.ui.BoldArrowDown,
						lang = "regex",
						title = " Search ↓ ",
					},
					search_up = {
						kind = "search",
						pattern = "^%?",
						icon = icons.ui.Search .. " " .. icons.ui.BoldArrowUp,
						lang = "regex",
						title = " Search ↑ ",
					},
					filter = { pattern = "^:%s*!", icon = icons.ui.Terminal, lang = "bash", title = " Shell " },
					lua = {
						pattern = { "^:%s*lua%s+", "^:%s*lua%s*=%s*", "^:%s*=%s*" },
						icon = icons.app.Lua,
						lang = "lua",
						title = " Lua ",
					},
					help = { pattern = "^:%s*he?l?p?%s+", icon = icons.ui.Note, title = " Help " },
					substitute = {
						pattern = "^:%%?s/",
						icon = icons.ui.Pencil,
						lang = "regex",
						title = " Substitute ",
					},
					input = { icon = icons.ui.Pencil, lang = "text", title = " Input " },
				},
			},

			-- ── Messages ──────────────────────────────────────────────
			messages = {
				enabled = true,
				view = "notify",
				view_error = "notify",
				view_warn = "notify",
				view_history = "messages",
				view_search = "virtualtext",
			},

			-- ── Popupmenu ─────────────────────────────────────────────
			popupmenu = { enabled = true, backend = "nui", kind_icons = true },

			-- ── Notifications ─────────────────────────────────────────
			notify = { enabled = true, view = "notify", opts = { replace = true, merge = true } },

			-- ── LSP integration ───────────────────────────────────────
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
					["cmp.entry.get_documentation"] = true,
				},
				hover = { enabled = true, silent = false },
				signature = {
					enabled = true,
					auto_open = { enabled = true, trigger = true, luasnip = true, throttle = 50 },
				},
				progress = {
					enabled = true,
					format = "lsp_progress",
					format_done = "lsp_progress_done",
					throttle = 1000 / 30,
					view = "mini",
				},
				message = { enabled = true, view = "notify" },
				documentation = {
					view = "hover",
					opts = {
						lang = "markdown",
						replace = true,
						render = "plain",
						format = { "{message}" },
						win_options = { concealcursor = "n", conceallevel = 3 },
					},
				},
			},

			-- ── Health & performance ──────────────────────────────────
			health = { checker = true },
			smart_move = { enabled = true, excluded_filetypes = { "cmp_menu", "cmp_docs", "notify" } },
			throttle = 1000 / 30,

			-- ── Smart routes (20 rules) ───────────────────────────────
			-- Organized by action: skip → mini → split → notify
			routes = {
				-- ── Skip: noise suppression ───────────────────────────
				{ filter = { event = "msg_show", find = "written" }, opts = { skip = true } },
				{ filter = { event = "msg_show", find = "fewer lines" }, opts = { skip = true } },
				{ filter = { event = "msg_show", find = "more lines" }, opts = { skip = true } },
				{ filter = { event = "msg_show", find = "more line" }, opts = { skip = true } },
				{ filter = { event = "msg_show", find = "fewer line" }, opts = { skip = true } },
				{ filter = { event = "msg_show", find = "yanked" }, opts = { skip = true } },
				{ filter = { event = "msg_show", kind = "search_count" }, opts = { skip = true } },
				{ filter = { event = "msg_show", find = "Already at" }, opts = { skip = true } },
				{ filter = { event = "msg_show", kind = "wmsg", find = "search hit" }, opts = { skip = true } },
				{ filter = { event = "notify", find = "No information available" }, opts = { skip = true } },
				{ filter = { event = "msg_show", find = "query" }, opts = { skip = true } },
				{ filter = { event = "msg_show", find = "No matching autocommands" }, opts = { skip = true } },

				-- ── Mini: transient messages ──────────────────────────
				{ filter = { event = "msg_show", find = "E486" }, view = "mini" },
				{ filter = { event = "msg_show", kind = "wmsg" }, view = "mini" },
				{ filter = { event = "msg_show", kind = "return_prompt" }, view = "mini" },
				{
					filter = { event = "lsp", kind = "progress" },
					view = "mini",
					opts = { replace = true, merge = true },
				},

				-- ── Split: long output ────────────────────────────────
				{ filter = { event = "msg_show", min_height = 15 }, view = "split", opts = { enter = true } },

				-- ── Notify: important events ──────────────────────────
				{
					filter = { event = "msg_showmode", find = "recording" },
					view = "notify",
					opts = {
						title = "Macro",
						level = vim.log.levels.INFO,
						replace = true,
						merge = true,
						timeout = 2000,
					},
				},
				{
					filter = { event = "msg_show", kind = "emsg" },
					view = "notify",
					opts = { level = vim.log.levels.ERROR, title = "Error" },
				},
			},

			-- ── Format templates (8) ──────────────────────────────────
			format = {
				default = { "{level} ", "{title} ", "{message}" },
				notify = { "{level} ", "{title} ", "{message}" },
				details = {
					"{level} ",
					"{date} ",
					"{event}",
					{ "{kind}", before = " (", after = ")" },
					" ",
					"{title} ",
					"\n",
					"{message}",
				},
				telescope = { "{level} ", "{date} ", "{title} ", "{message}" },
				telescope_preview = {
					"{level} ",
					"{date} ",
					"{event}",
					{ "{kind}", before = " (", after = ")" },
					"\n",
					"{title}\n",
					"\n",
					"{message}",
				},
				lsp_progress = { "{progress} ", "{title} ", "{message}" },
				lsp_progress_done = { icons.ui.Check .. " ", "{title} ", "{message}" },
				fidget = { "{spinner} ", "{title} ", "{message} ", "({data.progress.percentage}%) " },
			},

			-- ── Presets ───────────────────────────────────────────────
			presets = {
				command_palette = true,
				bottom_search = true,
				long_message_to_split = true,
				inc_rename = true,
				lsp_doc_border = true,
			},

			-- ── Views (8 custom configurations) ──────────────────────
			views = {
				-- ── Cmdline popup (centered, command palette) ──────────
				cmdline_popup = {
					position = { row = "40%", col = "50%" },
					size = { width = 70, height = "auto" },
					border = { style = border_style, padding = { 0, 1 } },
					win_options = {
						winhighlight = {
							Normal = "NoiceCmdlinePopup",
							FloatBorder = "NoiceCmdlinePopupBorder",
							FloatTitle = "NoiceCmdlinePopupTitle",
							IncSearch = "",
							CurSearch = "",
							Search = "",
						},
						cursorline = false,
					},
				},

				-- ── Cmdline popupmenu (completion list) ───────────────
				cmdline_popupmenu = {
					view = "popupmenu",
					zindex = 200,
					position = { row = "50%", col = "50%" },
					size = { width = 70, height = "auto", max_height = 15 },
					border = { style = border_style, padding = { 0, 1 } },
					win_options = {
						winhighlight = {
							Normal = "NoicePopupmenu",
							FloatBorder = "NoicePopupmenuBorder",
							CursorLine = "NoicePopupmenuSelected",
							PmenuMatch = "NoicePopupmenuMatch",
						},
					},
				},

				-- ── Mini (bottom-right transient) ─────────────────────
				mini = {
					timeout = 3000,
					zindex = 60,
					position = { row = -2, col = "100%" },
					size = "auto",
					border = { style = "none" },
					win_options = {
						winblend = 15,
						winhighlight = {
							Normal = "NoiceMini",
							IncSearch = "",
							CurSearch = "",
							Search = "",
						},
					},
				},

				-- ── Hover (LSP documentation) ─────────────────────────
				hover = {
					border = { style = border_style, padding = { 0, 1 } },
					position = { row = 2, col = 2 },
					size = { max_width = 80, max_height = 20 },
					win_options = {
						wrap = true,
						linebreak = true,
						winhighlight = {
							Normal = "NoiceHover",
							FloatBorder = "NoiceHoverBorder",
						},
					},
				},

				-- ── Split (long output, persistent) ───────────────────
				split = {
					enter = true,
					size = "40%",
					close = { keys = { "q", "<Esc>" } },
					win_options = {
						wrap = true,
						linebreak = true,
						winhighlight = {
							Normal = "NoiceSplit",
							FloatBorder = "NoiceSplitBorder",
						},
					},
				},

				-- ── Popup (large centered window) ─────────────────────
				popup = {
					backend = "popup",
					relative = "editor",
					close = { events = { "BufLeave" }, keys = { "q", "<Esc>" } },
					enter = true,
					border = { style = border_style },
					position = "50%",
					size = { width = "80%", height = "60%" },
					win_options = {
						winhighlight = {
							Normal = "NoicePopup",
							FloatBorder = "NoicePopupBorder",
						},
					},
				},

				-- ── Confirm (dialog box) ──────────────────────────────
				confirm = {
					backend = "popup",
					relative = "editor",
					focusable = false,
					enter = false,
					zindex = 210,
					format = { "{confirm}" },
					position = { row = "50%", col = "50%" },
					size = "auto",
					border = {
						style = border_style,
						padding = { 0, 1 },
						text = { top = " Confirm " },
					},
					win_options = {
						winhighlight = {
							Normal = "NoiceConfirm",
							FloatBorder = "NoiceConfirmBorder",
						},
					},
				},

				-- ── Notify (fallback to mini) ─────────────────────────
				notify = {
					backend = "notify",
					fallback = "mini",
					format = "notify",
					replace = true,
					merge = true,
				},

				-- ── Messages (split with details format) ──────────────
				messages = {
					view = "split",
					opts = { enter = true, format = "details" },
				},
			},
		}
	end,

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIG
	--
	-- Post-setup pipeline:
	-- 1. Initialize noice.nvim with merged options
	-- 2. Apply theme-adaptive highlights (33 groups, cached)
	-- 3. Register ColorScheme autocmd for highlight refresh
	-- ═══════════════════════════════════════════════════════════════════

	config = function(_, opts)
		-- ── Step 1: Initialize noice.nvim ─────────────────────────────
		require("noice").setup(opts)

		-- ── Step 2: Apply theme-adaptive highlights ───────────────────
		-- Colors are derived from the active colorscheme with Tokyo Night
		-- palette as fallback. A per-cycle cache avoids redundant
		-- nvim_get_hl calls for the same highlight group.

		--- Apply all 33 Noice highlight groups derived from the active colorscheme.
		---
		--- Uses a per-invocation cache: each highlight group is queried
		--- at most once per apply_highlights() call via get_hl().
		---@return nil
		---@private
		local function apply_highlights()
			local hl = vim.api.nvim_set_hl

			-- ── Per-cycle cache for highlight queries ──────────────────
			---@type table<string, table>
			local hl_cache = {}

			--- Get cached highlight attributes for a group.
			---@param name string Highlight group name
			---@return table attrs Highlight attributes (may be empty)
			local function get_hl(name)
				if not hl_cache[name] then
					local ok, group = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
					hl_cache[name] = ok and group or {}
				end
				return hl_cache[name]
			end

			--- Extract fg hex from cached highlight.
			---@param name string Highlight group name
			---@return string|nil hex Foreground hex or nil
			local function fg_of(name)
				local group = get_hl(name)
				return group.fg and string.format("#%06x", group.fg) or nil
			end

			--- Extract bg hex from cached highlight.
			---@param name string Highlight group name
			---@return string|nil hex Background hex or nil
			local function bg_of(name)
				local group = get_hl(name)
				return group.bg and string.format("#%06x", group.bg) or nil
			end

			-- ── Cmdline popup (5 groups) ──────────────────────────────
			hl(0, "NoiceCmdlinePopup", { bg = bg_of("NormalFloat") or "#1e1e2e" })
			hl(0, "NoiceCmdlinePopupBorder", {
				fg = fg_of("Function") or "#7aa2f7",
				bg = bg_of("NormalFloat") or "#1e1e2e",
			})
			hl(0, "NoiceCmdlinePopupTitle", {
				fg = fg_of("Function") or "#7aa2f7",
				bg = bg_of("NormalFloat") or "#1e1e2e",
				bold = true,
			})
			hl(0, "NoiceCmdlineIcon", { fg = fg_of("DiagnosticInfo") or "#7aa2f7", bold = true })
			hl(0, "NoiceCmdlineIconSearch", { fg = fg_of("DiagnosticWarn") or "#e0af68", bold = true })

			-- ── Cmdline icon variants (3 groups) ──────────────────────
			hl(0, "NoiceCmdlineIconFilter", { fg = fg_of("DiagnosticHint") or "#1abc9c", bold = true })
			hl(0, "NoiceCmdlineIconLua", { fg = fg_of("String") or "#9ece6a", bold = true })
			hl(0, "NoiceCmdlineIconHelp", { fg = fg_of("Special") or "#7dcfff", bold = true })

			-- ── Mini (1 group) ────────────────────────────────────────
			hl(0, "NoiceMini", {
				fg = fg_of("Comment") or "#565f89",
				bg = bg_of("CursorLine") or "#292e42",
				italic = true,
			})

			-- ── Hover (2 groups) ──────────────────────────────────────
			hl(0, "NoiceHover", { bg = bg_of("NormalFloat") or "#1e1e2e" })
			hl(0, "NoiceHoverBorder", {
				fg = fg_of("DiagnosticInfo") or "#7aa2f7",
				bg = bg_of("NormalFloat") or "#1e1e2e",
			})

			-- ── Split (2 groups) ──────────────────────────────────────
			hl(0, "NoiceSplit", { bg = bg_of("Normal") or "#1a1b26" })
			hl(0, "NoiceSplitBorder", {
				fg = fg_of("Comment") or "#565f89",
				bg = bg_of("Normal") or "#1a1b26",
			})

			-- ── Popup (2 groups) ──────────────────────────────────────
			hl(0, "NoicePopup", { bg = bg_of("NormalFloat") or "#1e1e2e" })
			hl(0, "NoicePopupBorder", {
				fg = fg_of("Function") or "#7aa2f7",
				bg = bg_of("NormalFloat") or "#1e1e2e",
			})

			-- ── Popupmenu (4 groups) ──────────────────────────────────
			hl(0, "NoicePopupmenu", { bg = bg_of("Pmenu") or "#1e1e2e" })
			hl(0, "NoicePopupmenuBorder", {
				fg = fg_of("Function") or "#7aa2f7",
				bg = bg_of("Pmenu") or "#1e1e2e",
			})
			hl(0, "NoicePopupmenuSelected", { bg = bg_of("PmenuSel") or "#292e42", bold = true })
			hl(0, "NoicePopupmenuMatch", { fg = fg_of("Special") or "#7dcfff", bold = true })

			-- ── Confirm (2 groups) ────────────────────────────────────
			hl(0, "NoiceConfirm", { bg = bg_of("NormalFloat") or "#1e1e2e" })
			hl(0, "NoiceConfirmBorder", {
				fg = fg_of("DiagnosticWarn") or "#e0af68",
				bg = bg_of("NormalFloat") or "#1e1e2e",
			})

			-- ── Scrollbar (2 groups) ──────────────────────────────────
			hl(0, "NoiceScrollbar", { fg = fg_of("Comment") or "#565f89" })
			hl(0, "NoiceScrollbarThumb", { bg = fg_of("Comment") or "#565f89" })

			-- ── Format (5 groups) ─────────────────────────────────────
			hl(0, "NoiceFormatTitle", { fg = fg_of("Title") or "#7aa2f7", bold = true })
			hl(0, "NoiceFormatDate", { fg = fg_of("Comment") or "#565f89", italic = true })
			hl(0, "NoiceFormatEvent", { fg = fg_of("Type") or "#2ac3de" })
			hl(0, "NoiceFormatKind", { fg = fg_of("Constant") or "#ff9e64", italic = true })
			hl(0, "NoiceFormatProgressDone", { fg = fg_of("String") or "#9ece6a", bold = true })
			hl(0, "NoiceFormatProgressTodo", { fg = fg_of("Comment") or "#565f89" })

			-- ── Virtual text (1 group) ────────────────────────────────
			hl(0, "NoiceVirtualText", { fg = fg_of("DiagnosticInfo") or "#7aa2f7", italic = true })

			-- ── LSP (3 groups) ────────────────────────────────────────
			hl(0, "NoiceLspProgressSpinner", { fg = fg_of("DiagnosticInfo") or "#7aa2f7" })
			hl(0, "NoiceLspProgressTitle", { fg = fg_of("Title") or "#7aa2f7", bold = true })
			hl(0, "NoiceLspProgressClient", { fg = fg_of("Comment") or "#565f89", italic = true })
		end

		apply_highlights()

		-- ── Step 3: Re-apply on colorscheme change ────────────────────
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("NvimEnterprise_NoiceHL", { clear = true }),
			pattern = "*",
			callback = apply_highlights,
			desc = "NvimEnterprise: Re-apply Noice highlights after colorscheme change",
		})
	end,
}
