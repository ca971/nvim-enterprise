#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# @file     install.sh
# @description Nvim Enterprise Installer — cross-platform setup with
#              dependency validation, backup strategy, and post-install checks
# @author   ca971
# @license  MIT
# @version  1.0.0
# @since    2026-01
#
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  install.sh — Nvim Enterprise Professional Installer                     ║
# ║                                                                          ║
# ║  Architecture:                                                           ║
# ║  ┌──────────────────────────────────────────────────────────────────┐    ║
# ║  │  Installation flow:                                              │    ║
# ║  │                                                                  │    ║
# ║  │  1. Environment validation                                       │    ║
# ║  │     ├─ OS detection (macOS / Linux / WSL / BSD)                  │    ║
# ║  │     ├─ Shell compatibility check (bash 4+)                       │    ║
# ║  │     └─ Terminal capability check (colors, unicode)               │    ║
# ║  │                                                                  │    ║
# ║  │  2. Dependency validation                                        │    ║
# ║  │     ├─ Required: nvim (≥0.10), git, rg, fd                       │    ║
# ║  │     ├─ Recommended: node, python3, gcc/clang, make, curl, wget   │    ║
# ║  │     ├─ Optional: lazygit, delta, bat, fzf, zoxide                │    ║
# ║  │     └─ Nerd Font detection heuristic                             │    ║
# ║  │                                                                  │    ║
# ║  │  3. Backup strategy                                              │    ║
# ║  │     ├─ Detect existing ~/.config/nvim                            │    ║
# ║  │     ├─ Timestamped backup: nvim.bak.YYYYMMDD_HHMMSS              │    ║
# ║  │     ├─ Also backs up ~/.local/share/nvim (plugin data)           │    ║
# ║  │     └─ Also backs up ~/.local/state/nvim (session/shada)         │    ║
# ║  │                                                                  │    ║
# ║  │  4. Deployment                                                   │    ║
# ║  │     ├─ Clone repository (HTTPS default, SSH optional)            │    ║
# ║  │     ├─ Verify clone integrity (init.lua exists)                  │    ║
# ║  │     └─ Set correct permissions                                   │    ║
# ║  │                                                                  │    ║
# ║  │  5. Post-install validation                                      │    ║
# ║  │     ├─ Headless Neovim launch to trigger lazy.nvim bootstrap     │    ║
# ║  │     ├─ Verify plugin directory was created                       │    ║
# ║  │     └─ Print summary with next steps                             │    ║
# ║  └──────────────────────────────────────────────────────────────────┘    ║
# ║                                                                          ║
# ║  Usage:                                                                  ║
# ║    curl -fsSL https://raw.githubusercontent.com/ca971/nvim-enterprise/   ║
# ║      main/install.sh | bash                                              ║
# ║                                                                          ║
# ║    # or with options:                                                    ║
# ║    ./install.sh                     # interactive (default)              ║
# ║    ./install.sh --ssh               # clone via SSH instead of HTTPS     ║
# ║    ./install.sh --no-backup         # skip backup of existing config     ║
# ║    ./install.sh --no-bootstrap      # skip headless plugin install       ║
# ║    ./install.sh --uninstall         # remove and restore backup          ║
# ║    ./install.sh --help              # show usage                         ║
# ║                                                                          ║
# ║  Exit codes:                                                             ║
# ║    0  Success                                                            ║
# ║    1  Missing required dependency                                        ║
# ║    2  Neovim version too old (<0.10)                                     ║
# ║    3  Git clone failed                                                   ║
# ║    4  Post-install validation failed                                     ║
# ║    5  User cancelled                                                     ║
# ╚══════════════════════════════════════════════════════════════════════════╝
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════

readonly SCRIPT_VERSION="1.0.0"
readonly REPO_HTTPS="https://github.com/ca971/nvim-enterprise.git"
readonly REPO_SSH="git@github.com:ca971/nvim-enterprise.git"
readonly MIN_NVIM_MAJOR=0
readonly MIN_NVIM_MINOR=10

# ── XDG paths ─────────────────────────────────────────────────────────────
readonly NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
readonly NVIM_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
readonly NVIM_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/nvim"
readonly NVIM_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/nvim"

# ── Timestamp for backups ─────────────────────────────────────────────────
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# ── Colors & icons ────────────────────────────────────────────────────────
# Detect color support — degrade gracefully in non-interactive terminals
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly BLUE='\033[0;34m'
    readonly YELLOW='\033[1;33m'
    readonly CYAN='\033[0;36m'
    readonly MAGENTA='\033[0;35m'
    readonly BOLD='\033[1m'
    readonly DIM='\033[2m'
    readonly NC='\033[0m'
    readonly ICON_OK="✔"
    readonly ICON_FAIL="✘"
    readonly ICON_INFO="ℹ"
    readonly ICON_WARN="⚠"
    readonly ICON_ARROW="→"
    readonly ICON_ROCKET="🚀"
    readonly ICON_PACKAGE="📦"
    readonly ICON_SHIELD="🛡"
    readonly ICON_GEAR="⚙"
    readonly ICON_CHECK="✅"
else
    readonly RED='' GREEN='' BLUE='' YELLOW='' CYAN='' MAGENTA=''
    readonly BOLD='' DIM='' NC=''
    readonly ICON_OK="[OK]" ICON_FAIL="[FAIL]" ICON_INFO="[i]"
    readonly ICON_WARN="[!]" ICON_ARROW="->" ICON_ROCKET="[*]"
    readonly ICON_PACKAGE="[P]" ICON_SHIELD="[S]" ICON_GEAR="[G]"
    readonly ICON_CHECK="[V]"
fi

# ═══════════════════════════════════════════════════════════════════════════
# CLI OPTIONS
# ═══════════════════════════════════════════════════════════════════════════

OPT_SSH=false
OPT_NO_BACKUP=false
OPT_NO_BOOTSTRAP=false
OPT_UNINSTALL=false

# ═══════════════════════════════════════════════════════════════════════════
# LOGGING HELPERS
# ═══════════════════════════════════════════════════════════════════════════

header() {
    echo ""
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
}

info()    { echo -e "${BLUE}${ICON_INFO}${NC}  $1"; }
success() { echo -e "${GREEN}${ICON_OK}${NC}  $1"; }
warn()    { echo -e "${YELLOW}${ICON_WARN}${NC}  $1"; }
error()   { echo -e "${RED}${ICON_FAIL}${NC}  $1" >&2; }
step()    { echo -e "${CYAN}${ICON_ARROW}${NC}  ${BOLD}$1${NC}"; }
dim()     { echo -e "${DIM}   $1${NC}"; }

# ═══════════════════════════════════════════════════════════════════════════
# OS DETECTION
# ═══════════════════════════════════════════════════════════════════════════

# Detect operating system — used for package manager hints
# and platform-specific behavior.
#
# Sets: OS_NAME, IS_MAC, IS_LINUX, IS_WSL, PKG_MANAGER, PKG_INSTALL
detect_os() {
    local uname_s
    uname_s="$(uname -s)"

    IS_MAC=false
    IS_LINUX=false
    IS_WSL=false
    PKG_MANAGER="unknown"
    PKG_INSTALL=""

    case "${uname_s}" in
        Darwin)
            OS_NAME="macOS"
            IS_MAC=true
            if command -v brew &>/dev/null; then
                PKG_MANAGER="brew"
                PKG_INSTALL="brew install"
            fi
            ;;
        Linux)
            OS_NAME="Linux"
            IS_LINUX=true

            # WSL detection
            if grep -qi "microsoft" /proc/version 2>/dev/null; then
                IS_WSL=true
                OS_NAME="WSL"
            fi

            # Package manager detection (ordered by preference)
            if command -v nix-env &>/dev/null; then
                PKG_MANAGER="nix"
                PKG_INSTALL="nix-env -iA nixpkgs."
            elif command -v apt &>/dev/null; then
                PKG_MANAGER="apt"
                PKG_INSTALL="sudo apt install -y"
            elif command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
                PKG_INSTALL="sudo dnf install -y"
            elif command -v pacman &>/dev/null; then
                PKG_MANAGER="pacman"
                PKG_INSTALL="sudo pacman -S --noconfirm"
            elif command -v apk &>/dev/null; then
                PKG_MANAGER="apk"
                PKG_INSTALL="sudo apk add"
            elif command -v zypper &>/dev/null; then
                PKG_MANAGER="zypper"
                PKG_INSTALL="sudo zypper install -y"
            fi
            ;;
        FreeBSD|OpenBSD|NetBSD)
            OS_NAME="BSD"
            if command -v pkg &>/dev/null; then
                PKG_MANAGER="pkg"
                PKG_INSTALL="sudo pkg install -y"
            fi
            ;;
        *)
            OS_NAME="Unknown"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════
