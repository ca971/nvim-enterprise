---@file lua/plugins/ui/presenting.lua
---@description Presenting — create and run presentations from markdown files
---@module "plugins.ui.presenting"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.markview Markdown inline rendering (complementary)
---@see plugins.ui.no-neck-pain Centered layout (complementary, not slides)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ui/presenting.lua — Markdown-based presentations                ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  presenting.nvim                                                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Transforms markdown files into slide presentations directly     │    ║
--- ║  │  inside Neovim. Each heading (# or ---) becomes a new slide.     │    ║
--- ║  │                                                                  │    ║
--- ║  │  ┌─────────────────────────────────────────────────────────┐     │    ║
--- ║  │  │                                                         │     │    ║
--- ║  │  │              Slide Title                                │     │    ║
--- ║  │  │              ───────────                                │     │    ║
--- ║  │  │                                                         │     │    ║
--- ║  │  │  • Bullet point one                                     │     │    ║
--- ║  │  │  • Bullet point two                                     │     │    ║
--- ║  │  │  • Code blocks rendered with syntax highlighting        │     │    ║
--- ║  │  │                                                         │     │    ║
--- ║  │  │                                        [3/12]           │     │    ║
--- ║  │  └─────────────────────────────────────────────────────────┘     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Features:                                                       │    ║
--- ║  │  • Headings (# or ---) split content into slides                 │    ║
--- ║  │  • Centered, full-screen presentation mode                       │    ║
--- ║  │  • Syntax highlighting in code blocks                            │    ║
--- ║  │  • Slide number indicator                                        │    ║
--- ║  │  • Navigate with n/p, arrow keys, or number keys                 │    ║
--- ║  │  • Live-edit: change slide content, see it immediately           │    ║
--- ║  │  • Works with markview.nvim for rich rendering                   │    ║
--- ║  │  • Hides statusline, tabline, cmdline for immersion              │    ║
--- ║  │                                                                  │    ║
--- ║  │  Complements (does NOT replace):                                 │    ║
--- ║  │  ├─ <leader>mm   Markview toggle (inline rendering)              │    ║
--- ║  │  ├─ <leader>z    Zen mode (general focus, not slides)            │    ║
--- ║  │  ├─ <leader>uN   No Neck Pain (centering, not slides)            │    ║
--- ║  │  └─ markdown-preview.nvim (browser-based, not in-editor)         │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • cmd + keys loading (zero startup cost until first presentation)       ║
--- ║  • ft-aware: only relevant for markdown files                            ║
--- ║  • Saves and restores all UI options on enter/exit                       ║
--- ║  • Icons from core/icons.lua (single source of truth)                    ║
--- ║  • No background processes (pure buffer manipulation)                    ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    <leader>vp   Start presentation from current markdown     (n)         ║
--- ║    <leader>vq   Quit current presentation                    (n)         ║
--- ║    <leader>vr   Resume / restart presentation                (n)         ║
--- ║    <leader>vt   Toggle presenting mode                       (n)         ║
--- ║                                                                          ║
--- ║  Presentation-local keymaps (only active during slides):                 ║
--- ║    n / <Right> / l    Next slide                                         ║
--- ║    p / <Left> / h     Previous slide                                     ║
--- ║    q / <Esc>          Quit presentation                                  ║
--- ║    gg                 First slide                                        ║
--- ║    G                  Last slide                                         ║
--- ║    1-9                Jump to slide N                                    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("presenting") then return {} end

---@type Icons
local icons = require("core.icons")

--- Saved UI state before entering presentation mode.
--- Restored when the presentation ends via the cleanup function
--- returned by the `configure` callback.
---@class PresentingSavedState
---@field showtabline integer vim.o.showtabline value
---@field laststatus integer vim.o.laststatus value
---@field cmdheight integer vim.o.cmdheight value
---@field number boolean vim.wo.number value
---@field relativenumber boolean vim.wo.relativenumber value
---@field signcolumn string vim.wo.signcolumn value
---@field colorcolumn string vim.wo.colorcolumn value
---@field foldcolumn string vim.wo.foldcolumn value
---@field cursorline boolean vim.wo.cursorline value
---@field wrap boolean vim.wo.wrap value
---@field linebreak boolean vim.wo.linebreak value
---@field conceallevel integer vim.wo.conceallevel value
---@field spell boolean vim.wo.spell value

return {
	"sotte/presenting.nvim",

	cmd = { "Presenting", "PresentingStart", "PresentingStop", "PresentingToggle" },
	ft = { "markdown" },

	keys = {
		{ "<leader>vp", "<Cmd>Presenting<CR>", ft = { "markdown" }, desc = icons.ui.Play .. " Start presentation" },
		{ "<leader>vq", "<Cmd>PresentingStop<CR>", desc = icons.ui.BoldClose .. " Quit presentation" },
		{
			"<leader>vr",
			"<Cmd>PresentingStart<CR>",
			ft = { "markdown" },
			desc = icons.ui.Refresh .. " Resume presentation",
		},
		{
			"<leader>vt",
			"<Cmd>PresentingToggle<CR>",
			ft = { "markdown" },
			desc = icons.ui.Window .. " Toggle presenting mode",
		},
	},

	opts = {
		separator = {
			---@type string Lua pattern to detect slide boundaries
			markdown = "^#+ ",
		},

		options = {
			---@type integer Width of the presentation area in columns
			width = 80,

			footer = {
				---@type boolean Show slide number footer
				enabled = true,
				--- Format the footer text shown at the bottom of each slide.
				---@param slide_number integer Current slide number (1-based)
				---@param total_slides integer Total number of slides
				---@return string formatted Footer text
				text = function(slide_number, total_slides)
					return string.format("  %s  Slide %d / %d  ", icons.ui.Play, slide_number, total_slides)
				end,
			},
		},

		--- Configure callback called when entering presentation mode.
		--- Saves all relevant UI options, applies presentation-optimized
		--- settings, and returns a cleanup function that restores everything.
		---@return fun() cleanup Function to restore saved UI state
		configure = function()
			---@type PresentingSavedState
			local saved = {
				showtabline = vim.o.showtabline,
				laststatus = vim.o.laststatus,
				cmdheight = vim.o.cmdheight,
				number = vim.wo.number,
				relativenumber = vim.wo.relativenumber,
				signcolumn = vim.wo.signcolumn,
				colorcolumn = vim.wo.colorcolumn,
				foldcolumn = vim.wo.foldcolumn,
				cursorline = vim.wo.cursorline,
				wrap = vim.wo.wrap,
				linebreak = vim.wo.linebreak,
				conceallevel = vim.wo.conceallevel,
				spell = vim.wo.spell,
			}

			-- Apply full-immersion presentation settings
			vim.o.showtabline = 0
			vim.o.laststatus = 0
			vim.o.cmdheight = 0
			vim.wo.number = false
			vim.wo.relativenumber = false
			vim.wo.signcolumn = "no"
			vim.wo.colorcolumn = ""
			vim.wo.foldcolumn = "0"
			vim.wo.cursorline = false
			vim.wo.wrap = true
			vim.wo.linebreak = true
			vim.wo.conceallevel = 2
			vim.wo.spell = false

			-- Disable mini.* modules in presentation buffer
			vim.b.minicursorword_disable = true
			vim.b.minitrailspace_disable = true
			vim.b.miniindentscope_disable = true

			vim.notify(
				icons.ui.Play .. "  Presentation started — n/p to navigate, q to quit",
				vim.log.levels.INFO,
				{ title = icons.ui.Play .. "  Presenting" }
			)

			--- Cleanup function: restores all saved UI state.
			---@return nil
			return function()
				vim.o.showtabline = saved.showtabline
				vim.o.laststatus = saved.laststatus
				vim.o.cmdheight = saved.cmdheight
				vim.wo.number = saved.number
				vim.wo.relativenumber = saved.relativenumber
				vim.wo.signcolumn = saved.signcolumn
				vim.wo.colorcolumn = saved.colorcolumn
				vim.wo.foldcolumn = saved.foldcolumn
				vim.wo.cursorline = saved.cursorline
				vim.wo.wrap = saved.wrap
				vim.wo.linebreak = saved.linebreak
				vim.wo.conceallevel = saved.conceallevel
				vim.wo.spell = saved.spell

				vim.notify(
					icons.ui.Check .. "  Presentation ended",
					vim.log.levels.INFO,
					{ title = icons.ui.Play .. "  Presenting" }
				)
			end
		end,
	},

	---@param _ table Plugin spec (unused)
	---@param opts table Resolved options
	config = function(_, opts)
		require("presenting").setup(opts)

		-- ── Which-key group ──────────────────────────────────────────
		local ok, wk = pcall(require, "which-key")
		if ok then
			wk.add({
				{ "<leader>v", group = icons.ui.Play .. " Presentation", icon = { icon = icons.ui.Play, color = "green" } },
			})
		end

		-- ── Disable mini.* in presenting filetype ────────────────────
		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("NvimEnterprise_Presenting", { clear = true }),
			pattern = "presenting",
			desc = "Configure presenting buffer: unlist + disable mini modules",
			---@param event table Autocmd event data with `buf` field
			callback = function(event)
				vim.bo[event.buf].buflisted = false
				vim.b[event.buf].minicursorword_disable = true
				vim.b[event.buf].minitrailspace_disable = true
				vim.b[event.buf].miniindentscope_disable = true
			end,
		})
	end,
}
