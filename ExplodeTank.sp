/**
 * 爆炸Tank模块
 * 红色皮肤 + 石头双重爆炸
 * 基于Mutant Tanks的实现方式
 */

#define MAX_ROCKS 128

// 爆炸Tank实体引用
static int g_iThisExplodeTankEntRef = INVALID_ENT_REFERENCE;

// 石头实体数组（用于跟踪爆炸Tank的石头）
static int g_iExplodeTankRocks[MAX_ROCKS];
static int g_iRockCount = 0;

// ==================== 辅助函数（供SuperTank.sp调用）====================

// 检查是否是爆炸Tank投掷的石头
bool ExplodeTank_IsTankRock(int inflictor)
{
    if (inflictor <= 0 || !IsValidEntity(inflictor))
    {
        PrintToServer("[爆炸TankDEBUG] 石头检测: inflictor无效");
        return false;
    }

    char classname[64];
    GetEntityClassname(inflictor, classname, sizeof(classname));

    PrintToServer("[爆炸TankDEBUG] 石头检测: classname=%s", classname);

    if (!StrEqual(classname, "tank_rock", false))
        return false;

    // 检查是否是爆炸Tank投掷的
    int currentTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);
    PrintToServer("[爆炸TankDEBUG] 当前爆炸Tank=%d, 检查有效性", currentTank);

    if (currentTank <= 0 || !IsClientInGame(currentTank))
    {
        PrintToServer("[爆炸TankDEBUG] 没有爆炸Tank存在");
        return false;
    }

    int thrower = GetEntPropEnt(inflictor, Prop_Data, "m_hThrower");
    PrintToServer("[爆炸TankDEBUG] 石头投掷者=%d, 爆炸Tank=%d, 匹配=%d", thrower, currentTank, (thrower == currentTank));

    return (thrower == currentTank);
}

// 获取当前爆炸Tank
public int ExplodeTank_GetCurrentTank()
{
    return EntRefToEntIndex(g_iThisExplodeTankEntRef);
}

// 检查指定索引的石头是否匹配指定的引用
public bool ExplodeTank_IsTrackedRock(int index, int rockRef)
{
    if (index < 0 || index >= g_iRockCount)
        return false;
    return (g_iExplodeTankRocks[index] == rockRef);
}

// 清理石头跟踪列表
void ExplodeTank_ClearRockList()
{
    PrintToServer("[爆炸TankDEBUG] 清理石头跟踪列表，当前数量: %d", g_iRockCount);

    for (int i = 0; i < g_iRockCount; i++)
    {
        if (g_iExplodeTankRocks[i] != INVALID_ENT_REFERENCE)
        {
            int rock = EntRefToEntIndex(g_iExplodeTankRocks[i]);
            if (rock > 0 && IsValidEntity(rock))
            {
                PrintToServer("[爆炸TankDEBUG] 移除石头Hook: rock=%d", rock);
                SDKUnhook(rock, SDKHook_OnTakeDamage, Hook_RockTakeDamage);
            }
        }
    }
    g_iRockCount = 0;
    PrintToServer("[爆炸TankDEBUG] 石头跟踪列表已清理");
}

// 为石头添加榴弹炮轨迹特效
void ExplodeTank_AddRockTrail(int rock, int rockIndex)
{
    // 点燃石头产生火焰烟雾轨迹（和mutant_tanks的meteor一样）
    AcceptEntityInput(rock, "Ignite");
    PrintToServer("[爆炸TankDEBUG] 已点燃石头添加轨迹特效: rock=%d", rock);
}

// 清理指定的石头跟踪（供SuperTank.sp调用）
public void ExplodeTank_RemoveRockTracking(int rockRef)
{
    for (int i = 0; i < g_iRockCount; i++)
    {
        if (g_iExplodeTankRocks[i] == rockRef)
        {
            g_iExplodeTankRocks[i] = INVALID_ENT_REFERENCE;

            int rock = EntRefToEntIndex(rockRef);
            if (rock > 0 && IsValidEntity(rock))
            {
                SDKUnhook(rock, SDKHook_OnTakeDamage, Hook_RockTakeDamage);
            }
            break;
        }
    }
}

