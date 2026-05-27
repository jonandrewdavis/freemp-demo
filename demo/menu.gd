extends Control

var host_input: LineEdit
var port_input: LineEdit
var use_ssl_check: CheckBox
var account_id_input: LineEdit
var account_key_input: LineEdit

func _ready() -> void:
	host_input = find_child( "HostInput", true )
	port_input = find_child( "PortInput", true )
	use_ssl_check = find_child( "UseSslCheckBox", true )
	account_id_input = find_child( "AccountIdInput", true )
	account_key_input = find_child( "AccountKeyInput", true )
	_update_dev_ui( false )

func _update_dev_ui( show_containers: bool ) -> void:
	find_child( "HostContainer", true ).visible = show_containers
	find_child( "AccountContainer", true ).visible = show_containers

func _on_join_game_pressed() -> void:
	var game_id: String = find_child( "GameIdInput", true ).text.strip_edges()
	if game_id.is_empty():
		return
	GameSession.join_game_id = game_id
	go_game()

func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_dev_mode_toggled( toggled_on: bool ) -> void:
	GameSession.dev_mode = toggled_on
	if toggled_on:
		host_input.text = "localhost"
		port_input.text = "12345"
		use_ssl_check.button_pressed = false
	else:
		host_input.text = "freemp.sleepless.com"
		port_input.text = "443"
		use_ssl_check.button_pressed = true
	_update_dev_ui( toggled_on )

func go_game() -> void:
	GameSession.host = host_input.text.strip_edges()
	GameSession.use_ssl = use_ssl_check.button_pressed
	GameSession.account_id = account_id_input.text.strip_edges()
	GameSession.access_key = account_key_input.text.strip_edges()
	var port_str: String = port_input.text.strip_edges()
	GameSession.port = int( port_str ) if port_str.is_valid_int() else 12345

	# hide the widgets node and show the loading node, then defer to next frame to change to the game scene
	find_child( "widgets", true ).visible = false
	find_child( "loading", true ).visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file( "res://demo/game.tscn" )
