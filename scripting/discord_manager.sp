/* CHANGELOG
	1.2.2: 12/04/2020
		-Translation: "PLAYER"
		-Fixed couple of errors
		-More debug messages to avoid errors

	1.2.1: 11/04/2020
		-Increased webhooks buffer size
		-disord_webhook_map_delay to specify the delay of the map webhook
		-Translation: "No reason specified"

	1.2: 10/04/2020
		-Initial release of the new version
*/

#include <sourcemod>
#include <colorvariables>

#include <discord>
#include <SteamWorks>
#include "discord/DiscordRequest.sp"
#include <servermanager>
#include <regex>

#undef REQUIRE_PLUGIN
#include <chat-processor>
#include <sourcebanspp>
#include <sourcecomms>
#define REQUIRE_PLUGIN

#define PLUGIN_NEV	"DSM"
#define PLUGIN_LERIAS	"DSM"
#define PLUGIN_AUTHOR	"Nexd ( w Deathknife Discord-API )"
#define PLUGIN_VERSION	"1.2.2"
#define PLUGIN_URL	"https://github.com/KillStr3aK"

#pragma tabsize 0;
#pragma newdecls required;
#pragma semicolon 1;

public Plugin myinfo = 
{
	name = PLUGIN_NEV,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_LERIAS,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

char sHostname[512];
char szTranslationBuffer[256];
char szColorList[19][] = {
	"{green}", "{lime}", "{default}", "{lightgreen}",
	"{gray}", "{grey}", "{bluegrey}", "{grey2}", "{gold}",
	"{red}", "{lightred}", "{darkred}", "{blue}", "{yellow}",
	"{teamcolor}", "{orchid}", "{purple}", "{rainbow}", "{darkblue}"
};

methodmap Jatekos
{
	public Jatekos(int jatekos) {
		return view_as<Jatekos>(jatekos);
	}

	property int index {
		public get() {
			return view_as<int>(this);
		}
	}

	property bool IsValid {
		public get() {
			return IsValidClient(this.index);
		}
	}

	public bool GetAuthId(AuthIdType authType, char[] auth, int maxlen, bool validate = true) {
		return GetClientAuthId(this.index, authType, auth, maxlen, validate);
	}
}

enum struct PlayerData {
	char UserID[20];
	char UniqueCode[30];
	char AvatarUrl[128];
	bool Member;
}

enum struct ServerManager {
	ConVar DebugMode;
	ConVar Token;
	ConVar InvLink;
	ConVar ChanID;
	ConVar GuiID;
	ConVar ServerID;
	ConVar UseSWGM;
	ConVar CheckInterval;
	//ConVar MessageInterval;

	char BotToken[60];
	char ChannelID[20];
	char ChannelName[32];
	char GuildID[sizeof(ServerManager::ChannelID)];
	char InviteLink[30];
	DiscordBot Bot;

	void CreateBot(bool guilds = true, bool listen = true) {
		if(strlen(this.BotToken) < 5 && this.DebugMode.BoolValue) {
			PrintToChatAll(" \x07BotToken missing..");
			return;
		}

		this.Bot = new DiscordBot(this.BotToken);
		if(guilds) this.Bot.GetGuilds(GuildList, _, listen);
	}

	void GetGuilds(bool listen = true) {
		if(strlen(this.BotToken) < 5 && this.DebugMode.BoolValue) return;

		if(this.DebugMode.BoolValue) {
			PrintToChatAll(" \x09Looking for guilds..");
		}
			
		if(strlen(this.GuildID) < 5 && this.DebugMode.BoolValue) {
			PrintToChatAll(" \x07GuildID missing..");
			return;
		}
			
		this.Bot.GetGuilds(GuildList, _, listen);
	}
	void ReCreateBot() { this.KillBot(); this.CreateBot(); }
	void SetToken(const char BotToken[60]) { this.BotToken = BotToken; }
	void SetChannel(const char ChannelID[20]) { this.ChannelID = ChannelID; }
	void SetServer(const char GuildID[20]) { this.GuildID = GuildID; }
	void RetrieveMembers() { if(this.DebugMode.BoolValue) { PrintToChatAll(" \x09Refreshing players.."); } AccountsCheck(); }
	void KillBot() { delete this.Bot; }
	
	#pragma deprecated Use ServerManager::KillBot();
	void KillBotEx() { if(this.Bot != null && this.Bot != view_as<DiscordBot>(INVALID_HANDLE)) { /*this.Bot.DestroyData();*/ delete this.Bot; } }
}

ServerManager manager;
PlayerData playerdata[MAXPLAYERS+1];

enum WebHookType {
	Ban,
	Report,
	Comms,
	Map,
	Type_Count,
	Type_Unknown
};

enum RelayType {
	Plain = 1,
	Hook
}

enum struct WebHooks {
	ConVar WebhookEnd[Type_Count];
	ConVar HookColor[Type_Count];
	ConVar HookMention[Type_Count];
	ConVar HookName[Type_Count];

	ConVar AuthorIkon;
	ConVar FooterIkon;
	ConVar HookIkon;

	ConVar MapDelay;

	char AuthorIcon[128];
	char FooterIcon[128];
	char HookIcon[128];

	char MapMention[256];
	char BanMention[256];
	char ReportMention[256];
	char CommsMention[256];

	char MapName[32];
	char BanName[32];
	char ReportName[32];
	char CommsName[32];

	char Report[128];
	char Ban[128];
	char Map[128];
	char Comms[128];

	char MapColor[8];
	char BanColor[8];
	char ReportColor[8];
	char CommsColor[8];

	DiscordWebHook SetupWebHook(char[] endpoint, const char[] name, const char[] avatar)
	{
		DiscordWebHook whook = new DiscordWebHook(endpoint);
		whook.SlackMode = true;
		whook.SetAvatar(avatar);
		whook.SetUsername(StrEqual(name, NULL_STRING)?"Discord Server Manager":name);
		return whook;
	}

	MessageEmbed SetupEmbed(const char[] title = NULL_STRING, const char[] color, const char[] thumbnail)
	{
		MessageEmbed embed = new MessageEmbed();
		embed.SetColor(StrEqual(color, NULL_STRING)?"#FF69B4":color);
		if(strlen(title) > 2) embed.SetTitle(title);
		if(strlen(thumbnail) > 5) embed.SetThumb(thumbnail);
		return embed;
	}

	void SendWebHook(char[] endpoint, WebHookType type, const char[] name = "Discord Server Manager", const char[] title = NULL_STRING, const char[] color = "#FF69B4", const char[] thumbnail = NULL_STRING, any data = 0, const char[] avatar = NULL_STRING)
	{
		if(strlen(endpoint) < 5)
		{
			LogError("Invalid(most likely empty) webhook endpoint (Type-%d)", type);
			if(strlen(endpoint) < 5 && manager.DebugMode.BoolValue) { PrintToChatAll(" \x07Endpoint is missing.."); return; }
			return;
		}

		DiscordWebHook hook = this.SetupWebHook(endpoint, name, avatar);
		MessageEmbed embed = this.SetupEmbed(title, color, thumbnail);

		if(type != Type_Unknown && type != Map)
		{
			StringMap mp = data;
			int client, target, time, commtype;
			char reason[128];
			mp.GetValue("admin", client);
			mp.GetValue("target", target);
			mp.GetString("reason", reason, sizeof(reason));
			if(type != Report) mp.GetValue("time", time);
			if(type == Comms) mp.GetValue("commtype", commtype);
			delete mp;

			char szAdminName[256];
			char szTargetName[256];
			char szAuthorName[256];
			char szBuffer[128];
			char szAuthId[20];
			char szAuthId64[20];
			char szTitleLink[128];

			if(IsValidClient(client)) GetClientName(client, szAdminName, sizeof(szAdminName));
			else Format(szAdminName, sizeof(szAdminName), "SYSTEM");
			GetClientName(target, szTargetName, sizeof(szTargetName));
			szAuthorName = szTargetName;

			GetClientAuthId(client, AuthId_Steam2, szAuthId, sizeof(szAuthId));
			GetClientAuthId(target, AuthId_Steam2, szAuthId, sizeof(szAuthId));
			GetClientAuthId(target, AuthId_SteamID64, szAuthId64, sizeof(szAuthId64));
			Format(szAdminName, sizeof(szAdminName), "%s (%s)", szAdminName, szAuthId);
			Format(szTargetName, sizeof(szTargetName), "%s (%s)", szTargetName, szAuthId);
			Format(szTitleLink, sizeof(szTitleLink), "https://steamcommunity.com/profiles/%s", szAuthId64);
			if(strlen(reason) < 2) Format(reason, sizeof(reason), "%T", "Modules.WebHook.NoReason", LANG_SERVER);

			if(time > 0) Format(szBuffer, sizeof szBuffer, "%T", "Modules.WebHook.LengthTime", LANG_SERVER, time);
			else if(time < 0) Format(szBuffer, sizeof szBuffer, "%T", "Modules.WebHook.LengthTemp", LANG_SERVER);
			else Format(szBuffer, sizeof szBuffer, "%T", "Modules.WebHook.LengthPerm", LANG_SERVER);

			embed.SetAuthorIcon(this.AuthorIcon);
			embed.SetAuthor(szAuthorName);
			embed.SetAuthorLink(szTitleLink);
			Format(szTranslationBuffer, sizeof(szTranslationBuffer), "%T", type==Report?"Modules.WebHook.Player":"Modules.WebHook.AdminField", LANG_SERVER);
			embed.AddField(szTranslationBuffer, szAdminName, true);
			Format(szTranslationBuffer, sizeof(szTranslationBuffer), "%T", "Modules.WebHook.TargetField", LANG_SERVER);
			embed.AddField(szTranslationBuffer, szTargetName, true);
			if(type != Report) {
				Format(szTranslationBuffer, sizeof(szTranslationBuffer), "%T", "Modules.WebHook.LengthField", LANG_SERVER);
				embed.AddField(szTranslationBuffer, szBuffer, false);
			}
			
			if(type == Comms)
			{
				char cType[32];
				this.GetCommType(cType, sizeof cType, commtype);
				Format(szTranslationBuffer, sizeof(szTranslationBuffer), "%T", "Modules.WebHook.TypeField", LANG_SERVER);
				embed.AddField(szTranslationBuffer, cType, true);
			}

			Format(szTranslationBuffer, sizeof(szTranslationBuffer), "%T", "Modules.WebHook.ReasonField", LANG_SERVER);
			embed.AddField(szTranslationBuffer, reason, false);
			embed.SetFooter(sHostname);
			embed.SetFooterIcon(this.FooterIcon);
		} else if(type == Map) {
			char szMap[64];
			char szPlayers[10];
			char szLink[128];

			GetCurrentMap(szMap, sizeof szMap);
			Format(szLink, sizeof(szLink), "steam://connect/%s", GetServerAdress());
			Format(szPlayers, sizeof(szPlayers), "%i/%i", GetRealClientCount(), GetMaxHumanPlayers());
			Format(szTranslationBuffer, sizeof(szTranslationBuffer), "%T", "Modules.WebHook.CurrentMapField", LANG_SERVER);
			embed.AddField(szTranslationBuffer, szMap, true);
			Format(szTranslationBuffer, sizeof(szTranslationBuffer), "%T", "Modules.WebHook.PlayersOnlineField", LANG_SERVER);
			embed.AddField(szTranslationBuffer, szPlayers, true);
			Format(szTranslationBuffer, sizeof(szTranslationBuffer), "%T", "Modules.WebHook.DirectConnectField", LANG_SERVER);
			embed.AddField(szTranslationBuffer, szLink, false);
		} else { LogError("Invalid WebHookType"); }

		hook.Embed(embed);

		char szMention[128];
		this.GetMentions(szMention, sizeof(szMention), type);
		if(strlen(szMention) > 5) hook.SetContent(szMention);
		hook.Send();
		delete hook;
	}

	void GetCommType(char[] sBuffer, int iBufferSize, int iType)
	{
		switch(iType)
		{
			case TYPE_MUTE: strcopy(sBuffer, iBufferSize, "Mute");
			case TYPE_GAG: strcopy(sBuffer, iBufferSize, "Gag");
			case TYPE_SILENCE: strcopy(sBuffer, iBufferSize, "Silence");
		}
	}

	void GetMentions(char[] buffer, int maxsize, WebHookType type)
	{
		switch(type)
		{
			case Map: strcopy(buffer, maxsize, this.MapMention);
			case Ban: strcopy(buffer, maxsize, this.BanMention);
			case Report: strcopy(buffer, maxsize, this.ReportMention);
			case Comms: strcopy(buffer, maxsize, this.CommsMention);
		}
	}
}

enum struct ChatRelay {
	ConVar ChatRelayType;
	ConVar ChatRelayHook;
	ConVar ChatRelayChannel;
	ConVar ChatRelayToServer;
	ConVar ChatRelayPrefix;

	ConVar SteamApiKey;

	char RelayChannel[20];
	char ChannelName[32];
	char RelayPrefix[128];
	char RelayHook[128];
	char ApiKey[64];

	Regex regex;

	void SendToDiscord(int client, RelayType type, const char[] message, int maxlength = 512, bool timestamp = true)
	{
		if(strlen(this.RelayHook) < 5 && manager.DebugMode.BoolValue) { PrintToChatAll(" \x07RelayHook endpoint is missing.."); return; }
		char[] sMessage = new char[maxlength];
		char[] szSafeText = new char[maxlength];
		char szPlayerName[MAX_NAME_LENGTH+1];
		char szTimestamp[32];

		GetClientName(client, szPlayerName, sizeof(szPlayerName));
		TrimString(szPlayerName);

		FormatEx(sMessage, maxlength, message);
		MakeStringSafe(sMessage, szSafeText, maxlength);

		this.RemoveColors(szSafeText, maxlength);
		this.RemoveColors(szPlayerName, sizeof(szPlayerName));

		if(timestamp) FormatTime(szTimestamp, sizeof(szTimestamp), "[%I:%M:%S %p] ", GetTime());

		switch(type)
		{
			case Plain: { FormatEx(sMessage, maxlength, "**%s%s: %s**", timestamp?szTimestamp:NULL_STRING, szPlayerName, szSafeText); manager.Bot.SendMessageToChannelID(this.RelayChannel, sMessage); }
			case Hook: {
				if(this.regex.Match(szPlayerName) > 0 || strlen(szPlayerName) < 2) {
					Format(szTranslationBuffer, sizeof(szTranslationBuffer), "%T", "Modules.ChatRelay.InvalidName", LANG_SERVER);
					strcopy(szPlayerName, MAX_NAME_LENGTH, szTranslationBuffer);
				} else strcopy(szPlayerName, MAX_NAME_LENGTH, szPlayerName);

				DiscordWebHook hook = new DiscordWebHook(this.RelayHook);
				hook.SlackMode = true;
				hook.SetUsername(szPlayerName);
				hook.SetAvatar(playerdata[client].AvatarUrl);
				Format(szSafeText, maxlength+32, "%s%s", szTimestamp, szSafeText);
				hook.SetContent(szSafeText);
				hook.Send();
				delete hook;
			}

			default: { LogError("Invalid RelayType"); }
		}
	}

	void RemoveColors(char[] message, int maxlength) { for(int i = 0; i < 19; i++) ReplaceString(message, maxlength, szColorList[i], "", false); }
}

enum struct Modules {
	ConVar Verification;
	ConVar ChatRelay;
	ConVar WebHooks;
	bool ChatProcessor;
	bool SourceBans;
	bool SourceComms;

	WebHooks webhook;
	ChatRelay relay;
}

char g_szTableName[32], g_szLinkCommand[20], g_szPrefix[100], g_szViewIdCommand[20];
ConVar g_cDataTable, g_cDatabase, g_cLinkCommand, g_cViewIdCommand, g_cPrefix;
Database g_DB;

Handle hRateLimit = null;
Handle hRateReset = null;
Handle hRateLeft = null;

GlobalForward g_hOnLinkedAccount = null;
GlobalForward g_hOnCheckedAccounts = null;

Modules modules;

public void OnPluginEnd() { manager.KillBot(); }
public void OnMapEnd() { /*manager.KillBot();*/ }
public void OnMapStart() { CreateTimer(manager.CheckInterval.FloatValue, VerifyAccounts, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); CreateTimer(modules.webhook.MapDelay.FloatValue, Timer_SendMap, _, TIMER_FLAG_NO_MAPCHANGE); }
public int HTTPCompleted(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statuscode, any data, any data2) {}
public Action VerifyAccounts(Handle timer) { manager.RetrieveMembers(); }
static stock bool IsDiscordMember(Jatekos jatekos) { return playerdata[jatekos.index].Member; }
public int Native_IsDiscordMember(Handle plugin, int params) { return playerdata[GetNativeCell(1)].Member; }
public int Native_RefreshClients(Handle plugin, int params) { RefreshClients(); }
public Action SendGetMembers(Handle timer, any data) { GetMembers(view_as<Handle>(data)); }
public Action Command_Recreate(int client, int args) { manager.ReCreateBot(); return Plugin_Handled; }
public void RefreshClients() { for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i)) OnClientPostAdminCheck(i); }
public void SQLHibaKereso(Handle owner, Handle hndl, const char[] error, any data) { if(!StrEqual(error, "")) LogError(error); }
public void GuildList(DiscordBot bot, char[] id, char[] name, char[] icon, bool owner, int permissions, const bool listen) { if(manager.DebugMode.BoolValue) { PrintToChatAll(" \x04Found guild: %s %s", id, name); PrintToChatAll(" \x09Looking for channels.."); } manager.Bot.GetGuildChannels(id, ChannelList, INVALID_FUNCTION, listen); }
public void OnPluginStart()
{
	manager.DebugMode = CreateConVar("discord_manager_debug", "1", "Debug mode");
	manager.Token = CreateConVar("discord_manager_bot_token", "", "Bot token", FCVAR_PROTECTED);
	manager.InvLink = CreateConVar("discord_manager_invite_link", "https://discord.gg/HpB5NE", "Invite link for your discord server");

	manager.ChanID = CreateConVar("discord_manager_channel_id", "", "Channel ID");
	manager.GuiID = CreateConVar("discord_manager_guild_id", "", "Guild ID");
	manager.ServerID = CreateConVar("discord_manager_server_id", "1", "If you have got multiple servers increment this value on each server by one");
	manager.UseSWGM = CreateConVar("discord_manager_use_swgm", "0", "Use the same .ini file with SWGM");
	//manager.MessageInterval = CreateConVar("discord_manager_message_interval", "1.0", "Time between check for messages"); unused
	manager.CheckInterval = CreateConVar("discord_manager_check_interval", "300.0", "Time between verify accounts");
	
	g_cDatabase = CreateConVar("discord_manager_database", "dsm", "Section name in databases.cfg");
	g_cDataTable = CreateConVar("discord_manager_table", "discord_users", "Database table name");
	g_cLinkCommand = CreateConVar("discord_manager_link_command", "!link", "Command to use in the textchannel");
	g_cViewIdCommand = CreateConVar("discord_manager_viewid_command", "sm_viewid", "Command for viewid");
	g_cPrefix = CreateConVar("discord_manager_prefix", "{default}[{red}DSM{default}]", "Prefix in chat messages");

	modules.Verification = CreateConVar("discord_modules_verification", "1", "Verification module");
	modules.ChatRelay = CreateConVar("discord_modules_chatrelay", "1", "ChatRelay module");
	modules.WebHooks = CreateConVar("discord_modules_webhooks", "1", "Webhooks module");

	modules.webhook.WebhookEnd[Map] = CreateConVar("discord_webhook_map", "", "Discord web hook endpoint for mapstart forward, Leave it empty to disable", FCVAR_PROTECTED);
	modules.webhook.WebhookEnd[Ban] = CreateConVar("discord_webhook_ban", "", "Discord web hook endpoint for ban forward, Leave it empty to disable", FCVAR_PROTECTED);
	modules.webhook.WebhookEnd[Report] = CreateConVar("discord_webhook_report", "", "Discord web hook endpoint for report forward, Leave it empty to disable", FCVAR_PROTECTED);
	modules.webhook.WebhookEnd[Comms] = CreateConVar("discord_webhook_comms", "", "Discord web hook endpoint for comms forward, Leave it empty to disabled", FCVAR_PROTECTED);

	modules.webhook.HookColor[Map] = CreateConVar("discord_webhook_map_color", "#30ED13", "Embed message color for map webhook, If left empty, #FF69B4 will be used instead.");
	modules.webhook.HookColor[Ban] = CreateConVar("discord_webhook_ban_color", "#FF69B4", "Embed message color for ban webhook, If left empty, #FF69B4 will be used instead.");
	modules.webhook.HookColor[Report] = CreateConVar("discord_webhook_report_color", "#EBEB13", "Embed message color for report webhook, If left empty, #FF69B4 will be used instead.");
	modules.webhook.HookColor[Comms] = CreateConVar("discord_webhook_comms_color", "#0E40E6", "Embed message color for comms webhook, If left empty, #FF69B4 will be used instead.");

	modules.webhook.AuthorIkon = CreateConVar("discord_webhook_author_icon", "https://cdn.discordapp.com/icons/697171677041393714/a9bd4eaafff5e7cf3f606c14c600b862.png", "Author icon");
	modules.webhook.FooterIkon = CreateConVar("discord_webhook_footer_icon", "https://cdn.discordapp.com/icons/697171677041393714/a9bd4eaafff5e7cf3f606c14c600b862.png", "Footer icon");
	modules.webhook.HookIkon = CreateConVar("discord_webhook_icon", "https://cdn.discordapp.com/icons/697171677041393714/a9bd4eaafff5e7cf3f606c14c600b862.png", "Webhook icon");

	modules.webhook.HookName[Map] = CreateConVar("discord_webhook_map_name", "Discord Server Manager", "Webhook name for map webhook, If left empty 'Discord Server Manager' will be used instead");
	modules.webhook.HookName[Ban] = CreateConVar("discord_webhook_ban_name", "Discord Server Manager", "Webhook name for ban webhook, If left empty 'Discord Server Manager' will be used instead");
	modules.webhook.HookName[Report] = CreateConVar("discord_webhook_report_name", "Discord Server Manager", "Webhook name for report webhook, If left empty 'Discord Server Manager' will be used instead");
	modules.webhook.HookName[Comms] = CreateConVar("discord_webhook_comms_name", "Discord Server Manager", "Webhook name for comms webhook, If left empty 'Discord Server Manager' will be used instead");

	modules.webhook.HookMention[Map] = CreateConVar("discord_webhook_map_mention", "<@&697333844025671770> @everyone", "Mention these roles with map webhook, Leave it empty to disable");
	modules.webhook.HookMention[Ban] = CreateConVar("discord_webhook_ban_mention", "<@&697333844025671770>", "Mention these roles with ban webhook, Leave it empty to disable");
	modules.webhook.HookMention[Report] = CreateConVar("discord_webhook_report_mention", "<@&697333844025671770>", "Mention these roles with report webhook, Leave it empty to disable");
	modules.webhook.HookMention[Comms] = CreateConVar("discord_webhook_comms_mention", "<@&697333844025671770>", "Mention these roles with comms webhook, Leave it empty to disable");

	modules.relay.ChatRelayChannel = CreateConVar("discord_chatrelay_channel_id", "697871331961864262", "Relay Channel ID");
	modules.relay.ChatRelayType = CreateConVar("discord_chatrelay_type", "2", "1 = plain name and message (bot) | 2 = Steam avatar+playername+message (webhook)");
	modules.relay.ChatRelayHook = CreateConVar("discord_chatrelay_hook", "", "Discord web hook endpoint for chatrelay", FCVAR_PROTECTED);
	modules.relay.ChatRelayToServer = CreateConVar("discord_chatrelay_toserver", "1", "Print discord messages ingame");
	modules.relay.ChatRelayPrefix = CreateConVar("discord_chatrelay_prefix", "{grey}[{red}ANNOUNCEMENT{grey}] >>{default}", "Discord message prefix");
	
	modules.relay.SteamApiKey = CreateConVar("discord_steam_api_key", "", "Steam API Key ( https://steamcommunity.com/dev/apikey )", FCVAR_PROTECTED);
	modules.webhook.MapDelay = CreateConVar("disord_webhook_map_delay", "30.0", "Seconds to wait after mapstart to send the map webhook");

	char sRegexErr[32];
	RegexError RegexErr;
	modules.relay.regex = CompileRegex(".*(clyde).*", PCRE_CASELESS, sRegexErr, sizeof(sRegexErr), RegexErr);
	if (RegexErr != REGEX_ERROR_NONE) LogError("Could not compile \"Clyde\" regex (err: %s)", sRegexErr);

	LoadCommands();

	LoadTranslations("common.phrases");
	LoadTranslations("dsm.phrases");
	AutoExecConfig(true, "discord_server_manager", "sourcemod");

	hRateLeft = new StringMap();
	hRateReset = new StringMap();
	hRateLimit = new StringMap();

	RegAdminCmd("sm_recreate", Command_Recreate, ADMFLAG_ROOT);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("DSM");
	CreateNative("DSM_IsMember", Native_IsDiscordMember);
	CreateNative("DSM_GetUserId", Native_GetUserId);
	CreateNative("DSM_RefreshClients", Native_RefreshClients);

	g_hOnLinkedAccount = new GlobalForward("DSM_OnLinkedAccount", ET_Ignore, Param_Cell, Param_String, Param_String, Param_String);
	g_hOnCheckedAccounts = new GlobalForward("DSM_OnCheckedAccouts", ET_Event, Param_String, Param_String, Param_String);
	return APLRes_Success;
}

