extends Node
## The pre-coded vocabulary of ability effects. AbilityDefinitions
## reference these by "type" - see TECHNICAL_DESIGN.md §8. A new ability
## built from an EXISTING type is pure data; a genuinely new mechanical
## behavior needs a new case here.
##
## Registered as the autoload singleton "EffectLibrary". Deliberately has
## no class_name, same reason as the other autoloads.

## Executes one effect spec against a context ({actor_id, target_id,
## direction} - not every effect needs all three). Returns a Dictionary
## describing what happened, merged into the ability's GameEvent by the
## caller (ActionResolver.resolve_ability). Returns {} if the type is
## unknown or required context is missing.
func execute(effect: Dictionary, context: Dictionary) -> Dictionary:
	match effect.get("type", ""):
		"deal_damage":
			return _deal_damage(effect, context)
		"dash":
			return _dash(effect, context)
		"dash_toward":
			return _dash_toward(effect, context)
		"apply_recovery":
			return _apply_recovery(effect, context)
		"heal":
			return _heal(effect, context)
		"revive":
			return _revive(effect, context)
		_:
			push_warning("EffectLibrary: unknown effect type '%s'" % effect.get("type", "<missing>"))
			return {}


## Deals damage equal to the actor's power stat times a multiplier.
## Checks adjacency itself (reusing ActionResolver.can_attack, which also
## covers the target being alive) rather than assuming the caller already
## validated range - a multi-effect ability like Charging Strike closes
## distance in an earlier effect, so range can't be checked once upfront
## for the whole ability.
func _deal_damage(effect: Dictionary, context: Dictionary) -> Dictionary:
	var actor_id: int = context.get("actor_id", -1)
	var target_id: int = context.get("target_id", -1)
	if actor_id == -1 or target_id == -1:
		return {}
	if effect.get("requires_adjacency", true) and not ActionResolver.can_attack(actor_id, target_id):
		return {"damage": 0, "out_of_reach": true}

	var attacker_stats: StatsComponent = EntityRegistry.get_component(actor_id, "StatsComponent")
	var target_stats: StatsComponent = EntityRegistry.get_component(target_id, "StatsComponent")
	if attacker_stats == null or target_stats == null:
		return {}
	var multiplier: float = effect.get("multiplier", 1.0)
	var damage: int = int(attacker_stats.power * multiplier)
	target_stats.current_hp = max(0, target_stats.current_hp - damage)
	return {"damage": damage, "target_defeated": not target_stats.is_alive()}


## Moves up to a distance that scales with the actor's Athletics level,
## stopping early if blocked. Deliberately weak at level 0 (base_distance
## defaults to 1 - the same as a plain Move), so Dash only becomes a real
## mobility advantage once Athletics is trained up. Same exploit shape as
## Heal: earn the payoff by grinding, don't start with it.
##
## Calls the real ActionResolver.resolve_move() per cell, which means each
## step fires its own "moved" GameEvent and trains Athletics normally - a
## deliberate, not fully evaluated choice. It's thematically reasonable
## (more movement, more training) but means one Dash produces several log
## lines instead of one unified "dashed two cells" line. Worth watching
## once actually played, not fixed pre-emptively.
func _dash(effect: Dictionary, context: Dictionary) -> Dictionary:
	var actor_id: int = context.get("actor_id", -1)
	var direction: int = context.get("direction", -1)
	if actor_id == -1 or direction == -1:
		return {}
	var max_distance: int = _compute_dash_distance(effect, actor_id)
	var cells_moved: int = 0
	for i in range(max_distance):
		var moved: GameEvent = ActionResolver.resolve_move(actor_id, direction)
		if moved == null:
			break
		cells_moved += 1
	return {"cells_moved": cells_moved}


