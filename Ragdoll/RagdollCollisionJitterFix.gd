class_name RagdollCollisionJitterFix
extends RefCounted


func apply(sk : Skeleton3D, ph : PhysicalBoneSimulator3D)->void:
	for i in ph.get_children():
		if i is PhysicalBone3D:
			exclude_parent_bone(sk, i, ph)

func exclude_parent_bone(sk : Skeleton3D, b : PhysicalBone3D, sim : PhysicalBoneSimulator3D)->void:
	var b_id : int = b.get_bone_id()
	var parent_id : int = sk.get_bone_parent(b_id)
	if parent_id != -1:
		for i in sim.get_children():
			if i is PhysicalBone3D and i.get_bone_id() == parent_id:
				
				PhysicsServer3D.body_add_collision_exception(b.get_rid(), i.get_rid())
				PhysicsServer3D.body_add_collision_exception(i.get_rid(), b.get_rid())