public void OnLibraryAdded(const char[] szLibrary)
{
	if(StrEqual(szLibrary, "sourcebans++")) modules.SourceBans = true;
	else if(StrEqual(szLibrary, "sourcecomms++")) modules.SourceComms = true;
	else if(StrEqual(szLibrary, "chat-processor")) modules.ChatProcessor = true;
}

public void OnLibraryRemoved(const char[] szLibrary)
{
	if(StrEqual(szLibrary, "sourcebans++")) modules.SourceBans = false;
	else if(StrEqual(szLibrary, "sourcecomms++")) modules.SourceComms = false;
	else if(StrEqual(szLibrary, "chat-processor")) modules.ChatProcessor = false;
}

public Action Command_ViewId(int client, int args)
{
	if(!IsValidClient(client)) return Plugin_Handled;
	CPrintToChat(client, "%s %T", g_szPrefix, "Manager.YourID", client, playerdata[client].UniqueCode);
	CPrintToChat(client, "%s %T", g_szPrefix, "Manager.Connect", client, manager.InviteLink);
	CPrintToChat(client, "%s %T", g_szPrefix, "Manager.Usage", client, g_szLinkCommand, playerdata[client].UniqueCode, manager.ChannelName);
	return Plugin_Handled;
}

/*public void OnAllPluginsLoaded() {
	if(manager.Bot != view_as<DiscordBot>(INVALID_HANDLE)) return;

	char token[60];
	manager.Token.GetString(token, sizeof(token));
	manager.SetToken(token);
	manager.CreateBot(false, false);
	//manager.Bot.MessageCheckInterval = g_cMessageInterval.FloatValue; Changing the value returns invalid handle, anyway the default value is 1.0
}*/

