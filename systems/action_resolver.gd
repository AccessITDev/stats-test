extends Node
## Validates and resolves actions into state changes.
##
## Deliberately keeps validation and resolution together in one file for
## now rather than a separate ActionValidator class (see
## TECHNICAL_DESIGN.md §4/§5): nothing yet produces untrusted/free-text
## input that needs independent validation ahead of resolution. can_move()
## and can_attack() are still their own public functions so that split is
## easy to make later without reshuffling callers.
##
## Registered as the autoload singleton "ActionResolver" (see
## project.godot). Deliberately has no class_name, same reason as
## EntityRegistry.

## Fired after any action resolves, successful or not (only successes emit -
## a rejected action just returns false/null to its caller and never
## reaches here). Other systems (progression, narration) connect to this
## rather than ActionResolver knowing about them directly - see
## TECHNICAL_DESIGN.md's "signals over direct references" convention.
signal action_resolved(event: GameEvent)

enum Direction {UP, DOWN, LEFT, RIGHT}

const DIRECTION_OFFSETS: Dictionary = {
	Direction.UP: Vector2i(0, -1),
	Direction.DOWN: Vector2i(0, 1),
	Direction.LEFT: Vector2i(-1, 0),
	Direction.RIGHT: Vector2i(1, 0),
}


## True if entity_id can legally move one step in `direction` right now.
func can_move(entity_id: int, direction: Direction) -> bool:
	var pos: PositionComponent = EntityRegistry.get_component(entity_id, "PositionComponent")
	if pos == null:
		return false
	var target: Vector2i = pos.grid_position + DIRECTION_OFFSETS[direction]
	return Grid.is_within_bounds(target) and not Grid.is_occupied(target)


## Moves entity_id one step in `direction` if legal. Returns the resulting
## GameEvent, or null if the move was rejected (out of bounds or occupied) -
## the caller is expected to check this, not assume success.
func resolve_move(entity_id: int, direction: Direction) -> GameEvent:
	if not can_move(entity_id, direction):
		return null
	var pos: PositionComponent = EntityRegistry.get_component(entity_id, "PositionComponent")
	var from: Vector2i = pos.grid_position
	pos.grid_position += DIRECTION_OFFSETS[direction]

	var event := GameEvent.new("moved", {
		"actor_id": entity_id,
		"from": from,
		"to": pos.grid_position,
	})
	action_resolved.emit(event)
	return event


## True if entity_id can legally attack target_id right now: both must have
## the required components, the target must be alive, and they must be in
## cardinally adjacent cells (no diagonals, matching Move's directions).
func can_attack(entity_id: int, target_id: int) -> bool:
	var attacker_pos: PositionComponent = EntityRegistry.get_component(entity_id, "PositionComponent")
	var target_pos: PositionComponent = EntityRegistry.get_component(target_id, "PositionComponent")
	var target_stats: StatsComponent = EntityRegistry.get_component(target_id, "StatsComponent")

	if attacker_pos == null or target_pos == null or target_stats == null:
		return false
	if not target_stats.is_alive():
		return false

	var delta: Vector2i = target_pos.grid_position - attacker_pos.grid_position
	var is_cardinally_adjacent: bool = (abs(delta.x) + abs(delta.y)) == 1
	return is_cardinally_adjacent


## Resolves an attack from entity_id against target_id if legal. Damage is
## a flat equal to the attacker's power stat - no randomness, no defense
## stat yet, since the real combat formula is still open (see
## DESIGN_PILLARS.md). Returns the resulting GameEvent, or null if the
## attack was rejected. Also emits action_resolved with the same event.
##
## Known gap: a defeated entity (is_alive() == false) is left in place -
## nothing yet removes it from TurnScheduler's order or EntityRegistry.
## can_attack() already refuses to target a dead entity, so it can't be
## attacked twice, but it'll still get offered a turn until this is
## addressed. Related to TurnScheduler's existing "mid-round removal" gap.
func resolve_attack(entity_id: int, target_id: int) -> GameEvent:
	if not can_attack(entity_id, target_id):
		return null

	var attacker_stats: StatsComponent = EntityRegistry.get_component(entity_id, "StatsComponent")
	var target_stats: StatsComponent = EntityRegistry.get_component(target_id, "StatsComponent")

	var damage: int = attacker_stats.power
	target_stats.current_hp = max(0, target_stats.current_hp - damage)

	var event_type: String = "attack_defeated" if not target_stats.is_alive() else "attack_hit"
	var event := GameEvent.new(event_type, {
		"actor_id": entity_id,
		"target_id": target_id,
		"damage": damage,
		"target_remaining_hp": target_stats.current_hp,
	})

	action_resolved.emit(event)
	return event


## True if entity_id currently has ability_id unlocked - purely the skill
## requirement, not any per-effect precondition (like adjacency), since
## those vary per ability and some abilities (Charging Strike) are meant
## to be usable from a distance because an earlier effect closes it. See
## TECHNICAL_DESIGN.md §8: unlock status is derived live, never stored.
func can_use_ability(entity_id: int, ability_id: String) -> bool:
	var definition: AbilityDefinition = AbilityRegistry.get_definition(ability_id)
	if definition == null:
		return false
	var skills: SkillsComponent = EntityRegistry.get_component(entity_id, "SkillsComponent")
	if skills == null:
		return false
	return definition.meets_requirements(skills)


## Resolves using ability_id, running each of its effects in order via
## EffectLibrary. target_id/direction are passed through as context - not
## every ability needs both (Dash needs a direction, Power Strike needs a
## target, Charging Strike needs a target and computes its own direction).
## Returns the resulting GameEvent, or null if the ability isn't unlocked.
## Unlike Move/Attack, an unlocked ability can still "fizzle" (e.g. deal 0
## damage if a target turned out to be out of reach) without returning
## null - see EffectLibrary._deal_damage's out_of_reach case.
func resolve_ability(entity_id: int, ability_id: String, target_id: int = -1, direction: int = -1) -> GameEvent:
	if not can_use_ability(entity_id, ability_id):
		return null
	var definition: AbilityDefinition = AbilityRegistry.get_definition(ability_id)

	var combined_result: Dictionary = {}
	for effect: Dictionary in definition.effects:
		var context: Dictionary = {"actor_id": entity_id, "target_id": target_id, "direction": direction}
		var effect_result: Dictionary = EffectLibrary.execute(effect, context)
		combined_result.merge(effect_result, true)

	var event := GameEvent.new("ability_used", {
		"actor_id": entity_id,
		"target_id": target_id,
		"ability_id": ability_id,
		"ability_name": definition.display_name,
	})
	event.data.merge(combined_result, true)
	action_resolved.emit(event)
	return event
