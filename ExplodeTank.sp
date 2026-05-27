/**
 * 爆炸Tank模块
 * 红色皮肤 + 石头双重爆炸
 * 完全独立模块，不依赖其他模块
 */

// 爆炸Tank独立的实体引用
static int g_iThisExplodeTankEntRef = INVALID_ENT_REFERENCE;
static float g_fExplodeExplosionPos[3];

// 爆炸Tank应用函数
void ExplodeTank_Apply(int tank)
{
    if (!IsClientInGame(tank))
        return;

    // 检查是否是Tank
    int zClass = GetEntProp(tank, Prop_Send, "m_zombieClass");
    if (zClass != 8)
        return;

    // 先清理旧效果（如果有）
    ExplodeTank_ClearEffects(tank);

    // 标记为爆炸Tank
    g_iThisExplodeTankEntRef = EntIndexToEntRef(tank);

    // 设置红色皮肤
    SetEntityRenderMode(tank, RENDER_NORMAL);
    SetEntityRenderColor(tank, 255, 0, 0, 255);

    // Hook所有实体输出事件（独立Hook）
    HookEntityOutput("tank_rock", "OnKilled", Hook_ExplodeTankRockKilled);
    HookEntityOutput("tank_rock", "OnBreak", Hook_ExplodeTankRockKilled);
    HookEntityOutput("prop_physics", "OnBreak", Hook_ExplodeTankRockKilled);

    PrintToServer("[爆炸TankDEBUG] 已Hook石头事件");

    // 计算血量 (使用全局配置)
    int playerCount = GetOnlineSurvivorCount();
    int baseHP = GetDifficultyTankHP();
    ConVar tankHP = FindConVar("shan_tank_hp");
    int hpPerPlayer = (tankHP != null) ? tankHP.IntValue : 4000;
    int finalHP = baseHP + (hpPerPlayer * playerCount);

    SetEntProp(tank, Prop_Send, "m_iHealth", finalHP);
    SetEntProp(tank, Prop_Send, "m_iMaxHealth", finalHP);

    PrintToChatAll("\x03[寄寄之家 - SuperTank] \x01强力感染者 \x02爆炸Tank \x01已出现!");
}

// 清理爆炸Tank效果
void ExplodeTank_ClearEffects(int tank)
{
    // 重置Tank颜色
    SetEntityRenderMode(tank, RENDER_NORMAL);
    SetEntityRenderColor(tank, 255, 255, 255, 255);
}

// Tank石头被杀死/破坏时的处理
void Hook_ExplodeTankRockKilled(const char[] output, int caller, int activator, float delay)
{
    PrintToServer("[爆炸TankDEBUG] 石头事件触发: output=%s, caller=%d", output, caller);

    if (caller <= 0 || !IsValidEntity(caller))
        return;

    // 获取实体类名
    char className[64];
    GetEntityClassname(caller, className, sizeof(className));

    // 获取模型名称
    char modelName[128];
    GetEntPropString(caller, Prop_Data, "m_ModelName", modelName, sizeof(modelName));

    // 检查是否是石头模型
    if (StrContains(modelName, "rock", false) == -1 && StrContains(className, "tank_rock", false) == -1)
        return;

    PrintToChatAll("[爆炸Tank] 检测到Tank石头破碎!");

    // 爆炸概率检查
    ConVar explosionRandom = FindConVar("shan_ExplodeTank_explosion_random");
    int explosionChance = (explosionRandom != null) ? explosionRandom.IntValue : 100;

    if (GetRandomInt(1, 100) > explosionChance)
    {
        PrintToChatAll("[爆炸Tank] 爆炸概率未通过");
        return;
    }

    // 获取当前位置
    float pos[3];
    GetEntPropVector(caller, Prop_Send, "m_vecOrigin", pos);

    PrintToChatAll("[爆炸Tank] 创建爆炸! 位置: %.1f, %.1f, %.1f", pos[0], pos[1], pos[2]);

    // 创建第一次爆炸
    ExplodeTank_CreateExplosion(pos, 1.5);

    // 存储位置用于第二次爆炸
    g_fExplodeExplosionPos[0] = pos[0];
    g_fExplodeExplosionPos[1] = pos[1];
    g_fExplodeExplosionPos[2] = pos[2];

    // 延迟创建第二次爆炸
    CreateTimer(0.2, Timer_ExplodeTankSecondExplosion, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ExplodeTankSecondExplosion(Handle timer)
{
    ExplodeTank_CreateExplosion(g_fExplodeExplosionPos, 1.8);
    PrintToChatAll("[爆炸Tank] 第二次爆炸触发!");
    return Plugin_Stop;
}

// 创建爆炸效果（独立函数）
void ExplodeTank_CreateExplosion(float pos[3], float scale)
{
    PrintToServer("[爆炸TankDEBUG] 开始创建爆炸效果，scale=%.1f", scale);

    // 创建爆炸粒子效果
    int particle = CreateEntityByName("info_particle_system");
    if (particle != -1)
    {
        TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchKeyValue(particle, "effect_name", "gas_explosion");
        DispatchSpawn(particle);
        ActivateEntity(particle);

        AcceptEntityInput(particle, "Start");
        CreateTimer(0.5, Timer_ExplodeTankRemoveParticle, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);

        PrintToServer("[爆炸TankDEBUG] 粒子系统已创建: ent=%d", particle);
    }
    else
    {
        PrintToServer("[爆炸TankDEBUG] 粒子系统创建失败!");
    }

    // 造成爆炸伤害
    ConVar explosionDamage = FindConVar("shan_ExplodeTank_explosion_damage");
    int damage = (explosionDamage != null) ? explosionDamage.IntValue : 50;

    // 对范围内的玩家造成伤害
    int hitCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            float playerPos[3];
            GetClientAbsOrigin(i, playerPos);

            float distance = GetVectorDistance(pos, playerPos, false);
            if (distance < 300.0 * scale)
            {
                float actualDamage = damage * (1.0 - (distance / (300.0 * scale)));
                SDKHooks_TakeDamage(i, 0, 0, actualDamage, DMG_BLAST);
                hitCount++;
                PrintToServer("[爆炸TankDEBUG] 命中玩家%d: 伤害=%.1f, 距离=%.1f", i, actualDamage, distance);
            }
        }
    }

    PrintToChatAll("[爆炸Tank] 爆炸完成! 伤害=%d, 命中=%d人", damage, hitCount);
}

public Action Timer_ExplodeTankRemoveParticle(Handle timer, int particleRef)
{
    int particle = EntRefToEntIndex(particleRef);
    if (particle > 0 && IsValidEntity(particle))
    {
        AcceptEntityInput(particle, "Kill");
    }
    return Plugin_Stop;
}

// 爆炸Tank死亡时清理
void ExplodeTank_OnDeath(int tank)
{
    int currentExplodeTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);
    if (currentExplodeTank == tank)
    {
        g_iThisExplodeTankEntRef = INVALID_ENT_REFERENCE;
    }
}
