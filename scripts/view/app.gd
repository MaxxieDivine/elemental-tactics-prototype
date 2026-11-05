## Top-level screen switcher: start menu -> town (any map) -> fight -> town.
## Owns no rules: GameSession (core) holds flags, the town spot and the fight
## in progress; each screen only reports what the player did.
extends Node

const GameSession = preload("res://scripts/core/game_session.gd")
const StartMenu = preload("res://scripts/view/start_menu.gd")
const TownScene = preload("res://scenes/town.tscn")
const FightScene = preload("res://scenes/main.tscn")

var screen: Node
var session


func _ready() -> void:
	session = GameSession.get_current()
	show_menu()


## Screen signals are connected deferred, so a screen is never freed while
## it is still handling the tap that asked for the switch.
func _swap(next: Node) -> void:
	if screen != null:
		screen.queue_free()
		remove_child(screen)
	screen = next
	add_child(screen)


func show_menu() -> void:
	var m = StartMenu.new()
	m.town_pressed.connect(show_town, CONNECT_DEFERRED)
	m.fight_pressed.connect(start_direct_fight, CONNECT_DEFERRED)
	_swap(m)


func show_town() -> void:
	var t = TownScene.instantiate()
	t.fight_requested.connect(start_town_fight, CONNECT_DEFERRED)
	t.menu_requested.connect(show_menu, CONNECT_DEFERRED)
	_swap(t)


func start_town_fight(request: Dictionary) -> void:
	session.begin_fight(request, screen.current_spot())
	_show_fight()


func start_direct_fight() -> void:
	session.begin_direct_fight()
	_show_fight()


func _show_fight() -> void:
	var f = FightScene.instantiate()
	f.encounter_id = session.encounter_id()
	f.from_town = session.fight.get("from_town", false)
	f.fight_finished.connect(_on_fight_finished, CONNECT_DEFERRED)
	f.menu_requested.connect(show_menu, CONNECT_DEFERRED)
	_swap(f)


func _on_fight_finished(won: bool) -> void:
	if session.end_fight(won):
		show_town()
	else:
		show_menu()
