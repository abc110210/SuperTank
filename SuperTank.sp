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

// 函数原型声明
public Action Command_TestRock(int client, int args);
public Action Timer_TriggerExplosion(Handle timer, DataPack pack);
void TestExplosionEffect(float pos[3]);

// 全局变量
int g_iVajraTankEntRef = INVALID_ENT_REFERENCE;
int g_iVajraShieldRef = INVALID_ENT_REFERENCE;
int g_iExplodeTankEntRef = INVALID_ENT_REFERENCE;

ConVar g_cvarVajraEnabled;

// 包含各个Tank模块（必须在全局变量声明之后）
#include "VajraTank.sp"
#include "ExplodeTank.sp"

public void OnPluginStart()
{
    // 金刚Tank配置
    g_cvarVajraEnabled = CreateConVar("shan_vajra_enabled", "1", "启用金刚Tank (0=禁用, 1=启用)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 1.0);
    CreateConVar("shan_Vajra_reflect_damage", "10", "金刚Tank反弹伤害基数 (1-100)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 1.0, true, 100.0);

    // 爆炸Tank配置
    CreateConVar("shan_ExplodeTank_explosion_damage", "50", "爆炸Tank爆炸伤害 (0-500)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 500.0);
    CreateConVar("shan_ExplodeTank_explosion_random", "100", "爆炸Tank爆炸概率 (1-100)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 1.0, true, 100.0);

    // 注册命令
    RegConsoleCmd("sm_supertank", Command_SuperTank, "打开SuperTank菜单");
    RegAdminCmd("sm_testrock", Command_TestRock, ADMFLAG_CHEATS, "测试Tank石头爆炸");

    // Hook事件
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("tank_spawn", Event_TankSpawn);

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

public Action Command_TestRock(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[寄寄之家 - SuperTank] 此命令只能由玩家使用");
        return Plugin_Handled;
    }

    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Handled;

    // 获取玩家位置
    float pos[3], ang[3];
    GetClientAbsOrigin(client, pos);
    GetClientAbsAngles(client, ang);

    // 在玩家前方创建石头
    float forward[3];
    GetAngleVectors(ang, forward, NULL_VECTOR, NULL_VECTOR);
    pos[0] += forward[0] * 200.0;
    pos[1] += forward[1] * 200.0;
    pos[2] += forward[2] * 200.0;

    ReplyToCommand(client, "[寄寄之家 - SuperTank] 2秒后将在你前方生成爆炸测试...");

    // 2秒后触发爆炸效果
    DataPack pack = new DataPack();
    pack.WriteFloat(pos[0]);
    pack.WriteFloat(pos[1]);
    pack.WriteFloat(pos[2]);
    CreateTimer(2.0, Timer_TriggerExplosion, pack, TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Handled;
}

public Action Timer_TriggerExplosion(Handle timer, DataPack pack)
{
    pack.Reset();
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    delete pack;

    // 直接调用爆炸函数
    TestExplosionEffect(pos);
    return Plugin_Stop;
}

// 测试爆炸效果函数
void TestExplosionEffect(float pos[3])
{
    PrintToChatAll("[爆炸Tank] 测试爆炸触发! 位置: %.1f, %.1f, %.1f", pos[0], pos[1], pos[2]);

    // 创建第一次爆炸
    CreateExplosionEffect(pos, 1.5);

    // 存储位置用于第二次爆炸
    g_fExplosionPos[0] = pos[0];
    g_fExplosionPos[1] = pos[1];
    g_fExplosionPos[2] = pos[2];

    // 延迟创建第二次爆炸
    CreateTimer(0.2, Timer_ExplodeTankSecondExplosion, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Command_SuperTank(int client, int args)

public Action Timer_RemoveRock(Handle timer, int rockRef)
{
    int rock = EntRefToEntIndex(rockRef);
    if (rock > 0 && IsValidEntity(rock))
    {
        AcceptEntityInput(rock, "Kill");
    }
    return Plugin_Stop;
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

    int tank = L4D2_SpawnTank(pos, ang);
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

// ==================== 事件处理 ====================

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
        return;

    // 检查是否是金刚Tank
    int currentVajraTank = EntRefToEntIndex(g_iVajraTankEntRef);
    if (currentVajraTank == client)
    {
        // 恢复正常颜色
        ResetTankColor(client);

        g_iVajraTankEntRef = INVALID_ENT_REFERENCE;

        // 移除防护罩
        VajraTank_RemoveShield();
    }

    // 检查是否是爆炸Tank
    int currentExplodeTank = EntRefToEntIndex(g_iExplodeTankEntRef);
    if (currentExplodeTank == client)
    {
        // 恢复正常颜色
        ResetTankColor(client);

        // 清理爆炸Tank
        ExplodeTank_Clear();
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_iVajraTankEntRef = INVALID_ENT_REFERENCE;
    g_iVajraShieldRef = INVALID_ENT_REFERENCE;
    g_iExplodeTankEntRef = INVALID_ENT_REFERENCE;
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

void ResetTankColor(int tank)
{
    SetEntityRenderMode(tank, RENDER_NORMAL);
    SetEntityRenderColor(tank, 255, 255, 255, 255);
}
