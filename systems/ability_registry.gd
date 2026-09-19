extends Node
## Loads and indexes every AbilityDefinition found under
## content/abilities/. Same auto-discovery pattern as SkillRegistry.
##
## Registered as the autoload singleton "AbilityRegistry". Deliberately
## has no class_name, same reason as the other autoloads.

const ABILITIES_PATH: String = "res://content/abilities/"

var _definitions: Dictionary = {}  # ability_id(String) -> AbilityDefinition


func _ready() -> void:
	load_all_definitions()


func load_all_definitions() -> void:
	_definitions.clear()
	var dir := DirAccess.open(ABILITIES_PATH)
	if dir == null:
		push_error("AbilityRegistry: could not open %s" % ABILITIES_PATH)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var definition: AbilityDefinition = load(ABILITIES_PATH + file_name)
			if definition == null:
				push_warning("AbilityRegistry: failed to load %s" % file_name)
			elif _definitions.has(definition.id):
				push_error("AbilityRegistry: duplicate ability id '%s' (from %s)" % [definition.id, file_name])
			else:
				_definitions[definition.id] = definition
		file_name = dir.get_next()
	dir.list_dir_end()


func get_definition(ability_id: String) -> AbilityDefinition:
	return _definitions.get(ability_id)


func has_definition(ability_id: String) -> bool:
	return _definitions.has(ability_id)


func get_all_ids() -> Array:
	return _definitions.keys()


## All ability ids currently unlocked for this SkillsComponent. Derived
## live from current skill levels vs. each definition's requirements -
## never stored - see TECHNICAL_DESIGN.md §8 and its noted performance
## caveat (fine at this content scale, revisit if that changes).
func get_unlocked_ids(skills: SkillsComponent) -> Array[String]:
	var unlocked: Array[String] = []
	for ability_id: String in _definitions:
		if _definitions[ability_id].meets_requirements(skills):
			unlocked.append(ability_id)
	return unlocked