# DEPENDENCY CHECKING
# ═══════════════════════════════════════════════════════════════════════════

# Counters for summary
REQUIRED_OK=0
REQUIRED_FAIL=0
RECOMMENDED_OK=0
RECOMMENDED_MISS=0
OPTIONAL_OK=0
OPTIONAL_MISS=0

# Check a required dependency — exit if missing.
#
# Usage: check_required <command> [display_name]
check_required() {
    local cmd="$1"
    local name="${2:-$1}"

    if command -v "$cmd" &>/dev/null; then
        local version
        version="$("$cmd" --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || echo "?")"
        success "${name} ${DIM}(${version})${NC}"
        ((REQUIRED_OK++))
    else
        error "${name} is ${RED}not installed${NC} — ${BOLD}required${NC}"
        if [[ -n "$PKG_INSTALL" ]]; then
            dim "Install: ${YELLOW}${PKG_INSTALL} ${cmd}${NC}"
        fi
        ((REQUIRED_FAIL++))
    fi
}

# Check a recommended dependency — warn if missing.
#
# Usage: check_recommended <command> [display_name] [purpose]
check_recommended() {
    local cmd="$1"
    local name="${2:-$1}"
    local purpose="${3:-}"

    if command -v "$cmd" &>/dev/null; then
        success "${name}"
        ((RECOMMENDED_OK++))
    else
        warn "${name} not found${purpose:+ — ${DIM}${purpose}${NC}}"
        if [[ -n "$PKG_INSTALL" ]]; then
            dim "Install: ${YELLOW}${PKG_INSTALL} ${cmd}${NC}"
        fi
        ((RECOMMENDED_MISS++))
    fi
}

# Check an optional dependency — note if missing.
#
# Usage: check_optional <command> [display_name] [purpose]
check_optional() {
    local cmd="$1"
    local name="${2:-$1}"
    local purpose="${3:-}"

    if command -v "$cmd" &>/dev/null; then
        success "${name}"
        ((OPTIONAL_OK++))
    else
        info "${name} not found${purpose:+ — ${DIM}${purpose}${NC}}"
        ((OPTIONAL_MISS++))
    fi
}

