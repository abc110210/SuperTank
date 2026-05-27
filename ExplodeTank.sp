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

    // Hook所有可能的相关实体事件
    HookEntityOutput("tank_rock", "OnBreak", Hook_TankRockBreak);
    HookEntityOutput("tank_rock", "OnKilled", Hook_TankRockBreak);
    HookEntityOutput("prop_physics", "OnBreak", Hook_TankRockBreak);
    HookEntityOutput("prop_physics", "OnHealthChanged", Hook_TankRockHealthChange);

    PrintToServer("[爆炸TankDEBUG] 已Hook所有石头相关事件");

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
    // 不重置颜色，让Tank尸体保留皮肤颜色
}

// 监听石头血量变化（提前检测石头即将被破坏）
void Hook_TankRockHealthChange(const char[] output, int caller, int activator, float delay)
{
    PrintToServer("[爆炸TankDEBUG] 石头血量变化: output=%s, caller=%d", output, caller);

    if (caller <= 0 || !IsValidEntity(caller))
        return;

    // 检查是否是石头
    char modelName[128];
    GetEntPropString(caller, Prop_Data, "m_ModelName", modelName, sizeof(modelName));

    if (StrContains(modelName, "rock", false) != -1)
    {
        PrintToServer("[爆炸TankDEBUG] 检测到石头血量变化，准备爆炸");

        // 获取位置
        float pos[3];
        GetEntPropVector(caller, Prop_Send, "m_vecOrigin", pos);

        // 直接触发爆炸（不等石头完全破碎）
        TriggerRockExplosion(pos, modelName);
    }
}

// 监听石头破碎事件
void Hook_TankRockBreak(const char[] output, int caller, int activator, float delay)
{
    PrintToServer("[爆炸TankDEBUG] 石头破碎事件: output=%s, caller=%d", output, caller);

    if (caller <= 0 || !IsValidEntity(caller))
        return;

    // 检查是否是石头
    char modelName[128];
    GetEntPropString(caller, Prop_Data, "m_ModelName", modelName, sizeof(modelName));

    if (StrContains(modelName, "rock", false) != -1)
    {
        // 获取位置
        float pos[3];
        GetEntPropVector(caller, Prop_Send, "m_vecOrigin", pos);

        PrintToChatAll("[爆炸Tank] 石头破碎! 触发爆炸");

        // 触发爆炸
        TriggerRockExplosion(pos, modelName);
    }
}