// 监听实体创建（用于跟踪爆炸Tank投掷的石头）
public void ExplodeTank_OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "tank_rock", false))
    {
        PrintToServer("[爆炸TankDEBUG] 检测到tank_rock创建: entity=%d", entity);

        // 检查是否有爆炸Tank存在
        int currentTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);
        if (currentTank <= 0 || !IsClientInGame(currentTank))
        {
            PrintToServer("[爆炸TankDEBUG] 没有爆炸Tank存在，跳过石头跟踪");
            return;
        }

        PrintToServer("[爆炸TankDEBUG] 爆炸Tank存在，跟踪此石头");

        // 添加到石头跟踪列表（不检查投掷者，因为此时thrower可能还没设置）
        if (g_iRockCount < MAX_ROCKS)
        {
            g_iExplodeTankRocks[g_iRockCount] = EntIndexToEntRef(entity);

            // 添加榴弹炮轨迹特效
            ExplodeTank_AddRockTrail(entity, g_iRockCount);

            g_iRockCount++;
            PrintToServer("[爆炸TankDEBUG] 石头已添加到跟踪列表: entity=%d, 总数=%d", entity, g_iRockCount);

            // Hook石头被破坏事件
            SDKHook(entity, SDKHook_OnTakeDamage, Hook_RockTakeDamage);
            PrintToServer("[爆炸TankDEBUG] 石头Hook已设置");
        }
        else
        {
            PrintToServer("[爆炸TankDEBUG] 石头跟踪列表已满！");
        }
    }
}

// 石头受到伤害时（检查是否被摧毁）
public Action Hook_RockTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (damage <= 0.0)
        return Plugin_Continue;

    char classname[64];
    GetEntityClassname(victim, classname, sizeof(classname));
    if (!StrEqual(classname, "tank_rock", false))
        return Plugin_Continue;

    // 检查是否在跟踪列表中
    int rockRef = EntIndexToEntRef(victim);
    bool isTrackedRock = false;
    for (int i = 0; i < g_iRockCount; i++)
    {
        if (g_iExplodeTankRocks[i] == rockRef)
        {
            isTrackedRock = true;
            break;
        }
    }

    if (!isTrackedRock)
        return Plugin_Continue;

    PrintToServer("[爆炸TankDEBUG] 跟踪的石头受到伤害: victim=%d, damage=%.1f", victim, damage);

    // 现在检查投掷者是否是爆炸Tank
    int thrower = GetEntPropEnt(victim, Prop_Data, "m_hThrower");
    int currentTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);
    PrintToServer("[爆炸TankDEBUG] 石头投掷者检查: thrower=%d, 爆炸Tank=%d", thrower, currentTank);

    if (thrower != currentTank)
    {
        PrintToServer("[爆炸TankDEBUG] 不是爆炸Tank的石头，从跟踪列表移除");

        // 从跟踪列表中移除（这不是爆炸Tank的石头）
        for (int i = 0; i < g_iRockCount; i++)
        {
            if (g_iExplodeTankRocks[i] == rockRef)
            {
                g_iExplodeTankRocks[i] = INVALID_ENT_REFERENCE;
                SDKUnhook(victim, SDKHook_OnTakeDamage, Hook_RockTakeDamage);
                break;
            }
        }
        return Plugin_Continue;
    }

    PrintToServer("[爆炸TankDEBUG] 确认是爆炸Tank的石头!");

    // 获取石头当前血量
    int rockHealth = GetEntProp(victim, Prop_Data, "m_iHealth");
    PrintToServer("[爆炸TankDEBUG] 石头当前血量: %d, 受到伤害: %.1f", rockHealth, damage);

    // 如果这次伤害会摧毁石头
    if (rockHealth > 0 && damage >= rockHealth)
    {
        PrintToServer("[爆炸TankDEBUG] 石头即将被摧毁，触发爆炸!");

        // 获取石头位置
        float rockPos[3];
        GetEntPropVector(victim, Prop_Data, "m_vecOrigin", rockPos);

        // 从跟踪列表中移除
        for (int i = 0; i < g_iRockCount; i++)
        {
            if (g_iExplodeTankRocks[i] == rockRef)
            {
                g_iExplodeTankRocks[i] = INVALID_ENT_REFERENCE;
                break;
            }
        }

        // 触发爆炸
        TriggerRockExplosion(rockPos);
    }

    return Plugin_Continue;
}

