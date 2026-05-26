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

    // Hook Tank的攻击事件
    SDKHook(tank, SDKHook_OnTakeDamagePost, Hook_ExplodeTankAttack);

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

// Tank攻击后的处理（检测石头投掷）
public void Hook_ExplodeTankAttack(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon)
{
    // 检查攻击者是否是爆炸Tank
    int currentTank = EntRefToEntIndex(g_iExplodeTankEntRef);
    if (attacker != currentTank)
        return;

    // 检查是否是近战攻击（投掷石头）
    if (damagetype & DMG_SLASH)
    {
        PrintToServer("[爆炸TankDEBUG] Tank投掷攻击检测到");

        // 延迟检查是否有石头实体被创建
        CreateTimer(0.1, Timer_CheckForRocks, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

// 检查周围的石头实体
public Action Timer_CheckForRocks(Handle timer)
{
    int currentTank = EntRefToEntIndex(g_iExplodeTankEntRef);
    if (currentTank <= 0)
        return Plugin_Stop;

    float tankPos[3];
    GetClientAbsOrigin(currentTank, tankPos);

    // 搜索周围的石头实体
    int rockCount = 0;
    for (int i = MaxClients + 1; i < GetMaxEntities(); i++)
    {
        if (!IsValidEntity(i))
            continue;

        char className[64];
        GetEntityClassname(i, className, sizeof(className));

        // 检查是否是石头相关实体
        if (StrContains(className, "tank_rock", false) != -1 ||
            StrContains(className, "prop_physics", false) != -1)
        {
            char modelName[128];
            GetEntPropString(i, Prop_Data, "m_ModelName", modelName, sizeof(modelName));

            if (StrContains(modelName, "rock", false) != -1)
            {
                float rockPos[3];
                GetEntPropVector(i, Prop_Send, "m_vecOrigin", rockPos);

                float distance = GetVectorDistance(tankPos, rockPos, false);
                if (distance < 500.0)
                {
                    PrintToServer("[爆炸TankDEBUG] 发现石头实体: ent=%d, model=%s", i, modelName);
                    rockCount++;

                    // Hook这个石头的销毁事件
                    SDKHook(i, SDKHook_OnTakeDamagePost, Hook_RockDestroyed);
                }
            }
        }
    }

    PrintToServer("[爆炸TankDEBUG] 共发现 %d 个石头实体", rockCount);
    return Plugin_Stop;
}

// 石头被销毁时触发爆炸
public void Hook_RockDestroyed(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon)
{
    // 检查是否是石头
    char modelName[128];
    GetEntPropString(victim, Prop_Data, "m_ModelName", modelName, sizeof(modelName));

    if (StrContains(modelName, "rock", false) == -1)
        return;

    PrintToChatAll("[爆炸Tank] 石头被破坏! model=%s", modelName);

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
    GetEntPropVector(victim, Prop_Send, "m_vecOrigin", pos);

    PrintToChatAll("[爆炸Tank] 创建爆炸! 位置: %.1f, %.1f, %.1f", pos[0], pos[1], pos[2]);

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
    PrintToChatAll("[爆炸Tank] 第二次爆炸触发!");
    return Plugin_Stop;
}

// 创建爆炸效果
void CreateExplosionEffect(float pos[3], float scale)
{
    PrintToServer("[爆炸TankDEBUG] 开始创建爆炸效果");

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
