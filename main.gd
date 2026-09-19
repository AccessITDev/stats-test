extends Control
## The first playable vertical slice: two entities (player, enemy) on a
## Grid.WIDTH x Grid.HEIGHT grid, Move + Attack via buttons, narration via
## ProceduralInterpreter. No LLM involved anywhere in this scene - see
## DESIGN_PILLARS.md's "Proposed First Vertical Slice."
##
## Known simplifications, deliberate for this slice:
## - Only ever two entities, so turn dispatch is hardcoded (player button
##   input, then always AIController for the one enemy) rather than a
##   generic "look up this entity's controller component" system.
## - Only the PLAYER dying ends the round (see _check_player_death).
##   Enemy death is narrated but the player can keep acting - including
##   reviving the enemy - since death is a state change, not necessarily
##   an ending. Restart is always available regardless of game_over, both
##   as the real "start a new round" flow and as a fast testing reset.
## - Move/Attack buttons are always enabled regardless of legality; an
##   illegal action just logs "That didn't work." and doesn't consume a
##   turn. Ability buttons (including Heal/Revive) ARE dynamically
##   disabled based on real unlock/target-state status - see
##   _refresh_display.
## - _resolve_full_turn loops until control returns to the player rather
##   than assuming exactly one enemy turn per player action, specifically
##   because RecoveringComponent can skip the player's own turn (see that
##   function's comment - this used to be a real soft-lock).
## - Player death still fully locks the UI down, including Heal/Revive -
##   a self-revival flow that overrides game_over is a natural future
##   extension, not built here. Placeholder, per the "let's first create
##   a placeholder game over state" framing this was built under.

@onready var grid_display: GridContainer = $ScrollContainer/VBox/GridDisplay
@onready var stats_label: Label = $ScrollContainer/VBox/StatsLabel
@onready var restart_button: Button = $ScrollContainer/VBox/RestartButton
@onready var skills_label: Label = $ScrollContainer/VBox/SkillsLabel
@onready var log_display: RichTextLabel = $ScrollContainer/VBox/LogDisplay
@onready var up_button: Button = $ScrollContainer/VBox/Buttons/UpButton
@onready var down_button: Button = $ScrollContainer/VBox/Buttons/DownButton
@onready var left_button: Button = $ScrollContainer/VBox/Buttons/LeftButton
@onready var right_button: Button = $ScrollContainer/VBox/Buttons/RightButton
@onready var attack_button: Button = $ScrollContainer/VBox/Buttons/AttackButton
@onready var dash_up_button: Button = $ScrollContainer/VBox/DashButtons/DashUpButton
@onready var dash_down_button: Button = $ScrollContainer/VBox/DashButtons/DashDownButton
@onready var dash_left_button: Button = $ScrollContainer/VBox/DashButtons/DashLeftButton
@onready var dash_right_button: Button = $ScrollContainer/VBox/DashButtons/DashRightButton
@onready var power_strike_button: Button = $ScrollContainer/VBox/AbilityButtons/PowerStrikeButton
@onready var charging_strike_button: Button = $ScrollContainer/VBox/AbilityButtons/ChargingStrikeButton
@onready var heal_button: Button = $ScrollContainer/VBox/SupportButtons/HealButton
@onready var revive_button: Button = $ScrollContainer/VBox/SupportButtons/ReviveButton
@onready var debug_buttons_container: HBoxContainer = $ScrollContainer/VBox/DebugButtons
@onready var debug_stat_buttons_container: HBoxContainer = $ScrollContainer/VBox/DebugStatButtons

var interpreter := ProceduralInterpreter.new()
var player_id: int
var enemy_id: int
var cell_labels: Array[Label] = []
var game_over: bool = false


