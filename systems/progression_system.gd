extends Node
## Listens to ActionResolver.action_resolved and awards skill XP based on
## what happened. Owns the event-type -> skill mapping for Move/Attack
## itself, so ActionResolver stays focused on mechanical resolution and
## never needs to know which skills exist or what trains them. Abilities
## are different: "ability_used" events consult the ability's own `trains`
## field (via AbilityRegistry) instead of this table, since deal_damage
## and other effects don't emit their own trainable sub-events the way
## resolve_attack does - see AbilityDefinition.trains and
## EffectLibrary._deal_damage's comment.
##
## Registered as the autoload singleton "ProgressionSystem". Deliberately
## has no class_name, same reason as the other autoloads.

## Fired whenever a skill crosses a level threshold. Its own signal, not a
## reuse of ActionResolver.action_resolved - this is a downstream
## consequence of an action, not the action's own resolution.
signal skill_leveled_up(event: GameEvent)

## event_type(String) -> Array of {skill_id, amount, recipient} rules.
## recipient is "actor" or "target" - which side of the event gets the XP
## (most skills train the actor, but something like poison resistance
## would need "target" once it exists). Deliberately just a placeholder
## mapping for Move/Attack - the real content (which actions train which
## skills, and how much) is wide open, see DESIGN_PILLARS.md. Does NOT
## include "ability_used" - see the class comment.
const XP_RULES: Dictionary = {
	"moved": [
		{"skill_id": "athletics", "amount": 5, "recipient": "actor"},
	],
	"attack_hit": [
		{"skill_id": "melee_combat", "amount": 10, "recipient": "actor"},
	],
	"attack_defeated": [
		{"skill_id": "melee_combat", "amount": 25, "recipient": "actor"},
	],
}


func _ready() -> void:
	ActionResolver.action_resolved.connect(_on_action_resolved)


func _on_action_resolved(event: GameEvent) -> void:
	if event.event_type == "ability_used":
		_apply_ability_training(event)
		return

	for rule: Dictionary in XP_RULES.get(event.event_type, []):
		var recipient_key: String = "actor_id" if rule.recipient == "actor" else "target_id"
		if not event.data.has(recipient_key):
			continue
		var entity_id: int = event.data[recipient_key]
		var skills: SkillsComponent = EntityRegistry.get_component(entity_id, "SkillsComponent")
		if skills == null:
			continue  # this entity doesn't track skills - nothing to do
		_award_xp(entity_id, skills, rule.skill_id, rule.amount)


func _apply_ability_training(event: GameEvent) -> void:
	var definition: AbilityDefinition = AbilityRegistry.get_definition(event.data.get("ability_id", ""))
	if definition == null or definition.trains.is_empty():
		return
	var actor_id: int = event.data.get("actor_id", -1)
	if actor_id == -1:
		return
	var skills: SkillsComponent = EntityRegistry.get_component(actor_id, "SkillsComponent")
	if skills == null:
		return
	for skill_id: String in definition.trains:
		_award_xp(actor_id, skills, skill_id, definition.trains[skill_id])


## Shared by both XP paths above: adds the XP, and emits skill_leveled_up
## if it crossed a threshold. Extracted so level-up detection/emission
## isn't duplicated between the Move/Attack path and the ability path.
func _award_xp(entity_id: int, skills: SkillsComponent, skill_id: String, amount: int) -> void:
	var result: Dictionary = skills.add_xp(skill_id, amount)
	if not result.leveled_up:
		return
	var definition: SkillDefinition = SkillRegistry.get_definition(skill_id)
	var skill_name: String = definition.display_name if definition != null else skill_id
	var level_event := GameEvent.new("skill_leveled_up", {
		"entity_id": entity_id,
		"skill_id": skill_id,
		"skill_name": skill_name,
		"old_level": result.old_level,
		"new_level": result.new_level,
	})
	skill_leveled_up.emit(level_event)
