class_name TurnTakerComponent
extends Component
## Marks an entity as participating in turn order. `speed` will drive
## initiative/extra-turn scheduling once TurnScheduler exists (see
## TECHNICAL_DESIGN.md §4 and pillar #8) - the actual formula is still
## open, so for this slice every entity just carries the default and
## the scheduler alternates them in a simple queue.

var speed: int = 1


func serialize() -> Dictionary:
	return {"speed": speed}


func deserialize(data: Dictionary) -> void:
	speed = data.get("speed", 1)
