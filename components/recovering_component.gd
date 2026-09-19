class_name RecoveringComponent
extends Component
## Temporary: while present, TurnScheduler skips this entity's turn.
## Attached by effects like Power Strike's follow-through cost, and
## automatically removed once turns_remaining reaches 0. First real use of
## "attach a temporary component as a turn-economy cost" - exactly what
## TurnTakerComponent.speed was left open for (see TECHNICAL_DESIGN.md §4,
## pillar #8).
##
## No stacking logic: attaching a second RecoveringComponent while one is
## already present just replaces it (EntityRegistry.add_component()
## overwrites by component type) rather than extending the duration.
## Not decided whether that's the right call long-term - not tested by
## anything that could trigger it yet.

var turns_remaining: int = 1


func serialize() -> Dictionary:
	return {"turns_remaining": turns_remaining}


func deserialize(data: Dictionary) -> void:
	turns_remaining = data.get("turns_remaining", 1)
