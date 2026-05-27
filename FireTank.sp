/**
 * 燃烧Tank模块
 * 橙色皮肤 + 全身着火 + 免疫火焰 + 灼烧幸存者
 * 完全独立模块，不依赖其他模块
 */

#define MAX_BURN_PLAYERS 32

// 燃烧Tank独立的实体引用
static int g_iThisFireTankEntRef = INVALID_ENT_REFERENCE;

// 灼烧玩家列表（存储玩家userid）
static int g_iBurnPlayerUserIds[MAX_BURN_PLAYERS];
// 灼烧剩余时间（秒）
static int g_iBurnPlayerTime[MAX_BURN_PLAYERS];
static int g_iBurnPlayerCount = 0;

// 灼烧定时器
static Handle g_hBurnTimer = null;

// 燃烧Tank火焰维持定时器
static Handle g_hFireTimer = null;

// ==================== 辅助函数（供SuperTank.sp调用）====================

// 清理所有灼烧玩家效果
void FireTank_ClearAllBurnEffects()
{
    for (int i = 0; i < MAX_BURN_PLAYERS; i++)
    {
        g_iBurnPlayerUserIds[i] = -1;
        g_iBurnPlayerTime[i] = 0;
    }
    g_iBurnPlayerCount = 0;

    if (g_hBurnTimer != null)
    {
        KillTimer(g_hBurnTimer);
        g_hBurnTimer = null;
    }
}

// 清理火焰维持定时器
void FireTank_ClearFireTimer()
{
    if (g_hFireTimer != null)
    {
        KillTimer(g_hFireTimer);
        g_hFireTimer = null;
    }
}

// 火焰维持定时器（每0.1秒检查并重新点燃燃烧Tank）
public Action Timer_MaintainFire(Handle timer)
{
    int currentTank = EntRefToEntIndex(g_iThisFireTankEntRef);
    if (currentTank <= 0 || !IsClientInGame(currentTank) || !IsPlayerAlive(currentTank))
    {
        g_hFireTimer = null;
        return Plugin_Stop;
    }

    // 先熄灭再点燃（确保火焰持续）
    AcceptEntityInput(currentTank, "Extinguish");
    AcceptEntityInput(currentTank, "Ignite");

    return Plugin_Continue;
}

