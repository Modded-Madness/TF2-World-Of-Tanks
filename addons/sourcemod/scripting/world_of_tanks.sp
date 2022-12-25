#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf2items>
#include <tf2attributes>

#include <shiko_stock>

#define ROUND_INIT		0
#define ROUND_INIT2		1
#define ROUND_SETUP		2
#define ROUND_INGAME	3
#define ROUND_END		4
int g_iRoundState = ROUND_INIT;
bool g_bNewRound = false;

bool g_bDirectRocket[2048] = false;
bool g_bStickyJump[MAXPLAYERS+1] = false;
bool g_bAttacking[MAXPLAYERS+1] = false;
bool g_bForceReload[MAXPLAYERS+1] = false;
bool g_bGroundCheck[MAXPLAYERS+1] = false;
bool g_bUltimateMode[MAXPLAYERS+1] = false;
bool g_bRoundActive = false;

float g_flTankMaxSpeed[MAXPLAYERS+1];
float g_flNextRocketFire[MAXPLAYERS+1] = -1.0;
float g_flNextReloadEnd[MAXPLAYERS+1] = -1.0;
float g_flRocketAngles[MAXPLAYERS+1];
float g_flStickyJumpTime[MAXPLAYERS+1];
float g_flNextStickyTime[MAXPLAYERS+1] = -1.0;
float g_flLastHitTime[MAXPLAYERS+1] = -1.0;
float g_flLastFallVel[MAXPLAYERS+1];
float g_flSpaceTime[MAXPLAYERS+1];
float g_flUltimateDamage[MAXPLAYERS+1];
float g_flUltimateEndTime[MAXPLAYERS+1];

Handle g_hRoundTick = INVALID_HANDLE;
Handle g_hReloadHud = INVALID_HANDLE;
Handle g_hUltimateHud = INVALID_HANDLE;

int g_iStickyBomb[MAXPLAYERS+1] = -1;
int g_iCrosshair[MAXPLAYERS+1] = -1;
int g_iCrosshairSprite[MAXPLAYERS+1] = -1;
int g_iStickySprite[MAXPLAYERS+1] = -1;
int g_LastButtons[MAXPLAYERS+1] = -1;
int g_iLaser;

#define SPR_EXPLODE			"spirites/zerogxplode.spr"
#define MDL_TANK			"models/custom_model/tank_soldier.mdl"
#define MDL_AP_SHELL		"models/weapons/w_models/w_rocket_airstrike/w_rocket_airstrike.mdl"
#define MDL_STICKYBOMB		"models/weapons/w_models/w_stickybomb.mdl"
#define MDL_JUMPER			"models/weapons/w_models/w_stickybomb2.mdl"

#define SFX_TANK			"player/taunt_tank_shoot.wav"
#define SFX_DIRECTHIT		"mvm/giant_soldier/giant_soldier_rocket_shoot.wav"
#define SFX_RELOAD_START	"player/taunt_tank_appear.wav"
#define SFX_RELOAD_END		"vehicles/tank_readyfire1.wav"
#define SFX_MODE			"player/taunt_moped_start_shake.wav"

#define SFX_IDLE			"player/taunt_tank_idle.wav"
#define SFX_FORWARD			"tank/taunt_tank_forward.wav"
#define SFX_REVERSE			"player/taunt_tank_reverse.wav"
#define SFX_STICKYBOMB		"player/taunt_moped_start_land.wav"
#define SFX_JUMPER			"weapons/sticky_jumper_explode1.wav"
#define SFX_ULTIMATE		"misc/doomsday_cap_open.wav"

#define SNDVOL_HALF			0.5

#define PLAYERANIMEVENT_ATTACK_PRIMARY	0

#define DMG_USEDISTANCEMOD	DMG_SLOWBURN
#define HIDEHUD_CROSSHAIR	( 1<<8 )
#define EF_NODRAW			32

ConVar g_cvEnabled;
ConVar g_cvTankMaxSpeed;
ConVar g_cvStickybombVel;
ConVar g_cvJumperVel;
ConVar g_cvUltimateCap;
ConVar g_cvUltimateRadius;

#define PLUGIN_VERSION 		"1.1"
#define TIMER_INTERVAL		0.1

bool lateLoad = false;
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	lateLoad = late;
	
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "World of Tanks",
	description = "",
	author = "shiko-",
	version = PLUGIN_VERSION
}

public void OnPluginStart()
{
	g_iRoundState = ROUND_INIT;
	g_bNewRound = true;

	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);
	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("post_inventory_application", OnLoadoutChanged);

	HookEvent("teamplay_round_start", Event_RoundStart);
	HookEvent("teamplay_setup_finished", Event_SetupEnd);
	HookEvent("teamplay_round_win", Event_RoundEnd);
	HookEvent("teamplay_round_active", Event_RoundActive);

	AddCommandListener(OnVoiceMenu, "voicemenu");
	AddCommandListener(OnJoinClass, "joinclass");
	AddCommandListener(OnJoinTeam, "jointeam");

	g_cvEnabled = CreateConVar("sm_soldiertank_enabled", "1", "", _, true, 0.0, true, 1.0);
	g_cvTankMaxSpeed = CreateConVar("sm_soldiertank_maxspeed", "230.0", "Max speed", 0, true, 0.0, false);
	g_cvStickybombVel = CreateConVar("sm_soldiertank_stickybomb_velocity", "1200.0", "", 0, true, 0.0, false);
	g_cvJumperVel = CreateConVar("sm_soldiertank_jumper_velocity", "800.0", "Max speed", 0, true, 0.0, false);
	g_cvUltimateCap = CreateConVar("sm_soldiertank_ultimate_capacity", "1200.0", "", 0, true, 0.0, false);
	g_cvUltimateRadius = CreateConVar("sm_soldiertank_ultimate_radius", "3.0", _, _, true, 0.01, false);

	RegAdminCmd("sm_ft", test, ADMFLAG_ROOT);

	g_hReloadHud = CreateHudSynchronizer();
	g_hUltimateHud = CreateHudSynchronizer();

	HookConVarChange(g_cvEnabled, OnConVarEnabledChange);

	if (lateLoad) ForcePluginEnable();
}

public Action test(int client, int args)
{
	PrintToChat(client, "max bonus");
	g_flUltimateDamage[client] = 1200.0;
	
	return Plugin_Handled;
}

public void OnConVarEnabledChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int old_val = StringToInt(oldValue);
	int new_val = StringToInt(newValue);

	if (old_val != new_val) {
		if (new_val <= 0) ForcePluginDisable();
		else ForcePluginEnable();
	}
}

public void ForcePluginEnable()
{
	OnMapStart();

	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i)) {
			SDKHook(i, SDKHook_PreThinkPost, OnClientThink);
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
		}
	}
}

public void ForcePluginDisable()
{
	g_bNewRound = true;
	g_iRoundState = ROUND_INIT;

	if (g_hRoundTick != INVALID_HANDLE) {
		CloseHandle(g_hRoundTick);
		g_hRoundTick = INVALID_HANDLE;
	}

	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i)) {
			SDKUnhook(i, SDKHook_PreThinkPost, OnClientThink);
			SDKUnhook(i, SDKHook_OnTakeDamage, OnTakeDamage);

			TF2Attrib_RemoveByDefIndex(i, 326);
		}
	}

	lateLoad = false;
}

public void OnConfigsExecuted()
{
	if (!g_cvEnabled.BoolValue) return;

	g_iRoundState = ROUND_INIT;
}	

public void OnMapStart()
{
	g_bRoundActive = false;
	g_iRoundState = ROUND_INIT;

	PrecacheModel(SPR_EXPLODE, true);
	PrecacheModel(MDL_TANK, true);
	PrecacheModel(MDL_AP_SHELL, true);
	PrecacheModel(MDL_STICKYBOMB, true);
	PrecacheModel(MDL_JUMPER, true);

	PrecacheSound(SFX_TANK, true);
	PrecacheSound(SFX_RELOAD_START, true);
	PrecacheSound(SFX_RELOAD_END, true);
	PrecacheSound(SFX_MODE, true);
	PrecacheSound(SFX_IDLE, true);
	PrecacheSound(SFX_FORWARD, true);
	PrecacheSound(SFX_REVERSE, true);
	PrecacheSound(SFX_STICKYBOMB, true);
	PrecacheSound(SFX_DIRECTHIT, true);
	PrecacheSound(SFX_JUMPER, true);
	PrecacheSound(SFX_ULTIMATE, true);

	AddFolderToDownloadsTable("models/custom_model");
	AddFolderToDownloadsTable("materials/models/custom_models/tank_soldier");
	//AddFolderToDownloadsTable("materials/vgui/crosshairs")
	AddFolderToDownloadsTable("sound/tank");

	g_iLaser = PrecacheModel("materials/sprites/laserbeam.vmt");
}

