extends Node
## Turn scheduling system. Snapshots every TurnTakerComponent-bearing
## entity into a fixed order at the start of a round and steps through
## them one at a time, ordered by speed (see start_round()). Still just
## one turn per entity per round - speed determining *how many* actions
## an entity gets (pillar #8's eventual goal) is a separate, bigger step
## on top of this, not done here.
##
## Also owns the elapsed in-fiction time tracker from
## TECHNICAL_DESIGN.md §9 (TIME_COSTS / get_elapsed_seconds /
## reset_elapsed_time, below). Living here rather than a separate
## autoload because turns are exactly what the clock measures; nothing
## outside this file reads the total yet, on purpose - see those
## functions' comments.
##
## Registered as the autoload singleton "TurnScheduler" (see
## project.godot). Deliberately has no class_name, same reason as
## EntityRegistry: Redot doesn't allow a class_name and an autoload of
## the same name together.

## Fired whenever an entity's turn is skipped (recovering or dead), so it
## can be telegraphed to the player instead of silently vanishing. This
## exists specifically because a silent skip was confusing in practice -
## see DESIGN_PILLARS.md's note on telegraphing.
signal turn_skipped(event: GameEvent)

## Seconds of in-fiction time charged per ActionResolver.action_resolved
## event type - the concrete numbers behind TECHNICAL_DESIGN.md §9's
## "each turn costs 1-3 seconds depending on the action." Move and
## Attack match that doc's already-committed "moving and most
## tactical-grid actions cost 1 second." Abilities don't have a
## committed cost there yet - 2 seconds here is a reasoned placeholder
## (inside the documented range, and distinct from the baseline so the
## counter actually proves it can vary by type), not a locked decision.
##
## Flat per event_type, not per-ability - one real consequence worth
## naming: Dash/Charging Strike call ActionResolver.resolve_move()
## internally per cell (see EffectLibrary._dash's comment), so each cell
## already adds its own "moved" second on top of the ability's own
## "ability_used" cost - a 4-cell Dash costs 4 + 2 = 6 seconds this way,
## not a flat 2. Not treated as a bug: unlike the identically-shaped
## athletics-XP double-count question the same code already avoids via
## an empty `trains`, charging for real distance covered seems like the
## right call for a time budget, not a wrong one - but naming it here as
## a real decision, not an oversight.
const TIME_COSTS: Dictionary = {
	"moved": 1,
	"attack_hit": 1,
	"attack_defeated": 1,
	"ability_used": 2,
}

var _turn_order: Array[int] = []
var _current_index: int = -1

## Total in-fiction seconds elapsed from resolved actions since the last
## reset_elapsed_time() call. Deliberately wired to nothing yet - no
## generation length, no game-over, no consequence at all. This is the
## smallest possible slice of TECHNICAL_DESIGN.md §9: prove the clock
## itself accumulates correctly through real play before anything is
## allowed to depend on it.
var _elapsed_seconds: int = 0


## Connects to ActionResolver so every resolved action is charged
## automatically - same "signals over direct references" convention as
## ProgressionSystem's identical connection to the same signal (see
## CLAUDE.md's Coding Conventions). Also the first place in the project
## where one autoload's _ready() depends on another autoload already
## existing: Redot instantiates autoloads in project.godot's listed
## order and calls each one's _ready() before the next is even created,
## so this only works because ActionResolver was moved ahead of
## TurnScheduler in that list specifically for this change (see
## project.godot and CLAUDE.md's Working Process). ProgressionSystem
## could already assume that ordering safely; TurnScheduler couldn't,
## until now.
func _ready() -> void:
	ActionResolver.action_resolved.connect(_on_action_resolved)


func _on_action_resolved(event: GameEvent) -> void:
	_elapsed_seconds += TIME_COSTS.get(event.event_type, 0)


func get_elapsed_seconds() -> int:
	return _elapsed_seconds


## Zeroes the clock. Deliberately not folded into start_round(): that's
## called every time the turn order wraps (continuously during ordinary
## play, once per lap through all turn-takers), not just when a new game
## actually begins - tying the reset to it would silently zero the clock
## every round instead of only on a real restart. main.gd's restart flow
## calls this explicitly, alongside EntityRegistry.clear_all().
func reset_elapsed_time() -> void:
	_elapsed_seconds = 0


## Builds a fresh turn order from every entity currently holding a
## TurnTakerComponent. Call this to (re)start a round. Ordered by speed,
## descending - highest speed acts first. Ties fall back to ascending
## entity id, purely for determinism; it isn't a game rule.
func start_round() -> void:
	var query: Array[String] = ["TurnTakerComponent"]
	_turn_order = EntityRegistry.get_entities_with(query)
	_turn_order.sort_custom(_compare_by_speed)
	_current_index = 0 if not _turn_order.is_empty() else -1


func _compare_by_speed(a: int, b: int) -> bool:
	var speed_a: int = _get_speed(a)
	var speed_b: int = _get_speed(b)
	if speed_a != speed_b:
		return speed_a > speed_b
	return a < b


func _get_speed(entity_id: int) -> int:
	var turn_taker: TurnTakerComponent = EntityRegistry.get_component(entity_id, "TurnTakerComponent")
	return turn_taker.speed if turn_taker != null else 1


## Returns the entity whose turn it currently is, or -1 if no round is
## active (start_round() hasn't run yet, or found no turn-takers).
func get_active_entity() -> int:
	if _current_index < 0 or _current_index >= _turn_order.size():
		return -1
	return _turn_order[_current_index]


## Advances to the next entity in the current order. Wraps into a fresh
## round (re-querying EntityRegistry, so entities created/destroyed since
## the last round get picked up) once the order is exhausted. Then skips
## past any entity that's ineligible to act right now (dead, recovering).
func advance_turn() -> void:
	if _turn_order.is_empty():
		start_round()
	else:
		_current_index += 1
		if _current_index >= _turn_order.size():
			start_round()
	_skip_ineligible_entities()


## Skips any entity that's dead or still recovering, emitting
## turn_skipped for each one so it can be narrated rather than silently
## disappearing.
##
## Known gap: if every entity in the turn order were ineligible at once,
## this loops until the safety cap below trips and just gives up rather
## than resolving the deadlock somehow. Can't happen with current content
## (never more than one dead entity and one recovering entity at a time
## in a 2-entity scene) - revisit if that changes.
func _skip_ineligible_entities() -> void:
	var safety_cap: int = _turn_order.size() + 1
	while safety_cap > 0:
		var active_id: int = get_active_entity()
		if active_id == -1:
			return
		var skip_reason: String = _consume_skip_if_ineligible(active_id)
		if skip_reason == "":
			return  # eligible - done skipping
		turn_skipped.emit(GameEvent.new("turn_skipped", {"entity_id": active_id, "reason": skip_reason}))
		_current_index += 1
		if _current_index >= _turn_order.size():
			start_round()
		safety_cap -= 1


## Returns why active_id's turn should be skipped ("dead"/"recovering"),
## or "" if it shouldn't be skipped. Also applies the side effect that
## goes with a recovering skip (decrementing/clearing
## RecoveringComponent) - slightly more than a pure query, but keeping
## the check and its side effect together avoids a second pass over the
## same component.
func _consume_skip_if_ineligible(entity_id: int) -> String:
	var stats: StatsComponent = EntityRegistry.get_component(entity_id, "StatsComponent")
	if stats != null and not stats.is_alive():
		return "dead"

	var recovering: RecoveringComponent = EntityRegistry.get_component(entity_id, "RecoveringComponent")
	if recovering != null:
		recovering.turns_remaining -= 1
		if recovering.turns_remaining <= 0:
			EntityRegistry.remove_component(entity_id, "RecoveringComponent")
		return "recovering"

	return ""


func is_active_entity(entity_id: int) -> bool:
	return get_active_entity() == entity_id