func _ready() -> void:
	_spawn_entities()
	_build_grid_display()
	_build_debug_buttons()
	TurnScheduler.start_round()

	restart_button.pressed.connect(_restart_game)
	up_button.pressed.connect(_on_move_pressed.bind(ActionResolver.Direction.UP))
	down_button.pressed.connect(_on_move_pressed.bind(ActionResolver.Direction.DOWN))
	left_button.pressed.connect(_on_move_pressed.bind(ActionResolver.Direction.LEFT))
	right_button.pressed.connect(_on_move_pressed.bind(ActionResolver.Direction.RIGHT))
	attack_button.pressed.connect(_on_attack_pressed)
	dash_up_button.pressed.connect(_on_dash_pressed.bind(ActionResolver.Direction.UP))
	dash_down_button.pressed.connect(_on_dash_pressed.bind(ActionResolver.Direction.DOWN))
	dash_left_button.pressed.connect(_on_dash_pressed.bind(ActionResolver.Direction.LEFT))
	dash_right_button.pressed.connect(_on_dash_pressed.bind(ActionResolver.Direction.RIGHT))
	power_strike_button.pressed.connect(_on_power_strike_pressed)
	charging_strike_button.pressed.connect(_on_charging_strike_pressed)
	heal_button.pressed.connect(_on_heal_pressed)
	revive_button.pressed.connect(_on_revive_pressed)
	ProgressionSystem.skill_leveled_up.connect(_on_skill_leveled_up)
	TurnScheduler.turn_skipped.connect(_on_turn_skipped)

	_refresh_display()


func _spawn_entities() -> void:
	player_id = EntityRegistry.create_entity()
	var player_pos := PositionComponent.new()
	player_pos.grid_position = Vector2i(2, 2)
	EntityRegistry.add_component(player_id, player_pos)
	var player_stats := StatsComponent.new()
	player_stats.max_hp = 20
	player_stats.current_hp = 20
	player_stats.power = 4
	EntityRegistry.add_component(player_id, player_stats)
	EntityRegistry.add_component(player_id, TurnTakerComponent.new())
	EntityRegistry.add_component(player_id, PlayerControlledComponent.new())
	EntityRegistry.add_component(player_id, SkillsComponent.new())

	enemy_id = EntityRegistry.create_entity()
	var enemy_pos := PositionComponent.new()
	enemy_pos.grid_position = Vector2i(4, 4)
	EntityRegistry.add_component(enemy_id, enemy_pos)
	var enemy_stats := StatsComponent.new()
	enemy_stats.max_hp = 12
	enemy_stats.current_hp = 12
	enemy_stats.power = 3
	EntityRegistry.add_component(enemy_id, enemy_stats)
	EntityRegistry.add_component(enemy_id, TurnTakerComponent.new())
	EntityRegistry.add_component(enemy_id, AIControlledComponent.new())
	EntityRegistry.add_component(enemy_id, SkillsComponent.new())


## Wipes all game state and starts a fresh round. Available regardless of
## game_over - both the real "game over -> restart" flow and a fast
## testing reset are the same action here.
func _restart_game() -> void:
	EntityRegistry.clear_all()
	log_display.clear()
	game_over = false
	up_button.disabled = false
	down_button.disabled = false
	left_button.disabled = false
	right_button.disabled = false
	attack_button.disabled = false
	_spawn_entities()
	TurnScheduler.start_round()
	_refresh_display()


func _build_grid_display() -> void:
	grid_display.columns = Grid.WIDTH
	for i in range(Grid.WIDTH * Grid.HEIGHT):
		var cell := Label.new()
		cell.custom_minimum_size = Vector2(28, 28)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.text = "."
		grid_display.add_child(cell)
		cell_labels.append(cell)


