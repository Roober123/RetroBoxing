class_name BalanceJointAxisResolver
extends RefCounted
## Resolve before the first physics tick, against the same reference as PD.
## Axes are reference-child BODY local, not skeleton bone local.
var joints: Dictionary = {}
var error := ""
var up := Vector3.ZERO
var right := Vector3.ZERO
var forward := Vector3.ZERO
var _skeleton: Skeleton3D
var _bodies: Dictionary = {}

func resolve(skeleton: Skeleton3D, simulator: PhysicalBoneSimulator3D) -> bool:
	joints.clear()
	_bodies.clear()
	error = ""
	_skeleton = skeleton
	for node in simulator.get_children():
		if node is PhysicalBone3D:
			_bodies[String(node.bone_name)] = node
	up = _direction("Hips", "Head")
	right = _direction("LeftUpLeg", "RightUpLeg")
	right = (right - up * right.dot(up)).normalized()
	# Anatomical forward is -Z in a right/up/backward Godot basis.
	forward = up.cross(right).normalized()
	var toes := _direction("LeftFoot", "LeftToeBase") + _direction("RightFoot", "RightToeBase")
	if forward.dot(toes) < 0.2 or right.length() < 0.9:
		_fail("Hips", "ambiguous character frame or toes point backward")
	for side in ["Left", "Right"]:
		_resolve_joint(side + "UpLeg", _direction(side + "UpLeg", side + "Leg"), forward, right)
		_resolve_joint(side + "Leg", _direction(side + "Leg", side + "Foot"), -forward)
		var foot := _direction(side + "Foot", side + "ToeBase")
		# Roll is rotation about the foot's length; its toe displacement is zero.
		# Use the sole normal as the probe for roll instead.
		var sole := foot.cross(right).normalized()
		_resolve_joint(side + "Foot", foot, up, right, sole)
	_resolve_joint("Spine", _direction("Spine", "Spine2"), forward, right)
	if not error.is_empty():
		joints.clear()
		push_error(error)
		return false
	if OS.is_debug_build():
		print("Balance joint axes (reference body local):")
		for bone in joints:
			var joint: Dictionary = joints[bone]
			print("  ", bone, ": ", joint.axes, " signs: ", joint.signs)
	return true

func _direction(start: String, end: String) -> Vector3:
	var a := _skeleton.find_bone("mixamorig_" + start)
	var b := _skeleton.find_bone("mixamorig_" + end)
	if a < 0 or b < 0:
		_fail(start, "missing reference bone " + end)
		return Vector3.ZERO
	var delta := _skeleton.global_basis * (_skeleton.get_bone_global_rest(b).origin - _skeleton.get_bone_global_rest(a).origin)
	if delta.length_squared() < 0.000001:
		_fail(start, "degenerate segment to " + end)
	return delta.normalized()

func _resolve_joint(short_name: String, segment: Vector3, pitch_motion: Vector3, roll_motion := Vector3.ZERO, roll_segment := Vector3.ZERO) -> void:
	var bone := "mixamorig_" + short_name
	var body: PhysicalBone3D = _bodies.get(bone)
	if body == null:
		_fail(bone, "missing physical bone")
		return
	var id := body.get_bone_id()
	var parent := _skeleton.get_bone_parent(id)
	if parent < 0 or not _bodies.has(String(_skeleton.get_bone_name(parent))) or _skeleton.get_bone_children(id).is_empty():
		_fail(bone, "missing physical parent or skeleton child")
		return
	# The current rig uses cone joints. Reject unsupported constraints explicitly
	# rather than pretending a locked/hinge axis offers two independent actions.
	if body.joint_type != PhysicalBone3D.JOINT_TYPE_CONE:
		_fail(bone, "expected a cone joint")
		return
	var constraints := {}
	for property in body.get_property_list():
		if String(property.name).begins_with("joint_constraints/"):
			constraints[property.name] = body.get(property.name)
	if float(constraints.get("joint_constraints/swing_span", 0.0)) <= 0.0 or float(constraints.get("joint_constraints/twist_span", 0.0)) <= 0.0:
		_fail(bone, "locked cone swing or twist")
		return
	var body_basis := body.global_basis.orthonormalized()
	# joint_rotation already belongs to joint_offset; do not apply it twice.
	var frame := (body_basis * body.joint_offset.basis).orthonormalized()
	var candidates: Array[Vector3] = [frame.x, frame.y, frame.z]
	var pitch := _select(candidates, segment, pitch_motion, -1)
	var axes: Array[Vector3] = []
	var signs: Array[float] = []
	if pitch < 0:
		_fail(bone, "no useful pitch/flexion axis")
		return
	var sign_pitch := signf(candidates[pitch].cross(segment).dot(pitch_motion))
	axes.append((body_basis.inverse() * candidates[pitch]).normalized())
	signs.append(sign_pitch)
	if not roll_motion.is_zero_approx():
		var probe := segment if roll_segment.is_zero_approx() else roll_segment
		var roll := _select(candidates, probe, roll_motion, pitch)
		if roll < 0:
			_fail(bone, "no independent roll axis")
			return
		axes.append((body_basis.inverse() * candidates[roll]).normalized())
		signs.append(signf(candidates[roll].cross(probe).dot(roll_motion)))
		if absf(axes[0].dot(axes[1])) > 0.1:
			_fail(bone, "parallel pitch and roll")
	for axis in axes:
		if not axis.is_finite() or not is_equal_approx(axis.length(), 1.0):
			_fail(bone, "invalid axis")
	joints[StringName(bone)] = {"axes": axes, "signs": signs, "bone_id": id,
		"parent": parent, "children": _skeleton.get_bone_children(id),
		"rest": _skeleton.get_bone_global_rest(id), "body_reference": body.global_transform,
		"joint_offset": body.joint_offset, "joint_rotation": body.joint_rotation,
		"joint_type": body.joint_type, "constraints": constraints,
		"limit_degrees": minf(float(constraints["joint_constraints/swing_span"]), float(constraints["joint_constraints/twist_span"])) / axes.size()}

func _select(candidates: Array[Vector3], segment: Vector3, motion: Vector3, excluded: int) -> int:
	var best := -1
	var score := 0.25
	for i in candidates.size():
		var movement := absf(candidates[i].cross(segment).dot(motion))
		if i != excluded and movement > score:
			best = i
			score = movement
	return best

func _fail(bone: String, reason: String) -> void:
	if error.is_empty():
		error = "Balance axis resolver: %s: %s" % [bone, reason]
