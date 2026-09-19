class_name PlayerControlledComponent
extends Component
## Marker only, deliberately empty. Its presence is what will tell the
## turn/input system (not yet built) that this entity's actions come from
## UI input rather than AI. Per DESIGN_PILLARS.md's "only then generalize" -
## no fields exist because nothing has needed one yet.


func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass
