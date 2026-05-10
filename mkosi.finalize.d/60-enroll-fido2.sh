#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# 60-enroll-fido2.sh — Drop yubiOS-enroll.service into the image
# Runs at mkosi finalize time (build host), installs first-boot enrollment logic.

set -euo pipefail

ROOT="${DESTDIR:-}"
UNIT_DIR="${ROOT}/usr/lib/systemd/system"
LIB_DIR="${ROOT}/usr/lib/yubiOS"

mkdir -p "${UNIT_DIR}" "${LIB_DIR}"

cat > "${UNIT_DIR}/yubiOS-enroll.service" << 'UNIT'
[Unit]
Description=yubiOS First-Boot FIDO2 Enrollment
ConditionPathExists=!/etc/.yubiOS-enrolled
After=systemd-udev-settle.service local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/lib/yubiOS/enroll.sh
StandardInput=tty
TTYPath=/dev/console
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNIT

cat > "${LIB_DIR}/enroll.sh" << 'ENROLL'
#!/bin/bash
set -euo pipefail
CONSOLE=/dev/console
echo_tty() { echo "$*" > "${CONSOLE}" 2>/dev/null || echo "$*"; }

LUKS_DEVICE=""
if grep -qo 'rd.luks.uuid=[^ ]*' /proc/cmdline 2>/dev/null; then
    LUKS_UUID=$(grep -o 'rd.luks.uuid=[^ ]*' /proc/cmdline | cut -d= -f2)
    LUKS_DEVICE="/dev/disk/by-uuid/${LUKS_UUID}"
fi

echo_tty "yubiOS: Insert YubiKey and press Enter."
read -r _c < "${CONSOLE}" || true
if ! ls /dev/hidraw* 2>/dev/null | xargs -I{} sh -c \
   'udevadm info --query=property --name={} 2>/dev/null | grep -q ID_VENDOR_ID=1050'; then
    echo_tty "yubiOS: ERROR - no YubiKey detected. Aborting."
    exit 1
fi

if [[ -n "${LUKS_DEVICE}" && -b "${LUKS_DEVICE}" ]]; then
    echo_tty "yubiOS: Enrolling LUKS2 FIDO2 slot..."
    systemd-cryptenroll --fido2-device=auto \
        --fido2-with-client-pin=yes --fido2-with-user-presence=yes \
        "${LUKS_DEVICE}"
fi

echo_tty "yubiOS: Enrolling pam_u2f key (tap twice)..."
pamu2fcfg --nouser >> /etc/u2f_keys

SSH_DIR="${HOME:-/root}/.ssh"
mkdir -p "${SSH_DIR}" && chmod 700 "${SSH_DIR}"
ssh-keygen -t ed25519-sk -O resident -O application=ssh:yubiOS \
    -C "yubiOS" -f "${SSH_DIR}/id_ed25519_sk" -N "" < "${CONSOLE}" 2>/dev/null || true
if [[ -f "${SSH_DIR}/id_ed25519_sk.pub" ]]; then
    cat "${SSH_DIR}/id_ed25519_sk.pub" >> "${SSH_DIR}/authorized_keys"
    chmod 600 "${SSH_DIR}/authorized_keys"
fi

touch /etc/.yubiOS-enrolled
echo_tty "yubiOS: Enrollment complete. Reboot with YubiKey removed."
ENROLL

chmod +x "${LIB_DIR}/enroll.sh"

WANTED="${UNIT_DIR}/multi-user.target.wants"
mkdir -p "${WANTED}"
ln -sf ../yubiOS-enroll.service "${WANTED}/yubiOS-enroll.service"

echo "60-enroll-fido2.sh: yubiOS-enroll.service installed."