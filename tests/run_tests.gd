## Runs every headless test: rule suites, then the UI and town flow smoke tests.
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits non-zero on any failure. With a display, `-- --shots=<dir>` saves
## UI screenshots.
extends SceneTree

const SUITES := [
	"res://tests/test_elements.gd",
	"res://tests/test_turns.gd",
	"res://tests/test_assets.gd",
	"res://tests/test_story.gd",
	"res://tests/test_town.gd",
	"res://tests/test_world_state.gd",
	"res://tests/test_night.gd",
	"res://tests/test_ui_text.gd",
]

var passed := 0
var failed := 0


func _init() -> void:
	_run.call_deferred()


func _report(name: String, failures: Array) -> void:
	if failures.is_empty():
		passed += 1
		print("  PASS  %s" % name)
	else:
		failed += 1
		print("  FAIL  %s" % name)
		for f in failures:
			print("        - " + f)


func _run() -> void:
	for path in SUITES:
		var script = load(path)
		if script == null or not script.can_instantiate():
			_report(path, ["suite failed to load (script error above)"])
			continue
		var suite = script.new()
		for m in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			suite.failures.clear()
			suite.call(name)
			_report(name, suite.failures)

	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	var ui = load("res://tests/ui_smoke.gd").new()
	await ui.run(self, shots)
	if not ui.completed:
		ui.failures.append("stopped early (script error above)")
	_report("ui_smoke (phone + desktop)", ui.failures)
	var flow = load("res://tests/flow_smoke.gd").new()
	await flow.run(self, shots)
	if not flow.completed:
		flow.failures.append("stopped early (script error above)")
	_report("flow_smoke (town -> fight -> town, phone)", flow.failures)

	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
