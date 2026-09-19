class_name ProceduralInterpreter
extends NarrativeInterpreter
## The non-LLM fallback narrator - see TECHNICAL_DESIGN.md §6. Template text
## with weighted variants per event type, no external calls, always
## available. interpret_free_text() is inherited unimplemented - the
## lightweight keyword parser described in TECHNICAL_DESIGN.md §6 comes
## later, once something actually produces free-text input to parse.

## event_type(String) -> Array[String] of templates. {token} placeholders
## are filled in from the event's data dictionary by _fill_template().
const TEMPLATES: Dictionary = {
	"moved": [
		"{actor} moves.",
		"{actor} steps aside.",
		"{actor} shifts position.",
	],
	"attack_hit": [
		"{actor} strikes {target} for {damage} damage.",
		"{actor} lands a hit on {target}, dealing {damage} damage.",
		"{target} is struck by {actor} for {damage} damage.",
	],
	"attack_defeated": [
		"{actor} strikes {target} down for {damage} damage.",
		"{target} falls to {actor}'s attack.",
	],
	"skill_leveled_up": [
		"{actor} reaches {skill} level {level}!",
		"{actor}'s {skill} grows to level {level}.",
	],
	"ability_used": [
		"{actor} uses {ability}!",
	],
}

## turn_skipped events need different wording per reason ("dead" vs
## "recovering"), which the flat TEMPLATES dict can't key on (it only
## keys by event_type). Kept separate rather than encoding the reason
## into the event_type itself (e.g. "turn_skipped_dead") to keep
## GameEvent's event_type values matching one concept each.
const TURN_SKIPPED_TEMPLATES: Dictionary = {
	"recovering": [
		"{actor} is still recovering and can't act!",
	],
	"dead": [
		"{actor} isn't able to act - they're down.",
	],
}


func narrate_event(event: GameEvent) -> String:
	var templates: Array
	if event.event_type == "turn_skipped":
		templates = TURN_SKIPPED_TEMPLATES.get(event.data.get("reason", ""), [])
	else:
		templates = TEMPLATES.get(event.event_type, [])

	if templates.is_empty():
		push_warning("No narration template for event type '%s' - using bland fallback." % event.event_type)
		return "Something happens."
	var template: String = templates[randi() % templates.size()]
	var result: String = _fill_template(template, event)
	if event.event_type == "ability_used":
		result += _describe_ability_outcome(event)
	return result


## Appends a short summary of what an ability actually did - damage,
## cells moved, whether a target was out of reach, healing/revival
## outcomes. Not every ability's base template mentions numbers (Dash
## doesn't deal damage; Power Strike doesn't move), and our template
## substitution can't gracefully handle a {token} that isn't present, so
## this is a separate step rather than more TEMPLATES entries.
func _describe_ability_outcome(event: GameEvent) -> String:
	var parts: Array[String] = []
	if event.data.get("out_of_reach", false):
		parts.append("out of reach")
	elif event.data.has("damage") and event.data["damage"] > 0:
		parts.append("%d damage" % event.data["damage"])
	if event.data.get("target_defeated", false):
		parts.append("defeated")
	if event.data.get("cells_moved", 0) > 0:
		parts.append("%d cell(s) closed" % event.data["cells_moved"])
	if event.data.has("healed") and event.data["healed"] > 0:
		parts.append("%d HP restored" % event.data["healed"])
	if event.data.get("target_dead", false):
		parts.append("target is dead, can't be healed")
	if event.data.get("revived", false):
		parts.append("revived with %d HP" % event.data.get("hp_restored", 0))
	if event.data.get("target_already_alive", false):
		parts.append("target is already alive")
	if parts.is_empty():
		return ""
	return " (%s)" % ", ".join(parts)


func is_available() -> bool:
	return true  # no external dependency - never unavailable


func _fill_template(template: String, event: GameEvent) -> String:
	var result: String = template
	if event.data.has("actor_id"):
		result = result.replace("{actor}", _entity_label(event.data["actor_id"]))
	elif event.data.has("entity_id"):
		result = result.replace("{actor}", _entity_label(event.data["entity_id"]))
	if event.data.has("target_id"):
		result = result.replace("{target}", _entity_label(event.data["target_id"]))
	if event.data.has("damage"):
		result = result.replace("{damage}", str(event.data["damage"]))
	if event.data.has("skill_name"):
		result = result.replace("{skill}", event.data["skill_name"])
	if event.data.has("new_level"):
		result = result.replace("{level}", str(event.data["new_level"]))
	if event.data.has("ability_name"):
		result = result.replace("{ability}", event.data["ability_name"])
	return result


## Placeholder labeling - real names/descriptions are an open question (see
## DESIGN_PILLARS.md). For now, entities are just labeled by id.
func _entity_label(entity_id: int) -> String:
	return "Entity %d" % entity_id
