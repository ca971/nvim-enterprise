---@file lua/plugins/ai/codecompanion.lua
---@description CodeCompanion — AI coding companion with chat, inline assist, slash commands and multi-provider support
---@module "plugins.ai.codecompanion"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (ai.enabled, ai.codecompanion.*, ai.provider, ai.ollama.*)
---@see core.icons Centralized icon definitions (UI, misc)
---@see plugins.ai AI plugin aggregator
---@see plugins.ai.avante Complementary AI plugin (different UX, different keymap prefix)
---
---@see https://github.com/olimorris/codecompanion.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ai/codecompanion.lua — AI coding companion (multi-provider)     ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard chain (3-level):                                          │    ║
--- ║  │  ├─ plugins.codecompanion.enabled = false → return {}            │    ║
--- ║  │  ├─ ai.enabled = false                    → return {}            │    ║
--- ║  │  └─ ai.codecompanion.enabled = false      → return {}            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Provider detection pipeline:                                    │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  1. ai.codecompanion.provider (plugin-specific pref)       │  │    ║
--- ║  │  │  2. ai.provider (global AI preference)                     │  │    ║
--- ║  │  │  3. Auto-detect from env vars (priority order)             │  │    ║
--- ║  │  │  4. Fallback → ollama (no API key needed)                  │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  Settings → adapter name mapping:                          │  │    ║
--- ║  │  │  "claude" → "anthropic" (codecompanion adapter name)       │  │    ║
--- ║  │  │  All others map 1:1 (openai, gemini, deepseek…)            │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Provider registry (8 providers):                                │    ║
--- ║  │  ┌──────────────┬──────────────────────┬──────────────────────┐  │    ║
--- ║  │  │ Adapter      │ Model                │ Type                 │  │    ║
--- ║  │  ├──────────────┼──────────────────────┼──────────────────────┤  │    ║
--- ║  │  │ anthropic    │ claude-sonnet-4      │ Native adapter       │  │    ║
--- ║  │  │ openai       │ gpt-5                │ Native adapter       │  │    ║
--- ║  │  │ gemini       │ gemini-2.5-pro       │ Native adapter       │  │    ║
--- ║  │  │ deepseek     │ deepseek-chat        │ openai_compatible    │  │    ║
--- ║  │  │ qwen         │ qwen-plus            │ openai_compatible    │  │    ║
--- ║  │  │ glm          │ glm-5                │ openai_compatible    │  │    ║
--- ║  │  │ kimi         │ kimi-2.5             │ openai_compatible    │  │    ║
--- ║  │  │ ollama       │ qwen2.5-coder:7b     │ Native adapter       │  │    ║
--- ║  │  └──────────────┴──────────────────────┴──────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Strategy routing:                                               │    ║
--- ║  │  ├─ chat    → chat_provider (detect_provider)                    │    ║
--- ║  │  ├─ inline  → inline_provider (detect_inline_provider)           │    ║
--- ║  │  └─ cmd     → inline_provider (same as inline)                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Runtime provider switching:                                     │    ║
--- ║  │  ├─ cycle_provider()   Rotates through PROVIDERS in order        │    ║
--- ║  │  │  Updates all 3 strategies (chat, inline, cmd) at once         │    ║
--- ║  │  └─ select_provider()  Interactive picker (vim.ui.select)        │    ║
--- ║  │     Shows API key availability (✅/❌) per provider              │    ║
--- ║  │                                                                  │    ║
--- ║  │  Features:                                                       │    ║
--- ║  │  ├─ Chat buffer with full conversation history                   │    ║
--- ║  │  ├─ Inline code assistance (edit in place with diff)             │    ║
--- ║  │  ├─ Slash commands: /explain, /fix, /tests, /docs, /optimize     │    ║
--- ║  │  ├─ Variables: #buffer, #lsp, #viewport for context injection    │    ║
--- ║  │  ├─ Action palette for quick AI actions                          │    ║
--- ║  │  ├─ Visual selection → AI prompt                                 │    ║
--- ║  │  ├─ Custom prompt library: Code Review, Commit, Error, Arch      │    ║
--- ║  │  └─ Snacks provider for slash command file/buffer pickers        │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Global keymaps (all under <leader>cc prefix):                           ║
--- ║    <leader>cca   Action palette                       (n, v)             ║
--- ║    <leader>ccc   Chat toggle                          (n, v)             ║
--- ║    <leader>ccq   Close chat                           (n)                ║
--- ║    <leader>cch   Chat history                         (n)                ║
--- ║    <leader>cci   Inline assist                        (n, v)             ║
--- ║    <leader>cce   Explain code (/explain)              (n, v)             ║
--- ║    <leader>ccf   Fix code (/fix)                      (n, v)             ║
--- ║    <leader>cct   Generate tests (/tests)              (n, v)             ║
--- ║    <leader>ccd   Generate docs (/docs)                (n, v)             ║
--- ║    <leader>cco   Optimize code (/optimize)            (n, v)             ║
--- ║    <leader>ccr   Refactor code (/refactor)            (n, v)             ║
--- ║    <leader>ccp   Cycle AI provider                    (n)                ║
--- ║    <leader>ccP   Select AI provider (picker)          (n)                ║
--- ║    <leader>ccH   Commands cheatsheet                  (n)                ║
--- ║                                                                          ║
--- ║  Internal keymaps (inside chat/inline windows):                          ║
--- ║    q / <C-c>        Close chat / stop generation                         ║
--- ║    <CR> / <C-s>     Send message (normal / insert)                       ║
--- ║    <leader>ccy/n    Accept / reject inline change                        ║
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
--- ║  ├─ 3-level guard chain identical to avante.lua                          ║
--- ║  ├─ SETTINGS_TO_ADAPTER map bridges settings names ("claude") to         ║
--- ║  │  codecompanion adapter names ("anthropic")                            ║
--- ║  ├─ Separate chat vs inline provider detection — allows using a          ║
--- ║  │  fast/cheap model for inline and a capable model for chat             ║
--- ║  ├─ Native adapters for anthropic, openai, gemini, ollama                ║
--- ║  ├─ openai_compatible for deepseek, qwen, glm, kimi                      ║
--- ║  ├─ Provider cycling updates all 3 strategies simultaneously             ║
--- ║  ├─ Slash command pickers use snacks provider for consistency            ║
--- ║  ├─ Prompt library includes 4 battle-tested prompts                      ║
--- ║  ├─ Keymap prefix <leader>cc avoids conflicts with avante (<leader>a)    ║
--- ║  └─ pcall(function() vim.cmd(...) end) pattern avoids vim.cmd typing     ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • VeryLazy loading — no startup cost until first use                    ║
--- ║  • Provider detection runs once at spec evaluation time                  ║
--- ║  • cc_cmd() wraps commands in pcall — safe if plugin not loaded          ║
--- ║  • Adapters are factory functions (lazy instantiation)                   ║
--- ║  • Ollama URL and model from central settings (shared with avante)       ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════
-- GUARD
--
-- 3-level guard chain:
-- 1. Plugin-level: settings:is_plugin_enabled("codecompanion")
-- 2. AI master switch: ai.enabled
-- 3. Plugin-specific: ai.codecompanion.enabled
-- All three must be true for the plugin to load.
-- ═══════════════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok then
	if not settings:is_plugin_enabled("codecompanion") then return {} end
	if not settings:get("ai.enabled", false) then return {} end
	if not settings:get("ai.codecompanion.enabled", false) then return {} end
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
			Bug = " ",
			Check = "󰄬",
			Terminal = "󰞷",
			Target = "󰓾",
			Fire = "󰈸",
			Note = "󰎚",
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
-- Static metadata for all supported providers. The `adapter` field
-- holds the codecompanion adapter name (differs from settings for
-- "claude" → "anthropic").
-- ═══════════════════════════════════════════════════════════════════════

