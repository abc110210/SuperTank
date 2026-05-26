/**
 * 爆炸Tank模块
 * 红色皮肤 + 石头双重爆炸
 */

// 存储爆炸位置的数据
float g_fExplosionPos[3];

// 爆炸Tank应用函数
void ExplodeTank_Apply(int tank)
{
    if (!IsClientInGame(tank))
        return;

    // 检查是否是Tank
    int zClass = GetEntProp(tank, Prop_Send, "m_zombieClass");
    if (zClass != 8)
        return;

    // 标记为爆炸Tank
    g_iExplodeTankEntRef = EntIndexToEntRef(tank);

    // 设置红色皮肤
    SetEntityRenderMode(tank, RENDER_NORMAL);
    SetEntityRenderColor(tank, 255, 0, 0, 255);

    // Hook实体创建事件来监听石头
    HookEntityOutput("prop_physics", "OnBreak", Hook_ExplodeTankRockBreak);

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

// 石头破碎时的爆炸处理
void Hook_ExplodeTankRockBreak(const char[] output, int caller, int activator, float delay)
{
    // 检查是否是爆炸Tank投掷的石头
    if (caller <= 0 || !IsValidEntity(caller))
        return;

    // 检查是否是石头实体
    char className[64];
    GetEntityClassname(caller, className, sizeof(className));
    if (!StrEqual(className, "prop_physics"))
        return;

    // 检查石头的模型是否是Tank石头
    char modelName[128];
    GetEntPropString(caller, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
    if (StrContains(modelName, "rock", false) == -1)
        return;

    // 爆炸概率检查
    ConVar explosionRandom = FindConVar("shan_ExplodeTank_explosion_random");
    int explosionChance = (explosionRandom != null) ? explosionRandom.IntValue : 100;

    if (GetRandomInt(1, 100) > explosionChance)
        return;  // 概率未通过，不产生爆炸

    // 获取当前位置
    float pos[3];
    GetEntPropVector(caller, Prop_Send, "m_vecOrigin", pos);

    // 创建第一次爆炸
    CreateExplosionEffect(pos, 1.5);

    // 存储位置用于第二次爆炸
    g_fExplosionPos[0] = pos[0];
    g_fExplosionPos[1] = pos[1];
    g_fExplosionPos[2] = pos[2];

    // 延迟创建第二次爆炸
    CreateTimer(0.2, Timer_ExplodeTankSecondExplosion, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ExplodeTankSecondExplosion(Handle timer)
{
    CreateExplosionEffect(g_fExplosionPos, 1.8);
    return Plugin_Stop;
}

// 创建爆炸效果
void CreateExplosionEffect(float pos[3], float scale)
{
    // 创建爆炸粒子效果
    int particle = CreateEntityByName("info_particle_system");
    if (particle != -1)
    {
        TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchKeyValue(particle, "effect_name", "gas_explosion");
        DispatchSpawn(particle);
        ActivateEntity(particle);

        AcceptEntityInput(particle, "Start");
        CreateTimer(0.5, Timer_RemoveExplosionParticle, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
    }

    // 造成爆炸伤害
    ConVar explosionDamage = FindConVar("shan_ExplodeTank_explosion_damage");
    int damage = (explosionDamage != null) ? explosionDamage.IntValue : 50;

    // 对范围内的玩家造成伤害
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
            }
        }
    }
}

public Action Timer_RemoveExplosionParticle(Handle timer, int particleRef)
{
    int particle = EntRefToEntIndex(particleRef);
    if (particle > 0 && IsValidEntity(particle))
    {
        AcceptEntityInput(particle, "Kill");
    }
    return Plugin_Stop;
}

// 清理爆炸Tank
void ExplodeTank_Clear()
{
    g_iExplodeTankEntRef = INVALID_ENT_REFERENCE;
}
