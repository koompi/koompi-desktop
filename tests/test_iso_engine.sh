#!/usr/bin/env bash
# The ISO's install engine, `koompi-install --answers FILE`, in its --dry-run mode:
# the answers the KOOMPI installer (the TUI) writes become the archinstall config
# that wipes the chosen disk with archinstall's default btrfs layout, for UEFI and
# BIOS, with and without LUKS. Bad answers stop it with an @@koompi fail line;
# passwords never reach the output, the log or the dry-run files; the answers file
# is gone afterwards. Without arguments it is still archinstall's own menu.
#
# Whether archinstall 4.5 itself accepts the config is a dev tool, not this test:
# sdata/dist-arch/iso/test/check-archinstall-config.py (it needs archinstall and its
# Python dependencies unpacked).
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$REPO_ROOT/sdata/dist-arch/iso/koompi/airootfs/usr/local/bin/koompi-install"

command -v jq >/dev/null || { echo "skip: jq not installed"; exit 0; }

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "${tmp:?}"' EXIT

# anything that would touch the machine is recorded instead; a dry run calls none
mkdir "$tmp/bin"
for cmd in archinstall arch-chroot cryptsetup mount umount systemctl nmtui; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/calls"\n' "$cmd" "$tmp" > "$tmp/bin/$cmd"
    chmod +x "$tmp/bin/$cmd"
done
export PATH="$tmp/bin:$PATH"

USER_PW='pw-USER-x7Q'
LUKS_PW='pw-LUKS-k3Z'
GiB=$((1024 ** 3)); MiB=$((1024 ** 2))

# answers JSON on stdout; $1 encrypt (true|false), then jq assignments to override
answers() {
    local encrypt="$1"; shift
    jq -n --argjson e "$encrypt" --arg up "$USER_PW" --arg lp "$LUKS_PW" "{
        version: 1, disk: \"/dev/koompi-test-disk\", encrypt: \$e,
        encryption_password: (if \$e then \$lp else \"\" end),
        hostname: \"koompi-lab\", full_name: \"Sok Dara\", username: \"dara\", password: \$up,
        timezone: \"Asia/Phnom_Penh\", keyboard: \"us\", locale: \"en_US.UTF-8\"
    } ${1:+| $1}"
}

# run NAME FIRMWARE: the engine on $tmp/NAME/answers.json, output in $tmp/NAME/{out,stdout}
run() {
    local name="$1" firmware="$2"
    KOOMPI_FIRMWARE="$firmware" KOOMPI_DISK_BYTES="${DISK_BYTES:-$((64 * GiB + 12345 * 512))}" \
        bash "$ENGINE" --answers "$tmp/$name/answers.json" --dry-run "$tmp/$name/out" \
        > "$tmp/$name/stdout" 2>&1
}

no_secrets() {
    local name="$1"
    if grep -rqF -e "$USER_PW" -e "$LUKS_PW" "$tmp/$name"; then
        fail "$name: a password shows in the output, the log or the dry-run files"
    fi
    [[ ! -e "$tmp/$name/answers.json" ]] || fail "$name: the answers file was not deleted"
}

