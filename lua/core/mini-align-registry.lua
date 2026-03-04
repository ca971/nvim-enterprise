---@file lua/core/mini-align-registry.lua
---@description MiniAlignRegistry — dynamic alignment preset registry with language awareness
---@module "core.mini-align-registry"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.mini-align Mini.align plugin spec (registers generic presets)
---@see core.settings Settings provider (languages.enabled drives awareness)
---@see core.icons Icon provider (preset icons reference)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/mini-align-registry.lua — Dynamic alignment preset registry        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  MiniAlignRegistry (singleton, stateful)                         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design Principles:                                              │    ║
--- ║  │  • Pure registry — NO hardcoded language presets                 │    ║
--- ║  │  • Generic presets registered by plugins/editor/mini-align.lua   │    ║
--- ║  │  • Language presets registered by each langs/<lang>.lua on       │    ║
--- ║  │    FileType event (lazy loading per filetype)                    │    ║
--- ║  │  • Aware of all enabled languages from settings but does NOT     │    ║
--- ║  │    load their presets until the filetype is actually opened      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Data Model:                                                     │    ║
--- ║  │  ┌────────────────────────────────────────────────────────┐      │    ║
--- ║  │  │  _presets        { name → MiniAlignPreset }            │      │    ║
--- ║  │  │  _ft_map         { filetype → default_preset_name }    │      │    ║
--- ║  │  │  _ft_presets     { filetype → [preset_name, ...] }     │      │    ║
--- ║  │  │  _enabled_langs  { lang_name → true }  (from settings) │      │    ║
--- ║  │  │  _loaded_langs   { lang_name → true }  (runtime state) │      │    ║
--- ║  │  └────────────────────────────────────────────────────────┘      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Lifecycle:                                                      │    ║
--- ║  │  ┌──────────┐    ┌─────────────┐    ┌──────────────────┐         │    ║
--- ║  │  │ Module   │───▶│ Read enabled│───▶│ _enabled_langs   │         │    ║
--- ║  │  │ require  │    │ from settings│    │ populated        │        │    ║
--- ║  │  └──────────┘    └─────────────┘    └──────────────────┘         │    ║
--- ║  │       │                                                          │    ║
--- ║  │       ▼                                                          │    ║
--- ║  │  ┌──────────┐    ┌─────────────┐    ┌──────────────────┐         │    ║
--- ║  │  │ mini-    │───▶│ register_   │───▶│ Generic presets  │         │    ║
--- ║  │  │ align.lua│    │ many()      │    │ available        │         │    ║
--- ║  │  └──────────┘    └─────────────┘    └──────────────────┘         │    ║
--- ║  │       │                                                          │    ║
--- ║  │       ▼                                                          │    ║
--- ║  │  ┌──────────┐    ┌─────────────┐    ┌──────────────────┐         │    ║
--- ║  │  │ FileType │───▶│ langs/      │───▶│ Lang presets     │         │    ║
--- ║  │  │ event    │    │ <lang>.lua  │    │ loaded on demand │         │    ║
--- ║  │  └──────────┘    └─────────────┘    └──────────────────┘         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Public API Groups:                                              │    ║
--- ║  │  ├─ Registration: register, register_many, unregister            │    ║
--- ║  │  ├─ Language awareness: is_language_enabled/loaded, get_*        │    ║
--- ║  │  ├─ Filetype mapping: set_ft_mapping(s), get_ft_default          │    ║
--- ║  │  ├─ Queries: get, get_all, get_by_category, get_for_filetype     │    ║
--- ║  │  ├─ Counting: count, count_generic, count_lang, count_by_cat     │    ║
--- ║  │  ├─ Hooks: on_register, on_language_loaded                       │    ║
--- ║  │  └─ Convenience: apply_preset, make_align_fn                     │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Enabled languages read once at module load (no repeated settings I/O) ║
--- ║  • Language presets loaded lazily on FileType (no eager loading)         ║
--- ║  • Filetype index (_ft_presets) avoids O(n) scans on every query         ║
--- ║  • Idempotent registration: re-registering is safe (no duplicates)       ║
--- ║  • Hook callbacks guarded with pcall (one bad hook won't break others)   ║
--- ║  • apply_preset uses feedkeys for seamless mini.align integration        ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════════════

---@class MiniAlignPreset
---@field description   string   Human-readable description
---@field icon          string   Nerd Font glyph from core.icons
---@field split_pattern string   Lua pattern for mini.align splitter
---@field category      string   Grouping label (e.g. "generic", "scripting")
---@field lang?         string   Language name matching langs/<lang>.lua (nil = generic)
---@field filetypes?    string[] Neovim filetypes this preset applies to

---@class MiniAlignRegistry
local M = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- INTERNAL STATE
--
-- All state is module-scoped (singleton pattern). The registry persists
-- for the lifetime of the Neovim session. State is never serialized to
-- disk — it is rebuilt on each startup from plugin specs and lang files.
-- ═══════════════════════════════════════════════════════════════════════════

--- All registered presets (generic + loaded language presets).
---@type table<string, MiniAlignPreset>
---@private
M._presets = {}

--- Filetype → default preset name (for smart auto-detection).
--- Set via `set_ft_mapping()`. Only one default per filetype.
---@type table<string, string>
---@private
M._ft_map = {}

--- Filetype → list of all preset names applicable to that filetype.
--- Populated automatically during `register()` when a preset declares `filetypes`.
---@type table<string, string[]>
---@private
M._ft_presets = {}

--- Set of enabled language names from `settings.languages.enabled`.
--- Built once at module load time. Keys are language names, values are `true`.
---@type table<string, boolean>
---@private
M._enabled_languages = {}

--- Set of languages whose presets have been registered (loaded).
--- A language is "loaded" after its `langs/<lang>.lua` calls `register_many()`
--- and then `mark_language_loaded()`.
---@type table<string, boolean>
---@private
M._loaded_languages = {}

--- Callbacks invoked after any preset registration.
---@type (fun(name: string, preset: MiniAlignPreset))[]
---@private
M._on_register_callbacks = {}

--- Callbacks invoked when a language's presets are first loaded.
---@type (fun(lang: string, presets: table<string, MiniAlignPreset>))[]
---@private
M._on_language_loaded_callbacks = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
--
-- Read enabled languages from settings exactly once at module load time.
-- This avoids repeated settings I/O on every query. The set is immutable
-- after initialization — adding/removing languages requires restarting.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local ok, settings = pcall(require, "core.settings")
	if ok and settings then
		local enabled = settings:get("languages.enabled", {})
		for _, lang in ipairs(enabled) do
			M._enabled_languages[lang] = true
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LANGUAGE AWARENESS
--
-- These functions expose the registry's knowledge of which languages
-- are enabled (from settings) vs which have actually loaded their
-- presets (at runtime). This distinction enables:
--   • UI indicators showing "pending" vs "ready" languages
--   • Health checks validating that lang files call mark_language_loaded()
--   • Lazy loading: presets are only loaded when the filetype is opened
-- ═══════════════════════════════════════════════════════════════════════════

--- Get the full list of enabled languages from settings.
---@return string[] languages Sorted list of enabled language names
function M.get_enabled_languages()
	local langs = vim.tbl_keys(M._enabled_languages)
	table.sort(langs)
	return langs
end

--- Check if a language is enabled in settings.
---@param lang string Language name (e.g. "lua", "rust")
---@return boolean enabled Whether the language is in `settings.languages.enabled`
function M.is_language_enabled(lang)
	return M._enabled_languages[lang] == true
end

--- Check if a language's presets have been loaded into the registry.
---
--- A language is "loaded" after its `langs/<lang>.lua` file calls
--- `register_many()` and then `mark_language_loaded()`.
---@param lang string Language name
---@return boolean loaded Whether the language's presets are in the registry
function M.is_language_loaded(lang)
	return M._loaded_languages[lang] == true
end

--- Get all languages whose presets are currently loaded.
---@return string[] languages Sorted list of loaded language names
function M.get_loaded_languages()
	local langs = vim.tbl_keys(M._loaded_languages)
	table.sort(langs)
	return langs
end

--- Get languages that are enabled but whose presets are not yet loaded.
---
--- These are languages waiting for their FileType event to fire.
---@return string[] languages Sorted list of pending language names
function M.get_pending_languages()
	local pending = {}
	for lang in pairs(M._enabled_languages) do
		if not M._loaded_languages[lang] then pending[#pending + 1] = lang end
	end
	table.sort(pending)
	return pending
end

--- Mark a language as having its presets loaded.
---
--- Called by each `langs/<lang>.lua` after registering its presets.
--- This triggers all `on_language_loaded` callbacks with the language
--- name and a table of its presets. Idempotent: calling twice is a no-op.
---@param lang string Language name (must match the key in `settings.languages.enabled`)
---@return nil
function M.mark_language_loaded(lang)
	if M._loaded_languages[lang] then
		return -- Already marked, idempotent
	end

	M._loaded_languages[lang] = true

	-- Collect the presets that belong to this language
	local lang_presets = {}
	for name, preset in pairs(M._presets) do
		if preset.lang == lang then lang_presets[name] = preset end
	end

	-- Fire language-loaded callbacks
	for _, cb in ipairs(M._on_language_loaded_callbacks) do
		local cb_ok, err = pcall(cb, lang, lang_presets)
		if not cb_ok then
			vim.schedule(function()
				vim.notify(
					string.format("[mini-align-registry] on_language_loaded callback error: %s", err),
					vim.log.levels.WARN,
					{ title = "mini-align-registry" }
				)
			end)
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- REGISTRATION
--
-- Core registration API. Presets are validated on registration to catch
-- schema errors early (missing description, pattern, etc.). The filetype
-- index (_ft_presets) is maintained automatically during registration
-- and cleanup during unregistration.
-- ═══════════════════════════════════════════════════════════════════════════

--- Register a single alignment preset.
---
--- If the preset declares a `filetypes` field, it is automatically
--- indexed for filetype-based lookups via `get_for_filetype()`.
--- Re-registering a preset with the same name silently overwrites it.
---@param name   string           Unique preset identifier (e.g. "lua_table_value")
---@param preset MiniAlignPreset  Preset definition table
---@return nil
function M.register(name, preset)
	vim.validate({
		name = { name, "string" },
		preset = { preset, "table" },
		["preset.description"] = { preset.description, "string" },
		["preset.split_pattern"] = { preset.split_pattern, "string" },
		["preset.category"] = { preset.category, "string" },
		["preset.icon"] = { preset.icon, "string" },
	})

	M._presets[name] = preset

	-- ── Index by filetypes ───────────────────────────────────────────
	if preset.filetypes and type(preset.filetypes) == "table" then
		for _, ft in ipairs(preset.filetypes) do
			if not M._ft_presets[ft] then M._ft_presets[ft] = {} end
			-- Avoid duplicates (idempotent registration)
			local already = false
			for _, existing in ipairs(M._ft_presets[ft]) do
				if existing == name then
					already = true
					break
				end
			end
			if not already then table.insert(M._ft_presets[ft], name) end
		end
	end

	-- ── Fire on_register callbacks ───────────────────────────────────
	for _, cb in ipairs(M._on_register_callbacks) do
		local cb_ok, err = pcall(cb, name, preset)
		if not cb_ok then
			vim.schedule(function()
				vim.notify(
					string.format("[mini-align-registry] on_register callback error: %s", err),
					vim.log.levels.WARN,
					{ title = "mini-align-registry" }
				)
			end)
		end
	end
end

--- Register multiple presets at once.
---
--- Convenience wrapper around `register()`. Each entry in the table
--- is validated individually.
---@param presets table<string, MiniAlignPreset> Map of name → preset definition
---@return nil
function M.register_many(presets)
	vim.validate({ presets = { presets, "table" } })
	for name, preset in pairs(presets) do
		M.register(name, preset)
	end
end

--- Remove a preset from the registry.
---
--- Cleans up the filetype index (`_ft_presets`) and filetype default
--- mapping (`_ft_map`) to prevent stale references.
---@param name string Preset name to remove
---@return boolean removed Whether the preset existed and was removed
function M.unregister(name)
	if not M._presets[name] then return false end

	local preset = M._presets[name]
	M._presets[name] = nil

	-- ── Clean up filetype index ──────────────────────────────────────
	if preset.filetypes then
		for _, ft in ipairs(preset.filetypes) do
			local list = M._ft_presets[ft]
			if list then
				for i, n in ipairs(list) do
					if n == name then
						table.remove(list, i)
						break
					end
				end
				if #list == 0 then M._ft_presets[ft] = nil end
			end
		end
	end

	-- ── Clean up ft_map references ───────────────────────────────────
	for ft, mapped_name in pairs(M._ft_map) do
		if mapped_name == name then M._ft_map[ft] = nil end
	end

	return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FILETYPE MAPPING
--
-- Maps filetypes to their "default" alignment preset. This is separate
-- from the _ft_presets index (which lists ALL applicable presets).
-- The ft_map provides a single recommended preset per filetype for
-- one-keypress alignment workflows.
-- ═══════════════════════════════════════════════════════════════════════════

--- Set the default preset for a given filetype.
---@param ft   string Neovim filetype (e.g. "lua", "rust")
---@param name string Preset name that should be the default for this filetype
---@return nil
function M.set_ft_mapping(ft, name)
	M._ft_map[ft] = name
end

--- Set default presets for multiple filetypes at once.
---@param mappings table<string, string> Map of filetype → preset name
---@return nil
function M.set_ft_mappings(mappings)
	for ft, name in pairs(mappings) do
		M._ft_map[ft] = name
	end
end

--- Get the default preset name for a filetype.
---@param ft string Neovim filetype
---@return string|nil name Default preset name, or `nil` if no mapping exists
function M.get_ft_default(ft)
	return M._ft_map[ft]
end

-- ═══════════════════════════════════════════════════════════════════════════
-- QUERIES
--
-- Read-only accessors for the registry. All query functions return
-- copies or computed results — they never expose mutable internal state.
-- The filetype query (`get_for_filetype`) merges generic presets with
-- filetype-specific ones, providing a complete menu for the user.
-- ═══════════════════════════════════════════════════════════════════════════

--- Get a preset by name.
---@param name string Preset identifier
---@return MiniAlignPreset|nil preset The preset definition, or `nil` if not found
function M.get(name)
	return M._presets[name]
end

--- Get all registered presets (shallow copy).
---@return table<string, MiniAlignPreset> presets Copy of the full preset map
function M.get_all()
	return vim.tbl_extend("force", {}, M._presets)
end

--- Get ONLY generic presets (those with `category == "generic"`).
---@return table<string, MiniAlignPreset> presets Filtered preset map
function M.get_generic_presets()
	local result = {}
	for name, preset in pairs(M._presets) do
		if preset.category == "generic" then result[name] = preset end
	end
	return result
end

--- Get all presets belonging to a specific category.
---@param category string Category name (e.g. "generic", "scripting", "systems")
---@return table<string, MiniAlignPreset> presets Filtered preset map
function M.get_by_category(category)
	local result = {}
	for name, preset in pairs(M._presets) do
		if preset.category == category then result[name] = preset end
	end
	return result
end

--- Get all presets applicable to a specific filetype.
---
--- Returns the union of:
---   1. All generic presets (`category == "generic"`)
---   2. All presets whose `filetypes` list contains `ft`
---
--- This provides the complete alignment menu for a given buffer.
---@param ft string Neovim filetype
---@return table<string, MiniAlignPreset> presets Merged preset map (generic + ft-specific)
function M.get_for_filetype(ft)
	local result = {}

	-- 1. Always include generic presets
	for name, preset in pairs(M._presets) do
		if preset.category == "generic" then result[name] = preset end
	end

	-- 2. Include presets indexed for this filetype
	local ft_names = M._ft_presets[ft]
	if ft_names then
		for _, name in ipairs(ft_names) do
			local preset = M._presets[name]
			if preset then result[name] = preset end
		end
	end

	return result
end

--- Get ONLY filetype-specific presets (excludes generic).
---@param ft string Neovim filetype
---@return table<string, MiniAlignPreset> presets Filetype-only preset map
function M.get_ft_presets_only(ft)
	local result = {}
	local ft_names = M._ft_presets[ft]
	if ft_names then
		for _, name in ipairs(ft_names) do
			local preset = M._presets[name]
			if preset then result[name] = preset end
		end
	end
	return result
end

--- Check if a preset is registered.
---@param name string Preset identifier
---@return boolean registered Whether the preset exists in the registry
function M.is_registered(name)
	return M._presets[name] ~= nil
end

--- Return the total number of registered presets.
---@return integer count Total presets (generic + language)
function M.count()
	return vim.tbl_count(M._presets)
end

--- Return the count of generic presets only.
---@return integer count Number of presets with `category == "generic"`
function M.count_generic()
	return vim.tbl_count(M.get_generic_presets())
end

--- Return the count of language presets only (those with a `lang` field).
---@return integer count Number of language-specific presets
function M.count_lang()
	local count = 0
	for _, preset in pairs(M._presets) do
		if preset.lang then count = count + 1 end
	end
	return count
end

--- Return preset counts grouped by category.
---@return table<string, integer> counts Map of category → count
function M.count_by_category()
	local counts = {}
	for _, preset in pairs(M._presets) do
		local cat = preset.category or "other"
		counts[cat] = (counts[cat] or 0) + 1
	end
	return counts
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HOOKS
--
-- Event hooks allow external modules to react to registry changes
-- without polling. Callbacks are guarded with pcall so one failing
-- hook does not prevent others from running.
-- ═══════════════════════════════════════════════════════════════════════════

--- Register a callback invoked after each preset registration.
---
--- Useful for dynamically updating UI elements (e.g., which-key
--- groups, statusline alignment indicators) as presets are added.
---@param callback fun(name: string, preset: MiniAlignPreset) Hook function
---@return nil
function M.on_register(callback)
	vim.validate({ callback = { callback, "function" } })
	table.insert(M._on_register_callbacks, callback)
end

--- Register a callback invoked when a language's presets are first loaded.
---
--- The callback receives the language name and a table of its presets.
--- Useful for updating which-key groups or statusline dynamically
--- when a new filetype is opened for the first time in a session.
---@param callback fun(lang: string, presets: table<string, MiniAlignPreset>) Hook function
---@return nil
function M.on_language_loaded(callback)
	vim.validate({ callback = { callback, "function" } })
	table.insert(M._on_language_loaded_callbacks, callback)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CONVENIENCE: ALIGNMENT EXECUTION
--
-- These functions bridge the registry with mini.align's input system.
-- `apply_preset` sends the appropriate keystrokes to trigger alignment
-- using feedkeys, which integrates naturally with mini.align's visual
-- mode workflow. `make_align_fn` returns a closure suitable for keymap
-- definitions.
-- ═══════════════════════════════════════════════════════════════════════════

--- Apply a named preset — sends the key sequence to mini.align.
---
--- Looks up the preset by name, shows a notification with its icon
--- and description, then feeds the `gA<pattern><CR>` key sequence
--- to trigger mini.align's interactive alignment.
---@param name string Preset name to apply
---@return boolean success Whether the preset was found and applied
function M.apply_preset(name)
	local preset = M._presets[name]
	if not preset then
		vim.schedule(function()
			vim.notify(string.format("mini.align: unknown preset '%s'", name), vim.log.levels.WARN, { title = "mini.align" })
		end)
		return false
	end

	vim.schedule(function()
		vim.notify(string.format("%s  %s", preset.icon, preset.description), vim.log.levels.INFO, { title = "mini.align" })
	end)

	vim.api.nvim_feedkeys(
		vim.api.nvim_replace_termcodes(string.format("gA%s<CR>", preset.split_pattern), true, false, true),
		"x",
		false
	)
	return true
end

--- Return a function that applies a named preset when called.
---
--- Suitable for keymap `rhs` values or lazy callback definitions.
--- The returned closure captures the preset name by value.
---@param name string Preset name to bind
---@return fun() align_fn Zero-argument function that calls `apply_preset(name)`
function M.make_align_fn(name)
	return function()
		M.apply_preset(name)
	end
end

return M
