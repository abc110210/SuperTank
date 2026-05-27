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

// 保存最后爆炸位置（用于二次爆炸）
static float g_fLastExplosionPos[3];
static bool g_bHasLastExplosionPos = false;

// ==================== 辅助函数（供SuperTank.sp调用）====================

// 检查是否是爆炸Tank投掷的石头
bool ExplodeTank_IsTankRock(int inflictor)
{
    if (inflictor <= 0 || !IsValidEntity(inflictor))
        return false;

    char classname[64];
    GetEntityClassname(inflictor, classname, sizeof(classname));

    if (!StrEqual(classname, "tank_rock", false))
        return false;

    // 检查是否是爆炸Tank投掷的
    int currentTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);
    if (currentTank <= 0 || !IsClientInGame(currentTank))
        return false;

    int thrower = GetEntPropEnt(inflictor, Prop_Data, "m_hThrower");
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
    for (int i = 0; i < MAX_ROCKS; i++)
    {
        if (g_iExplodeTankRocks[i] != INVALID_ENT_REFERENCE)
        {
            int rock = EntRefToEntIndex(g_iExplodeTankRocks[i]);
            if (rock > 0 && IsValidEntity(rock))
            {
                SDKUnhook(rock, SDKHook_OnTakeDamage, Hook_RockTakeDamage);
            }
        }
        g_iExplodeTankRocks[i] = INVALID_ENT_REFERENCE;
    }
    g_iRockCount = 0;
}

// 为石头添加榴弹炮轨迹特效
void ExplodeTank_AddRockTrail(int rock, int rockIndex)
{
    // 大幅增加石头血量，防止被点燃快速摧毁
    SetEntProp(rock, Prop_Data, "m_iHealth", 5000);
    SetEntProp(rock, Prop_Data, "m_iMaxHealth", 5000);

    // 点燃石头产生火焰烟雾轨迹（和mutant_tanks的meteor一样）
    AcceptEntityInput(rock, "Ignite");
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
        // 检查是否有爆炸Tank存在
        int currentTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);
        if (currentTank <= 0 || !IsClientInGame(currentTank))
            return;

        // 添加到石头跟踪列表
        if (g_iRockCount < MAX_ROCKS)
        {
            g_iExplodeTankRocks[g_iRockCount] = EntIndexToEntRef(entity);

            // 添加榴弹炮轨迹特效
            ExplodeTank_AddRockTrail(entity, g_iRockCount);

            g_iRockCount++;

            // Hook石头被破坏事件
            SDKHook(entity, SDKHook_OnTakeDamage, Hook_RockTakeDamage);
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

    // 检查投掷者是否是爆炸Tank
    int thrower = GetEntPropEnt(victim, Prop_Data, "m_hThrower");
    int currentTank = EntRefToEntIndex(g_iThisExplodeTankEntRef);

    if (thrower != currentTank)
    {
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

    // 获取石头当前血量
    int rockHealth = GetEntProp(victim, Prop_Data, "m_iHealth");

    // 如果这次伤害会摧毁石头（且伤害足够大，避免点燃小伤害累积）
    if (rockHealth > 0 && damage >= rockHealth && damage > 100.0)
    {
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

    // 先清理所有类型的旧效果
    ExplodeTank_ClearAllEffects(tank);
    VajraTank_ClearAllEffects(tank);

    // 清理旧的石头跟踪列表
    ExplodeTank_ClearRockList();

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

    PrintToChatAll("\x03[寄寄之家 - SuperTank] \x01强力感染者 \x04爆炸Tank \x01已出现!");
}

// ==================== 石头爆炸触发 ====================

// 触发石头爆炸（在SuperTank.sp中调用）
public void TriggerRockExplosion(float pos[3])
{
    // 爆炸概率检查
    ConVar explosionRandom = FindConVar("shan_ExplodeTank_explosion_random");
    int explosionChance = (explosionRandom != null) ? explosionRandom.IntValue : 100;

    int randomRoll = GetRandomInt(1, 100);

    if (randomRoll > explosionChance)
        return;

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
    }
}

void ExplodeTank_CreateExplosion(float pos[3])
{
    // 保存爆炸位置供二次爆炸使用
    g_fLastExplosionPos[0] = pos[0];
    g_fLastExplosionPos[1] = pos[1];
    g_fLastExplosionPos[2] = pos[2];
    g_bHasLastExplosionPos = true;

    // 获取配置的伤害值
    ConVar explosionDamage = FindConVar("shan_ExplodeTank_explosion_damage");
    int damage = (explosionDamage != null) ? explosionDamage.IntValue : 50;

    // 获取配置的爆炸范围
    ConVar explosionRange = FindConVar("shan_ExplodeTank_explosion_range");
    float damageRadius = (explosionRange != null) ? explosionRange.FloatValue : 300.0;

    // 第一次爆炸：中心闪光 + 四周红色火花 + 烟雾 + 火焰
    // 中心闪光（瞬间强光）
    ShowParticle(pos, "gas_explosion_initialburst");

    // 四周红色火花（主要视觉效果）
    for (int i = 0; i < 8; i++)
    {
        float offset[3];
        offset[0] = GetRandomFloat(-180.0, 180.0);
        offset[1] = GetRandomFloat(-180.0, 180.0);
        offset[2] = GetRandomFloat(-30.0, 80.0);

        float adjustedPos[3];
        AddVectors(pos, offset, adjustedPos);

        ShowParticle(adjustedPos, "gas_explosion_sparks_01");
    }

    // 烟雾效果（中等密度）
    for (int i = 0; i < 5; i++)
    {
        float offset[3];
        offset[0] = GetRandomFloat(-120.0, 120.0);
        offset[1] = GetRandomFloat(-120.0, 120.0);
        offset[2] = GetRandomFloat(0.0, 60.0);

        float adjustedPos[3];
        AddVectors(pos, offset, adjustedPos);

        ShowParticle(adjustedPos, "gas_explosion_smoke");
    }

    // 火焰效果（增加数量）
    for (int i = 0; i < 6; i++)
    {
        float offset[3];
        offset[0] = GetRandomFloat(-100.0, 100.0);
        offset[1] = GetRandomFloat(-100.0, 100.0);
        offset[2] = GetRandomFloat(0.0, 40.0);

        float adjustedPos[3];
        AddVectors(pos, offset, adjustedPos);

        ShowParticle(adjustedPos, "gas_explosion_fireball");
    }

    // 物理爆炸道具（火焰效果）
    for (int i = 0; i < 3; i++)
    {
        float offset[3];
        offset[0] = GetRandomFloat(-120.0, 120.0);
        offset[1] = GetRandomFloat(-120.0, 120.0);
        offset[2] = GetRandomFloat(0.0, 40.0);

        float adjustedPos[3];
        AddVectors(pos, offset, adjustedPos);

        ExplodeTank_SpawnBreakProp(adjustedPos, "models/props_junk/gascan001a.mdl");
    }

    // 播放第一层爆炸音效（低频冲击）
    char soundPath1[] = "weapons/hegrenade/explode5.wav";
    PrecacheSound(soundPath1, true);
    EmitAmbientSound(soundPath1, pos, SOUND_FROM_WORLD, SNDLEVEL_GUNFIRE);

    // 播放第二层爆炸音效（火焰爆炸）
    char soundPath2[] = "ambient/explosions/explode_2.wav";
    PrecacheSound(soundPath2, true);
    EmitAmbientSound(soundPath2, pos, SOUND_FROM_WORLD, SNDLEVEL_GUNFIRE);

    // 屏幕震动
    ShakeScreen(pos, damageRadius);

    // 击退幸存者并造成伤害
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
            }
        }
    }
}

