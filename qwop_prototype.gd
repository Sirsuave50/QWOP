extends Node2D

@export var hip_strength: float = 7800.0
@export var hip_damping: float = 420.0
@export var knee_strength: float = 6200.0
@export var knee_damping: float = 320.0
@export var ankle_strength: float = 3400.0
@export var ankle_damping: float = 220.0
@export var torso_upright_strength: float = 9500.0
@export var torso_upright_damping: float = 520.0

const FLOOR_Y: float = 620.0
const START_X: float = 280.0
const CAMERA_OFFSET: Vector2 = Vector2(240, -120)

var runner_root: Node2D
var torso: RigidBody2D
var left_thigh: RigidBody2D
var right_thigh: RigidBody2D
var left_calf: RigidBody2D
var right_calf: RigidBody2D
var left_foot: RigidBody2D
var right_foot: RigidBody2D

var cam: Camera2D
var hud: Label
var best_distance: float = 0.0


func _ready() -> void:
	_build_world()
	_spawn_runner()


func _process(delta: float) -> void:
	if cam != null and torso != null:
		var target: Vector2 = torso.global_position + CAMERA_OFFSET
		cam.global_position = cam.global_position.lerp(target, minf(1.0, delta * 5.0))

	if hud != null and torso != null:
		var distance: float = maxf(0.0, (torso.global_position.x - START_X) / 12.0)
		best_distance = maxf(best_distance, distance)

		var q_down: bool = Input.is_physical_key_pressed(KEY_Q)
		var w_down: bool = Input.is_physical_key_pressed(KEY_W)
		var o_down: bool = Input.is_physical_key_pressed(KEY_O)
		var p_down: bool = Input.is_physical_key_pressed(KEY_P)

		hud.text = (
			"Q/W = hips    O/P = knees    R = reset\n"
			+ "Q:%s  W:%s  O:%s  P:%s\n" % [str(q_down), str(w_down), str(o_down), str(p_down)]
			+ "Distance: %.1f    Best: %.1f" % [distance, best_distance]
	)


func _physics_process(_delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_R):
		_spawn_runner()
		return

	if torso == null:
		return

	if torso.global_position.y > 1200.0:
		_spawn_runner()
		return

	var q_down: bool = Input.is_physical_key_pressed(KEY_Q)
	var w_down: bool = Input.is_physical_key_pressed(KEY_W)
	var o_down: bool = Input.is_physical_key_pressed(KEY_O)
	var p_down: bool = Input.is_physical_key_pressed(KEY_P)

	var left_hip_target: float = 0.20
	var right_hip_target: float = -0.10

	if q_down:
		left_hip_target = 0.95
		right_hip_target = -0.60
	elif w_down:
		left_hip_target = -0.55
		right_hip_target = 0.95

	_drive_joint(left_thigh, torso, left_hip_target, hip_strength, hip_damping)
	_drive_joint(right_thigh, torso, right_hip_target, hip_strength, hip_damping)

	var left_knee_target: float = 0.35
	var right_knee_target: float = 0.35

	if o_down:
		left_knee_target = 0.95
		right_knee_target = 0.10
	elif p_down:
		left_knee_target = 0.10
		right_knee_target = 0.95

	_drive_joint(left_calf, left_thigh, left_knee_target, knee_strength, knee_damping)
	_drive_joint(right_calf, right_thigh, right_knee_target, knee_strength, knee_damping)

	var left_ankle_target: float = -0.18
	var right_ankle_target: float = -0.10

	_drive_joint(left_foot, left_calf, left_ankle_target, ankle_strength, ankle_damping)
	_drive_joint(right_foot, right_calf, right_ankle_target, ankle_strength, ankle_damping)

	var torso_target: float = 0.05
	if q_down:
		torso_target = 0.12
	elif w_down:
		torso_target = -0.02

	var torso_error: float = wrapf(torso_target - torso.rotation, -PI, PI)
	var upright_torque: float = torso_error * torso_upright_strength - torso.angular_velocity * torso_upright_damping
	torso.apply_torque(upright_torque)


func _drive_joint(child: RigidBody2D, parent: RigidBody2D, target_angle: float, strength: float, damping: float) -> void:
	var relative_angle: float = wrapf(child.rotation - parent.rotation, -PI, PI)
	var relative_velocity: float = child.angular_velocity - parent.angular_velocity
	var error: float = wrapf(target_angle - relative_angle, -PI, PI)
	var torque: float = error * strength - relative_velocity * damping

	child.apply_torque(torque)
	parent.apply_torque(-torque)


