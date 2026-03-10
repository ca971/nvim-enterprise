# 🌍 Adding a Language

## 1. Create the File

```bash
cp lua/langs/_template.lua lua/langs/elixir.lua
nvim lua/langs/elixir.lua
```

## 2. Minimal Structure

```lua
---@file lua/langs/elixir.lua
---@description Elixir language support
---@module "langs.elixir"

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok and not settings:is_language_enabled("elixir") then return {} end

return {
    -- Treesitter parser
    {
        "nvim-treesitter/nvim-treesitter",
        opts = function(_, opts)
            vim.list_extend(opts.ensure_installed, { "elixir", "heex", "eex" })
        end,
    },

    -- LSP
    {
        "neovim/nvim-lspconfig",
        opts = {
            servers = {
                elixirls = {},
            },
        },
    },

    -- Formatter
    {
        "stevearc/conform.nvim",
        opts = {
            formatters_by_ft = {
                elixir = { "mix" },
            },
        },
    },

    -- Linter (optional)
    {
        "mfussenegger/nvim-lint",
        opts = {
            linters_by_ft = {
                elixir = { "credo" },
            },
        },
    },
}
```

## 3. Enable in settings.lua

```lua
-- settings.lua or users/<name>/settings.lua
languages = {
    enabled = { "lua", "python", "elixir" },
},
```

## 4. Add the Runtime (if applicable)

In `lua/core/platform.lua` → `RUNTIME_EXECUTABLES`:

```lua
elixir = "elixir",
```

## 5. Add Version Detection in Lualine

In `lua/plugins/ui/lualine.lua`:
```lua
-- FT_TO_RUNTIME:
elixir = "elixir",

-- VERSION_ARGS:
elixir = { args = "--version", pattern = "Elixir%s+(%S+)" },
```

## 6. Mason — LSP/Formatter/Linter

Verify availability:

```vim
:Mason
```

Search for: `elixir-ls`, `credo`

## 7. Testing

```bash
nvim test.ex
:LspInfo          # LSP attached?
:TSInstall elixir # Parser installed?
:ConformInfo      # Formatter configured?
```

## Checklist

```
□ lua/langs/<lang>.lua created
□ Treesitter parser added
□ LSP server configured
□ Formatter configured
□ Linter configured (optional)
□ Runtime added to platform.lua (optional)
□ Version added to lualine.lua (optional)
□ Enabled in settings.lua
□ Tested with a real file
```
