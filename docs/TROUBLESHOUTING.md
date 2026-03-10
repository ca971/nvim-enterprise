# 🔧 Troubleshooting

## Common Issues and Solutions

### 1. `luac` error: attempt to assign to const variable

**Cause**: System `luac` is likely Lua 5.4, while Neovim uses LuaJIT (Lua 5.1). In Lua 5.4, `for` loop variables are `const`.

**Solution**:

```lua
-- ❌ Lua 5.4 forbids this
for line in data:gmatch("[^\n]+") do
    line = line:match("^%s*(.-)%s*$")
end

-- ✅ Compatible with both 5.1 AND 5.4
for raw_line in data:gmatch("[^\n]+") do
    local line = raw_line:match("^%s*(.-)%s*$")
end
```

**Prevention**: The pre-push hook prioritizes `luajit` for syntax checking.

### 2. `sed -i` fails on macOS

**Cause**: macOS (BSD) `sed` requires a backup extension argument: `sed -i ''`.

**Solution**:

```bash
# macOS
sed -i '' 's/old/new/' file

# Linux
sed -i 's/old/new/' file

# Cross-platform (inside a script)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed_i() { sed -i '' "$@"; }
else
    sed_i() { sed -i "$@"; }
fi
```

### 3. Lualine: broken separator between sections

**Cause**: An entirely empty section is removed by Lualine, which breaks the Powerline transition.

**Solution**: The last component of each section must **always be visible** and **without a custom separator**.

```lua
-- Section B: branch_or_cwd() always returns content
-- Section X: user_component always placed last
```

### 4. lua_ls warning: `doc-field-no-class`

**Cause**: `@field` is used without a preceding `@class` definition.

**Solution**:

```lua
-- ❌
---@type table<string, string>
---@field name string  ← warning

-- ✅
---@class MyType
---@field name string  ← OK
```

### 5. lua_ls warning: `undefined-field`

**Cause**: Accessing a field that wasn't declared on an inline type.

**Solution**: Declare a separate `@class`:

```lua
-- ❌
---@param opts? { color: table, sep: string }
-- opts.sep → undefined-field

-- ✅
---@class MyOpts
---@field color? table
---@field sep? string
---@param opts? MyOpts
```

### 6. CI: `luajit dofile()` fails

**Cause**: The Lua file uses the `vim.*` API, which does not exist in standalone LuaJIT (outside of Neovim).

**Solution**: Parse the file using `grep` in the CI pipeline:

```bash
MAJOR=$(grep -E '^\s+major\s*=' lua/core/version.lua | grep -oE '[0-9]+')
```

### 7. Release: tag pushed before CI fix

**Solution**:

```bash
git push origin --delete vX.Y.Z
git tag -d vX.Y.Z
# Fix CI issues, push to main
git tag -a vX.Y.Z -m "vX.Y.Z — description"
git push origin vX.Y.Z
```

### 8. Hook blocks a commit message

**Immediate workaround**:

```bash
git commit --no-verify -m "message"
```

**Permanent solution**: Check `.git/hooks/commit-msg` and verify the regex pattern for allowed types.

### 9. Plugin not loading

```vim
:Lazy                    " Is the plugin listed?
:Lazy load <plugin>      " Force manual load
:lua print(vim.inspect(require("lazy.core.config").plugins["<plugin>"]))
```

Check the guard inside the plugin file:

```lua
if settings_ok and not settings:is_plugin_enabled("name") then return {} end
```

### 10. LSP not attaching

```vim
:LspInfo                  " Active clients?
:LspLog                   " Any errors?
:Mason                    " Is the server installed?
:checkhealth lsp          " Diagnostics
```

---

## Committing and Merging

```bash
# Format
stylua lua/

# Commit
git add docs/
git commit -m "docs: add project documentation (release, versioning, architecture, guides)"

# Merge into main
git checkout main
git merge feat/docs

# Push
git push origin main
```

---

## Add to README

In the `Contributing` section of your `README.md`, add the following:

## 📚 Documentation

| Guide | Description |
| --- | --- |
| [Release Guide](https://www.google.com/search?q=docs/RELEASE_GUIDE.md) | Full release process |
| [Versioning](https://www.google.com/search?q=docs/VERSIONING.md) | SemVer strategy |
| [Architecture](https://www.google.com/search?q=docs/ARCHITECTURE.md) | Technical overview |
| [Adding a Language](https://www.google.com/search?q=docs/ADDING_LANGUAGE.md) | How to add a language |
| [Adding a Plugin](https://www.google.com/search?q=docs/ADDING_PLUGIN.md) | How to add a plugin |
| [Git Hooks](https://www.google.com/search?q=docs/HOOKS.md) | Hook documentation |
| [Troubleshooting](https://www.google.com/search?q=docs/TROUBLESHOOTING.md) | Common issues |

