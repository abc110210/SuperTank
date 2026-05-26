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
int g_iVajraTankEntRef = INVALID_ENT_REFERENCE;
int g_iVajraShieldRef = INVALID_ENT_REFERENCE;

ConVar g_cvarVajraEnabled;

// 包含各个Tank模块（必须在全局变量声明之后）
#include "VajraTank.sp"

public void OnPluginStart()
{
    // 金刚Tank配置
    g_cvarVajraEnabled = CreateConVar("shan_vajra_enabled", "1", "启用金刚Tank (0=禁用, 1=启用)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 1.0);
    CreateConVar("shan_Vajra_reflect_damage", "10", "金刚Tank反弹伤害基数 (1-100)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 1.0, true, 100.0);

    // 注册命令
    RegConsoleCmd("sm_supertank", Command_SuperTank, "打开SuperTank菜单");

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
    // 延迟检查配置值
    CreateTimer(0.5, Timer_CheckConfig, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_CheckConfig(Handle timer)
{
    ConVar reflectDamageCvar = FindConVar("shan_Vajra_reflect_damage");
    if (reflectDamageCvar != null)
    {
        PrintToServer("[寄寄之家 - SuperTank] 反弹伤害配置值: %d", reflectDamageCvar.IntValue);
    }
    else
    {
        PrintToServer("[寄寄之家 - SuperTank] 错误: 找不到 shan_Vajra_reflect_damage 配置!");
    }

    return Plugin_Stop;
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

    // 根据概率决定是否生成金刚Tank
    ConVar vajraOdds = FindConVar("shan_Vajra_odds");
    int odds = (vajraOdds != null) ? vajraOdds.IntValue : 50;

    if (GetRandomInt(1, 100) <= odds)
    {
        VajraTank_Apply(tank);
    }
}

// ==================== 事件处理 ====================

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
        return;

    // 检查是否是金刚Tank
    int currentTank = EntRefToEntIndex(g_iVajraTankEntRef);
    if (currentTank == client)
    {
        // 恢复正常颜色
        ResetTankColor(client);

        g_iVajraTankEntRef = INVALID_ENT_REFERENCE;

        // 移除防护罩
        VajraTank_RemoveShield();
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_iVajraTankEntRef = INVALID_ENT_REFERENCE;
    g_iVajraShieldRef = INVALID_ENT_REFERENCE;
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
