#!/usr/bin/env bash
# shellcheck disable=SC1090

#########################################################
# Arch Linux INSTALLER | Automated Arch Linux Installer TUI
#########################################################

# SOURCE:   https://github.com/snaplyze/arch-linux-gnome
# AUTOR:    snaplyze
# ORIGIN:   Russia
# LICENCE:  GPL 2.0

# CONFIG
set -o pipefail # A pipeline error results in the error status of the entire pipeline
set -e          # Terminate if any command exits with a non-zero
set -E          # ERR trap inherited by shell functions (errtrace)

# ENVIRONMENT
: "${DEBUG:=false}"            # DEBUG=true ./installer.sh
: "${FORCE:=false}"            # FORCE=true ./installer.sh
: "${GUM:=/usr/local/bin/gum}" # GUM=/usr/bin/gum ./installer.sh

# SCRIPT
VERSION='1.0.0'

# VERSION
[ "$*" = "--version" ] && echo "$VERSION" && exit 0

# GUM
GUM_VERSION="0.13.0"

# ENVIRONMENT
SCRIPT_CONFIG="./installer.conf"
SCRIPT_LOG="./installer.log"

# INIT
INIT_FILENAME="initialize"

# TEMP
SCRIPT_TMP_DIR="$(mktemp -d "./.tmp.XXXXX")"
ERROR_MSG="${SCRIPT_TMP_DIR}/installer.err"
PROCESS_LOG="${SCRIPT_TMP_DIR}/process.log"
PROCESS_RET="${SCRIPT_TMP_DIR}/process.ret"

# COLORS
COLOR_BLACK=0   #  #000000
COLOR_RED=9     #  #ff0000
COLOR_GREEN=10  #  #00ff00
COLOR_YELLOW=11 #  #ffff00
COLOR_BLUE=12   #  #0000ff
COLOR_PURPLE=13 #  #ff00ff
COLOR_CYAN=14   #  #00ffff
COLOR_WHITE=15  #  #ffffff

COLOR_FOREGROUND="${COLOR_BLUE}"
COLOR_BACKGROUND="${COLOR_WHITE}"

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main() {

    # Clear logfile
    [ -f "$SCRIPT_LOG" ] && mv -f "$SCRIPT_LOG" "${SCRIPT_LOG}.old"

    # Check gum binary or download
    gum_init

    # Traps (error & exit)
    trap 'trap_exit' EXIT
    trap 'trap_error ${FUNCNAME} ${LINENO}' ERR

    # Print version to logfile
    log_info "Arch Linux ${VERSION}"

    # ---------------------------------------------------------------------------------------------------

    # Loop properties step to update screen if user edit properties
    while (true); do

        print_header "Arch Linux Installer" # Show landig page
        gum_white 'Please make sure you have:' && echo
        gum_white '• Backed up your important data'
        gum_white '• A stable internet connection'
        gum_white '• Secure Boot disabled'
        gum_white '• Boot Mode set to UEFI'

        # Ask for load & remove existing config file
        if [ "$FORCE" = "false" ] && [ -f "$SCRIPT_CONFIG" ] && ! gum_confirm "Load existing installer.conf?"; then
            gum_confirm "Remove existing installer.conf?" || trap_gum_exit # If not want remove config > exit script
            echo && gum_title "Properties File"
            mv -f "$SCRIPT_CONFIG" "${SCRIPT_CONFIG}.old" && gum_info "installer.conf was moved to installer.conf.old"
            gum_warn "Please restart Arch Linux Installer..."
            echo && exit 0
        fi

        echo # Print new line

        # Source installer.conf if exists or select preset
        until properties_preset_source; do :; done

        # Selectors
        echo && gum_title "Core Setup"
        until select_username; do :; done
        until select_password; do :; done
        until select_timezone; do :; done
        until select_language; do :; done
        until select_keyboard; do :; done
        until select_filesystem; do :; done
        until select_bootloader; do :; done
        until select_disk; do :; done
        echo && gum_title "Desktop Setup"
        until select_enable_desktop_environment; do :; done
        until select_enable_desktop_driver; do :; done
        until select_enable_desktop_slim; do :; done
        until select_enable_desktop_keyboard; do :; done
        echo && gum_title "Feature Setup"
        until select_enable_encryption; do :; done
        until select_enable_core_tweaks; do :; done
        until select_enable_bootsplash; do :; done
        until select_enable_multilib; do :; done
        until select_enable_aur; do :; done
        until select_enable_housekeeping; do :; done
        until select_enable_shell_enhancement; do :; done

        # Print success
        echo && gum_title "Properties"

        # Open Advanced Properties?
        if [ "$FORCE" = "false" ] && gum_confirm --negative="Skip" "Open Advanced Setup Editor?"; then
            local header_txt="• Advanced Setup | Save with CTRL + D or ESC and cancel with CTRL + C"
            if gum_write --show-line-numbers --prompt "" --height=12 --width=180 --char-limit=0 --header="${header_txt}" --value="$(cat "$SCRIPT_CONFIG")" >"${SCRIPT_CONFIG}.new"; then
                mv "${SCRIPT_CONFIG}.new" "${SCRIPT_CONFIG}" && properties_source
                gum_info "Properties successfully saved"
                gum_confirm "Change Password?" && until select_password --change && properties_source; do :; done
                echo && ! gum_spin --title="Reload Properties in 3 seconds..." -- sleep 3 && trap_gum_exit
                continue # Restart properties step to refresh properties screen
            else
                rm -f "${SCRIPT_CONFIG}.new" # Remove tmp properties
                gum_warn "Advanced Setup canceled"
            fi
        fi

        # Finish
        gum_info "Successfully initialized"

        ######################################################
        break # Exit properties step and continue installation
        ######################################################
    done

    # ---------------------------------------------------------------------------------------------------

    # Start installation in 5 seconds?
    if [ "$FORCE" = "false" ]; then
        gum_confirm "Start Arch Linux Installation?" || trap_gum_exit
    fi
    local spin_title="Arch Linux Installation starts in 5 seconds. Press CTRL + C to cancel..."
    echo && ! gum_spin --title="$spin_title" -- sleep 5 && trap_gum_exit # CTRL + C pressed
    gum_title "Arch Linux Installation"

    SECONDS=0 # Messure execution time of installation

    # Executors
    exec_init_installation
    exec_prepare_disk
    exec_pacstrap_core
    exec_enable_multilib
    exec_install_aur_helper
    exec_install_bootsplash
    exec_install_housekeeping
    exec_install_shell_enhancement
    exec_install_desktop
    exec_install_graphics_driver
    exec_install_vm_support
    exec_finalize_arch_linux

    # Calc installation duration
    duration=$SECONDS # This is set before install starts
    duration_min="$((duration / 60))"
    duration_sec="$((duration % 60))"

    # Print duration time info
    local finish_txt="Installation successful in ${duration_min} minutes and ${duration_sec} seconds"
    echo && gum_green --bold "$finish_txt"
    log_info "$finish_txt"

    # Copy installer files to users home
    if [ "$DEBUG" = "false" ]; then
        cp -f "$SCRIPT_CONFIG" "/mnt/home/${ARCH_LINUX_USERNAME}/installer.conf"
        sed -i "1i\# Arch Linux Version: ${VERSION}" "/mnt/home/${ARCH_LINUX_USERNAME}/installer.conf"
        cp -f "$SCRIPT_LOG" "/mnt/home/${ARCH_LINUX_USERNAME}/installer.log"
        arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}/installer.conf"
        arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}/installer.log"
    fi

    wait # Wait for sub processes

    # ---------------------------------------------------------------------------------------------------

    # Show reboot & unmount promt
    local do_reboot do_unmount do_chroot

    # Default values
    do_reboot="false"
    do_chroot="false"
    do_unmount="false"

    # Force values
    if [ "$FORCE" = "true" ]; then
        do_reboot="false"
        do_chroot="false"
        do_unmount="true"
    fi

    # Reboot promt
    [ "$FORCE" = "false" ] && gum_confirm "Reboot to Arch Linux now?" && do_reboot="true" && do_unmount="true"

    # Unmount
    [ "$FORCE" = "false" ] && [ "$do_reboot" = "false" ] && gum_confirm "Unmount Arch Linux from /mnt?" && do_unmount="true"
    [ "$do_unmount" = "true" ] && echo && gum_warn "Unmounting Arch Linux from /mnt..."
    if [ "$DEBUG" = "false" ] && [ "$do_unmount" = "true" ]; then
        swapoff -a
        umount -A -R /mnt
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot
    fi

    # Do reboot
    [ "$FORCE" = "false" ] && [ "$do_reboot" = "true" ] && gum_warn "Rebooting to Arch Linux..." && [ "$DEBUG" = "false" ] && reboot

    # Chroot
    [ "$FORCE" = "false" ] && [ "$do_unmount" = "false" ] && gum_confirm "Chroot to new Arch Linux?" && do_chroot="true"
    if [ "$do_chroot" = "true" ] && echo && gum_warn "Chrooting Arch Linux at /mnt..."; then
        gum_warn "!! YOUR ARE NOW ON YOUR NEW Arch Linux SYSTEM !!"
        gum_warn ">> Leave with command 'exit'"
        if [ "$DEBUG" = "false" ]; then
            arch-chroot /mnt </dev/tty || true
        fi
        wait # Wait for subprocesses
        gum_warn "Please reboot manually..."
    fi

    # Print warning
    [ "$do_unmount" = "false" ] && [ "$do_chroot" = "false" ] && echo && gum_warn "Arch Linux is still mounted at /mnt"

    gum_info "Exit" && exit 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROPERTIES
# ////////////////////////////////////////////////////////////////////////////////////////////////////

properties_source() {
    [ ! -f "$SCRIPT_CONFIG" ] && return 1
    set -a # Load properties file and auto export variables
    source "$SCRIPT_CONFIG"
    set +a
    return 0
}

