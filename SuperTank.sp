#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#pragma semicolon 1
#pragma newdecls required

#define DMG_BULLET (1 << 1)

public Plugin myinfo =
{
    name = "Super Tank",
    author = "Shan",
    description = "金刚Tank：黑色皮肤+防护罩+反弹伤害",
    version = "1.0.0",
    url = ""
};

ConVar g_cvarEnabled;
ConVar g_cvarSpawnOdds;
ConVar g_cvarReflectChance;
ConVar g_cvarTankHP;

bool g_bTankSpawning = false;
float g_fLastTankSpawnTime = 0.0;

// 记录特殊Tank的实体引用
int g_iSuperTankEntRef = INVALID_ENT_REFERENCE;

public void OnPluginStart()
{
    g_cvarEnabled = CreateConVar("shan_Vajra_enabled", "1", "启用或者禁用金刚Tank (0=禁用, 1=启用)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 1.0);
    g_cvarSpawnOdds = CreateConVar("shan_Vajra_odds", "50", "Ghost Tank变成金刚Tank的概率 1~100", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 1.0, true, 100.0);
    g_cvarReflectChance = CreateConVar("shan_Vajra_Tank", "40", "反弹子弹概率 1~100", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 1.0, true, 100.0);
    g_cvarTankHP = CreateConVar("shan_tank_hp", "4000", "每名玩家给Tank增加的血量", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 10000.0);

    RegConsoleCmd("sm_supertank", Command_SuperTank, "打开金刚Tank菜单");

    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("tank_spawn", Event_TankSpawn);
}

public void OnMapStart()
{
    g_bTankSpawning = false;
    g_fLastTankSpawnTime = 0.0;
    g_iSuperTankEntRef = INVALID_ENT_REFERENCE;
}

public void OnConfigsExecuted()
{
    PrintToServer("[寄寄の家 - SuperTank] 该插件已重载成功");
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_bTankSpawning = false;
    g_fLastTankSpawnTime = 0.0;
    g_iSuperTankEntRef = INVALID_ENT_REFERENCE;
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvarEnabled.BoolValue)
        return;

    float currentTime = GetGameTime();

    // 30秒内只处理一次
    if (currentTime - g_fLastTankSpawnTime < 30.0)
        return;

    g_fLastTankSpawnTime = currentTime;

    int tank = GetClientOfUserId(event.GetInt("userid"));

    if (tank <= 0 || !IsClientInGame(tank))
        return;

    // 根据配置的概率替换成金刚Tank
    int spawnOdds = g_cvarSpawnOdds.IntValue;
    if (GetRandomInt(1, 100) > spawnOdds)
        return;

    // 延迟设置属性
    CreateTimer(0.1, Timer_SetVajraTank, EntIndexToEntRef(tank), TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvarEnabled.BoolValue)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    // 检查是否是Tank
    if (GetClientTeam(client) != 3)
        return;

    int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
    if (zClass != 8)
        return;

    // 检查是否已经是金刚Tank
    int currentTank = EntRefToEntIndex(g_iSuperTankEntRef);
    if (currentTank == client)
        return;

    // 根据配置的概率替换成金刚Tank
    int spawnOdds = g_cvarSpawnOdds.IntValue;
    if (GetRandomInt(1, 100) > spawnOdds)
        return;

    // 延迟设置属性
    CreateTimer(0.1, Timer_SetVajraTank, EntIndexToEntRef(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SetVajraTank(Handle timer, int tankRef)
{
    int tank = EntRefToEntIndex(tankRef);
    if (tank <= 0 || !IsValidEntity(tank))
        return Plugin_Stop;

    if (!IsClientInGame(tank))
        return Plugin_Stop;

    // 再次检查是否是Tank
    int zClass = GetEntProp(tank, Prop_Send, "m_zombieClass");
    if (zClass != 8)
        return Plugin_Stop;

    // 标记为特殊Tank
    g_iSuperTankEntRef = tankRef;

    // 设置黑色皮肤 (注意：L4D2可能不支持m_skin属性)
    SetEntProp(tank, Prop_Send, "m_skin", 1);

    // 添加SDKHook反弹伤害
    SDKHook(tank, SDKHook_OnTakeDamage, Hook_OnTakeDamage);

    // 计算在线玩家数量
    int playerCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            playerCount++;
        }
    }

    // 获取难度默认血量
    int baseHP = GetDifficultyTankHP();

    // 计算最终血量：难度默认 + (配置值 × 玩家数量)
    int hpPerPlayer = g_cvarTankHP.IntValue;
    int finalHP = baseHP + (hpPerPlayer * playerCount);

    // 设置Tank血量
    SetEntProp(tank, Prop_Send, "m_iHealth", finalHP);
    SetEntProp(tank, Prop_Send, "m_iMaxHealth", finalHP);

    PrintToChatAll("\x03[金刚Tank] \x01金刚 \x04Tank \x01已生成！(皮肤:%d→1, 血量:%d)", currentSkin, finalHP);

    // 立即添加防护罩特效
    Timer_AddShieldEffect(null, tankRef);

    return Plugin_Stop;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
        return;

    // 检查死亡的是否是金刚Tank
    int currentTank = EntRefToEntIndex(g_iSuperTankEntRef);
    if (currentTank == client)
    {
        g_iSuperTankEntRef = INVALID_ENT_REFERENCE;
    }
}

public Action Timer_AddShieldEffect(Handle timer, int tankRef)
{
    int tank = EntRefToEntIndex(tankRef);
    if (tank <= 0 || !IsValidEntity(tank))
        return Plugin_Stop;

    // 创建防护罩特效粒子
    int particle = CreateEntityByName("info_particle_system");
    if (particle != -1)
    {
        float pos[3];
        GetEntPropVector(tank, Prop_Send, "m_vecOrigin", pos);

        TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);

        DispatchKeyValue(particle, "effect_name", "electro_shock_hands");
        DispatchKeyValue(particle, "targetname", "tank_shield");

        SetVariantString("!self");
        AcceptEntityInput(particle, "SetParent", tank, particle, 0);

        DispatchSpawn(particle);
        AcceptEntityInput(particle, "Start");

        PrintToChatAll("\x03[金刚Tank] \x01防护罩特效已添加 (实体:%d)", particle);

        // 30秒后移除特效
        CreateTimer(30.0, Timer_RemoveParticle, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        PrintToChatAll("\x03[金刚Tank] \x01防护罩特效创建失败");
    }

    return Plugin_Stop;
}

public Action Timer_RemoveParticle(Handle timer, int particleRef)
{
    int particle = EntRefToEntIndex(particleRef);
    if (particle > 0 && IsValidEntity(particle))
    {
        AcceptEntityInput(particle, "Kill");
    }
    return Plugin_Stop;
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    // 检查是否是特殊Tank
    int currentTank = EntRefToEntIndex(g_iSuperTankEntRef);
    if (victim != currentTank)
        return Plugin_Continue;

    // 检查攻击者是否是有效玩家
    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
        return Plugin_Continue;

    // 检查是否是子弹伤害
    if (!(damagetype & DMG_BULLET))
        return Plugin_Continue;

    // 根据配置的概率反弹
    int reflectChance = g_cvarReflectChance.IntValue;

    char attackerName[MAX_NAME_LENGTH];
    GetClientName(attacker, attackerName, sizeof(attackerName));

    // 测试：总是反弹（用于调试）
    PrintToChatAll("\x03[金刚Tank] \x01DEBUG: 反弹检查 概率:%d 随机:%d", reflectChance, GetRandomInt(1, 100));

    if (GetRandomInt(1, 100) <= reflectChance)
    {
        // 反弹伤害给攻击者
        SDKHooks_TakeDamage(attacker, victim, victim, damage, damagetype);

        // 显示反弹效果
        PrintToChatAll("\x03[金刚Tank] \x01攻击被反弹！ \x04%s \x01受到了 \x04%.0f \x01点伤害", attackerName, damage);

        // 阻止原伤害
        return Plugin_Handled;
    }

    PrintToChatAll("\x03[金刚Tank] \x01DEBUG: 反弹未触发，继续正常伤害");

    return Plugin_Continue;
}

int GetDifficultyTankHP()
{
    ConVar difficulty = FindConVar("z_difficulty");
    if (difficulty != null)
    {
        char diff[32];
        difficulty.GetString(diff, sizeof(diff));

        if (StrEqual(diff, "easy", false))
            return 3000;       // 简单
        else if (StrEqual(diff, "normal", false))
            return 4000;      // 普通
        else if (StrEqual(diff, "hard", false))
            return 5000;      // 困难
        else if (StrEqual(diff, "impossible", false))
            return 6000;      // 专家
    }

    return 4000; // 默认普通难度
}

public Action Command_SuperTank(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[寄寄の家-SuperTank] 此命令只能由玩家使用");
        return Plugin_Handled;
    }

    if (!IsClientInGame(client))
        return Plugin_Handled;

    ShowSuperTankMenu(client);
    return Plugin_Handled;
}