public void OnMapEnd()
{
	if (!g_cvEnabled.BoolValue) return;

	g_iRoundState = ROUND_END;
}

public void OnGameFrame()
{
	if (!g_cvEnabled.BoolValue) return;

	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "tf_projectile_rocket")) != -1) {
		char name[128];
		GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
		if (StrContains(name, "_tank_rocket") != -1 && !g_bDirectRocket[entity]) {
			float vel[3];
			float ang[3];
			GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vel);
			
			vel[2] -= 5.0;
			GetVectorAngles(vel, ang);
			SetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vel);
			SetEntPropVector(entity, Prop_Data, "m_angRotation", ang);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (!g_cvEnabled.BoolValue) return;
	if (StrEqual(classname, "tf_ammo_pack", false) || StrContains(classname, "item_ammopack", false) != -1) {
		SDKHook(entity, SDKHook_StartTouch, OnAmmoTouch);
	}

	if (StrEqual(classname, "tf_projectile_rocket")) {
		SDKHook(entity, SDKHook_SpawnPost, OnRocketSpawned);
	}
}

public void TF2_OnConditionAdded(int client, TFCond condition)
{
	if (!g_cvEnabled.BoolValue) return;
	if (condition == TFCond_Taunting) {
		TF2_RemoveCondition(client, TFCond_Taunting);

		int primary = GetPlayerWeaponSlot(client, 0);
		if (IsValidEntity(primary)) {
			int effects = GetEntProp(primary, Prop_Send, "m_fEffects");
			effects |= EF_NODRAW;
			SetEntProp(primary, Prop_Send, "m_fEffects", effects);
		}
	}
}

public void OnAmmoTouch(int ammo, int client)
{
	int effects = GetEntProp(ammo, Prop_Send, "m_fEffects");
	if (effects & EF_NODRAW) return;

	char modelname[PLATFORM_MAX_PATH];
	GetEntityModel(ammo, modelname, sizeof(modelname));

	if (IsValidClient(client)) {
		char classname[128];
		GetEdictClassname(ammo, classname, sizeof(classname));
		if (StrContains(classname, "item_ammopack", false) != -1) {
			AcceptEntityInput(ammo, "Disable");
			CreateTimer(10.0, Timer_AmmoPackRegen, ammo);

			float time = 1.0;
			if (StrContains(classname, "medium") != -1) time = 2.0;
			else if (StrContains(classname, "full") != -1) time = 3.0;
			TF2_AddCondition(client, TFCond_SpeedBuffAlly, time);
		}
		else {
			AcceptEntityInput(ammo, "Kill");
			TF2_AddCondition(client, TFCond_SpeedBuffAlly, 2.0);
		}
	}
}

public void OnRocketSpawned(int entity)
{
	if (!IsValidEntity(entity)) return;

	int client = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
	if (!IsValidClient(client)) return;

	if (!g_bDirectRocket[entity]) return;
	//SetEntityModel(entity, MDL_AP_SHELL);
}

public Action OnVoiceMenu(int client, const char[] command, int argc)
{
	if (!g_cvEnabled.BoolValue) return Plugin_Continue;
	if (IsMapMVM() && IsFakeClient(client)) return Plugin_Continue;
	if(argc < 2) return Plugin_Handled;

	char cmd1[32];
	char cmd2[32];
	GetCmdArg(1, cmd1, sizeof(cmd1));
	GetCmdArg(2, cmd2, sizeof(cmd2));

	if(StrEqual(cmd1, "0") && StrEqual(cmd2, "0")) {
		if (IsPlayerUltimateFull(client)) {
			ActivatePlayerUltimate(client);
		}

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action OnJoinClass(int client, const char[] command, int argc)
{	
	if (!g_cvEnabled.BoolValue) return Plugin_Continue;
	if (IsMapMVM() && IsFakeClient(client)) return Plugin_Continue;

	char cmd1[32];
	if(argc < 1) return Plugin_Continue;
	GetCmdArg(1, cmd1, sizeof(cmd1));

	if (!StrEqual(cmd1, "soldier", false)) {
		FakeClientCommand(client, "joinclass soldier");

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action OnJoinTeam(int client, const char[] command, int argc)
{
	if (!g_cvEnabled.BoolValue) return Plugin_Continue;

	char cmd1[32];
	if(argc < 1) return Plugin_Continue;
	GetCmdArg(1, cmd1, sizeof(cmd1));

	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	PrintToChat(client, "Welcome to World of Tanks version %s!", PLUGIN_VERSION);

	if (!g_cvEnabled.BoolValue) return Plugin_Continue;

	if(g_iRoundState == ROUND_INIT)  {
		g_iRoundState = ROUND_INIT2;
		return Plugin_Continue;
	}
	else g_iRoundState = ROUND_SETUP;

	if (g_bNewRound) {
		if (g_hRoundTick != INVALID_HANDLE) {
			CloseHandle(g_hRoundTick);
			g_hRoundTick = INVALID_HANDLE;
		}   
		g_hRoundTick = CreateTimer(TIMER_INTERVAL, Timer_RoundTick, _, TIMER_REPEAT); 

		for (int i = 1; i <= MaxClients; i++) {
			g_flUltimateDamage[i] = 0.0;
		}
	}

	bool setup_time = false;
	int index = -1;
	while((index = FindEntityByClassname(index, "team_round_timer")) != -1) {
		if (IsValidEntity(index)) {
			if (GetEntProp(index, Prop_Send, "m_nSetupTimeLength") > 0) setup_time = true;
		}
	}

	g_bRoundActive = false;
	if (!setup_time) EndSetupPeriod();
	return Plugin_Continue;
}

public Action Event_SetupEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnabled.BoolValue) return Plugin_Continue;
	EndSetupPeriod();
	
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnabled.BoolValue) return Plugin_Continue;
	g_bNewRound = (GetEventBool(event, "full_round") || (GetEventInt(event, "team") == view_as<int>(TFTeam_Red)));

	g_iRoundState = ROUND_END;
	
	return Plugin_Continue;
}

public Action Event_RoundActive(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnabled.BoolValue) return Plugin_Continue;
	g_bRoundActive = true;
	return Plugin_Continue;
}


public void OnClientPostAdminCheck(int client)
{
	if (!g_cvEnabled.BoolValue) return;

	SDKHook(client, SDKHook_PreThinkPost, OnClientThink);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	g_flUltimateDamage[client] = 0.0;
	g_flUltimateEndTime[client] = -1.0;	
}

