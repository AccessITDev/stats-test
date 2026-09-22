extends Node
## Loads and indexes every AbilityDefinition found under
## content/abilities/. Same auto-discovery pattern as SkillRegistry.
##
## Registered as the autoload singleton "AbilityRegistry". Deliberately
## has no class_name, same reason as the other autoloads.

const ABILITIES_PATH: String = "res://content/abilities/"

var _definitions: Dictionary = {}  # ability_id(String) -> AbilityDefinition

## Reverse index built from every definition's `evolves_from`:
## base_tier_id(String) -> next_tier_id(String). Built once per
## load_all_definitions() call, same "derive it, don't hand-maintain it
## in two places" reasoning as everything else in this registry - a base
## tier never lists what it evolves into, so this is the only place that
## knows the forward direction.
var _evolution_next: Dictionary = {}


func _ready() -> void:
	load_all_definitions()


func load_all_definitions() -> void:
	_definitions.clear()
	_evolution_next.clear()
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

	_build_evolution_map()


## Separate pass, not folded into the load loop above: `evolves_from`
## points backward to an id that might not have been loaded yet
## depending on directory iteration order, so every definition needs to
## already be in `_definitions` before any of them can be cross-checked.
func _build_evolution_map() -> void:
	for ability_id: String in _definitions:
		var definition: AbilityDefinition = _definitions[ability_id]
		if definition.evolves_from == "":
			continue
		if not _definitions.has(definition.evolves_from):
			push_error("AbilityRegistry: '%s' evolves_from unknown ability '%s'" % [ability_id, definition.evolves_from])
			continue
		if _evolution_next.has(definition.evolves_from):
			push_error("AbilityRegistry: '%s' already evolves into '%s' - '%s' can't also claim it" % [definition.evolves_from, _evolution_next[definition.evolves_from], ability_id])
			continue
		_evolution_next[definition.evolves_from] = ability_id


func get_definition(ability_id: String) -> AbilityDefinition:
	return _definitions.get(ability_id)


func has_definition(ability_id: String) -> bool:
	return _definitions.has(ability_id)


func get_all_ids() -> Array:
	return _definitions.keys()


## Walks forward from `base_id` through its evolution chain (via
## `evolves_from`), returning the id of the DEEPEST tier whose
## requirements are currently met by `skills`. Stops and falls back one
## step the moment a tier's requirements aren't met - so a chain always
## resolves to exactly one currently-valid id, never skipping over a
## locked middle tier to a technically-also-qualifying one further out.
## `base_id` itself is returned if it has no evolution chain, or if
## `skills` doesn't even meet the base tier's own requirements (e.g. a
## chain built on a gated ability rather than an always-available one
## like Wait) - this is a display/dispatch helper, not a second
## `can_use_ability` check, so callers still gate on the real unlock
## status themselves before invoking whatever id this returns.
##
## Built for exactly the "one evolving button" case (main.gd's Wait
## button becoming Focus, then Meditate) - callers get back a single id
## to both label and pass to ActionResolver.resolve_ability(), no matter
## how far the underlying skill has progressed.
##
## Null-checks `skills` itself (unlike `get_unlocked_ids` below, which
## assumes a non-null caller the same way `can_use_ability` does) -
## `AbilityDefinition.meets_requirements` has no null-guard of its own,
## and an entity with no SkillsComponent at all should fall back to
## `base_id` rather than crash.
func get_active_tier(base_id: String, skills: SkillsComponent) -> String:
	if skills == null:
		return base_id
	var current_id: String = base_id
	while _evolution_next.has(current_id):
		var next_id: String = _evolution_next[current_id]
		var next_definition: AbilityDefinition = _definitions.get(next_id)
		if next_definition == null or not next_definition.meets_requirements(skills):
			break
		current_id = next_id
	return current_id


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
