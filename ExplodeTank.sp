/**
 * 爆炸Tank模块
 * 红色皮肤 + 石头双重爆炸
 * 多层监听系统 + 状态标记
 */

// 定义最大实体数量
#define MAX_ROCKS 128

// 爆炸Tank独立的实体引用
static int g_iThisExplodeTankEntRef = INVALID_ENT_REFERENCE;

// 石头状态管理
static int g_iExplodeRockEntRef[MAX_ROCKS];
static bool g_bRockDestroyedByPlayer[MAX_ROCKS];
static float g_vecRockPos[MAX_ROCKS][3];
static int g_iRockCount = 0;

// 爆炸Tank应用函数
void ExplodeTank_Apply(int tank)
{
    if (!IsClientInGame(tank))
        return;

    // 检查是否是Tank
    int zClass = GetEntProp(tank, Prop_Send, "m_zombieClass");
    if (zClass != 8)
        return;

    // 防止重复应用
    int currentExplodeTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);
    if (currentExplodeTank == tank)
    {
        PrintToServer("[爆炸TankDEBUG] 已经是爆炸Tank，跳过重复应用");
        return;
    }

    // 先清理旧效果（如果有）
    ExplodeTank_ClearEffects(tank);

    // 标记为爆炸Tank
    g_iThisExplodeTankEntRef = EntIndexToEntRef(tank);

    // 设置红色皮肤
    SetEntityRenderMode(tank, RENDER_NORMAL);
    SetEntityRenderColor(tank, 255, 0, 0, 255);

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

// ==================== 多层监听系统 ====================

// 第一层：检测石头创建（在主文件的OnEntityCreated中调用）
void ExplodeTank_OnEntityCreated(int entity, const char[] classname)
{
    // 检查是否是爆炸Tank存在
    int currentTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);
    if (currentTank <= 0 || !IsValidEntity(currentTank))
        return;

    PrintToServer("[爆炸TankDEBUG] OnEntityCreated: entity=%d, classname=%s", entity, classname);

    // 检查是否是石头
    if (!StrEqual(classname, "tank_rock", false) && !StrEqual(classname, "prop_physics", false))
        return;

    PrintToServer("[爆炸TankDEBUG] 检测到石头类实体，准备验证");

    // 延迟检查，确保实体完全创建
    CreateTimer(0.1, Timer_ValidateRock, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ValidateRock(Handle timer, int rockRef)
{
    int rock = EntRefToEntIndex(rockRef);
    if (rock <= 0 || !IsValidEntity(rock))
    {
        PrintToServer("[爆炸TankDEBUG] 石头验证失败：实体无效");
        return Plugin_Stop;
    }

    // 检查是否是石头模型
    char modelName[128];
    GetEntPropString(rock, Prop_Data, "m_ModelName", modelName, sizeof(modelName));

    PrintToServer("[爆炸TankDEBUG] 石头模型名称: %s", modelName);

    if (StrContains(modelName, "rock", false) == -1)
    {
        PrintToServer("[爆炸TankDEBUG] 模型名称不包含'rock'，跳过");
        return Plugin_Stop;
    }

    // 检查是否已经追踪
    for (int i = 0; i < g_iRockCount; i++)
    {
        if (EntRefToEntIndex(g_iExplodeRockEntRef[i]) == rock)
        {
            PrintToServer("[爆炸TankDEBUG] 石头已在追踪列表中");
            return Plugin_Stop;
        }
    }

    // 添加到追踪列表
    if (g_iRockCount < MAX_ROCKS)
    {
        g_iExplodeRockEntRef[g_iRockCount] = EntIndexToEntRef(rock);
        g_bRockDestroyedByPlayer[g_iRockCount] = false;
        g_vecRockPos[g_iRockCount][0] = 0.0;
        g_vecRockPos[g_iRockCount][1] = 0.0;
        g_vecRockPos[g_iRockCount][2] = 0.0;

        // Hook石头事件
        bool hook1 = SDKHook(rock, SDKHook_TraceAttack, Hook_RockTraceAttack);
        bool hook2 = SDKHook(rock, SDKHook_StartTouch, Hook_RockStartTouch);
        bool hook3 = SDKHook(rock, SDKHook_Think, Hook_RockThink);

        g_iRockCount++;

        PrintToServer("[爆炸TankDEBUG] 石头已添加到追踪列表: entity=%d, total=%d, hooks=%d/%d/%d", rock, g_iRockCount, hook1, hook2, hook3);
    }
    else
    {
        PrintToServer("[爆炸TankDEBUG] 追踪列表已满，无法添加更多石头");
    }

    return Plugin_Stop;
}

// 第二层：检测玩家攻击石头
public Action Hook_RockTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    // 检查是否是我们追踪的石头
    int rockIndex = -1;
    for (int i = 0; i < g_iRockCount; i++)
    {
        if (EntRefToEntIndex(g_iExplodeRockEntRef[i]) == victim)
        {
            rockIndex = i;
            break;
        }
    }

    if (rockIndex == -1)
        return Plugin_Continue;

    // 检查攻击者是否是玩家
    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
        return Plugin_Continue;

    // 标记为玩家摧毁
    g_bRockDestroyedByPlayer[rockIndex] = true;

    // 更新位置
    GetEntPropVector(victim, Prop_Send, "m_vecOrigin", g_vecRockPos[rockIndex]);

    PrintToServer("[爆炸TankDEBUG] 玩家攻击石头: victim=%d, attacker=%d", victim, attacker);

    return Plugin_Continue;
}