public void OnConfigsExecuted()
{
	FindConVar("hostname").GetString(sHostname, sizeof(sHostname));

	manager.Token.GetString(manager.BotToken, sizeof(ServerManager::BotToken));
	manager.ChanID.GetString(manager.ChannelID, sizeof(ServerManager::ChannelID));
	manager.GuiID.GetString(manager.GuildID, sizeof(ServerManager::GuildID));
	manager.InvLink.GetString(manager.InviteLink, sizeof(ServerManager::InviteLink));

	g_cLinkCommand.GetString(g_szLinkCommand, sizeof(g_szLinkCommand));
	g_cViewIdCommand.GetString(g_szViewIdCommand, sizeof(g_szViewIdCommand));
	g_cPrefix.GetString(g_szPrefix, sizeof(g_szPrefix));

	if(manager.Bot == view_as<DiscordBot>(INVALID_HANDLE)) { RegConsoleCmd(g_szViewIdCommand, Command_ViewId);  manager.CreateBot(); }

	modules.webhook.WebhookEnd[Map].GetString(modules.webhook.Map, sizeof(WebHooks::Map));
	modules.webhook.WebhookEnd[Ban].GetString(modules.webhook.Ban, sizeof(WebHooks::Ban));
	modules.webhook.WebhookEnd[Comms].GetString(modules.webhook.Comms, sizeof(WebHooks::Comms));
	modules.webhook.WebhookEnd[Report].GetString(modules.webhook.Report, sizeof(WebHooks::Report));

	modules.webhook.HookColor[Map].GetString(modules.webhook.MapColor, sizeof(WebHooks::MapColor));
	modules.webhook.HookColor[Ban].GetString(modules.webhook.BanColor, sizeof(WebHooks::BanColor));
	modules.webhook.HookColor[Report].GetString(modules.webhook.ReportColor, sizeof(WebHooks::ReportColor));
	modules.webhook.HookColor[Comms].GetString(modules.webhook.CommsColor, sizeof(WebHooks::CommsColor));

	modules.webhook.AuthorIkon.GetString(modules.webhook.AuthorIcon, sizeof(WebHooks::AuthorIcon));
	modules.webhook.FooterIkon.GetString(modules.webhook.FooterIcon, sizeof(WebHooks::FooterIcon));
	modules.webhook.HookIkon.GetString(modules.webhook.HookIcon, sizeof(WebHooks::HookIcon));

	modules.webhook.HookName[Map].GetString(modules.webhook.MapName, sizeof(WebHooks::MapName));
	modules.webhook.HookName[Ban].GetString(modules.webhook.BanName, sizeof(WebHooks::BanName));
	modules.webhook.HookName[Report].GetString(modules.webhook.ReportName, sizeof(WebHooks::ReportName));
	modules.webhook.HookName[Comms].GetString(modules.webhook.CommsName, sizeof(WebHooks::CommsName));

	modules.webhook.HookMention[Map].GetString(modules.webhook.MapMention, sizeof(WebHooks::MapMention));
	modules.webhook.HookMention[Ban].GetString(modules.webhook.BanMention, sizeof(WebHooks::BanMention));
	modules.webhook.HookMention[Report].GetString(modules.webhook.ReportMention, sizeof(WebHooks::ReportMention));
	modules.webhook.HookMention[Comms].GetString(modules.webhook.CommsMention, sizeof(WebHooks::CommsMention));

	modules.relay.SteamApiKey.GetString(modules.relay.ApiKey, sizeof(ChatRelay::ApiKey));
	modules.relay.ChatRelayChannel.GetString(modules.relay.RelayChannel, sizeof(ChatRelay::RelayChannel));
	modules.relay.ChatRelayHook.GetString(modules.relay.RelayHook, sizeof(ChatRelay::RelayHook));
	modules.relay.ChatRelayPrefix.GetString(modules.relay.RelayPrefix, sizeof(ChatRelay::RelayPrefix));

	char _error[255];
	char _db[32];
	g_cDatabase.GetString(_db, sizeof(_db));
	g_cDataTable.GetString(g_szTableName, sizeof(g_szTableName));
	g_DB = SQL_Connect(_db, true, _error, sizeof(_error));
	
	char createTableQuery[4096];
	Format(createTableQuery, sizeof(createTableQuery), 
		"CREATE TABLE IF NOT EXISTS `%s` ( \
 		`ID` bigint(20) NOT NULL AUTO_INCREMENT, \
  		`userid` varchar(20) COLLATE utf8_bin NOT NULL, \
  		`steamid` varchar(20) COLLATE utf8_bin NOT NULL, \
  		`member` int(20) NOT NULL, \
		`checked` int(20) NOT NULL, \
 		 PRIMARY KEY (`ID`), \
  		 UNIQUE KEY `steamid` (`steamid`)  \
  		 ) ENGINE = InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=utf8 COLLATE=utf8_bin;", g_szTableName);

	SQL_TQuery(g_DB, SQLHibaKereso, createTableQuery);

	for (int i = 1; i <= MaxClients; ++i)
    {
    	if(!IsValidClient(i)) continue;
    	OnClientPostAdminCheck(i);
    }
}