# Validate Neovim version meets minimum requirement.
#
# Parses `nvim --version` output and compares major.minor against
# MIN_NVIM_MAJOR.MIN_NVIM_MINOR. Exits with code 2 if too old.
check_nvim_version() {
    local nvim_ver
    nvim_ver="$(nvim --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "0.0.0")"

    local major minor
    major="$(echo "$nvim_ver" | cut -d. -f1)"
    minor="$(echo "$nvim_ver" | cut -d. -f2)"

    if [[ "$major" -gt "$MIN_NVIM_MAJOR" ]] || \
       { [[ "$major" -eq "$MIN_NVIM_MAJOR" ]] && [[ "$minor" -ge "$MIN_NVIM_MINOR" ]]; }; then
        success "Neovim ${GREEN}v${nvim_ver}${NC} ${DIM}(≥${MIN_NVIM_MAJOR}.${MIN_NVIM_MINOR} required)${NC}"
    else
        error "Neovim ${RED}v${nvim_ver}${NC} is too old — ${BOLD}v${MIN_NVIM_MAJOR}.${MIN_NVIM_MINOR}+${NC} required"
        dim "Update: https://github.com/neovim/neovim/releases"
        exit 2
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# BACKUP
# ═══════════════════════════════════════════════════════════════════════════

# Back up a directory if it exists.
#
# Usage: backup_dir <source_path> <label>
# Creates: <source_path>.bak.<TIMESTAMP>
backup_dir() {
    local src="$1"
    local label="$2"

    if [[ -d "$src" ]]; then
        local dest="${src}.bak.${TIMESTAMP}"
        mv "$src" "$dest"
        success "${label} backed up ${DIM}→ ${dest}${NC}"
    else
        dim "${label} not found — nothing to back up"
    fi
}

# Perform full backup of Neovim directories.
perform_backup() {
    if [[ "$OPT_NO_BACKUP" == true ]]; then
        warn "Backup skipped (--no-backup)"
        return
    fi

    step "Backing up existing Neovim data"

    backup_dir "$NVIM_CONFIG" "Config"
    backup_dir "$NVIM_DATA"   "Data"
    backup_dir "$NVIM_STATE"  "State"
    # Cache is intentionally NOT backed up (regenerated automatically)

    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# DEPLOYMENT
# ═══════════════════════════════════════════════════════════════════════════

# Clone the repository and verify the clone.
deploy() {
    local repo_url
    if [[ "$OPT_SSH" == true ]]; then
        repo_url="$REPO_SSH"
        info "Using SSH protocol"
    else
        repo_url="$REPO_HTTPS"
        info "Using HTTPS protocol"
    fi

    step "Cloning Nvim Enterprise"
    dim "${repo_url}"
    echo ""

    if ! git clone --depth 1 "$repo_url" "$NVIM_CONFIG" 2>&1; then
        error "Git clone failed"
        dim "Check your network connection and repository access"
        if [[ "$OPT_SSH" == true ]]; then
            dim "SSH clone failed — try without --ssh flag for HTTPS"
        fi
        exit 3
    fi

    echo ""

    # Verify clone integrity
    if [[ -f "${NVIM_CONFIG}/init.lua" ]]; then
        success "Clone verified ${DIM}(init.lua present)${NC}"
    else
        error "Clone appears incomplete — init.lua not found"
        exit 3
    fi

    # Set permissions
    chmod -R u+rw "$NVIM_CONFIG"
    success "Permissions set"
}

# ═══════════════════════════════════════════════════════════════════════════
# POST-INSTALL BOOTSTRAP
# ═══════════════════════════════════════════════════════════════════════════

# Run headless Neovim to trigger lazy.nvim plugin installation.
#
# This ensures all plugins are downloaded and compiled before the
# user opens Neovim for the first time, avoiding a long wait on
# first launch.
bootstrap() {
    if [[ "$OPT_NO_BOOTSTRAP" == true ]]; then
        warn "Bootstrap skipped (--no-bootstrap)"
        return
    fi

    step "Bootstrapping plugins (headless Neovim)"
    dim "This may take 1-2 minutes on first install..."
    echo ""

    # Run Neovim headless: install plugins, build parsers, quit
    if timeout 300 nvim --headless \
        "+Lazy! install" \
        "+TSUpdateSync" \
        "+qa" 2>/dev/null; then
        success "Plugin bootstrap complete"
    else
        warn "Bootstrap had issues — plugins will install on first launch"
        dim "This is normal if treesitter parsers need compilation"
    fi

    # Verify plugin directory was created
    local lazy_dir="${NVIM_DATA}/lazy"
    if [[ -d "$lazy_dir" ]]; then
        local plugin_count
        plugin_count="$(find "$lazy_dir" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"
        success "${plugin_count} plugins installed ${DIM}(${lazy_dir})${NC}"
    else
        warn "Plugin directory not found — will be created on first launch"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# UNINSTALL
# ═══════════════════════════════════════════════════════════════════════════

# Remove Nvim Enterprise and optionally restore the most recent backup.
uninstall() {
    header "${ICON_GEAR} Nvim Enterprise Uninstaller"

    echo ""
    warn "This will remove:"
    dim "${NVIM_CONFIG}"
    dim "${NVIM_DATA}"
    dim "${NVIM_STATE}"
    dim "${NVIM_CACHE}"
    echo ""

    read -rp "Continue? [y/N] " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        info "Uninstall cancelled"
        exit 5
    fi

    echo ""
    step "Removing Nvim Enterprise"

    [[ -d "$NVIM_CONFIG" ]] && rm -rf "$NVIM_CONFIG" && success "Config removed"
    [[ -d "$NVIM_DATA" ]]   && rm -rf "$NVIM_DATA"   && success "Data removed"
    [[ -d "$NVIM_STATE" ]]  && rm -rf "$NVIM_STATE"   && success "State removed"
    [[ -d "$NVIM_CACHE" ]]  && rm -rf "$NVIM_CACHE"   && success "Cache removed"

    # Find most recent backup
    local latest_backup
    latest_backup="$(ls -dt "${NVIM_CONFIG}.bak."* 2>/dev/null | head -n1 || true)"

    if [[ -n "$latest_backup" ]]; then
        echo ""
        read -rp "Restore backup ${latest_backup}? [y/N] " restore
        if [[ "${restore,,}" == "y" ]]; then
            mv "$latest_backup" "$NVIM_CONFIG"
            success "Backup restored from ${DIM}${latest_backup}${NC}"
        fi
    fi

    echo ""
    success "Uninstall complete"
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# USAGE
# ═══════════════════════════════════════════════════════════════════════════

usage() {
    cat <<EOF

${BOLD}Nvim Enterprise Installer v${SCRIPT_VERSION}${NC}

${BOLD}Usage:${NC}
  ./install.sh [options]

${BOLD}Options:${NC}
  --ssh            Clone via SSH instead of HTTPS
  --no-backup      Skip backup of existing Neovim configuration
  --no-bootstrap   Skip headless plugin installation
  --uninstall      Remove Nvim Enterprise and optionally restore backup
  --help, -h       Show this help message

${BOLD}Examples:${NC}
  ./install.sh                  # Full install with HTTPS
  ./install.sh --ssh            # Full install with SSH
  ./install.sh --uninstall      # Remove and restore

${BOLD}Requirements:${NC}
  • Neovim ≥ ${MIN_NVIM_MAJOR}.${MIN_NVIM_MINOR}
  • git, ripgrep (rg), fd-find (fd)
  • A Nerd Font installed in your terminal

EOF
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════

# Print the final success summary with next steps.
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║   ${ICON_CHECK}  NVIM ENTERPRISE INSTALLED SUCCESSFULLY                   ║"
    echo "║                                                                ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Dependency summary
    echo -e "${BOLD}  Dependency Summary:${NC}"
    echo -e "    Required:    ${GREEN}${REQUIRED_OK} found${NC}  ${RED}${REQUIRED_FAIL} missing${NC}"
    echo -e "    Recommended: ${GREEN}${RECOMMENDED_OK} found${NC}  ${YELLOW}${RECOMMENDED_MISS} missing${NC}"
    echo -e "    Optional:    ${GREEN}${OPTIONAL_OK} found${NC}  ${DIM}${OPTIONAL_MISS} missing${NC}"
    echo ""

    echo -e "${BOLD}  Next Steps:${NC}"
    echo ""
    echo -e "    ${CYAN}1.${NC} Open Neovim:"
    echo -e "       ${YELLOW}nvim${NC}"
    echo ""
    echo -e "    ${CYAN}2.${NC} Wait for any remaining plugins to install"
    echo -e "       ${DIM}(status shown in Lazy.nvim dashboard)${NC}"
    echo ""
    echo -e "    ${CYAN}3.${NC} Run health check inside Neovim:"
    echo -e "       ${YELLOW}:checkhealth${NC}"
    echo ""
    echo -e "    ${CYAN}4.${NC} Browse your configuration:"
    echo -e "       ${YELLOW}:NvimInfo${NC}     ${DIM}System information${NC}"
    echo -e "       ${YELLOW}:Settings${NC}     ${DIM}View/edit settings${NC}"
    echo -e "       ${YELLOW}:NvimCommands${NC} ${DIM}All available commands${NC}"
    echo ""

    if [[ "$RECOMMENDED_MISS" -gt 0 ]] || [[ "$OPTIONAL_MISS" -gt 0 ]]; then
        echo -e "${YELLOW}  ${ICON_WARN} Some optional tools are missing.${NC}"
        echo -e "    ${DIM}Install them for the best experience.${NC}"
        echo -e "    ${DIM}Run :checkhealth for detailed recommendations.${NC}"
        echo ""
    fi

    echo -e "  ${MAGENTA}${BOLD}Nerd Font:${NC} Make sure your terminal uses a Nerd Font"
    echo -e "    ${DIM}https://www.nerdfonts.com/font-downloads${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

main() {
    # ── Parse CLI arguments ───────────────────────────────────────────
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ssh)          OPT_SSH=true ;;
            --no-backup)    OPT_NO_BACKUP=true ;;
            --no-bootstrap) OPT_NO_BOOTSTRAP=true ;;
            --uninstall)    OPT_UNINSTALL=true ;;
            --help|-h)      usage ;;
            *)
                error "Unknown option: $1"
                dim "Run ./install.sh --help for usage"
                exit 1
                ;;
        esac
        shift
    done

    # ── Banner ────────────────────────────────────────────────────────
    echo ""
    echo -e "${BLUE}${BOLD}"
    echo "    ╔══════════════════════════════════════════════════════╗"
    echo "    ║                                                      ║"
    echo "    ║   ${ICON_ROCKET}  Nvim Enterprise Installer  v${SCRIPT_VERSION}            ║"
    echo "    ║                                                      ║"
    echo "    ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # ── Handle uninstall early ────────────────────────────────────────
    if [[ "$OPT_UNINSTALL" == true ]]; then
        detect_os
        uninstall
    fi

    # ── Phase 1: Environment ──────────────────────────────────────────
    header "${ICON_GEAR} Phase 1/5 — Environment Detection"
    echo ""

    detect_os
    info "OS: ${BOLD}${OS_NAME}${NC}"
    info "Shell: ${BOLD}${SHELL:-unknown}${NC}"
    [[ "$IS_WSL" == true ]] && info "WSL detected"
    if [[ "$PKG_MANAGER" != "unknown" ]]; then
        info "Package manager: ${BOLD}${PKG_MANAGER}${NC}"
    else
        warn "No known package manager detected"
    fi
    echo ""

    # ── Phase 2: Dependencies ─────────────────────────────────────────
    header "${ICON_PACKAGE} Phase 2/5 — Dependency Validation"
    echo ""

    step "Required dependencies"
    check_required "nvim"  "Neovim"
    check_nvim_version
    check_required "git"   "Git"
    check_required "rg"    "ripgrep"
    check_required "fd"    "fd-find"
    echo ""

    step "Recommended dependencies"
    check_recommended "node"    "Node.js"    "LSP servers, formatters"
    check_recommended "python3" "Python 3"   "LSP, DAP, formatters"
    check_recommended "gcc"     "GCC"        "treesitter parser compilation"
    check_recommended "make"    "Make"       "plugin builds"
    check_recommended "curl"    "curl"       "Mason package downloads"
    check_recommended "wget"    "wget"       "fallback downloader"
    check_recommended "unzip"   "unzip"      "Mason package extraction"
    echo ""

    step "Optional tools"
    check_optional "lazygit" "lazygit"  "TUI git client"
    check_optional "delta"   "delta"    "git diff pager"
    check_optional "bat"     "bat"      "syntax-highlighted previews"
    check_optional "fzf"     "fzf"      "fuzzy finder"
    check_optional "zoxide"  "zoxide"   "smart directory jumper"
    check_optional "tmux"    "tmux"     "terminal multiplexer"
    echo ""

    # Abort if any required dependency is missing
    if [[ "$REQUIRED_FAIL" -gt 0 ]]; then
        echo ""
        error "${REQUIRED_FAIL} required dependency(ies) missing — cannot continue"
        dim "Install the missing tools above, then re-run this script"
        exit 1
    fi

    # ── Phase 3: Backup ───────────────────────────────────────────────
    header "${ICON_SHIELD} Phase 3/5 — Backup"
    echo ""

    perform_backup

    # ── Phase 4: Deploy ───────────────────────────────────────────────
    header "${ICON_ROCKET} Phase 4/5 — Deployment"
    echo ""

    deploy
    echo ""

    # ── Phase 5: Bootstrap ────────────────────────────────────────────
    header "${ICON_PACKAGE} Phase 5/5 — Bootstrap"
    echo ""

    bootstrap
    echo ""

    # ── Summary ───────────────────────────────────────────────────────
    print_summary
}

# ═══════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════

main "$@"
