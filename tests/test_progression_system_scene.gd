extends Node
## Scene-based test for ProgressionSystem - depends on ActionResolver,
## EntityRegistry, and (via SkillsComponent) SkillRegistry, all autoloads.
##
## Run via F6 with this scene open, or:
##   redot --headless --path . tests/test_progression_system_scene.tscn

var leveled_up_events: Array[GameEvent] = []


func _on_skill_leveled_up(event: GameEvent) -> void:
	leveled_up_events.append(event)


func _ready() -> void:
	ProgressionSystem.skill_leveled_up.connect(_on_skill_leveled_up)

	var actor_id: int = EntityRegistry.create_entity()
	var actor_pos := PositionComponent.new()
	actor_pos.grid_position = Vector2i(2, 2)
	EntityRegistry.add_component(actor_id, actor_pos)
	var actor_stats := StatsComponent.new()
	actor_stats.power = 5
	EntityRegistry.add_component(actor_id, actor_stats)
	var actor_skills := SkillsComponent.new()
	EntityRegistry.add_component(actor_id, actor_skills)

	var target_id: int = EntityRegistry.create_entity()
	var target_pos := PositionComponent.new()
	target_pos.grid_position = Vector2i(3, 1)  # adjacent to the actor's post-move position, (2,1)
	EntityRegistry.add_component(target_id, target_pos)
	var target_stats := StatsComponent.new()
	target_stats.current_hp = 50
	EntityRegistry.add_component(target_id, target_stats)
	# Deliberately no SkillsComponent on the target - tests the graceful-skip path.

	# --- A move awards athletics XP to the actor, no level-up yet ---
	var move_event: GameEvent = ActionResolver.resolve_move(actor_id, ActionResolver.Direction.UP)
	assert(move_event != null, "Move should succeed from (2,2)")
	assert(actor_skills.get_xp("athletics") == 5, "One move should grant 5 athletics XP, got %d" % actor_skills.get_xp("athletics"))
	assert(leveled_up_events.is_empty(), "5 XP shouldn't trigger a level-up yet")

	# --- An attack awards melee_combat XP to the actor, not the target ---
	var attack_event: GameEvent = ActionResolver.resolve_attack(actor_id, target_id)
	assert(attack_event != null, "Attack should succeed - target is adjacent")
	assert(actor_skills.get_xp("melee_combat") == 10, "One hit should grant 10 melee_combat XP, got %d" % actor_skills.get_xp("melee_combat"))
	# No crash from the target lacking a SkillsComponent - that's the pass condition for that path.

	# --- Crossing a level threshold fires skill_leveled_up ---
	actor_skills.xp["melee_combat"] = 90  # one more hit (10 xp) will cross 100
	var leveling_attack: GameEvent = ActionResolver.resolve_attack(actor_id, target_id)
	assert(leveling_attack != null, "Second attack should also succeed")
	assert(leveled_up_events.size() == 1, "Crossing the threshold should emit exactly one skill_leveled_up event, got %d" % leveled_up_events.size())
	var level_event: GameEvent = leveled_up_events[0]
	assert(level_event.data["skill_id"] == "melee_combat", "Level-up event should be for melee_combat")
	assert(level_event.data["new_level"] == 1, "Level-up event should report new_level 1, got %d" % level_event.data["new_level"])
	assert(level_event.data["entity_id"] == actor_id, "Level-up event should report the actor, not the target")

	print("ProgressionSystem smoke test: all assertions passed.")
	get_tree().quit()
