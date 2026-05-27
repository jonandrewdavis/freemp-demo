extends CharacterBody3D

enum InputMode {
	LOCAL,
	REMOTE
}

const MOVE_SPEED := 8.0
const ROTATE_SPEED := 3.0

var _input_mode := InputMode.LOCAL


func set_input_mode( mode: InputMode ) -> void:
	_input_mode = mode


func set_position_and_rotation( pos: Vector3, rot: Vector3 ) -> void:
	set_input_mode( InputMode.REMOTE )
	global_position = pos
	global_rotation = rot
	velocity = Vector3.ZERO


func _physics_process( delta: float ) -> void:
	if _input_mode == InputMode.LOCAL:
		var rotate_input = Input.get_axis( "move_left", "move_right" )
		if abs( rotate_input ) >= 0.01:
			rotate_y( -rotate_input * ROTATE_SPEED * delta )

		var move_input = Input.get_axis( "move_back", "move_forward" )
		var move_dir = -transform.basis.z * move_input
		velocity.x = move_dir.x * MOVE_SPEED
		velocity.z = move_dir.z * MOVE_SPEED

		if not is_on_floor():
			velocity += get_gravity() * delta
		else:
			velocity.y = 0

		move_and_slide()
