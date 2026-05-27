/**
 * 金刚Tank模块
 * 黑色皮肤 + 防护罩 + 伤害反弹
 * 完全独立模块，不依赖其他模块
 */

#define DMG_BULLET (1 << 1)

// 金刚Tank独立的实体引用
static int g_iThisVajraTankEntRef = INVALID_ENT_REFERENCE;
static int g_iThisVajraShieldRef = INVALID_ENT_REFERENCE;

// 金刚Tank应用函数
void VajraTank_Apply(int tank)
{
    if (!IsClientInGame(tank))
        return;

    // 检查是否是Tank
    int zClass = GetEntProp(tank, Prop_Send, "m_zombieClass");
    if (zClass != 8)
        return;

    // 先清理所有类型的旧效果（重要：防止不同Tank类型之间的干扰）
    VajraTank_ClearAllEffects(tank);
    ExplodeTank_ClearAllEffects(tank);

    // 标记为金刚Tank
    g_iThisVajraTankEntRef = EntIndexToEntRef(tank);

    // 设置黑色皮肤
    SetEntityRenderMode(tank, RENDER_NORMAL);
    SetEntityRenderColor(tank, 0, 0, 0, 255);

    // 添加SDKHook反弹伤害
    SDKHook(tank, SDKHook_OnTakeDamage, Hook_VajraOnTakeDamage);

    // 计算血量 (使用全局配置)
    int playerCount = GetOnlineSurvivorCount();
    int baseHP = GetDifficultyTankHP();
    ConVar tankHP = FindConVar("shan_tank_hp");
    int hpPerPlayer = (tankHP != null) ? tankHP.IntValue : 4000;
    int finalHP = baseHP + (hpPerPlayer * playerCount);

    SetEntProp(tank, Prop_Send, "m_iHealth", finalHP);
    SetEntProp(tank, Prop_Send, "m_iMaxHealth", finalHP);

    PrintToChatAll("\x03[寄寄之家 - SuperTank] \x01强力感染者 \x04金刚Tank \x01已出现!");

    // 添加防护罩
    VajraTank_CreateShield(tank);
}

// 创建金刚Tank防护罩
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

        g_iThisVajraShieldRef = EntIndexToEntRef(shield);
    }
}

// 清理所有金刚Tank效果（包括移除Hook）
void VajraTank_ClearAllEffects(int tank)
{
    // 移除SDKHook（重要：防止Hook残留）
    SDKUnhook(tank, SDKHook_OnTakeDamage, Hook_VajraOnTakeDamage);

    // 移除防护罩
    VajraTank_RemoveShield();

    // 清除引用
    int currentVajraTank = EntRefToEntIndex(g_iThisVajraTankEntRef);
    if (currentVajraTank == tank)
    {
        g_iThisVajraTankEntRef = INVALID_ENT_REFERENCE;
    }
}

// 清理金刚Tank效果（保留颜色）
void VajraTank_ClearEffects(int tank)
{
    // 只移除防护罩，保留颜色和Hook
    int currentVajraTank = EntRefToEntIndex(g_iThisVajraTankEntRef);
    if (currentVajraTank == tank)
    {
        VajraTank_RemoveShield();
    }
}

// 移除金刚Tank防护罩
void VajraTank_RemoveShield()
{
    int shield = EntRefToEntIndex(g_iThisVajraShieldRef);
    if (shield > 0 && IsValidEntity(shield))
    {
        AcceptEntityInput(shield, "Kill");
    }
    g_iThisVajraShieldRef = INVALID_ENT_REFERENCE;
}

// 金刚Tank受到伤害时的反弹处理
public Action Hook_VajraOnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    // 检查是否是当前的金刚Tank
    int currentTank = EntRefToEntIndex(g_iThisVajraTankEntRef);
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
    int reflectValue = (reflectChance != null) ? reflectChance.IntValue : 10;

    if (GetRandomInt(1, 100) <= reflectValue)
    {
        // 计算反弹伤害 (配置值 ~ 配置值×2)
        ConVar reflectDamageCvar = FindConVar("shan_Vajra_reflect_damage");
        int baseDamage = (reflectDamageCvar != null) ? reflectDamageCvar.IntValue : 10;
        float randomDamage = GetRandomInt(baseDamage, baseDamage * 2) * 1.0;

        // 反弹伤害
        SDKHooks_TakeDamage(attacker, victim, victim, randomDamage, damagetype);

        // 私聊提示
        PrintToChat(attacker, "\x03[寄寄之家 - SuperTank] \x01你的攻击被 \x04反弹 \x01你受到了 \x04%.0f \x01点伤害", randomDamage);

        return Plugin_Handled;
    }

    return Plugin_Continue;
}

// 金刚Tank死亡时清理
void VajraTank_OnDeath(int tank)
{
    int currentVajraTank = EntRefToEntIndex(g_iThisVajraTankEntRef);
    if (currentVajraTank == tank)
    {
        VajraTank_RemoveShield();
        g_iThisVajraTankEntRef = INVALID_ENT_REFERENCE;
    }
}
