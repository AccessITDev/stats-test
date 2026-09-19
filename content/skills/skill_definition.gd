class_name SkillDefinition
extends Resource
## Data for one skill. Saved as .tres files under content/skills/ -
## SkillRegistry auto-discovers every file in that folder at startup, so
## adding a new skill is just adding a new .tres, no code change needed
## anywhere else.
##
## The XP curve here (flat cost per level) is deliberately the simplest
## possible placeholder - see DESIGN_PILLARS.md's open items on the real
## formula. Changing the curve later only touches the two functions below,
## not anything that depends on this class.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var xp_per_level: int = 100
@export var max_level: int = 10


## Computes the current level for a given amount of total earned XP.
func level_for_xp(total_xp: int) -> int:
	var level: int = total_xp / xp_per_level
	return min(level, max_level)


## Total XP required to reach `level` (for "XP to next level" display).
func xp_required_for_level(level: int) -> int:
	return level * xp_per_level
