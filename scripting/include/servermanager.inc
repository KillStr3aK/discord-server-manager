#if defined _servermanager_included
 #endinput
#endif
#define _servermanager_included

forward void DSM_OnLinkedAccount(int client, const char[] userid, const char[] username, const char[] discriminator);

native void DSM_RefreshClients();
native bool DSM_IsMember(int client);
native char DSM_GetUserId(int client, char[] output, int maxsize);

public SharedPlugin __pl_servermanager = {
		name = "discord_manager",
		file = "discord_manager.smx",
	#if defined REQUIRE_PLUGIN
		required = 1,
	#else
		required = 0,
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_servermanager_SetNTVOptional()
{
	MarkNativeAsOptional("DSM_IsMember");
	MarkNativeAsOptional("DSM_GetUserId");
	MarkNativeAsOptional("DSM_RefreshClients");
}
#endif 