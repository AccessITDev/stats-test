extends Node
## The ONLY thing allowed to create/destroy entities or attach/detach
## components. Other systems query this fresh every turn/tick rather than
## holding entity references between calls - see TECHNICAL_DESIGN.md §2.
##
## Registered as the autoload singleton named "EntityRegistry" (see
## project.godot) - game code just calls EntityRegistry.create_entity(), etc.
## Deliberately has no class_name: Redot/Godot doesn't allow a script to
## declare a class_name and be autoloaded under that same name. Tests that
## want a fresh, isolated instance load the script directly instead:
## load("res://systems/entity_registry.gd").new()

## Monotonically increasing id counter. Entity ids are never reused.
var _next_entity_id: int = 0

## { entity_id(int): { component_type_name(String): Component } }
var _entities: Dictionary = {}

## Reverse index for fast get_entities_with() queries.
## { component_type_name(String): { entity_id(int): true } }
var _component_index: Dictionary = {}


func create_entity() -> int:
	var id: int = _next_entity_id
	_next_entity_id += 1
	_entities[id] = {}
	return id


func destroy_entity(entity_id: int) -> void:
	if not _entities.has(entity_id):
		push_warning("destroy_entity called on unknown entity_id %d" % entity_id)
		return
	for component_type: String in _entities[entity_id].keys():
		_component_index[component_type].erase(entity_id)
	_entities.erase(entity_id)


func entity_exists(entity_id: int) -> bool:
	return _entities.has(entity_id)


## Destroys every entity and clears all component indices. Deliberately
## does NOT reset the id counter: if it did, a restarted entity could get
## the exact same id as one from before the reset, and any stale
## reference held somewhere to the old entity would silently keep
## "working" by coincidence instead of failing loudly. For full resets
## (restarting after game over) - clears the whole registry rather than
## requiring the caller to track every entity id that might need
## destroying individually.
func clear_all() -> void:
	_entities.clear()
	_component_index.clear()


func add_component(entity_id: int, component: Component) -> void:
	if not _entities.has(entity_id):
		push_error("add_component called on unknown entity_id %d" % entity_id)
		return
	var component_type: String = component.get_script().get_global_name()
	component.owner_entity_id = entity_id
	_entities[entity_id][component_type] = component
	if not _component_index.has(component_type):
		_component_index[component_type] = {}
	_component_index[component_type][entity_id] = true


func remove_component(entity_id: int, component_type: String) -> void:
	if not _entities.has(entity_id):
		return
	_entities[entity_id].erase(component_type)
	if _component_index.has(component_type):
		_component_index[component_type].erase(entity_id)


func get_component(entity_id: int, component_type: String) -> Component:
	if not _entities.has(entity_id):
		return null
	return _entities[entity_id].get(component_type)


func has_component(entity_id: int, component_type: String) -> bool:
	return _entities.has(entity_id) and _entities[entity_id].has(component_type)


## Returns entity ids that have ALL of the given component types.
func get_entities_with(component_types: Array[String]) -> Array[int]:
	if component_types.is_empty():
		return []

	# Start the intersection from whichever type currently has the fewest
	# entities, so the common case (rare component, many entities) stays cheap.
	var smallest_type: String = component_types[0]
	var smallest_size: int = _component_index.get(smallest_type, {}).size()
	for component_type: String in component_types:
		var size: int = _component_index.get(component_type, {}).size()
		if size < smallest_size:
			smallest_type = component_type
			smallest_size = size

	var result: Array[int] = []
	for entity_id: int in _component_index.get(smallest_type, {}).keys():
		var has_all: bool = true
		for component_type: String in component_types:
			if not _component_index.get(component_type, {}).has(entity_id):
				has_all = false
				break
		if has_all:
			result.append(entity_id)
	return result
