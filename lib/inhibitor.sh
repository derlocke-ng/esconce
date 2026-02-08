#!/bin/bash
# lib/inhibitor.sh - Prevent sleep/screensaver during long operations

INHIBIT_COOKIE=""

start_inhibitor() {
    if command -v gnome-session-inhibit &> /dev/null; then
        log_info "Inhibiting sleep/screensaver while setup runs..."
        INHIBIT_COOKIE=$(gdbus call --session \
            --dest org.gnome.SessionManager \
            --object-path /org/gnome/SessionManager \
            --method org.gnome.SessionManager.Inhibit \
            "esconce" 0 "Running post-installation setup" 12 2>/dev/null \
            | grep -oP '\d+' || echo "")

        if [[ -n "$INHIBIT_COOKIE" ]]; then
            log_success "Inhibitor active (cookie: $INHIBIT_COOKIE)"
        else
            _start_systemd_inhibitor
        fi
    elif command -v systemd-inhibit &> /dev/null; then
        _start_systemd_inhibitor
    else
        log_warn "No inhibitor available — system may sleep during long operations"
    fi
}

_start_systemd_inhibitor() {
    log_info "Using systemd-inhibit to prevent sleep..."
    systemd-inhibit --what=idle:sleep:handle-lid-switch \
        --who="esconce" \
        --why="Running post-installation setup" \
        sleep infinity &
    INHIBIT_COOKIE="systemd:$!"
    log_success "Inhibitor active (PID: $!)"
}

stop_inhibitor() {
    [[ -z "$INHIBIT_COOKIE" ]] && return 0

    if [[ "$INHIBIT_COOKIE" == systemd:* ]]; then
        kill "${INHIBIT_COOKIE#systemd:}" 2>/dev/null || true
    else
        gdbus call --session \
            --dest org.gnome.SessionManager \
            --object-path /org/gnome/SessionManager \
            --method org.gnome.SessionManager.Uninhibit \
            "$INHIBIT_COOKIE" 2>/dev/null || true
    fi
    log_info "Inhibitor released"
    INHIBIT_COOKIE=""
}
