extends Node
## Loads and indexes every SkillDefinition found under content/skills/.
## Adding a new skill is just dropping a new .tres file in that folder -
## no code change needed here.
##
## load_all_definitions() is public (not just called from _ready())
## deliberately: a manually-instantiated node's _ready() only fires once
## it's added to a live scene tree, which would force every test to be
## scene-based. Calling this directly lets isolated tests skip that.
##
## Registered as the autoload singleton "SkillRegistry". Deliberately has
## no class_name, same reason as the other autoloads.

const SKILLS_PATH: String = "res://content/skills/"

var _definitions: Dictionary = {}  # skill_id(String) -> SkillDefinition


func _ready() -> void:
	load_all_definitions()


func load_all_definitions() -> void:
	_definitions.clear()
	var dir := DirAccess.open(SKILLS_PATH)
	if dir == null:
		push_error("SkillRegistry: could not open %s" % SKILLS_PATH)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var definition: SkillDefinition = load(SKILLS_PATH + file_name)
			if definition == null:
				push_warning("SkillRegistry: failed to load %s" % file_name)
			elif _definitions.has(definition.id):
				push_error("SkillRegistry: duplicate skill id '%s' (from %s)" % [definition.id, file_name])
			else:
				_definitions[definition.id] = definition
		file_name = dir.get_next()
	dir.list_dir_end()


func get_definition(skill_id: String) -> SkillDefinition:
	return _definitions.get(skill_id)


func has_definition(skill_id: String) -> bool:
	return _definitions.has(skill_id)


func get_all_ids() -> Array:
	return _definitions.keys()
