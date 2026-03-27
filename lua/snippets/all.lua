local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node

return {
	-- Date dynamique (impossible en JSON)
	s("ddate", {
		f(function()
			return os.date("%Y-%m-%d")
		end),
	}),

	-- Header avec choix de style de commentaire
	s("hdr", {
		c(1, {
			t("-- "),
			t("// "),
			t("# "),
		}),
		t(
			"═══════════════════════════════════════"
		),
		t({ "", "" }),
		c(2, {
			t("-- "),
			t("// "),
			t("# "),
		}),
		i(3, "Section Title"),
		t({ "", "" }),
		c(4, {
			t("-- "),
			t("// "),
			t("# "),
		}),
		t(
			"═══════════════════════════════════════"
		),
	}),
}
