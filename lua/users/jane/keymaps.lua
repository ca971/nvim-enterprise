-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  User keymaps: jane                                                   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local M = {}

function M.setup()
	local map = vim.keymap.set

	-- Quick Python REPL
	map("n", "<leader>rp", function()
		require("toggleterm").exec("python3", 1, 20, nil, "horizontal")
	end, { desc = "Python REPL" })
end

return M
