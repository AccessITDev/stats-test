extends SceneTree
## Standalone smoke test for EntityRegistry + Component.
##
## Run it from the Redot editor with this script open (Run Current Script,
## F6), or from a terminal in the project folder:
##   redot --headless -s tests/test_entity_registry.gd

func _init() -> void:
	var registry = load("res://systems/entity_registry.gd").new()

	var player_id: int = registry.create_entity()
	var enemy_id: int = registry.create_entity()

	var player_pos := PositionComponent.new()
	player_pos.grid_position = Vector2i(0, 0)
	registry.add_component(player_id, player_pos)

	var enemy_pos := PositionComponent.new()
	enemy_pos.grid_position = Vector2i(3, 3)
	registry.add_component(enemy_id, enemy_pos)

	# Declared as Array[String] explicitly: calling through "registry" (untyped,
	# since it was loaded dynamically) skips the automatic literal-to-typed-array
	# conversion the compiler would otherwise insert for a statically typed call.
	var position_type: Array[String] = ["PositionComponent"]

	var with_position: Array[int] = registry.get_entities_with(position_type)
	assert(with_position.size() == 2, "Expected 2 entities with PositionComponent, got %d" % with_position.size())

	var fetched: Component = registry.get_component(player_id, "PositionComponent")
	assert(fetched == player_pos, "get_component did not return the same instance that was added")

	registry.remove_component(enemy_id, "PositionComponent")
	var after_removal: Array[int] = registry.get_entities_with(position_type)
	assert(after_removal.size() == 1, "Expected 1 entity with PositionComponent after removal, got %d" % after_removal.size())

	registry.destroy_entity(player_id)
	assert(not registry.entity_exists(player_id), "player_id should no longer exist after destroy_entity")

	print("EntityRegistry smoke test: all assertions passed.")

	# registry is a Node, not a RefCounted like the components - it was never
	# added to the scene tree, so it needs an explicit free() or it leaks.
	registry.free()
	quit()
