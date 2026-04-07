extends Node2D

@export var gravity: float = 1800.0
@export var step_impulse: float = 145.0
@export var max_speed: float = 320.0
@export var ground_friction: float = 1900.0
@export var air_drag: float = 260.0
@export var hip_speed: float = 10.0
@export var knee_speed: float = 14.0
@export var torso_follow_speed: float = 8.0
@export var hold_balance_decay: float = 0.55
@export var idle_balance_recover: float = 0.30
@export var stumble_balance_penalty: float = 0.28

const FLOOR_Y: float = 620.0
const GROUND_TOP_Y: float = 580.0
const START_POS: Vector2 = Vector2(240.0, GROUND_TOP_Y)
const CAMERA_OFFSET: Vector2 = Vector2(240.0, -120.0)

const THIGH_LEN: float = 46.0
const CALF_LEN: float = 42.0

var player: CharacterBody2D
var cam: Camera2D
var hud: Label

var visuals: Node2D
var torso: Node2D
var head_marker: Node2D
var left_thigh: Node2D
var right_thigh: Node2D
var left_calf: Node2D
var right_calf: Node2D
var left_foot: Node2D
var right_foot: Node2D

var best_distance: float = 0.0
var balance: float = 1.0

var last_pair: String = ""
var forward_phase: int = 0
var backward_phase: int = 0

var is_falling: bool = false
var is_dead: bool = false
var collapse_direction: float = 1.0


func _ready() -> void:
	_build_world()
	_spawn_player()


func _process(delta: float) -> void:
	if cam != null and player != null:
		var cam_target: Vector2 = player.global_position + CAMERA_OFFSET
		cam.global_position = cam.global_position.lerp(cam_target, minf(1.0, delta * 5.0))

	if hud != null and player != null:
		var q_down: bool = Input.is_physical_key_pressed(KEY_Q)
		var w_down: bool = Input.is_physical_key_pressed(KEY_W)
		var o_down: bool = Input.is_physical_key_pressed(KEY_O)
		var p_down: bool = Input.is_physical_key_pressed(KEY_P)

		var distance: float = maxf(0.0, (player.global_position.x - START_POS.x) / 12.0)
		best_distance = maxf(best_distance, distance)

		var status: String = "RUNNING"
		if is_falling:
			status = "FALLING"
		elif is_dead:
			status = "DEAD"

		hud.text = (
			"Q/W = thighs   O/P = calves   R = reset\n"
			+ "Forward: alternate Q+P -> W+O\n"
			+ "Backward: alternate Q+O -> W+P\n"
			+ "Status: %s   Balance: %.2f\n" % [status, balance]
			+ "Q:%s  W:%s  O:%s  P:%s\n" % [str(q_down), str(w_down), str(o_down), str(p_down)]
			+ "Distance: %.1f   Best: %.1f" % [distance, best_distance]
		)


func _physics_process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_R):
		_spawn_player()
		return

	if player == null:
		return

	var q_down: bool = Input.is_physical_key_pressed(KEY_Q)
	var w_down: bool = Input.is_physical_key_pressed(KEY_W)
	var o_down: bool = Input.is_physical_key_pressed(KEY_O)
	var p_down: bool = Input.is_physical_key_pressed(KEY_P)

	if is_dead:
		return

	if is_falling:
		_update_fall(delta)
		return

	_update_pose(delta, q_down, w_down, o_down, p_down)

	if not player.is_on_floor():
		player.velocity.y += gravity * delta
		player.velocity.x = _approach(player.velocity.x, 0.0, air_drag * delta)
	else:
		if player.velocity.y > 0.0:
			player.velocity.y = 0.0

		_handle_stride_input(delta, q_down, w_down, o_down, p_down)

	player.velocity.x = clampf(player.velocity.x, -max_speed, max_speed)
	player.move_and_slide()

	_update_live_lean(delta)

	if balance <= 0.0:
		_start_fall(_sign_from_motion())
		return


func _update_pose(delta: float, q_down: bool, w_down: bool, o_down: bool, p_down: bool) -> void:
	var left_hip_target: float = 0.30
	var right_hip_target: float = -0.30

	if q_down:
		left_hip_target = 0.95
		right_hip_target = -0.55
	elif w_down:
		left_hip_target = -0.55
		right_hip_target = 0.95

	var left_knee_target: float = 0.55
	var right_knee_target: float = 0.55

	if o_down:
		left_knee_target = 0.15
		right_knee_target = 1.10
	elif p_down:
		left_knee_target = 1.10
		right_knee_target = 0.15

	left_thigh.rotation = lerp_angle(left_thigh.rotation, left_hip_target, minf(1.0, delta * hip_speed))
	right_thigh.rotation = lerp_angle(right_thigh.rotation, right_hip_target, minf(1.0, delta * hip_speed))
	left_calf.rotation = lerp_angle(left_calf.rotation, left_knee_target, minf(1.0, delta * knee_speed))
	right_calf.rotation = lerp_angle(right_calf.rotation, right_knee_target, minf(1.0, delta * knee_speed))

	var left_foot_target: float = -left_calf.rotation * 0.55
	var right_foot_target: float = -right_calf.rotation * 0.55
	left_foot.rotation = lerp_angle(left_foot.rotation, left_foot_target, minf(1.0, delta * 12.0))
	right_foot.rotation = lerp_angle(right_foot.rotation, right_foot_target, minf(1.0, delta * 12.0))

	var torso_target: float = clampf(
		(player.velocity.x / max_speed) * 0.18 + (right_thigh.rotation - left_thigh.rotation) * 0.12,
		-0.30,
		0.30
	)
	torso.rotation = lerp_angle(torso.rotation, torso_target, minf(1.0, delta * torso_follow_speed))


func _handle_stride_input(delta: float, q_down: bool, w_down: bool, o_down: bool, p_down: bool) -> void:
	if (q_down and w_down) or (o_down and p_down):
		balance = maxf(0.0, balance - 0.70 * delta)

	var pair: String = _get_pair(q_down, w_down, o_down, p_down)

	if pair == "":
		last_pair = ""
		balance = minf(1.0, balance + idle_balance_recover * delta)
		player.velocity.x = _approach(player.velocity.x, 0.0, ground_friction * delta)
		return

	if pair == last_pair:
		balance = maxf(0.0, balance - hold_balance_decay * delta)
		return

	last_pair = pair

	match pair:
		"QP":
			if forward_phase == 0:
				player.velocity.x += step_impulse
				forward_phase = 1
				backward_phase = 0
				balance = minf(1.0, balance + 0.08)
			else:
				_stumble(1.0)

		"WO":
			if forward_phase == 1:
				player.velocity.x += step_impulse
				forward_phase = 0
				backward_phase = 0
				balance = minf(1.0, balance + 0.08)
			else:
				_stumble(1.0)

		"QO":
			if backward_phase == 0:
				player.velocity.x -= step_impulse
				backward_phase = 1
				forward_phase = 0
				balance = minf(1.0, balance + 0.06)
			else:
				_stumble(-1.0)

		"WP":
			if backward_phase == 1:
				player.velocity.x -= step_impulse
				backward_phase = 0
				forward_phase = 0
				balance = minf(1.0, balance + 0.06)
			else:
				_stumble(-1.0)


func _update_live_lean(delta: float) -> void:
	var stride_lean: float = clampf(
		(player.velocity.x / max_speed) * 0.22 + (right_thigh.rotation - left_thigh.rotation) * 0.12,
		-0.45,
		0.45
	)

	var wobble: float = (1.0 - balance) * 0.50 * _sign_or_default(stride_lean, _sign_from_motion())
	var target_visual_rotation: float = clampf(stride_lean + wobble, -1.00, 1.00)

	visuals.rotation = lerp_angle(
		visuals.rotation,
		target_visual_rotation,
		minf(1.0, delta * torso_follow_speed)
	)


func _stumble(direction: float) -> void:
	player.velocity.x += direction * 30.0
	balance = maxf(0.0, balance - stumble_balance_penalty)
	visuals.rotation = clampf(visuals.rotation + direction * 0.16, -1.10, 1.10)


func _start_fall(direction: float) -> void:
	is_falling = true
	collapse_direction = direction
	player.velocity.x *= 0.65


