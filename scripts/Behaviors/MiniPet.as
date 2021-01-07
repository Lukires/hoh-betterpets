auto g_collect_gold = HashString("collect_gold");
auto g_collect_ore = HashString("collect_ore");

enum PetState
{
	MovingToPickup = 0,
	MovingToPlayer,
	Idle
}

class MiniPet
{
	Actor@ m_owner;
	UnitPtr m_unit;

	AnimString@ m_animIdle;
	AnimString@ m_animWalk;
	
	float m_idleSpeed;
	float m_speed;
	
	bool m_hasTarget;
	vec2 m_target;
	UnitPtr m_lastUnitFound;
	int m_targetingDelay;
	
	int m_idleRange;
	int m_pickupRange;
	int m_pickupDuration;
	int m_idleDuration;
	int m_leashRange;

	PetState m_state;

	array<uint> m_flags;

    dictionary spotted_pickups;

	MiniPet(UnitPtr unit, SValue& params)
	{
		m_unit = unit;

		@m_animIdle = AnimString(GetParamString(unit, params, "anim-idle", false));
		@m_animWalk = AnimString(GetParamString(unit, params, "anim-walk", false));

		m_speed = GetParamFloat(unit, params, "speed", false, 3.0f);
		m_idleSpeed = GetParamFloat(unit, params, "idle-speed", false, 1.0f);

		m_idleRange = GetParamInt(unit, params, "range-idle", false, 100) * 1.5;
		m_pickupRange = GetParamInt(unit, params, "range-pickup", false, 200) * 1.2;

		m_pickupDuration = GetParamInt(unit, params, "pickup-duration", false, 2000);
		m_idleDuration = GetParamInt(unit, params, "idle-duration", false, 750);
		
		m_unit.SetMultiplyColor(vec4(1, 1, 1, GetVarFloat("g_pet_alpha")));

		m_leashRange = GetParamInt(unit, params, "leash-range", false, 350) * 100;
	}
	
	void Initialize(Actor@ owner, const array<uint> &in flags)
	{
		@m_owner = owner;
		m_flags = flags;
	}

	bool IsHusk()
	{
		return m_owner.IsHusk();
	}

	bool IsPickupOkay(Pickup@ p)
	{
		if (cast<Town>(g_gameMode) !is null)
			return false;
	
		if (p.m_pickupTrigger == Modifiers::EffectTrigger::PickupMoney)
			return (m_flags.find(g_collect_gold) != -1);
		else if (p.m_pickupTrigger == Modifiers::EffectTrigger::PickupOre)
			return (m_flags.find(g_collect_ore) != -1);

		return false;
	}
	
	void SetTarget(vec2 target, PetState petState)
	{
		if (!IsHusk())
			(Network::Message("SetPetTarget") << target << int(petState)).SendToAll();
		else
			return;

		m_hasTarget = true;
		m_target = target;
		m_state = petState;
	}

	void NetSetTarget(vec2 target, int petState)
	{
		if (!IsHusk())
			return;

		m_hasTarget = true;
		m_target = target;
		m_state = PetState(petState);
	}

	void ClearTarget()
	{
		m_hasTarget = false;
		m_target = vec2();
		m_state = PetState::Idle;
	}

	UnitPtr GetNearestSpottedPickup() {

		UnitPtr closestUnit = UnitPtr();
		float closestDistance = 999999999;
		string best_key;

		array<string> keys = spotted_pickups.getKeys();
		for (uint i = 0; i < keys.length(); i++) {
			UnitPtr pickup;
			spotted_pickups.get(keys[i], pickup);

			float distance = distsq(pickup.GetPosition(), m_unit.GetPosition()) * (randf() / 2.0f + 0.75f);

			if (m_lastUnitFound == pickup) {
				distance *= 10;
			}

			if (distance < closestDistance) {
				closestDistance = distance;
				closestUnit = pickup;
				best_key = keys[i];
			}
		}

		spotted_pickups.delete(best_key);
		return closestUnit;
	}

    vec2 FindPickupTarget(bool &out found, int range)
	{
		if (cast<Town>(g_gameMode) !is null)
		{
			found = false;
			return vec2();
		}

		vec2 ownerPos = xy(m_owner.m_unit.GetPosition());

		auto results = g_scene.FetchUnitsWithBehavior("Pickup", ownerPos, range);

		for (uint i = 0; i < results.length(); i++)
		{
			auto unit = results[i];
			auto pickup = cast<Pickup>(unit.GetScriptBehavior());

			if (pickup is null)
				continue;
			
			if (!IsPickupOkay(pickup))
				continue;
			
            spotted_pickups.set(results[i].GetPosition(), results[i]);
		}

		UnitPtr closestUnit = GetNearestSpottedPickup();
		
		if (!closestUnit.IsValid())
		{
			found = false;
			return vec2();
		}

		m_lastUnitFound = closestUnit;
		found = true;
		return xy(closestUnit.GetPosition());
	}
}