// 触发石头爆炸
void TriggerRockExplosion(float pos[3], const char[] modelName)
{
    PrintToServer("[爆炸TankDEBUG] 触发石头爆炸: pos=(%.1f,%.1f,%.1f), model=%s", pos[0], pos[1], pos[2], modelName);

    // 爆炸概率检查
    ConVar explosionRandom = FindConVar("shan_ExplodeTank_explosion_random");
    int explosionChance = (explosionRandom != null) ? explosionRandom.IntValue : 100;

    if (GetRandomInt(1, 100) > explosionChance)
    {
        PrintToChatAll("[爆炸Tank] 爆炸概率未通过");
        return;
    }

    PrintToChatAll("[爆炸Tank] 石头爆炸!");

    // 创建第一次爆炸
    ExplodeTank_CreateExplosion(pos, 1.3);

    // 存储位置用于第二次爆炸
    g_fExplodeExplosionPos[0] = pos[0];
    g_fExplodeExplosionPos[1] = pos[1];
    g_fExplodeExplosionPos[2] = pos[2];

    // 延迟创建第二次爆炸
    CreateTimer(0.2, Timer_ExplodeTankSecondExplosion, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ExplodeTankSecondExplosion(Handle timer)
{
    ExplodeTank_CreateExplosion(g_fExplodeExplosionPos, 1.6);
    PrintToChatAll("[爆炸Tank] 石头第二次爆炸!");
    return Plugin_Stop;
}

// 创建爆炸效果（独立函数）- 煤气罐爆炸风格
void ExplodeTank_CreateExplosion(float pos[3], float scale)
{
    PrintToServer("[爆炸TankDEBUG] 创建爆炸: scale=%.1f, pos=(%.1f,%.1f,%.1f)", scale, pos[0], pos[1], pos[2]);

    // 1. 创建env_explosion实体（煤气罐爆炸的核心效果）
    int explosion = CreateEntityByName("env_explosion");
    if (explosion != -1)
    {
        // 设置爆炸位置
        TeleportEntity(explosion, pos, NULL_VECTOR, NULL_VECTOR);

        // 设置爆炸属性
        DispatchKeyValue(explosion, "iMagnitude", "150");  // 爆炸威力
        DispatchKeyValue(explosion, "iRadiusOverride", "400");  // 爆炸半径
        DispatchKeyValue(explosion, "fireballsprite", "sprites/zerogxplode.spr");  // 火球精灵

        // 添加爆炸标志
        SetEntProp(explosion, Prop_Data, "m_spawnflags", 8);  // 8 = 产生烟雾和火焰

        DispatchSpawn(explosion);
        ActivateEntity(explosion);

        // 触发爆炸
        AcceptEntityInput(explosion, "Explode");

        // 延迟移除
        AcceptEntityInput(explosion, "Kill");

        PrintToServer("[爆炸TankDEBUG] env_explosion创建成功");
    }

    // 2. 创建爆炸粒子效果（gas_explosion - 煤气罐爆炸效果）
    int particle = CreateEntityByName("info_particle_system");
    if (particle != -1)
    {
        TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchKeyValue(particle, "effect_name", "gas_explosion");
        DispatchSpawn(particle);
        ActivateEntity(particle);

        AcceptEntityInput(particle, "Start");
        CreateTimer(0.8, Timer_ExplodeTankRemoveParticle, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);

        PrintToServer("[爆炸TankDEBUG] 粒子系统创建成功");
    }

    // 3. 创建火焰粒子效果
    int fireParticle = CreateEntityByName("info_particle_system");
    if (fireParticle != -1)
    {
        TeleportEntity(fireParticle, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchKeyValue(fireParticle, "effect_name", "fire_large_01");
        DispatchSpawn(fireParticle);
        ActivateEntity(fireParticle);

        AcceptEntityInput(fireParticle, "Start");
        CreateTimer(1.0, Timer_ExplodeTankRemoveParticle, EntIndexToEntRef(fireParticle), TIMER_FLAG_NO_MAPCHANGE);

        PrintToServer("[爆炸TankDEBUG] 火焰粒子创建成功");
    }

    // 4. 播放爆炸音效
    char soundPath[] = "weapons/hegrenade/explode3.wav";
    PrecacheSound(soundPath, true);
    EmitAmbientSound(soundPath, pos, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, 0.0);

    // 5. 造成爆炸伤害
    ConVar explosionDamage = FindConVar("shan_ExplodeTank_explosion_damage");
    int damage = (explosionDamage != null) ? explosionDamage.IntValue : 50;
    float explosionRadius = 400.0 * scale;  // 增大爆炸范围到400

    // 对范围内的玩家造成伤害
    int hitCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            float playerPos[3];
            GetClientAbsOrigin(i, playerPos);

            float distance = GetVectorDistance(pos, playerPos, false);
            if (distance < explosionRadius)
            {
                float actualDamage = damage * (1.0 - (distance / explosionRadius));
                SDKHooks_TakeDamage(i, 0, 0, actualDamage, DMG_BLAST);
                hitCount++;
            }
        }
    }

    PrintToChatAll("[爆炸Tank] 石头爆炸! 伤害=%d, 命中=%d人", damage, hitCount);
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
        PrintToServer("[爆炸TankDEBUG] 爆炸Tank死亡，清理引用");
    }
}
