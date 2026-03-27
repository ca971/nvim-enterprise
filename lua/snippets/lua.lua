local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local fmt = require("luasnip.extras.fmt").fmt

return {
	-- Module header avec nom de fichier auto-détecté
	s(
		"mod",
		fmt(
			[[
---@module "{}"
---@description {}
---@version 1.0.0
---@since {}

local M = {{}}

{}

return M
]],
			{
				f(function()
					return vim.fn.expand("%:t:r")
				end),
				i(1, "Module description"),
				f(function()
					return os.date("%Y-%m-%d")
				end),
				i(0),
			}
		)
	),

	-- Guard pattern (ton style)
	s(
		"guard",
		fmt(
			[[
local settings = require("core.settings")
if not settings:is_plugin_enabled("{}") then return {{}} end
]],
			{
				i(1, "plugin_name"),
			}
		)
	),
}
