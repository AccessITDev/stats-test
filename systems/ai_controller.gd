extends Node
## Minimal enemy decision-making: attack if adjacent to the target,
## otherwise take one step closer. Deliberately the ONLY behavior that
## exists - see AIControlledComponent's doc comment. Not a pluggable
## "behavior" framework, since there's nothing yet to justify generalizing
## a single behavior into one (DESIGN_PILLARS.md's "only then generalize").
##
## Known simplification: if the "closer" direction happens to be blocked,
## this just fails to act that turn rather than trying an alternate route -
## fine with no obstacles in this slice, revisit once any exist.
##
## Registered as the autoload singleton "AIController". Deliberately has no
## class_name, same reason as the other autoloads.

## Decides and executes one action for entity_id, chasing target_id.
## Returns the resulting GameEvent, or null if nothing happened (missing
## components, or the approach direction was blocked).
func take_turn(entity_id: int, target_id: int) -> GameEvent:
	var self_pos: PositionComponent = EntityRegistry.get_component(entity_id, "PositionComponent")
	var target_pos: PositionComponent = EntityRegistry.get_component(target_id, "PositionComponent")
	if self_pos == null or target_pos == null:
		return null

	if ActionResolver.can_attack(entity_id, target_id):
		return ActionResolver.resolve_attack(entity_id, target_id)

	var delta: Vector2i = target_pos.grid_position - self_pos.grid_position
	var direction: ActionResolver.Direction
	if abs(delta.x) >= abs(delta.y):
		direction = ActionResolver.Direction.RIGHT if delta.x > 0 else ActionResolver.Direction.LEFT
	else:
		direction = ActionResolver.Direction.DOWN if delta.y > 0 else ActionResolver.Direction.UP

	return ActionResolver.resolve_move(entity_id, direction)
