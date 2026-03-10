# 🔌 Adding a Plugin

## 1. Choose a Category

| Folder | Content |
| --- | --- |
| `plugins/ai/` | AI assistants |
| `plugins/code/` | Completion, LSP, Treesitter, formatting |
| `plugins/editor/` | Navigation, files, search |
| `plugins/ui/` | Statusline, tabline, notifications |
| `plugins/tools/` | Terminal, Git, debugging |
| `plugins/misc/` | Everything else |

## 2. Create the File

```bash
nvim lua/plugins/editor/my-plugin.lua
```

## 3. Standard Structure

```lua
---@file lua/plugins/editor/my-plugin.lua
---@description My Plugin — short description
---@module "plugins.editor.my-plugin"

-- Guard: allows disabling from settings.lua
local settings_ok, settings = pcall(require, "core.settings")
if settings_ok and not settings:is_plugin_enabled("my-plugin") then return {} end

return {
    "author/my-plugin.nvim",

    -- Lazy loading (choose ONE trigger):
    event = "VeryLazy",              -- On first idle
    -- cmd = "MyPluginCommand",      -- On first command execution
    -- ft = { "lua", "python" },     -- On first filetype match
    -- keys = { "<leader>mp" },      -- On first keymap usage

    dependencies = {
        "nvim-lua/plenary.nvim",     -- If required
    },

    opts = {
        -- Configuration passed to setup()
        option1 = true,
        option2 = "value",
    },

    -- OR config = function() for more control:
    -- config = function(_, opts)
    --     require("my-plugin").setup(opts)
    --     -- Additional code here
    -- end,
}
```

## 4. Make it Togglable

In `lua/core/settings.lua`, add the default value:

```lua
plugins = {
    ["my-plugin"] = true,  -- enabled by default
},
```

## 5. Add Keymaps

```lua
return {
    "author/my-plugin.nvim",
    keys = {
        { "<leader>mp", "<cmd>MyPlugin<cr>", desc = "My Plugin" },
        { "<leader>mt", "<cmd>MyPluginToggle<cr>", desc = "Toggle My Plugin" },
    },
    -- ...
}
```

## 6. Testing

```bash
nvim
:Lazy                    # Verify the plugin is listed
:Lazy load my-plugin     # Force loading
:checkhealth my-plugin   # If the plugin has a healthcheck
```

## Design Patterns

### Pattern: pcall on external requires

```lua
config = function(_, opts)
    local ok, plugin = pcall(require, "my-plugin")
    if not ok then return end
    plugin.setup(opts)
end,
```

### Pattern: core.icons integration

```lua
local icons_ok, icons = pcall(require, "core.icons")
local icon = icons_ok and icons.ui.MyIcon or "fallback"
```

### Pattern: core.platform integration

```lua
local platform_ok, platform = pcall(require, "core.platform")
if platform_ok and platform.is_ssh then
    -- Reduce features over SSH
    opts.animations = false
end
```

## Checklist

```
□ File created in the correct category
□ Settings guard added
□ Appropriate lazy trigger (event/cmd/ft/keys)
□ Dependencies listed
□ Default added to core/settings.lua
□ Keymaps documented (desc =)
□ Tested: :Lazy, loading, functionality
□ stylua lua/ executed
```
