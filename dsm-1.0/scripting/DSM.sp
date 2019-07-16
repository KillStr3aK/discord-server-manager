#include <sourcemod>
#include <clientprefs>
#include <discord>
#include <dsm>

#define PLUGIN_NEV	"DSM"
#define PLUGIN_LERIAS	"Discord Server Manager"
#define PLUGIN_AUTHOR	"Nexd"
#define PLUGIN_VERSION	"1.0"
#define PLUGIN_URL	"https://github.com/KillStr3aK"
#pragma tabsize 0

enum
{
	c_DiscordName,
	c_DiscordTag,
	Cookie_Count
}

enum
{
	Bot_Token,
	Channel_ID,
	AssignCommand,
	UseSWGM,
	Settings_Count
}

bool m_Discord[MAXPLAYERS+1];
int assignid[MAXPLAYERS+1];
char assigncommand[32];

Handle Cookies[Cookie_Count] = INVALID_HANDLE;
Handle OnClientLinkedAccount = INVALID_HANDLE;

ConVar DSM_Settings[Settings_Count];
DiscordBot dbot;

public Plugin myinfo = 
{
	name = PLUGIN_NEV,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_LERIAS,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	DSM_Settings[Bot_Token] = CreateConVar("dsm_token", "", "Bot token");
	DSM_Settings[Channel_ID] = CreateConVar("dsm_channel_id", "", "Text channel ID");
	DSM_Settings[AssignCommand] = CreateConVar("dsm_assign_command", "!link", "Command in discord to link the account. eg.( !link 12345 )");
	DSM_Settings[UseSWGM] = CreateConVar("dsm_use_swgm", "0", "1 - Use the same .ini as SWGM for the commands | 0 - Use a new ini (configs/dsm/command_listener.ini)");

	Cookies[c_DiscordName] = RegClientCookie("dsm_discord_name", "discord username", CookieAccess_Private);
	Cookies[c_DiscordTag] = RegClientCookie("dsm_discord_tag", "discord tag", CookieAccess_Private);

	AutoExecConfig(true, "discord_server_manager", "sourcemod");

	RegConsoleCmd("sm_link", Command_Assign);

	for (int i = MaxClients; i > 0; --i)
    {
        if (!AreClientCookiesCached(i))
        {
            continue;
        }
        
        OnClientCookiesCached(i);
    }

    LoadCommands();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("DSM_IsDiscordMember", Native_IsDiscordMember);

	OnClientLinkedAccount = CreateGlobalForward("DSM_OnClientLinkedAccount", ET_Ignore, Param_Cell);

	RegPluginLibrary("DSM"); 

	return APLRes_Success;
}

public void LoadCommands()
{
	KeyValues Kv = new KeyValues("Command_Listener");
	
	char sBuffer[256];
	if(!DSM_Settings[UseSWGM].BoolValue)
		BuildPath(Path_SM, sBuffer, sizeof(sBuffer), "configs/dsm/command_listener.ini");
	else
		BuildPath(Path_SM, sBuffer, sizeof(sBuffer), "configs/swgm/command_listener.ini");

	if (!FileToKeyValues(Kv, sBuffer)) SetFailState("Missing config file %s", sBuffer);
	
	if (Kv.GotoFirstSubKey())
	{
		do
		{
			if (Kv.GetSectionName(sBuffer, sizeof(sBuffer)))
			{
				AddCommandListener(Check, sBuffer);
			}
		} 
		while (Kv.GotoNextKey());
	}
	delete Kv;
}

