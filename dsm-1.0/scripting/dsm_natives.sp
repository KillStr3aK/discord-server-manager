#include <sourcemod>
#include <dsm>

#define PLUGIN_NEV	"DSM Natives"
#define PLUGIN_LERIAS	"Examples"
#define PLUGIN_AUTHOR	"Nexd"
#define PLUGIN_VERSION	"1.0"
#define PLUGIN_URL	"https://github.com/KillStr3aK"
#pragma tabsize 0

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
	RegConsoleCmd("sm_islinked", Command_IsLinked);
}

public Action Command_IsLinked(int client, int args)
{
	if(!IsValidClient(client))
		return Plugin_Continue;

	if(args != 1)
	{
		PrintToChat(client, "%s Usage: !islinked name", PREFIX);
		return Plugin_Handled;
	}

	char arg1[MAX_NAME_LENGTH];
	char playername[MAX_NAME_LENGTH+1];

	GetCmdArg(1, arg1, sizeof(arg1));
	int target = FindTarget(client, arg1, true);
	GetClientName(target, playername, sizeof(playername));
	if(DSM_IsDiscordMember(client))
		PrintToChat(client, "%s %s has linked his account.", PREFIX, playername);
	else
		PrintToChat(client, "%s %s hasn't linked his account.", PREFIX, playername);

	return Plugin_Continue;
}

public void DSM_OnClientLinkedAccount(int client)
{
	char playername[MAX_NAME_LENGTH+1];
	GetClientName(client, playername, sizeof(playername));
	PrintToChatAll("%s %s has linked his discord account!", PREFIX, playername);
}