public void OnClientThink(int client)
{
	float time = GetGameTime();
	int buttons = GetClientButtons(client);
	int weapon = GetPlayerWeaponSlot(client, 0);
	if (IsValidEntity(weapon)) {
		if (IsWeaponInBonusMode(weapon)) {
			int clip = GetEntData(weapon, FindSendPropInfo("CBaseCombatWeapon", "m_iClip1"));
			if (clip == 0) {
				g_flUltimateEndTime[client] = -1.0;
				g_flUltimateDamage[client] = 0.0;
				TF2_RemoveCondition(client, TFCond_CritOnKill);
				TF2_RemoveCondition(client, TFCond_Buffed);
				SetWeaponBonusMode(client, false);
				g_bUltimateMode[client] = false;
			}
		}
		else {
			char classname[128];
			GetEdictClassname(weapon, classname, sizeof(classname));

			bool empty_ammo = false;
			if (StrEqual(classname, "tf_weapon_particle_cannon")) {
				if (GetEntPropFloat(weapon, Prop_Send, "m_flEnergy") <= 0.0) empty_ammo = true;
			}
			else {
				if (GetTankAmmo(client) <= 0) empty_ammo = true;
			}

			if (buttons & IN_RELOAD && !empty_ammo) {
				if (StrEqual(classname, "tf_weapon_particle_cannon")) {
					if (GetEntPropFloat(weapon, Prop_Send, "m_flEnergy") < 20.0) g_bForceReload[client] = true;
				}
				else {
					if (GetTankAmmo(client) < 6) g_bForceReload[client] = true;
				}
			}

			if (empty_ammo || g_bForceReload[client]) {
				if (g_flNextReloadEnd[client] < 0.0) {
					g_flNextReloadEnd[client] = time + 2.0;

					CreateTimer(0.0, Timer_EmitReloadStartSound, client);
					CreateTimer(0.5, Timer_EmitReloadEndSound, client);
				}

				if (time >= g_flNextReloadEnd[client]) {
					SetEntPropFloat(weapon, Prop_Send, "m_flEnergy", 20.0);
					SetEntData(weapon, FindSendPropInfo("CBaseCombatWeapon", "m_iClip1"), 6);

					g_flNextReloadEnd[client] = -1.0;
					g_bForceReload[client] = false;
				}
			}
		}
	}

	int active_weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (IsValidEntity(active_weapon)) {
		char classname[128];
		GetEdictClassname(active_weapon, classname, sizeof(classname));
		if (!StrEqual(classname, "tf_weapon_rocketlauncher")) {
			int primary = GetPlayerWeaponSlot(client, 0);
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", primary);
		}
		
		int effects = GetEntProp(active_weapon, Prop_Send, "m_fEffects");
		if (!(effects & EF_NODRAW)) {
			effects |= EF_NODRAW;
			SetEntProp(active_weapon, Prop_Send, "m_fEffects", effects);
		}

		bool lowered = view_as<bool>(GetEntProp(active_weapon, Prop_Send, "m_bLowered"));
		if (!lowered) SetEntProp(active_weapon, Prop_Send, "m_bLowered", true);
	}

	int charge_meter = GetPlayerWeaponSlot(client, 1);
	if (IsClassname(charge_meter, "tf_weapon_buff_item")) {
		float percentage = ((g_flNextStickyTime[client] - time) / 8.0) * 100.0;
		if (percentage > 100.0) percentage = 100.0;
		else if (percentage < 0.0) percentage = 0.0;
		SetEntPropFloat(client, Prop_Send, "m_flRageMeter", percentage);
	} 

	if (g_flTankMaxSpeed[client] > 1.0) {
		if (!(buttons & IN_FORWARD || buttons & IN_BACK)) {
			g_flTankMaxSpeed[client] -= 8.0;
			if (g_flTankMaxSpeed[client] < 1.0) g_flTankMaxSpeed[client] = 1.0;
		}
	}

	float fall_vec = GetEntPropFloat(client, Prop_Send, "m_flFallVelocity");
	if (!IsPlayerOnGround(client) && fall_vec != 0.0) {
		if (!g_bGroundCheck[client]) g_bGroundCheck[client] = false;
	}
	else {
		if (g_bGroundCheck[client]) g_bGroundCheck[client] = true;
	}

	if ((g_bGroundCheck[client] != IsPlayerOnGround(client)) && g_flLastFallVel[client] != 0.0) {
		if (g_flLastFallVel[client] > 500.0) {
			int target = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
			if (IsValidClient(target) && GetClientTeam(client) != GetClientTeam(target)) {
				ShowStompEffect(target);
				if (IsValidEntity(weapon)) SDKHooks_TakeDamage(target, client, client, 1000.0, DMG_FALL, weapon);
				else SDKHooks_TakeDamage(target, client, client, 1000.0, DMG_FALL);
				SetEntityHealth(client, 400);
			}
		}

		if (g_bStickyJump[client]  && time > g_flStickyJumpTime[client]) g_bStickyJump[client] = false;
	}
	g_flLastFallVel[client] = GetEntPropFloat(client, Prop_Send, "m_flFallVelocity");

	if (TF2_IsPlayerInCondition(client, TFCond_SpeedBuffAlly)) g_flTankMaxSpeed[client] *= 1.8;
	SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", g_bRoundActive ? g_flTankMaxSpeed[client] : 0.1); 

	UpdateCrosshairAnchor(client);

	SetVariantInt(1);
	AcceptEntityInput(client, "SetForcedTauntCam");

	//SetEntProp(client, Prop_Send, "m_nForceTauntCam", 2);
    //SetEntProp(client, Prop_Send, "m_bAllowMoveDuringTaunt", 1);
}

public Action Timer_EmitReloadStartSound(Handle timer, any client) {
	if (!IsValidClient(client)) return Plugin_Continue;
	if (!IsPlayerAlive(client)) return Plugin_Continue;

	EmitSoundToClient(client, SFX_RELOAD_START);
	return Plugin_Continue;
}

public Action Timer_EmitReloadEndSound(Handle timer, any client) {
	if (!IsValidClient(client)) return Plugin_Continue;
	if (!IsPlayerAlive(client)) return Plugin_Continue;

	EmitSoundToClient(client, SFX_RELOAD_END);
	return Plugin_Continue;
}

public Action Timer_AmmoPackRegen(Handle timer, any ammo) {
	if (!IsValidEntity(ammo)) return Plugin_Continue;
	AcceptEntityInput(ammo, "Enable");
	return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	bool changed = false;

	float time = GetGameTime();
	if (IsValidClient(victim)) {
		if (IsClassname(inflictor, "env_explosion")) {
			char targetname[128];
			GetEntPropString(inflictor, Prop_Data, "m_iName", targetname, sizeof(targetname));

			char split[2][128];
			ExplodeString(targetname, "_", split, sizeof(split), sizeof(split[]));
			int owner = StringToInt(split[1]);

			if (StrEqual(split[0], "|jumper")) {
				if (owner == victim) {
					NormalizeVector(damageForce, damageForce);
					ScaleVector(damageForce, g_cvJumperVel.FloatValue);
					TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, damageForce);

					g_bStickyJump[victim] = true;
					g_flStickyJumpTime[victim] = time + 0.1;
				}

				damage = 0.0;
				changed = true;
			}
			else {
				if (owner == victim) {
					NormalizeVector(damageForce, damageForce);
					ScaleVector(damageForce, g_cvStickybombVel.FloatValue);
					TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, damageForce);
					damage = 0.0;
					changed = true;

					g_bStickyJump[victim] = true;
					g_flStickyJumpTime[victim] = time + 0.1;
				}
			}
		}

		if (IsClassname(inflictor, "tf_projectile_rocket")) {
			if (attacker == victim) {
				if (g_bDirectRocket[inflictor]) damage = 30.0; // AP rocket
				else damage = 10.0; // Stock rocket

				changed = true;
			}

			else {
				if (IsRocketPowerShot(inflictor) && damagetype == TF_DMG_ROCKET_CRIT) {
					if (damage < 33.35) {
						damage = 33.35; // Stock rocket, splash hit
						changed = true;
					}
				}
				else {
					if (g_bDirectRocket[inflictor]) {
						if (IsDirectHit(victim, inflictor, damagePosition)) damage = 50.0; // AP rocket, direct hit
						else damage = 0.0; // AP rocket, splash hit

						if (damagetype & DMG_USEDISTANCEMOD) damagetype &= ~DMG_USEDISTANCEMOD; // Remove damage falloff
						changed = true;
					}
					else {
						if (IsDirectHit(victim, inflictor, damagePosition)) {
							if (damage < 40.0) damage = 40.0; // Stock rocket, direct hit
						}
						else {
							damage *= 0.5;
							if (damage < 20.0) damage = 20.0; // Stock rocket, splash hit
						}

						changed = true;
					}
				}

				if (g_bStickyJump[victim] && time > g_flStickyJumpTime[victim]) {
					char classname[64];
					GetEdictClassname(inflictor, classname, sizeof(classname));
					if (StrContains(classname, "tf_projectile_rocket") != -1) {
						if (g_bDirectRocket[inflictor] && IsDirectHit(victim, inflictor, damagePosition)) {
							damage = 1000.0;
							SetEntityHealth(attacker, 200);

							damagetype |= DMG_CRIT;
							changed = true;
						}
					}
				}
			}
		}

		g_flLastHitTime[victim] = time;
	}

	if (changed) return Plugin_Changed;
	return Plugin_Continue;
}

