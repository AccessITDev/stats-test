class_name StatsComponent
extends Component
## Core stats every actor-like entity has. Deliberately minimal - one
## attribute is enough to prove the loop. The real attribute/skill schema
## is still open (see DESIGN_PILLARS.md, Open for Experimentation); don't
## treat this shape as final.

var max_hp: int = 10
var current_hp: int = 10
var power: int = 1  ## Used for damage calculation for now.


func is_alive() -> bool:
	return current_hp > 0


func serialize() -> Dictionary:
	return {
		"max_hp": max_hp,
		"current_hp": current_hp,
		"power": power,
	}


func deserialize(data: Dictionary) -> void:
	max_hp = data.get("max_hp", 10)
	current_hp = data.get("current_hp", max_hp)
	power = data.get("power", 1)