// 第三层：检测石头撞墙
public Action Hook_RockStartTouch(int entity, int other)
{
    // 检查是否是我们追踪的石头
    int rockIndex = -1;
    for (int i = 0; i < g_iRockCount; i++)
    {
        if (EntRefToEntIndex(g_iExplodeRockEntRef[i]) == entity)
        {
            rockIndex = i;
            break;
        }
    }

    if (rockIndex == -1)
        return Plugin_Continue;

    // 检查是否撞墙（不是玩家）
    if (other > 0 && other <= MaxClients && IsClientInGame(other))
        return Plugin_Continue;

    // 更新位置
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", g_vecRockPos[rockIndex]);

    // 检查石头速度，如果速度很小说明已经停止或即将破碎
    float velocity[3];
    GetEntPropVector(entity, Prop_Data, "m_vecVelocity", velocity);
    float speed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1] + velocity[2] * velocity[2]);

    if (speed < 50.0)
    {
        PrintToServer("[爆炸TankDEBUG] 石头撞墙且速度低，触发爆炸: entity=%d, speed=%.1f", entity, speed);
        TriggerRockExplosion(rockIndex);
    }

    return Plugin_Continue;
}

// 第四层：Think Hook 持续检测 + 更新位置
public Action Hook_RockThink(int entity)
{
    // 检查是否是我们追踪的石头
    int rockIndex = -1;
    for (int i = 0; i < g_iRockCount; i++)
    {
        if (EntRefToEntIndex(g_iExplodeRockEntRef[i]) == entity)
        {
            rockIndex = i;
            break;
        }
    }

    if (rockIndex == -1)
        return Plugin_Continue;

    // 持续更新位置
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", g_vecRockPos[rockIndex]);

    return Plugin_Continue;
}

// 第五层：实体销毁检测（在主文件OnEntityDestroyed中调用）
void ExplodeTank_OnEntityDestroyed(int entity)
{
    // 检查是否是爆炸Tank存在
    int currentTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);
    if (currentTank <= 0 || !IsValidEntity(currentTank))
        return;

    PrintToServer("[爆炸TankDEBUG] OnEntityDestroyed: entity=%d", entity);

    // 检查是否是我们追踪的石头
    int rockIndex = -1;
    for (int i = 0; i < g_iRockCount; i++)
    {
        int rock = EntRefToEntIndex(g_iExplodeRockEntRef[i]);
        PrintToServer("[爆炸TankDEBUG] 检查石头 %d: ref=%d, rock=%d, 匹配=%d", i, g_iExplodeRockEntRef[i], rock, (rock == entity));
        if (rock == entity)
        {
            rockIndex = i;
            break;
        }
    }

    if (rockIndex == -1)
    {
        PrintToServer("[爆炸TankDEBUG] 实体销毁但不在追踪列表中");
        return;
    }

    PrintToServer("[爆炸TankDEBUG] 石头销毁，触发爆炸: entity=%d, index=%d", entity, rockIndex);

    // 触发爆炸（使用缓存的位置）
    TriggerRockExplosion(rockIndex);

    // 从追踪列表中移除
    ExplodeTank_RemoveRockFromTracking(rockIndex);
}

// ==================== 爆炸触发 ====================

