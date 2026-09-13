extends Node
## 1-4: disturb forearm, arm, thigh, torso. Shift doubles impulse.
## V: velocity feed-forward on/off. This helper belongs to the sandbox scene.
@export var ragdoll_path: NodePath = ^"../ActiveRagdoll"
@onready var ragdoll: ActiveRagdoll = get_node(ragdoll_path)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_V: ragdoll.target_controller.use_target_velocity = not ragdoll.target_controller.use_target_velocity
	var bones := {KEY_1: "mixamorig_LeftForeArm", KEY_2: "mixamorig_LeftArm", KEY_3: "mixamorig_LeftUpLeg", KEY_4: "mixamorig_Spine"}
	if event.keycode in bones:
		for bone in ragdoll.bone_sim.get_children():
			if bone is PhysicalBone3D and bone.bone_name == bones[event.keycode]:
				PhysicsServer3D.body_apply_torque_impulse(bone.get_rid(), Vector3.RIGHT * (0.2 if event.shift_pressed else 0.1))
