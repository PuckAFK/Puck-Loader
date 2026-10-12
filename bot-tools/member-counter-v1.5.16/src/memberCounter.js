// PuckHub member counter v1.5.16 — one safe voice channel, verified on Discord.
// The counter must NEVER remove messages or mutate unrelated channels.
import { ChannelType, PermissionFlagsBits } from 'discord.js';

export const MEMBER_COUNTER_VERSION = '1.5.16';
export const DEFAULT_GUILD_ID = '1553769147064788772';
const COUNTER_NAME = /^👥\s*Members\s*:/iu;
const TEN_MINUTES = 10 * 60 * 1000;
const active = new Set();

export function memberCounterLabel(n) {
  const count = Number(n);
  if (!Number.isFinite(count) || count < 0) throw new Error('Guild member count unavailable');
  return `👥 Members: ${Math.trunc(count).toLocaleString('en-US')}`;
}

export function chooseCounterGuild(client) {
  const requested = process.env.PUCKHUB_GUILD_ID || DEFAULT_GUILD_ID;
  const direct = client.guilds.cache.get(requested);
  if (direct) return direct;
  const all = [...client.guilds.cache.values()];
  if (all.length === 1) {
    console.warn(`[PuckHub Counter] Configured guild ${requested} not found; using the bot's only server ${all[0].id}.`);
    return all[0];
  }
  throw new Error(`Guild ${requested} not present in bot cache (${all.length} guilds). Set PUCKHUB_GUILD_ID in .env.`);
}

function noConnectOverwrites(guild) {
  return [{id: guild.id, allow:[PermissionFlagsBits.ViewChannel], deny:[PermissionFlagsBits.Connect,PermissionFlagsBits.Speak,PermissionFlagsBits.Stream]}];
}

/** Ensure the channel exists, is locked to @everyone, and is persisted. Throws on any essential error. */
export async function ensureMemberCounter(guild, guildData, updateGuild, options={}) {
  if (!guild || guild.available === false) throw new Error('Discord guild unavailable');
  if (!guild.channels?.cache || !guild.channels?.create) throw new Error('Cannot access guild channels');
  const settings = guildData(guild.id).settings || {};
  let channel = settings.channels?.memberCounter ? guild.channels.cache.get(settings.channels.memberCounter) : null;
  if (channel && channel.type !== ChannelType.GuildVoice) channel = null;
  if (!channel) channel = guild.channels.cache.find(c => c.type===ChannelType.GuildVoice && COUNTER_NAME.test(c.name||'')) || null;
  const wanted = memberCounterLabel(guild.memberCount);
  let created = false;
  if (!channel) {
    channel = await guild.channels.create({
      name:wanted,
      type:ChannelType.GuildVoice,
      parent:null,
      position:0,
      permissionOverwrites:noConnectOverwrites(guild),
      reason:'PuckHub verified locked member counter',
    });
    created = true;
    console.log(`[PuckHub Counter] Created ${channel.name} (${channel.id})`);
  }
  if (channel.type !== ChannelType.GuildVoice) throw new Error(`Counter channel ${channel.id} is not a voice channel`);

  // Do not skip this when reusing a channel; old permissions may be incorrect.
  // One overwrite on the @everyone role denies voice connection but retains visibility.
  const existingEveryone=channel.permissionOverwrites?.cache?.get(guild.id);
  const isLocked=Boolean(existingEveryone?.allow?.has(PermissionFlagsBits.ViewChannel) && existingEveryone?.deny?.has(PermissionFlagsBits.Connect) && existingEveryone?.deny?.has(PermissionFlagsBits.Speak) && existingEveryone?.deny?.has(PermissionFlagsBits.Stream));
  if (!isLocked) await channel.permissionOverwrites.edit(guild.id,{ViewChannel:true,Connect:false,Speak:false,Stream:false},'PuckHub member counter locked');
  if (channel.parentId) await channel.setParent(null,{lockPermissions:false});
  let positioned=false;
  if ((created || options.forcePosition || !settings.memberCounterPositionedAt) && typeof channel.setPosition==='function') {
    try { await channel.setPosition(0); positioned=true; }
    catch(e) { console.warn(`[PuckHub Counter] Could not move counter to top: ${e?.message||e}`); }
  }
  const now=Date.now();
  const lastRename=Number(settings.memberCounterLastRenameAt||0);
  const mustRename=channel.name!==wanted && (options.forceRename || now-lastRename>=TEN_MINUTES);
  if (mustRename) await channel.setName(wanted,'PuckHub member counter refresh');
  const recordedName=mustRename?wanted:channel.name;
  // Keep the ID only after creation/permissions succeed; no duplicate channel on retry.
  updateGuild(guild.id, data => {
    data.settings.channels??={};
    data.settings.channels.memberCounter=channel.id;
    if(positioned) data.settings.memberCounterPositionedAt=now;
    if(created || mustRename) data.settings.memberCounterLastRenameAt=now;
  });
  if (options.verify) {
    const checked = await guild.channels.fetch(channel.id);
    if (!checked || checked.type!==ChannelType.GuildVoice) throw new Error('Discord could not return the new voice channel');
    const overwrite = checked.permissionOverwrites.cache.get(guild.id);
    if (!overwrite || !overwrite.deny.has(PermissionFlagsBits.Connect)) throw new Error('Discord did not retain the Connect denial');
    if (!overwrite.allow.has(PermissionFlagsBits.ViewChannel)) throw new Error('Discord did not retain public visibility');
  }
  return {id:channel.id,name:recordedName,created,guildId:guild.id};
}

/** Wire the counter into the real PuckHub client once (not a second bot process). */
export function attachMemberCounter(client,guildData,updateGuild) {
  if (client.__puckMemberCounter1516) return;
  client.__puckMemberCounter1516=true;
  let running=false, lastWarnAt=0;
  const sync=async reason=>{
    if(running)return;
    running=true;
    try {
      const guild=chooseCounterGuild(client);
      const result=await ensureMemberCounter(guild,guildData,updateGuild);
      if (reason==='ready') console.log(`[PuckHub Counter] Active: ${result.name} (${result.id}) in ${guild.name}`);
    }catch(e){
      const now=Date.now();
      if(now-lastWarnAt>30_000){console.error(`[PuckHub Counter] ${reason}: ${e?.message||e}`);lastWarnAt=now;}
    }finally{running=false;}
  };
  client.once('ready',()=>{
    // Not awaited by startup; scheduled again if Discord temporarily rejects the request.
    void sync('ready');
    const timer=setInterval(()=>void sync('periodic'),60_000);
    timer.unref?.();
  });
  client.on('guildMemberAdd', m=>{ if(m.guild?.id===(process.env.PUCKHUB_GUILD_ID||DEFAULT_GUILD_ID)) void sync('join'); });
  client.on('guildMemberRemove', m=>{ if(m.guild?.id===(process.env.PUCKHUB_GUILD_ID||DEFAULT_GUILD_ID)) void sync('leave'); });
}