properties_generate() {
    { # Write properties to installer.conf
        echo "ARCH_LINUX_HOSTNAME='${ARCH_LINUX_HOSTNAME}' # Hostname"
        echo "ARCH_LINUX_USERNAME='${ARCH_LINUX_USERNAME}' # User"
        echo "ARCH_LINUX_DISK='${ARCH_LINUX_DISK}' # Disk"
        echo "ARCH_LINUX_BOOT_PARTITION='${ARCH_LINUX_BOOT_PARTITION}' # Boot partition"
        echo "ARCH_LINUX_ROOT_PARTITION='${ARCH_LINUX_ROOT_PARTITION}' # Root partition"
        echo "ARCH_LINUX_FILESYSTEM='${ARCH_LINUX_FILESYSTEM}' # Filesystem | Available: btrfs, ext4"
        echo "ARCH_LINUX_BOOTLOADER='${ARCH_LINUX_BOOTLOADER}' # Bootloader | Available: grub, systemd"
        echo "ARCH_LINUX_SNAPPER_ENABLED='${ARCH_LINUX_SNAPPER_ENABLED}' # BTRFS Snapper enabled | Disable: false"
        echo "ARCH_LINUX_ENCRYPTION_ENABLED='${ARCH_LINUX_ENCRYPTION_ENABLED}' # Disk encryption | Disable: false"
        echo "ARCH_LINUX_TIMEZONE='${ARCH_LINUX_TIMEZONE}' # Timezone | Show available: ls /usr/share/zoneinfo/** | Example: Europe/Berlin"
        echo "ARCH_LINUX_LOCALE_LANG='${ARCH_LINUX_LOCALE_LANG}' # Locale | Show available: ls /usr/share/i18n/locales | Example: de_DE"
        echo "ARCH_LINUX_LOCALE_GEN_LIST=(${ARCH_LINUX_LOCALE_GEN_LIST[*]@Q}) # Locale List | Show available: cat /etc/locale.gen"
        echo "ARCH_LINUX_REFLECTOR_COUNTRY='${ARCH_LINUX_REFLECTOR_COUNTRY}' # Country used by reflector | Default: null | Example: Germany,France"
        echo "ARCH_LINUX_VCONSOLE_KEYMAP='${ARCH_LINUX_VCONSOLE_KEYMAP}' # Console keymap | Show available: localectl list-keymaps | Example: de-latin1-nodeadkeys"
        echo "ARCH_LINUX_VCONSOLE_FONT='${ARCH_LINUX_VCONSOLE_FONT}' # Console font | Default: null | Show available: find /usr/share/kbd/consolefonts/*.psfu.gz | Example: eurlatgr"
        echo "ARCH_LINUX_KERNEL='${ARCH_LINUX_KERNEL}' # Kernel | Default: linux-zen | Recommended: linux, linux-lts linux-zen, linux-hardened"
        echo "ARCH_LINUX_MICROCODE='${ARCH_LINUX_MICROCODE}' # Microcode | Disable: none | Available: intel-ucode, amd-ucode"
        echo "ARCH_LINUX_CORE_TWEAKS_ENABLED='${ARCH_LINUX_CORE_TWEAKS_ENABLED}' # Arch Linux Core Tweaks | Disable: false"
        echo "ARCH_LINUX_MULTILIB_ENABLED='${ARCH_LINUX_MULTILIB_ENABLED}' # MultiLib 32 Bit Support | Disable: false"
        echo "ARCH_LINUX_AUR_HELPER='${ARCH_LINUX_AUR_HELPER}' # AUR Helper | Default: paru | Disable: none | Recommended: paru, yay, trizen, pikaur"
        echo "ARCH_LINUX_BOOTSPLASH_ENABLED='${ARCH_LINUX_BOOTSPLASH_ENABLED}' # Bootsplash | Disable: false"
        echo "ARCH_LINUX_HOUSEKEEPING_ENABLED='${ARCH_LINUX_HOUSEKEEPING_ENABLED}'  # Housekeeping | Disable: false"
        echo "ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED='${ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED}' # Shell Enhancement | Disable: false"
        echo "ARCH_LINUX_SHELL_ENHANCEMENT_FISH_ENABLED='${ARCH_LINUX_SHELL_ENHANCEMENT_FISH_ENABLED}' # Enable fish shell | Default: true | Disable: false"
        echo "ARCH_LINUX_DESKTOP_ENABLED='${ARCH_LINUX_DESKTOP_ENABLED}' # Arch Linux Desktop (caution: if disabled, only a minimal tty will be provied)| Disable: false"
        echo "ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER='${ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER}' # Graphics Driver | Disable: none | Available: mesa, intel_i915, nvidia, amd, ati"
        echo "ARCH_LINUX_DESKTOP_EXTRAS_ENABLED='${ARCH_LINUX_DESKTOP_EXTRAS_ENABLED}' # Enable desktop extra packages (caution: if disabled, only core + gnome + git packages will be installed) | Disable: false"
        echo "ARCH_LINUX_DESKTOP_SLIM_ENABLED='${ARCH_LINUX_DESKTOP_SLIM_ENABLED}' # Enable Sim Desktop (only GNOME Core Apps) | Default: false"
        echo "ARCH_LINUX_DESKTOP_KEYBOARD_MODEL='${ARCH_LINUX_DESKTOP_KEYBOARD_MODEL}' # X11 keyboard model | Default: pc105 | Show available: localectl list-x11-keymap-models"
        echo "ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT='${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT}' # X11 keyboard layout | Show available: localectl list-x11-keymap-layouts | Example: de"
        echo "ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT='${ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT}' # X11 keyboard variant | Default: null | Show available: localectl list-x11-keymap-variants | Example: nodeadkeys"
        echo "ARCH_LINUX_SAMBA_SHARE_ENABLED='${ARCH_LINUX_SAMBA_SHARE_ENABLED}' # Enable Samba public (anonymous) & home share (user) | Disable: false"
        echo "ARCH_LINUX_VM_SUPPORT_ENABLED='${ARCH_LINUX_VM_SUPPORT_ENABLED}' # VM Support | Default: true | Disable: false"
        echo "ARCH_LINUX_ECN_ENABLED='${ARCH_LINUX_ECN_ENABLED}' # Disable ECN support for legacy routers | Default: true | Disable: false"
    } >"$SCRIPT_CONFIG" # Write properties to file
}