---@class CCProviderInfo
---@field name string Human-readable provider name
---@field icon string Emoji icon for notifications
---@field env string|nil Environment variable for API key (`nil` for local providers)
---@field adapter string codecompanion adapter name
---@field description string Short description for picker/notifications

---@type table<string, CCProviderInfo>
local PROVIDER_INFO = {
	anthropic = {
		name = "Claude Sonnet 4",
		icon = "🧠",
		env = "ANTHROPIC_API_KEY",
		adapter = "anthropic",
		description = "Anthropic — best coding quality",
	},
	openai = {
		name = "GPT-5",
		icon = "🤖",
		env = "OPENAI_API_KEY",
		adapter = "openai",
		description = "OpenAI — flagship model",
	},
	gemini = {
		name = "Gemini 2.5 Pro",
		icon = "💎",
		env = "GEMINI_API_KEY",
		adapter = "gemini",
		description = "Google — large context window",
	},
	deepseek = {
		name = "DeepSeek V4",
		icon = "🔍",
		env = "DEEPSEEK_API_KEY",
		adapter = "deepseek",
		description = "DeepSeek — fast, cost-effective",
	},
	qwen = {
		name = "Qwen 3.5",
		icon = "🌐",
		env = "DASHSCOPE_API_KEY",
		adapter = "qwen",
		description = "Alibaba — multilingual, reasoning",
	},
	glm = {
		name = "GLM-5",
		icon = "🐉",
		env = "GLM_API_KEY",
		adapter = "glm",
		description = "Zhipu AI — strong Chinese/English",
	},
	kimi = {
		name = "Kimi 2.5",
		icon = "🌙",
		env = "MOONSHOT_API_KEY",
		adapter = "kimi",
		description = "Moonshot — long context specialist",
	},
	ollama = {
		name = "Ollama (local)",
		icon = "🦙",
		env = nil,
		adapter = "ollama",
		description = "Local — offline, privacy-first",
	},
}