## Same idea as _dash, but computes its own direction toward target_id
## each step (greedy, axis-priority) instead of taking an explicit
## direction, and stops as soon as it's in attack range. Duplicates
## AIController's greedy-direction logic in miniature - a small,
## deliberate duplication rather than an early shared abstraction; worth
## factoring out if a third place needs the same logic, not before.
func _dash_toward(effect: Dictionary, context: Dictionary) -> Dictionary:
	var actor_id: int = context.get("actor_id", -1)
	var target_id: int = context.get("target_id", -1)
	if actor_id == -1 or target_id == -1:
		return {}
	var self_pos: PositionComponent = EntityRegistry.get_component(actor_id, "PositionComponent")
	var target_pos: PositionComponent = EntityRegistry.get_component(target_id, "PositionComponent")
	if self_pos == null or target_pos == null:
		return {}

	var max_distance: int = _compute_dash_distance(effect, actor_id)
	var cells_moved: int = 0
	for i in range(max_distance):
		if ActionResolver.can_attack(actor_id, target_id):
			break
		var delta: Vector2i = target_pos.grid_position - self_pos.grid_position
		var direction: int
		if abs(delta.x) >= abs(delta.y):
			direction = ActionResolver.Direction.RIGHT if delta.x > 0 else ActionResolver.Direction.LEFT
		else:
			direction = ActionResolver.Direction.DOWN if delta.y > 0 else ActionResolver.Direction.UP
		var moved: GameEvent = ActionResolver.resolve_move(actor_id, direction)
		if moved == null:
			break
		cells_moved += 1
	return {"cells_moved": cells_moved}


func _compute_dash_distance(effect: Dictionary, actor_id: int) -> int:
	var athletics_level: int = _get_skill_level(actor_id, "athletics")
	return effect.get("base_distance", 1) + effect.get("per_level", 1) * athletics_level


## Attaches RecoveringComponent, making TurnScheduler skip the actor's
## next `turns` turn(s).
func _apply_recovery(effect: Dictionary, context: Dictionary) -> Dictionary:
	var actor_id: int = context.get("actor_id", -1)
	if actor_id == -1:
		return {}
	var recovering := RecoveringComponent.new()
	recovering.turns_remaining = effect.get("turns", 1)
	EntityRegistry.add_component(actor_id, recovering)
	return {"recovery_turns": recovering.turns_remaining}


## Restores HP, up to max_hp. Refuses to act on a dead target (see
## _revive for that) - "heal someone who's fine" and "bring back someone
## who died" are different enough actions to be separate effects, not one
## effect with a "also secretly works on the dead" special case.
##
## Amount scales with the actor's Healing skill level, deliberately
## starting weak: at level 0 it heals for less than the enemy's attack
## deals, so healing instead of acting is a losing trade until Healing is
## trained up - the vertical slice's first real system exploit. See
## DESIGN_PILLARS.md's Experiment Log.
func _heal(effect: Dictionary, context: Dictionary) -> Dictionary:
	var actor_id: int = context.get("actor_id", -1)
	var target_id: int = context.get("target_id", -1)
	if target_id == -1:
		return {}
	var target_stats: StatsComponent = EntityRegistry.get_component(target_id, "StatsComponent")
	if target_stats == null:
		return {}
	if not target_stats.is_alive():
		return {"healed": 0, "target_dead": true}

	var healing_level: int = _get_skill_level(actor_id, "healing")
	var amount: int = effect.get("base_amount", 2) + effect.get("per_level", 4) * healing_level
	var before: int = target_stats.current_hp
	target_stats.current_hp = min(target_stats.max_hp, target_stats.current_hp + amount)
	return {"healed": target_stats.current_hp - before}


func _get_skill_level(entity_id: int, skill_id: String) -> int:
	var skills: SkillsComponent = EntityRegistry.get_component(entity_id, "SkillsComponent")
	return skills.get_level(skill_id) if skills != null else 0


## Restores a dead target (is_alive() == false) to a small positive HP
## value. Refuses to act on a target that's still alive - see _heal for
## that. Deliberately does not touch TurnScheduler or EntityRegistry
## beyond StatsComponent - a revived entity naturally starts getting
## turns again next time TurnScheduler's dead-check passes, no separate
## "re-enable this entity" step needed.
func _revive(effect: Dictionary, context: Dictionary) -> Dictionary:
	var target_id: int = context.get("target_id", -1)
	if target_id == -1:
		return {}
	var target_stats: StatsComponent = EntityRegistry.get_component(target_id, "StatsComponent")
	if target_stats == null:
		return {}
	if target_stats.is_alive():
		return {"revived": false, "target_already_alive": true}
	target_stats.current_hp = min(target_stats.max_hp, effect.get("hp", 1))
	return {"revived": true, "hp_restored": target_stats.current_hp}