// 爆炸Tank应用函数
void ExplodeTank_Apply(int tank)
{
    if (!IsClientInGame(tank))
        return;

    // 检查是否是Tank
    int zClass = GetEntProp(tank, Prop_Send, "m_zombieClass");
    if (zClass != 8)
        return;

    // 先清理所有类型的旧效果（重要：防止不同Tank类型之间的干扰）
    ExplodeTank_ClearAllEffects(tank);
    VajraTank_ClearAllEffects(tank);

    PrintToServer("[爆炸TankDEBUG] 应用爆炸Tank: tank=%d, userid=%d, entref=%d", tank, GetClientUserId(tank), EntIndexToEntRef(tank));

    // 清理旧的石头跟踪列表
    PrintToServer("[爆炸TankDEBUG] 清理旧的石头跟踪列表");
    ExplodeTank_ClearRockList();

    // 标记为爆炸Tank
    g_iThisExplodeTankEntRef = EntIndexToEntRef(tank);
    PrintToServer("[爆炸TankDEBUG] 爆炸Tank引用已设置: g_iThisExplodeTankEntRef=%d", g_iThisExplodeTankEntRef);

    // 设置红色皮肤
    SetEntityRenderMode(tank, RENDER_NORMAL);
    SetEntityRenderColor(tank, 255, 0, 0, 255);

    PrintToServer("[爆炸TankDEBUG] 已设置红色皮肤");

    // 计算血量 (使用全局配置)
    int playerCount = GetOnlineSurvivorCount();
    int baseHP = GetDifficultyTankHP();
    ConVar tankHP = FindConVar("shan_tank_hp");
    int hpPerPlayer = (tankHP != null) ? tankHP.IntValue : 4000;
    int finalHP = baseHP + (hpPerPlayer * playerCount);

    SetEntProp(tank, Prop_Send, "m_iHealth", finalHP);
    SetEntProp(tank, Prop_Send, "m_iMaxHealth", finalHP);

    PrintToServer("[爆炸TankDEBUG] 设置血量: %d (玩家数=%d, 每人血量=%d)", finalHP, playerCount, hpPerPlayer);

    PrintToChatAll("\x03[寄寄之家 - SuperTank] \x01强力感染者 \x04爆炸Tank \x01已出现!");
}

// ==================== 石头爆炸触发 ====================

// 触发石头爆炸（在SuperTank.sp中调用）
public void TriggerRockExplosion(float pos[3])
{
    PrintToServer("[爆炸TankDEBUG] ========== 触发石头爆炸 ==========");
    PrintToServer("[爆炸TankDEBUG] pos=(%.1f,%.1f,%.1f)", pos[0], pos[1], pos[2]);

    // 爆炸概率检查
    ConVar explosionRandom = FindConVar("shan_ExplodeTank_explosion_random");
    int explosionChance = (explosionRandom != null) ? explosionRandom.IntValue : 100;

    int randomRoll = GetRandomInt(1, 100);
    PrintToServer("[爆炸TankDEBUG] 爆炸概率检查: 随机数=%d, 需求=%d", randomRoll, explosionChance);

    if (randomRoll > explosionChance)
    {
        PrintToChatAll("[爆炸Tank] 爆炸概率未通过");
        return;
    }

    PrintToChatAll("[爆炸Tank] 石头爆炸!");

    // 创建煤气罐式强力爆炸
    ExplodeTank_CreateExplosion(pos);
}

// ==================== 爆炸效果 ====================

// 创建可破坏的道具（爆炸物）
void ExplodeTank_SpawnBreakProp(float pos[3], char[] model)
{
    int prop = CreateEntityByName("prop_physics_override");
    if (prop != -1)
    {
        SetEntityModel(prop, model);

        // 设置道具的生命值为1（这样任何伤害都会摧毁它）
        SetEntProp(prop, Prop_Data, "m_iHealth", 1);
        SetEntProp(prop, Prop_Data, "m_iMaxHealth", 1);

        // 设置随机旋转角度，让爆炸效果更自然
        float angles[3];
        angles[0] = GetRandomFloat(0.0, 360.0);
        angles[1] = GetRandomFloat(0.0, 360.0);
        angles[2] = GetRandomFloat(0.0, 360.0);

        TeleportEntity(prop, pos, angles, NULL_VECTOR);
        DispatchSpawn(prop);
        ActivateEntity(prop);

        // 立即引爆道具
        AcceptEntityInput(prop, "Break");

        PrintToServer("[爆炸TankDEBUG] 创建并引爆道具: %s", model);
    }
}