properties_preset_source() {

    # Default presets
    [ -z "$ARCH_LINUX_HOSTNAME" ] && ARCH_LINUX_HOSTNAME="arch-linux"
    [ -z "$ARCH_LINUX_KERNEL" ] && ARCH_LINUX_KERNEL="linux-zen"
    [ -z "$ARCH_LINUX_SNAPPER_ENABLED" ] && ARCH_LINUX_SNAPPER_ENABLED='true'
    [ -z "$ARCH_LINUX_SHELL_ENHANCEMENT_FISH_ENABLED" ] && ARCH_LINUX_SHELL_ENHANCEMENT_FISH_ENABLED="true"
    [ -z "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" ] && ARCH_LINUX_DESKTOP_EXTRAS_ENABLED='true'
    [ -z "$ARCH_LINUX_DESKTOP_KEYBOARD_MODEL" ] && ARCH_LINUX_DESKTOP_KEYBOARD_MODEL="pc105"
    [ -z "$ARCH_LINUX_SAMBA_SHARE_ENABLED" ] && ARCH_LINUX_SAMBA_SHARE_ENABLED="true"
    [ -z "$ARCH_LINUX_ECN_ENABLED" ] && ARCH_LINUX_ECN_ENABLED="true"
    [ -z "$ARCH_LINUX_VM_SUPPORT_ENABLED" ] && ARCH_LINUX_VM_SUPPORT_ENABLED="true"

    # Set microcode
    [ -z "$ARCH_LINUX_MICROCODE" ] && grep -E "GenuineIntel" &>/dev/null <<<"$(lscpu)" && ARCH_LINUX_MICROCODE="intel-ucode"
    [ -z "$ARCH_LINUX_MICROCODE" ] && grep -E "AuthenticAMD" &>/dev/null <<<"$(lscpu)" && ARCH_LINUX_MICROCODE="amd-ucode"

    # Load properties or select preset
    if [ -f "$SCRIPT_CONFIG" ]; then
        properties_source
        gum join "$(gum_green --bold "• ")" "$(gum_white "Setup preset loaded from: ")" "$(gum_white --bold "installer.conf")"
    else
        # Select preset
        local preset options
        options=("desktop - GNOME Desktop Environment (default)" "core    - Minimal Arch Linux TTY Environment" "none    - No pre-selection")
        preset=$(gum_choose --header "+ Choose Setup Preset" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$preset" ] && return 1 # Check if new value is null
        preset="$(echo "$preset" | awk '{print $1}')"

        # Core preset
        if [[ $preset == core* ]]; then
            ARCH_LINUX_SNAPPER_ENABLED='false'
            ARCH_LINUX_DESKTOP_ENABLED='false'
            ARCH_LINUX_MULTILIB_ENABLED='false'
            ARCH_LINUX_HOUSEKEEPING_ENABLED='false'
            ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED='false'
            ARCH_LINUX_BOOTSPLASH_ENABLED='false'
            ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER="none"
            ARCH_LINUX_AUR_HELPER='none'
        fi

        # Desktop preset
        if [[ $preset == desktop* ]]; then
            ARCH_LINUX_SNAPPER_ENABLED='true'
            ARCH_LINUX_DESKTOP_EXTRAS_ENABLED='true'
            ARCH_LINUX_SAMBA_SHARE_ENABLED='true'
            ARCH_LINUX_CORE_TWEAKS_ENABLED="true"
            ARCH_LINUX_BOOTSPLASH_ENABLED='true'
            ARCH_LINUX_DESKTOP_ENABLED='true'
            ARCH_LINUX_MULTILIB_ENABLED='true'
            ARCH_LINUX_HOUSEKEEPING_ENABLED='true'
            ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED='true'
            ARCH_LINUX_AUR_HELPER='paru'
        fi

        # Write properties
        properties_source
        gum join "$(gum_green --bold "• ")" "$(gum_white "Setup preset loaded for: ")" "$(gum_white --bold "$preset")"
    fi
    return 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# SELECTORS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

select_username() {
    if [ -z "$ARCH_LINUX_USERNAME" ]; then
        local user_input
        user_input=$(gum_input --header "+ Enter Username") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                      # Check if new value is null
        ARCH_LINUX_USERNAME="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Username" "$ARCH_LINUX_USERNAME"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_password() { # --change
    if [ "$1" = "--change" ] || [ -z "$ARCH_LINUX_PASSWORD" ]; then
        local user_password user_password_check
        user_password=$(gum_input --password --header "+ Enter Password") || trap_gum_exit_confirm
        [ -z "$user_password" ] && return 1 # Check if new value is null
        user_password_check=$(gum_input --password --header "+ Enter Password again") || trap_gum_exit_confirm
        [ -z "$user_password_check" ] && return 1 # Check if new value is null
        if [ "$user_password" != "$user_password_check" ]; then
            gum_confirm --affirmative="Ok" --negative="" "The passwords are not identical"
            return 1
        fi
        ARCH_LINUX_PASSWORD="$user_password" && properties_generate # Set value and generate properties file
    fi
    [ "$1" = "--change" ] && gum_info "Password successfully changed"
    [ "$1" != "--change" ] && gum_property "Password" "*******"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_timezone() {
    if [ -z "$ARCH_LINUX_TIMEZONE" ]; then
        local tz_auto user_input
        tz_auto="$(curl -s http://ip-api.com/line?fields=timezone)"
        user_input=$(gum_input --header "+ Enter Timezone (auto-detected)" --value "$tz_auto") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1 # Check if new value is null
        if [ ! -f "/usr/share/zoneinfo/${user_input}" ]; then
            gum_confirm --affirmative="Ok" --negative="" "Timezone '${user_input}' is not supported"
            return 1
        fi
        ARCH_LINUX_TIMEZONE="$user_input" && properties_generate # Set property and generate properties file
    fi
    gum_property "Timezone" "$ARCH_LINUX_TIMEZONE"
    return 0
}

# ---------------------------------------------------------------------------------------------------

# shellcheck disable=SC2001
select_language() {
    if [ -z "$ARCH_LINUX_LOCALE_LANG" ] || [ -z "${ARCH_LINUX_LOCALE_GEN_LIST[*]}" ]; then
        local user_input items options filter
        # Fetch available options (list all from /usr/share/i18n/locales and check if entry exists in /etc/locale.gen)
        mapfile -t items < <(basename -a /usr/share/i18n/locales/* | grep -v "@") # Create array without @ files
        # Add only available locales (!!! intense command !!!)
        options=() && for item in "${items[@]}"; do grep -q -e "^$item" -e "^#$item" /etc/locale.gen && options+=("$item"); done
        # shellcheck disable=SC2002
        [ -r /root/.zsh_history ] && filter=$(cat /root/.zsh_history | grep 'loadkeys' | head -n 2 | tail -n 1 | cut -d';' -f2 | cut -d' ' -f2 | cut -d'-' -f1)
        # Select locale
        user_input=$(gum_filter --value="$filter" --header "+ Choose Language" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1  # Check if new value is null
        ARCH_LINUX_LOCALE_LANG="$user_input" # Set property
        # Set locale.gen properties (auto generate ARCH_LINUX_LOCALE_GEN_LIST)
        ARCH_LINUX_LOCALE_GEN_LIST=() && while read -r locale_entry; do
            ARCH_LINUX_LOCALE_GEN_LIST+=("$locale_entry")
            # Remove leading # from matched lang in /etc/locale.gen and add entry to array
        done < <(sed "/^#${ARCH_LINUX_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "$ARCH_LINUX_LOCALE_LANG")
        # Add en_US fallback (every language) if not already exists in list
        [[ "${ARCH_LINUX_LOCALE_GEN_LIST[*]}" != *'en_US.UTF-8 UTF-8'* ]] && ARCH_LINUX_LOCALE_GEN_LIST+=('en_US.UTF-8 UTF-8')
        properties_generate # Generate properties file (for ARCH_LINUX_LOCALE_LANG & ARCH_LINUX_LOCALE_GEN_LIST)
    fi
    gum_property "Language" "$ARCH_LINUX_LOCALE_LANG"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_keyboard() {
    if [ -z "$ARCH_LINUX_VCONSOLE_KEYMAP" ]; then
        local user_input items options filter
        mapfile -t items < <(command localectl list-keymaps)
        options=() && for item in "${items[@]}"; do options+=("$item"); done
        # shellcheck disable=SC2002
        [ -r /root/.zsh_history ] && filter=$(cat /root/.zsh_history | grep 'loadkeys' | head -n 2 | tail -n 1 | cut -d';' -f2 | cut -d' ' -f2 | cut -d'-' -f1)
        user_input=$(gum_filter --value="$filter" --header "+ Choose Keyboard" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                             # Check if new value is null
        ARCH_LINUX_VCONSOLE_KEYMAP="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Keyboard" "$ARCH_LINUX_VCONSOLE_KEYMAP"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_disk() {
    if [ -z "$ARCH_LINUX_DISK" ] || [ -z "$ARCH_LINUX_BOOT_PARTITION" ] || [ -z "$ARCH_LINUX_ROOT_PARTITION" ]; then
        local user_input items options
        mapfile -t items < <(lsblk -I 8,259,254 -d -o KNAME,SIZE -n)
        # size: $(lsblk -d -n -o SIZE "/dev/${item}")
        options=() && for item in "${items[@]}"; do options+=("/dev/${item}"); done
        user_input=$(gum_choose --header "+ Choose Disk" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                          # Check if new value is null
        user_input=$(echo "$user_input" | awk -F' ' '{print $1}') # Remove size from input
        [ ! -e "$user_input" ] && log_fail "Disk does not exists" && return 1
        ARCH_LINUX_DISK="$user_input" # Set property
        [[ "$ARCH_LINUX_DISK" = "/dev/nvm"* ]] && ARCH_LINUX_BOOT_PARTITION="${ARCH_LINUX_DISK}p1" || ARCH_LINUX_BOOT_PARTITION="${ARCH_LINUX_DISK}1"
        [[ "$ARCH_LINUX_DISK" = "/dev/nvm"* ]] && ARCH_LINUX_ROOT_PARTITION="${ARCH_LINUX_DISK}p2" || ARCH_LINUX_ROOT_PARTITION="${ARCH_LINUX_DISK}2"
        properties_generate # Generate properties file
    fi
    gum_property "Disk" "$ARCH_LINUX_DISK"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_filesystem() {
    if [ -z "$ARCH_LINUX_FILESYSTEM" ]; then
        local user_input options
        options=("btrfs" "ext4")
        user_input=$(gum_choose --header "+ Choose Filesystem (snapshot support: btrfs)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                        # Check if new value is null
        ARCH_LINUX_FILESYSTEM="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Filesystem" "${ARCH_LINUX_FILESYSTEM}"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_bootloader() {
    if [ -z "$ARCH_LINUX_BOOTLOADER" ]; then
        local user_input options
        options=("grub" "systemd")
        user_input=$(gum_choose --header "+ Choose Bootloader (snapshot menu: grub)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                        # Check if new value is null
        ARCH_LINUX_BOOTLOADER="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Bootloader" "${ARCH_LINUX_BOOTLOADER}"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_encryption() {
    if [ -z "$ARCH_LINUX_ENCRYPTION_ENABLED" ]; then
        gum_confirm "Enable Disk Encryption?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_ENCRYPTION_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Disk Encryption" "$ARCH_LINUX_ENCRYPTION_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_core_tweaks() {
    if [ -z "$ARCH_LINUX_CORE_TWEAKS_ENABLED" ]; then
        gum_confirm "Enable Core Tweaks?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_CORE_TWEAKS_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Core Tweaks" "$ARCH_LINUX_CORE_TWEAKS_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_bootsplash() {
    if [ -z "$ARCH_LINUX_BOOTSPLASH_ENABLED" ]; then
        gum_confirm "Enable Bootsplash?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_BOOTSPLASH_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Bootsplash" "$ARCH_LINUX_BOOTSPLASH_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_environment() {
    if [ -z "$ARCH_LINUX_DESKTOP_ENABLED" ]; then
        local user_input
        gum_confirm "Enable GNOME Desktop Environment?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_DESKTOP_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Desktop Environment" "$ARCH_LINUX_DESKTOP_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_slim() {
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        if [ -z "$ARCH_LINUX_DESKTOP_SLIM_ENABLED" ]; then
            local user_input
            gum_confirm "Enable Desktop Slim Mode? (GNOME Core Apps only)" --affirmative="No (default)" --negative="Yes"
            local user_confirm=$?
            [ $user_confirm = 130 ] && {
                trap_gum_exit_confirm
                return 1
            }
            [ $user_confirm = 1 ] && user_input="true"
            [ $user_confirm = 0 ] && user_input="false"
            ARCH_LINUX_DESKTOP_SLIM_ENABLED="$user_input" && properties_generate # Set value and generate properties file
        fi
        gum_property "Desktop Slim Mode" "$ARCH_LINUX_DESKTOP_SLIM_ENABLED"
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_keyboard() {
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        if [ -z "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT" ]; then
            local user_input user_input2
            user_input=$(gum_input --header "+ Enter Desktop Keyboard Layout" --placeholder "e.g. 'us' or 'de'...") || trap_gum_exit_confirm
            [ -z "$user_input" ] && return 1 # Check if new value is null
            ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT="$user_input"
            gum_property "Desktop Keyboard" "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT"
            user_input2=$(gum_input --header "+ Enter Desktop Keyboard Variant (optional)" --placeholder "e.g. 'nodeadkeys' or leave empty...") || trap_gum_exit_confirm
            ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT="$user_input2"
            properties_generate
        else
            gum_property "Desktop Keyboard" "$ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT"
        fi
        [ -n "$ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT" ] && gum_property "Desktop Keyboard Variant" "$ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT"
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_desktop_driver() {
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        if [ -z "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" ] || [ "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" = "none" ]; then
            local user_input options
            options=("mesa" "intel_i915" "nvidia" "amd" "ati")
            user_input=$(gum_choose --header "+ Choose Desktop Graphics Driver (default: mesa)" "${options[@]}") || trap_gum_exit_confirm
            [ -z "$user_input" ] && return 1                                     # Check if new value is null
            ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER="$user_input" && properties_generate # Set value and generate properties file
        fi
        gum_property "Desktop Graphics Driver" "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER"
    fi
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_aur() {
    if [ -z "$ARCH_LINUX_AUR_HELPER" ]; then
        local user_input options
        options=("paru" "paru-bin" "paru-git" "none")
        user_input=$(gum_choose --header "+ Choose AUR Helper (default: paru)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                        # Check if new value is null
        ARCH_LINUX_AUR_HELPER="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "AUR Helper" "$ARCH_LINUX_AUR_HELPER"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_multilib() {
    if [ -z "$ARCH_LINUX_MULTILIB_ENABLED" ]; then
        gum_confirm "Enable 32 Bit Support?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_MULTILIB_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "32 Bit Support" "$ARCH_LINUX_MULTILIB_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_housekeeping() {
    if [ -z "$ARCH_LINUX_HOUSEKEEPING_ENABLED" ]; then
        gum_confirm "Enable Housekeeping?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_HOUSEKEEPING_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Housekeeping" "$ARCH_LINUX_HOUSEKEEPING_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_shell_enhancement() {
    if [ -z "$ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED" ]; then
        gum_confirm "Enable Shell Enhancement?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Shell Enhancement" "$ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED"
    return 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# EXECUTORS (SUB PROCESSES)
# ////////////////////////////////////////////////////////////////////////////////////////////////////

exec_init_installation() {
    local process_name="Initialize Installation"
    process_init "$process_name"
    (
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
        # Check installation prerequisites
        [ ! -d /sys/firmware/efi ] && log_fail "BIOS not supported! Please set your boot mode to UEFI." && exit 1
        log_info "UEFI detected"
        bootctl status | grep "Secure Boot" | grep -q "disabled" || { log_fail "You must disable Secure Boot in UEFI to continue installation" && exit 1; }
        log_info "Secure Boot: disabled"
        [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ] && log_fail "You must execute the Installer from Arch ISO!" && exit 1
        log_info "Arch ISO detected"
        log_info "Waiting for Reflector from Arch ISO..."
        # This mirrorlist will copied to new Arch system during installation
        while timeout 180 tail --pid=$(pgrep reflector) -f /dev/null &>/dev/null; do sleep 1; done
        pgrep reflector &>/dev/null && log_fail "Reflector timeout after 180 seconds" && exit 1
        rm -f /var/lib/pacman/db.lck # Remove pacman lock file if exists
        timedatectl set-ntp true     # Set time
        # Make sure everything is unmounted before start install
        swapoff -a || true
        umount -R /mnt/recovery || true
        if [[ "$(umount -f -A -R /mnt 2>&1)" == *"target is busy"* ]]; then
            # If umount is busy execute fuser
            fuser -km /mnt || true
            umount -f -A -R /mnt || true
        fi
        wait # Wait for sub process
        cryptsetup close cryptroot || true
        cryptsetup close cryptrecovery || true
        vgchange -an || true
        # Temporarily disable ECN (prevent traffic problems with some old routers)
        [ "$ARCH_LINUX_ECN_ENABLED" = "false" ] && sysctl net.ipv4.tcp_ecn=0
        pacman -Sy --noconfirm archlinux-keyring # Update keyring
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_capture $! "$process_name"
}

# ---------------------------------------------------------------------------------------------------

exec_prepare_disk() {
    local process_name="Prepare Disk"
    process_init "$process_name"
    (
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

        # Wipe and create partitions
        wipefs -af "$ARCH_LINUX_DISK"                                        # Remove All Filesystem Signatures
        sgdisk --zap-all "$ARCH_LINUX_DISK"                                  # Remove the Partition Table
        sgdisk -o "$ARCH_LINUX_DISK"                                         # Create new GPT partition table
        sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot --align-end "$ARCH_LINUX_DISK" # Create partition /boot efi partition: 1 GiB
        sgdisk -n 2:0:0 -t 2:8300 -c 2:root --align-end "$ARCH_LINUX_DISK"   # Create partition / partition: Rest of space
        partprobe "$ARCH_LINUX_DISK"                                         # Reload partition table

        # Disk encryption
        if [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ]; then
            log_info "Enable Disk Encryption for ${ARCH_LINUX_ROOT_PARTITION}"
            echo -n "$ARCH_LINUX_PASSWORD" | cryptsetup luksFormat "$ARCH_LINUX_ROOT_PARTITION"
            echo -n "$ARCH_LINUX_PASSWORD" | cryptsetup open "$ARCH_LINUX_ROOT_PARTITION" cryptroot
        fi

        # Format /boot partition
        mkfs.fat -F 32 -n BOOT "$ARCH_LINUX_BOOT_PARTITION"

        # EXT4
        if [ "$ARCH_LINUX_FILESYSTEM" = "ext4" ]; then
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && mkfs.ext4 -F -L ROOT /dev/mapper/cryptroot
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && mkfs.ext4 -F -L ROOT "$ARCH_LINUX_ROOT_PARTITION"

            # Mount disk to /mnt
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && mount -v /dev/mapper/cryptroot /mnt
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && mount -v "$ARCH_LINUX_ROOT_PARTITION" /mnt

            # Mount /boot
            #mount -v --mkdir LABEL=BOOT /mnt/boot
            mount -v --mkdir "$ARCH_LINUX_BOOT_PARTITION" /mnt/boot
        fi

        # BTRFS
        if [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ]; then
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && mkfs.btrfs -f -L BTRFS /dev/mapper/cryptroot
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && mkfs.btrfs -f -L BTRFS "$ARCH_LINUX_ROOT_PARTITION"

            # Mount disk to /mnt
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && mount -v /dev/mapper/cryptroot /mnt
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && mount -v "$ARCH_LINUX_ROOT_PARTITION" /mnt

            # Create subvolumes
            btrfs subvolume create /mnt/@
            btrfs subvolume create /mnt/@home
            btrfs subvolume create /mnt/@snapshots
            #local btrfs_root_id
            #btrfs_root_id="$(btrfs subvolume list /mnt | awk '$NF == "@" {print $2}')"
            #btrfs subvolume set-default "${btrfs_root_id}" /mnt # Set @ as default
            umount -R /mnt

            # Mount subvolumes
            local mount_target
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && mount_target="$ARCH_LINUX_ROOT_PARTITION"
            [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && mount_target="/dev/mapper/cryptroot"

            local mount_opts="defaults,noatime,compress=zstd"
            mount --mkdir -t btrfs -o ${mount_opts},subvol=@ "${mount_target}" /mnt
            mount --mkdir -t btrfs -o ${mount_opts},subvol=@home "${mount_target}" /mnt/home
            mount --mkdir -t btrfs -o ${mount_opts},subvol=@snapshots "${mount_target}" /mnt/.snapshots

            # Mount /boot
            #mount -v --mkdir LABEL=BOOT /mnt/boot
            mount -v --mkdir "$ARCH_LINUX_BOOT_PARTITION" /mnt/boot

            # Create dirs instead of subvolumes by systemd
            mkdir -p /mnt/var/lib/portables
            mkdir -p /mnt/var/lib/machines
        fi

        # Return
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_capture $! "$process_name"
}

# ---------------------------------------------------------------------------------------------------

exec_pacstrap_core() {
    local process_name="Pacstrap Arch Linux Core"
    process_init "$process_name"
    (
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

        # Core packages
        local packages=("$ARCH_LINUX_KERNEL" base base-devel linux-firmware zram-generator networkmanager)

        # Add microcode package
        [ -n "$ARCH_LINUX_MICROCODE" ] && [ "$ARCH_LINUX_MICROCODE" != "none" ] && packages+=("$ARCH_LINUX_MICROCODE")

        # Add filesystem packages
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && packages+=(btrfs-progs efibootmgr inotify-tools)

        # Add grub packages
        [ "$ARCH_LINUX_BOOTLOADER" = "grub" ] && packages+=(grub grub-btrfs)

        # Add snapper packages
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_SNAPPER_ENABLED" = "true" ] && packages+=(snapper)

        # Install core packages and initialize an empty pacman keyring in the target
        pacstrap -K /mnt "${packages[@]}"

        # Generate /etc/fstab
        genfstab -U /mnt >>/mnt/etc/fstab

        # Set timezone & system clock
        arch-chroot /mnt ln -sf "/usr/share/zoneinfo/${ARCH_LINUX_TIMEZONE}" /etc/localtime
        arch-chroot /mnt hwclock --systohc # Set hardware clock from system clock

        { # Create swap (zram-generator with zstd compression)
            # https://wiki.archlinux.org/title/Zram#Using_zram-generator
            echo '[zram0]'
            echo 'zram-size = min(ram / 2, 8192)'
            echo 'compression-algorithm = zstd'
        } >/mnt/etc/systemd/zram-generator.conf

        { # Optimize swap on zram (https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram)
            echo 'vm.swappiness = 180'
            echo 'vm.watermark_boost_factor = 0'
            echo 'vm.watermark_scale_factor = 125'
            echo 'vm.page-cluster = 0'
        } >/mnt/etc/sysctl.d/99-vm-zram-parameters.conf

        # Set console keymap in /etc/vconsole.conf
        echo "KEYMAP=$ARCH_LINUX_VCONSOLE_KEYMAP" >/mnt/etc/vconsole.conf
        [ -n "$ARCH_LINUX_VCONSOLE_FONT" ] && echo "FONT=$ARCH_LINUX_VCONSOLE_FONT" >>/mnt/etc/vconsole.conf

        # Set & Generate Locale
        echo "LANG=${ARCH_LINUX_LOCALE_LANG}.UTF-8" >/mnt/etc/locale.conf
        for ((i = 0; i < ${#ARCH_LINUX_LOCALE_GEN_LIST[@]}; i++)); do sed -i "s/^#${ARCH_LINUX_LOCALE_GEN_LIST[$i]}/${ARCH_LINUX_LOCALE_GEN_LIST[$i]}/g" "/mnt/etc/locale.gen"; done
        arch-chroot /mnt locale-gen

        # Set hostname & hosts
        echo "$ARCH_LINUX_HOSTNAME" >/mnt/etc/hostname
        {
            echo '# <ip>     <hostname.domain.org>  <hostname>'
            echo '127.0.0.1  localhost.localdomain  localhost'
            echo '::1        localhost.localdomain  localhost'
        } >/mnt/etc/hosts

        # Create initial ramdisk from /etc/mkinitcpio.conf
        # https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks
        # https://wiki.archlinux.org/title/Microcode#mkinitcpio
        local btrfs_hook
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_BOOTLOADER" = "grub" ] && btrfs_hook=' grub-btrfs-overlayfs'
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect microcode modconf sd-vconsole block sd-encrypt filesystems fsck${btrfs_hook})/" /mnt/etc/mkinitcpio.conf
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect microcode modconf sd-vconsole block filesystems fsck${btrfs_hook})/" /mnt/etc/mkinitcpio.conf
        arch-chroot /mnt mkinitcpio -P

        # KERNEL PARAMETER
        # Zswap should be disabled when using zram (https://github.com/archlinux/archinstall/issues/881)
        # Silent boot: https://wiki.archlinux.org/title/Silent_boot
        local kernel_args=('rw' 'init=/usr/lib/systemd/systemd' 'zswap.enabled=0')
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "true" ] && kernel_args+=("rd.luks.name=$(blkid -s UUID -o value "${ARCH_LINUX_ROOT_PARTITION}")=cryptroot" "root=/dev/mapper/cryptroot")
        [ "$ARCH_LINUX_ENCRYPTION_ENABLED" = "false" ] && kernel_args+=("root=PARTUUID=$(lsblk -dno PARTUUID "${ARCH_LINUX_ROOT_PARTITION}")")
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && kernel_args+=('rootflags=subvol=@' 'rootfstype=btrfs')
        [ "$ARCH_LINUX_CORE_TWEAKS_ENABLED" = "true" ] && kernel_args+=('nowatchdog')
        [ "$ARCH_LINUX_BOOTSPLASH_ENABLED" = "true" ] || [ "$ARCH_LINUX_CORE_TWEAKS_ENABLED" = "true" ] && kernel_args+=('quiet' 'splash' 'vt.global_cursor_default=0' 'loglevel=3' 'rd.udev.log_level=3' 'systemd.show_status=auto')

        # SYSTEMD-BOOT INSTALLATION
        if [ "$ARCH_LINUX_BOOTLOADER" = "systemd" ]; then

            # Install Bootloader to /boot (systemdboot)
            arch-chroot /mnt bootctl --esp-path=/boot install

            { # Create Bootloader config
                echo 'default main.conf'
                echo 'console-mode auto'
                echo 'timeout 0'
                echo 'editor yes'
            } >/mnt/boot/loader/loader.conf

            { # Create default boot entry
                echo 'title   Arch Linux'
                echo "linux   /vmlinuz-${ARCH_LINUX_KERNEL}"
                echo "initrd  /initramfs-${ARCH_LINUX_KERNEL}.img"
                echo "options ${kernel_args[*]}"
            } >/mnt/boot/loader/entries/main.conf

            { # Create fallback boot entry
                echo 'title   Arch Linux (Fallback)'
                echo "linux   /vmlinuz-${ARCH_LINUX_KERNEL}"
                echo "initrd  /initramfs-${ARCH_LINUX_KERNEL}-fallback.img"
                echo "options ${kernel_args[*]}"
            } >/mnt/boot/loader/entries/main-fallback.conf

            # Enable service: Auto bootloader update
            arch-chroot /mnt systemctl enable systemd-boot-update.service
        fi

        # ------------------------------------------------------------------

        # GRUB INSTALLATION
        if [ "$ARCH_LINUX_BOOTLOADER" = "grub" ]; then

            # Add kernel args to /etc/default/grub
            sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&${kernel_args[*]}," /mnt/etc/default/grub

            # Installing GRUB
            arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

            # Creating grub config file
            sed -i "s/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=3/" /mnt/etc/default/grub
            sed -i "s/^GRUB_TIMEOUT_STYLE=.*$/GRUB_TIMEOUT_STYLE=menu/" /mnt/etc/default/grub
            arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

            # Enable btrfs update service
            [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && arch-chroot /mnt systemctl enable grub-btrfsd.service
        fi

        # Create new user
        arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$ARCH_LINUX_USERNAME"

        # Create user dirs
        mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.config"
        mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.local/share"
        arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}"

        # Allow users in group wheel to use sudo
        sed -i 's^# %wheel ALL=(ALL:ALL) ALL^%wheel ALL=(ALL:ALL) ALL^g' /mnt/etc/sudoers

        # Change passwords
        printf "%s\n%s" "${ARCH_LINUX_PASSWORD}" "${ARCH_LINUX_PASSWORD}" | arch-chroot /mnt passwd
        printf "%s\n%s" "${ARCH_LINUX_PASSWORD}" "${ARCH_LINUX_PASSWORD}" | arch-chroot /mnt passwd "$ARCH_LINUX_USERNAME"

        # Enable services
        arch-chroot /mnt systemctl enable NetworkManager                   # Network Manager
        arch-chroot /mnt systemctl enable fstrim.timer                     # SSD support
        arch-chroot /mnt systemctl enable systemd-zram-setup@zram0.service # Swap (zram-generator)
        arch-chroot /mnt systemctl enable systemd-oomd.service             # Out of memory killer (swap is required)
        arch-chroot /mnt systemctl enable systemd-timesyncd.service        # Sync time from internet after boot

        if [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ]; then
            # Btrfs scrub timer
            arch-chroot /mnt systemctl enable btrfs-scrub@-.timer
            arch-chroot /mnt systemctl enable btrfs-scrub@home.timer
            arch-chroot /mnt systemctl enable btrfs-scrub@snapshots.timer
        fi

        if [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_SNAPPER_ENABLED" = "true" ]; then

            # Create snapper config
            arch-chroot /mnt umount /.snapshots
            arch-chroot /mnt rm -r /.snapshots
            arch-chroot /mnt snapper --no-dbus -c root create-config /
            arch-chroot /mnt btrfs subvolume delete /.snapshots
            arch-chroot /mnt mkdir /.snapshots
            arch-chroot /mnt mount -a
            arch-chroot /mnt chmod 750 /.snapshots
            arch-chroot /mnt sudo chown :wheel /.snapshots

            # Modify snapper config
            # https://www.dwarmstrong.org/btrfs-snapshots-rollbacks/
            # /etc/snapper/configs/root

            # Enable snapper services
            arch-chroot /mnt systemctl enable snapper-timeline.timer
            arch-chroot /mnt systemctl enable snapper-cleanup.timer
            arch-chroot /mnt systemctl enable snapper-boot.timer
        fi

        # Make some Arch Linux tweaks
        if [ "$ARCH_LINUX_CORE_TWEAKS_ENABLED" = "true" ]; then

            # Add password feedback
            echo -e "\n## Enable sudo password feedback\nDefaults pwfeedback" >>/mnt/etc/sudoers

            # Configure pacman parrallel downloads, colors, eyecandy
            sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf
            sed -i 's/^#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf

            # Disable watchdog modules
            mkdir -p /mnt/etc/modprobe.d/
            echo 'blacklist sp5100_tco' >>/mnt/etc/modprobe.d/blacklist-watchdog.conf
            echo 'blacklist iTCO_wdt' >>/mnt/etc/modprobe.d/blacklist-watchdog.conf

            # Disable debug packages when using makepkg
            sed -i '/OPTIONS=.*!debug/!s/\(OPTIONS=.*\)debug/\1!debug/' /mnt/etc/makepkg.conf

            # Set max VMAs (need for some apps/games)
            #echo vm.max_map_count=1048576 >/mnt/etc/sysctl.d/vm.max_map_count.conf

            # Reduce shutdown timeout
            #sed -i "s/^\s*#\s*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=10s/" /mnt/etc/systemd/system.conf
        fi

        # Return
        process_return 0
    ) &>"$PROCESS_LOG" &
    process_capture $! "$process_name"
}

# ---------------------------------------------------------------------------------------------------

exec_install_desktop() {
    local process_name="GNOME Desktop"
    if [ "$ARCH_LINUX_DESKTOP_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

            local packages=()

            # GNOME base packages
            packages+=(gnome git)

            # GNOME desktop extras
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then

                # GNOME base extras (buggy: power-profiles-daemon)
                packages+=(gnome-browser-connector gnome-themes-extra tuned-ppd rygel cups gnome-epub-thumbnailer)

                # GNOME wayland screensharing, flatpak & pipewire support
                packages+=(xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome flatpak-xdg-utils)

                # Audio (Pipewire replacements + session manager): https://wiki.archlinux.org/title/PipeWire#Installation
                packages+=(pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-pipewire lib32-pipewire-jack)

                # Disabled because hardware-specific
                #packages+=(sof-firmware) # Need for intel i5 audio

                # Networking & Access
                packages+=(samba rsync gvfs gvfs-mtp gvfs-smb gvfs-nfs gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-google gvfs-dnssd gvfs-wsdd)
                packages+=(modemmanager network-manager-sstp networkmanager-l2tp networkmanager-vpnc networkmanager-pptp networkmanager-openvpn networkmanager-openconnect networkmanager-strongswan)

                # Kernel headers
                packages+=("${ARCH_LINUX_KERNEL}-headers")

                # Utils (https://wiki.archlinux.org/title/File_systems)
                packages+=(base-devel archlinux-contrib pacutils fwupd bash-completion dhcp net-tools inetutils nfs-utils e2fsprogs f2fs-tools udftools dosfstools ntfs-3g exfat-utils btrfs-progs xfsprogs p7zip zip unzip unrar tar wget curl)
                packages+=(nautilus-image-converter)

                # Runtimes, Builder & Helper
                packages+=(gdb python go rust nodejs npm lua cmake jq zenity gum fzf)

                # Certificates
                packages+=(ca-certificates)

                # Codecs (https://wiki.archlinux.org/title/Codecs_and_containers)
                packages+=(ffmpeg ffmpegthumbnailer gstreamer gst-libav gst-plugin-pipewire gst-plugins-good gst-plugins-bad gst-plugins-ugly libdvdcss libheif webp-pixbuf-loader opus speex libvpx libwebp)
                packages+=(a52dec faac faad2 flac jasper lame libdca libdv libmad libmpeg2 libtheora libvorbis libxv wavpack x264 xvidcore libdvdnav libdvdread openh264)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gstreamer lib32-gst-plugins-good lib32-libvpx lib32-libwebp)

                # Optimization
                packages+=(gamemode sdl_image)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gamemode lib32-sdl_image)

                # Fonts
                packages+=(ttf-firacode-nerd ttf-nerd-fonts-symbols ttf-font-awesome noto-fonts noto-fonts-emoji ttf-liberation ttf-dejavu adobe-source-sans-fonts adobe-source-serif-fonts)

            fi

            # Installing packages together (preventing conflicts e.g.: jack2 and piepwire-jack)
            chroot_pacman_install "${packages[@]}"

            # Force remove gnome packages
            if [ "$ARCH_LINUX_DESKTOP_SLIM_ENABLED" = "true" ]; then
                chroot_pacman_remove gnome-calendar || true
                chroot_pacman_remove gnome-maps || true
                chroot_pacman_remove gnome-contacts || true
                chroot_pacman_remove gnome-font-viewer || true
                chroot_pacman_remove gnome-characters || true
                chroot_pacman_remove gnome-clocks || true
                chroot_pacman_remove gnome-connections || true
                chroot_pacman_remove gnome-music || true
                chroot_pacman_remove gnome-weather || true
                chroot_pacman_remove gnome-calculator || true
                chroot_pacman_remove gnome-logs || true
                chroot_pacman_remove gnome-text-editor || true
                chroot_pacman_remove gnome-disk-utility || true
                chroot_pacman_remove simple-scan || true
                chroot_pacman_remove baobab || true
                chroot_pacman_remove totem || true
                chroot_pacman_remove snapshot || true
                chroot_pacman_remove epiphany || true
                chroot_pacman_remove loupe || true
                chroot_pacman_remove decibels || true
                #chroot_pacman_remove evince || true # Need for sushi
            fi

            # Add user to other useful groups (https://wiki.archlinux.org/title/Users_and_groups#User_groups)
            arch-chroot /mnt groupadd -f plugdev
            arch-chroot /mnt usermod -aG adm,audio,video,optical,input,tty,plugdev "$ARCH_LINUX_USERNAME"

            # Add user to gamemode group
            [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ] && arch-chroot /mnt gpasswd -a "$ARCH_LINUX_USERNAME" gamemode

            # Enable GNOME auto login
            mkdir -p /mnt/etc/gdm
            # grep -qrnw /mnt/etc/gdm/custom.conf -e "AutomaticLoginEnable" || sed -i "s/^\[security\]/AutomaticLoginEnable=True\nAutomaticLogin=${ARCH_LINUX_USERNAME}\n\n\[security\]/g" /mnt/etc/gdm/custom.conf
            {
                echo "[daemon]"
                echo "WaylandEnable=True"
                echo ""
                echo "AutomaticLoginEnable=True"
                echo "AutomaticLogin=${ARCH_LINUX_USERNAME}"
                echo ""
                echo "[debug]"
                echo "Enable=False"
            } >/mnt/etc/gdm/custom.conf

            # Set git-credential-libsecret in ~/.gitconfig
            arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- git config --global credential.helper /usr/lib/git-core/git-credential-libsecret

            # GnuPG integration (https://wiki.archlinux.org/title/GNOME/Keyring#GnuPG_integration)
            mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.gnupg"
            echo 'pinentry-program /usr/bin/pinentry-gnome3' >"/mnt/home/${ARCH_LINUX_USERNAME}/.gnupg/gpg-agent.conf"

            # Set environment
            mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.config/environment.d/"
            # shellcheck disable=SC2016
            {
                echo '# SSH AGENT'
                echo 'SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gcr/ssh' # Set gcr sock (https://wiki.archlinux.org/title/GNOME/Keyring#Setup_gcr)
                echo ''
                echo '# PATH'
                echo 'PATH="${PATH}:${HOME}/.local/bin"'
                echo ''
                echo '# XDG'
                echo 'XDG_CONFIG_HOME="${HOME}/.config"'
                echo 'XDG_DATA_HOME="${HOME}/.local/share"'
                echo 'XDG_STATE_HOME="${HOME}/.local/state"'
                echo 'XDG_CACHE_HOME="${HOME}/.cache"                '
            } >"/mnt/home/${ARCH_LINUX_USERNAME}/.config/environment.d/00-arch.conf"

            # shellcheck disable=SC2016
            {
                echo '# Workaround for Flatpak aliases'
                echo 'PATH="${PATH}:/var/lib/flatpak/exports/bin"'
            } >"/mnt/home/${ARCH_LINUX_USERNAME}/.config/environment.d/99-flatpak.conf"

            # Samba
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then

                # Create samba config
                mkdir -p "/mnt/etc/samba/"
                {
                    echo '[global]'
                    echo '   workgroup = WORKGROUP'
                    echo '   server string = Samba Server'
                    echo '   server role = standalone server'
                    echo '   security = user'
                    echo '   map to guest = Bad User'
                    echo '   log file = /var/log/samba/%m.log'
                    echo '   max log size = 50'
                    echo '   client min protocol = SMB2'
                    echo '   server min protocol = SMB2'
                    if [ "$ARCH_LINUX_SAMBA_SHARE_ENABLED" = "true" ]; then
                        echo
                        echo '[homes]'
                        echo '   comment = Home Directory'
                        echo '   browseable = yes'
                        echo '   read only = no'
                        echo '   create mask = 0700'
                        echo '   directory mask = 0700'
                        echo '   valid users = %S'
                        echo
                        echo '[public]'
                        echo '   comment = Public Share'
                        echo '   path = /srv/samba/public'
                        echo '   browseable = yes'
                        echo '   guest ok = yes'
                        echo '   read only = no'
                        echo '   writable = yes'
                        echo '   create mask = 0777'
                        echo '   directory mask = 0777'
                        echo '   force user = nobody'
                        echo '   force group = users'
                    fi
                } >/mnt/etc/samba/smb.conf

                # Test samba config
                arch-chroot /mnt testparm -s /etc/samba/smb.conf

                if [ "$ARCH_LINUX_SAMBA_SHARE_ENABLED" = "true" ]; then

                    # Create samba public dir
                    arch-chroot /mnt mkdir -p /srv/samba/public
                    arch-chroot /mnt chmod 777 /srv/samba/public
                    arch-chroot /mnt chown -R nobody:users /srv/samba/public

                    # Add user as samba user with same password (different user db)
                    (
                        echo "$ARCH_LINUX_PASSWORD"
                        echo "$ARCH_LINUX_PASSWORD"
                    ) | arch-chroot /mnt smbpasswd -s -a "$ARCH_LINUX_USERNAME"
                fi

                # Start samba services
                arch-chroot /mnt systemctl enable smb.service

                # https://wiki.archlinux.org/title/Samba#Windows_1709_or_up_does_not_discover_the_samba_server_in_Network_view
                arch-chroot /mnt systemctl enable wsdd.service

                # Disabled (master browser issues) > may needed for old windows clients
                #arch-chroot /mnt systemctl enable nmb.service
            fi

            # Set X11 keyboard layout in /etc/X11/xorg.conf.d/00-keyboard.conf
            mkdir -p /mnt/etc/X11/xorg.conf.d/
            {
                echo 'Section "InputClass"'
                echo '    Identifier "system-keyboard"'
                echo '    MatchIsKeyboard "yes"'
                echo '    Option "XkbLayout" "'"${ARCH_LINUX_DESKTOP_KEYBOARD_LAYOUT}"'"'
                echo '    Option "XkbModel" "'"${ARCH_LINUX_DESKTOP_KEYBOARD_MODEL}"'"'
                echo '    Option "XkbVariant" "'"${ARCH_LINUX_DESKTOP_KEYBOARD_VARIANT}"'"'
                echo 'EndSection'
            } >/mnt/etc/X11/xorg.conf.d/00-keyboard.conf

            # Enable Arch Linux Desktop services
            arch-chroot /mnt systemctl enable gdm.service       # GNOME
            arch-chroot /mnt systemctl enable bluetooth.service # Bluetooth
            arch-chroot /mnt systemctl enable avahi-daemon      # Network browsing service
            arch-chroot /mnt systemctl enable gpm.service       # TTY Mouse Support

            # Extra services
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
                arch-chroot /mnt systemctl enable tuned       # Power daemon
                arch-chroot /mnt systemctl enable tuned-ppd   # Power daemon
                arch-chroot /mnt systemctl enable cups.socket # Printer
            fi

            # User services (Not working: Failed to connect to user scope bus via local transport: Permission denied)
            # arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- systemctl enable --user pipewire.service       # Pipewire
            # arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- systemctl enable --user pipewire-pulse.service # Pipewire
            # arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- systemctl enable --user wireplumber.service    # Pipewire
            # arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- systemctl enable --user gcr-ssh-agent.socket   # GCR ssh-agent

            # Workaround: Manual creation of user service symlinks
            arch-chroot /mnt mkdir -p "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/default.target.wants"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/pipewire.service" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/default.target.wants/pipewire.service"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/pipewire-pulse.service" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/default.target.wants/pipewire-pulse.service"
            arch-chroot /mnt mkdir -p "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/sockets.target.wants"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/pipewire.socket" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/sockets.target.wants/pipewire.socket"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/pipewire-pulse.socket" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/sockets.target.wants/pipewire-pulse.socket"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/gcr-ssh-agent.socket" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/sockets.target.wants/gcr-ssh-agent.socket"
            arch-chroot /mnt mkdir -p "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/pipewire.service.wants"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/wireplumber.service" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/pipewire-session-manager.service"
            arch-chroot /mnt ln -s "/usr/lib/systemd/user/wireplumber.service" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/user/pipewire.service.wants/wireplumber.service"
            arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}/.config/systemd/"

            # Enhance PAM (fix keyring issue for relogin): add try_first_pass
            sed -i 's/auth\s\+optional\s\+pam_gnome_keyring\.so$/& try_first_pass/' /mnt/etc/pam.d/gdm-password /mnt/etc/pam.d/gdm-autologin

            # Create users applications dir
            mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications"

            # Create UEFI Boot desktop entry
            # {
            #    echo '[Desktop Entry]'
            #    echo 'Name=Reboot to UEFI'
            #    echo 'Icon=system-reboot'
            #    echo 'Exec=systemctl reboot --firmware-setup'
            #    echo 'Type=Application'
            #    echo 'Terminal=false'
            # } >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/systemctl-reboot-firmware.desktop"

            # Hide aplications desktop icons
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/bssh.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/bvnc.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/avahi-discover.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/qv4l2.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/qvidcap.desktop"
            echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/lstopo.desktop"

            # Hide aplications (extra) desktop icons
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/stoken-gui.desktop"       # networkmanager-openconnect
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/stoken-gui-small.desktop" # networkmanager-openconnect
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/cups.desktop"
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/tuned-gui.desktop"
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/cmake-gui.desktop"
            fi

            # Hide Shell Enhancement apps
            if [ "$ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED" = "true" ]; then
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/fish.desktop"
                echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/${ARCH_LINUX_USERNAME}/.local/share/applications/btop.desktop"
            fi

            # Set Flatpak theme access
            arch-chroot /mnt flatpak override --filesystem=xdg-config/gtk-3.0
            arch-chroot /mnt flatpak override --filesystem=xdg-config/gtk-4.0

            # Add Init script
            if [ "$ARCH_LINUX_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
                {
                    echo "# exec_install_desktop | Favorite apps"
                    echo "gsettings set org.gnome.shell favorite-apps \"['org.gnome.Console.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Software.desktop', 'org.gnome.Settings.desktop']\""
                    echo "# exec_install_desktop | Reset app-folders"
                    echo "dconf reset -f /org/gnome/desktop/app-folders/"
                    echo "# exec_install_desktop | Show all input sources"
                    echo "gsettings set org.gnome.desktop.input-sources show-all-sources true"
                    echo "# exec_install_desktop | Mutter settings"
                    echo "gsettings set org.gnome.mutter center-new-windows true"
                    echo "# exec_install_desktop | File chooser settings"
                    echo "gsettings set org.gtk.Settings.FileChooser sort-directories-first true"
                    echo "gsettings set org.gtk.gtk4.Settings.FileChooser sort-directories-first true"
                } >>"/mnt/home/${ARCH_LINUX_USERNAME}/${INIT_FILENAME}.sh"
            fi

            # Set correct permissions
            arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}"

            # Return
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_graphics_driver() {
    local process_name="Desktop Driver"
    if [ -n "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" ] && [ "$ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER" != "none" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            case "${ARCH_LINUX_DESKTOP_GRAPHICS_DRIVER}" in
            "mesa") # https://wiki.archlinux.org/title/OpenGL#Installation
                local packages=(mesa mesa-utils vkd3d vulkan-tools)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-mesa-utils lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                ;;
            "intel_i915") # https://wiki.archlinux.org/title/Intel_graphics#Installation
                local packages=(vulkan-intel vkd3d libva-intel-driver vulkan-tools)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-vulkan-intel lib32-vkd3d lib32-libva-intel-driver)
                chroot_pacman_install "${packages[@]}"
                sed -i "s/^MODULES=(.*)/MODULES=(i915)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            "nvidia") # https://wiki.archlinux.org/title/NVIDIA#Installation
                local packages=("${ARCH_LINUX_KERNEL}-headers" nvidia-dkms nvidia-settings nvidia-utils opencl-nvidia vkd3d vulkan-tools)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-nvidia-utils lib32-opencl-nvidia lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                # https://wiki.archlinux.org/title/NVIDIA#DRM_kernel_mode_setting
                # Alternative (slow boot, bios logo twice, but correct plymouth resolution):
                #sed -i "s/systemd zswap.enabled=0/systemd nvidia_drm.modeset=1 nvidia_drm.fbdev=1 zswap.enabled=0/g" /mnt/boot/loader/entries/main.conf
                mkdir -p /mnt/etc/modprobe.d/ && echo -e 'options nvidia_drm modeset=1 fbdev=1' >/mnt/etc/modprobe.d/nvidia.conf
                sed -i "s/^MODULES=(.*)/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /mnt/etc/mkinitcpio.conf
                # https://wiki.archlinux.org/title/NVIDIA#pacman_hook
                mkdir -p /mnt/etc/pacman.d/hooks/
                {
                    echo "[Trigger]"
                    echo "Operation=Install"
                    echo "Operation=Upgrade"
                    echo "Operation=Remove"
                    echo "Type=Package"
                    echo "Target=nvidia"
                    echo "Target=${ARCH_LINUX_KERNEL}"
                    echo "# Change the linux part above if a different kernel is used"
                    echo ""
                    echo "[Action]"
                    echo "Description=Update NVIDIA module in initcpio"
                    echo "Depends=mkinitcpio"
                    echo "When=PostTransaction"
                    echo "NeedsTargets"
                    echo "Exec=/bin/sh -c 'while read -r trg; do case \$trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'"
                } >/mnt/etc/pacman.d/hooks/nvidia.hook
                # Enable Wayland Support (https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver)
                [ ! -f /mnt/etc/udev/rules.d/61-gdm.rules ] && mkdir -p /mnt/etc/udev/rules.d/ && ln -s /dev/null /mnt/etc/udev/rules.d/61-gdm.rules
                # Rebuild initial ram disk
                arch-chroot /mnt mkinitcpio -P
                ;;
            "amd") # https://wiki.archlinux.org/title/AMDGPU#Installation
                # Deprecated: libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau
                local packages=(mesa mesa-utils xf86-video-amdgpu vulkan-radeon vkd3d vulkan-tools)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-vulkan-radeon lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                # Must be discussed: https://wiki.archlinux.org/title/AMDGPU#Disable_loading_radeon_completely_at_boot
                sed -i "s/^MODULES=(.*)/MODULES=(amdgpu)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            "ati") # https://wiki.archlinux.org/title/ATI#Installation
                # Deprecated: libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau
                local packages=(mesa mesa-utils xf86-video-ati vkd3d vulkan-tools)
                [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-mesa lib32-vkd3d)
                chroot_pacman_install "${packages[@]}"
                sed -i "s/^MODULES=(.*)/MODULES=(radeon)/g" /mnt/etc/mkinitcpio.conf
                arch-chroot /mnt mkinitcpio -P
                ;;
            esac
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_enable_multilib() {
    local process_name="Enable Multilib"
    if [ "$ARCH_LINUX_MULTILIB_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
            arch-chroot /mnt pacman -Syyu --noconfirm
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_bootsplash() {
    local process_name="Bootsplash"
    if [ "$ARCH_LINUX_BOOTSPLASH_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0                                       # If debug mode then return
            chroot_pacman_install plymouth git base-devel                                              # Install packages
            sed -i "s/base systemd keyboard/base systemd plymouth keyboard/g" /mnt/etc/mkinitcpio.conf # Configure mkinitcpio                                                # Install Arch Linux plymouth theme from AUR
            arch-chroot /mnt plymouth-set-default-theme -R bgrt                                     # Set Theme & rebuild initram disk
            process_return 0                                                                           # Return
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_aur_helper() {
    local process_name="AUR Helper"
    if [ -n "$ARCH_LINUX_AUR_HELPER" ] && [ "$ARCH_LINUX_AUR_HELPER" != "none" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            chroot_pacman_install git base-devel                 # Install packages
            chroot_aur_install "$ARCH_LINUX_AUR_HELPER"             # Install AUR helper
            # Paru config
            if [ "$ARCH_LINUX_AUR_HELPER" = "paru" ] || [ "$ARCH_LINUX_AUR_HELPER" = "paru-bin" ] || [ "$ARCH_LINUX_AUR_HELPER" = "paru-git" ]; then
                sed -i 's/^#BottomUp/BottomUp/g' /mnt/etc/paru.conf
                sed -i 's/^#SudoLoop/SudoLoop/g' /mnt/etc/paru.conf
            fi
            process_return 0 # Return
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_housekeeping() {
    local process_name="Housekeeping"
    if [ "$ARCH_LINUX_HOUSEKEEPING_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0                            # If debug mode then return
            chroot_pacman_install pacman-contrib reflector pkgfile smartmontools irqbalance # Install Base packages
            {                                                                               # Configure reflector service
                echo "# Reflector config for the systemd service"
                echo "--save /etc/pacman.d/mirrorlist"
                [ -n "$ARCH_LINUX_REFLECTOR_COUNTRY" ] && echo "--country ${ARCH_LINUX_REFLECTOR_COUNTRY}"
                #echo "--completion-percent 95"
                echo "--protocol https"
                echo "--age 12"
                echo "--latest 10"
                echo "--sort rate"
            } >/mnt/etc/xdg/reflector/reflector.conf
            # Enable services
            arch-chroot /mnt systemctl enable reflector.service    # Rank mirrors after boot (reflector)
            arch-chroot /mnt systemctl enable paccache.timer       # Discard cached/unused packages weekly (pacman-contrib)
            arch-chroot /mnt systemctl enable pkgfile-update.timer # Pkgfile update timer (pkgfile)
            arch-chroot /mnt systemctl enable smartd               # SMART check service (smartmontools)
            arch-chroot /mnt systemctl enable irqbalance.service   # IRQ balancing daemon (irqbalance)
            process_return 0                                       # Return
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_shell_enhancement() {
    local process_name="Shell Enhancement"
    if [ "$ARCH_LINUX_SHELL_ENHANCEMENT_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

            # Install packages
            local packages=(git starship eza bat zoxide fd fzf fastfetch mc btop nano man-db bash-completion nano-syntax-highlighting ttf-firacode-nerd ttf-nerd-fonts-symbols)
            chroot_pacman_install "${packages[@]}"

            # Install & set fish for root & user
            if [ "$ARCH_LINUX_SHELL_ENHANCEMENT_FISH_ENABLED" = "true" ]; then
                chroot_pacman_install fish
                mkdir -p "/mnt/root/.config/fish" "/mnt/home/${ARCH_LINUX_USERNAME}/.config/fish" # Create fish config dirs
                # shellcheck disable=SC2016
                { # Create fish config for root & user
                    echo 'if status is-interactive'
                    echo '    # Commands to run in interactive sessions can go here'
                    echo 'end'
                    echo ''
                    echo '# Disable welcome message'
                    echo 'set fish_greeting'
                    echo ''
                    echo '# Colorize man pages (bat)'
                    echo 'command -v bat &>/dev/null && export MANPAGER="sh -c \"col -bx | bat -l man -p\""'
                    echo 'command -v bat &>/dev/null && export MANROFFOPT="-c"'
                    echo ''
                    echo '# Source user aliases'
                    echo 'test -f "$HOME/.aliases" && source "$HOME/.aliases"'
                    echo ''
                    echo '# Init zoxide'
                    echo 'command -v zoxide &>/dev/null && zoxide init fish | source'
                    echo ''
                    echo '# Init starship promt (except tty)'
                    echo 'if not tty | string match -q "/dev/tty*"'
                    echo '    and command -v starship >/dev/null'
                    echo '    starship init fish | source'
                    echo 'end'
                } | tee "/mnt/root/.config/fish/config.fish" "/mnt/home/${ARCH_LINUX_USERNAME}/.config/fish/config.fish" >/dev/null
                #arch-chroot /mnt chsh -s /usr/bin/fish
                #arch-chroot /mnt chsh -s /usr/bin/fish "$ARCH_LINUX_USERNAME"
            fi

            { # Create aliases for root & user
                echo '# ls / eza'
                echo 'alias ls="ls -h --color=always --group-directories-first"'
                echo 'command -v eza &>/dev/null && alias ls="eza -h --color=always --group-directories-first"'
                echo 'alias ll="ls -l"'
                echo 'alias la="ls -la"'
                echo 'alias lt="ls -Tal"'
                echo -e '\n# Colorize'
                echo 'alias diff="diff --color=auto"'
                echo 'alias grep="grep --color=auto"'
                echo 'alias ip="ip -color=auto"'
                echo -e '\n# Wrapper'
                echo 'alias logs="systemctl --failed; echo; journalctl -p 3 -b"'
                echo 'alias q="exit"'
                echo 'alias c="clear"'
                echo 'command -v meld &>/dev/null && alias pacnew="sudo DIFFPROG=meld pacdiff"'
                echo 'command -v xdg-open &>/dev/null && alias open="xdg-open"'
                echo 'alias myip="curl ipv4.icanhazip.com"'
                echo -e '\n# Change dir'
                echo 'alias .="cd .."'
                echo 'alias ..="cd ../.."'
                echo 'alias ...="cd ../../.."'
                echo -e '\n# Packages'
                local pkg_manager='pacman' && [ -n "$ARCH_LINUX_AUR_HELPER" ] && [ "$ARCH_LINUX_AUR_HELPER" != "none" ] && pkg_manager="$ARCH_LINUX_AUR_HELPER"
                if [ "$pkg_manager" = "pacman" ]; then
                    echo "alias paci='sudo ${pkg_manager} -S' # Install package"
                    echo "alias pacu='sudo ${pkg_manager} -Syu' # System upgrade"
                else
                    echo "alias paci='${pkg_manager} -S' # Install package"
                    echo "alias pacu='${pkg_manager} -Syu' # System upgrade"
                fi
                echo "alias pacs='${pkg_manager} -Ss' # Search package in database"
                echo "alias pacr='${pkg_manager} -Rns' # Remove package"
                echo "alias pacrc='${pkg_manager} -Scc' # Clear Cache"
                echo "alias pacl='${pkg_manager} -Qe' # List all installed packages"
                echo "alias pacla='${pkg_manager} -Qm' # List installed AUR packages"
                echo "alias pacls='${pkg_manager} -Qs' # Search installed packages"
                echo "alias pacli='${pkg_manager} -Qi' # Show package info"
            } | tee "/mnt/root/.aliases" "/mnt/home/${ARCH_LINUX_USERNAME}/.aliases" >/dev/null

            # shellcheck disable=SC2016
            { # Create bash config for root & user
                echo '# If not running interactively, do not do anything'
                echo '[[ $- != *i* ]] && return'
                echo ''
                echo ' # Export systemd environment vars from ~/.config/environment.d/* (tty only)'
                echo '[[ ${SHLVL} == 1 ]] && [ -z "${DISPLAY}" ] && export $(/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator | xargs)'
                echo ''
                echo '# Source aliases'
                echo 'source "${HOME}/.aliases"'
                echo ''
                echo '# Plugin: pkgfile (command not found)'
                echo '[ -f /usr/share/doc/pkgfile/command-not-found.bash ] && source /usr/share/doc/pkgfile/command-not-found.bash'
                echo ''
                echo '# Options'
                echo 'shopt -s autocd                  # Auto cd'
                echo 'shopt -s cdspell                 # Correct cd typos'
                echo 'shopt -s checkwinsize            # Update windows size on command'
                echo 'shopt -s histappend              # Append History instead of overwriting file'
                echo 'shopt -s cmdhist                 # Bash attempts to save all lines of a multiple-line command in the same history entry'
                echo 'shopt -s extglob                 # Extended pattern'
                echo 'shopt -s no_empty_cmd_completion # No empty completion'
                echo 'shopt -s expand_aliases          # Expand aliases'
                echo ''
                echo '# Ignore upper and lowercase when TAB completion'
                echo 'bind "set completion-ignore-case on"'
                echo ''
                echo '# Colorize man pages (bat)'
                echo 'command -v bat &>/dev/null && export MANPAGER="sh -c \"col -bx | bat -l man -p\""'
                echo 'command -v bat &>/dev/null && export MANROFFOPT="-c"'
                echo ''
                echo '# History'
                echo 'export HISTSIZE=1000                    # History will save N commands'
                echo 'export HISTFILESIZE=${HISTSIZE}         # History will remember N commands'
                echo 'export HISTCONTROL=ignoredups:erasedups # Ingore duplicates and spaces (ignoreboth)'
                echo 'export HISTTIMEFORMAT="%F %T "          # Add date to history'
                echo ''
                echo '# History ignore list'
                echo 'export HISTIGNORE="&:ls:ll:la:cd:exit:clear:history:q:c"'
                echo ''
                echo '# Start fish shell - no tty (https://wiki.archlinux.org/title/Fish#Modify_.bashrc_to_drop_into_fish)'
                echo 'if [[ ! $(tty) =~ /dev/tty[0-9]* ]] && command -v fish &>/dev/null && [[ $(ps --no-header --pid=$PPID --format=comm) != "fish" && -z ${BASH_EXECUTION_STRING} && ${SHLVL} == 1 ]]; then'
                echo '    shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""'
                echo '    exec fish $LOGIN_OPTION'
                echo '    return'
                echo 'fi'
                echo ''
                echo '# Init starship (no tty)'
                echo '[[ ! $(tty) =~ /dev/tty[0-9]* ]] && command -v starship &>/dev/null && eval "$(starship init bash)"'
                echo ''
                echo '# Init zoxide'
                echo 'command -v zoxide &>/dev/null && eval "$(zoxide init bash)"'
            } | tee "/mnt/root/.bashrc" "/mnt/home/${ARCH_LINUX_USERNAME}/.bashrc" >/dev/null

            # Download Arch Linux starship theme
            mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.config/"
            curl -Lf https://raw.githubusercontent.com/snaplyze/arch-linux-gnome/refs/heads/main/starship.toml >"/mnt/home/${ARCH_LINUX_USERNAME}/.config/starship.toml"
            if [ ! -s "/mnt/home/${ARCH_LINUX_USERNAME}/.config/starship.toml" ]; then
                # Theme fallback
                arch-chroot /mnt /usr/bin/starship preset pure-preset -o "/home/${ARCH_LINUX_USERNAME}/.config/starship.toml"
            fi
            cp "/mnt/home/${ARCH_LINUX_USERNAME}/.config/starship.toml" "/mnt/root/.config/starship.toml"
            arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}/.config/"
            
            { # Set nano environment
                echo 'EDITOR=nano'
                echo 'VISUAL=nano'
            } >/mnt/etc/environment

            # Set Nano colors
            sed -i "s/^# set linenumbers/set linenumbers/" /mnt/etc/nanorc
            sed -i "s/^# set minibar/set minibar/" /mnt/etc/nanorc
            sed -i 's;^# include /usr/share/nano/\*\.nanorc;include /usr/share/nano/*.nanorc\ninclude /usr/share/nano/extra/*.nanorc\ninclude /usr/share/nano-syntax-highlighting/*.nanorc;g' /mnt/etc/nanorc

            { # Add init script
                echo "# exec_install_shell_enhancement | Set default monospace font"
                echo "gsettings set org.gnome.desktop.interface monospace-font-name 'FiraCode Nerd Font 11'"
                if [ "$ARCH_LINUX_SHELL_ENHANCEMENT_FISH_ENABLED" = "true" ]; then
                    echo "# exec_install_shell_enhancement | Set fish theme"
                    echo "fish -c 'fish_config theme choose Nord && echo y | fish_config theme save'"
                fi
            } >>"/mnt/home/${ARCH_LINUX_USERNAME}/${INIT_FILENAME}.sh"

            # Set correct permissions
            arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}"

            # Finished
            process_return 0
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

exec_install_vm_support() {
    local process_name="VM Support"
    if [ "$ARCH_LINUX_VM_SUPPORT_ENABLED" = "true" ]; then
        process_init "$process_name"
        (
            [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return
            case $(systemd-detect-virt || true) in
            kvm)
                log_info "KVM detected"
                chroot_pacman_install spice spice-vdagent spice-protocol spice-gtk qemu-guest-agent
                arch-chroot /mnt systemctl enable qemu-guest-agent
                ;;
            vmware)
                log_info "VMWare Workstation/ESXi detected"
                chroot_pacman_install open-vm-tools
                arch-chroot /mnt systemctl enable vmtoolsd
                arch-chroot /mnt systemctl enable vmware-vmblock-fuse
                ;;
            oracle)
                log_info "VirtualBox detected"
                chroot_pacman_install virtualbox-guest-utils
                arch-chroot /mnt systemctl enable vboxservice
                ;;
            microsoft)
                log_info "Hyper-V detected"
                chroot_pacman_install hyperv
                arch-chroot /mnt systemctl enable hv_fcopy_daemon
                arch-chroot /mnt systemctl enable hv_kvp_daemon
                arch-chroot /mnt systemctl enable hv_vss_daemon
                ;;
            *) log_info "No VM detected" ;; # Do nothing
            esac
            process_return 0 # Return
        ) &>"$PROCESS_LOG" &
        process_capture $! "$process_name"
    fi
}

# ---------------------------------------------------------------------------------------------------

# shellcheck disable=SC2016
exec_finalize_arch_linux() {
    local process_name="Finalize Arch Linux"
    process_init "$process_name"
    (
        [ "$DEBUG" = "true" ] && sleep 1 && process_return 0 # If debug mode then return

        # Add init script
        if [ -s "/mnt/home/${ARCH_LINUX_USERNAME}/${INIT_FILENAME}.sh" ]; then
            mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.arch-linux/system"
            mkdir -p "/mnt/home/${ARCH_LINUX_USERNAME}/.config/autostart"
            mv "/mnt/home/${ARCH_LINUX_USERNAME}/${INIT_FILENAME}.sh" "/mnt/home/${ARCH_LINUX_USERNAME}/.arch-linux/system/${INIT_FILENAME}.sh"
            # Add version env
            sed -i "1i\ARCH_LINUX_VERSION=${VERSION}" "/mnt/home/${ARCH_LINUX_USERNAME}/.arch-linux/system/${INIT_FILENAME}.sh"
            # Add shebang
            sed -i '1i\#!/usr/bin/env bash' "/mnt/home/${ARCH_LINUX_USERNAME}/.arch-linux/system/${INIT_FILENAME}.sh"
            # Add autostart-remove
            {
                echo "# exec_finalize_arch_linux | Remove autostart init files"
                echo "rm -f /home/${ARCH_LINUX_USERNAME}/.config/autostart/${INIT_FILENAME}.desktop"
            } >>"/mnt/home/${ARCH_LINUX_USERNAME}/.arch-linux/system/${INIT_FILENAME}.sh"
            # Print initialized info
            {
                echo "# exec_finalize_arch_linux | Print initialized info"
                echo "echo \"\$(date '+%Y-%m-%d %H:%M:%S') | Arch Linux \${ARCH_LINUX_VERSION} | Initialized\""
            } >>"/mnt/home/${ARCH_LINUX_USERNAME}/.arch-linux/system/${INIT_FILENAME}.sh"
            arch-chroot /mnt chmod +x "/home/${ARCH_LINUX_USERNAME}/.arch-linux/system/${INIT_FILENAME}.sh"
            {
                echo "[Desktop Entry]"
                echo "Type=Application"
                echo "Name=Arch Linux Initialize"
                echo "Icon=preferences-system"
                echo "Exec=bash -c '/home/${ARCH_LINUX_USERNAME}/.arch-linux/system/${INIT_FILENAME}.sh > /home/${ARCH_LINUX_USERNAME}/.arch-linux/system/${INIT_FILENAME}.log'"
            } >"/mnt/home/${ARCH_LINUX_USERNAME}/.config/autostart/${INIT_FILENAME}.desktop"
        fi

        # Set correct home permissions
        arch-chroot /mnt chown -R "$ARCH_LINUX_USERNAME":"$ARCH_LINUX_USERNAME" "/home/${ARCH_LINUX_USERNAME}"

        # Remove orphans and force return true
        arch-chroot /mnt bash -c 'pacman -Qtd &>/dev/null && pacman -Rns --noconfirm $(pacman -Qtdq) || true'

        # Install snapper pacman hook
        [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_SNAPPER_ENABLED" = "true" ] && chroot_pacman_install snap-pac

        # Add pacman btrfs hook (need to place on the end of script)
        if [ "$ARCH_LINUX_FILESYSTEM" = "btrfs" ] && [ "$ARCH_LINUX_SNAPPER_ENABLED" = "false" ]; then
            # Create pacman hook (auto create snapshot on pre-transaction)
            mkdir -p /mnt/etc/pacman.d/hooks/
            # shellcheck disable=SC2016
            {
                echo '[Trigger]'
                echo 'Operation = Install'
                echo 'Operation = Upgrade'
                echo 'Operation = Remove'
                echo 'Type = Package'
                echo 'Target = *'
                echo ''
                echo '[Action]'
                echo 'Description = Creating BTRFS snapshot'
                echo 'When = PreTransaction'
                #echo 'Exec = /usr/bin/btrfs subvolume snapshot -r / /.snapshots/$(date +%Y-%m-%d_%H-%M-%S)'
                echo 'Exec = /bin/sh -c '\''/usr/bin/btrfs subvolume snapshot -r / /.snapshots/"$(date "+%Y-%m-%d_%H-%M-%S")"'\'''
            } >/mnt/etc/pacman.d/hooks/50-btrfs-snapshot.hook
        fi

        process_return 0 # Return
    ) &>"$PROCESS_LOG" &
    process_capture $! "$process_name"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# CHROOT HELPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

chroot_pacman_install() {
    local packages=("$@")
    local pacman_failed="true"
    # Retry installing packages 5 times (in case of connection issues)
    for ((i = 1; i < 6; i++)); do
        # Print log if greather than first try
        [ "$i" -gt 1 ] && log_warn "${i}. Retry Pacman installation..."
        # Try installing packages
        # if ! arch-chroot /mnt bash -c "yes | LC_ALL=en_US.UTF-8 pacman -S --needed --disable-download-timeout ${packages[*]}"; then
        if ! arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"; then
            sleep 10 && continue # Wait 10 seconds & try again
        else
            pacman_failed="false" && break # Success: break loop
        fi
    done
    # Result
    [ "$pacman_failed" = "true" ] && return 1  # Failed after 5 retries
    [ "$pacman_failed" = "false" ] && return 0 # Success
}

chroot_aur_install() {

    # Vars
    local repo repo_url repo_tmp_dir aur_failed
    repo="$1" && repo_url="https://aur.archlinux.org/${repo}.git"

    # Disable sudo needs no password rights
    sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers

    # Temp dir
    repo_tmp_dir=$(mktemp -u "/home/${ARCH_LINUX_USERNAME}/.tmp-aur-${repo}.XXXX")

    # Retry installing AUR 5 times (in case of connection issues)
    aur_failed="true"
    for ((i = 1; i < 6; i++)); do

        # Print log if greather than first try
        [ "$i" -gt 1 ] && log_warn "${i}. Retry AUR installation..."

        #  Try cloning AUR repo
        ! arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- bash -c "rm -rf ${repo_tmp_dir}; git clone ${repo_url} ${repo_tmp_dir}" && sleep 10 && continue

        # Add '!debug' option to PKGBUILD
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- bash -c "cd ${repo_tmp_dir} && echo -e \"\noptions=('!debug')\" >>PKGBUILD"

        # Try installing AUR
        if ! arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- bash -c "cd ${repo_tmp_dir} && makepkg -si --noconfirm --needed"; then
            sleep 10 && continue # Wait 10 seconds & try again
        else
            aur_failed="false" && break # Success: break loop
        fi
    done

    # Remove tmp dir
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_LINUX_USERNAME" -- rm -rf "$repo_tmp_dir"

    # Enable sudo needs no password rights
    sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers

    # Result
    [ "$aur_failed" = "true" ] && return 1  # Failed after 5 retries
    [ "$aur_failed" = "false" ] && return 0 # Success
}

chroot_pacman_remove() { arch-chroot /mnt pacman -Rn --noconfirm "$@" || return 1; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# TRAP FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# shellcheck disable=SC2317
trap_error() {
    # If process calls this trap, write error to file to use in exit trap
    echo "Command '${BASH_COMMAND}' failed with exit code $? in function '${1}' (line ${2})" >"$ERROR_MSG"
}

# shellcheck disable=SC2317
trap_exit() {
    local result_code="$?"

    # Read error msg from file (written in error trap)
    local error && [ -f "$ERROR_MSG" ] && error="$(<"$ERROR_MSG")" && rm -f "$ERROR_MSG"

    # Cleanup
    unset ARCH_LINUX_PASSWORD
    rm -rf "$SCRIPT_TMP_DIR"

    # When ctrl + c pressed exit without other stuff below
    [ "$result_code" = "130" ] && gum_warn "Exit..." && {
        exit 1
    }

    # Check if failed and print error
    if [ "$result_code" -gt "0" ]; then
        [ -n "$error" ] && gum_fail "$error"            # Print error message (if exists)
        [ -z "$error" ] && gum_fail "An Error occurred" # Otherwise pint default error message
        gum_warn "See ${SCRIPT_LOG} for more information..."
        gum_confirm "Show Logs?" && gum pager --show-line-numbers <"$SCRIPT_LOG" # Ask for show logs?
    fi

    exit "$result_code" # Exit installer.sh
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROCESS FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

process_init() {
    [ -f "$PROCESS_RET" ] && gum_fail "${PROCESS_RET} already exists" && exit 1
    echo 1 >"$PROCESS_RET" # Init result with 1
    log_proc "${1}..."     # Log starting
}

process_capture() {
    local pid="$1"              # Set process pid
    local process_name="$2"     # Set process name
    local user_canceled="false" # Will set to true if user press ctrl + c

    # Show gum spinner until pid is not exists anymore and set user_canceled to true on failure
    gum_spin --title "${process_name}..." -- bash -c "while kill -0 $pid &> /dev/null; do sleep 1; done" || user_canceled="true"
    cat "$PROCESS_LOG" >>"$SCRIPT_LOG" # Write process log to logfile

    # When user press ctrl + c while process is running
    if [ "$user_canceled" = "true" ]; then
        kill -0 "$pid" &>/dev/null && pkill -P "$pid" &>/dev/null              # Kill process if running
        gum_fail "Process with PID ${pid} was killed by user" && trap_gum_exit # Exit with 130
    fi

    # Handle error while executing process
    [ ! -f "$PROCESS_RET" ] && gum_fail "${PROCESS_RET} not found (do not init process?)" && exit 1
    [ "$(<"$PROCESS_RET")" != "0" ] && gum_fail "${process_name} failed" && exit 1 # If process failed (result code 0 was not write in the end)

    # Finish
    rm -f "$PROCESS_RET"                 # Remove process result file
    gum_proc "${process_name}" "success" # Print process success
}

process_return() {
    # 1. Write from sub process 0 to file when succeed (at the end of the script part)
    # 2. Rread from parent process after sub process finished (0=success 1=failed)
    echo "$1" >"$PROCESS_RET"
    exit "$1"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# HELPER FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

print_header() {
    local title="$1"
    clear && gum_foreground '
    _    ____   ____ _   _   _     ___ _   _ _   ___  __
   / \  |  _ \ / ___| | | | | |   |_ _| \ | | | | \ \/ /
  / _ \ | |_) | |   | |_| | | |    | ||  \| | | | |\  / 
 / ___ \|  _ <| |___|  _  | | |___ | || |\  | |_| |/  \ 
/_/   \_\_| \_\\____|_| |_| |_____|___|_| \_|\___//_/\_\'
    local header_version="               v. ${VERSION}"
    [ "$DEBUG" = "true" ] && header_version="               d. ${VERSION}"
    gum_white --margin "1 0" --align left --bold "Welcome to ${title} ${header_version}"
    [ "$FORCE" = "true" ] && gum_red --bold "CAUTION: Force mode enabled. Cancel with: Ctrl + c" && echo
    return 0
}

print_filled_space() {
    local total="$1" && local text="$2" && local length="${#text}"
    [ "$length" -ge "$total" ] && echo "$text" && return 0
    local padding=$((total - length)) && printf '%s%*s\n' "$text" "$padding" ""
}

gum_init() {
    if [ ! -x "$GUM" ]; then
        clear && echo "Loading Arch Linux Installer..." # Loading
        local gum_url gum_path                       # Prepare URL with version os and arch
        # https://github.com/charmbracelet/gum/releases
        gum_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_$(uname -s)_$(uname -m).tar.gz"
        if ! curl -Lsf "$gum_url" >"${SCRIPT_TMP_DIR}/gum.tar.gz"; then echo "Error downloading ${gum_url}" && exit 1; fi
        if ! tar -xf "${SCRIPT_TMP_DIR}/gum.tar.gz" --directory "$SCRIPT_TMP_DIR"; then echo "Error extracting ${SCRIPT_TMP_DIR}/gum.tar.gz" && exit 1; fi
        gum_path=$(find "${SCRIPT_TMP_DIR}" -type f -executable -name "gum" -print -quit)
        [ -z "$gum_path" ] && echo "Error: 'gum' binary not found in '${SCRIPT_TMP_DIR}'" && exit 1
        if ! mv "$gum_path" "$GUM"; then echo "Error moving ${gum_path} to ${GUM}" && exit 1; fi
        if ! chmod +x "$GUM"; then echo "Error chmod +x ${GUM}" && exit 1; fi
    fi
}

gum() {
    if [ -n "$GUM" ] && [ -x "$GUM" ]; then
        "$GUM" "$@"
    else
        echo "Error: GUM '${GUM}' is not found or executable" >&2
        exit 1
    fi
}

trap_gum_exit() { exit 130; }
trap_gum_exit_confirm() { gum_confirm "Exit Installation?" && trap_gum_exit; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# GUM WRAPPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# Gum colors (https://github.com/muesli/termenv?tab=readme-ov-file#color-chart)
gum_foreground() { gum_style --foreground "$COLOR_FOREGROUND" "${@}"; }
gum_background() { gum_style --foreground "$COLOR_BACKGROUND" "${@}"; }
gum_white() { gum_style --foreground "$COLOR_WHITE" "${@}"; }
gum_black() { gum_style --foreground "$COLOR_BLACK" "${@}"; }
gum_red() { gum_style --foreground "$COLOR_RED" "${@}"; }
gum_green() { gum_style --foreground "$COLOR_GREEN" "${@}"; }
gum_blue() { gum_style --foreground "$COLOR_BLUE" "${@}"; }
gum_yellow() { gum_style --foreground "$COLOR_YELLOW" "${@}"; }
gum_cyan() { gum_style --foreground "$COLOR_CYAN" "${@}"; }
gum_purple() { gum_style --foreground "$COLOR_PURPLE" "${@}"; }

# Gum prints
gum_title() { log_head "${*}" && gum join "$(gum_foreground --bold "+ ")" "$(gum_foreground --bold "${*}")"; }
gum_info() { log_info "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white "${*}")"; }
gum_warn() { log_warn "$*" && gum join "$(gum_yellow --bold "• ")" "$(gum_white "${*}")"; }
gum_fail() { log_fail "$*" && gum join "$(gum_red --bold "• ")" "$(gum_white "${*}")"; }

# Gum wrapper
gum_style() { gum style "${@}"; }
gum_confirm() { gum confirm --prompt.foreground "$COLOR_FOREGROUND" --selected.background "$COLOR_FOREGROUND" --selected.foreground "$COLOR_BACKGROUND" --unselected.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_input() { gum input --placeholder "..." --prompt "> " --cursor.foreground "$COLOR_FOREGROUND" --prompt.foreground "$COLOR_FOREGROUND" --header.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_choose() { gum choose --cursor "> " --header.foreground "$COLOR_FOREGROUND" --cursor.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_filter() { gum filter --prompt "> " --indicator ">" --placeholder "Type to filter..." --height 8 --header.foreground "$COLOR_FOREGROUND" --indicator.foreground "$COLOR_FOREGROUND" --match.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_write() { gum write --prompt "> " --show-cursor-line --char-limit 0 --cursor.foreground "$COLOR_FOREGROUND" --header.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_spin() { gum spin --spinner line --title.foreground "$COLOR_FOREGROUND" --spinner.foreground "$COLOR_FOREGROUND" "${@}"; }

# Gum key & value
gum_proc() { log_proc "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white --bold "$(print_filled_space 24 "${1}")")" "$(gum_white "  >  ")" "$(gum_green "${2}")"; }
gum_property() { log_prop "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white "$(print_filled_space 24 "${1}")")" "$(gum_green --bold "  >  ")" "$(gum_white --bold "${2}")"; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# LOGGING WRAPPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

write_log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | arch-linux | ${*}" >>"$SCRIPT_LOG"; }
log_info() { write_log "INFO | ${*}"; }
log_warn() { write_log "WARN | ${*}"; }
log_fail() { write_log "FAIL | ${*}"; }
log_head() { write_log "HEAD | ${*}"; }
log_proc() { write_log "PROC | ${*}"; }
log_prop() { write_log "PROP | ${*}"; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# START MAIN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main "$@"