# --- a good install, both firmwares --------------------------------------------
for firmware in uefi bios; do
    for encrypt in false true; do
        name="$firmware-$encrypt"
        mkdir -p "$tmp/$name"
        answers "$encrypt" > "$tmp/$name/answers.json"
        run "$name" "$firmware" || fail "$name: the dry run exited non-zero: $(tail -n3 "$tmp/$name/stdout")"
        cfg="$tmp/$name/out/config.json" creds="$tmp/$name/out/creds.json"
        [[ -s "$cfg" && -s "$creds" ]] || { fail "$name: no config/creds written"; continue; }
        no_secrets "$name"
        grep -qx '@@koompi done' "$tmp/$name/stdout" || fail "$name: no '@@koompi done'"
        grep -qx '@@koompi step 1/8 Checking your answers' "$tmp/$name/stdout" || fail "$name: no step line"
        grep -qx '@@koompi done' "$tmp/$name/out/koompi-install.log" || fail "$name: the log misses the output"

        dm='.disk_config.device_modifications[0]'
        jq -e '.disk_config.device_modifications | length == 1 and .[0].device == "/dev/koompi-test-disk" and .[0].wipe == true' "$cfg" >/dev/null \
            || fail "$name: the config does not wipe exactly /dev/koompi-test-disk"
        jq -e '.disk_config.config_type == "default_layout"' "$cfg" >/dev/null || fail "$name: not archinstall's default layout"
        jq -e "[${dm}.partitions[] | .status] == [\"create\", \"create\"]" "$cfg" >/dev/null || fail "$name: want two new partitions"

        boot_flags='["boot"]'; [[ $firmware == uefi ]] && boot_flags='["boot","esp"]'
        jq -e "${dm}.partitions[0] | .fs_type == \"fat32\" and .mountpoint == \"/boot\" and .flags == $boot_flags
            and .start == {value: 1, unit: \"MiB\", sector_size: {value: 512, unit: \"B\"}} and .size.value == 1 and .size.unit == \"GiB\"" \
            "$cfg" >/dev/null || fail "$name: /boot is not a 1 GiB FAT32 partition flagged $boot_flags"
        jq -e "${dm}.partitions[1] | .fs_type == \"btrfs\" and .mountpoint == null and .mount_options == [\"compress=zstd\"]
            and .btrfs == [{name: \"@\", mountpoint: \"/\"}, {name: \"@home\", mountpoint: \"/home\"},
                           {name: \"@log\", mountpoint: \"/var/log\"}, {name: \"@pkg\", mountpoint: \"/var/cache/pacman/pkg\"}]" \
            "$cfg" >/dev/null || fail "$name: root is not btrfs with @ @home @log @pkg and compress=zstd"

        # root: right after /boot, MiB-aligned, clear of the backup GPT on UEFI
        read -r start size < <(jq -r "${dm}.partitions[1] | \"\(.start.value) \(.size.value)\"" "$cfg")
        end_max=$((64 * GiB + 12345 * 512)); [[ $firmware == uefi ]] && end_max=$((end_max - MiB))
        (( start == MiB + GiB && start % MiB == 0 && size % MiB == 0 && start + size <= end_max && start + size > end_max - MiB )) \
            || fail "$name: root partition $start+$size does not fill the disk (max end $end_max)"

        if [[ $encrypt == true ]]; then
            jq -e '.disk_config as $d | $d.disk_encryption | .encryption_type == "luks"
                and .partitions == [$d.device_modifications[0].partitions[1].obj_id]' "$cfg" >/dev/null \
                || fail "$name: LUKS is not on the root partition"
            jq -e '.encryption_password == "<redacted>"' "$creds" >/dev/null || fail "$name: no (redacted) encryption password in creds"
        else
            jq -e '.disk_config | has("disk_encryption") | not' "$cfg" >/dev/null || fail "$name: encryption that was not asked for"
            jq -e 'has("encryption_password") | not' "$creds" >/dev/null || fail "$name: an encryption password that was not asked for"
        fi

        jq -e '.hostname == "koompi-lab" and .timezone == "Asia/Phnom_Penh"
            and .locale_config == {kb_layout: "us", sys_enc: "UTF-8", sys_lang: "en_US.UTF-8"}
            and .bootloader_config.bootloader == "Grub" and (has("users") | not) and (has("!root-password") | not)
            and .profile_config.profile.path == "/usr/share/koompi/archinstall/koompi_hyprland.py"' "$cfg" >/dev/null \
            || fail "$name: hostname/timezone/locale/GRUB/profile wrong, or an account in the (non-secret) config"
        jq -e '.users == [{username: "dara", "!password": "<redacted>", sudo: true, groups: []}]' "$creds" >/dev/null \
            || fail "$name: creds do not hold one sudo account for dara"
    done
done

# --- answers it must refuse --------------------------------------------------------
refuse() {
    local name="$1" why="$2" filter="$3" encrypt="${4:-false}"
    mkdir -p "$tmp/$name"
    answers "$encrypt" "$filter" > "$tmp/$name/answers.json"
    if run "$name" uefi; then fail "$name: accepted ($why)"; fi
    grep -q "^@@koompi fail .*$why" "$tmp/$name/stdout" \
        || fail "$name: no '@@koompi fail ...$why' line: $(grep '@@koompi' "$tmp/$name/stdout" | tail -n1)"
    no_secrets "$name"
}
refuse empty-pw 'password is empty' '.password = ""'
refuse no-luks-pw 'needs a passphrase' '.encryption_password = ""' true
refuse version 'answers version' '.version = 2'
refuse not-dev 'must be a /dev path' '.disk = "vda"'
refuse char-dev 'not a block device' '.disk = "/dev/null"'
refuse bad-user 'username' '.username = "Dara"'
refuse root-user 'taken by the system' '.username = "root"'
refuse bad-host 'hostname' '.hostname = "-koompi"'
refuse encrypt-str 'true or false' '.encrypt = "yes"'
refuse gecos 'full name' '.full_name = "Sok:Dara"'
DISK_BYTES=$((19 * GiB)) refuse small 'too small' '.'
mkdir -p "$tmp/not-json"; echo 'not json' > "$tmp/not-json/answers.json"
run not-json uefi && fail "not-json: accepted"
grep -q '^@@koompi fail the answers file is not a JSON object' "$tmp/not-json/stdout" || fail "not-json: no fail line"

[[ ! -s "$tmp/calls" ]] || fail "a dry run ran: $(sort -u "$tmp/calls" | tr '\n' ';')"

# --- no arguments: archinstall's own menu, as before -------------------------------
printf '#!/usr/bin/env bash\necho 0\n' > "$tmp/bin/id"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/curl"
chmod +x "$tmp/bin/id" "$tmp/bin/curl"
: > "$tmp/calls"
printf '\n\n' | bash "$ENGINE" >/dev/null 2>&1 || fail "koompi-install with no arguments exited non-zero"
grep -qx "archinstall --config $(dirname "$ENGINE")/../../share/koompi/archinstall/config.json" "$tmp/calls" \
    || fail "koompi-install with no arguments did not start archinstall's menu with config.json: $(cat "$tmp/calls")"

[[ $failed -eq 0 ]] && echo "PASS: test_iso_engine"
exit "$failed"
