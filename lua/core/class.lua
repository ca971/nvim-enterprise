---@file lua/core/class.lua
---@description Class — lightweight OOP system with single inheritance, mixins and runtime type checking
---@module "core.class"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (extends Class)
---@see core.logger Logger singleton (extends Class)
---@see config.plugin_manager PluginManager (extends Class)
---@see config.settings_manager SettingsManager (extends Class)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/class.lua — OOP class system (single inheritance + mixins)         ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Class (base metatable)                                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  • Single inheritance via :extend("Name")                        │    ║
--- ║  │  • Constructor pattern: :new(...) delegates to :init(...)        │    ║
--- ║  │  • Callable syntax: MyClass(...) ≡ MyClass:new(...)              │    ║
--- ║  │  • Mixin composition via :include(mixin_table)                   │    ║
--- ║  │  • Runtime type checking via :instanceof(klass)                  │    ║
--- ║  │  • Parent delegation via :super_call("method", ...)              │    ║
--- ║  │  • Automatic metamethod inheritance (__tostring, __eq, …)        │    ║
--- ║  │  • Human-readable repr: <ClassName instance> / <class Name>      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Inheritance chain (this config):                                │    ║
--- ║  │    Class                                                         │    ║
--- ║  │    ├─ Settings         (core/settings.lua)                       │    ║
--- ║  │    ├─ Logger           (core/logger.lua)                         │    ║
--- ║  │    ├─ Platform         (core/platform.lua)                       │    ║
--- ║  │    ├─ PluginManager    (config/plugin_manager.lua)               │    ║
--- ║  │    ├─ SettingsManager  (config/settings_manager.lua)             │    ║
--- ║  │    └─ UserManager      (users/user_manager.lua)                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ Metamethods (__*) are shallow-copied into subclasses so      │    ║
--- ║  │  │  Lua can resolve them without walking the __index chain       │    ║
--- ║  │  │  (Lua only checks the immediate metatable for __tostring)     │    ║
--- ║  │  ├─ :include() protects core methods (init, new, extend,         │    ║
--- ║  │  │  include) to prevent accidental override from mixins          │    ║
--- ║  │  ├─ :instanceof() walks __super (not __index) to verify          │    ║
--- ║  │  │  actual class lineage, not just method availability           │    ║
--- ║  │  └─ No multiple inheritance — keeps the system predictable       │    ║
--- ║  │     and debuggable for a Neovim configuration context            │    ║
--- ║  │                                                                  │    ║
--- ║  │  LuaLS annotations:                                              │    ║
--- ║  │  ├─ :extend() and :new() use @generic T to propagate the         │    ║
--- ║  │  │  concrete @class type declared by consumers (Platform, etc.)  │    ║
--- ║  │  ├─ :include() uses @generic T for fluent chaining               │    ║
--- ║  │  └─ This eliminates assign-type-mismatch / param-type-mismatch   │    ║
--- ║  │     warnings in all subclass files without per-site casts        │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Zero external dependencies (pure Lua metatable manipulation)          ║
--- ║  • No runtime allocation beyond initial class/instance tables            ║
--- ║  • Loaded once at startup, cached by require() module system             ║
--- ║  • Metamethod copy is O(n) on class fields, runs once per :extend()      ║
--- ║                                                                          ║
--- ║  Public API:                                                             ║
--- ║    Class:extend(name)              Create a named subclass               ║
--- ║    Class:new(...)                  Instantiate → calls :init(...)        ║
--- ║    Class:init(...)                 Override in subclasses (no-op base)   ║
--- ║    Class:include(mixin)           Mix in methods from a table            ║
--- ║    Class:instanceof(klass)        Walk __super chain for type check      ║
--- ║    Class:class_name()             Return __name string                   ║
--- ║    Class:super()                  Return __super reference               ║
--- ║    Class:super_call(method, ...)  Delegate to parent implementation      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════
-- CLASS DEFINITION
-- ═══════════════════════════════════════════════════════════════════════

---@class Class
---@field __name string Human-readable class name used in tostring() and error messages
---@field __super Class|nil Parent class reference for inheritance chain traversal
local Class = {}
Class.__index = Class
Class.__name = "Class"
Class.__super = nil

-- ═══════════════════════════════════════════════════════════════════════
-- INHERITANCE
--
-- Subclassing is the primary extension mechanism. Each call to
-- :extend() creates a new table that inherits methods from its
-- parent via __index, while metamethods are shallow-copied so
-- Lua can resolve them on the immediate metatable (required by
-- the Lua spec for __tostring, __eq, __len, etc.).
-- ═══════════════════════════════════════════════════════════════════════

--- Create a new subclass that inherits from this class.
---
--- Metamethods (keys starting with `"__"`) are shallow-copied into the
--- subclass so Lua resolves them directly on the metatable without
--- walking the `__index` chain (required for `__tostring`, `__eq`, etc.).
---
--- The returned subclass is callable: `MyClass(...)` is equivalent to
--- `MyClass:new(...)`.
---
--- ```lua
--- local Animal = Class:extend("Animal")
--- local Dog = Animal:extend("Dog")
--- local rex = Dog("Rex")  -- calls Dog:new("Rex") → Dog:init("Rex")
--- ```
---
---@generic T : Class
---@param self T
---@param name? string Human-readable class name (default: `"Anonymous"`)
---@return T subclass New class table inheriting from `self`
function Class:extend(name)
	local subclass = {}

	-- Shallow-copy metamethods from parent into subclass.
	-- Lua only checks the immediate metatable for __tostring, __eq, etc.
	-- so these must live directly on the subclass table, not behind __index.
	for k, v in pairs(self) do
		if k:find("^__") then subclass[k] = v end
	end

	subclass.__index = subclass
	subclass.__name = name or "Anonymous"
	subclass.__super = self

	-- Set up the subclass metatable:
	-- • __index → parent class (method inheritance via chain lookup)
	-- • __call  → constructor shorthand: MyClass(...) ≡ MyClass:new(...)
	-- • __tostring → human-readable class representation
	return setmetatable(subclass, {
		__index = self,
		__call = function(cls, ...)
			return cls:new(...)
		end,
		__tostring = function()
			return string.format("<class %s>", subclass.__name)
		end,
	})
