---@file lua/plugins/ui/no-neck-pain.lua
---@description No Neck Pain — center buffer for ergonomic coding on wide screens
---@module "plugins.ui.no-neck-pain"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.ui.presenting Presentation mode (complementary, slides-focused)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ui/no-neck-pain.lua — Centered buffer layout                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  no-neck-pain.nvim                                               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Adds empty padding buffers on each side of the active window    │    ║
--- ║  │  to center the content. Ideal for ultrawide monitors and 4K      │    ║
--- ║  │  displays where the buffer stretches too far horizontally.       │    ║
--- ║  │                                                                  │    ║
--- ║  │  ┌─────────┬───────────────────────┬─────────┐                   │    ║
--- ║  │  │ padding │    active buffer      │ padding │                   │    ║
--- ║  │  │ (empty) │    (centered, 100c)   │ (empty) │                   │    ║
--- ║  │  │         │                       │         │                   │    ║
--- ║  │  └─────────┴───────────────────────┴─────────┘                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Features:                                                       │    ║
--- ║  │  • Toggle centering on/off with a single keymap                  │    ║
--- ║  │  • Adjustable width (default 108 columns for 100 + gutter)       │    ║
--- ║  │  • Increase/decrease width dynamically                           │    ║
--- ║  │  • Optional scratch pads in side buffers (for notes)             │    ║
--- ║  │  • Autocmd integration (auto-enable per filetype optionally)     │    ║
--- ║  │  • Disables in diff mode, file explorers, terminals              │    ║
--- ║  │  • Side buffers inherit colorscheme (seamless look)              │    ║
--- ║  │                                                                  │    ║
--- ║  │  Complements (does NOT replace):                                 │    ║
--- ║  │  ├─ <leader>z    Zen mode (full immersion — hides UI)            │    ║
--- ║  │  ├─ <leader>uz   Toggle Zen Mode (snacks)                        │    ║
--- ║  │  ├─ <leader>uZ   Toggle Zoom Mode (maximize window)              │    ║
--- ║  │  ├─ <leader>wm   Toggle Zoom Mode (duplicate)                    │    ║
--- ║  │  └─ <leader>uD   Toggle Dimming                                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Key difference from Zen mode:                                   │    ║
--- ║  │  • Zen = immersive, hides everything, for focused writing        │    ║
--- ║  │  • NNP = lightweight centering, keeps all UI visible,            │    ║
--- ║  │    for daily coding on wide screens                              │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • cmd + keys loading (zero startup cost until first toggle)             ║
--- ║  • Side buffers are unlisted, unmodifiable (no interference)             ║
--- ║  • Auto-disables when opening splits or file explorers                   ║
--- ║  • Icons from core/icons.lua (single source of truth)                    ║
--- ║  • No background processes (pure window management)                      ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    <leader>uN   Toggle No Neck Pain on/off                   (n)         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("no_neck_pain") then return {} end

---@type Icons
local icons = require("core.icons")

return {
	"shortcuts/no-neck-pain.nvim",
	version = "*",

	cmd = {
		"NoNeckPain",
		"NoNeckPainResize",
		"NoNeckPainWidthUp",
		"NoNeckPainWidthDown",
		"NoNeckPainScratchPad",
	},

	keys = {
		{
			"<leader>uN",
			"<Cmd>NoNeckPain<CR>",
			desc = icons.ui.Window .. " Toggle No Neck Pain",
		},
	},

	opts = {
		--- Target width of the centered buffer in columns.
		--- 108 = 100 columns of code + 4 signcolumn + 4 line numbers.
		---@type integer
		width = 108,

		autocmds = {
			---@type boolean Start centering automatically on VimEnter
			enableOnVimEnter = false,
			---@type boolean Start centering automatically on TabEnter
			enableOnTabEnter = false,
			---@type boolean Re-apply highlights after colorscheme change
			reloadOnColorSchemeChange = true,
			---@type boolean Skip focus events on side padding buffers
			skipEnteringNoNeckPainBuffer = true,
		},

		mappings = {
			---@type boolean Enable built-in NNP keymaps
			enabled = true,
			---@type string Toggle keymap (mirrors global keymap)
			toggle = "<leader>uN",
			---@type string Increase width keymap (only active when NNP is on)
			widthUp = "<leader>u>",
			---@type string Decrease width keymap (only active when NNP is on)
			widthDown = "<leader>u<",
		},

		buffers = {
			colors = {
				---@type string Highlight group for side buffer background
				background = "Normal",
				---@type integer Blend level (0 = opaque)
				blend = 0,
			},

			--- Buffer options for side padding buffers.
			--- These ensure side buffers are invisible in buffer lists
			--- and cannot be accidentally modified.
			---@type table<string, any>
			bo = {
				filetype = "no-neck-pain",
				buftype = "nofile",
				bufhidden = "hide",
				buflisted = false,
				swapfile = false,
			},

			--- Window options for side padding windows.
			--- All chrome is disabled for a seamless appearance.
			---@type table<string, any>
			wo = {
				cursorline = false,
				cursorcolumn = false,
				colorcolumn = "",
				number = false,
				relativenumber = false,
				foldenable = false,
				list = false,
				wrap = true,
				linebreak = true,
				signcolumn = "no",
				foldcolumn = "0",
				statuscolumn = "",
			},

			left = { enabled = true },
			right = { enabled = true },

			scratchPad = {
				---@type boolean Enable editable scratch pads in side buffers
				enabled = false,
				---@type string Absolute path to save scratch pad content
				pathToFile = vim.fn.stdpath("data") .. "/no-neck-pain-scratchpad.md",
			},
		},

		--- Plugin integrations — auto-close sidebar plugins when NNP
		--- activates and reopen them when NNP deactivates.
		---@type table<string, { position: string, reopen?: boolean }>
		integrations = {
			NvimTree = { position = "left", reopen = true },
			NeoTree = { position = "left", reopen = true },
			undotree = { position = "left" },
			neotest = { position = "right", reopen = true },
			NvimDAPUI = { position = "none", reopen = true },
			outline = { position = "right", reopen = true },
		},
	},

	---@param _ table Plugin spec (unused)
	---@param opts table Resolved options
	config = function(_, opts)
		require("no-neck-pain").setup(opts)

		local group = vim.api.nvim_create_augroup("NvimEnterprise_NoNeckPain", { clear = true })

		vim.api.nvim_create_autocmd("User", {
			group = group,
			pattern = "NoNeckPainEnabled",
			desc = "Notify when No Neck Pain is enabled",
			---@param _ table Event data (unused)
			callback = function(_)
				vim.notify(
					icons.ui.Check .. "  No Neck Pain enabled (width: " .. (opts.width or 108) .. ")",
					vim.log.levels.INFO,
					{ title = icons.ui.Window .. "  No Neck Pain" }
				)
			end,
		})

		vim.api.nvim_create_autocmd("User", {
			group = group,
			pattern = "NoNeckPainDisabled",
			desc = "Notify when No Neck Pain is disabled",
			---@param _ table Event data (unused)
			callback = function(_)
				vim.notify(
					icons.ui.BoldClose .. "  No Neck Pain disabled",
					vim.log.levels.INFO,
					{ title = icons.ui.Window .. "  No Neck Pain" }
				)
			end,
		})
	end,
}
