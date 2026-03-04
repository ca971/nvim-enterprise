---@file lua/users/init.lua
---@description Active user loader — loads user settings, keymaps, plugins and customizations after core setup
---@module "users"
---@author ca971
---@license MIT
---@version 1.1.0
---@since 2026-01
---
---@see users.namespace      Namespace resolution and file loading
---@see users.user_manager   User CRUD, switching, and lifecycle management
---@see core.settings        Active user detection (`active_user` key)
---@see core.logger          Structured logging for user loading events
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  users/init.lua — Active user loader                                     ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  M.setup() — called AFTER lazy.nvim has loaded all plugins       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Flow:                                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Read active_user from core/settings                  │    │    ║
--- ║  │  │  2. Create Namespace instance for that user              │    │    ║
--- ║  │  │  3. Guard: skip if namespace directory doesn't exist     │    │    ║
--- ║  │  │  4. Load user settings   (overrides core/settings)       │    │    ║
--- ║  │  │  5. Load user keymaps    (applied AFTER default keymaps) │    │    ║
--- ║  │  │  6. Load user plugins    (merged into lazy.nvim)         │    │    ║
--- ║  │  │  7. Load user init       (post-plugin customization)     │    │    ║
--- ║  │  │  8. Log result                                           │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  File system layout:                                             │    ║
--- ║  │    lua/users/                                                    │    ║
--- ║  │    ├─ init.lua              ← this file (entry point)            │    ║
--- ║  │    ├─ namespace.lua         ← user namespace resolution          │    ║
--- ║  │    ├─ user_manager.lua      ← user CRUD & switching              │    ║
--- ║  │    ├─ default/              ← default user (always present)      │    ║
--- ║  │    │  ├─ init.lua           ← post-plugin customization          │    ║
--- ║  │    │  ├─ keymaps.lua        ← user-specific keymaps              │    ║
--- ║  │    │  ├─ settings.lua       ← user-specific settings overrides   │    ║
--- ║  │    │  └─ plugins/                                                │    ║
--- ║  │    │     └─ init.lua        ← user-specific plugin specs         │    ║
--- ║  │    ├─ bly/                                                       │    ║
--- ║  │    │  ├─ init.lua                                                │    ║
--- ║  │    │  ├─ keymaps.lua                                             │    ║
--- ║  │    │  ├─ settings.lua                                            │    ║
--- ║  │    │  └─ plugins/                                                │    ║
--- ║  │    │     └─ init.lua                                             │    ║
--- ║  │    └─ jane/                                                      │    ║
--- ║  │       ├─ init.lua                                                │    ║
--- ║  │       ├─ keymaps.lua                                             │    ║
--- ║  │       ├─ settings.lua                                            │    ║
--- ║  │       └─ plugins/                                                │    ║
--- ║  │          └─ init.lua                                             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Per-user file responsibilities:                                 │    ║
--- ║  │  ┌──────────────┬───────────────────────────────────────────┐    │    ║
--- ║  │  │ File         │ Purpose                                   │    │    ║
--- ║  │  ├──────────────┼───────────────────────────────────────────┤    │    ║
--- ║  │  │ settings.lua │ Override core/settings values             │    │    ║
--- ║  │  │              │ (colorscheme, languages, editor prefs)    │    │    ║
--- ║  │  │ keymaps.lua  │ User-specific key bindings                │    │    ║
--- ║  │  │              │ (applied after defaults — can override)   │    │    ║
--- ║  │  │ plugins/     │ Extra plugin specs merged into lazy.nvim  │    │    ║
--- ║  │  │  init.lua    │ (user-only plugins, not in base config)   │    │    ║
--- ║  │  │ init.lua     │ Post-plugin customization (runs last)     │    │    ║
--- ║  │  │              │ (autocmds, highlights, option tweaks)     │    │    ║
--- ║  │  └──────────────┴───────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Ordering guarantees:                                            │    ║
--- ║  │  ┌────────────────────────────────────────────────────────┐      │    ║
--- ║  │  │  core/settings    ← base defaults                      │      │    ║
--- ║  │  │       ↓                                                │      │    ║
--- ║  │  │  user/settings    ← user overrides merged in           │      │    ║
--- ║  │  │       ↓                                                │      │    ║
--- ║  │  │  core/keymaps     ← default keymaps                    │      │    ║
--- ║  │  │       ↓                                                │      │    ║
--- ║  │  │  user/keymaps     ← user keymaps (can shadow defaults) │      │    ║
--- ║  │  │       ↓                                                │      │    ║
--- ║  │  │  lazy.nvim        ← plugins loaded (incl. user specs)  │      │    ║
--- ║  │  │       ↓                                                │      │    ║
--- ║  │  │  user/init        ← final customization (runs last)    │      │    ║
--- ║  │  └────────────────────────────────────────────────────────┘      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Adding a new user:                                              │    ║
--- ║  │  1. Run :UserCreate <username>  (via user_manager.lua)           │    ║
--- ║  │     — or manually create lua/users/<username>/                   │    ║
--- ║  │  2. Add settings.lua, keymaps.lua, plugins/init.lua, init.lua    │    ║
--- ║  │  3. Set active_user = "<username>" in core/settings              │    ║
--- ║  │     — or run :UserSwitch                                         │    ║
--- ║  │  4. Restart Neovim — done                                        │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Only runs once at startup (called from init.lua after lazy.nvim)      ║
--- ║  • Early return if namespace doesn't exist (no file I/O wasted)          ║
--- ║  • Each load step is independent — missing files are silently skipped    ║
--- ║  • Logger module cached at require time (not per-call)                   ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════

local Namespace = require("users.namespace")
local Logger = require("core.logger")

---@type Logger
local log = Logger:for_module("users")

-- ═══════════════════════════════════════════════════════════════════════
-- MODULE
-- ═══════════════════════════════════════════════════════════════════════

local M = {}

--- Load the active user's customizations.
---
--- Called **after** lazy.nvim has loaded all plugins. This ensures that
--- user keymaps can safely reference plugin commands and that user init
--- code can configure plugins that are already available.
---
--- Loading order (each step is optional — missing files are skipped):
--- 1. `settings.lua` — merged into `core/settings` (overrides defaults)
--- 2. `keymaps.lua`  — applied after default keymaps (can shadow them)
--- 3. `plugins/`     — user plugin specs already merged by lazy.nvim
--- 4. `init.lua`     — final post-plugin customization (runs last)
---
--- ```lua
--- -- Called from your top-level init.lua:
--- require("users").setup()
--- ```
function M.setup()
	local settings = require("core.settings")

	---@type string
	local active_user = settings:get("active_user", "default")

	---@type Namespace
	local ns = Namespace:new(active_user)

	-- ── Guard: namespace must exist ──────────────────────────────────
	if not ns:exists() then
		log:debug("User namespace '%s' does not exist — skipping", active_user)
		return
	end

	-- ── 1. Load user settings (overrides core/settings defaults) ─────
	ns:load_settings()

	-- ── 2. Load user keymaps (applied after default keymaps) ─────────
	ns:load_keymaps()

	-- ── 3. User plugins are loaded by lazy.nvim via plugin spec ──────
	-- User plugin specs in users/<name>/plugins/init.lua are
	-- discovered by lazy.nvim's import mechanism — no manual
	-- loading needed here. This comment documents the ordering.

	-- ── 4. Load user init (post-plugin customization, runs last) ─────
	ns:load_init()

	log:info("Loaded user customizations for '%s'", active_user)
end

return M
