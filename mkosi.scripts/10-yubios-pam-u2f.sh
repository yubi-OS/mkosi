#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# 10-yubios-pam-u2f.sh — Configure pam_u2f for sudo + login + polkit
#
# pam-u2f >= 1.3.1 enforced (YSA-2025-01 / CVE-2025-23013)

set -euo pipefail

ROOT="${DESTDIR:-}"

PAM_SUDO="${ROOT}/etc/pam.d/sudo"
if [[ -f "${PAM_SUDO}" ]]; then
    sed -i '/@include common-auth/a auth    required    pam_u2f.so cue authfile=/etc/u2f_keys pinverification=0 userpresence=1' "${PAM_SUDO}"
fi

PAM_LOGIN="${ROOT}/etc/pam.d/login"
if [[ -f "${PAM_LOGIN}" ]]; then
    sed -i '/@include common-auth/a auth    required    pam_u2f.so cue authfile=/etc/u2f_keys pinverification=0 userpresence=1' "${PAM_LOGIN}"
fi

mkdir -p "${ROOT}/etc"
touch "${ROOT}/etc/u2f_keys"
chmod 600 "${ROOT}/etc/u2f_keys"

SSHD_CONF="${ROOT}/etc/ssh/sshd_config.d/10-yubios.conf"
mkdir -p "$(dirname ${SSHD_CONF})"
cat > "${SSHD_CONF}" << 'EOF'
# yubios: FIDO2-only SSH access
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitRootLogin no
EOF

echo "10-yubios-pam-u2f.sh: complete."