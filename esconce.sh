#!/bin/bash
# esconce — Modular post-installation setup for Bluefin-DX
#
# Transforms a fresh Bluefin installation into a fully configured
# development workstation. Modular steps, auto-resume after reboot,
# simple list-file configuration.
#
# Usage:
#   ./esconce.sh [options]
#
# Options:
#   --init              Create personal config from examples
#   --skip <steps>      Skip step(s) (comma-separated)
#   --only <steps>      Run only these step(s) (comma-separated)
#   --dry-run           Show what would be done without executing
#   --log [file]        Log all output to file
#   --status            Show current progress and exit
#   --list-steps        List available steps and exit
#   --reset             Clear saved progress and start fresh
#   -h, --help          Show this help message

set -euo pipefail

ESCONCE_VERSION="2.0.0"
ESCONCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# State
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/esconce"
PROGRESS_FILE="$STATE_DIR/progress"
PENDING_REBOOT_FILE="$STATE_DIR/pending_reboot"

# Options
DRY_RUN=false
ENABLE_LOG=false
LOG_FILE=""
RESET_PROGRESS=false
SHOW_STATUS=false
INIT_CONFIG=false
LIST_STEPS=false
SKIP_STEPS=()
ONLY_STEPS=()

# Config directory (set after loading)
CONFIG_DIR=""

# ============================================================================
# Source library modules (alphabetical order is fine — no inter-dependencies)
# ============================================================================

for _lib in "$ESCONCE_DIR"/lib/*.sh; do
    [[ -f "$_lib" ]] && source "$_lib"
done

# ============================================================================
# Step discovery — reads steps/NN-name.sh files to build step list
# ============================================================================

ALL_STEPS=()
declare -A STEP_FILES=()
declare -A STEP_DESCRIPTIONS=()

discover_steps() {
    local _step_file _basename _step_name _desc
    for _step_file in "$ESCONCE_DIR"/steps/[0-9][0-9]-*.sh; do
        [[ -f "$_step_file" ]] || continue
        _basename=$(basename "$_step_file" .sh)
        _step_name="${_basename#[0-9][0-9]-}"
        _desc=$(grep '^# Description:' "$_step_file" | head -1 | sed 's/^# Description: *//')

        ALL_STEPS+=("$_step_name")
        STEP_FILES["$_step_name"]="$_step_file"
        STEP_DESCRIPTIONS["$_step_name"]="${_desc:-$_step_name}"
    done
}

# Source all step files (defines their step_*() functions)
load_steps() {
    local _name
    for _name in "${ALL_STEPS[@]}"; do
        source "${STEP_FILES[$_name]}"
    done
}

# ============================================================================
# Configuration loading
# ============================================================================

load_config() {
    local config_dir="$ESCONCE_DIR/config"
    local example_dir="$ESCONCE_DIR/config.example"

    if [[ -f "$config_dir/settings.sh" ]]; then
        source "$config_dir/settings.sh"
        CONFIG_DIR="$config_dir"
    elif [[ -f "$example_dir/settings.sh" ]]; then
        log_warn "Using example config — run '$(basename "$0") --init' to create your own"
        source "$example_dir/settings.sh"
        CONFIG_DIR="$example_dir"
    else
        log_error "No configuration found!"
        log_error "Run '$(basename "$0") --init' to create config from examples"
        exit 1
    fi

    log_info "Config: $CONFIG_DIR"
}

init_config() {
    local src="$ESCONCE_DIR/config.example"
    local dst="$ESCONCE_DIR/config"

    if [[ ! -d "$src" ]]; then
        log_error "No config.example/ directory found"
        exit 1
    fi

    if [[ -d "$dst" ]]; then
        log_warn "config/ directory already exists"
        if ! confirm "Overwrite with examples? (existing files will be replaced)" "n"; then
            log_info "Cancelled"
            exit 0
        fi
    fi

    cp -r "$src" "$dst"
    log_success "Created config/ from config.example/"
    echo ""
    log_info "Edit files in config/ to customize your setup:"
    echo "  config/settings.sh              Main settings (server URLs, feature toggles)"
    echo "  config/packages.list            RPM packages to layer"
    echo "  config/flatpaks.list            Flatpak applications"
    echo "  config/extensions.list          GNOME Shell extensions"
    echo "  config/flatpak-overrides/       Per-app Flatpak permissions"
    echo "  config/repos.d/                 RPM repository files"
    echo "  config/nextcloud/folders.list   Nextcloud sync folders"
    echo "  config/nextcloud/exclude.lst    Sync exclusion rules"
    echo "  config/certs/                   CA certificates (.pem)"
    echo "  config/dconf-settings.ini       GNOME desktop settings"
    echo "  config/gtk3-bookmarks           Nautilus sidebar bookmarks"
}

