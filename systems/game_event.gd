class_name GameEvent
extends RefCounted
## A record of something that happened, for systems (ProgressionSystem,
## NarrativeInterpreter, ...) to react to after the fact. Deliberately
## generic - a type tag plus a flat data dictionary - rather than a rigid
## per-event-type class hierarchy, since the exact fields needed per event
## type are still being discovered (see DESIGN_PILLARS.md).

var event_type: String
var data: Dictionary


func _init(p_event_type: String, p_data: Dictionary = {}) -> void:
	event_type = p_event_type
	data = p_data
