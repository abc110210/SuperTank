/**
 * SuperTank 主文件
 * 包含所有Tank类型模块
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name = "SuperTank System",
    author = "Shan",
    description = "SuperTank系统 - 管理不同的Tank类型",
    version = "1.0.0",
    url = ""
};

// 全局变量
ConVar g_cvarVajraEnabled;

// Tank伤害配置
ConVar g_cvarTankDamage;

// 幸存者伤害Hook状态
bool g_bSurvivorHooksSetup = false;

// 标记：手动生成的Tank，防止Event_TankSpawn重复处理
bool g_bManualTankSpawn = false;

// 共享函数前向声明（让各模块可以互相调用清理函数）
void VajraTank_ClearAllEffects(int tank);
void ExplodeTank_ClearAllEffects(int tank);

// 爆炸Tank模块前向声明
void ExplodeTank_OnEntityCreated(int entity, const char[] classname);
bool ExplodeTank_IsTrackedRock(int index, int rockRef);
int ExplodeTank_GetCurrentTank();
void TriggerRockExplosion(float pos[3]);
void ExplodeTank_RemoveRockTracking(int rockRef);

// 包含各个Tank模块（必须在全局变量声明之后）
#include "VajraTank.sp"
#include "ExplodeTank.sp"

// ==================== 主要功能 ====================

public void OnPluginStart()
{
    // 金刚Tank配置
    g_cvarVajraEnabled = CreateConVar("shan_vajra_enabled", "1", "启用金刚Tank (0=禁用, 1=启用)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 1.0);
    CreateConVar("shan_Vajra_odds", "10", "金刚Tank生成概率 (0-100)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 100.0);
    CreateConVar("shan_Vajra_reflect", "10", "金刚Tank反弹概率 (0-100)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 100.0);
    CreateConVar("shan_Vajra_reflect_damage", "3", "金刚Tank反弹伤害基数 (1-100)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 1.0, true, 100.0);

    // 爆炸Tank配置
    CreateConVar("shan_ExplodeTank_odds", "90", "爆炸Tank生成概率 (0-100)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 100.0);
    CreateConVar("shan_ExplodeTank_explosion_damage", "50", "爆炸Tank爆炸伤害 (0-500)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 500.0);
    CreateConVar("shan_ExplodeTank_explosion_random", "100", "爆炸Tank爆炸概率 (1-100)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 1.0, true, 100.0);

    // 全局Tank配置
    CreateConVar("shan_tank_hp", "4000", "Tank动态生命值 (每名玩家增加的血量)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 10000.0);
    g_cvarTankDamage = CreateConVar("shan_tank_damage", "24", "Tank拳头伤害值 (1-1000)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 1.0, true, 1000.0);

    // 自动生成配置文件
    AutoExecConfig(true, "SuperTank");

    // 注册命令
    RegConsoleCmd("sm_supertank", Command_SuperTank, "打开SuperTank菜单");
    RegConsoleCmd("sm_tankconfig", Command_TankConfig, "显示Tank配置信息");

    // Hook事件
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("player_spawn", Event_PlayerSpawn);
}

public void OnMapStart()
{
    // 预缓存防护罩模型
    PrecacheModel("models/props_unique/airport/atlas_break_ball.mdl", true);

    // 预缓存爆炸模型（汽油罐和丙烷罐）
    PrecacheModel("models/props_junk/gascan001a.mdl", true);
    PrecacheModel("models/props_junk/propanecanister001a.mdl", true);

    // 预缓存爆炸精灵文件
    PrecacheGeneric("sprites/zerogxplode.spr", true);

    // 预缓存榴弹炮粒子特效文件（environmental_fx.pcf）
    PrecacheGeneric("particles/environmental_fx.pcf", true);
}

// 监听实体创建（用于石头跟踪）
public void OnEntityCreated(int entity, const char[] classname)
{
    ExplodeTank_OnEntityCreated(entity, classname);
}

// 监听实体销毁（用于石头击中玩家/障碍物时触发爆炸）
public void OnEntityDestroyed(int entity)
{
    char classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));

    if (StrEqual(classname, "tank_rock", false))
    {
        // 检查是否在跟踪列表中
        int rockRef = EntIndexToEntRef(entity);
        bool isExplodeTankRock = false;
        int thrower = -1;

        for (int i = 0; i < 128; i++)  // MAX_ROCKS
        {
            if (ExplodeTank_IsTrackedRock(i, rockRef))
            {
                isExplodeTankRock = true;
                // 获取投掷者
                thrower = GetEntPropEnt(entity, Prop_Data, "m_hThrower");
                break;
            }
        }

        if (isExplodeTankRock && thrower > 0)
        {
            // 检查是否是爆炸Tank的石头
            int currentTank = ExplodeTank_GetCurrentTank();
            if (thrower == currentTank)
            {
                PrintToServer("[爆炸TankDEBUG] 石头销毁（击中玩家/障碍物），触发爆炸!");

                // 清理石头跟踪
                ExplodeTank_RemoveRockTracking(rockRef);

                // 获取石头位置
                float rockPos[3];
                GetEntPropVector(entity, Prop_Data, "m_vecOrigin", rockPos);

                // 触发爆炸
                TriggerRockExplosion(rockPos);
            }
        }
    }
}

public void OnConfigsExecuted()
{
    PrintToServer("[寄寄之家 - SuperTank] 该插件已重载成功");
}

// ==================== 幸存者Hook设置 ====================

public void OnClientPutInServer(int client)
{
    // Hook所有玩家的伤害事件（用于检测Tank伤害）
    // 注意：在OnClientPutInServer时，客户端可能还未完全进入游戏，所以直接Hook
    SDKHook(client, SDKHook_OnTakeDamage, Hook_TankDamageOutput);
    PrintToServer("[HookDEBUG] 已Hook客户端 %d 的伤害事件", client);
}

// 石头爆炸检测（在OnTakeDamage中调用）
void CheckExplodeTankRock(int victim, int inflictor, float damage)
{
    PrintToServer("[爆炸TankDEBUG] ========== 石头检测开始 ==========");
    PrintToServer("[爆炸TankDEBUG] victim=%d, inflictor=%d, damage=%.1f", victim, inflictor, damage);

    // 检查inflictor是否有效
    if (inflictor <= 0)
    {
        PrintToServer("[爆炸TankDEBUG] inflictor无效，跳过检测");
        return;
    }

    // 检查是否是爆炸Tank的石头
    if (!ExplodeTank_IsTankRock(inflictor))
    {
        PrintToServer("[爆炸TankDEBUG] 不是爆炸Tank的石头");
        return;
    }

    PrintToServer("[爆炸TankDEBUG] 确认是爆炸Tank的石头!");

    // 检查是否打中幸存者
    if (victim > 0 && victim <= MaxClients && IsClientInGame(victim) && IsPlayerAlive(victim) && GetClientTeam(victim) == 2)
    {
        // 获取石头位置
        float rockPos[3];
        GetEntPropVector(inflictor, Prop_Data, "m_vecOrigin", rockPos);

        PrintToServer("[爆炸TankDEBUG] 石头击中幸存者，触发爆炸: pos=(%.1f,%.1f,%.1f)", rockPos[0], rockPos[1], rockPos[2]);

        // 触发爆炸
        TriggerRockExplosion(rockPos);
    }
    else
    {
        PrintToServer("[爆炸TankDEBUG] 受害者不是幸存者");
    }
}

// ==================== 菜单系统 ====================

public Action Command_TankConfig(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[寄寄之家 - SuperTank] 此命令只能由玩家使用");
        return Plugin_Handled;
    }

    if (!IsClientInGame(client))
        return Plugin_Handled;

    // 获取配置值
    ConVar cvarTankHP = FindConVar("shan_tank_hp");
    ConVar cvarTankDamage = FindConVar("shan_tank_damage");
    ConVar cvarVajraOdds = FindConVar("shan_Vajra_odds");
    ConVar cvarVajraReflect = FindConVar("shan_Vajra_reflect");
    ConVar cvarVajraReflectDamage = FindConVar("shan_Vajra_reflect_damage");
    ConVar cvarExplodeOdds = FindConVar("shan_ExplodeTank_odds");
    ConVar cvarExplodeRandom = FindConVar("shan_ExplodeTank_explosion_random");
    ConVar cvarExplodeDamage = FindConVar("shan_ExplodeTank_explosion_damage");

    // 计算当前难度基础血量
    int baseHP = GetDifficultyTankHP();
    int playerCount = GetOnlineSurvivorCount();
    int tankHPPerPlayer = (cvarTankHP != null) ? cvarTankHP.IntValue : 4000;
    int totalHP = baseHP + (tankHPPerPlayer * playerCount);

    // 显示配置信息
    PrintToChat(client, "\x01========== \x03[寄寄之家 - SuperTank]\x01 ==========");
    PrintToChat(client, "\x01Tank血量: \x04%d \x01(基础: %d + 玩家: %d × %d)", totalHP, baseHP, playerCount, tankHPPerPlayer);
    PrintToChat(client, "\x01Tank伤害: \x04%d", (cvarTankDamage != null) ? cvarTankDamage.IntValue : 24);
    PrintToChat(client, "\x01金刚Tank生成概率: \x04%d%%", (cvarVajraOdds != null) ? cvarVajraOdds.IntValue : 10);
    PrintToChat(client, "\x01金刚Tank反弹概率: \x04%d%%", (cvarVajraReflect != null) ? cvarVajraReflect.IntValue : 10);
    PrintToChat(client, "\x01金刚Tank反伤随机值: \x04%d ~ %d", (cvarVajraReflectDamage != null) ? cvarVajraReflectDamage.IntValue : 3, (cvarVajraReflectDamage != null) ? cvarVajraReflectDamage.IntValue * 2 : 6);
    PrintToChat(client, "\x01爆炸Tank生成概率: \x04%d%%", (cvarExplodeOdds != null) ? cvarExplodeOdds.IntValue : 90);
    PrintToChat(client, "\x01爆炸Tank爆炸概率: \x04%d%%", (cvarExplodeRandom != null) ? cvarExplodeRandom.IntValue : 100);
    PrintToChat(client, "\x01爆炸Tank爆炸伤害: \x04%d", (cvarExplodeDamage != null) ? cvarExplodeDamage.IntValue : 50);
    PrintToChat(client, "\x01====================================");

    return Plugin_Handled;
}

public Action Command_SuperTank(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[寄寄之家 - ControlTank] 此命令只能由玩家使用");
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
    menu.SetTitle("SuperTank - Tank类型管理");

    // 添加不同的Tank类型生成选项
    menu.AddItem("vajra", "生成金刚Tank");
    menu.AddItem("explode", "生成爆炸Tank");
    menu.AddItem("normal", "生成普通Tank");

    menu.ExitButton = true;
    menu.Display(client, 20);
}

public int Handler_SuperTankMenu(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "vajra"))
        {
            SpawnVajraTank(param1);
        }
        else if (StrEqual(info, "explode"))
        {
            SpawnExplodeTank(param1);
        }
        else if (StrEqual(info, "normal"))
        {
            SpawnNormalTank(param1);
        }

        // 重新显示菜单
        ShowSuperTankMenu(param1);
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
        return;

    // 标记为手动生成，防止Event_TankSpawn重复处理
    g_bManualTankSpawn = true;

    float pos[3], ang[3];
    GetClientAbsOrigin(client, pos);
    GetClientAbsAngles(client, ang);

    int tank = L4D2_SpawnTank(pos, ang);
    if (tank > 0)
    {
        // 调用模块函数
        VajraTank_Apply(tank);
    }

    // 延迟重置标记
    CreateTimer(1.0, Timer_ResetManualSpawn, _, TIMER_FLAG_NO_MAPCHANGE);
}

void SpawnExplodeTank(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    // 标记为手动生成，防止Event_TankSpawn重复处理
    g_bManualTankSpawn = true;

    float pos[3], ang[3];
    GetClientAbsOrigin(client, pos);
    GetClientAbsAngles(client, ang);

    int tank = L4D2_SpawnTank(pos, ang);
    if (tank > 0)
    {
        // 调用模块函数
        ExplodeTank_Apply(tank);
    }

    // 延迟重置标记
    CreateTimer(1.0, Timer_ResetManualSpawn, _, TIMER_FLAG_NO_MAPCHANGE);
}

void SpawnNormalTank(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    float pos[3], ang[3];
    GetClientAbsOrigin(client, pos);
    GetClientAbsAngles(client, ang);

    L4D2_SpawnTank(pos, ang);
}

// ==================== Tank生成事件 ====================

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    // 如果是手动生成的Tank，跳过自动处理
    if (g_bManualTankSpawn)
    {
        PrintToServer("[TankSpawnDEBUG] 跳过手动生成的Tank");
        return;
    }

    int tank = GetClientOfUserId(event.GetInt("userid"));
    if (tank <= 0 || !IsClientInGame(tank))
        return;

    PrintToServer("[TankSpawnDEBUG] Tank生成: tank=%d, userid=%d, name=%N", tank, event.GetInt("userid"), tank);

    // 随机选择Tank类型 (0-100)
    int random = GetRandomInt(1, 100);

    // 金刚Tank概率
    ConVar vajraOdds = FindConVar("shan_Vajra_odds");
    int vajraOddsValue = (vajraOdds != null) ? vajraOdds.IntValue : 30;

    // 爆炸Tank概率
    ConVar explodeOdds = FindConVar("shan_ExplodeTank_odds");
    int explodeOddsValue = (explodeOdds != null) ? explodeOdds.IntValue : 30;

    PrintToServer("[TankSpawnDEBUG] 随机数=%d, 金刚概率=%d, 爆炸概率=%d", random, vajraOddsValue, explodeOddsValue);

    // 根据概率选择Tank类型
    if (random <= vajraOddsValue)
    {
        PrintToServer("[TankSpawnDEBUG] 选择金刚Tank");
        VajraTank_Apply(tank);
    }
    else if (random <= vajraOddsValue + explodeOddsValue)
    {
        PrintToServer("[TankSpawnDEBUG] 选择爆炸Tank");
        ExplodeTank_Apply(tank);
    }
    else
    {
        PrintToServer("[TankSpawnDEBUG] 选择普通Tank");
    }
    // 剩余概率为普通Tank
}

public Action Timer_ResetManualSpawn(Handle timer)
{
    g_bManualTankSpawn = false;
    return Plugin_Stop;
}

// ==================== 玩家生成事件 ====================

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
        return;

    // 只Hook幸存者
    if (GetClientTeam(client) == 2)
    {
        SDKHook(client, SDKHook_OnTakeDamage, Hook_TankDamageOutput);
        PrintToServer("[HookDEBUG] 幸存者 %N 生成，已Hook伤害事件", client);
    }
}

// Tank输出伤害统一处理
public Action Hook_TankDamageOutput(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    // 调试：输出所有伤害事件
    if (inflictor > 0 && IsValidEntity(inflictor))
    {
        char classname[64];
        GetEntityClassname(inflictor, classname, sizeof(classname));
        if (StrEqual(classname, "tank_rock", false))
        {
            PrintToServer("[伤害HookDEBUG] 石头伤害: victim=%d, attacker=%d, inflictor=%d, damage=%.1f", victim, attacker, inflictor, damage);
        }
    }

    // 优先检查是否是爆炸Tank的石头伤害（石头伤害的attacker可能不是Tank）
    CheckExplodeTankRock(victim, inflictor, damage);

    // 检查攻击者是否是Tank
    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
        return Plugin_Continue;

    int zClass = GetEntProp(attacker, Prop_Send, "m_zombieClass");
    if (zClass != 8)
        return Plugin_Continue;

    // 应用全局Tank伤害值
    if (g_cvarTankDamage != null)
    {
        damage = g_cvarTankDamage.FloatValue;
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

// ==================== 事件处理 ====================

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
        return;

    // 检查是否是Tank
    int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
    if (zClass != 8)
        return;

    // 重置所有Tank效果和颜色
    ResetAllTankEffects(client);

    // 调用各模块的死亡处理
    VajraTank_OnDeath(client);
    ExplodeTank_OnDeath(client);
}

// 重置所有Tank效果（不重置颜色）
void ResetAllTankEffects(int tank)
{
    // 只重置防护罩等其他效果，保留颜色
    // 颜色会随Tank尸体保留
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    // 各模块会自动清理自己的状态
}

// ==================== 辅助函数 ====================

int GetOnlineSurvivorCount()
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            count++;
        }
    }
    return count;
}

int GetDifficultyTankHP()
{
    ConVar difficulty = FindConVar("z_difficulty");
    if (difficulty != null)
    {
        char diff[32];
        difficulty.GetString(diff, sizeof(diff));

        if (StrEqual(diff, "easy", false))
            return 3000;
        else if (StrEqual(diff, "normal", false))
            return 4000;
        else if (StrEqual(diff, "hard", false))
            return 5000;
        else if (StrEqual(diff, "impossible", false))
            return 6000;
    }

    return 4000;
}