void ExplodeTank_CreateExplosion(float pos[3])
{
    PrintToServer("[爆炸TankDEBUG] 创建爆炸: pos=(%.1f,%.1f,%.1f)", pos[0], pos[1], pos[2]);

    // 获取配置的伤害值
    ConVar explosionDamage = FindConVar("shan_ExplodeTank_explosion_damage");
    int damage = (explosionDamage != null) ? explosionDamage.IntValue : 50;

    float damageRadius = 250.0;      // 伤害范围
    float visualRadius = 500.0;      // 视觉特效范围

    // 第一次爆炸：创建大量爆炸道具（中心爆炸）
    for (int i = 0; i < 8; i++)
    {
        float offset[3];
        offset[0] = GetRandomFloat(-150.0, 150.0);
        offset[1] = GetRandomFloat(-150.0, 150.0);
        offset[2] = GetRandomFloat(0.0, 80.0);

        float adjustedPos[3];
        AddVectors(pos, offset, adjustedPos);

        ExplodeTank_SpawnBreakProp(adjustedPos, "models/props_junk/gascan001a.mdl");
        ExplodeTank_SpawnBreakProp(adjustedPos, "models/props_junk/propanecanister001a.mdl");
    }

    PrintToServer("[爆炸TankDEBUG] 已创建第一次爆炸");

    // 第二次爆炸：延迟0.1-0.3秒后在周围爆炸
    CreateTimer(0.15, Timer_SecondaryExplosion, .flags = TIMER_FLAG_NO_MAPCHANGE);

    // 第三次爆炸：延迟0.3-0.5秒在更外围爆炸
    CreateTimer(0.4, Timer_TertiaryExplosion, .flags = TIMER_FLAG_NO_MAPCHANGE);

    // 播放第一层爆炸音效（低频冲击）
    char soundPath1[] = "weapons/hegrenade/explode5.wav";
    PrecacheSound(soundPath1, true);
    EmitAmbientSound(soundPath1, pos, SOUND_FROM_WORLD, SNDLEVEL_GUNFIRE);

    // 播放第二层爆炸音效（火焰爆炸）
    char soundPath2[] = "ambient/explosions/explode_2.wav";
    PrecacheSound(soundPath2, true);
    EmitAmbientSound(soundPath2, pos, SOUND_FROM_WORLD, SNDLEVEL_GUNFIRE);

    // 屏幕震动（使用视觉特效范围）
    ShakeScreen(pos, visualRadius);

    // 击退幸存者并造成伤害（使用伤害范围）
    int hitCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            float playerPos[3];
            GetClientAbsOrigin(i, playerPos);

            float distance = GetVectorDistance(pos, playerPos, false);
            if (distance < damageRadius)
            {
                // 计算击退方向和力度
                float pushDir[3];
                MakeVectorFromPoints(pos, playerPos, pushDir);
                NormalizeVector(pushDir, pushDir);

                float pushForce = 500.0 * (1.0 - (distance / damageRadius));
                ScaleVector(pushDir, pushForce);

                // 应用击退
                PushPlayer(i, pushDir);

                // 造成伤害
                float actualDamage = damage * (1.0 - (distance / damageRadius));
                SDKHooks_TakeDamage(i, 0, 0, actualDamage, DMG_BLAST);
                hitCount++;
            }
        }
    }

    PrintToChatAll("[爆炸Tank] 石头爆炸! 伤害=%d, 命中=%d人", damage, hitCount);
}

// 第二次爆炸（在第一次爆炸周围）
public Action Timer_SecondaryExplosion(Handle timer)
{
    // 获取最近的石头爆炸位置
    for (int i = 0; i < g_iRockCount; i++)
    {
        if (g_iExplodeTankRocks[i] != INVALID_ENT_REFERENCE)
        {
            int rock = EntRefToEntIndex(g_iExplodeTankRocks[i]);
            if (rock > 0 && IsValidEntity(rock))
            {
                float rockPos[3];
                GetEntPropVector(rock, Prop_Data, "m_vecOrigin", rockPos);

                // 在石头位置周围创建二次爆炸
                for (int j = 0; j < 6; j++)
                {
                    float offset[3];
                    offset[0] = GetRandomFloat(-200.0, 200.0);
                    offset[1] = GetRandomFloat(-200.0, 200.0);
                    offset[2] = GetRandomFloat(0.0, 100.0);

                    float adjustedPos[3];
                    AddVectors(rockPos, offset, adjustedPos);

                    ExplodeTank_SpawnBreakProp(adjustedPos, "models/props_junk/gascan001a.mdl");
                    ExplodeTank_SpawnBreakProp(adjustedPos, "models/props_junk/propanecanister001a.mdl");
                }

                // 播放二次爆炸音效（组合）
                char soundPath[] = "weapons/hegrenade/explode5.wav";
                PrecacheSound(soundPath, true);
                EmitAmbientSound(soundPath, rockPos, SOUND_FROM_WORLD, SNDLEVEL_GUNFIRE);

                char soundPath2[] = "ambient/explosions/explode_2.wav";
                PrecacheSound(soundPath2, true);
                EmitAmbientSound(soundPath2, rockPos, SOUND_FROM_WORLD, SNDLEVEL_GUNFIRE);

                PrintToServer("[爆炸TankDEBUG] 已创建第二次爆炸");
                break;
            }
        }
    }
    return Plugin_Stop;
}