## First-pass debug tooling, deliberately minimal: one button per skill
## SkillRegistry knows about (auto-generated, so a new skill .tres file
## just works without touching this scene), plus a few hardcoded
## stat-tweak buttons (StatsComponent/TurnTakerComponent fields aren't
## registry-driven the way skills are, so these are just listed directly).
## Debug actions are explicitly outside the turn economy - they mutate
## state and refresh the display directly, without going through
## _resolve_full_turn(), so using them doesn't cost a turn or let the
## enemy act. Future expansion (typing an exact level, a real attribute
## system, etc.) can replace this without changing that basic separation.
func _build_debug_buttons() -> void:
	var skill_ids: Array = SkillRegistry.get_all_ids()
	skill_ids.sort()
	for skill_id: String in skill_ids:
		var definition: SkillDefinition = SkillRegistry.get_definition(skill_id)
		var button := Button.new()
		button.name = "DebugGrant_%s" % skill_id
		button.text = "+%d XP: %s" % [definition.xp_per_level, definition.display_name]
		button.pressed.connect(_on_debug_grant_skill.bind(skill_id))
		debug_buttons_container.add_child(button)

	_add_debug_stat_button("DebugAddPower", "+1 Power", _on_debug_add_power)
	_add_debug_stat_button("DebugAddSpeed", "+1 Speed", _on_debug_add_speed)
	_add_debug_stat_button("DebugAddMaxHp", "+5 Max HP", _on_debug_add_max_hp)


func _add_debug_stat_button(node_name: String, label: String, handler: Callable) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.pressed.connect(handler)
	debug_stat_buttons_container.add_child(button)


func _on_debug_grant_skill(skill_id: String) -> void:
	var skills: SkillsComponent = EntityRegistry.get_component(player_id, "SkillsComponent")
	if skills == null:
		return
	var definition: SkillDefinition = SkillRegistry.get_definition(skill_id)
	skills.add_xp(skill_id, definition.xp_per_level)
	_refresh_display()


func _on_debug_add_power() -> void:
	var stats: StatsComponent = EntityRegistry.get_component(player_id, "StatsComponent")
	if stats == null:
		return
	stats.power += 1
	_refresh_display()


## Takes effect at the start of the next round - TurnScheduler re-sorts by
## speed every time a round starts, so no extra invalidation is needed
## here for the change to actually be picked up.
func _on_debug_add_speed() -> void:
	var turn_taker: TurnTakerComponent = EntityRegistry.get_component(player_id, "TurnTakerComponent")
	if turn_taker == null:
		return
	turn_taker.speed += 1
	_refresh_display()


func _on_debug_add_max_hp() -> void:
	var stats: StatsComponent = EntityRegistry.get_component(player_id, "StatsComponent")
	if stats == null:
		return
	stats.max_hp += 5
	stats.current_hp += 5  # also heals the same amount, so the change is visible immediately
	_refresh_display()


## Known ordering quirk, not fixed: ProgressionSystem.skill_leveled_up fires
## synchronously *inside* ActionResolver's resolve_move/resolve_attack call
## (action_resolved -> ProgressionSystem.add_xp -> skill_leveled_up, all
## before resolve_* returns), so this line can appear in the log *before*
## the action's own narration that caused it. Cosmetic only - fixing it
## would mean deferring this signal (call_deferred), which isn't worth the
## complexity for a log-ordering detail at this stage.
func _on_skill_leveled_up(event: GameEvent) -> void:
	_log(interpreter.narrate_event(event))


func _on_turn_skipped(event: GameEvent) -> void:
	_log(interpreter.narrate_event(event))


func _on_move_pressed(direction: ActionResolver.Direction) -> void:
	if game_over or TurnScheduler.get_active_entity() != player_id:
		return
	var event: GameEvent = ActionResolver.resolve_move(player_id, direction)
	_resolve_full_turn(event)


func _on_attack_pressed() -> void:
	if game_over or TurnScheduler.get_active_entity() != player_id:
		return
	var event: GameEvent = ActionResolver.resolve_attack(player_id, enemy_id)
	_resolve_full_turn(event)


func _on_dash_pressed(direction: ActionResolver.Direction) -> void:
	if game_over or TurnScheduler.get_active_entity() != player_id:
		return
	var event: GameEvent = ActionResolver.resolve_ability(player_id, "dash", -1, direction)
	_resolve_full_turn(event)


