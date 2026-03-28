---@file lua/plugins/editor/dial.lua
---@description Dial.nvim — enhanced increment/decrement with custom augend groups
---@module "plugins.editor.dial"
---@version 1.0.0
---@since 2026-03
---@see https://github.com/monaqa/dial.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/dial.lua — Smart increment/decrement                     ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  dial.nvim                                                       │    ║
--- ║  │  ├─ Augend groups (what can be incremented/decremented)          │    ║
--- ║  │  │  ├─ default       All filetypes (numbers, booleans, dates)    │    ║
--- ║  │  │  ├─ typescript    JS/TS-specific (===, let/const, ||/&&)      │    ║
--- ║  │  │  ├─ python        Python-specific (True/False, and/or)        │    ║
--- ║  │  │  ├─ lua           Lua-specific (true/false, ~=, and/or)       │    ║
--- ║  │  │  ├─ rust          Rust-specific (i32/u32/f64..., mut)         │    ║
--- ║  │  │  ├─ css           CSS-specific (units, positions)             │    ║
--- ║  │  │  ├─ markdown      Markdown-specific (headers, checkboxes)     │    ║
--- ║  │  │  └─ yaml          YAML-specific (true/false, on/off)          │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Keymaps                                                      │    ║
--- ║  │  │  ┌────────────┬──────────────────────────────────────────┐    │    ║
--- ║  │  │  │ Key        │ Action                                   │    │    ║
--- ║  │  │  ├────────────┼──────────────────────────────────────────┤    │    ║
--- ║  │  │  │ <C-a>      │ Increment (replaces default)             │    │    ║
--- ║  │  │  │ <C-x>      │ Decrement (replaces default)             │    │    ║
--- ║  │  │  │ g<C-a>     │ Increment additive (visual: sequencing)  │    │    ║
--- ║  │  │  │ g<C-x>     │ Decrement additive (visual: sequencing)  │    │    ║
--- ║  │  │  └────────────┴──────────────────────────────────────────┘    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  │  NOTE: <C-a> was previously "Select all" — relocated to       │    ║
--- ║  │  │  <leader>A to free <C-a> for increment (standard Vim).        │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ Per-filetype augend groups (no CSS cycling in Rust files)    │    ║
--- ║  │  ├─ Additive mode for visual sequences (1,2,3... from selection) │    ║
--- ║  │  ├─ Semver support (1.2.3 → 1.2.4 / 1.3.0 / 2.0.0)               │    ║
--- ║  │  ├─ Date cycling in multiple formats (ISO, US, EU)               │    ║
--- ║  │  ├─ Boolean word boundaries (won't match "falsehood")            │    ║
--- ║  │  └─ keys event loading (zero cost until first use)               │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("dial") then return {} end

-- ═══════════════════════════════════════════════════════════════════════
-- AUGEND BUILDER
--
-- Builds all augend groups at config time (deferred require).
-- Organized by filetype for targeted cycling behavior.
-- ═══════════════════════════════════════════════════════════════════════

--- Build augend group definitions.
---
--- Called at config time to defer `require("dial.augend")`.
--- Returns a table of named groups, each containing a list of augends
--- appropriate for specific filetypes or as defaults.
---
---@return table<string, table[]> groups Named augend group lists
---@private
local function build_augend_groups()
	local augend = require("dial.augend")

	-- ── Shared augends (included in most groups) ─────────────────────
	local common = {
		-- Numbers
		augend.integer.alias.decimal_int, -- 0, 1, -1, 42
		augend.integer.alias.hex, -- 0x1a, 0xFF
		augend.integer.alias.octal, -- 0o77
		augend.integer.alias.binary, -- 0b1010

		-- Booleans (word boundary aware)
		augend.constant.new({
			elements = { "true", "false" },
			word = true,
			cyclic = true,
		}),
		augend.constant.new({
			elements = { "yes", "no" },
			word = true,
			cyclic = true,
		}),
		augend.constant.new({
			elements = { "on", "off" },
			word = true,
			cyclic = true,
		}),
		augend.constant.new({
			elements = { "enable", "disable" },
			word = true,
			cyclic = true,
		}),
		augend.constant.new({
			elements = { "enabled", "disabled" },
			word = true,
			cyclic = true,
		}),

		-- Dates
		augend.date.alias["%Y-%m-%d"], -- 2026-03-25
		augend.date.alias["%Y/%m/%d"], -- 2026/03/25
		augend.date.alias["%d/%m/%Y"], -- 25/03/2026
		augend.date.alias["%H:%M"], -- 14:30
		augend.date.alias["%H:%M:%S"], -- 14:30:00

		-- Days / months
		augend.constant.new({
			elements = {
				"Monday",
				"Tuesday",
				"Wednesday",
				"Thursday",
				"Friday",
				"Saturday",
				"Sunday",
			},
			word = true,
			cyclic = true,
		}),
		augend.constant.new({
			elements = {
				"January",
				"February",
				"March",
				"April",
				"May",
				"June",
				"July",
				"August",
				"September",
				"October",
				"November",
				"December",
			},
			word = true,
			cyclic = true,
		}),

		-- Semver
		augend.semver.alias.semver, -- 1.2.3

		-- Operators
		augend.constant.new({
			elements = { "&&", "||" },
			word = false,
			cyclic = true,
		}),
		augend.constant.new({
			elements = { "==", "!=" },
			word = false,
			cyclic = true,
		}),
		augend.constant.new({
			elements = { ">=", "<=" },
			word = false,
			cyclic = true,
		}),
		augend.constant.new({
			elements = { "++", "--" },
			word = false,
			cyclic = true,
		}),
	}

	-- ── Helper: extend common with extra augends ─────────────────────
	local function with(extras)
		local group = vim.deepcopy(common)
		for _, aug in ipairs(extras) do
			table.insert(group, aug)
		end
		return group
	end

	return {
		-- ── Default (all filetypes) ──────────────────────────────────
		default = common,

		-- ── TypeScript / JavaScript ──────────────────────────────────
		typescript = with({
			augend.constant.new({
				elements = { "let", "const" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "===", "!==" },
				word = false,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "public", "private", "protected" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "interface", "type" },
				word = true,
				cyclic = true,
			}),
		}),

		-- ── Python ───────────────────────────────────────────────────
		python = with({
			augend.constant.new({
				elements = { "True", "False" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "and", "or" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "is", "is not" },
				word = true,
				cyclic = true,
			}),
		}),

		-- ── Lua ──────────────────────────────────────────────────────
		lua = with({
			augend.constant.new({
				elements = { "and", "or" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "~=", "==" },
				word = false,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "local", "" },
				word = true,
				cyclic = true,
			}),
		}),

		-- ── Rust ─────────────────────────────────────────────────────
		rust = with({
			augend.constant.new({
				elements = { "i8", "i16", "i32", "i64", "i128", "isize" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "u8", "u16", "u32", "u64", "u128", "usize" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "f32", "f64" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "pub", "pub(crate)", "pub(super)" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "mut", "" },
				word = true,
				cyclic = true,
			}),
		}),

		-- ── Go ───────────────────────────────────────────────────────
		go = with({
			augend.constant.new({
				elements = { "int", "int8", "int16", "int32", "int64" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "uint", "uint8", "uint16", "uint32", "uint64" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "float32", "float64" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { ":=", "=" },
				word = false,
				cyclic = true,
			}),
		}),

		-- ── CSS / SCSS ───────────────────────────────────────────────
		css = with({
			augend.constant.new({
				elements = { "px", "em", "rem", "vh", "vw", "%" },
				word = false,
				cyclic = true,
			}),
			augend.constant.new({
				elements = {
					"top",
					"right",
					"bottom",
					"left",
					"center",
				},
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = {
					"flex-start",
					"flex-end",
					"center",
					"space-between",
					"space-around",
					"space-evenly",
				},
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "row", "column", "row-reverse", "column-reverse" },
				word = true,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "block", "inline", "inline-block", "flex", "grid", "none" },
				word = true,
				cyclic = true,
			}),
			augend.hexcolor.new({ case = "lower" }),
		}),

		-- ── Markdown ─────────────────────────────────────────────────
		markdown = with({
			augend.misc.alias.markdown_header, -- # → ## → ### ...
			augend.constant.new({
				elements = { "[ ]", "[x]" },
				word = false,
				cyclic = true,
			}),
		}),

		-- ── YAML / TOML ──────────────────────────────────────────────
		yaml = with({
			augend.constant.new({
				elements = { "True", "False" },
				word = true,
				cyclic = true,
			}),
		}),

		-- ── Shell ────────────────────────────────────────────────────
		shell = with({
			augend.constant.new({
				elements = { "-eq", "-ne", "-gt", "-lt", "-ge", "-le" },
				word = false,
				cyclic = true,
			}),
			augend.constant.new({
				elements = { "-f", "-d", "-e", "-r", "-w", "-x" },
				word = false,
				cyclic = true,
			}),
		}),
	}
end

-- ═══════════════════════════════════════════════════════════════════════
-- FILETYPE → GROUP MAPPING
--
-- Maps filetypes to their augend group name.
-- Filetypes not listed here use the "default" group.
-- ═══════════════════════════════════════════════════════════════════════

---@type table<string, string>
---@private
local FT_GROUP_MAP = {
	javascript = "typescript",
	javascriptreact = "typescript",
	typescript = "typescript",
	typescriptreact = "typescript",
	["javascript.jsx"] = "typescript",
	["typescript.tsx"] = "typescript",
	vue = "typescript",
	svelte = "typescript",
	astro = "typescript",

	python = "python",

	lua = "lua",

	rust = "rust",

	go = "go",

	css = "css",
	scss = "css",
	less = "css",
	sass = "css",

	markdown = "markdown",
	["markdown.mdx"] = "markdown",
	mdx = "markdown",

	yaml = "yaml",
	["yaml.ansible"] = "yaml",
	["yaml.docker-compose"] = "yaml",
	toml = "yaml",

	sh = "shell",
	bash = "shell",
	zsh = "shell",
	fish = "shell",
}

-- ═══════════════════════════════════════════════════════════════════════
-- KEYMAP HELPERS
--
-- Wraps dial's manipulate functions with filetype-aware group selection.
-- ═══════════════════════════════════════════════════════════════════════

