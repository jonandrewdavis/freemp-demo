
# Copyright 2026
# Sleepless Software Inc.
# All Rights Reserved

extends Node

signal ws_connected( reconnect_attempt: int )
signal ws_disconnected
signal ws_error( detail: Variant )
signal ws_message( msg_in: Dictionary )

@export var host: String = "example.com"
@export var port: int = 443
@export var use_ssl: bool = true
@export var account_id: String = "example_id"
@export var access_key: String = "example_key"
@export var debug: bool = false

var connected_to_server: bool = false:
	set( v ):
		connected_to_server = v
		if v:
			ws_connected.emit( _reconnect_attempt )
			if _on_connect_callback.is_valid():
				_on_connect_callback.call()
				_on_connect_callback = Callable()

var _seq: int = 0
var _waiting: Dictionary = {}  # msg_id -> { expire: float, msg: Dictionary, okay: Callable, fail: Callable }
var _waiting_cleanup_timer: float = 0.0
var _on_connect_callback: Callable = Callable()
var _socket := WebSocketPeer.new()
var _intentional_disconnect := false
var _reconnect_timer: Timer
var _connection_emitted := false
var _reconnect_attempt := 0


func _ready() -> void:
	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect( _on_reconnect_timer_timeout )
	add_child( _reconnect_timer )
	set_process( false )


func _process( delta: float ) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _connection_emitted:
			_connection_emitted = true
			connected_to_server = true
			_dbg( "Event: connect" )
		while _socket.get_available_packet_count():
			var packet := _socket.get_packet()
			if _socket.was_string_packet():
				_on_ws_text( packet.get_string_from_utf8() )
		# Clean up expired waiting entries every ~10 seconds
		_waiting_cleanup_timer += delta
		if _waiting_cleanup_timer >= 10.0:
			_waiting_cleanup_timer = 0.0
			var now := Time.get_unix_time_from_system()
			for id in _waiting.keys():
				if now >= _waiting[id].expire:
					_dbg( "cleanup: expired waiting", [ id ] )
					_waiting.erase( id )
	elif state == WebSocketPeer.STATE_CLOSING:
		pass
	elif state == WebSocketPeer.STATE_CLOSED:
		_connection_emitted = false
		connected_to_server = false
		ws_disconnected.emit()
		_dbg( "Event: disconnect" )
		set_process( false )
		if not _intentional_disconnect:
			_reconnect_timer.start( 2.0 )


func _dbg( msg: String, args: Array = [] ) -> void:
	if debug:
		var parts: Array = [ "FreeMP:", msg ]
		parts.append_array( args )
		print( parts )


func _next_seq() -> int:
	_seq += 1
	return _seq


## Initiates WebSocket connection using host, port, use_ssl. Returns OK on success.
func connect_to_server( from_reconnect: bool = false ) -> Error:
	if not from_reconnect:
		_reconnect_attempt = 0
	_connection_emitted = false
	_intentional_disconnect = false
	var scheme = "wss" if use_ssl else "ws"
	var path = "rpc/" + account_id + "/" + access_key
	var url = "%s://%s:%d/%s" % [ scheme, host, port, path ]
	_dbg( "Connecting to ", [ url ] )
	var err: Error = _socket.connect_to_url( url )
	if err == OK:
		set_process( true )
	elif not _intentional_disconnect:
		_dbg( "connect failed, will retry", [ err ] )
		set_process( false )
		_reconnect_timer.start( 2.0 )
	return err


## Closes WebSocket. Marks as intentional so auto-reconnect is not triggered.
func disconnect_from_server( code: int = 1000, reason: String = "" ) -> void:
	_dbg( "disconnect_from_server", [ code, reason ] )
	_intentional_disconnect = true
	_socket.close( code, reason )


## Returns true if WebSocket is open and ready for send/receive.
func is_connected_to_host() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


## Call callback when connected. If already connected, calls immediately.
func when_connected( cb: Callable ) -> void:
	if connected_to_server:
		_dbg( "when_connected: already connected, calling now" )
		cb.call()
	else:
		_dbg( "when_connected: deferring until connect" )
		_on_connect_callback = cb


