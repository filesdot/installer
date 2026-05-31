#!/usr/bin/env bash
#
# dotfiles-lib installer
# Modular & Aesthetic Linux Dotfiles Collection
# https://gitlab.com/filesdot/library
#
# Usage:
#   ./install.sh --all                    # Install everything
#   ./install.sh --interactive            # Guided selection
#   ./install.sh hyprland nvim alacritty  # Install specific modules
#   ./install.sh --help                   # Show this help
#

set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DOTFILES_DIR="${DOTFILES_DIR:-$SCRIPT_DIR}"
readonly BACKUP_DIR="${HOME}/.dotfiles/backup/$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="${HOME}/.dotfiles/install.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Available modules and their config paths (relative to DOTFILES_DIR)
declare -A MODULES=(
    [hyprland]="hyprland"
    [nvim]="nvim"
    [alacritty]="alacritty"
    [waybar]="waybar"
    [rofi]="rofi"
    [zsh]="zsh"
    [bspwm]="bspwm"
    [polybar]="polybar"
    [dunst]="dunst"
    [picom]="picom"
    [tmux]="tmux"
    [kitty]="kitty"
)

# Package managers by distro
declare -A PKG_MANAGERS=(
    [arch]="pacman"
    [manjaro]="pacman"
    [fedora]="dnf"
    [ubuntu]="apt"
    [debian]="apt"
    [opensuse]="zypper"
    [nixos]="nix-env"
)

# ════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

log() {
    local level="$1"; shift
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    
    case "$level" in
        INFO)  echo -e "${BLUE}[INFO]${NC} $msg" ;;
        SUCCESS) echo -e "${GREEN}[✓]${NC} $msg" ;;
        WARN)  echo -e "${YELLOW}[!]${NC} $msg" ;;
        ERROR) echo -e "${RED}[✗]${NC} $msg" >&2 ;;
        STEP)  echo -e "${CYAN}⟡${NC} $msg" ;;
        *)     echo "$msg" ;;
    esac
}

die() {
    log ERROR "$*"
    exit 1
}

# Detect Linux distribution
detect_distro() {
    if [[ -f /etc/arch-release ]]; then
        echo "arch"
    elif [[ -f /etc/manjaro-release ]]; then
        echo "manjaro"
    elif [[ -f /etc/fedora-release ]]; then
        echo "fedora"
    elif [[ -f /etc/ubuntu-release ]] || grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        echo "ubuntu"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/opensuse-release ]] || grep -q "openSUSE" /etc/os-release 2>/dev/null; then
        echo "opensuse"
    elif [[ -f /etc/NIXOS ]]; then
        echo "nixos"
    else
        die "Unsupported distribution. Please open an issue on GitLab."
    fi
}

# Check if command exists
cmd_exists() { command -v "$1" &>/dev/null; }

# Create backup of existing config
backup_config() {
    local config_name="$1"
    local config_path="$2"
    
    if [[ -e "$config_path" ]]; then
        local backup_path="${BACKUP_DIR}/${config_name}"
        mkdir -p "$(dirname "$backup_path")"
        if [[ -d "$config_path" ]]; then
            cp -r "$config_path" "$backup_path"
        else
            cp "$config_path" "$backup_path"
        fi
        log SUCCESS "Backed up ${config_name} to ${backup_path}"
    fi
}

# Symlink config file/directory
install_config() {
    local module="$1"
    local src="${DOTFILES_DIR}/${MODULES[$module]}"
    local target="${HOME}/.config/${module}"
    
    # Handle special cases
    case "$module" in
        zsh)
            target="${HOME}/.zshrc"
            src="${DOTFILES_DIR}/${MODULES[$module]}/.zshrc"
            ;;
        nvim)
            target="${HOME}/.config/nvim"
            src="${DOTFILES_DIR}/${MODULES[$module]}"
            ;;
        hyprland)
            target="${HOME}/.config/hypr"
            src="${DOTFILES_DIR}/${MODULES[$module]}"
            ;;
    esac
    
    if [[ ! -e "$src" ]]; then
        log WARN "Source not found: $src (skipping $module)"
        return 1
    fi
    
    backup_config "$module" "$target"
    
    # Remove existing and create symlink
    rm -rf "$target"
    mkdir -p "$(dirname "$target")"
    ln -sf "$src" "$target"
    
    log SUCCESS "Installed ${module} → ${target}"
}

# Install system dependencies for a module
install_deps() {
    local module="$1"
    local distro
    distro="$(detect_distro)"
    local pkg_mgr="${PKG_MANAGERS[$distro]}"
    
    declare -A DEPS=(
        [hyprland]="hyprland waybar rofi dunst picom grim slurp swappy wtype"
        [nvim]="neovim ripgrep fd-find fzf nodejs npm"
        [alacritty]="alacritty"
        [waybar]="waybar"
        [rofi]="rofi"
        [zsh]="zsh"
        [bspwm]="bspwm sxhkd polybar picom"
        [polybar]="polybar"
        [dunst]="dunst"
        [picom]="picom"
        [tmux]="tmux"
        [kitty]="kitty"
    )
    
    local deps="${DEPS[$module]:-}"
    [[ -z "$deps" ]] && return 0
    
    log STEP "Installing dependencies for ${module}..."
    
    case "$pkg_mgr" in
        pacman)
            sudo pacman -S --needed --noconfirm $deps 2>>"$LOG_FILE" || log WARN "Some packages may have failed to install"
            ;;
        dnf)
            sudo dnf install -y $deps 2>>"$LOG_FILE" || log WARN "Some packages may have failed to install"
            ;;
        apt)
            sudo apt update -qq 2>>"$LOG_FILE"
            sudo apt install -y $deps 2>>"$LOG_FILE" || log WARN "Some packages may have failed to install"
            ;;
        zypper)
            sudo zypper install -y $deps 2>>"$LOG_FILE" || log WARN "Some packages may have failed to install"
            ;;
        nix-env)
            nix-env -iA nixos.$deps 2>>"$LOG_FILE" || log WARN "Some packages may have failed to install"
            ;;
        *)
            log WARN "Unknown package manager: $pkg_mgr"
            ;;
    esac
}

