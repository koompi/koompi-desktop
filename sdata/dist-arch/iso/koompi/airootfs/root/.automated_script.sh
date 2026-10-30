#!/usr/bin/env bash
# KOOMPI live session, first login on tty1 (root's ~/.zlogin runs this).
#
# A script= boot parameter runs that script instead (Arch releng's hook: an
# unattended install, or the QEMU install test). Otherwise the installer starts;
# Ctrl+C at its first prompt leaves a root shell, and `koompi-install` restarts it.

script_cmdline() {
    local param
    for param in $(</proc/cmdline); do
        case "${param}" in
            script=*) echo "${param#*=}"; return 0 ;;
        esac
    done
}

automated_script() {
    local script rt
    script="$(script_cmdline)"
    [[ -n "${script}" ]] || return 1
    [[ ! -x /tmp/startup_script ]] || return 0
    if [[ "${script}" =~ ^((http|https|ftp|tftp)://) ]]; then
        printf '%s: waiting for network-online.target\n' "$0"
        # nothing else on the live ISO pulls the target in; started, it waits on NetworkManager
        systemctl --no-block start network-online.target
        until systemctl --quiet is-active network-online.target; do sleep 1; done
        printf '%s: downloading %s\n' "$0" "${script}"
        curl "${script}" --location --retry-connrefused --retry 10 --fail -s -o /tmp/startup_script
        rt=$?
    else
        cp "${script}" /tmp/startup_script
        rt=$?
    fi
    if [[ ${rt} -eq 0 ]]; then
        chmod +x /tmp/startup_script
        printf '%s: executing automated script\n' "$0"
        /tmp/startup_script
    fi
    return 0
}

if [[ $(tty) == "/dev/tty1" ]]; then
    automated_script || koompi-install
fi
