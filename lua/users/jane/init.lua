-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  User namespace: jane                                                 ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local M = {}

function M.setup()
	-- Jane prefers a minimal UI — hide some elements after plugins load
	vim.opt.showtabline = 1 -- Show tabline only when there are 2+ tabs
end

return M
