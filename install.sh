#!/usr/bin/env bash

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║ NvimEnterprise Installer — Professional Setup Script                     ║
# ╚══════════════════════════════════════════════════════════════════════════╝

set -e # Exit on error

# --- Colors & Icons ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
CHECK="✔"
INFO="ℹ"

echo -e "${BLUE}🚀 Starting NvimEnterprise Installation...${NC}\n"

# --- 1. Dependency Check ---
echo -e "${YELLOW}${INFO} Checking dependencies...${NC}"

check_dep() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}✘ Error: $1 is not installed.${NC}"
        exit 1
    else
        echo -e "${GREEN}${CHECK} $1 found.${NC}"
    fi
}

check_dep "nvim"
check_dep "git"
check_dep "rg" # ripgrep
check_dep "fd" # fd-find

# Check Neovim version (0.10+)
NVIM_VER=$(nvim --version | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
echo -e "${BLUE}${INFO} Neovim version $NVIM_VER detected.${NC}"

# --- 2. Backup Strategy ---
NVIM_CONFIG="$HOME/.config/nvim"
BACKUP_DIR="$HOME/.config/nvim.bak.$(date +%Y%m%d_%H%M%S)"

if [ -d "$NVIM_CONFIG" ]; then
    echo -e "${YELLOW}${INFO} Existing configuration found. Moving to $BACKUP_DIR...${NC}"
    mv "$NVIM_CONFIG" "$BACKUP_DIR"
    echo -e "${GREEN}${CHECK} Backup complete.${NC}"
fi

# --- 3. Deployment ---
echo -e "${YELLOW}${INFO} Cloning NvimEnterprise...${NC}"
git clone https://github.com/ca971/nvim-enterprise.git "$NVIM_CONFIG"

# --- 4. Finalizing ---
echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════╗"
echo -e "║        INSTALLATION SUCCESSFUL!                                ║"
echo -e "╚════════════════════════════════════════════════════════════════╝${NC}"
echo -e "\n${BLUE}Next steps:${NC}"
echo -e " 1. Open Neovim: ${YELLOW}nvim${NC}"
echo -e " 2. Wait for Lazy.nvim to install plugins."
echo -e " 3. Run ${YELLOW}:checkhealth nvimenterprise${NC} inside Neovim."
echo -e "\n${YELLOW}Note:${NC} Make sure you have a ${BLUE}Nerd Font${NC} installed in your terminal."
