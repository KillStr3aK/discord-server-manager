#include <sourcemod>
#include <servermanager>

#define PLUGIN_NEV	"DSM NATIVES"
#define PLUGIN_LERIAS	"EXAMPLES"
#define PLUGIN_AUTHOR	"Nexd"
#define PLUGIN_VERSION	"1.0"
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

public void OnPluginStart()
{
	RegConsoleCmd("sm_member", Command_Member);
}

public Action Command_Member(int client, int args)
{
	if(DSM_IsMember(client))
	{
		char userid[64];
		DSM_GetUserId(client, userid, sizeof(userid));
		PrintToChat(client, " \x04%sYou are a member! Userid: %s", userid);
	} else {
		PrintToChat(client, " \x07You aren't a member!");
	}

	DSM_RefreshClients(); //Refresh every client (Call OnClientPostAdminCheck)

	return Plugin_Handled;
}

public void DSM_OnLinkedAccount(int client, const char[] userid, const char[] username, const char[] discriminator)
{
	PrintToChatAll("%N %s%s (%s)", client, username, discriminator, userid);
}