void TriggerRockExplosion(int rockIndex)
{
    if (rockIndex < 0 || rockIndex >= g_iRockCount)
        return;

    // 检查位置是否有效
    if (g_vecRockPos[rockIndex][0] == 0.0 && g_vecRockPos[rockIndex][1] == 0.0 && g_vecRockPos[rockIndex][2] == 0.0)
    {
        PrintToServer("[爆炸TankDEBUG] 石头位置无效，跳过爆炸");
        return;
    }

    // 爆炸概率检查
    ConVar explosionRandom = FindConVar("shan_ExplodeTank_explosion_random");
    int explosionChance = (explosionRandom != null) ? explosionRandom.IntValue : 100;

    if (GetRandomInt(1, 100) > explosionChance)
    {
        PrintToChatAll("[爆炸Tank] 爆炸概率未通过");
        return;
    }

    bool destroyedByPlayer = g_bRockDestroyedByPlayer[rockIndex];
    char reason[64];
    Format(reason, sizeof(reason), destroyedByPlayer ? "玩家击碎" : "撞击破碎");

    PrintToChatAll("[爆炸Tank] 石头爆炸! 原因: %s", reason);

    // 创建第一次爆炸
    ExplodeTank_CreateExplosion(g_vecRockPos[rockIndex], 1.3);

    // 延迟创建第二次爆炸
    DataPack pack = new DataPack();
    pack.WriteFloat(g_vecRockPos[rockIndex][0]);
    pack.WriteFloat(g_vecRockPos[rockIndex][1]);
    pack.WriteFloat(g_vecRockPos[rockIndex][2]);
    CreateTimer(0.2, Timer_ExplodeTankSecondExplosion, pack, TIMER_FLAG_NO_MAPCHANGE);

    // 从追踪列表中移除
    ExplodeTank_RemoveRockFromTracking(rockIndex);
}

public Action Timer_ExplodeTankSecondExplosion(Handle timer, DataPack pack)
{
    pack.Reset();
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    delete pack;

    ExplodeTank_CreateExplosion(pos, 1.6);
    PrintToChatAll("[爆炸Tank] 石头第二次爆炸!");
    return Plugin_Stop;
}

// ==================== 爆炸效果 ====================

void ExplodeTank_CreateExplosion(float pos[3], float scale)
{
    PrintToServer("[爆炸TankDEBUG] 创建爆炸: scale=%.1f, pos=(%.1f,%.1f,%.1f)", scale, pos[0], pos[1], pos[2]);

    // 1. 创建env_explosion实体
    int explosion = CreateEntityByName("env_explosion");
    if (explosion != -1)
    {
        TeleportEntity(explosion, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchKeyValue(explosion, "iMagnitude", "150");
        DispatchKeyValue(explosion, "iRadiusOverride", "400");
        DispatchKeyValue(explosion, "fireballsprite", "sprites/zerogxplode.spr");
        SetEntProp(explosion, Prop_Data, "m_spawnflags", 8);
        DispatchSpawn(explosion);
        ActivateEntity(explosion);
        AcceptEntityInput(explosion, "Explode");
        AcceptEntityInput(explosion, "Kill");
        PrintToServer("[爆炸TankDEBUG] env_explosion创建成功");
    }

    // 2. 创建爆炸粒子效果
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
    float explosionRadius = 400.0 * scale;

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

// ==================== 辅助函数 ====================

void ExplodeTank_RemoveRockFromTracking(int rockIndex)
{
    if (rockIndex < 0 || rockIndex >= g_iRockCount)
        return;

    // 移除Hook
    int rock = EntRefToEntIndex(g_iExplodeRockEntRef[rockIndex]);
    if (rock > 0 && IsValidEntity(rock))
    {
        SDKHook(rock, SDKHook_TraceAttack, Hook_RockTraceAttack);
        SDKHook(rock, SDKHook_StartTouch, Hook_RockStartTouch);
        SDKHook(rock, SDKHook_Think, Hook_RockThink);
    }

    // 从列表中移除（通过移动后续元素）
    for (int i = rockIndex; i < g_iRockCount - 1; i++)
    {
        g_iExplodeRockEntRef[i] = g_iExplodeRockEntRef[i + 1];
        g_bRockDestroyedByPlayer[i] = g_bRockDestroyedByPlayer[i + 1];
        g_vecRockPos[i][0] = g_vecRockPos[i + 1][0];
        g_vecRockPos[i][1] = g_vecRockPos[i + 1][1];
        g_vecRockPos[i][2] = g_vecRockPos[i + 1][2];
    }

    g_iRockCount--;
}

void ExplodeTank_ClearEffects(int tank)
{
    // 不重置颜色，让Tank尸体保留皮肤颜色
}

void ExplodeTank_OnDeath(int tank)
{
    int currentExplodeTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);
    if (currentExplodeTank == tank)
    {
        // 清理所有石头追踪
        for (int i = g_iRockCount - 1; i >= 0; i--)
        {
            ExplodeTank_RemoveRockFromTracking(i);
        }

        g_iThisExplodeTankEntRef = INVALID_ENT_REFERENCE;
        PrintToServer("[爆炸TankDEBUG] 爆炸Tank死亡，清理引用");
    }
}
