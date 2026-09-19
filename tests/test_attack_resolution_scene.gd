extends Node
## Scene-based test for ActionResolver.can_attack / resolve_attack.
## Run via F6 with this scene open, or:
##   redot --headless --path . tests/test_attack_resolution_scene.tscn

var received_events: Array[GameEvent] = []


func _on_action_resolved(event: GameEvent) -> void:
	received_events.append(event)


func _ready() -> void:
	ActionResolver.action_resolved.connect(_on_action_resolved)

	# --- Attacker and target, adjacent ---
	var attacker_id: int = EntityRegistry.create_entity()
	var attacker_pos := PositionComponent.new()
	attacker_pos.grid_position = Vector2i(2, 2)
	EntityRegistry.add_component(attacker_id, attacker_pos)
	var attacker_stats := StatsComponent.new()
	attacker_stats.power = 5
	EntityRegistry.add_component(attacker_id, attacker_stats)

	var target_id: int = EntityRegistry.create_entity()
	var target_pos := PositionComponent.new()
	target_pos.grid_position = Vector2i(3, 2)  # adjacent, right of attacker
	EntityRegistry.add_component(target_id, target_pos)
	var target_stats := StatsComponent.new()
	target_stats.max_hp = 12
	target_stats.current_hp = 12
	EntityRegistry.add_component(target_id, target_stats)

	# --- can_attack: adjacent and alive -> true ---
	assert(ActionResolver.can_attack(attacker_id, target_id), "Adjacent, living target should be attackable")

	# --- A far-away entity should not be attackable ---
	var far_id: int = EntityRegistry.create_entity()
	var far_pos := PositionComponent.new()
	far_pos.grid_position = Vector2i(0, 0)
	EntityRegistry.add_component(far_id, far_pos)
	EntityRegistry.add_component(far_id, StatsComponent.new())
	assert(not ActionResolver.can_attack(attacker_id, far_id), "Non-adjacent target should not be attackable")

	# --- resolve_attack: legal hit ---
	var event: GameEvent = ActionResolver.resolve_attack(attacker_id, target_id)
	assert(event != null, "resolve_attack should return a GameEvent for a legal attack")
	assert(event.event_type == "attack_hit", "Target survives a 5-damage hit at 12 HP, expected attack_hit")
	assert(target_stats.current_hp == 7, "Target HP should drop from 12 to 7, got %d" % target_stats.current_hp)
	assert(received_events.size() == 1, "action_resolved signal should have fired exactly once")

	# --- resolve_attack: illegal (non-adjacent) attack ---
	var illegal_event: GameEvent = ActionResolver.resolve_attack(attacker_id, far_id)
	assert(illegal_event == null, "resolve_attack should return null for a non-adjacent target")
	assert(received_events.size() == 1, "action_resolved should not fire again for a rejected attack")

	# --- resolve_attack: a killing blow ---
	target_stats.current_hp = 3  # about to die to a 5-power hit
	var defeat_event: GameEvent = ActionResolver.resolve_attack(attacker_id, target_id)
	assert(defeat_event != null, "A killing blow should still resolve")
	assert(defeat_event.event_type == "attack_defeated", "Expected attack_defeated once HP reaches 0")
	assert(target_stats.current_hp == 0, "HP should clamp at 0, not go negative")
	assert(not target_stats.is_alive(), "Target should be dead")

	# --- Can't attack an already-dead target ---
	assert(not ActionResolver.can_attack(attacker_id, target_id), "A dead target should no longer be attackable")

	print("Attack resolution smoke test: all assertions passed.")
	get_tree().quit()
