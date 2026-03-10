# 🚀 Release Guide

## Daily Workflow

```bash
# Edit → Format → Commit → Push
nvim lua/plugins/ui/lualine.lua
stylua lua/
git add -A
git commit -m "fix(lualine): resolve separator glitch"
git push origin main
```

## Commit Convention

```
<type>(<scope>): <subject>
```

| Type | SemVer | Usage |
| --- | --- | --- |
| `feat` | MINOR | New feature |
| `fix` | PATCH | Bug fix |
| `docs` | PATCH | Documentation |
| `style` | PATCH | Formatting (stylua) |
| `refactor` | PATCH | Restructuring without behavior change |
| `perf` | PATCH | Optimization |
| `test` | PATCH | Tests |
| `build` | PATCH | Build / dependencies |
| `ci` | PATCH | CI/CD |
| `chore` | PATCH | Maintenance |
| `revert` | PATCH | Revert |
| `release` | TAG | Version release |
| `feat!` | MAJOR | Breaking change |

## Release Process

### 1. Determine Version Number

```
PATCH (x.x.+1) → fix, refactor, docs, style
MINOR (x.+1.0) → feat (new feature, module, command)
MAJOR (+1.0.0) → feat! or BREAKING CHANGE
```

### 2. Update CHANGELOG.md

```bash
nvim CHANGELOG.md
```

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- **module**: description

### Changed
- **module**: description

### Fixed
- **module**: description
```

### 3. Commit the CHANGELOG

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): add vX.Y.Z entry"
```

### 4. Run the Script

```bash
./scripts/release.sh X.Y.Z "Short description"
```

The script automatically performs the following:

1. Verifies a clean working tree
2. Updates `lua/core/version.lua`
3. Updates `init.lua` `@version`
4. Verifies CHANGELOG.md
5. Runs stylua + luajit checks
6. Creates an annotated commit + tag
7. Pushes main + tag (with confirmation)

### 5. Verify CI

```bash
gh run watch
gh release view vX.Y.Z --web
```

## Troubleshooting & Emergency Commands

```bash
# Delete a tag
git tag -d vX.Y.Z
git push origin --delete vX.Y.Z

# Delete a release
gh release delete vX.Y.Z --yes

# Bypass hooks (Emergency only)
git commit --no-verify -m "hotfix: urgent"
git push --no-verify

# View current version
grep -E '^\s+(major|minor|patch)' lua/core/version.lua
```

## Checklist

```
□ Commits pushed to main
□ Main CI is green
□ CHANGELOG.md updated and committed
□ Clean working tree
□ ./scripts/release.sh X.Y.Z "description"
□ Tag CI is green
□ Release visible on GitHub