public void OnClientPostAdminCheck(int client)
{
	if(!IsValidClient(client)) return;
	playerdata[client].UserID = "\0";
	playerdata[client].UniqueCode = "\0";
	playerdata[client].AvatarUrl = "\0";
	playerdata[client].Member = false;

	char szSteamId[20];
	GetClientAuthId(client, AuthId_Steam2, szSteamId, sizeof(szSteamId));

	char Query[512];
	Format(Query, sizeof(Query), "SELECT userid, member FROM %s WHERE steamid = '%s';", g_szTableName, szSteamId);
	SQL_TQuery(g_DB, GetUserData, Query, view_as<Jatekos>(client));

	if(view_as<RelayType>(modules.relay.ChatRelayType.IntValue) == Hook)
	{
		if(strlen(modules.relay.ApiKey) < 5 && manager.DebugMode.BoolValue) {
			PrintToChatAll(" \x07SteamAPI Key missing..");
			return;
		}
		char szSteamID64[32];
		if(!GetClientAuthId(client, AuthId_SteamID64, szSteamID64, sizeof(szSteamID64))) return;

		static char sRequest[256];
		FormatEx(sRequest, sizeof(sRequest), "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s&format=vdf", modules.relay.ApiKey, szSteamID64);
		Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sRequest);
		if(!hRequest || !SteamWorks_SetHTTPRequestContextValue(hRequest, client) || !SteamWorks_SetHTTPCallbacks(hRequest, OnTransferCompleted) || !SteamWorks_SendHTTPRequest(hRequest)) delete hRequest;
	}
}

