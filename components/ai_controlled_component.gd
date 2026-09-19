class_name AIControlledComponent
extends Component
## Marker only, for the same reason as PlayerControlledComponent. The
## "attack if adjacent, else move closer" behavior for this slice will
## live in a system, not here - see the vertical slice plan's later steps.
## Only add fields (e.g. a behavior type) once a second AI behavior
## actually exists to justify the branch.


func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass
