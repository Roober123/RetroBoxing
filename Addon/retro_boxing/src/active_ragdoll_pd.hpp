#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/physical_bone3d.hpp>
#include <godot_cpp/classes/physical_bone_simulator3d.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/templates/vector.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/quaternion.hpp>

namespace godot {

struct PDJoint {
	StringName bone_name;
	uint64_t child_id = 0;
	uint64_t parent_id = 0;
	RID child_rid;
	RID parent_rid;
	Quaternion reference_relative_rotation;
	Quaternion target_rotation;
	Vector3 target_angular_velocity; // Parent-body local frame, radians/second.
	real_t stiffness = 2.0;
	real_t damping = 0.08;
	real_t max_torque = 0.5;
	real_t strength = 1.0;
	bool enabled = true;
};

class ActiveRagdollPD3D : public Node {
	GDCLASS(ActiveRagdollPD3D, Node)
	Vector<PDJoint> joints;
	bool enabled = false;
	bool reference_captured = false;
	real_t default_stiffness = 2.0;
	real_t default_damping = 0.08;
	real_t default_max_torque = 0.5;
	int find_joint(const StringName &bone_name) const;

protected:
	static void _bind_methods();

public:
	ActiveRagdollPD3D();
	bool initialize(Skeleton3D *skeleton, PhysicalBoneSimulator3D *simulator);
	bool capture_reference_pose();
	void _physics_process(double delta) override;
	void set_enabled(bool value);
	bool is_enabled() const;

	void set_default_stiffness(real_t value);
	real_t get_default_stiffness() const;
	void set_default_damping(real_t value);
	real_t get_default_damping() const;
	void set_default_max_torque(real_t value);
	real_t get_default_max_torque() const;

	void set_joint_target(const StringName &bone_name, const Quaternion &rotation);
	
	void set_joint_target_by_index(int index, const Quaternion &rotation);
	void set_joint_target_angular_velocity(const StringName &bone_name, const Vector3 &velocity);
	void set_joint_strength(const StringName &bone_name, real_t strength);
	
	void set_joint_enabled(const StringName &bone_name, bool value);
	void set_joint_parameters(const StringName &bone_name, real_t stiffness, real_t damping, real_t max_torque);
	void reset_joint_target(const StringName &bone_name);
	
	void reset_all_targets();
	PackedStringArray get_controlled_bones() const;
	int get_joint_count() const;
	StringName get_joint_name(int index) const;
};

} // namespace godot
