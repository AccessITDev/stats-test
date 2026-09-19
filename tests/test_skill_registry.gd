extends SceneTree
## Standalone smoke test for SkillRegistry + SkillDefinition. No autoload
## dependency here (load_all_definitions() is called directly, not via
## _ready()), so this can run as a plain -s script.
##
## Run via F6 in the editor, or:
##   redot --headless -s tests/test_skill_registry.gd

func _init() -> void:
	var registry = load("res://systems/skill_registry.gd").new()
	registry.load_all_definitions()

	# --- Auto-discovery found both test skills ---
	assert(registry.has_definition("melee_combat"), "melee_combat.tres should have been auto-discovered")
	assert(registry.has_definition("athletics"), "athletics.tres should have been auto-discovered")
	assert(not registry.has_definition("nonexistent_skill"), "A skill that doesn't exist should not be found")
	assert(registry.get_all_ids().size() == 3, "Exactly 3 skills should be loaded, got %d" % registry.get_all_ids().size())

	# --- Loaded definitions have the right data ---
	var melee: SkillDefinition = registry.get_definition("melee_combat")
	assert(melee.display_name == "Melee Combat", "Wrong display_name loaded: %s" % melee.display_name)
	assert(melee.xp_per_level == 100, "Wrong xp_per_level loaded: %d" % melee.xp_per_level)
	assert(melee.max_level == 10, "Wrong max_level loaded: %d" % melee.max_level)

	# --- Level curve math ---
	assert(melee.level_for_xp(0) == 0, "0 XP should be level 0")
	assert(melee.level_for_xp(99) == 0, "99 XP should still be level 0 (needs 100)")
	assert(melee.level_for_xp(100) == 1, "100 XP should be exactly level 1")
	assert(melee.level_for_xp(250) == 2, "250 XP should be level 2")
	assert(melee.level_for_xp(999999) == 10, "Absurdly high XP should clamp at max_level (10), got %d" % melee.level_for_xp(999999))
	assert(melee.xp_required_for_level(3) == 300, "Level 3 should require 300 XP, got %d" % melee.xp_required_for_level(3))

	print("SkillRegistry + SkillDefinition smoke test: all assertions passed.")
	registry.free()
	quit()