public void GetUserData(Handle owner, Handle hndl, const char[] error, Jatekos jatekos)
{
	if(!jatekos.IsValid) return;
	if(SQL_GetRowCount(hndl) == 0)
	{
		char szSteamId[20];
		jatekos.GetAuthId(AuthId_Steam2, szSteamId, sizeof(szSteamId));

		char Query[256];
		Format(Query, sizeof(Query), "INSERT INTO `%s` (ID, steamid) VALUES (NULL, '%s');", g_szTableName, szSteamId);
		SQL_TQuery(g_DB, SQLHibaKereso, Query);

		OnClientPostAdminCheck(jatekos.index);
		return;
	}

	while (SQL_FetchRow(hndl))
	{
		SQL_FetchString(hndl, 0, playerdata[jatekos.index].UserID, sizeof(PlayerData::UserID));
		playerdata[jatekos.index].Member = view_as<bool>(SQL_FetchInt(hndl, 1));
	}

	char szSteamId64[20];
	jatekos.GetAuthId(AuthId_SteamID64, szSteamId64, sizeof(szSteamId64));
	if(manager.ServerID.IntValue > 1) Format(playerdata[jatekos.index].UniqueCode, sizeof(PlayerData::UniqueCode), "%i-%s", manager.ServerID.IntValue, szSteamId64);
	else Format(playerdata[jatekos.index].UniqueCode, sizeof(PlayerData::UniqueCode), "%s", szSteamId64);
}

stock int OnTransferCompleted(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int client)
{
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		LogError("SteamAPI HTTP Response failed: %d", eStatusCode);
		if(manager.DebugMode.BoolValue) { PrintToChatAll(" \x07SteamAPI HTTP Response failed: %d", eStatusCode); return; }
		delete hRequest;
		return;
	}

	int iBodyLength;
	SteamWorks_GetHTTPResponseBodySize(hRequest, iBodyLength);

	char[] sData = new char[iBodyLength];
	SteamWorks_GetHTTPResponseBodyData(hRequest, sData, iBodyLength);

	delete hRequest;
	
	APIWebResponse(sData, client);
}

stock void APIWebResponse(const char[] sData, int client)
{
	KeyValues kvResponse = new KeyValues("SteamAPIResponse");

	if (!kvResponse.ImportFromString(sData, "SteamAPIResponse"))
	{
		LogError("kvResponse.ImportFromString(\"SteamAPIResponse\") in APIWebResponse failed.");
		if(manager.DebugMode.BoolValue) { PrintToChatAll(" \x07kvResponse.ImportFromString(\"SteamAPIResponse\") in APIWebResponse failed."); return; }

		delete kvResponse;
		return;
	}

	if (!kvResponse.JumpToKey("players"))
	{
		LogError("kvResponse.JumpToKey(\"players\") in APIWebResponse failed.");
		if(manager.DebugMode.BoolValue) { PrintToChatAll(" \x07kvResponse.JumpToKey(\"players\") in APIWebResponse failed."); return; }

		delete kvResponse;
		return;
	}

	if (!kvResponse.GotoFirstSubKey())
	{
		LogError("kvResponse.GotoFirstSubKey() in APIWebResponse failed.");
		if(manager.DebugMode.BoolValue) { PrintToChatAll(" \x07kvResponse.GotoFirstSubKey() in APIWebResponse failed."); return; }

		delete kvResponse;
		return;
	}

	kvResponse.GetString("avatarfull", playerdata[client].AvatarUrl, sizeof(PlayerData::AvatarUrl));
	delete kvResponse;
}

