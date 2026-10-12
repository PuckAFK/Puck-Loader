#!/usr/bin/env bash
# Bootstrap PuckHub v1.5.16 WARP-aware verified member counter.
# Downloads versioned/pinned installer assets, then runs the same VM ZIP installer.
set -Eeuo pipefail
HERE="$(mktemp -d)"
trap 'rm -rf -- "$HERE"' EXIT
mkdir -p "$HERE/src" "$HERE/tools"
echo '[PuckHub Counter] Downloading checked v1.5.16 assets from PuckAFK/Puck-Loader...'
curl -fLsS --retry 3 --connect-timeout 10 --max-time 45 "https://raw.githubusercontent.com/PuckAFK/Puck-Loader/main/bot-tools/member-counter-v1.5.16/INSTALL-PUCKHUB-MEMBER-COUNTER-v1.5.16.sh" -o "$HERE/INSTALL-PUCKHUB-MEMBER-COUNTER-v1.5.16.sh"
curl -fLsS --retry 3 --connect-timeout 10 --max-time 45 "https://raw.githubusercontent.com/PuckAFK/Puck-Loader/main/bot-tools/member-counter-v1.5.16/src/memberCounter.js" -o "$HERE/src/memberCounter.js"
curl -fLsS --retry 3 --connect-timeout 10 --max-time 45 "https://raw.githubusercontent.com/PuckAFK/Puck-Loader/main/bot-tools/member-counter-v1.5.16/tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs" -o "$HERE/tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs"

# Verify exact reviewed version; fail closed if anything changed or was truncated.
printf "%s  %s\n" "a273f437e7aaeca7e8b7f11e9a0f32f0cd6b786418e4664e0d34bc342f10da57" "$HERE/INSTALL-PUCKHUB-MEMBER-COUNTER-v1.5.16.sh" | sha256sum -c --status || { echo "[PuckHub Counter] ERROR: Invalid checksum for INSTALL-PUCKHUB-MEMBER-COUNTER-v1.5.16.sh"; exit 1; }
printf "%s  %s\n" "a88bbf3b8635b7f1a01e4bd335360c37528da217ec1c192f83e19e5132968e82" "$HERE/src/memberCounter.js" | sha256sum -c --status || { echo "[PuckHub Counter] ERROR: Invalid checksum for src/memberCounter.js"; exit 1; }
printf "%s  %s\n" "8352a2366f6c3a9a8134ff2a0d1f8c1f4e034d450f1066044ca2f78ac1446e40" "$HERE/tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs" | sha256sum -c --status || { echo "[PuckHub Counter] ERROR: Invalid checksum for tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs"; exit 1; }
echo '[PuckHub Counter] Release integrity verified.'
bash "$HERE/INSTALL-PUCKHUB-MEMBER-COUNTER-v1.5.16.sh"
