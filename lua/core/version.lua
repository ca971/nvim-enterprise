---@file lua/core/version.lua
---@description Single source of truth for project version (SemVer)
---@module "core.version"
---@author ca971
---@license MIT
---@version 1.0.1
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
---
--- ```lua
--- require("core.version").string()  -- → "1.0.1"
--- -- With pre-release:              -- → "2.0.0-beta"
--- ```
---
---@return string version Formatted semver string
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
---
--- ```lua
--- require("core.version").at_least(1, 0, 0)  -- → true
--- require("core.version").at_least(2, 0, 0)  -- → false
--- ```
---
---@param major integer Required major version
---@param minor integer Required minor version
---@param patch integer Required patch version
---@return boolean meets `true` if current version ≥ required
---@nodiscard
function M.at_least(major, minor, patch)
	if M.major ~= major then return M.major > major end
	if M.minor ~= minor then return M.minor > minor end
	return M.patch >= patch
end

vim.api.nvim_create_user_command("Version", function()
	M.show()
end, { desc = "Show nvim-enterprise version" })

return M