public void CP_OnChatMessagePost(int author, ArrayList recipients, const char[] flagstring, const char[] formatstring, const char[] name, const char[] message)
{
	if(!modules.ChatRelay.BoolValue) return;
	if(!modules.ChatProcessor) return;
	if(message[0] == '!' || message[1] == '!') return;

	modules.relay.SendToDiscord(author, view_as<RelayType>(modules.relay.ChatRelayType.IntValue), message);
}

public int Native_GetUserId(Handle plugin, int params)
{
	if(!IsDiscordMember(view_as<Jatekos>(GetNativeCell(1))))
		return ThrowNativeError(25, "%N isn't verified", GetNativeCell(1));
		
	SetNativeString(2, playerdata[GetNativeCell(1)].UserID, GetNativeCell(3));
	return 0;
}

public void ChannelList(DiscordBot bot, const char[] guild, DiscordChannel Channel, const bool listen)
{
	char name[32];
	char id[20];
	Channel.GetID(id, sizeof(id));
	Channel.GetName(name, sizeof(name));
	if(strlen(manager.ChannelID) > 10 || strlen(modules.relay.RelayChannel) > 10) //ChannelID size is around 18-20 char
	{
		if(StrEqual(id, manager.ChannelID))
		{
			manager.ChannelName = name;
			if(manager.DebugMode.BoolValue) {
				PrintToChatAll(" \x04Found channel #%s (%s)", name, id);
				if(strlen(g_szLinkCommand) > 2) PrintToChatAll(" \x04Verification command: %s", g_szLinkCommand);
				else PrintToChatAll(" \x07Verification command was not set!");
			}
			
			if(listen)
			{
				manager.Bot.StopListeningToChannel(Channel);
				manager.Bot.StartListeningToChannel(Channel, OnMessageReceived);
			}
		} else if(StrEqual(id, modules.relay.RelayChannel))
		{
			modules.relay.ChannelName = name;
			if(manager.DebugMode.BoolValue) {
				PrintToChatAll(" \x04Found channel #%s (%s)", name, id);

				RelayType type = view_as<RelayType>(modules.relay.ChatRelayType.IntValue);
				switch(type)
				{
					case Plain: PrintToChatAll(" \x04ChatRelay Type: Plain");
					case Hook: PrintToChatAll(" \x04ChatRelay Type: Hook");
					default: PrintToChatAll(" \x07ChatRelay Type: Unknown");
				}
			}
			if(modules.relay.ChatRelayToServer.BoolValue)
			{
				manager.Bot.StopListeningToChannel(Channel);
				manager.Bot.StartListeningToChannel(Channel, ChatRelayReceived);
			}
		}
	} else {
		if(manager.DebugMode.BoolValue) { PrintToChatAll(" \x07You must specify a Channel ID"); }
	}
}

public void ChatRelayReceived(DiscordBot bot, DiscordChannel channel, DiscordMessage discordmessage)
{
	if(discordmessage.GetAuthor().IsBot()) return;

	char message[512];
	char userName[32], discriminator[6];
	discordmessage.GetContent(message, sizeof(message));
	discordmessage.GetAuthor().GetUsername(userName, sizeof(userName));
	discordmessage.GetAuthor().GetDiscriminator(discriminator, sizeof(discriminator));

	CPrintToChatAll("%s %s#%s: %s", modules.relay.RelayPrefix, userName, discriminator, message);
}

public void OnMessageReceived(DiscordBot bot, DiscordChannel channel, DiscordMessage discordmessage)
{
	if(discordmessage.GetAuthor().IsBot()) return;

	char szValues[2][99];
	char szReply[512];
	char message[512];
	char userID[20], userName[32], discriminator[6];

	discordmessage.GetContent(message, sizeof(message));
	discordmessage.GetAuthor().GetUsername(userName, sizeof(userName));
	discordmessage.GetAuthor().GetDiscriminator(discriminator, sizeof(discriminator));
	discordmessage.GetAuthor().GetID(userID, sizeof(userID));

	ExplodeString(message, " ", szValues, sizeof(szValues), sizeof(szValues[]));

	if(StrEqual(szValues[0], g_szLinkCommand))
	{
		if(manager.ServerID.IntValue > 1)
		{
			char _szValues[2][50];
			ExplodeString(szValues[1], "-", _szValues, sizeof(_szValues), sizeof(_szValues[]));
			if(StringToInt(_szValues[0]) != manager.ServerID.IntValue) return; //Prevent multiple replies from the bot (for e.g. the plugin is installed on more than 1 server and they're using the same bot & channel)
		}

		Jatekos jatekos = GetJatekosFromUniqueCode(szValues[1]);
		if(!jatekos.IsValid)
		{
			Format(szReply, sizeof(szReply), "%T", "Manager.Invalid", LANG_SERVER, userID);
			manager.Bot.SendMessage(channel, szReply);
		} else {
			DataPack datapack = new DataPack();
			datapack.WriteCell(jatekos);
			datapack.WriteString(userID);
			datapack.WriteString(userName);
			datapack.WriteString(discriminator);
			//datapack.WriteString(messageID);

			char szSteamId[20];
			jatekos.GetAuthId(AuthId_Steam2, szSteamId, sizeof(szSteamId));

			char Query[512];
			Format(Query, sizeof(Query), "SELECT userid FROM %s WHERE steamid = '%s';", g_szTableName, szSteamId);
			SQL_TQuery(g_DB, CheckUserData, Query, datapack);
		}
	} else {
		if(manager.ServerID.IntValue == 1)
		{
			Format(szReply, sizeof(szReply), "%T", "Manager.Info", LANG_SERVER, userID, g_szLinkCommand);
			manager.Bot.SendMessage(channel, szReply);
		}
	}
}

public void CheckUserData(Handle owner, Handle hndl, const char[] error, DataPack pack)
{
	char szUserIdDb[20];
	while (SQL_FetchRow(hndl)) {
		SQL_FetchString(hndl, 0, szUserIdDb, sizeof(szUserIdDb));
	}

	char szUserId[20], szUserName[32], szDiscriminator[6]/*, szMessageId[20]*/;
	ResetPack(pack);
	Jatekos jatekos = pack.ReadCell();
	pack.ReadString(szUserId, sizeof(szUserId));
	pack.ReadString(szUserName, sizeof(szUserName));
	pack.ReadString(szDiscriminator, sizeof(szDiscriminator));
	//pack.ReadString(szMessageId, sizeof(szMessageId));
	delete pack;

	char szReply[512];
	if(!StrEqual(szUserIdDb, szUserId))
	{
		CPrintToChat(jatekos.index, "%s %T", g_szPrefix, "Manager.Verified", jatekos.index, szUserName, szDiscriminator);
		playerdata[jatekos.index].Member = true;

		Format(playerdata[jatekos.index].UserID, sizeof(PlayerData::UserID), szUserId);
		Format(szReply, sizeof(szReply), "%T", "Manager.Linked", LANG_SERVER, szUserId);
		manager.Bot.SendMessageToChannelID(manager.ChannelID, szReply);
		//manager.Bot.AddReactionID(manager.ChannelID, szMessageId, ":white_check_mark:"); // error

		char szSteamId[20];
		jatekos.GetAuthId(AuthId_Steam2, szSteamId, sizeof(szSteamId));

		char Query[512];
		Format(Query, sizeof(Query), "UPDATE `%s` SET `userid` = '%s', member = 1 WHERE `%s`.`steamid` = '%s';", g_szTableName, szUserId, g_szTableName, szSteamId);
		SQL_TQuery(g_DB, SQLHibaKereso, Query);

		Call_StartForward(g_hOnLinkedAccount);
		Call_PushCell(jatekos.index);
		Call_PushString(szUserId);
		Call_PushString(szUserName);
		Call_PushString(szDiscriminator);
		Call_Finish();
	} else {
		Format(szReply, sizeof(szReply), "%T", "Manager.AlreadyLinked", LANG_SERVER, szUserId);
		manager.Bot.SendMessageToChannelID(manager.ChannelID, szReply);
		//manager.Bot.AddReactionID(manager.ChannelID, szMessageId, ":x:"); // error
	}
}