## Both target the enemy directly, same simplification as the Attack
## button - there's only ever one possible target in this slice.
func _on_power_strike_pressed() -> void:
	if game_over or TurnScheduler.get_active_entity() != player_id:
		return
	var event: GameEvent = ActionResolver.resolve_ability(player_id, "power_strike", enemy_id)
	_resolve_full_turn(event)


func _on_charging_strike_pressed() -> void:
	if game_over or TurnScheduler.get_active_entity() != player_id:
		return
	var event: GameEvent = ActionResolver.resolve_ability(player_id, "charging_strike", enemy_id)
	_resolve_full_turn(event)


func _on_heal_pressed() -> void:
	if game_over or TurnScheduler.get_active_entity() != player_id:
		return
	var event: GameEvent = ActionResolver.resolve_ability(player_id, "heal", player_id)
	_resolve_full_turn(event)


func _on_revive_pressed() -> void:
	if game_over or TurnScheduler.get_active_entity() != player_id:
		return
	var event: GameEvent = ActionResolver.resolve_ability(player_id, "revive", enemy_id)
	_resolve_full_turn(event)


## Logs the player's action, then resolves every subsequent turn until
## it's the player's turn again (normally just one enemy turn, but see
## below) or the round ends (only on player death - see
## _check_player_death).
##
## This used to just call AIController.take_turn() exactly once and
## advance_turn() exactly twice, assuming "player acts, enemy acts, back
## to player." That assumption breaks the moment RecoveringComponent can
## skip the player's own turn: advancing past a skipped player lands back
## on the enemy, so the old code would leave the game stuck showing
## "Enemy turn" forever with no way to act - a real soft-lock, not a
## hypothetical one. This loops until control genuinely returns to the
## player instead of assuming it does after one enemy turn.
func _resolve_full_turn(player_event: GameEvent) -> void:
	if player_event == null:
		_log("That didn't work.")
		_refresh_display()
		return
	_log_event(player_event)

	if _check_player_death():
		_refresh_display()
		return

	TurnScheduler.advance_turn()  # off the player's turn

	var safety_cap: int = 10  # generous for a 2-entity scene; guards against a real loop, not just this one
	while TurnScheduler.get_active_entity() != player_id and safety_cap > 0:
		if TurnScheduler.get_active_entity() == enemy_id:
			var enemy_event: GameEvent = AIController.take_turn(enemy_id, player_id)
			if enemy_event != null:
				_log_event(enemy_event)
			if _check_player_death():
				_refresh_display()
				return
		TurnScheduler.advance_turn()
		safety_cap -= 1

	_refresh_display()


## Narrates an action event, then adds a clear callout if it happened to
## defeat the enemy - the mechanical narration alone ("strikes down"/
## "(defeated)") is easy to miss now that enemy death doesn't freeze
## anything the way it used to. Player death has its own unmistakable
## message via _check_player_death, so this only needs to cover the enemy.
func _log_event(event: GameEvent) -> void:
	_log(interpreter.narrate_event(event))
	var defeated_enemy: bool = event.data.get("target_id", -1) == enemy_id and (
		event.event_type == "attack_defeated" or event.data.get("target_defeated", false)
	)
	if defeated_enemy:
		_log("The enemy is down. Revive them to keep fighting, or Restart for a fresh round.")


## Only the player dying ends the round - see the top-of-file comment on
## why enemy death is handled differently (_log_event's defeat callout,
## not this).
func _check_player_death() -> bool:
	var player_stats: StatsComponent = EntityRegistry.get_component(player_id, "StatsComponent")
	if not player_stats.is_alive():
		_log("You have fallen.")
		_end_game()
		return true
	return false


func _end_game() -> void:
	game_over = true
	up_button.disabled = true
	down_button.disabled = true
	left_button.disabled = true
	right_button.disabled = true
	attack_button.disabled = true


