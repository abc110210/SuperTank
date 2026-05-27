/**
 * 爆炸Tank模块
 * 红色皮肤 + 石头双重爆炸
 * 基于Mutant Tanks的实现方式
 */

// 爆炸Tank实体引用
static int g_iThisExplodeTankEntRef = INVALID_ENT_REFERENCE;

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

    PrintToChatAll("\x03[寄寄之家 - SuperTank] \x01强力感染者 \x06爆炸Tank \x01已出现!");
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

    // 创建第一次爆炸
    ExplodeTank_CreateExplosion(pos, 1.3);

    // 延迟创建第二次爆炸
    DataPack pack = new DataPack();
    pack.WriteFloat(pos[0]);
    pack.WriteFloat(pos[1]);
    pack.WriteFloat(pos[2]);
    CreateTimer(0.2, Timer_ExplodeTankSecondExplosion, pack, TIMER_FLAG_NO_MAPCHANGE);
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

// ==================== 清理函数 ====================

// 清理所有爆炸Tank效果
void ExplodeTank_ClearAllEffects(int tank)
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
        PrintToServer("[爆炸TankDEBUG] 爆炸Tank死亡，清理引用");
    }
}