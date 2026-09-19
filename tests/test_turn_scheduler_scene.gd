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

	print("TurnScheduler smoke test: all assertions passed.")
	get_tree().quit()