func _build_world() -> void:
	cam = Camera2D.new()
	cam.enabled = true
	add_child(cam)

	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)

	hud = Label.new()
	hud.position = Vector2(16, 16)
	canvas.add_child(hud)

	var ground: StaticBody2D = StaticBody2D.new()
	ground.position = Vector2(1500, FLOOR_Y)
	ground.collision_layer = 2
	ground.collision_mask = 1
	add_child(ground)

	var ground_shape: CollisionShape2D = CollisionShape2D.new()
	var ground_rect: RectangleShape2D = RectangleShape2D.new()
	ground_rect.size = Vector2(4000, 80)
	ground_shape.shape = ground_rect
	ground.add_child(ground_shape)

	var ground_poly: Polygon2D = Polygon2D.new()
	ground_poly.polygon = PackedVector2Array([
		Vector2(-2000, -40),
		Vector2(2000, -40),
		Vector2(2000, 40),
		Vector2(-2000, 40),
	])
	ground_poly.color = Color(0.18, 0.18, 0.18)
	ground.add_child(ground_poly)


func _spawn_runner() -> void:
	if runner_root != null:
		runner_root.queue_free()

	runner_root = Node2D.new()
	add_child(runner_root)

	torso = _make_box_body(
		runner_root, "Torso",
		Vector2(300, 392),
		Vector2(40, 92),
		2.8,
		Color(0.24, 0.49, 0.85),
		1.2
	)

	right_thigh = _make_box_body(
		runner_root, "RightThigh",
		Vector2(302, 471),
		Vector2(22, 64),
		1.7,
		Color(0.86, 0.32, 0.25),
		1.8
	)

	right_calf = _make_box_body(
		runner_root, "RightCalf",
		Vector2(304, 534),
		Vector2(20, 62),
		1.3,
		Color(0.96, 0.64, 0.18),
		2.2
	)

	right_foot = _make_box_body(
		runner_root, "RightFoot",
		Vector2(312, 572),
		Vector2(56, 16),
		1.0,
		Color(0.90, 0.82, 0.50),
		7.0
	)

	left_thigh = _make_box_body(
		runner_root, "LeftThigh",
		Vector2(264, 466),
		Vector2(22, 64),
		1.7,
		Color(0.89, 0.43, 0.25),
		1.8
	)

	left_calf = _make_box_body(
		runner_root, "LeftCalf",
		Vector2(246, 528),
		Vector2(20, 62),
		1.3,
		Color(0.96, 0.71, 0.24),
		2.2
	)

	left_foot = _make_box_body(
		runner_root, "LeftFoot",
		Vector2(235, 572),
		Vector2(56, 16),
		1.0,
		Color(0.94, 0.84, 0.56),
		7.0
	)

	torso.rotation = 0.06
	right_thigh.rotation = 0.06
	right_calf.rotation = 0.02
	right_foot.rotation = 0.00

	left_thigh.rotation = 0.55
	left_calf.rotation = -0.18
	left_foot.rotation = 0.02

	_make_pin_joint(runner_root, torso, right_thigh, Vector2(302, 438))
	_make_pin_joint(runner_root, right_thigh, right_calf, Vector2(304, 503))
	_make_pin_joint(runner_root, right_calf, right_foot, Vector2(306, 565))

	_make_pin_joint(runner_root, torso, left_thigh, Vector2(278, 438))
	_make_pin_joint(runner_root, left_thigh, left_calf, Vector2(254, 500))
	_make_pin_joint(runner_root, left_calf, left_foot, Vector2(238, 565))

	if cam != null:
		cam.global_position = torso.global_position + CAMERA_OFFSET


func _make_box_body(
	parent: Node,
	body_name: String,
	body_pos: Vector2,
	size: Vector2,
	body_mass: float,
	color: Color,
	friction: float
) -> RigidBody2D:
	var body: RigidBody2D = RigidBody2D.new()
	body.name = body_name
	body.position = body_pos
	body.mass = body_mass
	body.linear_damp = 0.9
	body.angular_damp = 1.8
	body.can_sleep = false
	body.collision_layer = 1
	body.collision_mask = 2
	body.gravity_scale = 1.0

	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.0
	body.physics_material_override = material

	parent.add_child(body)

	var collider: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = size
	collider.shape = rect
	body.add_child(collider)

	var poly: Polygon2D = Polygon2D.new()
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	poly.polygon = PackedVector2Array([
		Vector2(-hx, -hy),
		Vector2(hx, -hy),
		Vector2(hx, hy),
		Vector2(-hx, hy),
	])
	poly.color = color
	body.add_child(poly)

	return body


func _make_pin_joint(
	parent: Node,
	body_a: RigidBody2D,
	body_b: RigidBody2D,
	anchor: Vector2
) -> PinJoint2D:
	var joint: PinJoint2D = PinJoint2D.new()
	joint.position = anchor
	parent.add_child(joint)

	joint.node_a = joint.get_path_to(body_a)
	joint.node_b = joint.get_path_to(body_b)
	return joint
