## Story memory: a set of simple named flags such as "read_letter".
## Plain data, no Nodes.
extends RefCounted

var flags: Dictionary = {}  # name -> true


func set_flag(name: String) -> void:
	flags[name] = true


func clear_flag(name: String) -> void:
	flags.erase(name)


func has(name: String) -> bool:
	return flags.has(name)


## True when every flag in `requires` is set and none in `unless` is.
func meets(requires: Array, unless: Array = []) -> bool:
	return requires.all(func(f): return has(f)) and not unless.any(func(f): return has(f))


func names() -> Array:
	var out: Array = flags.keys()
	out.sort()
	return out
