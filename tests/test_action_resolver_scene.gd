extends Node
## Scene-based test for Grid + ActionResolver (Move only, per step 4 scope).
## Needs to be a scene test, not a `-s` script - both are autoloads that
## reference each other and EntityRegistry (see CLAUDE.md's note on -s
## scripts skipping autoload init).
##
## Run via F6 with this scene open, or:
##   redot --headless --path . tests/test_action_resolver_scene.tscn

func _ready() -> void:
	var entity_a: int = EntityRegistry.create_entity()
	var pos_a := PositionComponent.new()
	pos_a.grid_position = Vector2i(2, 2)
	EntityRegistry.add_component(entity_a, pos_a)

	var entity_b: int = EntityRegistry.create_entity()
	var pos_b := PositionComponent.new()
	pos_b.grid_position = Vector2i(3, 2)
	EntityRegistry.add_component(entity_b, pos_b)

	# --- Grid bounds ---
	assert(Grid.is_within_bounds(Vector2i(0, 0)), "(0,0) should be in bounds")
	assert(Grid.is_within_bounds(Vector2i(4, 4)), "(4,4) should be in bounds on a 5x5 grid, 0-indexed")
	assert(not Grid.is_within_bounds(Vector2i(5, 0)), "(5,0) should be out of bounds")
	assert(not Grid.is_within_bounds(Vector2i(-1, 0)), "(-1,0) should be out of bounds")

	# --- Grid occupancy (derived live from PositionComponent, see grid.gd) ---
	assert(Grid.get_entity_at(Vector2i(2, 2)) == entity_a, "entity_a should occupy (2,2)")
	assert(Grid.get_entity_at(Vector2i(3, 2)) == entity_b, "entity_b should occupy (3,2)")
	assert(Grid.get_entity_at(Vector2i(0, 0)) == -1, "Empty cell should return -1")
	assert(not Grid.is_occupied(Vector2i(0, 0)), "Empty cell should not be occupied")
	assert(Grid.is_occupied(Vector2i(2, 2)), "entity_a's cell should be occupied")

	# --- ActionResolver.can_move ---
	assert(ActionResolver.can_move(entity_a, ActionResolver.Direction.UP), "Moving up from (2,2) to (2,1) should be legal")
	assert(not ActionResolver.can_move(entity_a, ActionResolver.Direction.RIGHT), "Moving right into entity_b at (3,2) should be illegal")

	var edge_entity: int = EntityRegistry.create_entity()
	var edge_pos := PositionComponent.new()
	edge_pos.grid_position = Vector2i(0, 0)
	EntityRegistry.add_component(edge_entity, edge_pos)
	assert(not ActionResolver.can_move(edge_entity, ActionResolver.Direction.LEFT), "Moving left off the grid from (0,0) should be illegal")
	assert(not ActionResolver.can_move(edge_entity, ActionResolver.Direction.UP), "Moving up off the grid from (0,0) should be illegal")

	# --- ActionResolver.resolve_move ---
	var moved_up: GameEvent = ActionResolver.resolve_move(entity_a, ActionResolver.Direction.UP)
	assert(moved_up != null, "resolve_move should report success for a legal move")
	assert(pos_a.grid_position == Vector2i(2, 1), "entity_a should now be at (2,1)")

	var moved_back: GameEvent = ActionResolver.resolve_move(entity_a, ActionResolver.Direction.DOWN)
	assert(moved_back != null, "Moving back into the now-empty (2,2) should succeed")
	assert(pos_a.grid_position == Vector2i(2, 2), "entity_a should be back at (2,2)")

	var illegal_move: GameEvent = ActionResolver.resolve_move(entity_a, ActionResolver.Direction.RIGHT)
	assert(illegal_move == null, "Moving into entity_b's occupied cell should fail")
	assert(pos_a.grid_position == Vector2i(2, 2), "entity_a's position should be unchanged after a failed move")

	print("Grid + ActionResolver (Move) smoke test: all assertions passed.")
	get_tree().quit()
