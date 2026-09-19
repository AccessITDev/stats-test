extends Node
## Integration test for the wired-up main game scene (main.tscn):
## instantiates the *real* scene, simulates button presses by emitting
## their `pressed` signal (no real mouse/display needed - this exercises
## the actual signal connections main.gd makes in _ready()), and checks
## the resulting state and narration log.
##
## Note: log_display.text does NOT reflect content added via
## append_text() - only get_parsed_text() does. Learned the hard way;
## worth remembering for any future RichTextLabel-based UI.
##
## Run via F6 with this scene open, or:
##   redot --headless --path . tests/test_main_scene_integration.tscn

func _ready() -> void:
	var main_scene: PackedScene = load("res://main.tscn")
	var main_instance: Control = main_scene.instantiate()
	add_child(main_instance)
	await get_tree().process_frame
	await get_tree().process_frame

	var log_display: RichTextLabel = main_instance.get_node("ScrollContainer/VBox/LogDisplay")
	var stats_label: Label = main_instance.get_node("ScrollContainer/VBox/StatsLabel")
	var skills_label: Label = main_instance.get_node("ScrollContainer/VBox/SkillsLabel")
	var up_button: Button = main_instance.get_node("ScrollContainer/VBox/Buttons/UpButton")
	var attack_button: Button = main_instance.get_node("ScrollContainer/VBox/Buttons/AttackButton")
	var power_strike_button: Button = main_instance.get_node("ScrollContainer/VBox/AbilityButtons/PowerStrikeButton")
	var dash_up_button: Button = main_instance.get_node("ScrollContainer/VBox/DashButtons/DashUpButton")
	var heal_button: Button = main_instance.get_node("ScrollContainer/VBox/SupportButtons/HealButton")
	var revive_button: Button = main_instance.get_node("ScrollContainer/VBox/SupportButtons/ReviveButton")
	var restart_button: Button = main_instance.get_node("ScrollContainer/VBox/RestartButton")

	assert(stats_label.text != "Loading...", "main_instance's _ready() should have completed by now, but stats_label was never refreshed")
	assert(log_display.get_parsed_text() == "", "Log should start empty")
	assert(main_instance.player_id != main_instance.enemy_id, "Sanity check: player and enemy are different entities")
	assert(stats_label.text.contains("HP"), "Stats label should show HP from the very first frame: %s" % stats_label.text)

	# --- A full legal move: player starts at (2,2), Up is unobstructed ---
	up_button.pressed.emit()
	await get_tree().process_frame
	assert(log_display.get_parsed_text().length() > 0, "Log should have content after a legal move")
	var player_pos: PositionComponent = EntityRegistry.get_component(main_instance.player_id, "PositionComponent")
	assert(player_pos.grid_position == Vector2i(2, 1), "Player should have moved from (2,2) to (2,1), got %s" % player_pos.grid_position)
	var player_skills: SkillsComponent = EntityRegistry.get_component(main_instance.player_id, "SkillsComponent")
	assert(player_skills.get_xp("athletics") == 5, "A real move through the UI should award 5 athletics XP, got %d" % player_skills.get_xp("athletics"))
	assert(skills_label.text.contains("Athletics"), "Skills label should display Athletics: %s" % skills_label.text)

	# --- An illegal attack: player and enemy are still far apart, should no-op ---
	var log_before_bad_attack: String = log_display.get_parsed_text()
	attack_button.pressed.emit()
	await get_tree().process_frame
	assert(log_display.get_parsed_text() == log_before_bad_attack + "That didn't work.\n", "An illegal attack should just log the fallback line and change nothing else")

	# --- Force a legal attack by repositioning the enemy next to the player,
	# reaching into the same EntityRegistry the scene itself uses ---
	var enemy_pos: PositionComponent = EntityRegistry.get_component(main_instance.enemy_id, "PositionComponent")
	enemy_pos.grid_position = player_pos.grid_position + Vector2i(1, 0)
	var log_before_real_attack: String = log_display.get_parsed_text()
	attack_button.pressed.emit()
	await get_tree().process_frame
	assert(log_display.get_parsed_text().length() > log_before_real_attack.length(), "A legal attack should add real narration to the log")
	var enemy_stats: StatsComponent = EntityRegistry.get_component(main_instance.enemy_id, "StatsComponent")
	assert(enemy_stats.current_hp < 12, "Enemy HP should have dropped below its starting 12, got %d" % enemy_stats.current_hp)
	assert(player_skills.get_xp("melee_combat") == 10, "A real attack through the UI should award 10 melee_combat XP, got %d" % player_skills.get_xp("melee_combat"))

	# --- Force a level-up on the next real attack and confirm it's narrated ---
	player_skills.xp["melee_combat"] = 90  # one more hit (10 xp) crosses 100
	var log_before_level_up: String = log_display.get_parsed_text()
	attack_button.pressed.emit()
	await get_tree().process_frame
	assert(player_skills.get_level("melee_combat") == 1, "melee_combat should now be level 1")
	assert(log_display.get_parsed_text().length() > log_before_level_up.length(), "A level-up should add to the log")
	assert(log_display.get_parsed_text().contains("Melee Combat"), "Level-up narration should mention the skill's display name: %s" % log_display.get_parsed_text())
	assert(skills_label.text.contains("Lv1"), "Skills label should now show melee_combat at level 1: %s" % skills_label.text)

	# --- Ability buttons: gated on real unlock status ---
	assert(not power_strike_button.disabled, "Power Strike should be enabled - melee_combat is level 1")
	assert(dash_up_button.disabled, "Dash should still be disabled - athletics is only 5 XP, not level 1 yet")

	# Seed athletics directly to unlock Dash/Charging Strike too, then force
	# a refresh (no other action is happening to trigger one naturally).
	player_skills.xp["athletics"] = 100
	main_instance._refresh_display()
	assert(not dash_up_button.disabled, "Dash should now be enabled at athletics level 1")

	# --- Power Strike through the real button: double damage, proves the
	# recovery-skip doesn't soft-lock the turn cycle (this exact scenario
	# used to leave the game stuck on "Enemy turn" forever - see
	# _resolve_full_turn's comment), and confirms the recovery skip is now
	# actually telegraphed instead of silent. ---
	enemy_stats.current_hp = 30
	var log_before_power_strike: String = log_display.get_parsed_text()
	power_strike_button.pressed.emit()
	await get_tree().process_frame
	assert(enemy_stats.current_hp == 30 - (4 * 2), "Power Strike should deal double the player's power as damage, got enemy HP %d" % enemy_stats.current_hp)
	assert(log_display.get_parsed_text().length() > log_before_power_strike.length(), "Power Strike should add to the log")
	assert(player_skills.get_xp("melee_combat") == 100 + 10, "Power Strike should train melee_combat via the real UI too (100 + 10), got %d" % player_skills.get_xp("melee_combat"))
	assert(log_display.get_parsed_text().contains("8 damage"), "The log should show the actual damage dealt, not just 'uses Power Strike!': %s" % log_display.get_parsed_text())
	assert(log_display.get_parsed_text().contains("recovering"), "The recovery skip should now be telegraphed in the log, not silent: %s" % log_display.get_parsed_text())
	assert(TurnScheduler.get_active_entity() == main_instance.player_id, "Control must return to the player, not get stuck on the enemy after a recovery-skip")
	assert(EntityRegistry.get_component(main_instance.player_id, "RecoveringComponent") == null, "Recovery should already be consumed by the time control returns to the player")

	# --- Enemy defeat no longer ends the round - it's a state change,
	# narrated but not a lockdown (see main.gd's _check_player_death /
	# _log_event split, and the CLAUDE.md decision this follows). ---
	enemy_stats.current_hp = 1
	attack_button.pressed.emit()
	await get_tree().process_frame
	assert(not enemy_stats.is_alive(), "Enemy should be dead after this hit")
	assert(not main_instance.game_over, "Enemy death should NOT set game_over - only the player dying does")
	assert(not attack_button.disabled, "Attack button should stay enabled - the round isn't over")
	assert(log_display.get_parsed_text().contains("The enemy is down"), "Enemy defeat should still get a clear callout in the log: %s" % log_display.get_parsed_text())
	assert(not revive_button.disabled, "Revive should now be enabled - the enemy is dead")

	# --- Revive Enemy: brings it back, costs a turn like any other action ---
	revive_button.pressed.emit()
	await get_tree().process_frame
	assert(enemy_stats.is_alive(), "Enemy should be alive again after Revive")
	assert(enemy_stats.current_hp == 5, "Revive should restore to the 5 HP configured in revive.tres, got %d" % enemy_stats.current_hp)
	assert(revive_button.disabled, "Revive should be disabled again now that the enemy is alive")

	# --- Heal Self: restores HP, and is gated on actually being useful ---
	var player_stats: StatsComponent = EntityRegistry.get_component(main_instance.player_id, "StatsComponent")
	player_stats.current_hp = 5  # force a known, clearly-below-max value
	main_instance._refresh_display()
	assert(not heal_button.disabled, "Heal should be enabled - player is alive and below max HP")
	heal_button.pressed.emit()
	await get_tree().process_frame
	# At Healing level 0, Heal restores only 2 HP (deliberately below the
	# enemy's 3 damage - the exploit's whole point). Heal costs a turn
	# like any other action, and the enemy (revived, still adjacent)
	# counter-attacks for its power (3): 5 + 2 - 3 = 4.
	assert(player_stats.current_hp == 4, "Heal should net to 4 HP (5 + 2 healed at level 0 - 3 from the enemy's counter-attack), got %d" % player_stats.current_hp)

	# --- Real player death: this IS a full round-ending event ---
	player_stats.current_hp = 0
	var died: bool = main_instance._check_player_death()
	assert(died, "_check_player_death should detect 0 HP and return true")
	assert(main_instance.game_over, "game_over should now be true")
	assert(attack_button.disabled, "Attack should be disabled once the game is truly over")
	assert(log_display.get_parsed_text().contains("You have fallen"), "Log should show the player-death message: %s" % log_display.get_parsed_text())

	# --- Restart: full reset, regardless of game_over ---
	var old_player_id: int = main_instance.player_id
	restart_button.pressed.emit()
	await get_tree().process_frame
	assert(not main_instance.game_over, "game_over should be false after restart")
	assert(main_instance.player_id != old_player_id, "Restart should create a fresh player entity, not reuse the old id")
	assert(not attack_button.disabled, "Buttons should be re-enabled after restart")
	assert(log_display.get_parsed_text() == "", "Log should be cleared on restart")
	assert(not EntityRegistry.entity_exists(old_player_id), "The old player entity should no longer exist after clear_all()")

	# Fresh references - the ones above now point at destroyed entities.
	var new_player_skills: SkillsComponent = EntityRegistry.get_component(main_instance.player_id, "SkillsComponent")
	var new_player_stats: StatsComponent = EntityRegistry.get_component(main_instance.player_id, "StatsComponent")
	var new_player_turn_taker: TurnTakerComponent = EntityRegistry.get_component(main_instance.player_id, "TurnTakerComponent")
	assert(new_player_stats.current_hp == 20, "A freshly restarted player should be back to full starting HP, got %d" % new_player_stats.current_hp)
	assert(new_player_skills.get_xp("athletics") == 0, "A freshly restarted player should have no skill progress")

	# --- Debug menu: grants XP directly, outside the turn economy, and
	# works on the fresh post-restart player ---
	var debug_melee_button: Button = main_instance.get_node("ScrollContainer/VBox/DebugButtons/DebugGrant_melee_combat")
	var turn_before_debug: int = TurnScheduler.get_active_entity()
	var log_before_debug: String = log_display.get_parsed_text()
	debug_melee_button.pressed.emit()
	await get_tree().process_frame
	assert(new_player_skills.get_xp("melee_combat") == 100, "Debug button should grant exactly one skill's xp_per_level (100), got %d" % new_player_skills.get_xp("melee_combat"))
	assert(TurnScheduler.get_active_entity() == turn_before_debug, "Debug XP grant must not advance or change whose turn it is")
	assert(log_display.get_parsed_text() == log_before_debug, "Debug XP grant must not add to the narrative log")

	# --- Debug stat buttons: power, speed, max HP ---
	var power_button: Button = main_instance.get_node("ScrollContainer/VBox/DebugStatButtons/DebugAddPower")
	var speed_button: Button = main_instance.get_node("ScrollContainer/VBox/DebugStatButtons/DebugAddSpeed")
	var max_hp_button: Button = main_instance.get_node("ScrollContainer/VBox/DebugStatButtons/DebugAddMaxHp")

	var power_before: int = new_player_stats.power
	power_button.pressed.emit()
	await get_tree().process_frame
	assert(new_player_stats.power == power_before + 1, "Power button should add exactly 1 power")

	var max_hp_before: int = new_player_stats.max_hp
	var hp_before: int = new_player_stats.current_hp
	max_hp_button.pressed.emit()
	await get_tree().process_frame
	assert(new_player_stats.max_hp == max_hp_before + 5, "Max HP button should add exactly 5 max HP")
	assert(new_player_stats.current_hp == hp_before + 5, "Max HP button should also heal by the same amount, so the change is visible")

	# Speed actually changing turn order, not just the stored number:
	# push player speed well above the enemy's default (1) and confirm a
	# fresh round now puts the player first.
	for i in range(10):
		speed_button.pressed.emit()
	await get_tree().process_frame
	assert(new_player_turn_taker.speed == 11, "10 presses of +1 Speed should leave speed at 11 (1 base + 10), got %d" % new_player_turn_taker.speed)
	TurnScheduler.start_round()
	assert(TurnScheduler.get_active_entity() == main_instance.player_id, "With much higher speed, the player should now act first in a fresh round")

	print("Main scene integration smoke test: all assertions passed.")
	get_tree().quit()
