---@file lua/config/colorscheme_manager.lua
---@description ColorschemeManager — colorscheme lifecycle, specs, and hot-swap
---@module "config.colorscheme_manager"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see config.plugin_manager Plugin spec collector (calls :specs())
---@see config.settings_manager Settings manager (calls :apply(), :register_commands())
---@see core.settings Settings provider (ui.colorscheme, colorschemes map)
---@see core.class OOP base class (Class:extend)
---@see core.logger Structured logging utility
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  config/colorscheme_manager.lua — Colorscheme lifecycle manager          ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  ColorschemeManager (singleton, Class-based)                     │    ║
--- ║  │                                                                  │    ║
--- ║  │  THEME_REGISTRY (26 colorschemes)                                │    ║
--- ║  │  │  Each entry defines:                                          │    ║
--- ║  │  │  ├─ module           Lua require() name                       │    ║
--- ║  │  │  ├─ deps?            Extra lazy.nvim dependencies             │    ║
--- ║  │  │  ├─ colorscheme_name String or fn(style) → vim cs name        │    ║
--- ║  │  │  ├─ setup?           fn(style, transparent, ...) → opts       │    ║
--- ║  │  │  └─ pre_setup?       fn(style, transparent, ...) → vim.g      │    ║
--- ║  │  │                                                               │    ║
--- ║  │  │  #1-5   The Giants                                            │    ║
--- ║  │  │  │  catppuccin, tokyonight, rose-pine, kanagawa,              │    ║
--- ║  │  │  │  gruvbox-material                                          │    ║
--- ║  │  │  #6-10  Modern Standards                                      │    ║
--- ║  │  │  │  everforest, nord, onedark-pro, nightfox,                  │    ║
--- ║  │  │  │  solarized-osaka                                           │    ║
--- ║  │  │  #11-15 Aesthetic & Thematic                                  │    ║
--- ║  │  │  │  dracula, github-theme, monokai-pro, cyberdream,           │    ║
--- ║  │  │  │  material                                                  │    ║
--- ║  │  │  #16-20 Emerging & Specialized                                │    ║
--- ║  │  │  │  bamboo, oxocarbon, melange, fluoromachine, vscode         │    ║
--- ║  │  │  #21-26 Honorable Mentions                                    │    ║
--- ║  │  │     night-owl, nightfly, zenbones, yorumi, gruvbox, shadow    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Lifecycle:                                                      │    ║
--- ║  │  ┌──────────┐    ┌─────────────┐    ┌──────────────────┐         │    ║
--- ║  │  │ specs()  │───▶│ Active: lazy│───▶│ config → apply() │         │    ║
--- ║  │  │          │    │ = false,    │    │ (eager load)      │        │    ║
--- ║  │  │          │    │ prio=1000   │    └──────────────────┘         │    ║
--- ║  │  │          │    ├─────────────┤                                 │    ║
--- ║  │  │          │───▶│ Others: lazy│    (available via picker)       │    ║
--- ║  │  │          │    │ = true,     │                                 │    ║
--- ║  │  │          │    │ prio=50     │                                 │    ║
--- ║  │  └──────────┘    └─────────────┘                                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  apply() pipeline:                                               │    ║
--- ║  │  ├─ Step 0: Set vim.o.background                                 │    ║
--- ║  │  ├─ Step 1: pre_setup (vim.g vars, background override)          │    ║
--- ║  │  ├─ Step 2: require(module).setup(opts)                          │    ║
--- ║  │  └─ Step 3: vim.cmd.colorscheme(resolved_name)                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  switch() pipeline:                                              │    ║
--- ║  │  ├─ Lazy-load plugin if not loaded yet                           │    ║
--- ║  │  ├─ Persist to settings.lua (survives restart)                   │    ║
--- ║  │  ├─ apply() immediately                                          │    ║
--- ║  │  └─ Notify user                                                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Commands:                                                       │    ║
--- ║  │  ├─ :ColorschemeSwitch   Interactive multi-step picker           │    ║
--- ║  │  ├─ :ColorschemeSet      Direct: name [style] [bg] [variant]     │    ║
--- ║  │  └─ :ColorschemeList     Show all with variants + active marker  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Only active colorscheme loaded eagerly (priority 1000)                ║
--- ║  • All others lazy = true (installed but not loaded until picked)        ║
--- ║  • Singleton pattern: one instance per session                           ║
--- ║  • switch() lazy-loads plugin on demand before applying                  ║
--- ║  • Fallback to habamax if colorscheme application fails                  ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local Class = require("core.class")
local Logger = require("core.logger")

local log = Logger:for_module("config.colorscheme_manager")

-- ═══════════════════════════════════════════════════════════════════════════
-- CLASS DEFINITION
-- ═══════════════════════════════════════════════════════════════════════════

---@class ColorschemeManager : Class
local ColorschemeManager = Class:extend("ColorschemeManager")

-- ═══════════════════════════════════════════════════════════════════════════
-- THEME REGISTRY
--
-- Maps theme name → configuration table. Each entry defines how to
-- set up the theme (module name, setup function, pre_setup for vim.g
-- variables, and colorscheme name resolution).
--
-- Themes that use vim.g for configuration (gruvbox-material, everforest,
-- nord, etc.) define pre_setup instead of (or in addition to) setup.
-- Themes with dynamic colorscheme names (kanagawa-wave, rose-pine-moon)
-- define colorscheme_name as a function of style.
-- ═══════════════════════════════════════════════════════════════════════════

