---@file lua/plugins/ai/avante.lua
---@description Avante — AI-powered code assistant with multi-provider support, auto-detection and MCP integration
---@module "plugins.ai.avante"
---@author ca971
---@license MIT
---@version 1.1.0
---@since 2026-01
---
---@see core.settings Settings singleton (ai.enabled, ai.avante.*, ai.provider, ai.ollama.*)
---@see core.icons Centralized icon definitions (UI, misc)
---@see plugins.ai AI plugin aggregator
---@see plugins.ai.codecompanion Complementary AI plugin (different UX)
---@see plugins.ai.mcphub MCP server hub (tools provider for AI plugins)
---
---@see https://github.com/yetone/avante.nvim
---@see https://github.com/ravitemer/mcphub.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ai/avante.lua — AI coding assistant (multi-provider + MCP)      ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard chain (3-level):                                          │    ║
--- ║  │  ├─ plugins.avante.enabled = false  → return {}                  │    ║
--- ║  │  ├─ ai.enabled = false              → return {}                  │    ║
--- ║  │  └─ ai.avante.enabled = false       → return {}                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Provider detection pipeline:                                    │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  1. ai.avante.provider (plugin-specific preference)        │  │    ║
--- ║  │  │  2. ai.provider (global AI preference)                     │  │    ║
--- ║  │  │  3. Auto-detect from env vars (priority order):            │  │    ║
--- ║  │  │     ANTHROPIC_API_KEY → claude                             │  │    ║
--- ║  │  │     OPENAI_API_KEY   → openai                              │  │    ║
--- ║  │  │     GEMINI_API_KEY   → gemini                              │  │    ║
--- ║  │  │     DEEPSEEK_API_KEY → deepseek                            │  │    ║
--- ║  │  │     DASHSCOPE_API_KEY → qwen                               │  │    ║
--- ║  │  │     GLM_API_KEY      → glm                                 │  │    ║
--- ║  │  │     MOONSHOT_API_KEY → kimi                                │  │    ║
--- ║  │  │  4. Fallback → ollama (no API key needed)                  │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Provider registry (8 providers):                                │    ║
--- ║  │  ┌─────────────┬──────────────────────┬───────────────────────┐  │    ║
--- ║  │  │ Provider    │ Model                │ Type                  │  │    ║
--- ║  │  ├─────────────┼──────────────────────┼───────────────────────┤  │    ║
--- ║  │  │ claude      │ claude-sonnet-4      │ Built-in (native)     │  │    ║
--- ║  │  │ openai      │ gpt-5                │ Built-in (native)     │  │    ║
--- ║  │  │ gemini      │ gemini-2.5-pro       │ Built-in (native)     │  │    ║
--- ║  │  │ deepseek    │ deepseek-chat        │ Vendor (OpenAI-compat)│  │    ║
--- ║  │  │ qwen        │ qwen-plus            │ Vendor (OpenAI-compat)│  │    ║
--- ║  │  │ glm         │ glm-5                │ Vendor (OpenAI-compat)│  │    ║
--- ║  │  │ kimi        │ kimi-2.5             │ Vendor (OpenAI-compat)│  │    ║
--- ║  │  │ ollama      │ qwen2.5-coder:7b     │ Vendor (local)        │  │    ║
--- ║  │  └─────────────┴──────────────────────┴───────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  MCP integration (via mcphub.nvim):                              │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  mcphub.nvim (optional dependency)                         │  │    ║
--- ║  │  │  ├─ custom_tools:  MCP tools injected into Avante          │  │    ║
--- ║  │  │  │  → AI can call tools (filesystem, fetch, github, etc.)  │  │    ║
--- ║  │  │  ├─ system_prompt: MCP server instructions appended        │  │    ║
--- ║  │  │  │  → AI knows which tools are available                   │  │    ║
--- ║  │  │  └─ Slash commands from MCP servers (/mcp_*)               │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  Without mcphub: Avante works normally (no tools)          │  │    ║
--- ║  │  │  With mcphub:    AI can read files, fetch URLs, query DBs  │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Runtime provider switching:                                     │    ║
--- ║  │  ├─ cycle_provider()   Rotates through PROVIDERS in order        │    ║
--- ║  │  │  (claude → openai → gemini → … → ollama → claude)             │    ║
--- ║  │  └─ select_provider()  Interactive picker (vim.ui.select)        │    ║
--- ║  │     Shows API key availability (✅/❌) per provider              │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    <leader>aa   Toggle Avante chat panel              (n, v)             ║
--- ║    <leader>af   Focus Avante panel                    (n)                ║
--- ║    <leader>ar   Refresh Avante                        (n)                ║
--- ║    <leader>ae   Edit selection with AI                (n, v)             ║
--- ║    <leader>ac   Ask about code                        (n, v)             ║
--- ║    <leader>aR   Chat with repo context                (n)                ║
--- ║    <leader>ad   Show AI diff                          (n)                ║
--- ║    <leader>at   Cycle AI provider                     (n)                ║
--- ║    <leader>aT   Select AI provider (picker)           (n)                ║
--- ║    <leader>ah   Chat history                          (n)                ║
--- ║    <leader>aH   Avante help / commands                (n)                ║
--- ║                                                                          ║
--- ║  Internal keymaps (inside Avante windows):                               ║
--- ║    co/ct/ca/cb/cc   Diff resolution (ours/theirs/all/both/cursor)        ║
--- ║    ]x / [x          Next/previous diff                                   ║
--- ║    ]] / [[          Jump next/previous section                           ║
--- ║    <M-l>            Accept suggestion                                    ║
--- ║    <M-]> / <M-[>    Next/previous suggestion                             ║
--- ║    <CR> / <C-s>     Submit (normal / insert)                             ║
--- ║    A / a             Apply all / apply at cursor                         ║
--- ║    <Tab> / <S-Tab>  Switch sidebar windows                               ║
--- ║                                                                          ║
--- ║  Environment variables:                                                  ║
--- ║    ANTHROPIC_API_KEY   — Claude (Anthropic)                              ║
--- ║    OPENAI_API_KEY      — GPT-5 (OpenAI)                                  ║
--- ║    GEMINI_API_KEY      — Gemini (Google)                                 ║
--- ║    DEEPSEEK_API_KEY    — DeepSeek                                        ║
--- ║    DASHSCOPE_API_KEY   — Qwen (Alibaba DashScope)                        ║
--- ║    GLM_API_KEY         — GLM-5 (Zhipu AI)                                ║
--- ║    MOONSHOT_API_KEY    — Kimi (Moonshot AI)                              ║
--- ║    (none)              — Ollama (local, no key needed)                   ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  ├─ 3-level guard chain: master AI switch + avante-specific switch       ║
--- ║  │  + plugin enable flag — maximum granularity                           ║
--- ║  ├─ pcall-wrapped requires for icons/settings — degrades gracefully      ║
--- ║  │  in minimal environments or during bootstrap                          ║
--- ║  ├─ icon() helper with fallback — never crashes on missing icon keys     ║
--- ║  ├─ setting() helper wraps pcall around settings:get() — safe defaults   ║
--- ║  ├─ Built-in providers (claude, openai, gemini) use native avante API    ║
--- ║  ├─ Custom vendors (deepseek, qwen, glm, kimi, ollama) use               ║
--- ║  │  __inherited_from = "openai" for OpenAI-compatible API format         ║
--- ║  ├─ Ollama URL and model from central settings (ai.ollama.*)             ║
--- ║  ├─ MCP tools injected via pcall — graceful degradation if mcphub        ║
--- ║  │  is not installed (custom_tools = {}, system_prompt = nil)            ║
--- ║  ├─ auto_set_keymaps = false — we define keymaps explicitly in keys{}    ║
--- ║  ├─ auto_apply_diff_after_generation = false — user reviews first        ║
--- ║  └─ file_selector uses snacks provider for consistency                   ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • VeryLazy loading — no startup cost until first use                    ║
--- ║  • Provider detection runs once at spec evaluation time                  ║
--- ║  • avante_cmd() wraps commands in pcall — safe if plugin not loaded      ║
--- ║  • cycle_provider() reads current state from avante.config (no cache)    ║
--- ║  • select_provider() checks env vars live for accurate ✅/❌ status      ║
--- ║  • MCP tools loaded lazily via pcall (zero cost if mcphub absent)        ║
--- ║                                                                          ║
--- ║  Changelog:                                                              ║
--- ║  • 1.1.0 — Added MCP integration via mcphub.nvim                         ║
--- ║            custom_tools injected from MCP servers                        ║
--- ║            system_prompt augmented with MCP tool descriptions            ║
--- ║            mcphub added as optional dependency                           ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════
-- GUARD
--
-- 3-level guard chain:
-- 1. Plugin-level: settings:is_plugin_enabled("avante")
-- 2. AI master switch: ai.enabled
-- 3. Plugin-specific: ai.avante.enabled
-- All three must be true for the plugin to load.
-- ═══════════════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok then
	if not settings:is_plugin_enabled("avante") then return {} end
	if not settings:get("ai.enabled", false) then return {} end
	if not settings:get("ai.avante.enabled", false) then return {} end
end

-- ═══════════════════════════════════════════════════════════════════════
-- SAFE REQUIRES
--
-- Icons are loaded via pcall with a complete fallback table.
-- This ensures the plugin spec can be evaluated even during
-- bootstrap or in minimal environments where core modules
-- haven't loaded yet.
-- ═══════════════════════════════════════════════════════════════════════

local icons_ok, icons = pcall(require, "core.icons")

if not icons_ok or not icons then
	icons = {
		ui = {
			Code = "󰅩",
			Rocket = "󰓅",
			Gear = "󰒓",
			Pencil = "●",
			Search = "",
			List = "󰗚",
			Close = "×",
			BookMark = "󰃀",
			Robot = "󰚩",
		},
		misc = { AI = "󰧑" },
	}
end

-- ═══════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════

--- Safely get an icon from a table with a fallback value.
--- Prevents crashes when an icon key is missing from the icons module.
---
---@param tbl table|nil Icon group table (e.g. `icons.ui`)
---@param key string Icon key within the group
---@param fallback string Fallback string if key is missing or tbl is nil
---@return string icon The icon string
---@private
local function icon(tbl, key, fallback)
	if type(tbl) == "table" and tbl[key] ~= nil then return tbl[key] end
	return fallback or ""
end

---@type table
local ui = icons.ui or {}
---@type table
local mi = icons.misc or {}

--- Safely read a setting value with pcall protection.
--- Returns `default` if settings module is not loaded or the
--- key lookup fails for any reason.
---
---@param key string Dot-separated settings path
---@param default any Fallback value
---@return any value The setting value or default
---@private
local function setting(key, default)
	if not settings_ok or not settings then return default end
	local ok, val = pcall(settings.get, settings, key, default)
	return ok and val or default
end

-- ═══════════════════════════════════════════════════════════════════════
-- PROVIDER REGISTRY
--
-- Static metadata for all supported providers. Used by:
-- • detect_provider()   — auto-detection from env vars
-- • cycle_provider()    — display name and icon in notifications
-- • select_provider()   — picker items with API key status
-- ═══════════════════════════════════════════════════════════════════════

---@class ProviderInfo
---@field name string Human-readable provider name
---@field icon string Emoji icon for notifications
---@field env string|nil Environment variable for API key (`nil` for local providers)
---@field description string Short description for picker/notifications

---@type table<string, ProviderInfo>
local PROVIDER_INFO = {
	claude = {
		name = "Claude Sonnet 4",
		icon = "🧠",
		env = "ANTHROPIC_API_KEY",
		description = "Anthropic — best coding quality",
	},
	openai = {
		name = "GPT-5",
		icon = "🤖",
		env = "OPENAI_API_KEY",
		description = "OpenAI — flagship model",
	},
	gemini = {
		name = "Gemini 2.5 Pro",
		icon = "💎",
		env = "GEMINI_API_KEY",
		description = "Google — large context window",
	},
	deepseek = {
		name = "DeepSeek V4",
		icon = "🔍",
		env = "DEEPSEEK_API_KEY",
		description = "DeepSeek — fast, cost-effective",
	},
	qwen = {
		name = "Qwen 3.5",
		icon = "🌐",
		env = "DASHSCOPE_API_KEY",
		description = "Alibaba — multilingual, reasoning",
	},
	glm = {
		name = "GLM-5",
		icon = "🐉",
		env = "GLM_API_KEY",
		description = "Zhipu AI — strong Chinese/English",
	},
	kimi = {
		name = "Kimi 2.5",
		icon = "🌙",
		env = "MOONSHOT_API_KEY",
		description = "Moonshot — long context specialist",
	},
	ollama = {
		name = "Ollama (local)",
		icon = "🦙",
		env = nil,
		description = "Local — offline, privacy-first",
	},
}

--- Provider cycle order (most capable → local fallback).
--- Used by cycle_provider() to rotate through providers.
---@type string[]
local PROVIDERS = { "claude", "openai", "gemini", "deepseek", "qwen", "glm", "kimi", "ollama" }

-- ═══════════════════════════════════════════════════════════════════════
-- PROVIDER DETECTION
--
-- 4-step cascade:
-- 1. Plugin-specific setting (ai.avante.provider)
-- 2. Global AI setting (ai.provider)
-- 3. Auto-detect from environment variables (priority order)
-- 4. Fallback to ollama (always available, no key needed)
-- ═══════════════════════════════════════════════════════════════════════

--- Auto-detect the best available provider.
---
--- Follows a 4-step cascade:
--- 1. Plugin-specific preference (`ai.avante.provider`)
--- 2. Global AI preference (`ai.provider`)
--- 3. Auto-detect from available API keys (priority order)
--- 4. Fallback to `"ollama"` (no API key needed)
---
---@return string provider The detected provider key
---@private
local function detect_provider()
	-- 1. Plugin-specific preference (ai.avante.provider)
	local avante_provider = setting("ai.avante.provider", nil)
	if avante_provider and avante_provider ~= "" and PROVIDER_INFO[avante_provider] then return avante_provider end

	-- 2. Global AI preference (ai.provider)
	local global_provider = setting("ai.provider", nil)
	if global_provider and global_provider ~= "" and global_provider ~= "auto" and PROVIDER_INFO[global_provider] then
		return global_provider
	end

	-- 3. Auto-detect based on available API keys (priority order)
	local detection_order = {
		{ provider = "claude", env = "ANTHROPIC_API_KEY" },
		{ provider = "openai", env = "OPENAI_API_KEY" },
		{ provider = "gemini", env = "GEMINI_API_KEY" },
		{ provider = "deepseek", env = "DEEPSEEK_API_KEY" },
		{ provider = "qwen", env = "DASHSCOPE_API_KEY" },
		{ provider = "glm", env = "GLM_API_KEY" },
		{ provider = "kimi", env = "MOONSHOT_API_KEY" },
	}

	for _, entry in ipairs(detection_order) do
		local val = vim.env[entry.env]
		if val and val ~= "" then return entry.provider end
	end

	-- 4. Fallback to ollama (no API key needed)
	return "ollama"
end

--- Resolve the auto-suggestions provider from settings.
---
--- Returns `nil` if no auto-suggestions provider is configured,
--- which disables automatic inline suggestions.
---
---@return string|nil provider The suggestions provider key, or `nil`
---@private
local function detect_suggestions_provider()
	local provider = setting("ai.avante.auto_suggestions_provider", nil)
	if provider and provider ~= "" and PROVIDER_INFO[provider] then return provider end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════════
-- ICONS
-- ═══════════════════════════════════════════════════════════════════════

---@type string AI icon for keymaps and notifications
local ai_icon = icon(mi, "AI", "󰧑")

-- ═══════════════════════════════════════════════════════════════════════
-- PROVIDER SWITCHER
--
-- Two modes:
-- • cycle_provider(): rotates through PROVIDERS in order
--   (claude → openai → gemini → … → ollama → claude)
-- • select_provider(): interactive picker showing all providers
--   with API key availability status
-- ═══════════════════════════════════════════════════════════════════════

--- Cycle to the next provider in the PROVIDERS list and notify.
---
--- Reads the current provider from `avante.config`, finds it in
--- the PROVIDERS array, advances to the next index (wrapping around),
--- and issues `:AvanteSwitchProvider`.
---
---@private
local function cycle_provider()
	local ok, _ = pcall(require, "avante.api")
	if not ok then
		vim.notify("Avante not loaded", vim.log.levels.WARN)
		return
	end

	-- Get current provider
	local config_ok, avante_config = pcall(require, "avante.config")
	local current = "claude"
	if config_ok and avante_config and avante_config.provider then current = avante_config.provider end

	-- Find next in cycle
	local idx = 1
	for i, p in ipairs(PROVIDERS) do
		if p == current then
			idx = i
			break
		end
	end
	local next_provider = PROVIDERS[(idx % #PROVIDERS) + 1]

	-- Switch
	pcall(function()
		vim.cmd("AvanteSwitchProvider " .. next_provider)
	end)

	-- Notify with provider info
	local info = PROVIDER_INFO[next_provider] or {}
	vim.notify(
		string.format("%s Switched to: %s\n   %s", info.icon or "🤖", info.name or next_provider, info.description or ""),
		vim.log.levels.INFO,
		{ title = "Avante" }
	)
end

--- Show an interactive picker to select a provider.
---
--- Displays all providers from PROVIDERS with their display name,
--- icon, and API key availability (✅ if the environment variable
--- is set, ❌ if missing). Uses `vim.ui.select()` for the picker.
---
---@private
local function select_provider()
	local items = {}
	for _, p in ipairs(PROVIDERS) do
		local info = PROVIDER_INFO[p]
		local has_key = true
		if info.env then
			local val = vim.env[info.env]
			has_key = val and val ~= ""
		end

		items[#items + 1] = string.format(
			"%s %s %s %s",
			info.icon,
			info.name,
			has_key and "✅" or "❌",
			has_key and "" or ("(set " .. (info.env or "N/A") .. ")")
		)
	end

	vim.ui.select(items, {
		prompt = ai_icon .. " Select AI Provider:",
	}, function(choice, idx)
		if not choice or not idx then return end
		local selected = PROVIDERS[idx]
		pcall(function()
			vim.cmd("AvanteSwitchProvider " .. selected)
		end)

		local info = PROVIDER_INFO[selected] or {}
		vim.notify(
			string.format("%s Now using: %s", info.icon or "🤖", info.name or selected),
			vim.log.levels.INFO,
			{ title = "Avante" }
		)
	end)
end

-- ═══════════════════════════════════════════════════════════════════════
-- COMMAND WRAPPER
--
-- Wraps Avante commands in pcall for safe execution.
-- Returns a closure suitable for use in lazy.nvim keys[].
-- ═══════════════════════════════════════════════════════════════════════

--- Create a safe Avante command executor.
---
--- Returns a function that first ensures `avante` is loaded via
--- pcall, then executes the given command string. Shows a warning
--- notification if Avante is not available.
---
--- ```lua
--- avante_cmd("AvanteToggle")  --> function that safely runs :AvanteToggle
--- ```
---
---@param cmd string Avante command name (e.g. `"AvanteToggle"`)
---@return function executor Closure suitable for lazy.nvim `keys[]` entries
---@private
local function avante_cmd(cmd)
	return function()
		local ok = pcall(require, "avante")
		if ok then
			pcall(function()
				vim.cmd(cmd)
			end)
		else
			vim.notify("Avante not loaded", vim.log.levels.WARN)
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- OLLAMA SETTINGS
--
-- Reads Ollama URL and model from central settings so all AI
-- plugins share the same configuration for local inference.
-- ═══════════════════════════════════════════════════════════════════════

---@type string Ollama server URL (from ai.ollama.url)
local ollama_url = setting("ai.ollama.url", "http://localhost:11434")

---@type string Ollama chat model name (from ai.ollama.chat_model)
local ollama_chat_model = setting("ai.ollama.chat_model", "qwen2.5-coder:7b")

-- ═══════════════════════════════════════════════════════════════════════
-- MCP INTEGRATION
--
-- Builds custom_tools and system_prompt from mcphub.nvim if available.
-- Uses pcall for graceful degradation — Avante works normally without
-- mcphub, and gains MCP tools when mcphub is installed and configured.
--
-- Tool injection flow:
--   mcphub.nvim → mcphub.extensions.avante → avante custom_tools
--   mcphub.nvim → mcphub.extensions.avante → avante system_prompt
--
-- When mcphub is absent:
--   custom_tools = {}         (no tools, no error)
--   mcp_system_prompt = nil   (default system prompt, no augmentation)
-- ═══════════════════════════════════════════════════════════════════════

--- Build MCP custom tools for Avante.
---
--- Attempts to load `mcphub.extensions.avante` and extract the
--- MCP tool definition. Returns an empty table if mcphub is not
--- installed or not configured.
---
---@return table[] tools List of custom tool definitions for Avante
---@private
local function build_mcp_tools()
	local mcp_ok, mcphub_avante = pcall(require, "mcphub.extensions.avante")
	if mcp_ok and mcphub_avante and mcphub_avante.mcp_tool then return { mcphub_avante.mcp_tool() } end
	return {}
end

--- Build MCP-augmented system prompt for Avante.
---
--- Attempts to load `mcphub.extensions.avante` and retrieve the
--- prompt describing all active MCP servers and their available
--- tools. Returns `nil` if mcphub is not available (Avante uses
--- its default system prompt).
---
---@return string|nil prompt MCP-augmented system prompt, or `nil`
---@private
local function build_mcp_system_prompt()
	local mcp_ok, mcphub_avante = pcall(require, "mcphub.extensions.avante")
	if mcp_ok and mcphub_avante and mcphub_avante.get_prompt_for_active_servers then
		local prompt_ok, prompt = pcall(mcphub_avante.get_prompt_for_active_servers)
		if prompt_ok and prompt and prompt ~= "" then return prompt end
	end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"yetone/avante.nvim",
	event = "VeryLazy",
	build = "make",

	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"stevearc/dressing.nvim",
		"nvim-lua/plenary.nvim",
		"MunifTanjim/nui.nvim",
		"nvim-mini/mini.icons",

		-- ── MCP integration ──────────────────────────────────────
		-- Optional: when installed, MCP tools are injected into
		-- Avante via custom_tools and system_prompt augmentation.
		-- When absent, Avante works normally without tools.
		{
			"ravitemer/mcphub.nvim",
			optional = true,
		},

		{
			"MeanderingProgrammer/render-markdown.nvim",
			optional = true,
			opts = { file_types = { "markdown", "Avante" } },
			ft = { "markdown", "Avante" },
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAPS
	-- ═══════════════════════════════════════════════════════════════════

	keys = {
		-- ── Chat ──────────────────────────────────────────────────────
		{
			"<leader>aa",
			avante_cmd("AvanteToggle"),
			mode = { "n", "v" },
			desc = ai_icon .. " Toggle Avante",
		},
		{
			"<leader>af",
			avante_cmd("AvanteFocus"),
			desc = ai_icon .. " Focus Avante",
		},
		{
			"<leader>ar",
			avante_cmd("AvanteRefresh"),
			desc = icon(ui, "Rocket", "󰓅") .. " Refresh Avante",
		},

		-- ── Edit / Ask ────────────────────────────────────────────────
		{
			"<leader>ae",
			avante_cmd("AvanteEdit"),
			mode = { "n", "v" },
			desc = icon(ui, "Pencil", "●") .. " Edit with AI",
		},
		{
			"<leader>ac",
			avante_cmd("AvanteAsk"),
			mode = { "n", "v" },
			desc = icon(ui, "Code", "󰅩") .. " Ask about code",
		},

		-- ── Repo context ──────────────────────────────────────────────
		{
			"<leader>aR",
			avante_cmd("AvanteChatWithRepo"),
			desc = icon(ui, "Search", "") .. " Chat with repo context",
		},

		-- ── Diff ──────────────────────────────────────────────────────
		{
			"<leader>ad",
			avante_cmd("AvanteShowDiff"),
			desc = icon(ui, "List", "󰗚") .. " Show AI diff",
		},

		-- ── Provider ──────────────────────────────────────────────────
		{
			"<leader>at",
			cycle_provider,
			desc = icon(ui, "Gear", "󰒓") .. " Cycle AI provider",
		},
		{
			"<leader>aT",
			select_provider,
			desc = icon(ui, "Gear", "󰒓") .. " Select AI provider",
		},

		-- ── History ───────────────────────────────────────────────────
		{
			"<leader>ah",
			avante_cmd("AvanteHistory"),
			desc = icon(ui, "BookMark", "󰃀") .. " Chat history",
		},

		-- ── Help ──────────────────────────────────────────────────────
		{
			"<leader>aH",
			avante_cmd("AvanteHelp"),
			desc = ai_icon .. " Avante help",
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	-- ═══════════════════════════════════════════════════════════════════

	opts = {
		-- ── Default provider (from settings → auto-detect) ───────────
		provider = detect_provider(),
		auto_suggestions_provider = detect_suggestions_provider(),

		-- ── Built-in providers (native avante support) ───────────────
		claude = {
			endpoint = "https://api.anthropic.com",
			model = "claude-sonnet-4-20250514",
			temperature = 0,
			max_tokens = 8192,
		},

		openai = {
			endpoint = "https://api.openai.com/v1",
			model = "gpt-5",
			temperature = 0,
			max_tokens = 8192,
		},

		gemini = {
			endpoint = "https://generativelanguage.googleapis.com/v1beta/models",
			model = "gemini-2.5-pro-preview-06-05",
			temperature = 0,
			max_tokens = 8192,
		},

		-- ── Custom vendors (OpenAI-compatible APIs) ──────────────────
		vendors = {
			deepseek = {
				__inherited_from = "openai",
				api_key_name = "DEEPSEEK_API_KEY",
				endpoint = "https://api.deepseek.com",
				model = "deepseek-chat",
				temperature = 0,
				max_tokens = 8192,
			},

			qwen = {
				__inherited_from = "openai",
				api_key_name = "DASHSCOPE_API_KEY",
				endpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1",
				model = "qwen-plus",
				temperature = 0,
				max_tokens = 8192,
			},

			glm = {
				__inherited_from = "openai",
				api_key_name = "GLM_API_KEY",
				endpoint = "https://open.bigmodel.cn/api/paas/v4",
				model = "glm-5",
				temperature = 0,
				max_tokens = 8192,
			},

			kimi = {
				__inherited_from = "openai",
				api_key_name = "MOONSHOT_API_KEY",
				endpoint = "https://api.moonshot.cn/v1",
				model = "kimi-2.5",
				temperature = 0,
				max_tokens = 8192,
			},

			-- ── Ollama: URL and model from central settings ──────────
			ollama = {
				__inherited_from = "openai",
				api_key_name = "",
				endpoint = ollama_url .. "/v1",
				model = ollama_chat_model,
				temperature = 0,
				max_tokens = 4096,
			},
		},

		-- ── Behavior ─────────────────────────────────────────────────
		behaviour = {
			auto_suggestions = false,
			auto_set_highlight_group = true,
			auto_set_keymaps = false,
			auto_apply_diff_after_generation = false,
			support_paste_from_clipboard = true,
			minimize_diff = true,
		},

		-- ── Mappings inside Avante windows ───────────────────────────
		mappings = {
			diff = {
				ours = "co",
				theirs = "ct",
				all_theirs = "ca",
				both = "cb",
				cursor = "cc",
				next = "]x",
				prev = "[x",
			},
			suggestion = {
				accept = "<M-l>",
				next = "<M-]>",
				prev = "<M-[>",
				dismiss = "<C-]>",
			},
			jump = {
				next = "]]",
				prev = "[[",
			},
			submit = {
				normal = "<CR>",
				insert = "<C-s>",
			},
			sidebar = {
				apply_all = "A",
				apply_cursor = "a",
				switch_windows = "<Tab>",
				reverse_switch_windows = "<S-Tab>",
			},
		},

		-- ── UI ───────────────────────────────────────────────────────
		hints = { enabled = true },

		windows = {
			position = "right",
			wrap = true,
			width = 40,
			sidebar_header = {
				enabled = true,
				align = "center",
				rounded = true,
			},
			input = {
				prefix = ai_icon .. " ",
				height = 8,
			},
			edit = {
				border = "rounded",
				start_insert = true,
			},
			ask = {
				floating = false,
				start_insert = true,
				border = "rounded",
			},
		},

		highlights = {
			diff = {
				current = "DiffText",
				incoming = "DiffAdd",
			},
		},

		diff = {
			autojump = true,
			list_opener = "copen",
			override_timeoutlen = 500,
		},

		file_selector = {
			provider = "snacks",
			provider_opts = {},
		},

		-- ── MCP Tools ────────────────────────────────────────────────
		-- Injected from mcphub.nvim via its avante extension.
		-- When mcphub is installed and configured, AI can use tools
		-- like filesystem access, HTTP fetch, GitHub API, etc.
		-- When mcphub is absent, this resolves to {} (no tools).
		--
		-- Tools become available as slash commands in the Avante chat
		-- and the AI can call them autonomously based on context.
		custom_tools = build_mcp_tools(),

		-- ── System Prompt (MCP-augmented) ────────────────────────────
		-- When mcphub is active, appends descriptions of all running
		-- MCP servers and their available tools to the system prompt.
		-- This lets the AI know which tools it can call.
		-- When mcphub is absent, this is nil (Avante uses its default).
		system_prompt = build_mcp_system_prompt(),
	},
}
