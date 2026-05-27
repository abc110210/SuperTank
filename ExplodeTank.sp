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
int ExplodeTank_GetCurrentTank()
{
    return EntRefToEntIndex(g_iThisExplodeTankEntRef);
}

// 检查指定索引的石头是否匹配指定的引用
bool ExplodeTank_IsTrackedRock(int index, int rockRef)
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
void TriggerRockExplosion(float pos[3])
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

void ExplodeTank_CreateExplosion(float pos[3])
{
    PrintToServer("[爆炸TankDEBUG] 创建Pipe Bomb爆炸: pos=(%.1f,%.1f,%.1f)", pos[0], pos[1], pos[2]);

    // 获取配置的伤害值
    ConVar explosionDamage = FindConVar("shan_ExplodeTank_explosion_damage");
    int damage = (explosionDamage != null) ? explosionDamage.IntValue : 50;

    // 1. 创建env_explosion实体（Pipe Bomb式爆炸）
    int explosion = CreateEntityByName("env_explosion");
    if (explosion != -1)
    {
        TeleportEntity(explosion, pos, NULL_VECTOR, NULL_VECTOR);

        char damageStr[32];
        IntToString(damage, damageStr, sizeof(damageStr));

        char radiusStr[32];
        IntToString(350, radiusStr, sizeof(radiusStr)); // Pipe Bomb爆炸范围

        DispatchKeyValue(explosion, "iMagnitude", damageStr);
        DispatchKeyValue(explosion, "iRadiusOverride", radiusStr);
        DispatchKeyValue(explosion, "fireballsprite", "sprites/zerogxplode.spr");
        SetEntProp(explosion, Prop_Data, "m_spawnflags", 8); // 环境爆炸
        DispatchSpawn(explosion);
        ActivateEntity(explosion);
        AcceptEntityInput(explosion, "Explode");
        AcceptEntityInput(explosion, "Kill");
        PrintToServer("[爆炸TankDEBUG] env_explosion创建成功: 伤害=%d, 范围=350", damage);
    }

    // 2. Pipe Bomb主爆炸粒子效果（火焰爆炸）
    int particle = CreateEntityByName("info_particle_system");
    if (particle != -1)
    {
        TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchKeyValue(particle, "effect_name", "weapon_pipebomb_explosion"); // Pipe Bomb主爆炸效果
        DispatchSpawn(particle);
        ActivateEntity(particle);
        AcceptEntityInput(particle, "Start");
        CreateTimer(2.0, Timer_ExplodeTankRemoveParticle, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
        PrintToServer("[爆炸TankDEBUG] Pipe Bomb爆炸粒子创建成功");
    }

    // 3. 冲击火花效果
    int sparkParticle = CreateEntityByName("info_particle_system");
    if (sparkParticle != -1)
    {
        TeleportEntity(sparkParticle, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchKeyValue(sparkParticle, "effect_name", "sparks_bounce"); // 冲击火花
        DispatchSpawn(sparkParticle);
        ActivateEntity(sparkParticle);
        AcceptEntityInput(sparkParticle, "Start");
        CreateTimer(1.0, Timer_ExplodeTankRemoveParticle, EntIndexToEntRef(sparkParticle), TIMER_FLAG_NO_MAPCHANGE);
        PrintToServer("[爆炸TankDEBUG] 冲击火花粒子创建成功");
    }

    // 4. 烟雾效果
    int smokeParticle = CreateEntityByName("info_particle_system");
    if (smokeParticle != -1)
    {
        TeleportEntity(smokeParticle, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchKeyValue(smokeParticle, "effect_name", "explosion_smoke"); // 爆炸烟雾
        DispatchSpawn(smokeParticle);
        ActivateEntity(smokeParticle);
        AcceptEntityInput(smokeParticle, "Start");
        CreateTimer(4.0, Timer_ExplodeTankRemoveParticle, EntIndexToEntRef(smokeParticle), TIMER_FLAG_NO_MAPCHANGE);
        PrintToServer("[爆炸TankDEBUG] 烟雾粒子创建成功");
    }

    // 5. Pipe Bomb爆炸音效
    char soundPath[] = "weapons/pipe_bomb/explode3.wav";
    PrecacheSound(soundPath, true);
    EmitAmbientSound(soundPath, pos, SNDLEVEL_GUNFIRE, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, 0.0);

    // 6. 强力震动效果
    int shake = CreateEntityByName("env_shake");
    if (shake != -1)
    {
        TeleportEntity(shake, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchKeyValue(shake, "amplitude", "25.0");
        DispatchKeyValue(shake, "duration", "0.8");
        DispatchKeyValue(shake, "frequency", "150.0");
        DispatchKeyValue(shake, "radius", "600");
        SetEntProp(shake, Prop_Data, "m_spawnflags", 4); // 全局震动
        DispatchSpawn(shake);
        ActivateEntity(shake);
        AcceptEntityInput(shake, "StartShake");
        AcceptEntityInput(shake, "Kill");
        PrintToServer("[爆炸TankDEBUG] 震动效果创建成功");
    }

    PrintToChatAll("[爆炸Tank] 石头爆炸! 伤害=%d", damage);
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