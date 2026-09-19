class_name SkillsComponent
extends Component
## Tracks total earned XP per skill. Only skills the entity has actually
## trained appear here - no entity needs every skill pre-populated with
## zeroes (no entry and level 0 mean the same thing).
##
## Deliberate departure from other components: get_level() reaches into
## the SkillRegistry autoload to apply a skill's own XP curve, rather than
## requiring every caller to fetch the SkillDefinition itself first. The
## alternative keeps this component "purer" (no autoload dependency) but
## pushes friction onto what will be an extremely common lookup, for a
## consistency benefit that doesn't protect anything real - SkillDefinition
## is static content, not mutable game state, so reading it here doesn't
## put anything at risk the way writing to state would.

var xp: Dictionary = {}  # skill_id(String) -> total earned XP(int)


func get_xp(skill_id: String) -> int:
	return xp.get(skill_id, 0)


func get_level(skill_id: String) -> int:
	var definition: SkillDefinition = SkillRegistry.get_definition(skill_id)
	if definition == null:
		push_warning("SkillsComponent: unknown skill id '%s'" % skill_id)
		return 0
	return definition.level_for_xp(get_xp(skill_id))


## Adds XP to a skill, creating its entry on first use. Returns what
## changed so a caller (ProgressionSystem) can decide whether a level-up
## deserves its own narration event - this component doesn't emit
## anything itself, consistent with components being data, not signal
## sources (see ActionResolver's action_resolved for where that lives).
func add_xp(skill_id: String, amount: int) -> Dictionary:
	var old_level: int = get_level(skill_id)
	xp[skill_id] = get_xp(skill_id) + amount
	var new_level: int = get_level(skill_id)
	return {
		"skill_id": skill_id,
		"old_level": old_level,
		"new_level": new_level,
		"leveled_up": new_level > old_level,
	}


func serialize() -> Dictionary:
	return {"xp": xp.duplicate()}


func deserialize(data: Dictionary) -> void:
	xp = data.get("xp", {}).duplicate()