public void AccountsCheck()
{
	if(strlen(manager.BotToken) < 5 && manager.DebugMode.BoolValue) {
		PrintToChatAll(" \x07BotToken missing.."); 
		return;
	} if(strlen(manager.GuildID) < 5 && manager.DebugMode.BoolValue) {
		PrintToChatAll(" \x07GuildID missing..");
		return;
	}

	Action action = Plugin_Continue;
    Call_StartForward(g_hOnCheckedAccounts);
	Call_PushString(manager.BotToken);
	Call_PushString(manager.GuildID);
	Call_PushString(g_szTableName);
    Call_Finish(action);

    if(action >= Plugin_Handled) return;

	char Query[256];
	Format(Query, sizeof(Query), "UPDATE `%s` SET `checked` = 0 WHERE `%s`.`ID` > 0;", g_szTableName, g_szTableName);
	SQL_TQuery(g_DB, SQLHibaKereso, Query);

	Handle hData = json_object();
	json_object_set_new(hData, "limit", json_integer(1000));
	json_object_set_new(hData, "afterID", json_string(""));
	GetMembers(hData);
}

static void GetMembers(Handle hData = INVALID_HANDLE)
{
	int limit = JsonObjectGetInt(hData, "limit");
	char afterID[32];
	JsonObjectGetString(hData, "afterID", afterID, sizeof(afterID));
	
	char url[256];
	if(StrEqual(afterID, "")) FormatEx(url, sizeof(url), "https://discordapp.com/api/guilds/%s/members?limit=%i", manager.GuildID, limit);
	else FormatEx(url, sizeof(url), "https://discordapp.com/api/guilds/%s/members?limit=%i&afterID=%s", manager.GuildID, limit, afterID);
	
	char route[128];
	FormatEx(route, sizeof(route), "guild/%s/members", manager.GuildID);
	
	DiscordRequest request = new DiscordRequest(url, k_EHTTPMethodGET);
	if(request == null) { CreateTimer(2.0, SendGetMembers, hData); return; }
	request.SetCallbacks(HTTPCompleted, MembersDataReceive);
	request.SetBot(manager.Bot);
	request.SetData(hData, route);
	request.Send(route);
}

public void MembersDataReceive(Handle request, bool failure, int offset, int statuscode, any dp) {
	if(failure || (statuscode != 200)) {
		if(manager.DebugMode.BoolValue) { PrintToChatAll(" \x07Failed to refresh database! (%d-%d) N1", failure, statuscode); }
		if(statuscode == 400) { PrintToServer("BAD REQUEST"); }
		if(statuscode == 429 || statuscode == 500) {
			GetMembers(dp);
			delete request;
			return;
		}
		LogError("[DISCORD] Couldn't Send GetMembers - Fail %i %i", failure, statuscode);
		if(manager.DebugMode.BoolValue) { PrintToChatAll(" \x07Failed to refresh database! (%d-%d) N2", failure, statuscode); }
		delete request;
		delete view_as<Handle>(dp);
		return;
	}
	SteamWorks_GetHTTPResponseBodyCallback(request, GetMembersData, dp);
	delete request;
}

public int GetMembersData(const char[] data, any dp) {
	Handle hJson = json_load(data);
	Handle hData = view_as<Handle>(dp);
	OnGetMembersAll(hJson);
	if(JsonObjectGetBool(hData, "autoPaginate")) {
		int size = json_array_size(hJson);
		int limit = JsonObjectGetInt(hData, "limit");
		if(limit == size) {
			Handle hLast = json_array_get(hJson, size - 1);
			char lastID[32];
			json_string_value(hLast, lastID, sizeof(lastID));
			delete hJson;
			delete hLast;
				
			json_object_set_new(hData, "afterID", json_string(lastID));
			GetMembers(hData);
			return;
		}
	}
	
	delete hJson;
	delete hData;
}

public void OnGetMembersAll(Handle hMemberList)
{
	char Query[256];
	char userid[20];
	DiscordGuildUser GuildUser;
	DiscordUser user;
	for(int i = 0; i < json_array_size(hMemberList); i++) {
		GuildUser = view_as<DiscordGuildUser>(json_array_get(hMemberList, i));
		user = GuildUser.GetUser();
		user.GetID(userid, sizeof(userid));

		Format(Query, sizeof(Query), "UPDATE `%s` SET `checked` = 1 WHERE `%s`.`userid` = '%s';", g_szTableName, g_szTableName, userid);
		SQL_TQuery(g_DB, SQLHibaKereso, Query);
	}

	delete user;
	delete GuildUser;

	Format(Query, sizeof(Query), "DELETE FROM %s WHERE checked = 0;", g_szTableName);
	SQL_TQuery(g_DB, SQLHibaKereso, Query);
	if(manager.DebugMode.BoolValue) { PrintToChatAll(" \x04Database refreshed!"); }
	RefreshClients();
}

public int HeadersReceived(Handle request, bool failure, any data, any datapack) {
	DataPack dp = view_as<DataPack>(datapack);
	if(failure) {
		delete dp;
		return;
	}
	
	char xRateLimit[16];
	char xRateLeft[16];
	char xRateReset[32];
	
	bool exists = false;
	
	exists = SteamWorks_GetHTTPResponseHeaderValue(request, "X-RateLimit-Limit", xRateLimit, sizeof(xRateLimit));
	exists = SteamWorks_GetHTTPResponseHeaderValue(request, "X-RateLimit-Remaining", xRateLeft, sizeof(xRateLeft));
	exists = SteamWorks_GetHTTPResponseHeaderValue(request, "X-RateLimit-Reset", xRateReset, sizeof(xRateReset));
	
	//Get url
	char route[128];
	ResetPack(dp);
	ReadPackString(dp, route, sizeof(route));
	delete dp;
	
	int reset = StringToInt(xRateReset);
	if(reset > GetTime() + 3) {
		reset = GetTime() + 3;
	}
	
	if(exists) {
		SetTrieValue(hRateReset, route, reset);
		SetTrieValue(hRateLeft, route, StringToInt(xRateLeft));
		SetTrieValue(hRateLimit, route, StringToInt(xRateLimit));
	}else {
		SetTrieValue(hRateReset, route, -1);
		SetTrieValue(hRateLeft, route, -1);
		SetTrieValue(hRateLimit, route, -1);
	}
}

public Handle UrlToDP(char[] url) {
	DataPack dp = new DataPack();
	WritePackString(dp, url);
	return dp;
}

stock void BuildAuthHeader(Handle request, DiscordBot Bot) {
	static char buffer[256];
	static char token[196];
	JsonObjectGetString(Bot, "token", token, sizeof(token));
	FormatEx(buffer, sizeof(buffer), "Bot %s", token);
	SteamWorks_SetHTTPRequestHeaderValue(request, "Authorization", buffer);
}

