class_name NarrativeInterpreter
extends RefCounted
## Base contract both LLMInterpreter (not built yet) and ProceduralInterpreter
## follow - see TECHNICAL_DESIGN.md §5.
##
## interpret_free_text() isn't implemented by anything yet, since nothing in
## the game produces free-text input yet - it's declared here so the
## interface shape matches the design doc, not because it's tested today.
## Returns a plain Dictionary rather than a proper ActionIntent type, since
## that type doesn't exist until free-text input is actually being built.

func narrate_event(event: GameEvent) -> String:
	push_error("narrate_event() not implemented for %s" % get_script().resource_path)
	return ""


func interpret_free_text(_text: String, _valid_actions: Array) -> Dictionary:
	push_error("interpret_free_text() not implemented for %s" % get_script().resource_path)
	return {}


func is_available() -> bool:
	return false
