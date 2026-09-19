extends Node
## Scene-based test for ProceduralInterpreter. Needs to be a scene (not a
## `-s` script) for the integration section, which calls the real
## ActionResolver/EntityRegistry autoloads.
##
## Run via F6 with this scene open, or:
##   redot --headless --path . tests/test_procedural_interpreter_scene.tscn

func _ready() -> void:
	var interpreter := ProceduralInterpreter.new()
	assert(interpreter.is_available(), "ProceduralInterpreter should always report available")

	# --- Hand-built events: correct substitution, no leftover {tokens} ---
	var moved_event := GameEvent.new("moved", {"actor_id": 7})
	var moved_line: String = interpreter.narrate_event(moved_event)
	assert(not moved_line.is_empty(), "moved narration should not be empty")
	assert(not moved_line.contains("{"), "moved narration should have no leftover template tokens: %s" % moved_line)
	assert(moved_line.contains("Entity 7"), "moved narration should mention the actor: %s" % moved_line)

	var hit_event := GameEvent.new("attack_hit", {"actor_id": 1, "target_id": 2, "damage": 5})
	var hit_line: String = interpreter.narrate_event(hit_event)
	assert(not hit_line.contains("{"), "attack_hit narration should have no leftover tokens: %s" % hit_line)
	assert(hit_line.contains("Entity 1") and hit_line.contains("Entity 2") and hit_line.contains("5"), "attack_hit narration should mention actor, target, and damage: %s" % hit_line)

	var defeat_event := GameEvent.new("attack_defeated", {"actor_id": 1, "target_id": 2, "damage": 8})
	var defeat_line: String = interpreter.narrate_event(defeat_event)
	assert(not defeat_line.contains("{"), "attack_defeated narration should have no leftover tokens: %s" % defeat_line)

	# --- ability_used: damage, out-of-reach, and pure-movement cases ---
	var ability_damage_event := GameEvent.new("ability_used", {"actor_id": 1, "ability_name": "Power Strike", "damage": 8})
	var ability_damage_line: String = interpreter.narrate_event(ability_damage_event)
	assert(ability_damage_line.contains("Power Strike") and ability_damage_line.contains("8 damage"), "Ability narration should name the ability and show damage: %s" % ability_damage_line)

	var ability_reach_event := GameEvent.new("ability_used", {"actor_id": 1, "ability_name": "Power Strike", "damage": 0, "out_of_reach": true})
	var ability_reach_line: String = interpreter.narrate_event(ability_reach_event)
	assert(ability_reach_line.contains("out of reach"), "An ability that whiffed should say so, not silently show 0 damage: %s" % ability_reach_line)

	var ability_move_event := GameEvent.new("ability_used", {"actor_id": 1, "ability_name": "Dash", "cells_moved": 2})
	var ability_move_line: String = interpreter.narrate_event(ability_move_event)
	assert(ability_move_line.contains("Dash") and ability_move_line.contains("2 cell"), "A pure-movement ability should mention cells moved, not damage it never dealt: %s" % ability_move_line)
	assert(not ability_move_line.contains("damage"), "A pure-movement ability shouldn't mention damage at all: %s" % ability_move_line)

	# --- Unknown event type: bland fallback, no crash ---
	var unknown_event := GameEvent.new("something_unforeseen", {})
	var unknown_line: String = interpreter.narrate_event(unknown_event)
	assert(unknown_line == "Something happens.", "Unknown event types should get the bland fallback, got: %s" % unknown_line)

	# --- Integration: real ActionResolver output narrates correctly ---
	var actor_id: int = EntityRegistry.create_entity()
	var actor_pos := PositionComponent.new()
	actor_pos.grid_position = Vector2i(1, 1)
	EntityRegistry.add_component(actor_id, actor_pos)
	var actor_stats := StatsComponent.new()
	actor_stats.power = 4
	EntityRegistry.add_component(actor_id, actor_stats)

	var move_event: GameEvent = ActionResolver.resolve_move(actor_id, ActionResolver.Direction.UP)
	assert(move_event != null, "Move should succeed (no bounds/occupancy issue moving up from (1,1))")
	var move_line: String = interpreter.narrate_event(move_event)
	assert(not move_line.contains("{"), "Real move event should narrate cleanly: %s" % move_line)
	assert(actor_pos.grid_position == Vector2i(1, 0), "Sanity check: actor should now be at (1,0)")

	# Target placed adjacent to the actor's *new* position, (1,0).
	var target_id: int = EntityRegistry.create_entity()
	var target_pos := PositionComponent.new()
	target_pos.grid_position = Vector2i(2, 0)
	EntityRegistry.add_component(target_id, target_pos)
	var target_stats := StatsComponent.new()
	target_stats.current_hp = 10
	EntityRegistry.add_component(target_id, target_stats)

	var attack_event: GameEvent = ActionResolver.resolve_attack(actor_id, target_id)
	assert(attack_event != null, "Attack should succeed - target is adjacent to the actor's post-move position")
	var attack_line: String = interpreter.narrate_event(attack_event)
	assert(not attack_line.contains("{"), "Real attack event should narrate cleanly: %s" % attack_line)
	assert(attack_line.contains("4"), "Attack narration should mention the 4 damage dealt: %s" % attack_line)

	print("ProceduralInterpreter smoke test: all assertions passed.")
	get_tree().quit()