public Action OnPlayerSpawn(Handle event, const char[] Name, bool Spawn_Broadcast)
{
	if (!g_cvEnabled.BoolValue) return Plugin_Continue;

	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (IsMapMVM() && IsFakeClient(client)) return Plugin_Continue;

	if (GetClientTeam(client) >= 2) {
		if (TF2_GetPlayerClass(client) != TFClass_Soldier) FakeClientCommand(client, "joinclass soldier");

		g_flSpaceTime[client] = -1.0;
		CreateTimer(0.1, OnPlayerSpawnPost, client);
		TF2_AddCondition(client, TFCond_SpeedBuffAlly, 3.0);
	}

	return Plugin_Continue;
}

public Action OnPlayerDeath(Handle event, const char[] Name, bool Spawn_Broadcast)
{
	if (!g_cvEnabled.BoolValue) return Plugin_Continue;

	bool changed = false;
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (g_iRoundState != ROUND_INGAME) return Plugin_Continue;

	if (IsValidClient(attacker)) {
		int health = GetClientHealth(attacker) + 100;
		int max_health = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, attacker);
		if (health > max_health) health = max_health;
		SetEntityHealth(attacker, health);

		if (client != attacker) {
			float death_bonus = g_cvUltimateCap.FloatValue * 0.1;
			AddPlayerUltimate(client, death_bonus);
		}
	}

	SetVariantString("");
	AcceptEntityInput(client, "SetCustomModel");
	
	int damagetype = GetEventInt(event, "damagebits");
	int inflictor = GetEventInt(event, "inflictor_entindex");
	if (IsValidEntity(inflictor)) {
		char classname[128];
		GetEdictClassname(inflictor, classname, sizeof(classname));

		char targetname[128];
		GetEntPropString(inflictor, Prop_Data, "m_iName", targetname, sizeof(targetname));

		char split[2][128];
		ExplodeString(targetname, "_", split, sizeof(split), sizeof(split[]));

		int owner = StringToInt(split[1]);
		if (owner == attacker && StrEqual(classname, "env_explosion")) {
			SetEventString(event, "weapon", "sticky_resistance");
			SetEventString(event, "weapon_logclassname", "sticky_resistance");
			SetEventInt(event, "weaponid", 35);

			int primary = GetPlayerWeaponSlot(attacker, 0);
			if (IsValidEntity(primary)) SetEventInt(event, "inflictor_entindex", primary);
			else SetEventInt(event, "inflictor_entindex", attacker);
			
			SetEventInt(event, "damagebits", 393280);
			SetEventInt(event, "customkill", 26);
			SetEventInt(event, "death_flags", 128);
			SetEventInt(event, "weapon_def_index", 130);

			int new_value = GetEntProp(attacker, Prop_Send, "m_nStreaks") + 1;
			SetEntProp(attacker, Prop_Send, "m_nStreaks", new_value);
			SetEventInt(event, "kill_streak_total", new_value);
			SetEventInt(event, "kill_streak_wep", new_value);
			changed = true;
		}

		if (IsValidClient(inflictor) && (damagetype & DMG_FALL)) {
			SetEventString(event, "weapon", "mantreads");
			changed = true;
		}
	}

	DestroyStickyBomb(client);
	RemoveCrosshair(client);

	if (changed) return Plugin_Changed;
	return Plugin_Continue;
}

public Action OnPlayerHurt(Handle event, const char[] Name, bool Spawn_Broadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (IsValidClient(client)) {
		if (IsValidClient(attacker) && IsPlayerAlive(attacker) && attacker != client) {
			int damage = GetEventInt(event, "damageamount");
			g_flUltimateDamage[attacker] += float(damage);
			if (g_flUltimateDamage[attacker] > g_cvUltimateCap.FloatValue) g_flUltimateDamage[attacker] = g_cvUltimateCap.FloatValue;

			//g_flLastDamageTime = GetGameTime();
		}
	}
	
	return Plugin_Continue;
}


public Action RemoveBody(Handle timer, any client)
{
	if (!IsValidClient(client)) return Plugin_Continue;

	int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if(IsValidEntity(ragdoll)) AcceptEntityInput(ragdoll, "kill");

	return Plugin_Continue;
}

public Action RemoveRagdoll(Handle timer, any entity)
{
	if(IsValidEntity(entity)) {
		char classname[64];
		GetEdictClassname(entity, classname, sizeof(classname));
		if(StrEqual(classname, "tf_ragdoll", false)) AcceptEntityInput(entity, "kill");
	}

	return Plugin_Continue;
}

public Action OnLoadoutChanged(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnabled.BoolValue) return Plugin_Continue;

	int i = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(i)) return Plugin_Continue;
	if (IsMapMVM() && IsFakeClient(i)) return Plugin_Continue;

	if (TF2_GetPlayerClass(i) == TFClass_Soldier) CreateTimer(0.1, OnPlayerSpawnPost, i);

	return Plugin_Continue;
}

public Action OnPlayerSpawnPost(Handle timer, any client)
{
	if (!IsValidClient(client)) return Plugin_Continue;
	if (TF2_GetPlayerClass(client) != TFClass_Soldier) return Plugin_Continue;

	RemoveWearable(client, 133);
	RemoveWearable(client, 444);
	TF2_RemoveAllWeapons(client);

	Handle weapon = TF2Items_CreateItem(PRESERVE_ATTRIBUTES);
	TF2Items_SetClassname(weapon, "tf_weapon_rocketlauncher");
	TF2Items_SetQuality(weapon, 6);
	TF2Items_SetLevel(weapon, 15);
	TF2Items_SetItemIndex(weapon, 205);
	TF2Items_SetAttribute(weapon, 0, 2025, 1.0);
	TF2Items_SetAttribute(weapon, 1, 68, 1.0);
	TF2Items_SetAttribute(weapon, 2, 4, 1.5);
	TF2Items_SetNumAttributes(weapon, 3);

	int primary = TF2Items_GiveNamedItem(client, weapon);
	SetEntProp(primary, Prop_Send, "m_iAccountID", GetSteamAccountID(client));
	SetEntProp(primary, Prop_Send, "m_bInitialized", 1);
	EquipPlayerWeapon(client, primary);

	int secondary = CreateEntityByName("tf_weapon_buff_item");
    SetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex", 129);     
    SetEntProp(secondary, Prop_Send, "m_bInitialized", 1);
    SetEntProp(secondary, Prop_Send, "m_iEntityLevel", 100);
    SetEntProp(secondary, Prop_Send, "m_iEntityQuality", 5);

    DispatchSpawn(secondary); 
    EquipPlayerWeapon(client, secondary);

    /*
	Handle charge = TF2Items_CreateItem(PRESERVE_ATTRIBUTES);
	TF2Items_SetClassname(charge, "tf_weapon_buff_item");
	TF2Items_SetQuality(charge, 6);
	TF2Items_SetLevel(charge, 15);
	TF2Items_SetItemIndex(charge, 129);
	TF2Items_SetNumAttributes(charge, 0);

	int secondary = TF2Items_GiveNamedItem(client, charge);
	SetEntProp(secondary, Prop_Send, "m_iAccountID", GetSteamAccountID(client));
	SetEntProp(secondary, Prop_Send, "m_bInitialized", 1);
	SetEntProp(secondary, Prop_Send, "m_bValidatedAttachedEntity", 1);
	EquipPlayerWeapon(client, secondary);*/

	TF2Attrib_SetByName(client, "increased jump height", 0.0);

	SetVariantString(MDL_TANK);
	AcceptEntityInput(client, "SetCustomModel");
	SetVariantInt(1);
	AcceptEntityInput(client, "SetCustomModelRotates");
	SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
	SetVariantInt(1);
	AcceptEntityInput(client, "SetForcedTauntCam");

	SetEntProp(primary, Prop_Send, "m_bLowered", true);
	SetEntProp(secondary, Prop_Send, "m_bLowered", true);

	int effects = GetEntProp(primary, Prop_Send, "m_fEffects");
	effects |= EF_NODRAW;
	SetEntProp(primary, Prop_Send, "m_fEffects", effects);

	effects = GetEntProp(secondary, Prop_Send, "m_fEffects");
	effects |= EF_NODRAW;
	SetEntProp(secondary, Prop_Send, "m_fEffects", effects);

	int extraWearable = GetEntPropEnt(secondary, Prop_Send, "m_hExtraWearable");
	if (IsValidEntity(extraWearable)) TF2_RemoveWearable(client, extraWearable);

	float time = GetGameTime();
	g_bAttacking[client] = false;
	g_flNextRocketFire[client] = time;
	g_flNextReloadEnd[client] = -1.0;
	g_flRocketAngles[client] = 0.0;
	g_flTankMaxSpeed[client] = 0.0;
	g_flNextStickyTime[client] = time;

	DestroyStickyBomb(client);
	EmitSoundToAll(SFX_IDLE, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_CHANGEVOL, SNDVOL_HALF, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);

	CreateTimer(0.1, Timer_SetWeaponTransparent, client);
	return Plugin_Continue;
}