public void DiscordSendRequest(Handle request, const char[] route) {
	//Check for reset
	int time = GetTime();
	int resetTime;
	
	int defLimit = 0;
	if(!GetTrieValue(hRateLimit, route, defLimit)) {
		defLimit = 1;
	}
	
	bool exists = GetTrieValue(hRateReset, route, resetTime);
	
	if(!exists) {
		SetTrieValue(hRateReset, route, GetTime() + 5);
		SetTrieValue(hRateLeft, route, defLimit - 1);
		SteamWorks_SendHTTPRequest(request);
		return;
	}
	
	if(time == -1) {
		//No x-rate-limit send
		SteamWorks_SendHTTPRequest(request);
		return;
	}
	
	if(time > resetTime) {
		SetTrieValue(hRateLeft, route, defLimit - 1);
		SteamWorks_SendHTTPRequest(request);
		return;
	}else {
		int left;
		GetTrieValue(hRateLeft, route, left);
		if(left == 0) {
			float remaining = float(resetTime) - float(time) + 1.0;
			Handle dp = new DataPack();
			WritePackCell(dp, request);
			WritePackString(dp, route);
			CreateTimer(remaining, SendRequestAgain, dp);
		}else {
			left--;
			SetTrieValue(hRateLeft, route, left);
			SteamWorks_SendHTTPRequest(request);
		}
	}
}

public Action SendRequestAgain(Handle timer, any dp) {
	ResetPack(dp);
	Handle request = ReadPackCell(dp);
	char route[128];
	ReadPackString(dp, route, sizeof(route));
	delete view_as<Handle>(dp);
	DiscordSendRequest(request, route);
}

public Action Timer_SendMap(Handle timer)
{
	if(!StrEqual(modules.webhook.Map, NULL_STRING))
	{
		char sMap[32];
		GetCurrentMap(sMap, sizeof(sMap));

		char sThumb[256];
		Format(sThumb, sizeof(sThumb), "https://image.gametracker.com/images/maps/160x120/csgo/%s.jpg", sMap);
		modules.webhook.SendWebHook(modules.webhook.Map, Map, modules.webhook.MapName, sHostname, modules.webhook.MapColor, sThumb, _, modules.webhook.HookIcon);
	}
}

public void LoadCommands()
{
	KeyValues Kv = new KeyValues("Command_Listener");
	
	char sBuffer[256];
	if(!manager.UseSWGM.BoolValue) BuildPath(Path_SM, sBuffer, sizeof(sBuffer), "configs/dsm/command_listener.ini");
	else BuildPath(Path_SM, sBuffer, sizeof(sBuffer), "configs/swgm/command_listener.ini");
	if(!FileToKeyValues(Kv, sBuffer)) SetFailState("Missing config file %s", sBuffer);
	if(Kv.GotoFirstSubKey()) {
		do {
			if(Kv.GetSectionName(sBuffer, sizeof(sBuffer))) AddCommandListener(Check, sBuffer);
		} while (Kv.GotoNextKey());
	}

	delete Kv;
}

public void SBPP_OnBanPlayer(int admin, int target, int time, const char[] reason)
{
	if(!modules.SourceBans) return;
	if(!StrEqual(modules.webhook.Ban, NULL_STRING))
	{
		StringMap things = new StringMap();
		things.SetValue("admin", admin);
		things.SetValue("target", target);
		things.SetValue("time", time);
		things.SetString("reason", reason);

		modules.webhook.SendWebHook(modules.webhook.Ban, Ban, modules.webhook.BanName, _, modules.webhook.BanColor, _, things, modules.webhook.HookIcon);
	}
}

public void SourceComms_OnBlockAdded(int admin, int target, int time, int commtype, char[] reason)
{
	if(!modules.SourceComms) return;
	if(!StrEqual(modules.webhook.Comms, NULL_STRING))
	{
		StringMap things = new StringMap();
		things.SetValue("admin", admin);
		things.SetValue("target", target);
		things.SetValue("time", time);
		things.SetValue("commtype", commtype);
		things.SetString("reason", reason);

		modules.webhook.SendWebHook(modules.webhook.Comms, Comms, modules.webhook.CommsName, _, modules.webhook.CommsColor, _, things, modules.webhook.HookIcon);
	}
}

public void SBPP_OnReportPlayer(int reporter, int target, const char[] reason)
{
	if(!modules.SourceBans) return;
	if(!StrEqual(modules.webhook.Report, NULL_STRING))
	{
		StringMap things = new StringMap();
		things.SetValue("admin", reporter);
		things.SetValue("target", target);
		things.SetString("reason", reason);

		modules.webhook.SendWebHook(modules.webhook.Report, Report, modules.webhook.ReportName, _, modules.webhook.ReportColor, _, things, modules.webhook.HookIcon);
	}
}

public Action Check(int client, const char[] command, int args)
{
	if(!IsValidClient(client)) return Plugin_Continue;
	if(!IsDiscordMember(view_as<Jatekos>(client)))
	{
		CPrintToChat(client, "%s %T", g_szPrefix, "Manager.MustVerify", client, ChangePartsInString(g_szViewIdCommand, "sm_", "!"));
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

static stock Jatekos GetJatekosFromUniqueCode(const char[] unique)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i)) continue;
		if(StrEqual(playerdata[i].UniqueCode, unique)) return Jatekos(i);
	}

	return Jatekos(-1);
}

static stock char ChangePartsInString(char[] input, const char[] from, const char[] to)
{
	char output[64];
	ReplaceString(input, sizeof(output), from, to);
	strcopy(output, sizeof(output), input);
	return output;
}

static stock bool IsValidClient(int client)
{
	if(client <= 0) return false;
	if(client > MaxClients) return false;
	if(!IsClientConnected(client)) return false;
	if(IsFakeClient(client)) return false;
	if(IsClientSourceTV(client)) return false;
	return IsClientInGame(client);
}

static stock int GetRealClientCount()
{
	int count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i)) count++;
	}

	return count;
}

static stock char GetServerAdress()
{
	char sAddress[64];
	int ip[4];
	SteamWorks_GetPublicIP(ip);
	if(SteamWorks_GetPublicIP(ip)) Format(sAddress, sizeof sAddress, "%d.%d.%d.%d:%d", ip[0], ip[1], ip[2], ip[3], FindConVar("hostport").IntValue);
	else {
		int iIPB = FindConVar("hostip").IntValue;
		Format(sAddress, sizeof sAddress, "%d.%d.%d.%d:%d", iIPB >> 24 & 0x000000FF, iIPB >> 16 & 0x000000FF, iIPB >> 8 & 0x000000FF, iIPB & 0x000000FF, FindConVar("hostport").IntValue);
	}

	return sAddress;
}

static stock void MakeStringSafe(const char[] sOrigin, char[] sOut, int iOutSize)
{
	int iDataLen = strlen(sOrigin);
	int iCurIndex;

	for (int i = 0; i < iDataLen && iCurIndex < iOutSize; i++)
	{
		if (sOrigin[i] < 0x20 && sOrigin[i] != 0x0) continue;

		switch (sOrigin[i])
		{
			case '@':
			{
				strcopy(sOut[iCurIndex], iOutSize, "@​");
				iCurIndex += 4;

				continue;
			}
			case '`':
			{
				strcopy(sOut[iCurIndex], iOutSize, "\\`");
				iCurIndex += 2;

				continue;
			}
			case '_':
			{
				strcopy(sOut[iCurIndex], iOutSize, "\\_");
				iCurIndex += 2;

				continue;
			}
			case '~':
			{
				strcopy(sOut[iCurIndex], iOutSize, "\\~");
				iCurIndex += 2;

				continue;
			}
			default:
			{
				sOut[iCurIndex] = sOrigin[i];
				iCurIndex++;
			}
		}
	}
}