# ============================================================================
# Step filtering (--skip / --only)
# ============================================================================

should_run_step() {
    local step="$1"

    # --only: whitelist mode
    if [[ ${#ONLY_STEPS[@]} -gt 0 ]]; then
        printf '%s\n' "${ONLY_STEPS[@]}" | grep -qx "$step"
        return $?
    fi

    # --skip: blacklist mode
    if [[ ${#SKIP_STEPS[@]} -gt 0 ]]; then
        if printf '%s\n' "${SKIP_STEPS[@]}" | grep -qx "$step"; then
            return 1
        fi
    fi

    return 0
}

validate_step_names() {
    local name
    for name in "$@"; do
        if [[ -z "${STEP_FILES[$name]+x}" ]]; then
            log_error "Unknown step: '$name'"
            log_info "Available steps: ${ALL_STEPS[*]}"
            exit 1
        fi
    done
}

# ============================================================================
# Argument parsing
# ============================================================================

show_help() {
    cat << HELPEOF
esconce — Bluefin-DX Post-Installation Setup (v${ESCONCE_VERSION})

Usage: $(basename "$0") [options]

Options:
  --init              Create personal config/ from config.example/
  --skip <steps>      Skip step(s) (comma-separated: rebase,ujust,packages)
  --only <steps>      Run only these step(s) (comma-separated)
  --dry-run           Show what would be done without executing
  --log [file]        Log output to file (default: timestamped in state dir)
  --status            Show current progress and exit
  --list-steps        List all available steps and exit
  --reset             Clear saved progress and start fresh
  -h, --help          Show this help message

Steps:
$(for step in "${ALL_STEPS[@]}"; do printf "  %-17s %s\n" "$step" "${STEP_DESCRIPTIONS[$step]}"; done)

Examples:
  $(basename "$0")                          # Run all steps
  $(basename "$0") --skip rebase,ujust      # Skip rebase and ujust
  $(basename "$0") --only extensions,dconf  # Only run extensions and dconf
  $(basename "$0") --dry-run --log          # Preview with logging
  $(basename "$0") --init                   # Create config from examples

Config:
  Edit files in config/ to customize. Run --init to create from examples.
  See README.md for full documentation.
HELPEOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip)
                [[ -z "${2:-}" ]] && { log_error "--skip requires step name(s)"; exit 1; }
                IFS=',' read -ra _s <<< "$2"
                SKIP_STEPS+=("${_s[@]}")
                shift 2
                ;;
            --only)
                [[ -z "${2:-}" ]] && { log_error "--only requires step name(s)"; exit 1; }
                IFS=',' read -ra _s <<< "$2"
                ONLY_STEPS+=("${_s[@]}")
                shift 2
                ;;
            --dry-run)     DRY_RUN=true;       shift ;;
            --log)
                ENABLE_LOG=true
                if [[ "${2:-}" && ! "$2" =~ ^-- ]]; then
                    LOG_FILE="$2"; shift
                fi
                shift
                ;;
            --reset)       RESET_PROGRESS=true; shift ;;
            --status)      SHOW_STATUS=true;    shift ;;
            --init)        INIT_CONFIG=true;    shift ;;
            --list-steps)  LIST_STEPS=true;     shift ;;
            -h|--help)     show_help ;;
            *)
                log_error "Unknown option: $1"
                echo "Run '$(basename "$0") --help' for usage"
                exit 1
                ;;
        esac
    done

    if [[ ${#SKIP_STEPS[@]} -gt 0 && ${#ONLY_STEPS[@]} -gt 0 ]]; then
        log_error "Cannot use --skip and --only together"
        exit 1
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Esconce — Bluefin-DX Setup  v${ESCONCE_VERSION}               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Discover steps first (needed for --help and validation)
    discover_steps

    parse_args "$@"

    # ── Standalone commands (no config needed) ──

    if [[ "$INIT_CONFIG" == "true" ]]; then
        init_config
        exit 0
    fi

    if [[ "$LIST_STEPS" == "true" ]]; then
        echo "Available steps:"
        for step in "${ALL_STEPS[@]}"; do
            printf "  %-17s %s\n" "$step" "${STEP_DESCRIPTIONS[$step]}"
        done
        exit 0
    fi

    # ── Logging ──

    if [[ "$ENABLE_LOG" == "true" ]]; then
        mkdir -p "$STATE_DIR"
        [[ -z "$LOG_FILE" ]] && LOG_FILE="$STATE_DIR/setup-$(date +%Y-%m-%d_%H%M%S).log"
        start_logging "$LOG_FILE" "$@"
    fi

    # ── Reset / Status (need state dir but not full config) ──

    if [[ "$RESET_PROGRESS" == "true" ]]; then
        init_progress
        reset_progress
        exit 0
    fi

    if [[ "$SHOW_STATUS" == "true" ]]; then
        init_progress
        show_progress_status
        exit 0
    fi

    # ── Full run ──

    load_config
    load_steps

    # Validate step names
    [[ ${#SKIP_STEPS[@]} -gt 0 ]] && validate_step_names "${SKIP_STEPS[@]}"
    [[ ${#ONLY_STEPS[@]} -gt 0 ]] && validate_step_names "${ONLY_STEPS[@]}"

    init_progress

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE — No changes will be made"
    fi

    # Preflight checks
    run_preflight_checks

    # System info
    log_section "System Information"
    log_info "Image:    $(get_current_image)"
    log_info "Hostname: $(hostname)"
    log_info "User:     $(whoami)"
    log_info "Config:   $CONFIG_DIR"
    if is_dx_image; then
        log_info "Already running a DX variant"
    else
        log_warn "Not currently on a DX variant"
    fi
    echo ""

    # Progress / resume logic
    local next_step
    next_step=$(get_next_step)

    if [[ "$next_step" == "done" && ${#ONLY_STEPS[@]} -eq 0 ]]; then
        log_success "All steps already completed!"
        show_progress_status
        if confirm "Reset progress and start fresh?" "n"; then
            reset_progress
            next_step=$(get_next_step)
        else
            exit 0
        fi
    fi

    if check_pending_reboot; then
        log_info "Continuing setup after reboot..."
    elif [[ "$next_step" != "${ALL_STEPS[0]:-}" ]]; then
        log_info "Resuming from step: $next_step"
        show_progress_status
        echo ""
    fi

    if ! confirm "Continue with setup?"; then
        log_info "Setup cancelled"
        exit 0
    fi

    # Prevent sleep
    start_inhibitor
    trap 'stop_inhibitor' EXIT

    # ── Run steps ──

    for step_name in "${ALL_STEPS[@]}"; do
        # Already completed (from saved progress)
        if is_step_done "$step_name" && [[ ${#ONLY_STEPS[@]} -eq 0 ]]; then
            log_info "[$step_name] Already completed"
            continue
        fi

        # Filtered out by --skip / --only
        if ! should_run_step "$step_name"; then
            log_info "[$step_name] Skipped"
            mark_step_done "$step_name"
            continue
        fi

        # Run the step
        local step_rc=0
        "step_${step_name}" || step_rc=$?

        case $step_rc in
            0)
                mark_step_done "$step_name"
                ;;
            42)
                # Step signalled "reboot required"
                mark_step_done "$step_name"
                log_warn "Reboot required to continue. Run the script again after reboot."
                exit 0
                ;;
            *)
                log_warn "Step '$step_name' had issues (exit code: $step_rc)"
                if ! confirm "Continue with remaining steps?"; then
                    exit 1
                fi
                # Mark done anyway so we don't loop on a broken step
                mark_step_done "$step_name"
                ;;
        esac
    done

    # ── Done ──

    log_section "Setup Complete!"
    show_progress_status
    echo ""

    if is_step_done "packages"; then
        log_info "If you layered packages, reboot to apply rpm-ostree changes!"
    fi
    if is_step_done "nextcloud"; then
        log_info "Don't forget to log in to Nextcloud to activate folder syncs!"
    fi

    log_info "After reboot, you may need to log out/in for extensions to activate"
    echo ""

    if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        log_info "Full log: $LOG_FILE"
    fi

    log_success "All done! Enjoy your Bluefin-DX setup 🐟"

    if confirm "Clear saved progress (setup complete)?" "y"; then
        reset_progress
    fi
}

main "$@"