public Action Check(int client, const char[] command, int args)
{
	if(!IsValidClient(client))
		return Plugin_Continue;

	if(!IsDiscordMember(client))
	{
		PrintToChat(client, "%s You have to link your \x0BDiscord \x01account first. Use \x04!link", PREFIX);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public void OnClientCookiesCached(int client) 
{
	char DiscordName_Value[MAX_USERNAME_LENGTH];
	char DiscordTag_Value[MAX_TAG_LENGTH];
	GetClientCookie(client, Cookies[c_DiscordName], DiscordName_Value, sizeof(DiscordName_Value));
	GetClientCookie(client, Cookies[c_DiscordTag], DiscordTag_Value, sizeof(DiscordTag_Value));

	if(!StrEqual(DiscordName_Value, empty) && !StrEqual(DiscordTag_Value, empty)){
		m_Discord[client] = true;
	} else {
		m_Discord[client] = false;
	}
}

public void OnClientPostAdminCheck(int client)
{
	assignid[client] = GetAssignID();
}

public Action Command_Assign(int client, int args)
{
	if(!m_Discord[client])
	{
		if(!IsValidAssignID(assignid[client]))
		{
			PrintToChat(client, "%s We can't find your assign ID. Please reconnect!", PREFIX); //This could only happen if the plugin was reloaded
		} else {
			PrintToChat(client, "%s Use this command on our discord server: \x04%s \x0C%i", PREFIX, assigncommand, GetClientAssignID(client));
		}
	} else {
		PrintToChat(client, "%s You have already linked your discord account.", PREFIX);
	}

	return Plugin_Handled;
}

public void OnConfigsExecuted()
{
	if (dbot != view_as<DiscordBot>(INVALID_HANDLE))
	{
		dbot.GetGuilds(GuildList, INVALID_FUNCTION);
	}

	GetConVarString(DSM_Settings[AssignCommand], assigncommand, sizeof(assigncommand));
}

public void GuildList(DiscordBot bot, char[] id, char[] name, char[] icon, bool owner, int permissions, any data)
{
	dbot.GetGuildChannels(id, ChannelList, INVALID_FUNCTION);
}

public void ChannelList(DiscordBot bot, char[] guild, DiscordChannel Channel, any data)
{
	if(Channel.IsText) {
		char id[32];
		Channel.GetID(id, sizeof(id));
		
		char sChannelID[64];
		DSM_Settings[Channel_ID].GetString(sChannelID, sizeof(sChannelID));
		
		if(StrEqual(id, sChannelID))
		{
			dbot.StopListening();
			
			char name[32];
			Channel.GetName(name, sizeof(name));
			dbot.StartListeningToChannel(Channel, OnMessage);
		}
	}
}

public void OnMessage(DiscordBot Bot, DiscordChannel Channel, DiscordMessage message)
{
	if (message.GetAuthor().IsBot())
		return;
	
	char sMessage[MAX_DISCORD_MESSAGE_LENGTH];
	char m_Author[MAX_USERNAME_LENGTH];
	char m_dTag[MAX_TAG_LENGTH];
	char ReplyTo[MAX_DISCORD_MESSAGE_LENGTH];
	char userid[32];
	char explodemessage[2][MAX_DISCORD_MESSAGE_LENGTH];

	message.GetContent(sMessage, sizeof(sMessage));
	message.GetAuthor().GetUsername(m_Author, sizeof(m_Author));
	message.GetAuthor().GetDiscriminator(m_dTag, sizeof(m_dTag));
	message.GetAuthor().GetID(userid, sizeof(userid));

	ExplodeString(sMessage, " ", explodemessage, sizeof(explodemessage), sizeof(explodemessage[]));

	if(!StrEqual(explodemessage[0], assigncommand))
	{
		Format(ReplyTo, sizeof(ReplyTo), "<@%s> This channel is being used for account linking!\nUsage: %s <assignid>", userid, assigncommand);
		dbot.SendMessage(Channel, ReplyTo);
		return;
	}

	if(!IsValidAssignID(StringToInt(explodemessage[1]))) {
		Format(ReplyTo, sizeof(ReplyTo), "<@%s> This assign ID isn't valid!", userid);
		dbot.SendMessage(Channel, ReplyTo);
		return;
	}

	if(StringToInt(explodemessage[1]) == assignid[GetClientFromAssignID(StringToInt(explodemessage[1]))]){
		SetClientCookie(GetClientFromAssignID(StringToInt(explodemessage[1])), Cookies[c_DiscordName], m_Author);
		SetClientCookie(GetClientFromAssignID(StringToInt(explodemessage[1])), Cookies[c_DiscordName], m_dTag);

		PrintToChat(GetClientFromAssignID(StringToInt(explodemessage[1])), "%s You have linked your discord to this steam account. (\x04%s%s\x01)", PREFIX, m_Author, m_dTag);
		m_Discord[GetClientFromAssignID(StringToInt(explodemessage[1]))] = true;

		Format(ReplyTo, sizeof(ReplyTo), "<@%s> You have linked your discord account! You can go back ingame.", userid);
		dbot.SendMessage(Channel, ReplyTo);

		Call_StartForward(OnClientLinkedAccount);
		Call_PushCell(GetClientFromAssignID(StringToInt(explodemessage[1])));
		Call_Finish();
	}
}

public void OnAllPluginsLoaded()
{
	if(dbot != view_as<DiscordBot>(INVALID_HANDLE))
		return;
	
	char token[128];
	GetConVarString(DSM_Settings[Bot_Token], token, sizeof(token));
	dbot = new DiscordBot(token);
}

stock int GetAssignID()
{
	return GetRandomInt(MIN_ASSIGN_ID, MAX_ASSIGN_ID);
}

stock int GetClientAssignID(int client)
{
	return assignid[client];
}

stock bool IsValidAssignID(int id)
{
	if(id < MIN_ASSIGN_ID || id > MAX_ASSIGN_ID)
		return false;
	else
		return true;
}

stock bool IsDiscordMember(int client)
{
	return m_Discord[client];
}

stock int GetClientFromAssignID(int id)
{
	int client;
	for (int i = 1; i <= MaxClients; ++i)
	{
		if(!IsValidClient(i))
			continue;

		if(assignid[i] == id)
			client = i;
	}

	return client;
}

public int Native_IsDiscordMember(Handle myplugin, int argc)
{
	int client = GetNativeCell(1);

	return IsDiscordMember(client);
}