void ShowSuperTankMenu(int client)
{
    Menu menu = new Menu(Handler_SuperTankMenu);
    menu.SetTitle("金刚Tank 菜单");

    menu.AddItem("spawn", "生成金刚坦克");

    menu.ExitButton = true;
    menu.Display(client, 20);
}

public int Handler_SuperTankMenu(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "spawn"))
        {
            SpawnVajraTank(param1);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

void SpawnVajraTank(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
    {
        ReplyToCommand(client, "\x03[金刚Tank] \x01你需要活着才能生成Tank");
        return;
    }

    float pos[3], ang[3];
    GetClientAbsOrigin(client, pos);
    GetClientAbsAngles(client, ang);

    int tank = L4D2_SpawnTank(pos, ang);

    if (tank <= 0)
    {
        ReplyToCommand(client, "\x03[金刚Tank] \x01生成失败！");
        return;
    }

    ReplyToCommand(client, "\x03[金刚Tank] \x01已生成金刚Tank！");
    PrintToChatAll("\x03[金刚Tank] \x01玩家 \x04%N \x01生成了金刚Tank！", client);

    // 延迟设置属性
    CreateTimer(0.1, Timer_SetVajraTank, EntIndexToEntRef(tank), TIMER_FLAG_NO_MAPCHANGE);
}
