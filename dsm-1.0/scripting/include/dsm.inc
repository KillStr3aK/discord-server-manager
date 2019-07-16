#if defined _dsm_included_ 
  #endinput 
#endif 
#define _dsm_included_
#define empty "\0"
#define MAX_DISCORD_MESSAGE_LENGTH 2000
#define MAX_USERNAME_LENGTH 32
#define MAX_TAG_LENGTH 5
#define MIN_ASSIGN_ID 12345
#define MAX_ASSIGN_ID 54321
#define PREFIX "\x01[\x07DSM\x01]"

native bool DSM_IsDiscordMember(int client);

forward void DSM_OnClientLinkedAccount(int client);

stock bool IsValidClient(int client)
{
	if(client <= 0 ) return false;
	if(client > MaxClients) return false;
	if(!IsClientConnected(client)) return false;
	if(IsFakeClient(client)) return false;
	return IsClientInGame(client);
}