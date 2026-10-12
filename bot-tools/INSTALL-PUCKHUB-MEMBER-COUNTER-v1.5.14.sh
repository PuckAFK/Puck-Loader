#!/usr/bin/env bash
# PuckHub member-count display hotfix, based on v1.5.13.
# Non-destructive: patches src/index.js only, with backup and rollback.
set -Eeuo pipefail

SERVICE='puckhub-bot.service'
APP="$(systemctl show "$SERVICE" -p WorkingDirectory --value 2>/dev/null || true)"
if [[ -z "$APP" || "$APP" == '/' ]]; then APP="$HOME/PuckHub"; fi
TARGET="$APP/src/index.js"
if [[ ! -f "$TARGET" ]]; then
  echo '[PuckHub] ERROR: Existing bot src/index.js not found. No changes made.'
  exit 1
fi
if ! grep -q 'const client = new Client' "$TARGET" || ! grep -q 'client.login(' "$TARGET"; then
  echo '[PuckHub] ERROR: Bot file layout is unfamiliar. No changes made.'
  exit 1
fi

BACKUP="$HOME/puckhub-member-counter-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
cp -p "$TARGET" "$BACKUP/index.js"
echo "[PuckHub] Backed up index.js to $BACKUP"

python3 - "$TARGET" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
old = path.read_text(encoding="utf-8")
marker = "// PUCKHUB_MEMBER_COUNTER_V1514"
if marker in old:
    print("[PuckHub] Member counter is already installed; leaving source unchanged.")
    sys.exit(0)
needle = "client.login("
place = old.rfind(needle)
if place < 0:
    raise SystemExit("[PuckHub] Missing client.login marker. No changes made.")
place = old.rfind("\n", 0, place) + 1

addon = r'''
// PUCKHUB_MEMBER_COUNTER_V1514
// Locked, visible voice counter. Discord administrators can bypass channel denies.
const __puckCounterGuildId = process.env.PUCKHUB_GUILD_ID || "1553769147064788772";
const __puckCounterRenameIntervalMs = 10 * 60 * 1000;
const __puckCounterSecured = new Set();
let __puckCounterBusy = false;

async function __puckSyncMemberCounter() {
  if (__puckCounterBusy) return;
  __puckCounterBusy = true;
  try {
    const guild = client.guilds.cache.get(__puckCounterGuildId);
    if (!guild || guild.available === false) return;

    const wanted = "👥 Members: " + Number(guild.memberCount || 0).toLocaleString("en-US");
    const settings = guildData(guild.id).settings || {};
    const id = settings.channels?.memberCounter || null;
    let channel = id ? guild.channels.cache.get(id) : null;
    if (!channel || channel.type !== ChannelType.GuildVoice) {
      channel = guild.channels.cache.find(c =>
        c.type === ChannelType.GuildVoice &&
        /^👥[\s・: -]*Members\s*:/iu.test(c.name || "")
      ) || null;
    }

    if (!channel) {
      channel = await guild.channels.create({
        name: wanted,
        type: ChannelType.GuildVoice,
        position: 0,
        permissionOverwrites: [
          {
            id: guild.id,
            allow: [PermissionFlagsBits.ViewChannel],
            deny: [
              PermissionFlagsBits.Connect,
              PermissionFlagsBits.Speak,
              PermissionFlagsBits.Stream
            ]
          }
        ],
        reason: "PuckHub top-of-server locked member counter"
      });
      __puckCounterSecured.add(channel.id);
      updateGuild(guild.id, data => {
        data.settings.channels ??= {};
        data.settings.channels.memberCounter = channel.id;
        data.settings.memberCounterLastRenameAt = Date.now();
      });
      console.log("[PuckHub] Created locked member counter: " + channel.name);
      return;
    }

    if (!__puckCounterSecured.has(channel.id)) {
      await channel.permissionOverwrites.edit(guild.id, {
        ViewChannel: true,
        Connect: false,
        Speak: false,
        Stream: false
      }, "PuckHub locked member counter");
      if (channel.parentId) {
        await channel.setParent(null, { lockPermissions: false }).catch(e =>
          console.warn("[PuckHub] Counter category move:", e.message)
        );
      }
      await channel.setPosition(0).catch(e =>
        console.warn("[PuckHub] Counter position:", e.message)
      );
      __puckCounterSecured.add(channel.id);
    }

    if (settings.channels?.memberCounter !== channel.id) {
      updateGuild(guild.id, data => {
        data.settings.channels ??= {};
        data.settings.channels.memberCounter = channel.id;
      });
    }

    const now = Date.now();
    const lastRename = Number(guildData(guild.id).settings?.memberCounterLastRenameAt || 0);
    if (channel.name !== wanted && now - lastRename >= __puckCounterRenameIntervalMs) {
      await channel.setName(wanted, "PuckHub live member count");
      updateGuild(guild.id, data => {
        data.settings.memberCounterLastRenameAt = now;
      });
      console.log("[PuckHub] Member counter updated: " + wanted);
    }
  } catch (error) {
    console.warn("[PuckHub] Member counter update failed:", error?.message || error);
  } finally {
    __puckCounterBusy = false;
  }
}

client.once("ready", () => {
  void __puckSyncMemberCounter();
  const clock = setInterval(() => {
    void __puckSyncMemberCounter();
  }, 60 * 1000);
  clock.unref?.();
});

client.on("guildMemberAdd", member => {
  if (member.guild.id === __puckCounterGuildId) void __puckSyncMemberCounter();
});
client.on("guildMemberRemove", member => {
  if (member.guild.id === __puckCounterGuildId) void __puckSyncMemberCounter();
});
// END_PUCKHUB_MEMBER_COUNTER_V1514

'''
updated = old[:place] + addon + old[place:]
path.write_text(updated, encoding="utf-8")
print("[PuckHub] Injected locked member counter into existing bot.")
PY

if ! node --check "$TARGET"; then
  cp -p "$BACKUP/index.js" "$TARGET"
  echo '[PuckHub] ERROR: Syntax check failed; restored original bot.'
  exit 1
fi

if ! sudo systemctl restart "$SERVICE"; then
  cp -p "$BACKUP/index.js" "$TARGET"
  sudo systemctl restart "$SERVICE" || true
  echo '[PuckHub] ERROR: Restart failed; restored original bot.'
  exit 1
fi
sleep 8
if ! systemctl is-active --quiet "$SERVICE"; then
  cp -p "$BACKUP/index.js" "$TARGET"
  sudo systemctl restart "$SERVICE" || true
  echo '[PuckHub] ERROR: Bot not active; restored original source.'
  exit 1
fi

echo ''
echo '[PuckHub] Member-counter patch installed.'
echo 'A locked, non-joinable voice channel should appear at the top of the server.'
echo 'It displays the total Discord member count, including bots.'
echo 'Name updates no more than once per 10 minutes (unless creating it).'
echo 'Discord owners and Administrators may bypass channel denies.'
echo "Backup: $BACKUP"
echo 'View recent logs: sudo journalctl -u puckhub-bot.service -n 50 --no-pager'