# ════════════════════════════════════════════════════════════════════════════
# INSTALLATION LOGIC
# ════════════════════════════════════════════════════════════════════════════

install_module() {
    local module="$1"
    
    if [[ ! -v MODULES[$module] ]]; then
        log WARN "Unknown module: $module"
        return 1
    fi
    
    log STEP "Installing module: ${BOLD}${module}${NC}"
    
    # Install system dependencies first
    install_deps "$module"
    
    # Install config files
    install_config "$module"
    
    echo ""
}

install_all() {
    log INFO "Starting full installation of all modules..."
    echo ""
    
    for module in "${!MODULES[@]}"; do
        install_module "$module"
    done
    
    echo ""
    log SUCCESS "All modules installed successfully!"
}

interactive_install() {
    log INFO "Starting interactive installation..."
    echo ""
    echo -e "${BOLD}Available modules:${NC}"
    
    local selected=()
    local i=1
    declare -A module_list
    
    # Display modules with numbers
    for module in "${!MODULES[@]}"; do
        echo -e "  ${CYAN}$i)${NC} ${module}"
        module_list[$i]="$module"
        ((i++))
    done
    echo ""
    echo -e "Enter module numbers separated by spaces, or '${GREEN}all${NC}' for everything:"
    read -r -p "> " input
    
    if [[ "$input" == "all" ]]; then
        install_all
        return
    fi
    
    # Parse selection
    for num in $input; do
        if [[ -v module_list[$num] ]]; then
            selected+=("${module_list[$num]}")
        else
            log WARN "Invalid selection: $num"
        fi
    done
    
    if [[ ${#selected[@]} -eq 0 ]]; then
        log WARN "No valid modules selected. Exiting."
        return 1
    fi
    
    echo ""
    log INFO "Selected modules: ${selected[*]}"
    echo ""
    
    for module in "${selected[@]}"; do
        install_module "$module"
    done
    
    echo ""
    log SUCCESS "Installation complete!"
}

show_help() {
    cat << EOF
${BOLD}dotfiles-lib installer${NC}
Modular & Aesthetic Linux Dotfiles Collection

${BOLD}USAGE:${NC}
  ./install.sh [OPTIONS] [MODULES...]

${BOLD}OPTIONS:${NC}
  --all           Install all available modules
  --interactive   Guided module selection
  --help, -h      Show this help message
  --backup-only   Create backups without installing
  --dry-run       Show what would be installed

${BOLD}MODULES:${NC}
EOF
    
    for module in "${!MODULES[@]}"; do
        printf "  %-12s %s\n" "$module" "${MODULES[$module]}"
    done
    
    cat << EOF

${BOLD}EXAMPLES:${NC}
  ./install.sh --all
  ./install.sh hyprland nvim alacritty
  ./install.sh --interactive

${BOLD}ENVIRONMENT VARIABLES:${NC}
  DOTFILES_DIR    Override dotfiles directory (default: script location)
  BACKUP_DIR      Override backup location (default: ~/.dotfiles/backup/)

${BOLD}SUPPORT:${NC}
  GitLab: https://gitlab.com/flessan/dotfiles-lib
  License: MIT

EOF
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ════════════════════════════════════════════════════════════════════════════

main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log INFO "dotfiles-lib installer started"
    log INFO "Distribution: $(detect_distro)"
    log INFO "Dotfiles dir: $DOTFILES_DIR"
    
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --all)
            mkdir -p "$BACKUP_DIR"
            install_all
            ;;
        --interactive)
            mkdir -p "$BACKUP_DIR"
            interactive_install
            ;;
        --backup-only)
            log INFO "Creating backups only (no installation)..."
            mkdir -p "$BACKUP_DIR"
            for module in "${!MODULES[@]}"; do
                local target="${HOME}/.config/${module}"
                [[ -e "$target" ]] && backup_config "$module" "$target"
            done
            log SUCCESS "Backups saved to: $BACKUP_DIR"
            ;;
        --dry-run)
            log INFO "Dry run - no changes will be made"
            echo ""
            echo "Modules that would be installed:"
            if [[ $# -gt 1 ]]; then
                shift
                for module in "$@"; do
                    [[ -v MODULES[$module] ]] && echo "  • $module"
                done
            else
                for module in "${!MODULES[@]}"; do
                    echo "  • $module"
                done
            fi
            ;;
        *)
            # Treat arguments as module names
            mkdir -p "$BACKUP_DIR"
            for module in "$@"; do
                install_module "$module"
            done
            log SUCCESS "Installation complete!"
            ;;
    esac
    
    # Post-install message
    echo ""
    echo -e "${BOLD}${GREEN}✓ Setup complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "  • Restart your terminal or run: source ~/.zshrc"
    echo "  • For Hyprland: logout and select Hyprland session"
    echo "  • For Neovim: run 'nvim' and wait for plugins to install"
    echo ""
    echo "Restore previous configs anytime with:"
    echo "  dotlib restore --last"
    echo ""
    echo "Backups saved to: ${BACKUP_DIR}"
    echo ""
    
    log INFO "Installation finished successfully"
}

# Run main function with all arguments
main "$@"
