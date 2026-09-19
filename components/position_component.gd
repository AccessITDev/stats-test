class_name PositionComponent
extends Component
## Where an entity sits on the grid, in grid cells - not pixels.
## Pixel/world conversion is the renderer's job, not this component's.

var grid_position: Vector2i = Vector2i.ZERO


func serialize() -> Dictionary:
	return {"x": grid_position.x, "y": grid_position.y}


func deserialize(data: Dictionary) -> void:
	grid_position = Vector2i(data.get("x", 0), data.get("y", 0))