// 显示粒子特效（榴弹炮爆炸效果）
void ShowParticle(float pos[3], char[] particleName)
{
    int particle = CreateEntityByName("info_particle_system");
    if (particle != -1)
    {
        // 先设置位置
        TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);

        // 设置粒子名称
        SetEntPropString(particle, Prop_Data, "m_iszEffectName", particleName);

        DispatchSpawn(particle);
        ActivateEntity(particle);

        // 启动粒子
        AcceptEntityInput(particle, "Start");

        // 5秒后删除粒子
        CreateTimer(5.0, Timer_DeleteParticle, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_DeleteParticle(Handle timer, int particleRef)
{
    int particle = EntRefToEntIndex(particleRef);
    if (particle > 0 && IsValidEntity(particle))
    {
        AcceptEntityInput(particle, "Kill");
    }
    return Plugin_Stop;
}

// 屏幕震动
void ShakeScreen(float pos[3], float radius)
{
    int shake = CreateEntityByName("env_shake");
    if (shake != -1)
    {
        SetEntPropFloat(shake, Prop_Data, "m_amplitude", 25.0);
        SetEntPropFloat(shake, Prop_Data, "m_frequency", 150.0);
        SetEntPropFloat(shake, Prop_Data, "m_duration", 1.5);
        SetEntProp(shake, Prop_Data, "m_radius", radius);

        TeleportEntity(shake, pos, NULL_VECTOR, NULL_VECTOR);

        DispatchSpawn(shake);
        ActivateEntity(shake);

        AcceptEntityInput(shake, "StartShake");
        AcceptEntityInput(shake, "Kill");
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
    }
}