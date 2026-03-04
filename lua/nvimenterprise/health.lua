-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Bridge module for :checkhealth nvimenterprise                        ║
-- ║                                                                        ║
-- ║  Neovim looks for <name>/health.lua → this delegates to core/health   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local M = {}

function M.check()
	require("core.health").check()
end

return M