public Action Timer_SetWeaponTransparent(Handle timer, any client)
{
	if (!IsValidClient(client)) return Plugin_Continue;
	if (!IsPlayerAlive(client)) return Plugin_Continue;

	for (int slot = 0; slot < 2; slot++) {
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (!IsValidEntity(weapon)) continue;

		int effects = GetEntProp(weapon, Prop_Send, "m_fEffects");
		if (!(effects & EF_NODRAW)) {
			effects |= EF_NODRAW;
			SetEntProp(weapon, Prop_Send, "m_fEffects", effects);
		}
	}

	CreateCrosshair(client);
	return Plugin_Continue;
}

stock void EndSetupPeriod()
{
	if(g_iRoundState == ROUND_INGAME) return;
	if(g_iRoundState == ROUND_END) return;

	g_iRoundState = ROUND_INGAME;
	g_bRoundActive = true;
}

public Action Timer_RoundTick(Handle hTimer)
{
	float time = GetGameTime();
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsValidClient(i)) continue;
		if (!IsPlayerAlive(i)) continue;

		if (GetClientTeam(i) > 1) {
			int health = GetClientHealth(i) + 1;	//	10 per second
			int max_health = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, i);
			if (health <= max_health && g_flLastHitTime[i] + 3.0 < time) SetEntityHealth(i, health);

			if (g_flNextReloadEnd[i] > 0.0) {
				char reload[128];
				float percentage = ((g_flNextReloadEnd[i] - time) / 3.0) * 100.0;

				Format(reload, sizeof(reload), "Reload: %.0f%%", percentage);
				SetHudTextParams(0.8, 0.845, 0.5, 255, 255, 255, 255, _, 1.0, 0.07, 0.5);
				ShowSyncHudText(i, g_hReloadHud, reload);
			}


			int weapon = GetPlayerWeaponSlot(i, 0);
			if (IsValidEntity(weapon)) {
				int colors[3] = {255, 255, 255};
				float ultimate_percentage = (g_flUltimateDamage[i] / g_cvUltimateCap.FloatValue) * 100.0;

				if (IsPlayerUltimateFull(i) && g_bUltimateMode[i]) {
					switch (GetClientTeam(i)) {
						case 2: {
							colors[0] = 255;
							colors[1] = 0;
							colors[2] = 0;
						}
						case 3: {
							colors[0] = 0;
							colors[1] = 0;
							colors[2] = 255;
						}
					}

					if (g_flUltimateEndTime[i] <= 0.0) {
						g_flUltimateEndTime[i] = time + 10.0;
						TF2_AddCondition(i, TFCond_CritOnKill, 10.0); // 1.0
						TF2_AddCondition(i, TFCond_Buffed, 10.0); // 1.0
						SetEntData(weapon, FindSendPropInfo("CBaseCombatWeapon", "m_iClip1"), 1, 4);
						SetWeaponBonusMode(i, true);

						EmitSoundToAll(SFX_ULTIMATE, i);
						CreateTimer(0.0, Timer_EmitReloadStartSound, i);
						CreateTimer(0.5, Timer_EmitReloadEndSound, i);
						g_flNextRocketFire[i] = time + 2.0;
					}
					else {
						if (time > g_flUltimateEndTime[i]) {
							g_flUltimateEndTime[i] = -1.0;
							g_flUltimateDamage[i] = 0.0;
							SetEntData(weapon, FindSendPropInfo("CBaseCombatWeapon", "m_iClip1"), 0, 4);
							SetWeaponBonusMode(i, false);
							g_bUltimateMode[i] = false;
						}
					}
				}

				char ultimate[256];
				Format(ultimate, sizeof(ultimate), "NUKE: %.0f%%", ultimate_percentage);
				if (IsPlayerUltimateFull(i) && !IsWeaponInBonusMode(weapon)) Format(ultimate, sizeof(ultimate), "NUKE: E");
				SetHudTextParams(-1.0, 0.8, TIMER_INTERVAL, colors[0], colors[1], colors[2], 255, _, 1.0, 0.07, 0.5);

				ShowSyncHudText(i, g_hUltimateHud, ultimate);
			}
		}
	}

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (!g_cvEnabled.BoolValue) return Plugin_Continue;
	if (!IsPlayerAlive(client) || IsClientObserver(client)) return Plugin_Continue;

	bool changed = false;
	for (new i = 0; i < 26; i++) {
		int button2 = (1 << i);
		
		if ((buttons & button2)) {
			if (!(g_LastButtons[client] & button2)) {
				OnButtonPress(client, button2);
			}
		}
		else if ((g_LastButtons[client] & button2)) {
			OnButtonRelease(client, button2);
		}
	}
	g_LastButtons[client] = buttons;

	float time = GetGameTime();
	int primary = GetPlayerWeaponSlot(client, 0);
	if (IsValidEntity(primary)) {
		if (IsWeaponInBonusMode(primary)) {
			if (buttons & IN_ATTACK) {
				if (time >= g_flNextRocketFire[client]) {
					CreateUltimateRocket(client);
				}
			}
		}
		else {
			if (buttons & IN_ATTACK || buttons & IN_ATTACK2) {
				if (time >= g_flNextRocketFire[client]) {
					bool directhit = false;
					if (buttons & IN_ATTACK2) directhit = true;
					CreateRocket(client, directhit);
				}
			}
		}
	}

	if (buttons & IN_DUCK) {
		// force crouching disabled
		SetEntProp(client, Prop_Send, "m_bDucking", 0);
	}
	int flags = GetEntityFlags(client);
	if (!(flags & FL_ONGROUND) || (buttons & IN_DUCK)) {
		if (GetEntProp(client, Prop_Send, "m_bDucked") == 1) {
			buttons &= ~IN_DUCK;
			changed = true;
		}
	}

	if (vel[1] != 0.0) {
		vel[1] = 0.0;
		changed = true;
	}

	if ((buttons & IN_FORWARD || buttons & IN_BACK)) {
		float speed = 3.0;
		if (buttons & IN_BACK) speed = 1.5;
		g_flTankMaxSpeed[client] += speed;

		float maxSpeed = GetConVarFloat(g_cvTankMaxSpeed);
		if (g_flTankMaxSpeed[client] > maxSpeed) g_flTankMaxSpeed[client] = maxSpeed;
	}

	if (changed) return Plugin_Changed;
	return Plugin_Continue;
}

