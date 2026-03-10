#!/bin/bash
# ╔══════════════════════════════════════════════════════════╗
# ║  scripts/release.sh — Semi-automated SemVer release      ║
# ║  Usage: ./scripts/release.sh 1.0.1 "Short description"   ║
# ╚══════════════════════════════════════════════════════════╝

set -euo pipefail

VERSION="${1:?Usage: release.sh VERSION \"message\"}"
MESSAGE="${2:-Release v$VERSION}"
TAG="v$VERSION"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  NvimEnterprise Release — ${TAG}          ${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"

# ── Guards ─────────────────────────────────────────────────
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${RED}✗ Uncommitted changes — commit or stash first${NC}"
    exit 1
fi

if git tag | grep -q "^${TAG}$"; then
    echo -e "${RED}✗ Tag ${TAG} already exists${NC}"
    exit 1
fi

if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$'; then
    echo -e "${RED}✗ Invalid semver: ${VERSION}${NC}"
    exit 1
fi

# ── Parse version components ───────────────────────────────
IFS='.' read -r MAJOR MINOR PATCH <<< "${VERSION%%-*}"
PRE=""
if [[ "$VERSION" == *-* ]]; then
    PRE="${VERSION#*-}"
fi

# ── Update lua/core/version.lua ────────────────────────────
VERSION_FILE="lua/core/version.lua"
if [ -f "$VERSION_FILE" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        SED_INPLACE=(sed -i '')
    else
        SED_INPLACE=(sed -i)
    fi

    "${SED_INPLACE[@]}" "s/major = [0-9]*/major = $MAJOR/" "$VERSION_FILE"
    "${SED_INPLACE[@]}" "s/minor = [0-9]*/minor = $MINOR/" "$VERSION_FILE"
    "${SED_INPLACE[@]}" "s/patch = [0-9]*/patch = $PATCH/" "$VERSION_FILE"

    if [ -n "$PRE" ]; then
        sed -i.bak "s/pre.*=.*/pre   = \"$PRE\",/" "$VERSION_FILE"
    else
        sed -i.bak "s/pre.*=.*/pre   = nil,/" "$VERSION_FILE"
    fi
    rm -f "${VERSION_FILE}.bak"
    echo -e "${GREEN}✓ Updated ${VERSION_FILE} → ${VERSION}${NC}"
else
    echo -e "${YELLOW}⚠ ${VERSION_FILE} not found — skipping${NC}"
fi

# ── Verify CHANGELOG.md ───────────────────────────────────
CHANGELOG="CHANGELOG.md"
if [ -f "$CHANGELOG" ]; then
    if grep -q "\[${VERSION}\]" "$CHANGELOG"; then
        echo -e "${GREEN}✓ CHANGELOG.md contains [${VERSION}]${NC}"
    else
        echo -e "${YELLOW}⚠ CHANGELOG.md missing [${VERSION}] entry${NC}"
        echo -e "${YELLOW}  Edit CHANGELOG.md before continuing${NC}"
        read -p "  Open in \$EDITOR? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ${EDITOR:-nvim} "$CHANGELOG"
        fi
    fi
fi

# ── Run pre-release checks ────────────────────────────────
echo -e "\n${CYAN}Running pre-release checks...${NC}"

if command -v stylua &>/dev/null; then
    if stylua --check lua/ 2>/dev/null; then
        echo -e "${GREEN}✓ StyLua formatting OK${NC}"
    else
        echo -e "${RED}✗ StyLua check failed — run: stylua lua/${NC}"
        exit 1
    fi
fi

LUA_CHECK=""
if command -v luajit &>/dev/null; then
    LUA_CHECK="luajit -bl"
elif command -v luac &>/dev/null; then
    LUA_CHECK="luac -p"
fi

if [ -n "$LUA_CHECK" ]; then
    errors=0
    while IFS= read -r -d '' f; do
        if ! $LUA_CHECK "$f" &>/dev/null; then
            echo -e "${RED}  ✗ $f${NC}"
            errors=$((errors + 1))
        fi
    done < <(find lua -name '*.lua' -print0 2>/dev/null)

    if [ $errors -gt 0 ]; then
        echo -e "${RED}✗ $errors Lua syntax error(s)${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Lua syntax OK${NC}"
fi

# ── Summary ────────────────────────────────────────────────
echo -e "\n${CYAN}Release summary:${NC}"
echo -e "  Version:  ${GREEN}${VERSION}${NC}"
echo -e "  Tag:      ${GREEN}${TAG}${NC}"
echo -e "  Message:  ${MESSAGE}"
echo -e "  Branch:   $(git branch --show-current)"
echo ""

# ── Commit + Tag ───────────────────────────────────────────
git add -A
git commit -m "release: ${TAG} — ${MESSAGE}"
git tag -a "$TAG" -m "${TAG} — ${MESSAGE}"

echo -e "${GREEN}✓ Committed and tagged${NC}"

# ── Push ───────────────────────────────────────────────────
echo ""
read -p "Push to origin? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git push origin "$(git branch --show-current)"
    git push origin "$TAG"
    echo -e "\n${GREEN}✅ ${TAG} released successfully!${NC}"
    echo -e "${CYAN}   → https://github.com/ca971/nvim-enterprise/releases/tag/${TAG}${NC}"
else
    echo -e "${YELLOW}⚠ Not pushed — run manually:${NC}"
    echo "  git push origin $(git branch --show-current)"
    echo "  git push origin ${TAG}"
fi
