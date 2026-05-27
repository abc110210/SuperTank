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

// 包含各个Tank模块（必须在全局变量声明之后）
#include "VajraTank.sp"
#include "ExplodeTank.sp"

// ==================== 主要功能 ====================

public void OnPluginStart()
{
    // 金刚Tank配置
    g_cvarVajraEnabled = CreateConVar("shan_vajra_enabled", "1", "启用金刚Tank (0=禁用, 1=启用)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 1.0);
    CreateConVar("shan_Vajra_reflect_damage", "10", "金刚Tank反弹伤害基数 (1-100)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 1.0, true, 100.0);

    // 爆炸Tank配置
    CreateConVar("shan_ExplodeTank_explosion_damage", "50", "爆炸Tank爆炸伤害 (0-500)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 500.0);
    CreateConVar("shan_ExplodeTank_explosion_random", "100", "爆炸Tank爆炸概率 (1-100)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 1.0, true, 100.0);

    // 全局Tank配置
    g_cvarTankDamage = CreateConVar("shan_tank_damage", "24", "Tank拳头伤害值 (1-1000)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 1.0, true, 1000.0);

    // 注册命令
    RegConsoleCmd("sm_supertank", Command_SuperTank, "打开SuperTank菜单");

    // Hook事件
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("player_spawn", Event_PlayerSpawn);

    // 尝试多个可能的配置文件路径
    ServerCommand("exec sourcemod/SuperTank");
    ServerCommand("exec SuperTank");
}

public void OnMapStart()
{
    // 预缓存防护罩模型
    PrecacheModel("models/props_unique/airport/atlas_break_ball.mdl", true);
}

public void OnConfigsExecuted()
{
    PrintToServer("[寄寄之家 - SuperTank] 该插件已重载成功");
}

// ==================== 菜单系统 ====================

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

    float pos[3], ang[3];
    GetClientAbsOrigin(client, pos);
    GetClientAbsAngles(client, ang);

    int tank = L4D2_SpawnTank(pos, ang);
    if (tank > 0)
    {
        // 调用模块函数
        VajraTank_Apply(tank);
    }
}

void SpawnExplodeTank(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    float pos[3], ang[3];
    GetClientAbsOrigin(client, pos);
    GetClientAbsAngles(client, ang);

    int tank = L4D2_SpawnTank(pos, ang);
    if (tank > 0)
    {
        // 调用模块函数
        ExplodeTank_Apply(tank);
    }
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
    int tank = GetClientOfUserId(event.GetInt("userid"));
    if (tank <= 0 || !IsClientInGame(tank))
        return;

    // 随机选择Tank类型 (0-100)
    int random = GetRandomInt(1, 100);

    // 金刚Tank概率
    ConVar vajraOdds = FindConVar("shan_Vajra_odds");
    int vajraOddsValue = (vajraOdds != null) ? vajraOdds.IntValue : 30;

    // 爆炸Tank概率
    ConVar explodeOdds = FindConVar("shan_ExplodeTank_odds");
    int explodeOddsValue = (explodeOdds != null) ? explodeOdds.IntValue : 30;

    // 根据概率选择Tank类型
    if (random <= vajraOddsValue)
    {
        VajraTank_Apply(tank);
    }
    else if (random <= vajraOddsValue + explodeOddsValue)
    {
        ExplodeTank_Apply(tank);
    }
    // 剩余概率为普通Tank
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
    }
}

// Tank输出伤害统一处理
public Action Hook_TankDamageOutput(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
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

    // 调用各模块的死亡处理
    VajraTank_OnDeath(client);
    ExplodeTank_OnDeath(client);
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
