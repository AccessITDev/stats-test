extends Node
## Scene-based test for TurnScheduler. This exists as a scene (not a
## standalone `-s` script like the earlier tests) because autoloads are
## only initialized when Redot boots a real scene - `-s` scripts run in a
## minimal SceneTree that skips project autoload setup entirely. Since
## TurnScheduler's own code depends on the EntityRegistry autoload
## internally, testing it honestly requires going through the real boot
## path.
##
## Run via F6 in the editor (this is a full scene, F6 works the same way),
## or from a terminal in the project folder:
##   redot --headless --path . tests/test_turn_scheduler_scene.tscn

func _ready() -> void:
	var entity_a: int = EntityRegistry.create_entity()
	EntityRegistry.add_component(entity_a, TurnTakerComponent.new())

	var entity_b: int = EntityRegistry.create_entity()
	EntityRegistry.add_component(entity_b, TurnTakerComponent.new())

	TurnScheduler.start_round()

	var first_active: int = TurnScheduler.get_active_entity()
	assert(first_active == entity_a, "Expected entity_a (lower id) to go first, got %d" % first_active)
	assert(TurnScheduler.is_active_entity(entity_a), "is_active_entity should be true for entity_a")
	assert(not TurnScheduler.is_active_entity(entity_b), "is_active_entity should be false for entity_b")

	TurnScheduler.advance_turn()
	var second_active: int = TurnScheduler.get_active_entity()
	assert(second_active == entity_b, "Expected entity_b to go second, got %d" % second_active)

	TurnScheduler.advance_turn()
	var wrapped_active: int = TurnScheduler.get_active_entity()
	assert(wrapped_active == entity_a, "Expected turn order to wrap back to entity_a, got %d" % wrapped_active)

	# --- Speed determines order: higher speed acts first, ties fall back to id ---
	var fast_id: int = EntityRegistry.create_entity()
	var fast_turn_taker := TurnTakerComponent.new()
	fast_turn_taker.speed = 5
	EntityRegistry.add_component(fast_id, fast_turn_taker)

	TurnScheduler.start_round()  # fresh round, now with three entities
	assert(TurnScheduler.get_active_entity() == fast_id, "Higher speed (5) should act first, got %d" % TurnScheduler.get_active_entity())
	TurnScheduler.advance_turn()
	assert(TurnScheduler.get_active_entity() == entity_a, "Tied speed (1 vs 1) should fall back to ascending entity id")
	TurnScheduler.advance_turn()
	assert(TurnScheduler.get_active_entity() == entity_b, "entity_b should be third")

	# --- Elapsed time tracking (TECHNICAL_DESIGN.md §9): the smallest
	# possible slice - just prove seconds accumulate correctly per
	# resolved action type. No consequence wired to this yet. ---
	assert(TurnScheduler.get_elapsed_seconds() == 0, "Elapsed time should start at 0 before any action resolves")

	var mover_id: int = EntityRegistry.create_entity()
	var mover_pos := PositionComponent.new()
	mover_pos.grid_position = Vector2i(0, 0)
	EntityRegistry.add_component(mover_id, mover_pos)

	ActionResolver.resolve_move(mover_id, ActionResolver.Direction.RIGHT)
	assert(TurnScheduler.get_elapsed_seconds() == 1, "A move should cost 1 second, got %d" % TurnScheduler.get_elapsed_seconds())

	var attacker_id: int = EntityRegistry.create_entity()
	var attacker_pos := PositionComponent.new()
	attacker_pos.grid_position = Vector2i(2, 0)
	EntityRegistry.add_component(attacker_id, attacker_pos)
	var attacker_stats := StatsComponent.new()
	attacker_stats.power = 1
	EntityRegistry.add_component(attacker_id, attacker_stats)
	EntityRegistry.add_component(attacker_id, SkillsComponent.new())  # needed for resolve_ability below

	var victim_id: int = EntityRegistry.create_entity()
	var victim_pos := PositionComponent.new()
	victim_pos.grid_position = Vector2i(3, 0)  # adjacent to attacker
	EntityRegistry.add_component(victim_id, victim_pos)
	EntityRegistry.add_component(victim_id, StatsComponent.new())

	ActionResolver.resolve_attack(attacker_id, victim_id)
	assert(TurnScheduler.get_elapsed_seconds() == 2, "An attack should add 1 more second (1 move + 1 attack), got %d" % TurnScheduler.get_elapsed_seconds())

	TurnScheduler.reset_elapsed_time()
	assert(TurnScheduler.get_elapsed_seconds() == 0, "reset_elapsed_time should zero the clock")

	# A rejected action never reaches ActionResolver.action_resolved, so it shouldn't cost anything.
	var illegal_move: GameEvent = ActionResolver.resolve_move(mover_id, ActionResolver.Direction.UP)  # mover is at (1,0); UP goes to (1,-1), off-grid
	assert(illegal_move == null, "Sanity check: moving off-grid should be rejected")
	assert(TurnScheduler.get_elapsed_seconds() == 0, "A rejected action should not cost any time")

	var heal_event: GameEvent = ActionResolver.resolve_ability(attacker_id, "heal", victim_id)
	assert(heal_event != null, "Heal should succeed - victim is alive")
	assert(TurnScheduler.get_elapsed_seconds() == 2, "An ability should cost 2 seconds, got %d" % TurnScheduler.get_elapsed_seconds())

	print("TurnScheduler smoke test: all assertions passed.")
	get_tree().quit()
