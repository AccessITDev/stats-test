extends Node
## Grid bounds + occupancy queries. Deliberately holds no position state of
## its own - PositionComponent is the only source of truth for where an
## entity is (CLAUDE.md principle #1: the state database is the only
## source of truth). Occupancy is derived by querying EntityRegistry each
## time rather than caching it, since a second copy of "where things are"
## is exactly the kind of two-sources-of-truth bug this architecture is
## built to avoid. Fine at this scale (a handful of entities on a 5x5
## grid) - revisit only if profiling ever says otherwise.
##
## Registered as the autoload singleton "Grid" (see project.godot).
## Deliberately has no class_name, same reason as EntityRegistry.

const WIDTH: int = 5
const HEIGHT: int = 5


func is_within_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT


## Returns the entity id occupying `cell`, or -1 if empty. Scans every
## entity with a PositionComponent - see the class comment on why this
## isn't cached.
func get_entity_at(cell: Vector2i) -> int:
	var query: Array[String] = ["PositionComponent"]
	for entity_id: int in EntityRegistry.get_entities_with(query):
		var pos: PositionComponent = EntityRegistry.get_component(entity_id, "PositionComponent")
		if pos.grid_position == cell:
			return entity_id
	return -1


func is_occupied(cell: Vector2i) -> bool:
	return get_entity_at(cell) != -1