--- Provider cycle order (most capable → local fallback).
--- Uses codecompanion adapter names (not settings names).
---@type string[]
local PROVIDERS = { "anthropic", "openai", "gemini", "deepseek", "qwen", "glm", "kimi", "ollama" }

--- Map settings provider names to codecompanion adapter names.
--- Settings uses "claude", codecompanion uses "anthropic".
--- All others map 1:1.
---@type table<string, string>
local SETTINGS_TO_ADAPTER = {
	claude = "anthropic",
	openai = "openai",
	gemini = "gemini",
	deepseek = "deepseek",
	qwen = "qwen",
	glm = "glm",
	kimi = "kimi",
	ollama = "ollama",
}

-- ═══════════════════════════════════════════════════════════════════════
-- PROVIDER DETECTION
--
-- 4-step cascade identical to avante.lua, but with an additional
-- mapping layer (SETTINGS_TO_ADAPTER) because codecompanion uses
-- "anthropic" where settings uses "claude".
--
-- Separate detection for inline provider allows using a fast/cheap
-- model for inline suggestions and a more capable model for chat.
-- ═══════════════════════════════════════════════════════════════════════

--- Auto-detect the best available provider (adapter name).
---
--- Follows a 4-step cascade:
--- 1. Plugin-specific preference (`ai.codecompanion.provider`)
--- 2. Global AI preference (`ai.provider`)
--- 3. Auto-detect from available API keys (priority order)
--- 4. Fallback to `"ollama"` (no API key needed)
---
---@return string adapter Codecompanion adapter name
---@private
local function detect_provider()
	-- 1. Plugin-specific preference (ai.codecompanion.provider)
	local cc_provider = setting("ai.codecompanion.provider", nil)
	if cc_provider and cc_provider ~= "" then
		local mapped = SETTINGS_TO_ADAPTER[cc_provider]
		if mapped and PROVIDER_INFO[mapped] then return mapped end
	end

	-- 2. Global AI preference (ai.provider)
	local global_provider = setting("ai.provider", nil)
	if global_provider and global_provider ~= "" and global_provider ~= "auto" then
		local mapped = SETTINGS_TO_ADAPTER[global_provider]
		if mapped and PROVIDER_INFO[mapped] then return mapped end
	end

	-- 3. Auto-detect based on available API keys
	local detection_order = {
		{ provider = "anthropic", env = "ANTHROPIC_API_KEY" },
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

--- Detect the inline provider (may differ from chat provider).
---
--- Allows using a fast/cheap model for inline suggestions
--- while keeping a more capable model for chat conversations.
--- Falls back to the main chat provider if not configured.
---
---@return string adapter Codecompanion adapter name for inline strategy
---@private
local function detect_inline_provider()
	local inline = setting("ai.codecompanion.inline_provider", nil)
	if inline and inline ~= "" then
		local mapped = SETTINGS_TO_ADAPTER[inline]
		if mapped and PROVIDER_INFO[mapped] then return mapped end
	end
	-- Fall back to main provider
	return detect_provider()
end

-- ═══════════════════════════════════════════════════════════════════════
-- ICONS
-- ═══════════════════════════════════════════════════════════════════════

---@type string AI icon for keymaps and notifications
local ai_icon = icon(mi, "AI", "󰧑")

-- ═══════════════════════════════════════════════════════════════════════
-- COMMAND WRAPPER
--
-- Wraps CodeCompanion commands in pcall for safe execution.
-- Uses pcall(function() vim.cmd(...) end) to avoid the
-- lua-language-server warning about vim.cmd being a callable
-- table rather than a function.
-- ═══════════════════════════════════════════════════════════════════════

--- Create a safe CodeCompanion command executor.
---
--- Returns a function that first ensures `codecompanion` is loaded
--- via pcall, then executes the given command string. Shows a warning
--- notification if CodeCompanion is not available.
---
--- ```lua
--- cc_cmd("CodeCompanionChat Toggle")  --> function that safely runs :CodeCompanionChat Toggle
--- ```
---
---@param cmd string CodeCompanion command string (e.g. `"CodeCompanionChat Toggle"`)
---@return function executor Closure suitable for lazy.nvim `keys[]` entries
---@private
local function cc_cmd(cmd)
	return function()
		local ok = pcall(require, "codecompanion")
		if ok then
			pcall(function()
				vim.cmd(cmd)
			end)
		else
			vim.notify("CodeCompanion not loaded", vim.log.levels.WARN)
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- PROVIDER SWITCHER
--
-- Two modes:
-- • cycle_provider(): rotates through PROVIDERS in order
--   (anthropic → openai → gemini → … → ollama → anthropic)
--   Updates all 3 strategies (chat, inline, cmd) simultaneously.
-- • select_provider(): interactive picker showing all providers
--   with API key availability status
-- ═══════════════════════════════════════════════════════════════════════

--- Cycle to the next provider in the PROVIDERS list and notify.
---
--- Reads the current adapter from `codecompanion.config.options.strategies`,
--- advances to the next index (wrapping around), and updates all
--- three strategies (chat, inline, cmd) simultaneously.
---
---@private
local function cycle_provider()
	local ok, _ = pcall(require, "codecompanion")
	if not ok then
		vim.notify("CodeCompanion not loaded", vim.log.levels.WARN)
		return
	end

	-- Get current
	local config_ok, config = pcall(require, "codecompanion.config")
	local current = "anthropic"
	if config_ok and config and config.options and config.options.strategies then
		local chat_adapter = config.options.strategies.chat and config.options.strategies.chat.adapter
		if chat_adapter then current = type(chat_adapter) == "string" and chat_adapter or current end
	end

	-- Find next
	local idx = 1
	for i, p in ipairs(PROVIDERS) do
		if p == current then
			idx = i
			break
		end
	end
	local next_p = PROVIDERS[(idx % #PROVIDERS) + 1]
	local info = PROVIDER_INFO[next_p] or {}

	-- Apply by reconfiguring all 3 strategies
	pcall(function()
		local cfg = require("codecompanion.config")
		if cfg and cfg.options and cfg.options.strategies then
			cfg.options.strategies.chat.adapter = next_p
			cfg.options.strategies.inline.adapter = next_p
			cfg.options.strategies.cmd.adapter = next_p
		end
	end)

	vim.notify(
		string.format("%s Switched to: %s\n   %s", info.icon or "🤖", info.name or next_p, info.description or ""),
		vim.log.levels.INFO,
		{ title = "CodeCompanion" }
	)
end

--- Show an interactive picker to select a provider.
---
--- Displays all providers from PROVIDERS with their display name,
--- icon, and API key availability (✅ if the environment variable
--- is set, ❌ if missing). Uses `vim.ui.select()` for the picker.
--- Updates all 3 strategies on selection.
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
	}, function(_, idx)
		if not idx then return end
		local selected = PROVIDERS[idx]
		local info = PROVIDER_INFO[selected] or {}

		pcall(function()
			local cfg = require("codecompanion.config")
			if cfg and cfg.options and cfg.options.strategies then
				cfg.options.strategies.chat.adapter = selected
				cfg.options.strategies.inline.adapter = selected
				cfg.options.strategies.cmd.adapter = selected
			end
		end)

		vim.notify(
			string.format("%s Now using: %s", info.icon or "🤖", info.name or selected),
			vim.log.levels.INFO,
			{ title = "CodeCompanion" }
		)
	end)
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
-- RESOLVED PROVIDERS
--
-- Detected once at spec evaluation time. Used in the strategies
-- section to route chat, inline, and cmd to the correct adapter.
-- ═══════════════════════════════════════════════════════════════════════

---@type string Resolved chat adapter name
local chat_provider = detect_provider()

---@type string Resolved inline/cmd adapter name
local inline_provider = detect_inline_provider()

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"olimorris/codecompanion.nvim",
	event = "VeryLazy",

	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-treesitter/nvim-treesitter",
		"nvim-mini/mini.icons",
		{
			"MeanderingProgrammer/render-markdown.nvim",
			optional = true,
			opts = {
				file_types = { "markdown", "codecompanion" },
			},
			ft = { "markdown", "codecompanion" },
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAPS
	-- ═══════════════════════════════════════════════════════════════════

	keys = {
		-- ── Action palette ────────────────────────────────────────────
		{
			"<leader>cca",
			cc_cmd("CodeCompanionActions"),
			mode = { "n", "v" },
			desc = ai_icon .. " Action palette",
		},

		-- ── Chat ──────────────────────────────────────────────────────
		{
			"<leader>ccc",
			cc_cmd("CodeCompanionChat Toggle"),
			mode = { "n", "v" },
			desc = ai_icon .. " Chat toggle",
		},
		{
			"<leader>ccq",
			cc_cmd("CodeCompanionChat Close"),
			desc = icon(ui, "Close", "×") .. " Close chat",
		},
		{
			"<leader>cch",
			cc_cmd("CodeCompanionChat History"),
			desc = icon(ui, "BookMark", "󰃀") .. " Chat history",
		},

		-- ── Inline ────────────────────────────────────────────────────
		{
			"<leader>cci",
			cc_cmd("CodeCompanion"),
			mode = { "n", "v" },
			desc = icon(ui, "Pencil", "●") .. " Inline assist",
		},

		-- ── Slash commands via keymaps ────────────────────────────────
		{
			"<leader>cce",
			cc_cmd("CodeCompanionChat Add /explain"),
			mode = { "n", "v" },
			desc = icon(ui, "Note", "󰎚") .. " Explain code",
		},
		{
			"<leader>ccf",
			cc_cmd("CodeCompanionChat Add /fix"),
			mode = { "n", "v" },
			desc = icon(ui, "Bug", " ") .. " Fix code",
		},
		{
			"<leader>cct",
			cc_cmd("CodeCompanionChat Add /tests"),
			mode = { "n", "v" },
			desc = icon(ui, "Target", "󰓾") .. " Generate tests",
		},
		{
			"<leader>ccd",
			cc_cmd("CodeCompanionChat Add /docs"),
			mode = { "n", "v" },
			desc = icon(ui, "Note", "󰎚") .. " Generate docs",
		},
		{
			"<leader>cco",
			cc_cmd("CodeCompanionChat Add /optimize"),
			mode = { "n", "v" },
			desc = icon(ui, "Rocket", "󰓅") .. " Optimize code",
		},
		{
			"<leader>ccr",
			cc_cmd("CodeCompanionChat Add /refactor"),
			mode = { "n", "v" },
			desc = icon(ui, "Code", "󰅩") .. " Refactor code",
		},

		-- ── Provider ──────────────────────────────────────────────────
		{
			"<leader>ccp",
			cycle_provider,
			desc = icon(ui, "Gear", "󰒓") .. " Cycle AI provider",
		},
		{
			"<leader>ccP",
			select_provider,
			desc = icon(ui, "Gear", "󰒓") .. " Select AI provider",
		},

		-- ── Help ──────────────────────────────────────────────────────
		{
			"<leader>ccH",
			function()
				vim.notify(
					table.concat({
						ai_icon .. " CodeCompanion — Slash Commands",
						string.rep("─", 45),
						"  /explain     — Explain selected code",
						"  /fix         — Fix bugs in selection",
						"  /tests       — Generate unit tests",
						"  /docs        — Generate documentation",
						"  /optimize    — Optimize for performance",
						"  /refactor    — Refactor code",
						"  /buffer      — Include buffer context",
						"  /lsp         — Include LSP diagnostics",
						"  /commit      — Generate commit message",
						string.rep("─", 45),
						"  #buffer      — Inject current buffer",
						"  #lsp         — Inject LSP info",
						"  #viewport    — Inject visible code",
						"  @editor      — Editor tool (apply changes)",
						"  @cmd_runner  — Run shell commands",
					}, "\n"),
					vim.log.levels.INFO,
					{ title = "CodeCompanion" }
				)
			end,
			desc = ai_icon .. " Commands cheatsheet",
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	-- ═══════════════════════════════════════════════════════════════════

	opts = {
		-- ── Adapters ─────────────────────────────────────────────────
		-- Each adapter is a factory function for lazy instantiation.
		-- Native adapters (anthropic, openai, gemini, ollama) extend
		-- their built-in counterparts. Custom vendors (deepseek, qwen,
		-- glm, kimi) extend openai_compatible.
		adapters = {
			anthropic = function()
				return require("codecompanion.adapters").extend("anthropic", {
					schema = {
						model = { default = "claude-sonnet-4-20250514" },
						max_tokens = { default = 8192 },
						temperature = { default = 0 },
					},
				})
			end,

			openai = function()
				return require("codecompanion.adapters").extend("openai", {
					schema = {
						model = { default = "gpt-5" },
						max_tokens = { default = 8192 },
						temperature = { default = 0 },
					},
				})
			end,

			gemini = function()
				return require("codecompanion.adapters").extend("gemini", {
					schema = {
						model = { default = "gemini-2.5-pro-preview-06-05" },
						max_tokens = { default = 8192 },
						temperature = { default = 0 },
					},
				})
			end,

			deepseek = function()
				return require("codecompanion.adapters").extend("openai_compatible", {
					env = { api_key = "DEEPSEEK_API_KEY" },
					url = "https://api.deepseek.com/chat/completions",
					schema = {
						model = { default = "deepseek-chat" },
						max_tokens = { default = 8192 },
						temperature = { default = 0 },
					},
				})
			end,

			qwen = function()
				return require("codecompanion.adapters").extend("openai_compatible", {
					env = { api_key = "DASHSCOPE_API_KEY" },
					url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
					schema = {
						model = { default = "qwen-plus" },
						max_tokens = { default = 8192 },
						temperature = { default = 0 },
					},
				})
			end,

			glm = function()
				return require("codecompanion.adapters").extend("openai_compatible", {
					env = { api_key = "GLM_API_KEY" },
					url = "https://open.bigmodel.cn/api/paas/v4/chat/completions",
					schema = {
						model = { default = "glm-5" },
						max_tokens = { default = 8192 },
						temperature = { default = 0 },
					},
				})
			end,

			kimi = function()
				return require("codecompanion.adapters").extend("openai_compatible", {
					env = { api_key = "MOONSHOT_API_KEY" },
					url = "https://api.moonshot.cn/v1/chat/completions",
					schema = {
						model = { default = "kimi-2.5" },
						max_tokens = { default = 8192 },
						temperature = { default = 0 },
					},
				})
			end,

			-- ── Ollama: URL and model from central settings ──────────
			ollama = function()
				return require("codecompanion.adapters").extend("ollama", {
					url = ollama_url .. "/api/chat",
					schema = {
						model = { default = ollama_chat_model },
						max_tokens = { default = 4096 },
						temperature = { default = 0 },
					},
				})
			end,
		},

		-- ── Strategies — adapter routing per interaction type ─────────
		strategies = {
			chat = {
				adapter = chat_provider,
				roles = {
					llm = ai_icon .. " AI",
					user = "👤 You",
				},
				keymaps = {
					close = { modes = { n = "q", i = "<C-c>" } },
					stop = { modes = { n = "<C-c>" } },
					send = { modes = { n = "<CR>", i = "<C-s>" } },
				},
			},
			inline = {
				adapter = inline_provider,
				keymaps = {
					accept_change = { modes = { n = "<leader>ccy" } },
					reject_change = { modes = { n = "<leader>ccn" } },
				},
			},
			cmd = {
				adapter = inline_provider,
			},
		},

		-- ── Slash commands ───────────────────────────────────────────
		slash_commands = {
			buffer = { opts = { provider = "snacks" } },
			file = { opts = { provider = "snacks" } },
			help = { opts = { provider = "snacks" } },
			symbols = { opts = { provider = "snacks" } },
		},

		-- ── Display ──────────────────────────────────────────────────
		display = {
			action_palette = {
				provider = "default",
				opts = {
					show_default_actions = true,
					show_default_prompt_library = true,
				},
			},
			chat = {
				window = {
					layout = "vertical",
					position = "right",
					width = 0.35,
					border = "rounded",
					opts = {
						wrap = true,
						linebreak = true,
						number = false,
						relativenumber = false,
						signcolumn = "no",
					},
				},
				intro_message = ai_icon .. " How can I help? (use /help for commands)",
				show_header_separator = true,
				separator = "─",
				show_references = true,
				show_settings = false,
				show_token_count = true,
			},
			inline = {
				diff = {
					enabled = true,
					priority = 130,
					hl_groups = {
						added = "DiffAdd",
						removed = "DiffDelete",
					},
				},
			},
		},

		-- ── Prompt library ───────────────────────────────────────────
		prompt_library = {
			["Code Review"] = {
				strategy = "chat",
				description = "Review code for bugs, security, and best practices",
				opts = { short_name = "review", auto_submit = true },
				prompts = {
					{
						role = "system",
						content = "You are a senior code reviewer. Review the code for bugs, security vulnerabilities, performance issues, and adherence to best practices. Be specific and actionable.",
					},
					{
						role = "user",
						content = "Please review this code:\n\n```${filetype}\n${buf}\n```",
					},
				},
			},
			["Commit Message"] = {
				strategy = "chat",
				description = "Generate a conventional commit message",
				opts = { short_name = "commit", auto_submit = true },
				prompts = {
					{
						role = "system",
						content = "You are a git commit message generator. Follow the Conventional Commits specification. Be concise. Output ONLY the commit message, nothing else.",
					},
					{
						role = "user",
						content = "Generate a commit message for these changes:\n\n```diff\n${git_diff}\n```",
					},
				},
			},
			["Explain Error"] = {
				strategy = "chat",
				description = "Explain an error message and suggest fixes",
				opts = { short_name = "error", auto_submit = false },
				prompts = {
					{
						role = "system",
						content = "You are a debugging expert. Explain the error clearly, identify the root cause, and provide specific fix suggestions with code examples.",
					},
					{
						role = "user",
						content = "Explain this error and suggest how to fix it:\n\n",
					},
				},
			},
			["Architecture"] = {
				strategy = "chat",
				description = "Discuss architecture and design patterns",
				opts = { short_name = "arch", auto_submit = false },
				prompts = {
					{
						role = "system",
						content = "You are a software architect. Discuss design patterns, SOLID principles, and architecture decisions. Provide concrete examples in the user's language/framework.",
					},
					{
						role = "user",
						content = "I'd like to discuss the architecture of this code:\n\n```${filetype}\n${buf}\n```\n\nMy question: ",
					},
				},
			},
		},

		-- ── General options ──────────────────────────────────────────
		opts = {
			log_level = "ERROR",
			send_code = true,
			use_default_actions = true,
			use_default_prompts = true,
			system_prompt = [[You are an expert software engineer.
You write clean, idiomatic, well-documented code.
When editing code, preserve the existing style and conventions.
Be concise in explanations unless asked for detail.
Always include the programming language in code fences.]],
		},
	},
}
