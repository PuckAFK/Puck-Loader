#!/usr/bin/env bash
# PuckHub v1.5.16 member counter. Use the SAME network route as the running bot.
# Creates/verifies Discord counter while the live bot is safely stopped, then enables runtime updates.
set -Eeuo pipefail

SERVICE='puckhub-bot.service'
APP="$(systemctl show "$SERVICE" -p WorkingDirectory --value 2>/dev/null || true)"
[[ -n "$APP" && "$APP" != '/' ]] || APP="$HOME/PuckHub"
SRC="$APP/src/index.js"
[[ -f "$SRC" && -f "$APP/src/storage.js" && -d "$APP/node_modules/discord.js" ]] || { echo '[PuckHub Counter] ERROR: Installed PuckHub source/discord.js not found. Nothing changed.'; exit 1; }
[[ -f "$APP/.env" || -n "${DISCORD_TOKEN:-}" ]] || { echo '[PuckHub Counter] ERROR: Missing PuckHub .env / Discord token. Nothing changed.'; exit 1; }
command -v node >/dev/null && command -v python3 >/dev/null && command -v curl >/dev/null || { echo '[PuckHub Counter] ERROR: Requires node, python3 and curl.'; exit 1; }

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ "$HERE" != "$APP" ]] || { echo '[PuckHub Counter] ERROR: Extract update outside the live PuckHub folder.'; exit 1; }
[[ -f "$HERE/src/memberCounter.js" && -f "$HERE/tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs" ]] || { echo '[PuckHub Counter] ERROR: Incomplete v1.5.16 archive.'; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
cp "$HERE/src/memberCounter.js" "$TMP/memberCounter.js"
cp "$HERE/tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs" "$TMP/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs"
node --check "$TMP/memberCounter.js"
node --check "$TMP/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs"

# v1.5.15 used bare `node` to verify Discord. The production bot in this VM
# normally runs through proxychains4 -> Cloudflare WARP SOCKS5 127.0.0.1:40000.
# Reuse the service's networking, not a separate direct HTTPS connection.
SERVICE_EXEC="$(systemctl show "$SERVICE" -p ExecStart --value 2>/dev/null || true)"
NODE_RUNNER=(node)
if [[ "$SERVICE_EXEC" == *proxychains* ]]; then
  command -v proxychains4 >/dev/null || { echo '[PuckHub Counter] ERROR: Live bot uses proxychains4 but the command is missing.'; exit 1; }
  CONF="$APP/proxychains-puckhub.conf"
  [[ -r "$CONF" ]] || { echo "[PuckHub Counter] ERROR: Live bot uses proxychains4 but $CONF is missing."; exit 1; }
  NODE_RUNNER=("$(command -v proxychains4)" -q -f "$CONF" node)
  # Read the actual SOCKS proxy endpoint from the bot config (not an invented endpoint).
  SOCKS_SETTINGS="$(awk 'BEGIN{inlist=0} /^\[ProxyList\]/{inlist=1;next} inlist && $1=="socks5" {print $2 " " $3;exit}' "$CONF")"
  read -r SOCKS_HOST SOCKS_PORT <<< "$SOCKS_SETTINGS"
  [[ -n "${SOCKS_HOST:-}" && "${SOCKS_PORT:-}" =~ ^[0-9]+$ ]] || { echo '[PuckHub Counter] ERROR: Could not parse the SOCKS5 endpoint from proxychains config.'; exit 1; }
  echo "[PuckHub Counter] Production service uses proxychains4; testing SOCKS5 ${SOCKS_HOST}:${SOCKS_PORT} first."
  [[ "$SOCKS_HOST" == '127.0.0.1' || "$SOCKS_HOST" == 'localhost' || "$SOCKS_HOST" == '::1' ]] || { echo '[PuckHub Counter] ERROR: Unexpected non-local SOCKS5 proxy. Stopping safely.'; exit 1; }
  if ! curl -fLsS --retry 1 --connect-timeout 8 --max-time 22 --socks5-hostname "${SOCKS_HOST}:${SOCKS_PORT}" 'https://discord.com/api/v10/gateway' -o /dev/null; then
    echo '[PuckHub Counter] ERROR: Discord cannot be reached through the live bot WARP proxy. No files or service were changed.'
    echo '[PuckHub Counter] Diagnostics: sudo systemctl status puckhub-warp.service --no-pager; sudo journalctl -u puckhub-warp.service -n 30 --no-pager'
    exit 1
  fi
  echo '[PuckHub Counter] Discord REST API reachable through WARP. Continuing with verified install.'
else
  echo '[PuckHub Counter] Production service does not declare proxychains; testing direct Discord HTTPS.'
  if ! curl -fLsS --retry 1 --connect-timeout 8 --max-time 22 'https://discord.com/api/v10/gateway' -o /dev/null;then
    echo '[PuckHub Counter] ERROR: Direct Discord API connection failed. Live bot not stopped; no files changed.'
    exit 1
  fi
fi

# Generate a candidate without touching the running bot.
python3 - "$SRC" "$TMP/new-index.js" <<'PY'
import pathlib,sys
source=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
if 'client.login(TOKEN)' not in source or 'const client = new Client' not in source or "from './storage.js'" not in source:
    raise SystemExit('[PuckHub Counter] ERROR: Unfamiliar bot source; no live changes made.')
# Remove only the old v1.5.14 addition, preserving everything else.
start='// PUCKHUB_MEMBER_COUNTER_V1514'
end='// END_PUCKHUB_MEMBER_COUNTER_V1514'
if start in source:
    if source.count(start)!=1 or source.count(end)!=1:raise SystemExit('[PuckHub Counter] ERROR: Ambiguous old patch; no changes made.')
    a=source.index(start)
    b=source.index(end,a)+len(end)
    source=source[:a]+source[b:]
    print('[PuckHub Counter] Retired the v1.5.14 injection (prevents duplicate event listeners).')
imports="import { attachMemberCounter } from './memberCounter.js'; // PUCKHUB_MEMBER_COUNTER_V1516\n"
# Upgrade an earlier verified implementation without adding a second listener.
if 'PUCKHUB_MEMBER_COUNTER_V1515' in source:
    source=source.replace('PUCKHUB_MEMBER_COUNTER_V1515','PUCKHUB_MEMBER_COUNTER_V1516')
if 'PUCKHUB_MEMBER_COUNTER_V1516' not in source:
    source=imports+source
    source=source.replace('client.login(TOKEN).catch(', 'attachMemberCounter(client,guildData,updateGuild);\n\nclient.login(TOKEN).catch(',1)
if source.count('attachMemberCounter(client,guildData,updateGuild);')!=1:
    raise SystemExit('[PuckHub Counter] ERROR: Unexpected counter startup wiring; no changes made.')
pathlib.Path(sys.argv[2]).write_text(source,encoding='utf-8')
PY
node --check "$TMP/new-index.js"

BACKUP="$HOME/puckhub-member-counter-backup-v1.5.16-$(date +%Y%m%d-%H%M%S)"
(umask 077; mkdir -p "$BACKUP")
cp -p "$SRC" "$BACKUP/index.js"
[[ ! -f "$APP/src/memberCounter.js" ]] || cp -p "$APP/src/memberCounter.js" "$BACKUP/memberCounter.js"
[[ ! -f "$APP/tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs" ]] || cp -p "$APP/tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs" "$BACKUP/repair.mjs"
mkdir -p "$APP/tools"

rollback() {
  echo '[PuckHub Counter] Restoring previous bot code and restarting service...'
  cp -p "$BACKUP/index.js" "$SRC"
  if [[ -f "$BACKUP/memberCounter.js" ]];then cp -p "$BACKUP/memberCounter.js" "$APP/src/memberCounter.js"; else rm -f "$APP/src/memberCounter.js"; fi
  if [[ -f "$BACKUP/repair.mjs" ]];then cp -p "$BACKUP/repair.mjs" "$APP/tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs"; else rm -f "$APP/tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs";fi
  sudo systemctl restart "$SERVICE" || true
}

sudo systemctl stop "$SERVICE"
if ! {
  cp -p "$TMP/new-index.js" "$SRC"
  cp -p "$TMP/memberCounter.js" "$APP/src/memberCounter.js"
  cp -p "$TMP/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs" "$APP/tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs"
  node --check "$SRC"
  echo '[PuckHub Counter] Connecting through the SAME network route as the live bot...'
  (cd "$APP" && "${NODE_RUNNER[@]}" tools/REPAIR-PUCKHUB-MEMBER-COUNTER-v1.5.16.mjs)
};then
  echo '[PuckHub Counter] ERROR: Discord verification failed. NOT reporting installation success.'
  rollback
  echo "[PuckHub Counter] Restore backup: $BACKUP"
  exit 1
fi

if ! { sudo systemctl start "$SERVICE" && sleep 10 && systemctl is-active --quiet "$SERVICE"; };then
  echo '[PuckHub Counter] ERROR: Service did not restart cleanly.'
  rollback
  exit 1
fi

echo ''
echo '[PuckHub Counter] SUCCESS: Discord returned and verified the counter channel.'
echo '[PuckHub Counter] The bot is active with periodic updates and join/leave refreshes.'
echo '[PuckHub Counter] If you cannot see it, refresh Discord and check category/channel visibility for your role.'
echo "[PuckHub Counter] Backup: $BACKUP"
echo "[PuckHub Counter] Logs: sudo journalctl -u $SERVICE -n 80 --no-pager | grep -i -E 'counter|error|ready'"