func _update_fall(delta: float) -> void:
	player.velocity.x = _approach(player.velocity.x, 0.0, 700.0 * delta)
	player.position.x += player.velocity.x * delta

	visuals.rotation = lerp_angle(
		visuals.rotation,
		collapse_direction * 1.58,
		minf(1.0, delta * 4.2)
	)

	torso.rotation = lerp_angle(
		torso.rotation,
		collapse_direction * 0.18,
		minf(1.0, delta * 5.0)
	)

	left_thigh.rotation = lerp_angle(left_thigh.rotation, 0.85 * collapse_direction, minf(1.0, delta * 4.5))
	right_thigh.rotation = lerp_angle(right_thigh.rotation, 0.55 * collapse_direction, minf(1.0, delta * 4.5))
	left_calf.rotation = lerp_angle(left_calf.rotation, 1.15, minf(1.0, delta * 4.5))
	right_calf.rotation = lerp_angle(right_calf.rotation, 0.95, minf(1.0, delta * 4.5))
	left_foot.rotation = lerp_angle(left_foot.rotation, 0.10, minf(1.0, delta * 4.5))
	right_foot.rotation = lerp_angle(right_foot.rotation, 0.10, minf(1.0, delta * 4.5))

	if head_marker != null and head_marker.global_position.y >= GROUND_TOP_Y - 2.0:
		is_falling = false
		is_dead = true


func _get_pair(q_down: bool, w_down: bool, o_down: bool, p_down: bool) -> String:
	if q_down and p_down and not w_down and not o_down:
		return "QP"
	if w_down and o_down and not q_down and not p_down:
		return "WO"
	if q_down and o_down and not w_down and not p_down:
		return "QO"
	if w_down and p_down and not q_down and not o_down:
		return "WP"
	return ""


func _build_world() -> void:
	cam = Camera2D.new()
	cam.enabled = true
	add_child(cam)

	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)

	hud = Label.new()
	hud.position = Vector2(16.0, 16.0)
	canvas.add_child(hud)

	var ground: StaticBody2D = StaticBody2D.new()
	ground.position = Vector2(1800.0, FLOOR_Y)
	add_child(ground)

	var ground_shape: CollisionShape2D = CollisionShape2D.new()
	var ground_rect: RectangleShape2D = RectangleShape2D.new()
	ground_rect.size = Vector2(5000.0, 80.0)
	ground_shape.shape = ground_rect
	ground.add_child(ground_shape)

	var ground_poly: Polygon2D = Polygon2D.new()
	ground_poly.polygon = PackedVector2Array([
		Vector2(-2500.0, -40.0),
		Vector2(2500.0, -40.0),
		Vector2(2500.0, 40.0),
		Vector2(-2500.0, 40.0),
	])
	ground_poly.color = Color(0.17, 0.17, 0.18)
	ground.add_child(ground_poly)

	for i: int in range(0, 20):
		var mark: Polygon2D = Polygon2D.new()
		var x: float = 100.0 + float(i) * 250.0
		mark.position = Vector2(x, GROUND_TOP_Y - 3.0)
		mark.polygon = PackedVector2Array([
			Vector2(-20.0, -2.0),
			Vector2(20.0, -2.0),
			Vector2(20.0, 2.0),
			Vector2(-20.0, 2.0),
		])
		mark.color = Color(0.55, 0.55, 0.58)
		add_child(mark)