public void OnButtonPress(int client, int& button)
{
	if (button & IN_ATTACK) {
		if (!g_bAttacking[client]) {
			g_bAttacking[client] = true;
		}
	}

	if (button & IN_FORWARD) {
		EmitSoundToAll(SFX_IDLE, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_STOPLOOPING, 0.0, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		EmitSoundToAll(SFX_FORWARD, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_CHANGEVOL, SNDVOL_HALF, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		EmitSoundToAll(SFX_REVERSE, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_STOPLOOPING, 0.0, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
	}
	if (button & IN_BACK) {
		EmitSoundToAll(SFX_IDLE, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_STOPLOOPING, 0.0, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		EmitSoundToAll(SFX_REVERSE, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_CHANGEVOL, SNDVOL_HALF, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		EmitSoundToAll(SFX_FORWARD, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_STOPLOOPING, 0.0, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
	}

	if (button & IN_JUMP) {
		g_flSpaceTime[client] = GetGameTime();

		PlaceTankStickyBomb(client);
	}
}

public void OnButtonRelease(int client, int& button)
{
	if (button & IN_ATTACK) {
		if (g_bAttacking[client]) {
			g_bAttacking[client] = false;
		}
	}

	float vecPos[3];
	GetClientAbsOrigin(client, vecPos);
	if (button & IN_FORWARD) {
		EmitSoundToAll(SFX_IDLE, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_CHANGEVOL, SNDVOL_HALF, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		EmitSoundToAll(SFX_REVERSE, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_STOPLOOPING, 0.0, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		EmitSoundToAll(SFX_FORWARD, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_STOPLOOPING, 0.0, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
	}
	if (button & IN_BACK) {
		EmitSoundToAll(SFX_IDLE, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_CHANGEVOL, SNDVOL_HALF, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		EmitSoundToAll(SFX_REVERSE, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_STOPLOOPING, 0.0, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
		EmitSoundToAll(SFX_FORWARD, client, SNDCHAN_AUTO, SNDLEVEL_SCREAMING, SND_STOPLOOPING, 0.0, SNDPITCH_NORMAL, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
	}

	if (button & IN_JUMP) {
		/*
		float time_diff = GetGameTime() - g_flSpaceTime[client];
		//PrintToChat(client, "time diff %f", time_diff);

		if (time_diff >= 0.5) PlaceTankStickyBomb(client, true);
		else PlaceTankStickyBomb(client);*/

		g_flSpaceTime[client] = -1.0;
	}
}

stock void CreateRocket(int client, bool directhit = false)
{
	if (g_flNextReloadEnd[client] > 0.0) return;

	float speed = 1100.0;
	float damage = 64.0;
	float fire_rate = 0.8;

	if (directhit) {
		speed = 1980.0;
		damage = 50.0;
	}

	int iTeam = GetClientTeam(client);
	int iRocketEntity = CreateEntityByName("tf_projectile_rocket");
	if (!IsValidEntity(iRocketEntity)) return;

	DispatchKeyValue(iRocketEntity, "targetname", "_tank_rocket");
	SetEntPropEnt(iRocketEntity, Prop_Send, "m_hOwnerEntity", client);
	SetEntProp(iRocketEntity, Prop_Send, "m_iTeamNum", iTeam);
	SetEntDataFloat(iRocketEntity, FindSendPropInfo("CTFProjectile_Rocket", "m_iDeflected") + 4, damage, true);  
	g_bDirectRocket[iRocketEntity] = false;	//reset direct hit state

	float fPos[3];
	float fAng[3];
	float fVel[3];
	GetClientEyePosition(client, fPos);
	GetClientEyeAngles(client, fAng);
	fPos[2] -= 28.0;

	float fParam = GetEntPropFloat(client, Prop_Send, "m_flPoseParameter", 4);
	float fAim = (fParam-0.5) * 120.0;
	fAng[1] += fAim;

	if (directhit) {
		fAng[0] += 6.5;
		//SetEntPropFloat(iRocketEntity, Prop_Send, "m_flModelScale", 1.1);
		g_bDirectRocket[iRocketEntity] = true;
	}

	if (fAng[0] < -50.0) fAng[0] = -50.0;
	else if (fAng[0] > 50.0) fAng[0] = 50.0;

	GetAngleVectors(fAng, fVel, NULL_VECTOR, NULL_VECTOR);
	fPos[0] += fVel[0] * 20.0;
	fPos[1] += fVel[1] * 20.0;
	ScaleVector(fVel, speed);

	TeleportEntity(iRocketEntity, fPos, fAng, fVel);
	DispatchSpawn(iRocketEntity);
	ShowRocketParticle(client);
	
	int weapon = GetPlayerWeaponSlot(client, 0);
	if (IsValidEntity(weapon)) {
		if (directhit) EmitSoundToAll(SFX_DIRECTHIT, client);
		else {
			if (g_bAttacking[client]) EmitSoundToAll(SFX_TANK, client);
		}

		SetEntPropEnt(iRocketEntity, Prop_Send, "m_hOriginalLauncher", weapon); // GetEntPropEnt(baseRocket, Prop_Send, "m_hOriginalLauncher")
		SetEntPropEnt(iRocketEntity, Prop_Send, "m_hLauncher", weapon); // GetEntPropEnt(baseRocket, Prop_Send, "m_hLauncher")

		g_flNextRocketFire[client] = GetGameTime() + fire_rate;
		SubtractTankAmmo(client);
	}

	//fake animations
	TE_Start("PlayerAnimEvent");
	//TE_WriteEncodedEnt("m_hPlayer", client);
	TE_WriteNum("m_hPlayer", GetWeaponAnimOwner(client));
	TE_WriteNum("m_iEvent", 0);
	TE_WriteNum("m_nData", 0);
	TE_SendToAll();
}

stock void CreateUltimateRocket(int client)
{
	if (g_flNextReloadEnd[client] > 0.0) return;

	float speed = 550.0;
	float damage = 100.0;
	float fire_rate = 0.8;

	int iTeam = GetClientTeam(client);
	int iRocketEntity = CreateEntityByName("tf_projectile_rocket");
	if (!IsValidEntity(iRocketEntity)) return;

	DispatchKeyValue(iRocketEntity, "targetname", "_tank_rocket_ultimate");
	SetEntPropEnt(iRocketEntity, Prop_Send, "m_hOwnerEntity", client);
	SetEntProp(iRocketEntity, Prop_Send, "m_iTeamNum", iTeam);
	SetEntDataFloat(iRocketEntity, FindSendPropInfo("CTFProjectile_Rocket", "m_iDeflected") + 4, damage, true);  

	float fPos[3];
	float fAng[3];
	float fVel[3];
	GetClientEyePosition(client, fPos);
	GetClientEyeAngles(client, fAng);
	fPos[2] -= 28.0;

	float fParam = GetEntPropFloat(client, Prop_Send, "m_flPoseParameter", 4);
	float fAim = (fParam-0.5) * 120.0;
	fAng[1] += fAim;

	if (fAng[0] < -50.0) fAng[0] = -50.0;
	else if (fAng[0] > 50.0) fAng[0] = 50.0;

	GetAngleVectors(fAng, fVel, NULL_VECTOR, NULL_VECTOR);
	fPos[0] += fVel[0] * 20.0;
	fPos[1] += fVel[1] * 20.0;
	ScaleVector(fVel, speed);

	TeleportEntity(iRocketEntity, fPos, fAng, fVel);
	DispatchSpawn(iRocketEntity);
	ShowRocketParticle(client);
	
	int weapon = GetPlayerWeaponSlot(client, 0);
	if (IsValidEntity(weapon)) {
		if (g_bAttacking[client]) EmitSoundToAll(SFX_TANK, client);

		SetEntPropEnt(iRocketEntity, Prop_Send, "m_hOriginalLauncher", weapon); // GetEntPropEnt(baseRocket, Prop_Send, "m_hOriginalLauncher")
		SetEntPropEnt(iRocketEntity, Prop_Send, "m_hLauncher", weapon); // GetEntPropEnt(baseRocket, Prop_Send, "m_hLauncher")
		SetEntProp(iRocketEntity, Prop_Send, "m_bCritical", 1); // GetEntPropEnt(baseRocket, Prop_Send, "m_hLauncher")

		g_flNextRocketFire[client] = GetGameTime() + fire_rate;
		SubtractTankAmmo(client);
	}

	//fake animations
	TE_Start("PlayerAnimEvent");
	//TE_WriteEncodedEnt("m_hPlayer", client);
	TE_WriteNum("m_hPlayer", GetWeaponAnimOwner(client));
	TE_WriteNum("m_iEvent", 0);
	TE_WriteNum("m_nData", 0);
	TE_SendToAll();
}

stock int GetWeaponAnimOwner(int client)
{
	if (!IsValidClient(client)) return 0;

	int active_weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (!IsValidEntity(active_weapon)) return 0;
	
	return GetEntProp(active_weapon, Prop_Send, "m_hOwnerEntity");
}

stock bool RemoveWearable(int client, int id)
{
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "tf_wearable")) != -1) {
		if (IsClassname(entity, "tf_wearable") && GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client && GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex") == id) {
			TF2_RemoveWearable(client, entity);
			return true;
		}
	}
	return false;
}

stock void SubtractTankAmmo(int client, int amount = 1)
{
	int weapon = GetPlayerWeaponSlot(client, 0);
	if (IsValidEntity(weapon)) {
		char classname[128];
		GetEdictClassname(weapon, classname, sizeof(classname));

		if (StrEqual(classname, "tf_weapon_particle_cannon")) {
			float new_energy = GetEntPropFloat(weapon, Prop_Send, "m_flEnergy") - (amount * 5.0);

			SetEntPropFloat(weapon, Prop_Send, "m_flEnergy", new_energy);
		}
		else {
			int new_ammo = GetTankAmmo(client) - amount;

			SetEntData(weapon, FindSendPropInfo("CBaseCombatWeapon", "m_iClip1"), new_ammo);
		}
	}
}

stock int GetTankAmmo(int client)
{
	int weapon = GetPlayerWeaponSlot(client, 0);
	if (!IsValidEntity(weapon)) return -1;

	return GetEntData(weapon, FindSendPropInfo("CBaseCombatWeapon", "m_iClip1"), 4);
}

stock void ShowRocketParticle(int client)
{
	if (!IsValidClient(client)) return;
	if (!IsPlayerAlive(client)) return;

	int particle = CreateEntityByName("info_particle_system");
	if (!IsValidEntity(particle)) return;

	float pos[3];
	GetBonePosition(client, pos, "weapon_bone");
	TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);

	char targetname[128];
	Format(targetname, sizeof(targetname), "target%i", client);
	DispatchKeyValue(client, "targetname", targetname);

	DispatchKeyValue(particle, "targetname", "tf2particle");
	DispatchKeyValue(particle, "parentname", targetname);
	DispatchKeyValue(particle, "effect_name", "rocketbackblast");
	DispatchSpawn(particle);
	SetVariantString(targetname);
	AcceptEntityInput(particle, "SetParent", particle, particle, 0);
	SetVariantString("weapon_bone");
	AcceptEntityInput(particle, "SetParentAttachment", particle, particle, 0);
	ActivateEntity(particle);
	AcceptEntityInput(particle, "start");

	CreateTimer(5.0, RemoveParticle, particle);
}

stock void ShowStompEffect(int client)
{
    if (!IsValidClient(client)) return;
    if (!IsPlayerAlive(client)) return;

    int particle = CreateEntityByName("info_particle_system");
    if (!IsValidEntity(particle)) return;

    float pos[3];
    GetEntPropVector(client, Prop_Send, "m_vecOrigin", pos);
    TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);

    char targetname[128];
    Format(targetname, sizeof(targetname), "target%i", client);
    DispatchKeyValue(client, "targetname", targetname);

    DispatchKeyValue(particle, "targetname", "tf2particle");
    DispatchKeyValue(particle, "parentname", targetname);
    DispatchKeyValue(particle, "effect_name", "stomp_text");
    DispatchSpawn(particle);
    SetVariantString(targetname);
    AcceptEntityInput(particle, "SetParent", particle, particle, 0);
    SetVariantString("head");
    AcceptEntityInput(particle, "SetParentAttachment", particle, particle, 0);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "start");

    CreateTimer(5.0, RemoveParticle, particle);
}

stock void PlaceTankStickyBomb(int client, bool force_jumper = false)
{
	if (IsStickyBomb(g_iStickyBomb[client])) {
		char targetname[128];
		GetEntPropString(g_iStickyBomb[client], Prop_Data, "m_iName", targetname, sizeof(targetname));

		float bomb_pos[3];
		GetEntPropVector(g_iStickyBomb[client], Prop_Data, "m_vecOrigin", bomb_pos);
		AcceptEntityInput(g_iStickyBomb[client], "Kill");

		bool jumper = false;
		if (StrContains(targetname, "_jumper_") != -1) jumper = true;
		DetonateStickyBomb(client, bomb_pos, jumper);

		g_iStickyBomb[client] = -1;
		return;
	}

	float time = GetGameTime();
	if (!IsPlayerOnGround(client) || time < g_flNextStickyTime[client]) return;

	float pos[3];
	GetClientAbsOrigin(client, pos);
	pos[2] += 4.0;

	int bomb = CreateEntityByName("prop_dynamic");

	char targetname[128];
	Format(targetname, sizeof(targetname), "_stickybomb_");
	DispatchKeyValue(bomb, "targetname", targetname);
	DispatchKeyValueVector(bomb, "origin", pos);
	SetEntProp(bomb, Prop_Send, "m_nSkin", GetClientTeam(client)-2);
	SetEntityModel(bomb, MDL_STICKYBOMB);
	DispatchSpawn(bomb);

	SetEntPropEnt(bomb, Prop_Send, "m_hOwnerEntity", client);
	SetEntProp(bomb, Prop_Data, "m_takedamage", 0);
	SetEntProp(bomb, Prop_Send, "m_nSolidType", 2);
	SetEntProp(bomb, Prop_Data, "m_CollisionGroup", 2);
	g_iStickyBomb[client] = bomb;

	//int buttons = GetClientButtons(client);
	if (force_jumper) {
		SetEntityModel(bomb, MDL_JUMPER);
		SetEntPropString(bomb, Prop_Data, "m_iName", "_jumper_");
		g_flNextStickyTime[client] = time + 4.0;
	}
	else g_flNextStickyTime[client] = time + 8.0;
	

	EmitSoundToClient(client, SFX_STICKYBOMB);
}

stock void DetonateStickyBomb(int owner, float pos[3], bool jumper, int damage = 100, int radius = 90)
{
	int explode = CreateEntityByName("env_explosion");
	if(!IsValidEntity(explode)) return;

	char targetname[128];
	Format(targetname, sizeof(targetname), "|explode_%d", owner);

	int flags = 2;
	if (jumper) {
		EmitSoundToAll(SFX_JUMPER, owner);
		Format(targetname, sizeof(targetname), "|jumper_%d", owner);
		flags = 66;
	}

	char spawnflags[4];
	IntToString(flags, spawnflags, sizeof(spawnflags));
	DispatchKeyValue(explode, "targetname", targetname);
	DispatchKeyValue(explode, "spawnflags", spawnflags);
	DispatchKeyValue(explode, "rendermode", "5");
	DispatchKeyValue(explode, "fireballsprite", SPR_EXPLODE);

	SetEntPropEnt(explode, Prop_Data, "m_hOwnerEntity", owner);
	SetEntProp(explode, Prop_Data, "m_iMagnitude", damage);
	SetEntProp(explode, Prop_Data, "m_iRadiusOverride", radius);

	TeleportEntity(explode, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(explode);
	ActivateEntity(explode);
	AcceptEntityInput(explode, "Explode");
	AcceptEntityInput(explode, "Kill");
}

stock void DestroyStickyBomb(int client) {
	if (IsStickyBomb(g_iStickyBomb[client])) {
		AcceptEntityInput(g_iStickyBomb[client], "Kill");
		g_iStickyBomb[client] = -1;
	}
}

stock bool IsStickyBomb(int entity)
{
	if (!IsClassname(entity, "prop_dynamic")) return false;

	if (IsValidEntity(entity)) {
		char targetname[128];
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if (StrContains(targetname, "_stickybomb_") != -1 || StrContains(targetname, "_jumper_") != -1) return true;
	}

	return false;
}

stock void CreateCrosshair(int client)
{
	RemoveCrosshair(client);

	float pos[3];
	GetClientAbsOrigin(client, pos);

	// Create prop_physics entities
	char crosshairName[64];
	Format(crosshairName, sizeof(crosshairName), "crosshair_%d", client);

	int anchor = CreateEntityByName("prop_physics");
	DispatchKeyValue(anchor, "targetname", crosshairName);
	SetEntityMoveType(anchor, MOVETYPE_NOCLIP); 
	TeleportEntity(anchor, pos, NULL_VECTOR, NULL_VECTOR);

	g_iCrosshair[client] = anchor;

	// Create env_sprite entities
	char spriteName[64];
	Format(spriteName, sizeof(spriteName), "sprite_%d", client);
	
	int sprite = CreateEntityByName("env_sprite_oriented");
	DispatchKeyValueVector(sprite, "origin", pos);
	DispatchKeyValue(sprite, "targetname", spriteName);
	DispatchKeyValue(sprite, "spawnflags", "0");
	DispatchKeyValue(sprite, "scale", "0.5");
	DispatchKeyValue(sprite, "rendermode", "5");
	DispatchKeyValue(sprite, "rendercolor", "255 255 255");
	DispatchKeyValue(sprite, "renderamt", "255");
	DispatchKeyValue(sprite, "model", "vgui/crosshairs/crosshair2.vmt");
	SetEntPropEnt(sprite, Prop_Send, "m_hOwnerEntity", client);
	DispatchSpawn(sprite);
	AcceptEntityInput(sprite, "ShowSprite");

	DispatchKeyValue(sprite, "parentname", crosshairName);
	SetVariantString(crosshairName);
	AcceptEntityInput(sprite, "SetParent"); 

	SDKHook(sprite, SDKHook_SetTransmit, OnCrosshairTransmit);
	g_iCrosshairSprite[client] = sprite;

	// Create stickybomb indicator
	Format(spriteName, sizeof(spriteName), "sprite2_%d", client);

	int sprite2 = CreateEntityByName("env_sprite_oriented");
	DispatchKeyValueVector(sprite2, "origin", pos);
	DispatchKeyValue(sprite2, "targetname", spriteName);
	DispatchKeyValue(sprite2, "spawnflags", "0");
	DispatchKeyValue(sprite2, "scale", "0.25");
	DispatchKeyValue(sprite2, "rendermode", "5");
	DispatchKeyValue(sprite2, "rendercolor", "255 255 255");
	DispatchKeyValue(sprite2, "renderamt", "80");
	DispatchKeyValue(sprite2, "model", "vgui/crosshairs/tank/default_fix.vmt");
	SetEntPropEnt(sprite2, Prop_Send, "m_hOwnerEntity", client);
	DispatchSpawn(sprite2);
	AcceptEntityInput(sprite2, "ShowSprite");

	DispatchKeyValue(sprite2, "parentname", crosshairName);
	SetVariantString(crosshairName);
	AcceptEntityInput(sprite2, "SetParent"); 

	SDKHook(sprite2, SDKHook_SetTransmit, OnCrosshairTransmit);
	g_iStickySprite[client] = sprite2;

	int hidehud = GetEntProp(client, Prop_Data, "m_iHideHUD");
	if (!(hidehud & HIDEHUD_CROSSHAIR)) {
		hidehud |= HIDEHUD_CROSSHAIR;
		SetEntProp(client, Prop_Data, "m_iHideHUD", hidehud);
	}
}

public Action OnCrosshairTransmit(int entity, int client)
{
	if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") != client) return Plugin_Handled;
	if (!IsPlayerAlive(client)) return Plugin_Handled;
	return Plugin_Continue;
}

stock bool RemoveCrosshair(int client)
{
	if (IsValidEntity(g_iCrosshair[client])) {
		char name[128];
		GetEntPropString(g_iCrosshair[client], Prop_Data, "m_iName", name, sizeof(name));
		if (StrContains(name, "crosshair_") != -1) {
			AcceptEntityInput(g_iCrosshair[client], "Deactivate");
			AcceptEntityInput(g_iCrosshair[client], "Kill");

			int hidehud = GetEntProp(client, Prop_Data, "m_iHideHUD");
			if (hidehud & HIDEHUD_CROSSHAIR) {
				hidehud &= ~HIDEHUD_CROSSHAIR;
				SetEntProp(client, Prop_Data, "m_iHideHUD", hidehud);
			}

			g_iCrosshair[client] = -1;
			g_iCrosshairSprite[client] = -1;
			g_iStickySprite[client] = -1;
			return true;
		} 
	}

	return false;
}

stock void UpdateCrosshairAnchor(int client)
{
	if (IsValidEntity(g_iCrosshair[client])) {
		char name[128];
		GetEntPropString(g_iCrosshair[client], Prop_Data, "m_iName", name, sizeof(name));
		if (StrContains(name, "crosshair_") != -1) {
			float fPos[3];
			float fAng[3];
			float fVel[3];
			GetClientEyePosition(client, fPos);
			GetClientEyeAngles(client, fAng);
			fPos[2] -= 10.0;

			float fParam = GetEntPropFloat(client, Prop_Send, "m_flPoseParameter", 4);
			float fAim = (fParam-0.5) * 120.0;
			fAng[1] += fAim;

			bool clamped = false;
			if (fAng[0] < -50.0) {
				fAng[0] = -50.0;
				clamped = true;
			}
			else if (fAng[0] > 50.0) {
				fAng[0] = 50.0;
				clamped = true;
			}

			GetAngleVectors(fAng, fVel, NULL_VECTOR, NULL_VECTOR);
			fPos[0] += fVel[0] * 100.0;
			fPos[1] += fVel[1] * 100.0;
			fPos[2] += fVel[2] * 100.0;

			TeleportEntity(g_iCrosshair[client], fPos, NULL_VECTOR, fVel);

			// clamped crosshair colors
			if (clamped) SetEntityRenderColor(g_iCrosshairSprite[client], 255, 0, 0, 255);
			else SetEntityRenderColor(g_iCrosshairSprite[client], 255, 255, 255, 255);

			// stickybomb indicator colors
			int color[3];
			color[0] = 0;
			color[1] = 255;
			color[2] = 0;
			float time = GetGameTime();
			if (time < g_flNextStickyTime[client]) {
				color[0] = 255;
				color[1] = 0;
				color[2] = 0;
			}

			if (IsStickyBomb(g_iStickyBomb[client])) {
				color[0] = 255;
				color[1] = 150;
				color[2] = 0;
			}
			SetEntityRenderColor(g_iStickySprite[client], color[0], color[1], color[2], 50);
		}
	}
}

stock bool IsDirectHit(int victim, int inflictor, const float damage_pos[3])
{
	float pos[3];
	GetClientAbsOrigin(victim, pos);
	pos[2] = 0.0;

	float rocket_pos[3];
	//GetEntPropVector(inflictor, Prop_Data, "m_vecOrigin", rocket_pos);
	rocket_pos[0] = damage_pos[0];
	rocket_pos[1] = damage_pos[1];
	rocket_pos[2] = 0.0;

	float distance = GetVectorDistance(pos, rocket_pos);
	float target_dist = 24.0 * SquareRoot(2.0);
	//PrintToChatAll("dist %f, targetdist %f", distance, target_dist);
	if (distance > target_dist) return false;

	return true;
}

stock bool IsMapMVM()
{
	char mapname[PLATFORM_MAX_PATH];
	GetCurrentMap(mapname, sizeof(mapname));

	if (StrContains(mapname, "mvm_", false) == 0) return true;
	return false;
}

stock float AddPlayerUltimate(int client, float amount)
{
	float new_value = g_flUltimateDamage[client] + amount;
	if (new_value > g_cvUltimateCap.FloatValue) new_value = g_cvUltimateCap.FloatValue;

	g_flUltimateDamage[client] = new_value;
	return new_value;
}

stock bool IsPlayerUltimateFull(int client)
{
	return g_flUltimateDamage[client] >= g_cvUltimateCap.FloatValue;
}

stock void ActivatePlayerUltimate(int client)
{
	if (g_bUltimateMode[client]) return;

	FakeClientCommand(client, "voicemenu 2 1"); // battlecry
	g_bUltimateMode[client] = true;
}

stock void SetWeaponBonusMode(int client, bool bonus = false)
{
	int weapon = GetPlayerWeaponSlot(client, 0);
	if (!IsValidEntity(weapon)) return;
	
	Address attrib = TF2Attrib_GetByName(weapon, "mod max primary clip override");
	if (bonus) {
		if (attrib == Address_Null) {
			TF2Attrib_SetByName(weapon, "mod max primary clip override", -1.0);
			TF2Attrib_SetByName(weapon, "Projectile speed decreased", 0.5);
			TF2Attrib_SetByName(weapon, "Blast radius increased", g_cvUltimateRadius.FloatValue);
			TF2Attrib_SetByName(weapon, "maxammo primary reduced", 0.07);
		}
	}
	else {
		if (attrib != Address_Null) {
			TF2Attrib_RemoveByName(weapon, "mod max primary clip override");
			TF2Attrib_RemoveByName(weapon, "Projectile speed decreased");
			TF2Attrib_RemoveByName(weapon, "Blast radius increased");
			TF2Attrib_RemoveByName(weapon, "maxammo primary reduced");
		}
	}
}
stock bool IsWeaponInBonusMode(int weapon)
{
	if (!IsValidEntity(weapon)) return false;

	return (TF2Attrib_GetByName(weapon, "mod max primary clip override") != Address_Null);
}

stock bool IsRocketPowerShot(int rocket)
{
	if (!IsValidEntity(rocket)) return false;

	char classname[128];
	GetEdictClassname(rocket, classname, sizeof(classname));
	if (!StrEqual(classname, "tf_projectile_rocket")) return false;

	char targetname[128];
	GetEntPropString(rocket, Prop_Data, "m_iName", targetname, sizeof(targetname));
	if (StrContains(targetname, "_tank_rocket_ultimate") != -1) return true;

	return false;
}