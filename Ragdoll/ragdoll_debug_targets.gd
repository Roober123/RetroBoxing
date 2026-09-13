extends Node
## Opt-in testing controls. Targets are offsets in the reference child-body frame.
## 1/2: elbows, 3: left arm, 4: left thigh, 5: spine, R: reset targets.
var controller: ActiveRagdollPD3D

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_R:
		controller.reset_all_targets()
		return
	var bones := {
		KEY_1: &"mixamorig_LeftForeArm", KEY_2: &"mixamorig_RightForeArm",
		KEY_3: &"mixamorig_LeftArm", KEY_4: &"mixamorig_LeftUpLeg",
		KEY_5: &"mixamorig_Spine",
	}
	if event.keycode in bones:
		var bone: StringName = bones[event.keycode]
		controller.set_joint_enabled(bone, true)
		controller.set_joint_target(bone, Quaternion(Vector3.RIGHT, deg_to_rad(30.0)))