// 第三次爆炸（更外围）
public Action Timer_TertiaryExplosion(Handle timer)
{
    for (int i = 0; i < g_iRockCount; i++)
    {
        if (g_iExplodeTankRocks[i] != INVALID_ENT_REFERENCE)
        {
            int rock = EntRefToEntIndex(g_iExplodeTankRocks[i]);
            if (rock > 0 && IsValidEntity(rock))
            {
                float rockPos[3];
                GetEntPropVector(rock, Prop_Data, "m_vecOrigin", rockPos);

                // 在更外围创建三次爆炸
                for (int j = 0; j < 4; j++)
                {
                    float offset[3];
                    offset[0] = GetRandomFloat(-300.0, 300.0);
                    offset[1] = GetRandomFloat(-300.0, 300.0);
                    offset[2] = GetRandomFloat(0.0, 120.0);

                    float adjustedPos[3];
                    AddVectors(rockPos, offset, adjustedPos);

                    ExplodeTank_SpawnBreakProp(adjustedPos, "models/props_junk/gascan001a.mdl");
                    ExplodeTank_SpawnBreakProp(adjustedPos, "models/props_junk/propanecanister001a.mdl");
                }

                // 播放三次爆炸音效（组合）
                char soundPath[] = "weapons/hegrenade/explode5.wav";
                PrecacheSound(soundPath, true);
                EmitAmbientSound(soundPath, rockPos, SOUND_FROM_WORLD, SNDLEVEL_GUNFIRE);

                char soundPath2[] = "ambient/explosions/explode_2.wav";
                PrecacheSound(soundPath2, true);
                EmitAmbientSound(soundPath2, rockPos, SOUND_FROM_WORLD, SNDLEVEL_GUNFIRE);

                PrintToServer("[爆炸TankDEBUG] 已创建第三次爆炸");
                break;
            }
        }
    }
    return Plugin_Stop;
}

// 屏幕震动
void ShakeScreen(float pos[3], float radius)
{
    int shake = CreateEntityByName("env_shake");
    if (shake != -1)
    {
        SetEntPropFloat(shake, Prop_Data, "m_amplitude", 25.0);      // 震动幅度（增大）
        SetEntPropFloat(shake, Prop_Data, "m_frequency", 150.0);     // 震动频率
        SetEntPropFloat(shake, Prop_Data, "m_duration", 1.5);        // 震动持续时间（增大）
        SetEntProp(shake, Prop_Data, "m_radius", radius);            // 震动半径

        TeleportEntity(shake, pos, NULL_VECTOR, NULL_VECTOR);

        DispatchSpawn(shake);
        ActivateEntity(shake);

        AcceptEntityInput(shake, "StartShake");
        AcceptEntityInput(shake, "Kill");

        PrintToServer("[爆炸TankDEBUG] 已创建屏幕震动: radius=%.1f", radius);
    }
}

// 击退玩家
void PushPlayer(int client, float pushDir[3])
{
    float currentVel[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", currentVel);

    // 添加击退速度到当前速度
    AddVectors(currentVel, pushDir, currentVel);

    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, currentVel);
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

// ==================== 清理函数 ====================

// 清理所有爆炸Tank效果
public void ExplodeTank_ClearAllEffects(int tank)
{
    // 清除引用
    int currentExplodeTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);
    if (currentExplodeTank == tank)
    {
        g_iThisExplodeTankEntRef = INVALID_ENT_REFERENCE;
    }
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
        g_iThisExplodeTankEntRef = INVALID_ENT_REFERENCE;
        ExplodeTank_ClearRockList();
        PrintToServer("[爆炸TankDEBUG] 爆炸Tank死亡，清理引用和石头列表");
    }
}