## Send message via WebSocket.
func request( msg: Dictionary, okay: Callable = Callable(), fail: Callable = Callable() ) -> void:
	ws( msg, okay, fail )


## Send message via WebSocket.
func ws( msg: Dictionary, okay: Callable = Callable(), fail: Callable = Callable() ) -> void:
	var wrapped: Dictionary = { "msg": msg }
	if not wrapped.has( "msg_id" ):
		wrapped["msg_id"] = "CMID-%d" % _next_seq()

	if okay.is_valid() or fail.is_valid():
		_waiting[wrapped["msg_id"]] = {
			"expire": Time.get_unix_time_from_system() + 60,
			"msg": wrapped,
			"okay": okay,
			"fail": fail
		}

	# Wait for socket to be open (up to 10 seconds)
	const MAX_WAIT := 10.0
	var waited := 0.0
	while _socket.get_ready_state() != WebSocketPeer.STATE_OPEN and waited < MAX_WAIT:
		await get_tree().create_timer( 0.2 ).timeout
		waited += 0.2

	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_dbg( "ws: connection timeout", [ wrapped["msg_id"] ] )
		var w: Variant = _waiting.get( wrapped["msg_id"] )
		if w:
			_waiting.erase( wrapped["msg_id"] )
			if w.fail.is_valid():
				w.fail.call( "WebSocket connection timeout after %.0f ms" % ( MAX_WAIT * 1000 ) )
		return

	var err: Error = _socket.send_text( JSON.stringify( wrapped ) )
	if err != OK:
		_dbg( "ws: send failed", [ wrapped["msg_id"], err ] )
		var w: Variant = _waiting.get( wrapped["msg_id"] )
		if w:
			_waiting.erase( wrapped["msg_id"] )
			if w.fail.is_valid():
				w.fail.call( "Send failed: %d" % err )
		return

	_dbg( ">>--->", [ wrapped, _socket.get_ready_state() ] )


func _on_reconnect_timer_timeout() -> void:
	_dbg( "reconnect: attempting" )
	_reconnect_attempt += 1
	_socket = WebSocketPeer.new()
	_intentional_disconnect = false
	set_process( true )
	var err: Error = connect_to_server( true )
	if err != OK:
		_dbg( "reconnect: failed", [ err ] )
		set_process( false )
		_reconnect_timer.start( 2.0 )


func _on_ws_text( text: String ) -> void:
	var msg_in = JSON.parse_string( text )
	if msg_in == null:
		ws_error.emit( "unreadable message" )
		_dbg( "error: unreadable message" )
		return
	if not ( msg_in is Dictionary ):
		ws_error.emit( "invalid message: expected JSON object" )
		_dbg( "error: invalid message, expected JSON object", [ msg_in ] )
		return

	_dbg( "<---<<", [ msg_in ] )

	# Error response to client-initiated message
	if msg_in is Dictionary and msg_in.has( "error" ):
		_dbg( "ws: error response", [ msg_in.msg_id, msg_in.error ] )
		var x = _waiting.get( msg_in.msg_id )
		if not x:
			_dbg( "warning: invalid reply", [ msg_in.msg_id ] )
			return
		_waiting.erase( msg_in.msg_id )
		if x.fail.is_valid():
			x.fail.call( msg_in.error )
		return

	# Normal response to client-initiated message
	if msg_in is Dictionary and msg_in.has( "response" ):
		_dbg( "ws: ok response", [ msg_in.msg_id ] )
		var x = _waiting.get( msg_in.msg_id )
		if not x:
			_dbg( "warning: invalid reply", [ msg_in.msg_id ] )
			return
		_waiting.erase( msg_in.msg_id )
		if x.okay.is_valid():
			x.okay.call( msg_in.response )
		return

	# Server-initiated message (has msg, not response/error)
	if msg_in is Dictionary and msg_in.has( "msg" ):
		_dbg( "ws: server message", [ msg_in ] )
		ws_message.emit( msg_in )
		return

	ws_error.emit( [ "invalid message", msg_in ] )
	_dbg( "error: invalid message", [ msg_in ] )
