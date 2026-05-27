extends Node3D

# Demonstration of the FreeMP addon: WebSocket-based messaging with request/response
# and server-initiated broadcasts

var _place_id: String = ""		#  place_id (game id) to join

# This dictionary tracks remote players by their client_id.
var _remote_players: Dictionary = {}
const REMOTE_TIMEOUT := 5.0  # seconds of silence after which remote player is removed
const PLAYER_SCENE := preload( "res://demo/player.tscn" )	# instantiated for remote players

# Timer for sending position updates of the local player to the server
const POSITION_SEND_INTERVAL := 0.1  # 0.1 = 10 times per second, 1.0 = 1 time per second
var _position_send_timer := 0.0

# State machine for the game
enum State {
	WAIT_CONNECT, # waiting for server connection
	WAIT_JOIN_PLACE, # waiting for join place response
	PLAYING, # playing the game
	RETURNING_TO_MENU, # returning to menu
}
# Timeouts for each state
var state_timeouts: Dictionary = {
	State.WAIT_CONNECT: 20.0,
	State.WAIT_JOIN_PLACE: 10.0,
	State.PLAYING: 0.0,
	State.RETURNING_TO_MENU: 2.0,
}
var state = State.WAIT_CONNECT
var _timeout = 0.0

# Set the text of the overlay message
func set_message( msg: String ) -> void:
	print( msg )  # also print to console
	var message_label: Label = find_child( "message", true ) as Label
	message_label.text = msg

# change to a new state, show message, and set state timeout
func _change_state( new_state: State, msg: String = "" ) -> void:
	print( "changing state to: ", new_state )
	self.state = new_state
	set_message( msg )
	_timeout = 0

# general use error handler
func _fail( err: String ) -> void:
	_change_state( State.RETURNING_TO_MENU, err )

# actually return to the menu scene
func _return_to_menu() -> void:
	# Disconnect signal handler before disconnecting, or ws_message can fire during teardown
	if FreeMP.ws_message.is_connected( _on_freemp_message ):
		FreeMP.ws_message.disconnect( _on_freemp_message )
	FreeMP.disconnect_from_server()
	var tree := get_tree()
	if tree:
		tree.change_scene_to_file( "res://demo/menu.tscn" )  # go back to menu

# handle the ESCAPE key to return to the menu
func _unhandled_input( event: InputEvent ) -> void:
	if event.is_action_pressed( "ui_cancel" ):
		_change_state( State.RETURNING_TO_MENU, "Returning to menu" )

# called by FreeMP when connection is lost
func _on_connection_lost() -> void:
	_change_state( State.WAIT_CONNECT, "Reconnecting ..." )

func _on_connected( _reconnect_attempt: int = 0 ) -> void:
	FreeMP.ws( { "action": "join_place", "place_id": _place_id }, _on_join_place_done, _fail )
	_change_state( State.WAIT_JOIN_PLACE, "Joining " + _place_id + " ..." )

# Called when join_place request succeeds
func _on_join_place_done( response: Dictionary ) -> void:
	# check for error attribute
	if response.has( "error" ):
		_fail( response.error )
		return
	var you: Dictionary = response.get( "you", {} ) as Dictionary
	var client_id: String = you.get( "client_id", "" )
	$Player.get_node( "client_id" ).text = client_id
	var place: Dictionary = response.get( "place", {} ) as Dictionary
	_change_state( State.PLAYING, "You joined " + place.get( "id", "" ) )

