## Commands the view sends to the rules (see Rules.apply_command).
## Plain dictionaries so they are easy to log, test and replay.
extends RefCounted


static func move(unit_id: int, to: Vector2i) -> Dictionary:
	return {"type": "move", "unit": unit_id, "to": to}


static func use_ability(unit_id: int, ability_id: String, target: Vector2i) -> Dictionary:
	return {"type": "use_ability", "unit": unit_id, "ability": ability_id, "target": target}


static func wait(unit_id: int) -> Dictionary:
	return {"type": "wait", "unit": unit_id}


static func end_turn() -> Dictionary:
	return {"type": "end_turn"}
