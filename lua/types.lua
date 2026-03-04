---@file lua/types.lua
---@description Global type definitions for lua_ls — eliminates warnings and enables IDE autocompletion
---@module "types"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
--- This file is NOT required at runtime. It exists solely for lua_ls
--- static analysis. It must be in the workspace root or a path included
--- in lua_ls settings (`.luarc.json` → `workspace.library`).
---
--- Convention: all types are defined as @class with @field annotations.
--- Runtime modules return values that conform to these shapes.

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM
-- ═══════════════════════════════════════════════════════════════════════════

---@class lazy.PluginSpec

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE.ICONS
-- ═══════════════════════════════════════════════════════════════════════════

---@class IconsUI

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE.SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════

---@class Settings : Class

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE.CLASS
-- ═══════════════════════════════════════════════════════════════════════════

---@class Class

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE.LOGGER
-- ═══════════════════════════════════════════════════════════════════════════

---@class Logger

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE.UTILS
-- ═══════════════════════════════════════════════════════════════════════════

---@class CoreUtils

-- ═══════════════════════════════════════════════════════════════════════════
-- CORE.PLATFORM
-- ═══════════════════════════════════════════════════════════════════════════

---@class PlatformInfo
