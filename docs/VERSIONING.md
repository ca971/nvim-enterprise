# 📋 Versioning Strategy

## Semantic Versioning (SemVer)

NvimEnterprise suit [SemVer 2.0.0](https://semver.org/) avec deux niveaux de version.

```
MAJOR.MINOR.PATCH[-pre]
  │     │     │     └─ Pre-release : alpha, beta, rc.1
  │     │     └─────── Patch : fix, refactor, docs, style
  │     └───────────── Minor : nouvelle feature, module, commande
  └─────────────────── Major : breaking change, refonte architecture
```

## Deux niveaux de version

| Niveau | Scope | Localisation | Exemple |
|---|---|---|---|
| **Projet** | Tout le dépôt | `lua/core/version.lua` + tag Git | `v1.1.0` |
| **Module** | Fichier individuel | `---@version` dans le header | `@version 2.2.0` |

### Source unique : `lua/core/version.lua`

```lua
local M = {
    major = 1,
    minor = 1,
    patch = 0,
    pre = nil,
}
```

Tous les autres fichiers **lisent** depuis cette source :
- `init.lua` → `dofile("lua/core/version.lua")`
- `:Version` → `require("core.version").show()`
- `release.sh` → met à jour via `sed`
- CI → parse via `grep`

### Version par module (indépendante)

```lua
-- lua/plugins/ui/lualine.lua
---@version 2.2.0  ← version du MODULE, pas du projet
```

Un module peut être en `v3.0.0` alors que le projet est en `v1.2.0`.

## Fichiers impliqués

| Fichier | Rôle |
|---|---|
| `lua/core/version.lua` | Source unique (major, minor, patch) |
| `init.lua` | `@version` dans le header LuaDoc |
| `CHANGELOG.md` | Historique humain |
| `scripts/release.sh` | Met à jour version.lua + init.lua |
| `.github/workflows/ci.yml` | Vérifie tag = version.lua |

## Diagramme

```
lua/core/version.lua  (source unique)
        │
        ├──→ init.lua           dofile() → _G.NvimConfig.version
        ├──→ :Version           commande utilisateur
        ├──→ :NvimVersion       alias
        ├──→ release.sh         mise à jour via sed
        ├──→ CI                 parse via grep
        └──→ CHANGELOG.md       référence humaine
```
