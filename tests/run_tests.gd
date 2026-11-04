## Headless test runner. Usage:
##   godot --headless --path . --script res://tests/run_tests.gd
## Runs every method starting with "test_" in each suite and exits non-zero on failure.
extends SceneTree

const SUITES := [
	"res://tests/test_elements.gd",
	"res://tests/test_turns.gd",
]


func _init() -> void:
	var passed := 0
	var failed := 0
	for path in SUITES:
		var suite = load(path).new()
		for m in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			suite.failures.clear()
			suite.call(name)
			if suite.failures.is_empty():
				passed += 1
				print("  PASS  %s" % name)
			else:
				failed += 1
				print("  FAIL  %s" % name)
				for f in suite.failures:
					print("        - " + f)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
