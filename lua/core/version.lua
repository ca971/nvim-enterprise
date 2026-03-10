---@file lua/core/version.lua
---@description Single source of truth for project version (SemVer)
---@module "core.version"
---@author ca971
---@license MIT
---@version 1.1.0
---@since 2026-01
---
---@see https://semver.org SemVer specification
---@see CHANGELOG.md      Human-readable change history
---@see scripts/release.sh Automated release workflow

---@class NvimEnterpriseVersion
---@field major integer Breaking changes (new architecture, incompatible settings)
---@field minor integer New features (new plugin, new module, new command)
---@field patch integer Bug fixes, refactoring, documentation
---@field pre?  string  Pre-release tag ("alpha", "beta", "rc.1")
local M = {
	major = 1,
	minor = 1,
	patch = 0,
	pre = nil,
}

--- Return full semver string.
---@return string version e.g. "1.1.0" or "2.0.0-beta"
---@nodiscard
function M.string()
	local v = string.format("%d.%d.%d", M.major, M.minor, M.patch)
	if M.pre then v = v .. "-" .. M.pre end
	return v
end

--- Display version in a notification.
---@return nil
function M.show()
	vim.notify(
		string.format("  nvim-enterprise v%s  (Neovim %s)", M.string(), tostring(vim.version())),
		vim.log.levels.INFO,
		{ title = "Version" }
	)
end

--- Compare with a required minimum version.
---@param maj integer Required major version
---@param min integer Required minor version
---@param pat integer Required patch version
---@return boolean meets `true` if current version >= required
---@nodiscard
function M.at_least(maj, min, pat)
	if M.major ~= maj then return M.major > maj end
	if M.minor ~= min then return M.minor > min end
	return M.patch >= pat
end

--- Register user commands (called once, idempotent).
---@return nil
function M.setup_commands()
	if M._commands_registered then return end
	M._commands_registered = true

	vim.api.nvim_create_user_command("Version", function()
		M.show()
	end, { desc = "Show nvim-enterprise version" })

	vim.api.nvim_create_user_command("NvimVersion", function()
		M.show()
	end, { desc = "Show nvim-enterprise version" })
end

-- Auto-register commands when loaded via require() (vim.* is available)
-- When loaded via dofile() from init.lua, commands are registered
-- later during core bootstrap.
if vim and vim.api then M.setup_commands() end

return M
