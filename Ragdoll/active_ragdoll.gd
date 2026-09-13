class_name ActiveRagdoll
extends Node3D

@onready var bone_sim : PhysicalBoneSimulator3D = $PhysicalSkeleton/PhysicalBoneSimulator3D
@onready var skel := $PhysicalSkeleton

func _ready() -> void:
	RagdollCollisionJitterFix.new().apply(skel,bone_sim)
	bone_sim.physical_bones_start_simulation()
