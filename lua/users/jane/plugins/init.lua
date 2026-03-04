-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  User plugins: jane                                                   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

return {
	-- Jane uses render-markdown for better markdown previews
	{
		"MeanderingProgrammer/render-markdown.nvim",
		ft = "markdown",
		dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" },
		opts = {},
	},
}