# Called for server-initiated messages (not responses to client initiated messages)
# Client-initiated requests use the okay/fail callbacks passed to FreeMP.ws() instead.
func _on_freemp_message( msg_in: Dictionary ) -> void:
	var msg: Dictionary = msg_in.get( "msg", {} ) as Dictionary

	if msg.get( "action", "" ) == "bcast":
		var from_id: String = msg.get( "from", "" )
		var payload: Dictionary = msg.get( "payload", {} )
		var pos_dict: Dictionary = payload.get( "position", {} )
		var rot_dict: Dictionary = payload.get( "rotation", {} )
		var pos := Vector3( pos_dict.get( "x", 0.0 ), pos_dict.get( "y", 0.0 ), pos_dict.get( "z", 0.0 ) )
		var rot := Vector3( rot_dict.get( "x", 0.0 ), rot_dict.get( "y", 0.0 ), rot_dict.get( "z", 0.0 ) )
		var remote: Dictionary
		if _remote_players.has( from_id ):
			# update existing remote player
			remote = _remote_players[ from_id ]
		else:
			# create game object for newly appearing remote player
			var remote_player: CharacterBody3D = PLAYER_SCENE.instantiate()
			remote_player.get_node( "client_id" ).text = from_id
			remote_player.set_input_mode( remote_player.InputMode.REMOTE )
			add_child( remote_player ) # add to scene
			# add to tracking dictionary for timing them out if they stop talking
			remote = { "player": remote_player, "last_heard": 0.0 } 
			_remote_players[ from_id ] = remote
			set_message( "New player joined: " + from_id )
		# updat the info for the new or existing remote player
		remote.player.set_position_and_rotation( pos, rot )
		remote.last_heard = Time.get_unix_time_from_system()


func _ready() -> void:
	print( "ready" )
	_place_id = GameSession.join_game_id

	# Mitigate spawning on top of other players
	$Player.global_position = Vector3( randf_range( -15, 15 ), $Player.global_position.y, randf_range( -15, 15 ) )

	# Configure FreeMP before connecting
	# FreeMP.debug = true
	FreeMP.host = GameSession.host
	FreeMP.port = GameSession.port
	FreeMP.account_id = GameSession.account_id
	FreeMP.access_key = GameSession.access_key
	FreeMP.use_ssl = GameSession.use_ssl

	# Connect  signals
	FreeMP.ws_message.connect( _on_freemp_message )  # For server broadcasts and push messages
	FreeMP.ws_connected.connect( _on_connected )
	FreeMP.ws_disconnected.connect( _on_connection_lost )

	# Actually initiate the connection to the server
	FreeMP.connect_to_server()

	var url = "ws" + ( "s" if GameSession.use_ssl else "" ) + "://" + GameSession.host + ":" + str( GameSession.port ) + " as " + GameSession.account_id + " / " + GameSession.access_key
	print( url )
	_change_state( State.WAIT_CONNECT, "Connecting to " + GameSession.host + " ..." )

func _process_playing( delta: float ) -> void:

	# look for and remove remote players that haven't been heard from in a while
	var now := Time.get_unix_time_from_system()
	var to_remove: Array = []
	for from_id in _remote_players.keys():
		if now - _remote_players[from_id].last_heard >= REMOTE_TIMEOUT:
			to_remove.append( from_id )  # mark timed-out remote players
	for from_id in to_remove:
		_remote_players[from_id].player.queue_free()
		_remote_players.erase( from_id )  # remove timed-out remotes
		set_message( "Player left: " + from_id )

	# broadcast position periodically
	_position_send_timer -= delta
	if _position_send_timer <= 0:
		_position_send_timer = POSITION_SEND_INTERVAL	# reset timer
		var local_player: CharacterBody3D = $Player
		var pos := local_player.global_position
		var rot := local_player.global_rotation
		var payload := {
			"position": { "x": pos.x, "y": pos.y, "z": pos.z },
			"rotation": { "x": rot.x, "y": rot.y, "z": rot.z }
		}
		# Fire-and-forget local player's state (no callbacks). 
		# Server broadcasts this to the players in the same place.
		# they receive it via ws_message signal
		FreeMP.ws( { "action": "bcast", "payload": payload } )

func _process( delta: float ) -> void:
	if state == State.PLAYING:
		# normal playing state
		_process_playing( delta )
	else:
		# This is state that may time out
		_timeout += delta
		if _timeout >= state_timeouts[ state ]:
			if state != State.RETURNING_TO_MENU:
				print( "state timeout: ", state )
				_change_state( State.RETURNING_TO_MENU, "Timeout" )
			else:
				_return_to_menu()
			return
