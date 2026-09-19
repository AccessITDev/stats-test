extends Node
## Scene-based test for SkillsComponent - get_level() depends on the
## SkillRegistry autoload, so this needs the real scene boot path (see
## CLAUDE.md's note on -s scripts skipping autoload init).
##
## Run via F6 with this scene open, or:
##   redot --headless --path . tests/test_skills_component_scene.tscn

func _ready() -> void:
	var skills := SkillsComponent.new()

	# --- No XP yet: level 0, no entry needed ---
	assert(skills.get_xp("melee_combat") == 0, "Untouched skill should report 0 XP")
	assert(skills.get_level("melee_combat") == 0, "Untouched skill should report level 0")

	# --- Adding XP below a level threshold ---
	var result: Dictionary = skills.add_xp("melee_combat", 50)
	assert(skills.get_xp("melee_combat") == 50, "XP should accumulate")
	assert(result.old_level == 0 and result.new_level == 0, "50 XP shouldn't be enough to level up (needs 100)")
	assert(not result.leveled_up, "leveled_up should be false below the threshold")

	# --- Crossing a level threshold ---
	var level_up_result: Dictionary = skills.add_xp("melee_combat", 60)  # 50 + 60 = 110 total
	assert(skills.get_xp("melee_combat") == 110, "XP should keep accumulating")
	assert(level_up_result.old_level == 0 and level_up_result.new_level == 1, "Crossing 100 XP should go from level 0 to 1")
	assert(level_up_result.leveled_up, "leveled_up should be true when crossing a threshold")

	# --- Two skills tracked independently ---
	skills.add_xp("athletics", 250)
	assert(skills.get_level("athletics") == 2, "250 XP in athletics should be level 2")
	assert(skills.get_level("melee_combat") == 1, "melee_combat should be unaffected by athletics XP")

	# --- Unknown skill id: warns, doesn't crash ---
	assert(skills.get_level("not_a_real_skill") == 0, "An unknown skill id should report level 0, not crash")

	# --- serialize()/deserialize() round-trip ---
	var serialized: Dictionary = skills.serialize()
	var restored := SkillsComponent.new()
	restored.deserialize(serialized)
	assert(restored.get_xp("melee_combat") == 110, "melee_combat XP should round-trip")
	assert(restored.get_xp("athletics") == 250, "athletics XP should round-trip")
	assert(restored.get_level("athletics") == 2, "Restored component should compute the same level")

	print("SkillsComponent smoke test: all assertions passed.")
	get_tree().quit()
