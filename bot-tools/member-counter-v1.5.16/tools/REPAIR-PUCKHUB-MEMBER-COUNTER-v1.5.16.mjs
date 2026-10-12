// Run inside ~/PuckHub/tools, after the live systemd service is stopped. Run with the live service proxychains4 configuration.
// Uses the bot's existing token locally. NEVER prints or uploads credentials.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Client,GatewayIntentBits,PermissionFlagsBits,ChannelType} from 'discord.js';
import {guildData,updateGuild} from '../src/storage.js';
import {ensureMemberCounter,chooseCounterGuild} from '../src/memberCounter.js';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const envFile=path.join(root,'.env');
if(fs.existsSync(envFile)){
  for(const raw of fs.readFileSync(envFile,'utf8').split(/\r?\n/)){
    const line=raw.trim();if(!line||line.startsWith('#'))continue;
    const eq=line.indexOf('=');if(eq<1)continue;
    const key=line.slice(0,eq).trim();let value=line.slice(eq+1).trim();
    if((value.startsWith('"')&&value.endsWith('"'))||(value.startsWith("'")&&value.endsWith("'")))value=value.slice(1,-1);
    if(!(key in process.env))process.env[key]=value;
  }
}
const token=process.env.DISCORD_TOKEN?.trim();
if(!token) {console.error('[PuckHub Counter] Missing DISCORD_TOKEN in bot environment/.env');process.exit(1);}
const client=new Client({intents:[GatewayIntentBits.Guilds]});
let watchdog;
try{
  watchdog=setTimeout(()=>{console.error('[PuckHub Counter] Discord login timed out after 30 seconds.');process.exitCode=1;void client.destroy();},30_000);
  await client.login(token);
  if(!client.isReady())await new Promise((resolve,reject)=>{client.once('ready',resolve);client.once('error',reject);});
  clearTimeout(watchdog);
  const guild=chooseCounterGuild(client);
  const member=await guild.members.fetchMe();
  if(!member.permissions.has(PermissionFlagsBits.ManageChannels)) throw new Error('PuckHub bot is missing Manage Channels in this server. Enable it in Server Settings > Roles.');
  console.log(`[PuckHub Counter] Connected to guild ${guild.name} (${guild.id}); ${guild.memberCount} total members.`);
  const ensured=await ensureMemberCounter(guild,guildData,updateGuild,{verify:true,forcePosition:true,forceRename:true});
  // Independently fetch after ensuring, rather than relying on local cache alone.
  const direct=await guild.channels.fetch(ensured.id);
  if(!direct || direct.type!==ChannelType.GuildVoice)throw new Error('Final Discord verification failed: no voice counter was found');
  if(direct.parentId)throw new Error('Counter still sits inside a category; expected a top-level channel');
  console.log(`[PuckHub Counter] VERIFIED: #${ensured.name} | ID ${ensured.id} | https://discord.com/channels/${guild.id}/${ensured.id}`);
  process.exitCode=0;
}catch(e){
  clearTimeout(watchdog);
  console.error(`[PuckHub Counter] REPAIR FAILED: ${e?.message||e}${e?.code?' (code '+e.code+')':''}`);
  process.exitCode=1;
}finally{await client.destroy().catch(()=>{});}