--- Known theme configurations.
---
--- Each entry can define:
--- - `module`           : Lua module name for `require()`
--- - `deps`             : Extra lazy.nvim dependencies
--- - `colorscheme_name` : Actual vim colorscheme name (string or `fn(style) → string`)
--- - `setup`            : `fn(style, transparent, bg, variant) → opts table`
--- - `pre_setup`        : `fn(style, transparent, bg, variant)` — called before setup
---@type table<string, table>
ColorschemeManager.THEME_REGISTRY = {

	-- ── #1 Catppuccin — Latte / Frappé / Macchiato / Mocha ───────────
	catppuccin = {
		module = "catppuccin",
		---@param style string "latte"|"frappe"|"macchiato"|"mocha"
		---@param transparent boolean
		---@return table
		setup = function(style, transparent)
			return {
				flavour = (style ~= "" and style) or "mocha",
				transparent_background = transparent,
				term_colors = true,
				dim_inactive = { enabled = false, shade = "dark", percentage = 0.15 },
				styles = {
					comments = { "italic" },
					conditionals = { "italic" },
					keywords = { "bold" },
					functions = {},
					strings = {},
					variables = {},
				},
				integrations = {
					aerial = true,
					bufferline = true,
					cmp = true,
					dashboard = true,
					diffview = true,
					flash = true,
					gitsigns = true,
					indent_blankline = { enabled = true, scope_color = "lavender" },
					lsp_trouble = true,
					mason = true,
					mini = { enabled = true, indentscope_color = "lavender" },
					native_lsp = {
						enabled = true,
						underlines = {
							errors = { "undercurl" },
							hints = { "undercurl" },
							warnings = { "undercurl" },
							information = { "undercurl" },
						},
					},
					neotree = true,
					noice = true,
					notify = true,
					semantic_tokens = true,
					snacks = true,
					telescope = { enabled = true },
					treesitter = true,
					treesitter_context = true,
					which_key = true,
				},
			}
		end,
	},

	-- ── #2 Tokyo Night — Night / Storm / Moon / Day ──────────────────
	tokyonight = {
		module = "tokyonight",
		---@param style string "night"|"storm"|"moon"|"day"
		---@param transparent boolean
		---@return table
		setup = function(style, transparent)
			return {
				style = (style ~= "" and style) or "storm",
				transparent = transparent,
				terminal_colors = true,
				dim_inactive = false,
				lualine_bold = true,
				styles = {
					comments = { italic = true },
					keywords = { italic = true },
					functions = {},
					variables = {},
					sidebars = transparent and "transparent" or "dark",
					floats = transparent and "transparent" or "dark",
				},
				on_highlights = function(hl, c)
					hl.CursorLineNr = { fg = c.orange, bold = true }
				end,
			}
		end,
	},

	-- ── #3 Rosé Pine — Main / Moon / Dawn ────────────────────────────
	["rose-pine"] = {
		module = "rose-pine",
		---@param style string "main"|"moon"|"dawn"
		---@return string
		colorscheme_name = function(style)
			if style ~= "" and style ~= "main" then return "rose-pine-" .. style end
			return "rose-pine"
		end,
		---@param style string
		---@param transparent boolean
		---@return table
		setup = function(style, transparent)
			return {
				variant = (style ~= "" and style) or "auto",
				dark_variant = "main",
				dim_inactive_windows = false,
				extend_background_behind_borders = true,
				styles = {
					bold = true,
					italic = true,
					transparency = transparent,
				},
				highlight_groups = {
					CursorLineNr = { fg = "gold", bold = true },
					StatusLine = { fg = "love", bg = "love", blend = 10 },
				},
			}
		end,
	},

	-- ── #4 Kanagawa — Wave / Dragon / Lotus ──────────────────────────
	kanagawa = {
		module = "kanagawa",
		---@param style string "wave"|"dragon"|"lotus"
		---@return string
		colorscheme_name = function(style)
			if style ~= "" then return "kanagawa-" .. style end
			return "kanagawa"
		end,
		---@param style string
		---@param transparent boolean
		---@return table
		setup = function(style, transparent)
			return {
				compile = false,
				undercurl = true,
				commentStyle = { italic = true },
				functionStyle = {},
				keywordStyle = { italic = true },
				statementStyle = { bold = true },
				typeStyle = {},
				transparent = transparent,
				dimInactive = false,
				terminalColors = true,
				theme = (style ~= "" and style) or "wave",
				colors = { theme = {} },
				overrides = function()
					return {}
				end,
			}
		end,
	},

	-- ── #5 Gruvbox Material — Hard/Medium/Soft × Dark/Light ──────────
	["gruvbox-material"] = {
		module = "gruvbox-material",
		---@return string
		colorscheme_name = function()
			return "gruvbox-material"
		end,
		---@param style string "hard"|"medium"|"soft"
		---@param transparent boolean
		---@param background string "dark"|"light"
		---@param variant string "material"|"mix"|"original"
		pre_setup = function(style, transparent, background, variant)
			vim.o.background = background or "dark"
			vim.g.gruvbox_material_background = (style ~= "" and style) or "medium"
			vim.g.gruvbox_material_foreground = (variant ~= "" and variant) or "material"
			vim.g.gruvbox_material_enable_bold = 1
			vim.g.gruvbox_material_enable_italic = 1
			vim.g.gruvbox_material_cursor = "auto"
			vim.g.gruvbox_material_transparent_background = transparent and 2 or 0
			vim.g.gruvbox_material_dim_inactive_windows = 0
			vim.g.gruvbox_material_visual = "grey"
			vim.g.gruvbox_material_diagnostic_text_highlight = 1
			vim.g.gruvbox_material_diagnostic_line_highlight = 1
			vim.g.gruvbox_material_diagnostic_virtual_text = "colored"
			vim.g.gruvbox_material_better_performance = 1
		end,
	},

	-- ── #6 Everforest — Hard/Medium/Soft × Dark/Light ────────────────
	everforest = {
		module = "everforest",
		---@return string
		colorscheme_name = function()
			return "everforest"
		end,
		---@param style string "hard"|"medium"|"soft"
		---@param transparent boolean
		---@param background string "dark"|"light"
		pre_setup = function(style, transparent, background)
			vim.o.background = background or "dark"
			vim.g.everforest_background = (style ~= "" and style) or "medium"
			vim.g.everforest_enable_italic = 1
			vim.g.everforest_cursor = "auto"
			vim.g.everforest_transparent_background = transparent and 2 or 0
			vim.g.everforest_dim_inactive_windows = 0
			vim.g.everforest_diagnostic_text_highlight = 1
			vim.g.everforest_diagnostic_line_highlight = 1
			vim.g.everforest_diagnostic_virtual_text = "colored"
			vim.g.everforest_better_performance = 1
		end,
	},

	-- ── #7 Nord — Default (dark only) ────────────────────────────────
	nord = {
		module = "nord",
		---@param _ string (unused — single variant)
		---@param transparent boolean
		pre_setup = function(_, transparent)
			vim.g.nord_contrast = true
			vim.g.nord_borders = true
			vim.g.nord_disable_background = transparent
			vim.g.nord_italic = true
			vim.g.nord_uniform_diff_background = true
			vim.g.nord_bold = true
		end,
		---@return table
		setup = function()
			return {}
		end,
	},

	-- ── #8 OneDark Pro — Onedark / Onelight / Vivid / Dark ──────────
	["onedark-pro"] = {
		module = "onedarkpro",
		---@param style string "onedark"|"onelight"|"onedark_vivid"|"onedark_dark"
		---@return string
		colorscheme_name = function(style)
			return (style ~= "" and style) or "onedark"
		end,
		---@param style string
		---@param transparent boolean
		---@return table
		setup = function(style, transparent)
			return {
				colors = {},
				highlights = {},
				styles = {
					types = "NONE",
					methods = "NONE",
					numbers = "NONE",
					strings = "NONE",
					comments = "italic",
					keywords = "bold,italic",
					constants = "NONE",
					functions = "NONE",
					operators = "NONE",
					variables = "NONE",
					parameters = "NONE",
					conditionals = "italic",
					virtual_text = "NONE",
				},
				options = {
					cursorline = true,
					transparency = transparent,
					lualine_transparency = false,
					highlight_inactive_windows = false,
				},
			}
		end,
	},

	-- ── #9 Nightfox — Nightfox/Dayfox/Dawnfox/Duskfox/etc. ──────────
	nightfox = {
		module = "nightfox",
		---@param style string "nightfox"|"dayfox"|"dawnfox"|"duskfox"|"nordfox"|"terafox"|"carbonfox"
		---@return string
		colorscheme_name = function(style)
			return (style ~= "" and style) or "nightfox"
		end,
		---@param style string
		---@param transparent boolean
		---@return table
		setup = function(style, transparent)
			return {
				options = {
					compile_path = vim.fn.stdpath("cache") .. "/nightfox",
					compile_file_suffix = "_compiled",
					transparent = transparent,
					terminal_colors = true,
					dim_inactive = false,
					module_default = true,
					styles = {
						comments = "italic",
						conditionals = "NONE",
						constants = "NONE",
						functions = "NONE",
						keywords = "bold",
						numbers = "NONE",
						operators = "NONE",
						strings = "NONE",
						types = "italic,bold",
						variables = "NONE",
					},
					inverse = {
						match_paren = false,
						visual = false,
						search = true,
					},
				},
				palettes = {},
				specs = {},
				groups = {},
			}
		end,
	},

	-- ── #10 Solarized Osaka — Dark / Light ───────────────────────────
	["solarized-osaka"] = {
		module = "solarized-osaka",
		---@param _ string (unused — controlled by vim.o.background)
		---@param transparent boolean
		---@return table
		setup = function(_, transparent)
			return {
				transparent = transparent,
				terminal_colors = true,
				dim_inactive = false,
				lualine_bold = true,
				styles = {
					comments = { italic = true },
					keywords = { italic = true },
					functions = {},
					variables = {},
					sidebars = transparent and "transparent" or "dark",
					floats = transparent and "transparent" or "dark",
				},
				sidebars = { "qf", "help", "terminal", "packer" },
				day_brightness = 0.3,
				on_highlights = function() end,
			}
		end,
	},

	-- ── #11 Dracula — Default / Soft ─────────────────────────────────
	dracula = {
		module = "dracula",
		---@param style string "dracula"|"dracula-soft"|"soft"
		---@return string
		colorscheme_name = function(style)
			if style == "soft" or style == "dracula-soft" then return "dracula-soft" end
			return "dracula"
		end,
		---@param _ string
		---@param transparent boolean
		---@return table
		setup = function(_, transparent)
			return {
				transparent_bg = transparent,
				show_end_of_buffer = true,
				lualine_bg_color = nil,
				italic_comment = true,
				overrides = {},
			}
		end,
	},

	-- ── #12 GitHub Theme — github_dark_* / github_light_* ────────────
	["github-theme"] = {
		module = "github-theme",
		---@param style string One of the github_ variants
		---@return string
		colorscheme_name = function(style)
			if style ~= "" then
				if not style:match("^github_") then return "github_" .. style end
				return style
			end
			return "github_dark"
		end,
		---@param _ string
		---@param transparent boolean
		---@return table
		setup = function(_, transparent)
			return {
				options = {
					compile_path = vim.fn.stdpath("cache") .. "/github-theme",
					compile_file_suffix = "_compiled",
					hide_end_of_buffer = true,
					hide_nc_statusline = true,
					transparent = transparent,
					terminal_colors = true,
					dim_inactive = false,
					module_default = true,
					styles = {
						comments = "italic",
						functions = "NONE",
						keywords = "bold",
						variables = "NONE",
						conditionals = "NONE",
						constants = "NONE",
						numbers = "NONE",
						operators = "NONE",
						strings = "NONE",
						types = "NONE",
					},
					inverse = {
						match_paren = false,
						visual = false,
						search = false,
					},
					darken = {
						floats = false,
						sidebars = {
							enable = true,
							list = {},
						},
					},
				},
				palettes = {},
				specs = {},
				groups = {},
			}
		end,
	},

	-- ── #13 Monokai Pro — Classic/Octagon/Pro/Machine/etc. ───────────
	["monokai-pro"] = {
		module = "monokai",
		---@return string
		colorscheme_name = function()
			return "monokai"
		end,
		---@param _ string
		---@param transparent boolean
		---@return table
		setup = function(_, transparent)
			return {
				transparent_background = transparent,
				terminal_colors = true,
				devicons = true,
				italic_comments = true,
			}
		end,
	},

	-- ── #14 Cyberdream — Dark / Light ────────────────────────────────
	cyberdream = {
		module = "cyberdream",
		---@param style string "dark"|"light"
		---@param transparent boolean
		---@return table
		setup = function(style, transparent)
			local is_light = (style == "light")
			return {
				transparent = transparent,
				italic_comments = true,
				hide_fillchars = false,
				borderless_telescope = true,
				terminal_colors = true,
				theme = {
					variant = is_light and "light" or "default",
				},
			}
		end,
	},

	-- ── #15 Material — Darker/Lighter/Oceanic/Palenight/Deep Ocean ───
	material = {
		module = "material",
		---@return string
		colorscheme_name = function()
			return "material"
		end,
		---@param style string "darker"|"lighter"|"oceanic"|"palenight"|"deep ocean"
		pre_setup = function(style)
			vim.g.material_style = (style ~= "" and style) or "deep ocean"
		end,
		---@param _ string
		---@param transparent boolean
		---@return table
		setup = function(_, transparent)
			return {
				contrast = {
					terminal = false,
					sidebars = false,
					floating_windows = false,
					cursor_line = false,
					non_current_windows = false,
					filetypes = {},
				},
				styles = {
					comments = { italic = true },
					strings = {},
					keywords = { bold = true },
					functions = {},
					variables = {},
					operators = {},
					types = {},
				},
				plugins = {
					"dap",
					"dashboard",
					"gitsigns",
					"indent-blankline",
					"mini",
					"neotree",
					"noice",
					"nvim-cmp",
					"mini.icons",
					"telescope",
					"trouble",
					"which-key",
				},
				disable = {
					colored_cursor = false,
					borders = false,
					background = transparent,
					term_colors = false,
					eob_lines = false,
				},
				lualine_style = "default",
			}
		end,
	},

	-- ── #16 Bamboo — Vulgaris / Multiplex / Light ────────────────────
	bamboo = {
		module = "bamboo",
		---@param style string "vulgaris"|"multiplex"|"light"
		---@return string
		colorscheme_name = function(style)
			if style ~= "" and style ~= "vulgaris" then return "bamboo-" .. style end
			return "bamboo"
		end,
		---@param style string
		---@param transparent boolean
		---@return table
		setup = function(style, transparent)
			return {
				style = (style ~= "" and style) or "vulgaris",
				transparent = transparent,
				dim_inactive = false,
				term_colors = true,
				ending_tildes = false,
				code_style = {
					comments = { italic = true },
					conditionals = { italic = true },
					keywords = {},
					functions = {},
					namespaces = { italic = true },
					parameters = { italic = true },
					strings = {},
					variables = {},
				},
				lualine = { transparent = transparent },
				diagnostics = {
					darker = true,
					undercurl = true,
					background = true,
				},
			}
		end,
	},

	-- ── #17 Oxocarbon — Dark / Light (IBM Carbon) ────────────────────
	oxocarbon = {
		module = "oxocarbon",
		---@return string
		colorscheme_name = function()
			return "oxocarbon"
		end,
		---@param _ string (unused)
		---@param _ boolean (unused)
		---@param background string "dark"|"light"
		pre_setup = function(_, _, background)
			vim.o.background = background or "dark"
		end,
	},

	-- ── #18 Melange — Dark / Light ───────────────────────────────────
	melange = {
		module = "melange",
		---@return string
		colorscheme_name = function()
			return "melange"
		end,
		---@param _ string (unused)
		---@param _ boolean (unused)
		---@param background string "dark"|"light"
		pre_setup = function(_, _, background)
			vim.o.background = background or "dark"
		end,
	},

	-- ── #19 Fluoromachine — Fluoromachine / Retrowave / Delta ────────
	fluoromachine = {
		module = "fluoromachine",
		---@param style string "fluoromachine"|"retrowave"|"delta"
		---@param transparent boolean
		---@return table
		setup = function(style, transparent)
			return {
				glow = true,
				brightness = 0.05,
				theme = (style ~= "" and style) or "fluoromachine",
				transparent = transparent and "full" or false,
			}
		end,
	},

	-- ── #20 VSCode — Dark+ / Light+ ─────────────────────────────────
	vscode = {
		module = "vscode",
		---@return string
		colorscheme_name = function()
			return "vscode"
		end,
		---@param _ string
		---@param _ boolean
		---@param background string "dark"|"light"
		pre_setup = function(_, _, background)
			vim.o.background = background or "dark"
		end,
		---@param _ string
		---@param transparent boolean
		---@return table
		setup = function(_, transparent)
			return {
				transparent = transparent,
				italic_comments = true,
				underline_links = true,
				disable_nvimtree_bg = transparent,
				color_overrides = {},
				group_overrides = {},
			}
		end,
	},

	-- ── #21 Night Owl — Dark / Light ─────────────────────────────────
	["night-owl"] = {
		module = "night-owl",
		---@param style string "dark"|"light"
		---@return string
		colorscheme_name = function(style)
			if style == "light" then return "night-owl-light" end
			return "night-owl"
		end,
		---@param _ string
		---@param transparent boolean
		---@return table
		setup = function(_, transparent)
			return {
				bold = true,
				italics = true,
				underline = true,
				undercurl = true,
				transparent_background = transparent,
			}
		end,
	},

	-- ── #22 Nightfly — Default (dark only) ───────────────────────────
	nightfly = {
		module = "nightfly",
		---@return string
		colorscheme_name = function()
			return "nightfly"
		end,
		---@param _ string (unused — single variant)
		---@param transparent boolean
		pre_setup = function(_, transparent)
			vim.g.nightflyTransparent = transparent
			vim.g.nightflyCursorColor = true
			vim.g.nightflyItalics = true
			vim.g.nightflyNormalFloat = true
			vim.g.nightflyTerminalColors = true
			vim.g.nightflyUndercurls = true
			vim.g.nightflyUnderlineMatchParen = false
			vim.g.nightflyVirtualTextColor = true
		end,
	},

	-- ── #23 Zenbones — Collection (requires lush.nvim) ───────────────
	zenbones = {
		module = "zenbones",
		deps = { "rktjmp/lush.nvim" },
		---@param style string Variant name from the zenbones family
		---@return string
		colorscheme_name = function(style)
			return (style ~= "" and style) or "zenbones"
		end,
		---@param style string
		---@param transparent boolean
		pre_setup = function(style, transparent)
			local base = (style ~= "" and style) or "zenbones"
			vim.g[base] = vim.tbl_extend("force", vim.g[base] or {}, {
				transparent_background = transparent,
				italic_comments = true,
				darken_noncurrent_window = false,
			})
		end,
	},

	-- ── #24 Yorumi — Yorumi / Abyss ─────────────────────────────────
	yorumi = {
		module = "yorumi",
		---@return string
		colorscheme_name = function()
			return "yorumi"
		end,
		---@param style string "yorumi"|"abyss"
		---@param transparent boolean
		---@return table
		setup = function(style, transparent)
			return {
				transparent = transparent,
				style = (style ~= "" and style) or "yorumi",
			}
		end,
	},

	-- ── #25 Gruvbox (classic) — Dark / Light ─────────────────────────
	gruvbox = {
		module = "gruvbox",
		---@return string
		colorscheme_name = function()
			return "gruvbox"
		end,
		---@param _ string
		---@param _ boolean
		---@param background string "dark"|"light"
		pre_setup = function(_, _, background)
			vim.o.background = background or "dark"
		end,
		---@param style string contrast: "hard"|"soft"|""
		---@param transparent boolean
		---@return table
		setup = function(style, transparent)
			return {
				terminal_colors = true,
				undercurl = true,
				underline = true,
				bold = true,
				italic = {
					strings = true,
					emphasis = true,
					comments = true,
					operators = false,
					folds = true,
				},
				strikethrough = true,
				invert_selection = false,
				invert_signs = false,
				invert_tabline = false,
				invert_intend_guides = false,
				inverse = true,
				contrast = (style ~= "" and style) or "",
				palette_overrides = {},
				overrides = {},
				dim_inactive = false,
				transparent_mode = transparent,
			}
		end,
	},

	-- ── #26 Shadow — Default (dark only, minimalist) ─────────────────
	shadow = {
		module = "shadow",
		---@return string
		colorscheme_name = function()
			return "shadow"
		end,
		---@param _ string (unused — single variant)
		---@param transparent boolean
		---@return table
		setup = function(_, transparent)
			return {
				transparent = transparent,
			}
		end,
	},
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTRUCTOR
-- ═══════════════════════════════════════════════════════════════════════════

--- Initialize the ColorschemeManager instance.
---@return nil
function ColorschemeManager:init()
	self._settings = require("core.settings")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INTERNAL HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Get the active colorscheme info from settings.
---@return string name Theme key (e.g. "catppuccin")
---@return string style Style variant (e.g. "mocha")
---@return boolean transparent Whether transparent background is enabled
---@return string background "dark" or "light"
---@return string variant Secondary style option (e.g. "material" for gruvbox-material)
---@private
function ColorschemeManager:_active_theme_info()
	local name = self._settings:get("ui.colorscheme", "habamax")
	local style = self._settings:get("ui.colorscheme_style", "")
	local transparent = self._settings:get("ui.transparent_background", false)
	local background = self._settings:get("ui.background", "dark")
	local variant = self._settings:get("ui.colorscheme_variant", "")
	return name, style, transparent, background, variant
end

--- Resolve the actual vim colorscheme name for a given theme.
---
--- Some themes have dynamic names based on style (e.g., kanagawa-wave,
--- rose-pine-moon). This function handles both static and dynamic names.
---@param name string Theme key from settings
---@param style string Style variant
---@return string colorscheme_name Name to pass to `vim.cmd.colorscheme()`
---@private
function ColorschemeManager:_resolve_colorscheme_name(name, style)
	local registry = self.THEME_REGISTRY[name]
	if registry and registry.colorscheme_name then
		if type(registry.colorscheme_name) == "function" then return registry.colorscheme_name(style) end
		return registry.colorscheme_name
	end
	return name
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SPEC GENERATION
--
-- Generates lazy.nvim plugin specs for all configured colorschemes.
-- The active colorscheme is loaded eagerly (lazy=false, priority=1000)
-- with a config function that calls apply(). All others are lazy=true
-- (installed but not loaded until picked via :ColorschemeSwitch).
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate lazy.nvim specs for all configured colorschemes.
---
--- The active colorscheme gets `lazy = false` and `priority = 1000`
--- so it loads immediately during startup. All others get `lazy = true`
--- and `priority = 50` (available via picker or command).
---@return table[] specs List of lazy.nvim plugin specs
function ColorschemeManager:specs()
	local specs = {}
	local active_name = self:_active_theme_info()
	local colorschemes = self._settings:get("colorschemes", {})

	for name, repo in pairs(colorschemes) do
		local is_active = (name == active_name)
		local registry = self.THEME_REGISTRY[name]
		local deps = (registry and registry.deps) or nil

		local spec = {
			repo,
			name = name,
			lazy = not is_active,
			priority = is_active and 1000 or 50,
			dependencies = deps,
		}

		-- Active theme gets a config function that applies it on load
		if is_active then spec.config = function()
			self:apply()
		end end

		table.insert(specs, spec)
		log:debug("Colorscheme spec: %s (%s) [%s]", name, repo, is_active and "ACTIVE" or "lazy")
	end

	if #specs == 0 then log:info("No colorschemes configured — using built-in 'habamax'") end

	return specs
end

-- ═══════════════════════════════════════════════════════════════════════════
-- APPLY
--
-- Executes the full colorscheme setup pipeline:
-- Step 0: Set vim.o.background
-- Step 1: pre_setup (vim.g vars, background overrides)
-- Step 2: require(module).setup(opts) if available
-- Step 3: vim.cmd.colorscheme(resolved_name) with habamax fallback
-- ═══════════════════════════════════════════════════════════════════════════

--- Apply (or re-apply) the active colorscheme.
---
--- Calls pre_setup (vim.g vars), then setup(), then sets the
--- colorscheme. Falls back to habamax if application fails.
---@return nil
function ColorschemeManager:apply()
	local name, style, transparent, background, variant = self:_active_theme_info()
	local registry = self.THEME_REGISTRY[name]

	-- ── Step 0: Set vim.o.background globally ────────────────────────
	vim.o.background = background

	-- ── Step 1: pre_setup (vim.g variables, etc.) ────────────────────
	if registry and registry.pre_setup then
		registry.pre_setup(style, transparent, background, variant)
		log:debug("Pre-setup completed for '%s'", name)
	end

	-- ── Step 2: Call theme setup() if available ──────────────────────
	if registry and registry.setup then
		local module_name = registry.module or name
		local ok, theme_mod = pcall(require, module_name)
		if ok and type(theme_mod) == "table" and theme_mod.setup then
			local opts = registry.setup(style, transparent, background, variant)
			theme_mod.setup(opts)
			log:debug("Configured theme '%s' (style=%s, bg=%s, variant=%s)", name, style, background, variant)
		elseif not ok then
			log:warn("Could not require module '%s': %s", module_name, theme_mod)
		end
	end

	-- ── Step 3: Resolve name and apply ───────────────────────────────
	local cs_name = self:_resolve_colorscheme_name(name, style)
	local ok, err = pcall(vim.cmd.colorscheme, cs_name)
	if not ok then
		log:warn("Failed to apply colorscheme '%s': %s — falling back to habamax", cs_name, err)
		vim.cmd.colorscheme("habamax")
	else
		log:info(
			"Applied colorscheme: %s (style=%s, bg=%s, variant=%s, transparent=%s)",
			cs_name,
			style,
			background,
			variant,
			tostring(transparent)
		)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SWITCH (runtime hot-swap)
--
-- Switches to a different colorscheme at runtime:
-- 1. Lazy-loads the plugin if not loaded yet
-- 2. Persists the change to settings.lua (survives restart)
-- 3. Applies immediately via apply()
-- 4. Notifies the user
-- ═══════════════════════════════════════════════════════════════════════════

--- Switch to a different colorscheme at runtime.
---
--- Persists the change to `settings.lua` so it survives restart.
--- If the target colorscheme plugin is lazy-loaded, it is loaded
--- on demand before applying.
---@param name string Theme name (must be a key in `settings.colorschemes`)
---@param style? string Optional style/variant
---@param background? string Optional "dark" or "light"
---@param variant? string Optional secondary variant
---@return nil
function ColorschemeManager:switch(name, style, background, variant)
	local colorschemes = self._settings:get("colorschemes", {})
	if not colorschemes[name] then
		log:warn("Colorscheme '%s' is not in the configured list", name)
		pcall(vim.cmd.colorscheme, name)
		return
	end

	-- ── Lazy-load plugin if needed ───────────────────────────────────
	local lazy_ok, lazy_config = pcall(require, "lazy.core.config")
	if lazy_ok and lazy_config and lazy_config.plugins then
		for _, plugin in pairs(lazy_config.plugins) do
			if plugin.name == name and not plugin._.loaded then
				require("lazy").load({ plugins = { name } })
				log:debug("Lazy-loaded colorscheme plugin: %s", name)
				break
			end
		end
	end

	-- ── Persist to settings.lua ──────────────────────────────────────
	self._settings:persist("ui.colorscheme", name)
	self._settings:persist("ui.colorscheme_style", style or "")
	self._settings:persist("ui.background", background or "dark")
	self._settings:persist("ui.colorscheme_variant", variant or "")

	-- ── Apply immediately ────────────────────────────────────────────
	self:apply()

	-- ── Notify ───────────────────────────────────────────────────────
	local parts = { name }
	if style and style ~= "" then table.insert(parts, style) end
	if background and background ~= "" and background ~= "dark" then table.insert(parts, background) end
	if variant and variant ~= "" then table.insert(parts, variant) end
	vim.notify("🎨 Colorscheme: " .. table.concat(parts, " → "), vim.log.levels.INFO, { title = "NvimEnterprise" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- QUERIES
-- ═══════════════════════════════════════════════════════════════════════════

--- Get sorted list of available colorscheme names.
---@return string[] names Sorted list of configured colorscheme keys
function ColorschemeManager:available()
	local names = {}
	local colorschemes = self._settings:get("colorschemes", {})
	for name, _ in pairs(colorschemes) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

--- Get available variants for a given colorscheme.
---@param name string Colorscheme name
---@return table|nil info Table with `styles`, `backgrounds`, `variants` fields (or nil)
function ColorschemeManager:variant_info(name)
	--stylua: ignore start
	local info = {
		["catppuccin"]       = { styles = { "latte", "frappe", "macchiato", "mocha" } },
		["tokyonight"]       = { styles = { "night", "storm", "moon", "day" } },
		["rose-pine"]        = { styles = { "main", "moon", "dawn" } },
		["kanagawa"]         = { styles = { "wave", "dragon", "lotus" } },
		["gruvbox-material"] = { styles = { "hard", "medium", "soft" }, backgrounds = { "dark", "light" }, variants = { "material", "mix", "original" } },
		["everforest"]       = { styles = { "hard", "medium", "soft" }, backgrounds = { "dark", "light" } },
		["nord"]             = { styles = { "default" } },
		["onedark-pro"]      = { styles = { "onedark", "onelight", "onedark_vivid", "onedark_dark" } },
		["nightfox"]         = { styles = { "nightfox", "dayfox", "dawnfox", "duskfox", "nordfox", "terafox", "carbonfox" } },
		["solarized-osaka"]  = { backgrounds = { "dark", "light" } },
		["dracula"]          = { styles = { "dracula", "dracula-soft" } },
		["github-theme"]     = { styles = { "github_dark", "github_dark_default", "github_dark_dimmed", "github_dark_high_contrast", "github_dark_colorblind", "github_dark_tritanopia", "github_light", "github_light_default", "github_light_high_contrast", "github_light_colorblind", "github_light_tritanopia" } },
		["monokai-pro"]      = { styles = { "classic", "octagon", "pro", "machine", "ristretto", "spectrum" } },
		["cyberdream"]       = { styles = { "dark", "light" } },
		["material"]         = { styles = { "darker", "lighter", "oceanic", "palenight", "deep ocean" } },
		["bamboo"]           = { styles = { "vulgaris", "multiplex", "light" } },
		["oxocarbon"]        = { backgrounds = { "dark", "light" } },
		["melange"]          = { backgrounds = { "dark", "light" } },
		["fluoromachine"]    = { styles = { "fluoromachine", "retrowave", "delta" } },
		["vscode"]           = { backgrounds = { "dark", "light" } },
		["night-owl"]        = { styles = { "dark", "light" } },
		["nightfly"]         = { styles = { "default" } },
		["zenbones"]         = { styles = { "zenbones", "zenwritten", "neobones", "vimbones", "rosebones", "forestbones", "nordbones", "tokyobones", "seoulbones", "duckbones", "zenburned", "kanagawabones" } },
		["yorumi"]           = { styles = { "yorumi", "abyss" } },
		["gruvbox"]          = { backgrounds = { "dark", "light" }, styles = { "", "hard", "soft" } },
		["shadow"]           = { styles = { "default" } },
	}
	--stylua: ignore end
	return info[name]
end

-- ═══════════════════════════════════════════════════════════════════════════
-- VIM COMMANDS
--
-- Three commands for colorscheme management:
-- :ColorschemeSwitch — Interactive multi-step picker (style → bg → variant)
-- :ColorschemeSet    — Direct switch with args
-- :ColorschemeList   — Display all available with active marker
-- ═══════════════════════════════════════════════════════════════════════════

--- Register colorscheme-related Vim commands.
---@return nil
function ColorschemeManager:register_commands()
	local manager = self

	-- ── :ColorschemeSwitch — Interactive picker ──────────────────────
	vim.api.nvim_create_user_command("ColorschemeSwitch", function()
		local cs_available = manager:available()
		local active_name = manager:_active_theme_info()

		local items = {}
		for _, n in ipairs(cs_available) do
			local prefix = (n == active_name) and "● " or "  "
			local cs_info = manager:variant_info(n)
			local detail = ""
			if cs_info and cs_info.styles then detail = " [" .. table.concat(cs_info.styles, ", ") .. "]" end
			table.insert(items, { name = n, display = prefix .. n .. detail })
		end

		vim.ui.select(items, {
			prompt = "🎨 Select Colorscheme:",
			format_item = function(item)
				return item.display
			end,
		}, function(choice)
			if not choice then return end
			local chosen_name = choice.name
			local cs_info = manager:variant_info(chosen_name)

			-- Style picker
			if cs_info and cs_info.styles and #cs_info.styles > 1 then
				vim.ui.select(cs_info.styles, {
					prompt = "🎨 " .. chosen_name .. " — Style:",
				}, function(chosen_style)
					if not chosen_style then
						manager:switch(chosen_name)
						return
					end

					-- Background picker
					if cs_info.backgrounds and #cs_info.backgrounds > 1 then
						vim.ui.select(cs_info.backgrounds, {
							prompt = "🎨 " .. chosen_name .. " — Background:",
						}, function(chosen_bg)
							if not chosen_bg then
								manager:switch(chosen_name, chosen_style)
								return
							end

							-- Variant picker
							if cs_info.variants and #cs_info.variants > 1 then
								vim.ui.select(cs_info.variants, {
									prompt = "🎨 " .. chosen_name .. " — Variant:",
								}, function(chosen_variant)
									manager:switch(chosen_name, chosen_style, chosen_bg, chosen_variant)
								end)
							else
								manager:switch(chosen_name, chosen_style, chosen_bg)
							end
						end)
					else
						manager:switch(chosen_name, chosen_style)
					end
				end)
			else
				manager:switch(chosen_name)
			end
		end)
	end, {
		nargs = 0,
		desc = "🎨 Interactive colorscheme picker",
	})

	-- ── :ColorschemeSet <name> [style] [bg] [variant] ────────────────
	vim.api.nvim_create_user_command("ColorschemeSet", function(cmd)
		local args = vim.split(vim.trim(cmd.args), "%s+")
		local cs_name = args[1]
		local cs_style = args[2]
		local cs_background = args[3]
		local cs_variant = args[4]

		if not cs_name or cs_name == "" then
			vim.notify(
				"Usage: :ColorschemeSet <name> [style] [bg] [variant]\n\n"
					.. "Examples:\n"
					.. "  :ColorschemeSet catppuccin mocha\n"
					.. "  :ColorschemeSet gruvbox-material soft dark original\n"
					.. "  :ColorschemeSet tokyonight storm\n\n"
					.. "Use :ColorschemeSwitch for interactive picker\n"
					.. "Use :ColorschemeList to see all options",
				vim.log.levels.INFO,
				{ title = "NvimEnterprise" }
			)
			return
		end

		manager:switch(cs_name, cs_style, cs_background, cs_variant)
	end, {
		nargs = "+",
		desc = "Set colorscheme: :ColorschemeSet <name> [style] [bg] [variant]",
	})

	-- ── :ColorschemeList — Show all with variants ────────────────────
	vim.api.nvim_create_user_command("ColorschemeList", function()
		local cs_available = manager:available()
		local active_cs, active_style, _, active_bg, active_variant = manager:_active_theme_info()
		local lines = {}
		for _, n in ipairs(cs_available) do
			local prefix = (n == active_cs) and "  ● " or "  ○ "
			local cs_info = manager:variant_info(n)
			local detail_parts = {}
			if cs_info then
				if cs_info.styles then table.insert(detail_parts, "styles: " .. table.concat(cs_info.styles, " | ")) end
				if cs_info.backgrounds then table.insert(detail_parts, "bg: " .. table.concat(cs_info.backgrounds, " | ")) end
				if cs_info.variants then table.insert(detail_parts, "variant: " .. table.concat(cs_info.variants, " | ")) end
			end
			local detail = #detail_parts > 0 and (" [" .. table.concat(detail_parts, "; ") .. "]") or ""
			local active_marker = ""
			if n == active_cs then
				local current_parts = {}
				if active_style ~= "" then table.insert(current_parts, active_style) end
				if active_bg ~= "" and active_bg ~= "dark" then table.insert(current_parts, active_bg) end
				if active_variant ~= "" then table.insert(current_parts, active_variant) end
				if #current_parts > 0 then active_marker = " (current: " .. table.concat(current_parts, ", ") .. ")" end
			end
			table.insert(lines, prefix .. n .. detail .. active_marker)
		end
		vim.notify(
			"Available colorschemes:\n" .. table.concat(lines, "\n"),
			vim.log.levels.INFO,
			{ title = "NvimEnterprise Colorschemes" }
		)
	end, {
		nargs = 0,
		desc = "List all colorschemes with variants",
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SINGLETON
--
-- Only one ColorschemeManager instance exists per session. The singleton
-- is created on first require and reused thereafter.
-- ═══════════════════════════════════════════════════════════════════════════

---@type ColorschemeManager
local _instance

--- Get or create the singleton ColorschemeManager instance.
---@return ColorschemeManager instance The singleton instance
local function get_instance()
	if not _instance then
		---@diagnostic disable-next-line: assign-type-mismatch
		_instance = ColorschemeManager:new()
	end
	return _instance
end

return get_instance()
