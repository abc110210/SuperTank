/**
 * 金刚Tank模块
 * 黑色皮肤 + 防护罩 + 伤害反弹
 */

#define DMG_BULLET (1 << 1)

// 金刚Tank应用函数
void VajraTank_Apply(int tank)
{
    if (!IsClientInGame(tank))
        return;

    // 检查是否是Tank
    int zClass = GetEntProp(tank, Prop_Send, "m_zombieClass");
    if (zClass != 8)
        return;

    // 标记为金刚Tank
    g_iVajraTankEntRef = EntIndexToEntRef(tank);

    // 设置黑色皮肤
    SetEntityRenderMode(tank, RENDER_NORMAL);
    SetEntityRenderColor(tank, 0, 0, 0, 255);

    // 添加SDKHook反弹伤害
    SDKHook(tank, SDKHook_OnTakeDamage, Hook_VajraOnTakeDamage);
    SDKHook(tank, SDKHook_OnTakeDamagePost, Hook_VajraOnTakeDamagePost);

    // 计算血量 (使用全局配置)
    int playerCount = GetOnlineSurvivorCount();
    int baseHP = GetDifficultyTankHP();
    ConVar tankHP = FindConVar("shan_tank_hp");
    int hpPerPlayer = (tankHP != null) ? tankHP.IntValue : 4000;
    int finalHP = baseHP + (hpPerPlayer * playerCount);

    SetEntProp(tank, Prop_Send, "m_iHealth", finalHP);
    SetEntProp(tank, Prop_Send, "m_iMaxHealth", finalHP);

    PrintToChatAll("\x04[寄寄之家 - SuperTank] \x05金刚Tank\x01已出现!");

    // 添加防护罩
    VajraTank_CreateShield(tank);
}

void VajraTank_CreateShield(int tank)
{
    int shield = CreateEntityByName("prop_dynamic_override");
    if (shield != -1)
    {
        float pos[3];
        GetClientAbsOrigin(tank, pos);
        pos[2] -= 120.0;

        SetEntityModel(shield, "models/props_unique/airport/atlas_break_ball.mdl");
        TeleportEntity(shield, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchSpawn(shield);

        // 附着到Tank
        SetVariantString("!activator");
        AcceptEntityInput(shield, "SetParent", tank, shield, 0);

        // 黑色透明效果
        SetEntityRenderMode(shield, RENDER_TRANSTEXTURE);
        SetEntityRenderColor(shield, 0, 0, 0, 180);

        // 黑色反光
        SetEntProp(shield, Prop_Send, "m_glowColorOverride", 50);
        SetEntProp(shield, Prop_Send, "m_nGlowRange", 300);
        SetEntProp(shield, Prop_Send, "m_iGlowType", 3);

        // 不阻挡移动
        SetEntProp(shield, Prop_Send, "m_CollisionGroup", 1);

        g_iVajraShieldRef = EntIndexToEntRef(shield);
    }
}

void VajraTank_RemoveShield()
{
    int shield = EntRefToEntIndex(g_iVajraShieldRef);
    if (shield > 0 && IsValidEntity(shield))
    {
        AcceptEntityInput(shield, "Kill");
    }
    g_iVajraShieldRef = INVALID_ENT_REFERENCE;
}

public Action Hook_VajraOnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    // 检查是否是金刚Tank
    int currentTank = EntRefToEntIndex(g_iVajraTankEntRef);
    if (victim != currentTank)
        return Plugin_Continue;

    // 检查攻击者是否是有效玩家
    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
        return Plugin_Continue;

    // 检查是否是子弹伤害
    if (!(damagetype & DMG_BULLET))
        return Plugin_Continue;

    // 反弹概率检查 (使用全局配置)
    ConVar reflectChance = FindConVar("shan_Vajra_reflect");
    int reflectValue = (reflectChance != null) ? reflectChance.IntValue : 40;
    if (GetRandomInt(1, 100) <= reflectValue)
    {
        // 反弹伤害
        SDKHooks_TakeDamage(attacker, victim, victim, damage, damagetype);

        // 私聊提示
        PrintToChat(attacker, "\x04[寄寄之家 - SuperTank] \x01你的攻击被\x04反弹\x01你受到了\x04%.0f\x01点伤害", damage);

        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public Action Hook_VajraOnTakeDamagePost(int victim, int attacker, int inflictor, float &damage, int &damagetype, int &weapon)
{
    // 检查是否是金刚Tank
    int currentTank = EntRefToEntIndex(g_iVajraTankEntRef);
    if (victim != currentTank)
        return Plugin_Continue;

    // 应用固定伤害值 (使用全局配置)
    ConVar damageValue = FindConVar("shan_tank_damage");
    if (damageValue != null)
    {
        damage = damageValue.FloatValue;
    }

    return Plugin_Changed;
}