end

-- ═══════════════════════════════════════════════════════════════════════
-- INSTANTIATION
--
-- Two-phase construction: :new() allocates the instance table and
-- sets the metatable, then delegates to :init() for state setup.
-- Subclasses override :init(), never :new().
-- ═══════════════════════════════════════════════════════════════════════

--- Create a new instance of this class.
---
--- Allocates a new table with `self` as its metatable, then calls
--- `self:init(...)` if defined. All method lookups on the instance
--- delegate to the class (and up the inheritance chain) via `__index`.
---
--- ```lua
--- local dog = Dog:new("Rex", 3)
--- -- or equivalently:
--- local dog = Dog("Rex", 3)
--- ```
---
---@generic T : Class
---@param self T
---@param ... any Arguments forwarded to `self:init(...)`
---@return T instance New instance with `self` as metatable
function Class:new(...)
	local instance = setmetatable({}, self)
	if instance.init then instance:init(...) end
	return instance
end

--- Default initializer — override in subclasses.
---
--- Called automatically by `:new(...)`. The base implementation is a
--- no-op; subclasses should override this to set up instance state.
---
--- ```lua
--- function MyClass:init(name, age)
---   self.name = name
---   self.age = age
--- end
--- ```
---
---@param ... any Subclass-defined initialization arguments
function Class:init(...) end

-- ═══════════════════════════════════════════════════════════════════════
-- COMPOSITION
--
-- Mixins provide horizontal code reuse without multiple inheritance.
-- Core methods are protected to preserve class system integrity.
-- ═══════════════════════════════════════════════════════════════════════

--- Mix in methods from another table (mixin / trait pattern).
---
--- Copies all key-value pairs from `mixin` into `self`, except for
--- protected core methods (`init`, `new`, `extend`, `include`) which
--- are never overwritten to preserve class system integrity.
---
--- ```lua
--- local Serializable = {
---   serialize = function(self) return vim.inspect(self) end,
--- }
--- MyClass:include(Serializable)
--- ```
---
---@generic T : Class
---@param self T
---@param mixin table Table of methods/values to copy into this class
---@return T self Returns `self` for method chaining
function Class:include(mixin)
	assert(type(mixin) == "table", "Class:include() expects a table")

	-- These methods form the class system's core contract and must
	-- never be overwritten by a mixin — doing so would break
	-- construction, inheritance, or composition itself.
	local protected = { init = true, new = true, extend = true, include = true }

	for k, v in pairs(mixin) do
		if not protected[k] then self[k] = v end
	end
	return self
end

-- ═══════════════════════════════════════════════════════════════════════
-- INTROSPECTION
--
-- Runtime type checking and class metadata access. :instanceof()
-- walks the __super chain (not __index) to verify actual lineage.
-- ═══════════════════════════════════════════════════════════════════════

--- Check whether this instance belongs to a given class or any ancestor.
---
--- Walks up the `__super` chain (not `__index`) to verify actual class
--- lineage. This distinguishes the "is-a" relationship from mere
--- method availability through mixins.
---
--- NOTE: designed for instance checks, not class-to-class comparison.
---
--- ```lua
--- local dog = Dog("Rex")
--- dog:instanceof(Dog)    -- true
--- dog:instanceof(Animal) -- true  (Dog extends Animal)
--- dog:instanceof(Class)  -- true  (everything extends Class)
--- ```
---
---@param klass Class The class to check against
---@return boolean is_instance `true` if `self` is an instance of `klass` or a subclass thereof
function Class:instanceof(klass)
	local cls = getmetatable(self)
	while cls do
		if cls == klass then return true end
		cls = cls.__super
	end
	return false
end

--- Get the human-readable class name.
---
---@return string name The `__name` field, or `"Unknown"` if unset
function Class:class_name()
	return self.__name or "Unknown"
end

--- Get the parent (super) class reference.
---
---@return Class|nil parent The `__super` reference, or `nil` for the root `Class`
function Class:super()
	return self.__super
end

--- Call a method on the parent class with the current instance as `self`.
---
--- Useful for extending (not replacing) parent behavior in overridden methods:
---
--- ```lua
--- function Dog:init(name)
---   self:super_call("init", name) -- call Animal:init(name)
---   self.tricks = {}
--- end
--- ```
---
---@param method string Method name to call on the parent class
---@param ... any Arguments forwarded to the parent method
---@return any result Return value(s) from the parent method
function Class:super_call(method, ...)
	local parent = self.__super
	if parent and type(parent[method]) == "function" then return parent[method](self, ...) end
	error(string.format("No method '%s' on super class of %s", method, self.__name))
end

-- ═══════════════════════════════════════════════════════════════════════
-- METAMETHODS
-- ═══════════════════════════════════════════════════════════════════════

--- Human-readable string representation for instances.
---
--- Produces `<ClassName instance>` for instances. Class tables use the
--- `__tostring` set in their metatable by `:extend()`, which produces
--- `<class ClassName>` instead.
---
---@return string repr Formatted string `<ClassName instance>`
function Class:__tostring()
	return string.format("<%s instance>", self.__name or "Class")
end

return Class
