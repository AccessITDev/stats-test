class_name Component
extends RefCounted
## Base contract every component must follow.
##
## Components hold data plus, at most, minimal logic about that data.
## They must never reach into other entities directly - that's a system's
## job (see TECHNICAL_DESIGN.md §2). RefCounted, not Resource: components
## are runtime objects with a custom JSON serialization contract, not
## editor-facing assets.

## Set by EntityRegistry.add_component(). Do not set this manually.
var owner_entity_id: int = -1


## Returns a plain Dictionary suitable for JSON serialization.
## Every subclass must override this.
func serialize() -> Dictionary:
	push_error("serialize() not implemented for %s" % get_script().resource_path)
	return {}


## Restores this component's state from a Dictionary produced by serialize().
## Every subclass must override this.
func deserialize(_data: Dictionary) -> void:
	push_error("deserialize() not implemented for %s" % get_script().resource_path)