func _log(text: String) -> void:
	log_display.append_text(text + "\n")


func _refresh_display() -> void:
	var player_pos: PositionComponent = EntityRegistry.get_component(player_id, "PositionComponent")
	var enemy_pos: PositionComponent = EntityRegistry.get_component(enemy_id, "PositionComponent")
	var player_stats: StatsComponent = EntityRegistry.get_component(player_id, "StatsComponent")
	var enemy_stats: StatsComponent = EntityRegistry.get_component(enemy_id, "StatsComponent")

	for cell in cell_labels:
		cell.text = "."

	# Dead entities still occupy their cell (Grid.is_occupied() doesn't
	# check is_alive() - a body still blocks movement onto it), so they
	# need a visible symbol too, or the grid would show an empty-looking
	# cell that mysteriously can't be walked onto. Lowercase marks a body,
	# distinct from the uppercase living symbol for the same entity.
	var player_index: int = player_pos.grid_position.y * Grid.WIDTH + player_pos.grid_position.x
	cell_labels[player_index].text = "P" if player_stats.is_alive() else "p"
	var enemy_index: int = enemy_pos.grid_position.y * Grid.WIDTH + enemy_pos.grid_position.x
	cell_labels[enemy_index].text = "E" if enemy_stats.is_alive() else "e"

	var turn_label: String = "Game over" if game_over else ("Your turn" if TurnScheduler.get_active_entity() == player_id else "Enemy turn")
	var player_turn_taker: TurnTakerComponent = EntityRegistry.get_component(player_id, "TurnTakerComponent")
	stats_label.text = "Player HP: %d/%d (Power %d, Speed %d)    Enemy HP: %d/%d    [%s]" % [
		player_stats.current_hp, player_stats.max_hp, player_stats.power, player_turn_taker.speed,
		enemy_stats.current_hp, enemy_stats.max_hp,
		turn_label,
	]
	skills_label.text = _build_skills_label_text(player_id)

	var dash_unlocked: bool = not game_over and ActionResolver.can_use_ability(player_id, "dash")
	dash_up_button.disabled = not dash_unlocked
	dash_down_button.disabled = not dash_unlocked
	dash_left_button.disabled = not dash_unlocked
	dash_right_button.disabled = not dash_unlocked
	power_strike_button.disabled = game_over or not ActionResolver.can_use_ability(player_id, "power_strike")
	charging_strike_button.disabled = game_over or not ActionResolver.can_use_ability(player_id, "charging_strike")

	# Heal/Revive have no skill requirement, so they're gated on whether
	# using them right now would actually do anything, not on unlock
	# status - a different kind of gating than the ability buttons above,
	# not unified with can_use_ability. Fine for two buttons; would be
	# worth a real rule if more target-state-gated abilities show up.
	heal_button.disabled = game_over or not player_stats.is_alive() or player_stats.current_hp >= player_stats.max_hp
	revive_button.disabled = game_over or enemy_stats.is_alive()


## Player-only for now - the enemy has a SkillsComponent too (consistency,
## not a special-cased player), but nothing needs to display its progress
## yet.
func _build_skills_label_text(entity_id: int) -> String:
	var skills: SkillsComponent = EntityRegistry.get_component(entity_id, "SkillsComponent")
	if skills == null:
		return ""
	var skill_ids: Array = SkillRegistry.get_all_ids()
	skill_ids.sort()
	var parts: Array[String] = []
	for skill_id: String in skill_ids:
		var definition: SkillDefinition = SkillRegistry.get_definition(skill_id)
		var level: int = skills.get_level(skill_id)
		var xp: int = skills.get_xp(skill_id)
		var xp_into_level: int = xp - definition.xp_required_for_level(level)
		parts.append("%s: Lv%d (%d/%d XP)" % [definition.display_name, level, xp_into_level, definition.xp_per_level])
	return " | ".join(parts)
