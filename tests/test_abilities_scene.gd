extends Node
## Scene-based test for the ability system: AbilityRegistry, EffectLibrary,
## ActionResolver.resolve_ability, and RecoveringComponent's interaction
## with TurnScheduler. Needs a scene - depends on many autoloads.
##
## Run via F6 with this scene open, or:
##   redot --headless --path . tests/test_abilities_scene.tscn

func _ready() -> void:
	# --- Registry discovery ---
	assert(AbilityRegistry.has_definition("dash"), "dash.tres should have been auto-discovered")
	assert(AbilityRegistry.has_definition("power_strike"), "power_strike.tres should have been auto-discovered")
	assert(AbilityRegistry.has_definition("charging_strike"), "charging_strike.tres should have been auto-discovered")

	var actor_id: int = EntityRegistry.create_entity()
	var actor_pos := PositionComponent.new()
	actor_pos.grid_position = Vector2i(0, 0)
	EntityRegistry.add_component(actor_id, actor_pos)
	var actor_stats := StatsComponent.new()
	actor_stats.power = 5
	EntityRegistry.add_component(actor_id, actor_stats)
	EntityRegistry.add_component(actor_id, TurnTakerComponent.new())
	var actor_skills := SkillsComponent.new()
	EntityRegistry.add_component(actor_id, actor_skills)

	# A second turn-taker, purely to prove the recovery-skip mechanism later.
	var other_id: int = EntityRegistry.create_entity()
	var other_pos := PositionComponent.new()
	other_pos.grid_position = Vector2i(4, 4)
	EntityRegistry.add_component(other_id, other_pos)
	EntityRegistry.add_component(other_id, TurnTakerComponent.new())
	var other_stats := StatsComponent.new()
	EntityRegistry.add_component(other_id, other_stats)

	var skipped_events: Array[GameEvent] = []
	TurnScheduler.turn_skipped.connect(func(event: GameEvent) -> void: skipped_events.append(event))

	TurnScheduler.start_round()

	# --- Nothing unlocked before any skill XP ---
	assert(not ActionResolver.can_use_ability(actor_id, "dash"), "dash shouldn't be unlocked with 0 athletics")
	assert(not ActionResolver.can_use_ability(actor_id, "power_strike"), "power_strike shouldn't be unlocked with 0 melee_combat")
	assert(not ActionResolver.can_use_ability(actor_id, "charging_strike"), "charging_strike needs both")

	# --- Seed both skills to level 1 ---
	actor_skills.add_xp("athletics", 100)
	actor_skills.add_xp("melee_combat", 100)
	assert(ActionResolver.can_use_ability(actor_id, "dash"), "dash should unlock at athletics level 1")
	assert(ActionResolver.can_use_ability(actor_id, "power_strike"), "power_strike should unlock at melee_combat level 1")
	assert(ActionResolver.can_use_ability(actor_id, "charging_strike"), "charging_strike should unlock once both are level 1")

	var unlocked: Array[String] = AbilityRegistry.get_unlocked_ids(actor_skills)
	unlocked.sort()
	assert(unlocked == ["charging_strike", "dash", "heal", "power_strike", "revive"], "All three skill-gated abilities plus the two always-available ones should be unlocked now, got %s" % str(unlocked))

	# --- Dash: 2 clear cells, nothing in the way ---
	var dash_event: GameEvent = ActionResolver.resolve_ability(actor_id, "dash", -1, ActionResolver.Direction.RIGHT)
	assert(dash_event != null, "Dash should succeed")
	assert(actor_pos.grid_position == Vector2i(2, 0), "Dash should move 2 cells right from (0,0), got %s" % actor_pos.grid_position)
	assert(dash_event.data.get("cells_moved", 0) == 2, "Dash event should report 2 cells moved")
	assert(actor_skills.get_xp("athletics") == 110, "Dash should train athletics via its internal moves (100 + 2x5), got %d" % actor_skills.get_xp("athletics"))

	# --- Dash distance keeps growing with continued Athletics investment,
	# not just at the level-1 unlock threshold - the actual "powerfully
	# broken" payoff for grinding past minimum. ---
	actor_skills.xp["athletics"] = 300  # level 3
	actor_pos.grid_position = Vector2i(0, 0)  # reset to a corner with room to move
	var big_dash_event: GameEvent = ActionResolver.resolve_ability(actor_id, "dash", -1, ActionResolver.Direction.RIGHT)
	assert(big_dash_event.data.get("cells_moved", 0) == 4, "At Athletics level 3, Dash should cover 4 cells (1 base + 1/level x3), got %d" % big_dash_event.data.get("cells_moved", 0))
	assert(actor_pos.grid_position == Vector2i(4, 0), "A level-3 Dash from (0,0) should reach the far edge of a 5-wide grid in one action, got %s" % actor_pos.grid_position)

	actor_pos.grid_position = Vector2i(2, 0)  # put the actor back for the rest of the test to proceed as before
	actor_skills.xp["athletics"] = 110  # and back down, so later assertions aren't affected

	# --- Power Strike: adjacent target, double damage, and a real recovery cost ---
	var target_id: int = EntityRegistry.create_entity()
	var target_pos := PositionComponent.new()
	target_pos.grid_position = Vector2i(3, 0)  # adjacent to actor's post-dash position (2,0)
	EntityRegistry.add_component(target_id, target_pos)
	var target_stats := StatsComponent.new()
	target_stats.max_hp = 50
	target_stats.current_hp = 50
	EntityRegistry.add_component(target_id, target_stats)

	var strike_event: GameEvent = ActionResolver.resolve_ability(actor_id, "power_strike", target_id)
	assert(strike_event != null, "Power Strike should succeed")
	assert(strike_event.data.get("damage", 0) == 10, "Power Strike should deal 10 damage (5 power x2), got %d" % strike_event.data.get("damage", 0))
	assert(target_stats.current_hp == 40, "Target HP should drop from 50 to 40, got %d" % target_stats.current_hp)
	assert(actor_skills.get_xp("melee_combat") == 110, "Power Strike should train melee_combat via AbilityDefinition.trains (100 + 10), got %d" % actor_skills.get_xp("melee_combat"))
	var recovering: RecoveringComponent = EntityRegistry.get_component(actor_id, "RecoveringComponent")
	assert(recovering != null, "Power Strike should attach RecoveringComponent")
	assert(recovering.turns_remaining == 1, "Recovery should last 1 turn")

	# --- TurnScheduler actually skips the recovering entity ---
	assert(TurnScheduler.get_active_entity() == actor_id, "Should still be actor's turn right after using the ability")
	TurnScheduler.advance_turn()
	assert(TurnScheduler.get_active_entity() == other_id, "Should now be other_id's turn")
	TurnScheduler.advance_turn()  # wraps to a new round - actor would go first, but is recovering
	assert(TurnScheduler.get_active_entity() == other_id, "actor_id should have been skipped due to RecoveringComponent")
	assert(EntityRegistry.get_component(actor_id, "RecoveringComponent") == null, "RecoveringComponent should be gone after being consumed")
	assert(skipped_events.size() == 1, "The recovery skip should have been telegraphed via turn_skipped, got %d events" % skipped_events.size())
	assert(skipped_events[0].data["reason"] == "recovering", "Skip reason should be 'recovering'")
	assert(skipped_events[0].data["entity_id"] == actor_id, "Skip event should name actor_id as the one skipped")

	# --- Charging Strike: target far away, should close distance AND hit ---
	target_pos.grid_position = Vector2i(2, 2)  # 2 cells from actor's current (2,0), not adjacent
	var charge_event: GameEvent = ActionResolver.resolve_ability(actor_id, "charging_strike", target_id)
	assert(charge_event != null, "Charging Strike should succeed")
	assert(charge_event.data.get("cells_moved", 0) > 0, "Charging Strike should move the actor closer")
	assert(charge_event.data.get("damage", 0) == 5, "Charging Strike should deal 5 damage (5 power x1) once in range, got %d" % charge_event.data.get("damage", 0))
	assert(target_stats.current_hp == 35, "Target HP should now be 35 (40 - 5), got %d" % target_stats.current_hp)
	assert(actor_skills.get_xp("melee_combat") == 120, "Charging Strike should train melee_combat via trains (110 + 10), got %d" % actor_skills.get_xp("melee_combat"))
	assert(actor_skills.get_xp("athletics") == 110 + (charge_event.data["cells_moved"] * 5), "Charging Strike's movement should train athletics via the same internal-move mechanism as Dash, no more and no less (no double count from also having a trains entry), got %d" % actor_skills.get_xp("athletics"))

	# --- A locked ability refuses to resolve, even with a nonsense entity ---
	var locked_id: int = EntityRegistry.create_entity()
	EntityRegistry.add_component(locked_id, SkillsComponent.new())
	assert(not ActionResolver.can_use_ability(locked_id, "dash"), "0 athletics XP should mean dash is locked")
	assert(ActionResolver.resolve_ability(locked_id, "dash", -1, ActionResolver.Direction.RIGHT) == null, "resolve_ability should refuse a locked ability")

	# --- Heal: amount scales with Healing skill level, deliberately weak
	# at level 0. This vertical slice's enemy deals 3 damage per hit -
	# healing below that at level 0 is the point: it's a losing trade
	# until Healing is trained up. First real exploit in the game. ---
	# target_id is currently at 35/50 HP.
	assert(actor_skills.get_level("healing") == 0, "Sanity check: actor hasn't trained Healing yet")
	var heal_event: GameEvent = ActionResolver.resolve_ability(actor_id, "heal", target_id)
	assert(heal_event != null, "Heal should succeed (target is alive)")
	assert(heal_event.data.get("healed", 0) == 2, "At Healing level 0, Heal should restore only 2 HP, got %d" % heal_event.data.get("healed", 0))
	assert(heal_event.data.get("healed", 0) < 3, "Heal at level 0 must stay below the enemy's 3 damage - that's the whole point")
	assert(target_stats.current_hp == 37, "Target HP should now be 37 (35 + 2), got %d" % target_stats.current_hp)
	assert(actor_skills.get_xp("healing") == 10, "Heal should train Healing via trains, got %d" % actor_skills.get_xp("healing"))

	# Grind Healing to level 1 - the exploit actually "unlocking"
	actor_skills.xp["healing"] = 100
	var leveled_heal_event: GameEvent = ActionResolver.resolve_ability(actor_id, "heal", target_id)
	assert(leveled_heal_event.data.get("healed", 0) == 6, "At Healing level 1, Heal should restore 6 HP (2 base + 4/level), got %d" % leveled_heal_event.data.get("healed", 0))
	assert(leveled_heal_event.data.get("healed", 0) > 3, "Heal at level 1 should now beat the enemy's damage output - the exploit paying off")
	assert(target_stats.current_hp == 43, "Target HP should now be 43 (37 + 6), got %d" % target_stats.current_hp)

	target_stats.current_hp = 49  # 1 short of max (50) - next heal should cap, not overheal
	var capped_heal_event: GameEvent = ActionResolver.resolve_ability(actor_id, "heal", target_id)
	assert(capped_heal_event.data.get("healed", 0) == 1, "Heal should only restore 1 HP when 1 short of max, not the full 6, got %d" % capped_heal_event.data.get("healed", 0))
	assert(target_stats.current_hp == 50, "Target HP should cap at max_hp (50), got %d" % target_stats.current_hp)

	target_stats.current_hp = 0  # dead
	var heal_on_dead_event: GameEvent = ActionResolver.resolve_ability(actor_id, "heal", target_id)
	assert(heal_on_dead_event != null, "resolve_ability itself still succeeds - heal is unlocked, it just does nothing useful")
	assert(heal_on_dead_event.data.get("target_dead", false), "Heal should report the target is dead rather than healing them")
	assert(target_stats.current_hp == 0, "A dead target's HP should be untouched by Heal")

	# --- Revive: only works on a dead target, restores a small amount of HP ---
	var revive_event: GameEvent = ActionResolver.resolve_ability(actor_id, "revive", target_id)
	assert(revive_event != null, "Revive should succeed on a dead target")
	assert(revive_event.data.get("revived", false), "Revive should report success")
	assert(target_stats.current_hp == 5, "Revive should restore to the 5 HP configured in revive.tres, got %d" % target_stats.current_hp)
	assert(target_stats.is_alive(), "Target should be alive again after Revive")

	var revive_on_living_event: GameEvent = ActionResolver.resolve_ability(actor_id, "revive", target_id)
	assert(revive_on_living_event.data.get("target_already_alive", false), "Revive should refuse a target that's already alive")
	assert(target_stats.current_hp == 5, "Revive should not touch HP when the target was already alive")

	# --- TurnScheduler skips a dead entity's turn, and stops skipping it once revived ---
	other_stats.current_hp = 0  # kill other_id
	TurnScheduler.start_round()
	if TurnScheduler.get_active_entity() != other_id:
		TurnScheduler.advance_turn()  # get to where other_id would be active
	skipped_events.clear()
	TurnScheduler.advance_turn()
	assert(skipped_events.size() >= 1, "Killing other_id should cause its turn to be skipped and telegraphed")
	var dead_skip: GameEvent = skipped_events.filter(func(e: GameEvent) -> bool: return e.data["entity_id"] == other_id)[0]
	assert(dead_skip.data["reason"] == "dead", "Skip reason for a dead entity should be 'dead', not 'recovering'")

	other_stats.current_hp = 10  # revive it directly for this check
	TurnScheduler.start_round()
	assert(TurnScheduler.get_active_entity() != -1, "Sanity check: a round can still start with other_id alive again")
	var found_other_active: bool = false
	for i in range(3):
		if TurnScheduler.get_active_entity() == other_id:
			found_other_active = true
			break
		TurnScheduler.advance_turn()
	assert(found_other_active, "A revived entity should get turns again, not be permanently skipped")

	print("Abilities smoke test: all assertions passed.")
	get_tree().quit()
