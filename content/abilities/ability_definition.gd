class_name AbilityDefinition
extends Resource
## Data for one ability. Saved as .tres under content/abilities/ -
## AbilityRegistry auto-discovers every file there, same pattern as
## SkillRegistry. States its own unlock requirement rather than the skill
## listing what it unlocks - see TECHNICAL_DESIGN.md §8.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

## Unlock requirement: needs at least this level in ALL listed skills.
## {skill_id: required_level}. Empty means always available - not used by
## any test content yet, but keeps a future Move/Attack-style "no
## requirement" ability representable without a schema change.
@export var requirements: Dictionary = {}

## Skills this ability trains when used: {skill_id: xp_amount}, awarded to
## the actor by ProgressionSystem. Only needed for effects that don't
## already emit their own trainable event - dash/dash_toward call the
## real ActionResolver.resolve_move() internally, which already fires
## "moved" events ProgressionSystem awards XP for, so an ability that's
## ONLY movement (like Dash) needs no entry here or it'd double-count.
## deal_damage does NOT emit its own sub-event, so anything using it
## (Power Strike, Charging Strike) needs an explicit entry to train
## anything at all.
@export var trains: Dictionary = {}

## List of {type, ...params} dicts - see EffectLibrary for what each type
## does. Flat Dictionary shape rather than typed Resource subclasses per
## effect, deliberately, for authoring speed - revisit if it gets unwieldy.
@export var effects: Array[Dictionary] = []

## The id of the ability tier this one evolves from, or "" if this isn't
## part of an evolution chain (or is that chain's own base tier - a base
## tier leaves this empty; only the tier ABOVE it points back). A tier
## declares what it supersedes rather than the reverse (evolves_from
## here, not an "evolves_to" on the earlier tier), so adding a new tier
## on top later never requires editing the tier before it - same
## "adding content is purely additive" property this schema already has
## for ordinary unlock requirements. This is ability EVOLUTION, distinct
## from the (still undesigned) skill transcendence in TECHNICAL_DESIGN.md
## §8/DESIGN_PILLARS.md's Open items - a skill leveling up and becoming a
## different skill is a separate, bigger, not-yet-touched idea. See
## AbilityRegistry.get_active_tier() for how a chain is walked at runtime.
@export var evolves_from: String = ""


func meets_requirements(skills: SkillsComponent) -> bool:
	for skill_id: String in requirements:
		if skills.get_level(skill_id) < requirements[skill_id]:
			return false
	return true