--- Create a dial manipulate function that auto-selects the augend group
--- based on the current buffer's filetype.
---
---@param direction "increment"|"decrement" Manipulation direction
---@param mode "normal"|"visual"|"gnormal"|"gvisual" Manipulation mode
---@return fun() handler Keymap callback
---@private
local function dial_map(direction, mode)
	return function()
		local ft = vim.bo.filetype
		local group = FT_GROUP_MAP[ft] or "default"
		require("dial.map").manipulate(direction, mode, group)
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

return {
	"monaqa/dial.nvim",

	keys = {
		-- Normal mode
		{ "<C-a>", dial_map("increment", "normal"), desc = " Increment" },
		{ "<C-x>", dial_map("decrement", "normal"), desc = " Decrement" },

		-- Normal mode (additive — for sequences)
		{ "g<C-a>", dial_map("increment", "gnormal"), desc = " Increment (additive)" },
		{ "g<C-x>", dial_map("decrement", "gnormal"), desc = " Decrement (additive)" },

		-- Visual mode
		{ "<C-a>", dial_map("increment", "visual"), mode = "v", desc = " Increment" },
		{ "<C-x>", dial_map("decrement", "visual"), mode = "v", desc = " Decrement" },

		-- Visual mode (additive — creates sequences: 1,2,3...)
		{ "g<C-a>", dial_map("increment", "gvisual"), mode = "v", desc = " Increment (sequence)" },
		{ "g<C-x>", dial_map("decrement", "gvisual"), mode = "v", desc = " Decrement (sequence)" },
	},

	config = function()
		local dial_config = require("dial.config")
		local groups = build_augend_groups()

		dial_config.augends:register_group(groups)

		-- ── Per-filetype autocmd ─────────────────────────────────────
		-- Sets the default augend group based on filetype.
		-- This is used by dial when no explicit group is passed.
		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("Dial_FtGroup", { clear = true }),
			desc = "Set dial augend group per filetype",
			callback = function(event)
				local group = FT_GROUP_MAP[event.match]
				if group then vim.b[event.buf].dial_augends = group end
			end,
		})
	end,
}
