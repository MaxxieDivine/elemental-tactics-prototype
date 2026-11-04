## A hero or enemy. Pure data; no rendering.
extends RefCounted

var id: int = 0
var type_id: String = ""
var team: String = ""  # "hero" or "enemy"
var name: String = ""
var cell: Vector2i = Vector2i.ZERO
var hp: int = 1
var max_hp: int = 1
var move: int = 3
var abilities: Array = []  # ability ids; heroes: [basic, ability1, ability2]
var cooldowns: Dictionary = {}  # ability id -> rounds until usable
var burning: int = 0  # rounds of burning left
var moved: bool = false
var acted: bool = false
var alive: bool = true
## Enemies only: {"move_to": Vector2i, "has_target": bool, "target": Vector2i, "target_name": String}
var intent: Dictionary = {}
var order: int = 0  # enemy action order within the enemy phase


func is_done() -> bool:
	return moved and acted


func can_use(ability_id: String) -> bool:
	return not acted and int(cooldowns.get(ability_id, 0)) <= 0


func clone():
	var u = get_script().new()
	u.id = id
	u.type_id = type_id
	u.team = team
	u.name = name
	u.cell = cell
	u.hp = hp
	u.max_hp = max_hp
	u.move = move
	u.abilities = abilities.duplicate()
	u.cooldowns = cooldowns.duplicate()
	u.burning = burning
	u.moved = moved
	u.acted = acted
	u.alive = alive
	u.intent = intent.duplicate()
	u.order = order
	return u
