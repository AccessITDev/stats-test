extends SceneTree
## Standalone smoke test for step 2: StatsComponent, TurnTakerComponent,
## PlayerControlledComponent, AIControlledComponent.
##
## Run via F6 in the editor, or from a terminal in the project folder:
##   redot --headless -s tests/test_components.gd

func _init() -> void:
	var registry = load("res://systems/entity_registry.gd").new()

	# --- Player entity: Stats + TurnTaker + PlayerControlled ---
	var player_id: int = registry.create_entity()
	var player_stats := StatsComponent.new()
	player_stats.max_hp = 20
	player_stats.current_hp = 20
	player_stats.power = 3
	registry.add_component(player_id, player_stats)
	registry.add_component(player_id, TurnTakerComponent.new())
	registry.add_component(player_id, PlayerControlledComponent.new())

	# --- Enemy entity: Stats + TurnTaker + AIControlled ---
	var enemy_id: int = registry.create_entity()
	var enemy_stats := StatsComponent.new()
	enemy_stats.max_hp = 8
	enemy_stats.current_hp = 8
	enemy_stats.power = 2
	registry.add_component(enemy_id, enemy_stats)
	registry.add_component(enemy_id, TurnTakerComponent.new())
	registry.add_component(enemy_id, AIControlledComponent.new())

	# --- Queries correctly discriminate player vs. AI entities ---
	var turn_taker_query: Array[String] = ["TurnTakerComponent"]
	var all_turn_takers: Array[int] = registry.get_entities_with(turn_taker_query)
	assert(all_turn_takers.size() == 2, "Expected 2 turn-taking entities, got %d" % all_turn_takers.size())

	var player_query: Array[String] = ["TurnTakerComponent", "PlayerControlledComponent"]
	var players: Array[int] = registry.get_entities_with(player_query)
	assert(players.size() == 1 and players[0] == player_id, "Expected only the player entity to match the player-controlled query")

	var ai_query: Array[String] = ["TurnTakerComponent", "AIControlledComponent"]
	var ai_entities: Array[int] = registry.get_entities_with(ai_query)
	assert(ai_entities.size() == 1 and ai_entities[0] == enemy_id, "Expected only the enemy entity to match the AI-controlled query")

	# --- is_alive() ---
	assert(player_stats.is_alive(), "Player should be alive at full HP")
	enemy_stats.current_hp = 0
	assert(not enemy_stats.is_alive(), "Enemy should be dead at 0 HP")

	# --- serialize()/deserialize() round-trip (matters once save/load exists) ---
	var serialized: Dictionary = player_stats.serialize()
	var restored := StatsComponent.new()
	restored.deserialize(serialized)
	assert(restored.max_hp == player_stats.max_hp, "max_hp did not round-trip through serialize/deserialize")
	assert(restored.current_hp == player_stats.current_hp, "current_hp did not round-trip through serialize/deserialize")
	assert(restored.power == player_stats.power, "power did not round-trip through serialize/deserialize")

	print("Component smoke test: all assertions passed.")
	registry.free()
	quit()