// 添加灼烧效果到玩家
void FireTank_AddBurnEffect(int client)
{
    int userid = GetClientUserId(client);

    // 检查是否已经在灼烧列表中
    for (int i = 0; i < g_iBurnPlayerCount; i++)
    {
        if (g_iBurnPlayerUserIds[i] == userid)
        {
            // 重置灼烧时间
            ConVar fireTime = FindConVar("shan_Firetank_fire_time");
            g_iBurnPlayerTime[i] = (fireTime != null) ? fireTime.IntValue : 10;
            return;
        }
    }

    // 添加到灼烧列表
    if (g_iBurnPlayerCount < MAX_BURN_PLAYERS)
    {
        g_iBurnPlayerUserIds[g_iBurnPlayerCount] = userid;

        // 获取配置的灼烧持续时间
        ConVar fireTime = FindConVar("shan_Firetank_fire_time");
        g_iBurnPlayerTime[g_iBurnPlayerCount] = (fireTime != null) ? fireTime.IntValue : 10;
        g_iBurnPlayerCount++;

        // 点燃玩家产生视觉特效
        if (IsClientInGame(client) && IsPlayerAlive(client))
        {
            // 先熄灭（防止重复叠加）
            AcceptEntityInput(client, "Extinguish");
            // 延迟一小段时间再点燃，确保视觉效果生效
            CreateTimer(0.1, Timer_IgnitePlayer, userid, TIMER_FLAG_NO_MAPCHANGE);
        }

        // 启动灼烧定时器（如果还未启动）
        if (g_hBurnTimer == null)
        {
            g_hBurnTimer = CreateTimer(1.0, Timer_BurnDamage, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

public Action Timer_IgnitePlayer(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
    {
        AcceptEntityInput(client, "Ignite");
    }
    return Plugin_Stop;
}

// 灼烧伤害定时器
public Action Timer_BurnDamage(Handle timer)
{
    // 获取配置的伤害值
    ConVar fireDamage = FindConVar("shan_Firetank_damage");
    int burnDamage = (fireDamage != null) ? fireDamage.IntValue : 3;

    int activeBurns = 0;

    for (int i = 0; i < g_iBurnPlayerCount; i++)
    {
        int userid = g_iBurnPlayerUserIds[i];
        int client = GetClientOfUserId(userid);

        if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
        {
            // 造成灼烧伤害
            SDKHooks_TakeDamage(client, 0, 0, burnDamage * 1.0, DMG_BURN);

            // 减少剩余时间
            g_iBurnPlayerTime[i]--;
            if (g_iBurnPlayerTime[i] <= 0)
            {
                // 灼烧结束，熄灭火焰
                AcceptEntityInput(client, "Extinguish");
                g_iBurnPlayerUserIds[i] = -1;
            }
            else
            {
                activeBurns++;
            }
        }
        else
        {
            // 玩家已死亡或离线，熄灭火焰并移除
            if (client > 0 && IsClientInGame(client))
            {
                AcceptEntityInput(client, "Extinguish");
            }
            g_iBurnPlayerUserIds[i] = -1;
        }
    }

    // 重新整理列表（移除无效玩家）
    int newCount = 0;
    for (int i = 0; i < g_iBurnPlayerCount; i++)
    {
        if (g_iBurnPlayerUserIds[i] != -1)
        {
            if (newCount != i)
            {
                g_iBurnPlayerUserIds[newCount] = g_iBurnPlayerUserIds[i];
                g_iBurnPlayerTime[newCount] = g_iBurnPlayerTime[i];
            }
            newCount++;
        }
    }
    g_iBurnPlayerCount = newCount;

    // 如果没有玩家被灼烧，停止定时器
    if (activeBurns == 0)
    {
        g_hBurnTimer = null;
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

// ==================== 燃烧Tank应用函数 ====================

void FireTank_Apply(int tank)
{
    if (!IsClientInGame(tank))
        return;

    // 检查是否是Tank
    int zClass = GetEntProp(tank, Prop_Send, "m_zombieClass");
    if (zClass != 8)
        return;

    // 先清理所有类型的旧效果
    FireTank_ClearAllEffects(tank);
    VajraTank_ClearAllEffects(tank);
    ExplodeTank_ClearAllEffects(tank);

    // 清理旧的灼烧效果
    FireTank_ClearAllBurnEffects();

    // 标记为燃烧Tank
    g_iThisFireTankEntRef = EntIndexToEntRef(tank);

    // 设置橙色皮肤
    SetEntityRenderMode(tank, RENDER_NORMAL);
    SetEntityRenderColor(tank, 255, 128, 0, 255);

    // 全身着火特效
    AcceptEntityInput(tank, "Ignite");

    // 启动火焰维持定时器（防止被水/雨浇灭）
    if (g_hFireTimer != null)
    {
        KillTimer(g_hFireTimer);
    }
    g_hFireTimer = CreateTimer(0.1, Timer_MaintainFire, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

    // 添加伤害Hook（用于免疫火焰和触发灼烧）
    SDKHook(tank, SDKHook_OnTakeDamage, Hook_FireOnTakeDamage);

    // 计算血量 (使用全局配置)
    int playerCount = GetOnlineSurvivorCount();
    int baseHP = GetDifficultyTankHP();
    ConVar tankHP = FindConVar("shan_tank_hp");
    int hpPerPlayer = (tankHP != null) ? tankHP.IntValue : 4000;
    int finalHP = baseHP + (hpPerPlayer * playerCount);

    SetEntProp(tank, Prop_Send, "m_iHealth", finalHP);
    SetEntProp(tank, Prop_Send, "m_iMaxHealth", finalHP);

    PrintToChatAll("\x03[寄寄之家 - SuperTank] \x01强力感染者 \x04燃烧Tank \x01已出现!");
}

// ==================== 燃烧Tank伤害处理 ====================

public Action Hook_FireOnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    // 检查是否是当前的燃烧Tank
    int currentTank = EntRefToEntIndex(g_iThisFireTankEntRef);
    if (victim != currentTank)
        return Plugin_Continue;

    // 免疫火焰伤害
    if (damagetype & DMG_BURN)
    {
        damage = 0.0;
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

// ==================== 燃烧Tank攻击处理 ====================

// Hook燃烧Tank的攻击事件（在SuperTank.sp中调用）
void FireTank_OnAttack(int victim, int attacker)
{
    // 检查攻击者是否是燃烧Tank
    int currentTank = EntRefToEntIndex(g_iThisFireTankEntRef);
    if (attacker != currentTank)
        return;

    // 检查受害者是否是幸存者
    if (victim > 0 && victim <= MaxClients && IsClientInGame(victim) && IsPlayerAlive(victim) && GetClientTeam(victim) == 2)
    {
        // 添加灼烧效果
        FireTank_AddBurnEffect(victim);
    }
}

// ==================== 清理函数 ====================

// 清理所有燃烧Tank效果
public void FireTank_ClearAllEffects(int tank)
{
    // 移除SDKHook
    int currentTank = EntRefToEntIndex(g_iThisFireTankEntRef);
    if (currentTank == tank)
    {
        SDKUnhook(tank, SDKHook_OnTakeDamage, Hook_FireOnTakeDamage);
    }

    // 清除引用
    if (currentTank == tank)
    {
        g_iThisFireTankEntRef = INVALID_ENT_REFERENCE;
    }

    // 清理火焰维持定时器
    FireTank_ClearFireTimer();
}

// 燃烧Tank死亡时清理
void FireTank_OnDeath(int tank)
{
    int currentFireTank = EntRefToEntIndex(g_iThisFireTankEntRef);
    if (currentFireTank == tank)
    {
        // 获取Tank死亡位置
        float deathPos[3];
        GetClientAbsOrigin(tank, deathPos);

        // 创建死亡爆炸火焰效果
        FireTank_CreateDeathExplosion(deathPos);

        g_iThisFireTankEntRef = INVALID_ENT_REFERENCE;
        FireTank_ClearAllBurnEffects();
        FireTank_ClearFireTimer();
    }
}

// ==================== 燃烧Tank死亡爆炸效果 ====================

// 创建可破坏的道具（用于火焰爆炸）
void FireTank_SpawnBreakProp(float pos[3], char[] model)
{
    int prop = CreateEntityByName("prop_physics_override");
    if (prop != -1)
    {
        SetEntityModel(prop, model);

        // 设置道具的生命值为1（这样任何伤害都会摧毁它）
        SetEntProp(prop, Prop_Data, "m_iHealth", 1);
        SetEntProp(prop, Prop_Data, "m_iMaxHealth", 1);

        // 设置随机旋转角度
        float angles[3];
        angles[0] = GetRandomFloat(0.0, 360.0);
        angles[1] = GetRandomFloat(0.0, 360.0);
        angles[2] = GetRandomFloat(0.0, 360.0);

        TeleportEntity(prop, pos, angles, NULL_VECTOR);
        DispatchSpawn(prop);
        ActivateEntity(prop);

        // 立即引爆道具
        AcceptEntityInput(prop, "Break");
    }
}

// 显示粒子特效
void FireTank_ShowParticle(float pos[3], char[] particleName)
{
    int particle = CreateEntityByName("info_particle_system");
    if (particle != -1)
    {
        TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
        SetEntPropString(particle, Prop_Data, "m_iszEffectName", particleName);
        DispatchSpawn(particle);
        ActivateEntity(particle);
        AcceptEntityInput(particle, "Start");

        // 5秒后删除粒子
        CreateTimer(5.0, Timer_DeleteFireParticle, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_DeleteFireParticle(Handle timer, int particleRef)
{
    int particle = EntRefToEntIndex(particleRef);
    if (particle > 0 && IsValidEntity(particle))
    {
        AcceptEntityInput(particle, "Kill");
    }
    return Plugin_Stop;
}

// 创建燃烧Tank死亡爆炸（大面积火焰）
void FireTank_CreateDeathExplosion(float pos[3])
{
    // 在地面上创建多个持续燃烧的火焰（像汽油罐爆炸后留下的火焰）
    for (int i = 0; i < 8; i++)
    {
        float offset[3];
        offset[0] = GetRandomFloat(-200.0, 200.0);
        offset[1] = GetRandomFloat(-200.0, 200.0);
        offset[2] = 0.0;

        float adjustedPos[3];
        AddVectors(pos, offset, adjustedPos);

        // 调整高度到地面
        adjustedPos[2] = pos[2];

        // 创建环境火焰实体
        int fire = CreateEntityByName("env_fire");
        if (fire != -1)
        {
            // 设置火焰属性
            SetEntPropFloat(fire, Prop_Data, "m_flFireScale", GetRandomFloat(1.5, 2.5));  // 火焰大小
            SetEntProp(fire, Prop_Data, "m_iFireMagnitude", 100);  // 火焰强度
            SetEntProp(fire, Prop_Data, "m_iFireAttack", 10);  // 火焰伤害
            SetEntPropFloat(fire, Prop_Data, "m_flLifetime", GetRandomFloat(8.0, 15.0));  // 持续时间（秒）
            SetEntProp(fire, Prop_Data, "m_bEnabled", 1);  // 启用

            TeleportEntity(fire, adjustedPos, NULL_VECTOR, NULL_VECTOR);
            DispatchSpawn(fire);
            ActivateEntity(fire);

            AcceptEntityInput(fire, "StartFire");

            // 火焰会在设定时间后自动熄灭
        }
    }

    // 创建汽油罐爆炸来产生初始的地面火焰
    for (int i = 0; i < 3; i++)
    {
        float offset[3];
        offset[0] = GetRandomFloat(-100.0, 100.0);
        offset[1] = GetRandomFloat(-100.0, 100.0);
        offset[2] = 0.0;

        float adjustedPos[3];
        AddVectors(pos, offset, adjustedPos);
        adjustedPos[2] = pos[2];

        FireTank_SpawnBreakProp(adjustedPos, "models/props_junk/gascan001a.mdl");
    }

    // 对周围幸存者造成灼烧效果
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            float playerPos[3];
            GetClientAbsOrigin(i, playerPos);

            float distance = GetVectorDistance(pos, playerPos, false);
            if (distance < 250.0)
            {
                // 添加灼烧效果
                FireTank_AddBurnEffect(i);
            }
        }
    }
}
