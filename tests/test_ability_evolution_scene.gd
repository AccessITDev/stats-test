extends Node
## Scene-based test for ability EVOLUTION (Wait -> Focus -> Meditate),
## AbilityDefinition.evolves_from, and AbilityRegistry.get_active_tier().
## This is deliberately a separate concept from skill transcendence
## (TECHNICAL_DESIGN.md §8/DESIGN_PILLARS.md's open items - a skill
## leveling up and becoming a different skill) - nothing here touches
## that; this is one ability's presentation and effects changing as a
## single skill (Patience) climbs, not a skill itself changing identity.
##
## Needs a scene, not a `-s` script - depends on AbilityRegistry,
## EntityRegistry, ActionResolver, and SkillRegistry, all autoloads (see
## CLAUDE.md's note on `-s` scripts skipping autoload init).
##
## Run via F6 with this scene open, or:
##   redot --headless --path . tests/test_ability_evolution_scene.tscn

func _ready() -> void:
	# --- Registry discovery: all three tiers auto-discovered ---
	assert(AbilityRegistry.has_definition("wait"), "wait.tres should have been auto-discovered")
	assert(AbilityRegistry.has_definition("focus"), "focus.tres should have been auto-discovered")
	assert(AbilityRegistry.has_definition("meditate"), "meditate.tres should have been auto-discovered")
	assert(SkillRegistry.has_definition("patience"), "patience.tres should have been auto-discovered")

	var actor_id: int = EntityRegistry.create_entity()
	var actor_skills := SkillsComponent.new()
	EntityRegistry.add_component(actor_id, actor_skills)

	# --- At 0 Patience, the chain resolves to its base tier ---
	assert(ActionResolver.can_use_ability(actor_id, "wait"), "wait should always be usable - it has no requirements")
	assert(not ActionResolver.can_use_ability(actor_id, "focus"), "focus shouldn't be usable yet - needs patience 3")
	assert(not ActionResolver.can_use_ability(actor_id, "meditate"), "meditate shouldn't be usable yet - needs patience 7")
	assert(AbilityRegistry.get_active_tier("wait", actor_skills) == "wait", "Active tier at 0 patience should be 'wait', got '%s'" % AbilityRegistry.get_active_tier("wait", actor_skills))

	# --- Using the base tier trains Patience and costs a real turn/event,
	# same as any other ability (resolve_ability -> ability_used) ---
	var wait_event: GameEvent = ActionResolver.resolve_ability(actor_id, "wait")
	assert(wait_event != null, "Resolving 'wait' should succeed")
	assert(wait_event.event_type == "ability_used", "wait should resolve as a normal ability_used event")
	assert(wait_event.data["ability_name"] == "Wait", "wait's event should carry its display name")
	assert(actor_skills.get_xp("patience") == 5, "Using Wait should train patience via trains (5 xp), got %d" % actor_skills.get_xp("patience"))

	# --- Crossing patience level 3 promotes the active tier to Focus ---
	actor_skills.xp["patience"] = 300  # level 3
	assert(ActionResolver.can_use_ability(actor_id, "focus"), "focus should now be unlocked at patience level 3")
	assert(AbilityRegistry.get_active_tier("wait", actor_skills) == "focus", "Active tier at patience 3 should be 'focus', got '%s'" % AbilityRegistry.get_active_tier("wait", actor_skills))
	assert(not ActionResolver.can_use_ability(actor_id, "meditate"), "meditate still shouldn't be usable - needs patience 7")

	var focus_event: GameEvent = ActionResolver.resolve_ability(actor_id, AbilityRegistry.get_active_tier("wait", actor_skills))
	assert(focus_event != null, "Resolving the active tier (focus) should succeed")
	assert(focus_event.data["ability_name"] == "Focus", "Active-tier resolution should have invoked Focus, not Wait, got '%s'" % focus_event.data["ability_name"])
	assert(actor_skills.get_xp("patience") == 308, "Focus should train patience via its own trains entry (300 + 8), got %d" % actor_skills.get_xp("patience"))

	# --- Crossing patience level 7 promotes the active tier to Meditate,
	# the deepest tier in the chain ---
	actor_skills.xp["patience"] = 700  # level 7
	assert(ActionResolver.can_use_ability(actor_id, "meditate"), "meditate should now be unlocked at patience level 7")
	assert(AbilityRegistry.get_active_tier("wait", actor_skills) == "meditate", "Active tier at patience 7 should be 'meditate', got '%s'" % AbilityRegistry.get_active_tier("wait", actor_skills))

	var meditate_event: GameEvent = ActionResolver.resolve_ability(actor_id, AbilityRegistry.get_active_tier("wait", actor_skills))
	assert(meditate_event != null, "Resolving the active tier (meditate) should succeed")
	assert(meditate_event.data["ability_name"] == "Meditate", "Active-tier resolution should have invoked Meditate, not an earlier tier, got '%s'" % meditate_event.data["ability_name"])
	assert(actor_skills.get_xp("patience") == 712, "Meditate should train patience via its own trains entry (700 + 12), got %d" % actor_skills.get_xp("patience"))

	# --- A null SkillsComponent (an entity with none at all) still
	# resolves to the chain's base tier rather than erroring -
	# get_active_tier() null-checks `skills` itself up front, since
	# AbilityDefinition.meets_requirements() has no such guard of its
	# own and would otherwise crash on the first gated tier. ---
	assert(AbilityRegistry.get_active_tier("wait", null) == "wait", "A null SkillsComponent should fall back to the base tier, not error")

	# --- None of this touches Move/Attack's time cost or narration paths -
	# a Wait/Focus/Meditate use is still just an ordinary ability_used
	# event under TurnScheduler.TIME_COSTS's flat ability cost. Confirms
	# the evolution feature is purely additive, not a special case
	# elsewhere in the pipeline. ---
	var before_time: int = TurnScheduler.get_elapsed_seconds()
	ActionResolver.resolve_ability(actor_id, "wait")
	assert(TurnScheduler.get_elapsed_seconds() == before_time + TurnScheduler.TIME_COSTS["ability_used"], "Wait should cost the same flat ability time as any other ability")

	print("Ability evolution smoke test: all assertions passed.")
	get_tree().quit()