func _spawn_player() -> void:
	if player != null:
		player.queue_free()

	player = CharacterBody2D.new()
	player.position = START_POS
	player.floor_snap_length = 18.0
	player.up_direction = Vector2.UP
	add_child(player)

	var collider: CollisionShape2D = CollisionShape2D.new()
	var body_shape: RectangleShape2D = RectangleShape2D.new()
	body_shape.size = Vector2(34.0, 112.0)
	collider.shape = body_shape
	collider.position = Vector2(0.0, -56.0)
	player.add_child(collider)

	visuals = Node2D.new()
	player.add_child(visuals)

	torso = Node2D.new()
	torso.position = Vector2(0.0, -94.0)
	visuals.add_child(torso)

	_add_centered_rect(torso, Vector2(0.0, 18.0), Vector2(34.0, 76.0), Color(0.24, 0.48, 0.86))
	_add_centered_rect(torso, Vector2(0.0, -28.0), Vector2(24.0, 24.0), Color(0.93, 0.82, 0.68))

	head_marker = Node2D.new()
	head_marker.position = Vector2(0.0, -40.0)
	torso.add_child(head_marker)

	left_thigh = _make_segment_pivot(visuals, "LeftThigh", THIGH_LEN, 14.0, Color(0.88, 0.43, 0.24))
	left_thigh.position = Vector2(-10.0, -54.0)

	left_calf = _make_segment_pivot(left_thigh, "LeftCalf", CALF_LEN, 12.0, Color(0.96, 0.71, 0.24))
	left_calf.position = Vector2(0.0, THIGH_LEN)

	left_foot = _make_foot_pivot(left_calf, "LeftFoot", Color(0.94, 0.86, 0.56))
	left_foot.position = Vector2(0.0, CALF_LEN)

	right_thigh = _make_segment_pivot(visuals, "RightThigh", THIGH_LEN, 14.0, Color(0.84, 0.31, 0.23))
	right_thigh.position = Vector2(10.0, -54.0)

	right_calf = _make_segment_pivot(right_thigh, "RightCalf", CALF_LEN, 12.0, Color(0.96, 0.63, 0.18))
	right_calf.position = Vector2(0.0, THIGH_LEN)

	right_foot = _make_foot_pivot(right_calf, "RightFoot", Color(0.92, 0.82, 0.50))
	right_foot.position = Vector2(0.0, CALF_LEN)

	left_thigh.rotation = 0.58
	right_thigh.rotation = -0.20
	left_calf.rotation = 0.72
	right_calf.rotation = 0.24
	left_foot.rotation = -0.25
	right_foot.rotation = -0.10
	torso.rotation = 0.02
	visuals.rotation = 0.0

	player.velocity = Vector2.ZERO
	balance = 1.0
	last_pair = ""
	forward_phase = 0
	backward_phase = 0
	is_falling = false
	is_dead = false
	collapse_direction = 1.0

	if cam != null:
		cam.global_position = player.global_position + CAMERA_OFFSET


func _add_centered_rect(parent: Node, rect_pos: Vector2, size: Vector2, color: Color) -> Polygon2D:
	var poly: Polygon2D = Polygon2D.new()
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	poly.position = rect_pos
	poly.polygon = PackedVector2Array([
		Vector2(-hx, -hy),
		Vector2(hx, -hy),
		Vector2(hx, hy),
		Vector2(-hx, hy),
	])
	poly.color = color
	parent.add_child(poly)
	return poly


func _make_segment_pivot(parent: Node, segment_name: String, length: float, thickness: float, color: Color) -> Node2D:
	var pivot: Node2D = Node2D.new()
	pivot.name = segment_name
	parent.add_child(pivot)

	var half_thickness: float = thickness * 0.5

	var poly: Polygon2D = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-half_thickness, 0.0),
		Vector2(half_thickness, 0.0),
		Vector2(half_thickness, length),
		Vector2(-half_thickness, length),
	])
	poly.color = color
	pivot.add_child(poly)

	return pivot


func _make_foot_pivot(parent: Node, foot_name: String, color: Color) -> Node2D:
	var pivot: Node2D = Node2D.new()
	pivot.name = foot_name
	parent.add_child(pivot)

	var poly: Polygon2D = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-8.0, 0.0),
		Vector2(28.0, 0.0),
		Vector2(28.0, 10.0),
		Vector2(-8.0, 10.0),
	])
	poly.color = color
	pivot.add_child(poly)

	return pivot


func _approach(value: float, target: float, amount: float) -> float:
	if value < target:
		return minf(value + amount, target)
	elif value > target:
		return maxf(value - amount, target)
	return target


func _sign_from_motion() -> float:
	if player != null and absf(player.velocity.x) > 5.0:
		if player.velocity.x < 0.0:
			return -1.0
		return 1.0

	if visuals != null and visuals.rotation < 0.0:
		return -1.0

	return 1.0


func _sign_or_default(value: float, fallback: float) -> float:
	if value < -0.001:
		return -1.0
	if value > 0.001:
		return 1.0
	return fallback
