#include "active_ragdoll_pd.hpp"
#include "pd_math.hpp"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

using namespace godot;

namespace {
PhysicalBone3D *get_bone(uint64_t id) {
	return Object::cast_to<PhysicalBone3D>(ObjectDB::get_instance(id));
}
Quaternion world_rotation(PhysicalBone3D *bone) {
	return bone->get_global_transform().basis.orthonormalized().get_rotation_quaternion();
}
bool valid_gain(real_t value) { return std::isfinite(value) && value >= 0; }
}

void ActiveRagdollPD3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize", "skeleton", "simulator"), &ActiveRagdollPD3D::initialize);
	ClassDB::bind_method(D_METHOD("capture_reference_pose"), &ActiveRagdollPD3D::capture_reference_pose);
	ClassDB::bind_method(D_METHOD("set_enabled", "value"), &ActiveRagdollPD3D::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &ActiveRagdollPD3D::is_enabled);
	ClassDB::bind_method(D_METHOD("set_joint_target", "bone_name", "rotation"), &ActiveRagdollPD3D::set_joint_target);
	ClassDB::bind_method(D_METHOD("set_joint_target_by_index", "index", "rotation"), &ActiveRagdollPD3D::set_joint_target_by_index);
	ClassDB::bind_method(D_METHOD("set_joint_target_angular_velocity", "bone_name", "velocity"), &ActiveRagdollPD3D::set_joint_target_angular_velocity);
	ClassDB::bind_method(D_METHOD("set_joint_strength", "bone_name", "strength"), &ActiveRagdollPD3D::set_joint_strength);
	ClassDB::bind_method(D_METHOD("set_joint_enabled", "bone_name", "value"), &ActiveRagdollPD3D::set_joint_enabled);
	ClassDB::bind_method(D_METHOD("set_joint_parameters", "bone_name", "stiffness", "damping", "max_torque"), &ActiveRagdollPD3D::set_joint_parameters);
	ClassDB::bind_method(D_METHOD("reset_joint_target", "bone_name"), &ActiveRagdollPD3D::reset_joint_target);
	ClassDB::bind_method(D_METHOD("reset_all_targets"), &ActiveRagdollPD3D::reset_all_targets);
	ClassDB::bind_method(D_METHOD("get_controlled_bones"), &ActiveRagdollPD3D::get_controlled_bones);
	ClassDB::bind_method(D_METHOD("get_joint_count"), &ActiveRagdollPD3D::get_joint_count);
	ClassDB::bind_method(D_METHOD("get_joint_name", "index"), &ActiveRagdollPD3D::get_joint_name);
	ClassDB::bind_method(D_METHOD("set_default_stiffness", "value"), &ActiveRagdollPD3D::set_default_stiffness);
	ClassDB::bind_method(D_METHOD("get_default_stiffness"), &ActiveRagdollPD3D::get_default_stiffness);
	ClassDB::bind_method(D_METHOD("set_default_damping", "value"), &ActiveRagdollPD3D::set_default_damping);
	ClassDB::bind_method(D_METHOD("get_default_damping"), &ActiveRagdollPD3D::get_default_damping);
	ClassDB::bind_method(D_METHOD("set_default_max_torque", "value"), &ActiveRagdollPD3D::set_default_max_torque);
	ClassDB::bind_method(D_METHOD("get_default_max_torque"), &ActiveRagdollPD3D::get_default_max_torque);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "default_stiffness", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater"), "set_default_stiffness", "get_default_stiffness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "default_damping", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater"), "set_default_damping", "get_default_damping");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "default_max_torque", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater"), "set_default_max_torque", "get_default_max_torque");
}

ActiveRagdollPD3D::ActiveRagdollPD3D() { set_physics_process(false); }

bool ActiveRagdollPD3D::initialize(Skeleton3D *skeleton, PhysicalBoneSimulator3D *simulator) {
	set_enabled(false);
	joints.clear();
	reference_captured = false;
	ERR_FAIL_NULL_V(skeleton, false);
	ERR_FAIL_NULL_V(simulator, false);
	ERR_FAIL_COND_V(!skeleton->is_inside_tree() || simulator->get_parent() != skeleton, false);
	Vector<PhysicalBone3D *> bones;
	bones.resize(skeleton->get_bone_count());
	for (int i = 0; i < bones.size(); ++i) { bones.write[i] = nullptr; }
	for (int i = 0; i < simulator->get_child_count(); ++i) {
		auto *bone = Object::cast_to<PhysicalBone3D>(simulator->get_child(i));
		if (!bone) { continue; }
		ERR_FAIL_COND_V(bone->is_simulating_physics(), false);
		const int id = bone->get_bone_id();
		if (id >= 0 && id < bones.size()) { bones.write[id] = bone; }
	}
	// Ascending skeleton IDs give stable indices independent of node names/order.
	for (int id = 0; id < bones.size(); ++id) {
		const int parent_id = skeleton->get_bone_parent(id);
		if (!bones[id] || parent_id < 0 || !bones[parent_id] ||
				bones[id]->get_joint_type() == PhysicalBone3D::JOINT_TYPE_NONE) { continue; }
		PDJoint joint;
		joint.bone_name = skeleton->get_bone_name(id);
		joint.child_id = bones[id]->get_instance_id();
		joint.parent_id = bones[parent_id]->get_instance_id();
		joint.child_rid = bones[id]->get_rid();
		joint.parent_rid = bones[parent_id]->get_rid();
		joint.stiffness = default_stiffness;
		joint.damping = default_damping;
		joint.max_torque = default_max_torque;
		joints.push_back(joint);
	}
	return !joints.is_empty();
}

bool ActiveRagdollPD3D::capture_reference_pose() {
	set_enabled(false);
	reference_captured = false;
	for (const PDJoint &joint : joints) {
		auto *child = get_bone(joint.child_id);
		auto *parent = get_bone(joint.parent_id);
		ERR_FAIL_COND_V(!child || !parent, false);
		ERR_FAIL_COND_V(child->is_simulating_physics() || parent->is_simulating_physics(), false);
	}
	for (PDJoint &joint : joints) {
		joint.reference_relative_rotation = (world_rotation(get_bone(joint.parent_id)).inverse() *
			world_rotation(get_bone(joint.child_id))).normalized();
	}
	reference_captured = !joints.is_empty();
	return reference_captured;
}

void ActiveRagdollPD3D::_physics_process(double) {
	if (!enabled || !reference_captured || Engine::get_singleton()->is_editor_hint()) { return; }
	auto *server = PhysicsServer3D::get_singleton();
	for (const PDJoint &joint : joints) {
		if (!joint.enabled || joint.strength == 0 || joint.max_torque == 0) { continue; }
		auto *child = get_bone(joint.child_id);
		auto *parent = get_bone(joint.parent_id);
		if (!child || !parent || !child->is_inside_tree() || !parent->is_inside_tree() ||
				!child->is_simulating_physics() || !parent->is_simulating_physics()) { continue; }
		// Read physics state, not interpolated visual/skeleton transforms.
		const Transform3D parent_transform = server->body_get_state(joint.parent_rid, PhysicsServer3D::BODY_STATE_TRANSFORM);
		const Transform3D child_transform = server->body_get_state(joint.child_rid, PhysicsServer3D::BODY_STATE_TRANSFORM);
		const Quaternion parent_world = parent_transform.basis.orthonormalized().get_rotation_quaternion();
		const Quaternion child_world = child_transform.basis.orthonormalized().get_rotation_quaternion();
		const Quaternion current = (parent_world.inverse() * child_world).normalized();
		const Quaternion desired = (joint.reference_relative_rotation * joint.target_rotation).normalized();
		const Vector3 error_world = parent_world.xform(retro_boxing::rotation_error(current, desired));
		const Vector3 child_velocity = server->body_get_state(joint.child_rid, PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY);
		const Vector3 parent_velocity = server->body_get_state(joint.parent_rid, PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY);
		const Vector3 velocity_error = parent_world.xform(joint.target_angular_velocity) - (child_velocity - parent_velocity);
		const Vector3 torque = retro_boxing::pd_torque(error_world, velocity_error,
			joint.stiffness, joint.damping, joint.strength, joint.max_torque);
		if (!torque.is_finite()) { continue; }
		server->body_apply_torque(joint.child_rid, torque);
		server->body_apply_torque(joint.parent_rid, -torque);
	}
}

void ActiveRagdollPD3D::set_enabled(bool value) {
	enabled = value;
	set_physics_process(value);
}
bool ActiveRagdollPD3D::is_enabled() const { return enabled; }

int ActiveRagdollPD3D::find_joint(const StringName &bone_name) const {
	for (int i = 0; i < joints.size(); ++i) {
		if (joints[i].bone_name == bone_name) { return i; }
	}
	return -1;
}
void ActiveRagdollPD3D::set_joint_target(const StringName &bone_name, const Quaternion &rotation) {
	set_joint_target_by_index(find_joint(bone_name), rotation);
}
void ActiveRagdollPD3D::set_joint_target_by_index(int index, const Quaternion &rotation) {
	ERR_FAIL_INDEX(index, joints.size());
	ERR_FAIL_COND(!rotation.is_finite() || rotation.length_squared() < 1e-12);
	joints.write[index].target_rotation = rotation.normalized();
}
void ActiveRagdollPD3D::set_joint_target_angular_velocity(const StringName &bone_name, const Vector3 &velocity) {
	const int index = find_joint(bone_name);
	ERR_FAIL_INDEX(index, joints.size());
	ERR_FAIL_COND(!velocity.is_finite());
	joints.write[index].target_angular_velocity = velocity;
}
void ActiveRagdollPD3D::set_joint_strength(const StringName &bone_name, real_t strength) {
	const int index = find_joint(bone_name);
	ERR_FAIL_INDEX(index, joints.size());
	ERR_FAIL_COND(!valid_gain(strength));
	joints.write[index].strength = strength;
}
void ActiveRagdollPD3D::set_joint_enabled(const StringName &bone_name, bool value) {
	const int index = find_joint(bone_name);
	ERR_FAIL_INDEX(index, joints.size());
	joints.write[index].enabled = value;
}
void ActiveRagdollPD3D::set_joint_parameters(const StringName &bone_name, real_t stiffness, real_t damping, real_t max_torque) {
	const int index = find_joint(bone_name);
	ERR_FAIL_INDEX(index, joints.size());
	ERR_FAIL_COND(!valid_gain(stiffness) || !valid_gain(damping) || !valid_gain(max_torque));
	PDJoint &joint = joints.write[index];
	joint.stiffness = stiffness;
	joint.damping = damping;
	joint.max_torque = max_torque;
}
void ActiveRagdollPD3D::reset_joint_target(const StringName &bone_name) {
	const int index = find_joint(bone_name);
	ERR_FAIL_INDEX(index, joints.size());
	joints.write[index].target_rotation = Quaternion();
	joints.write[index].target_angular_velocity = Vector3();
}
void ActiveRagdollPD3D::reset_all_targets() {
	for (PDJoint &joint : joints) {
		joint.target_rotation = Quaternion();
		joint.target_angular_velocity = Vector3();
	}
}
PackedStringArray ActiveRagdollPD3D::get_controlled_bones() const {
	PackedStringArray names;
	for (const PDJoint &joint : joints) { names.push_back(joint.bone_name); }
	return names;
}
int ActiveRagdollPD3D::get_joint_count() const { return joints.size(); }
StringName ActiveRagdollPD3D::get_joint_name(int index) const {
	ERR_FAIL_INDEX_V(index, joints.size(), StringName());
	return joints[index].bone_name;
}

void ActiveRagdollPD3D::set_default_stiffness(real_t value) {
	ERR_FAIL_COND(!valid_gain(value));
	default_stiffness = value;
}
real_t ActiveRagdollPD3D::get_default_stiffness() const { return default_stiffness; }

void ActiveRagdollPD3D::set_default_damping(real_t value) {
	ERR_FAIL_COND(!valid_gain(value));
	default_damping = value;
}
real_t ActiveRagdollPD3D::get_default_damping() const { return default_damping; }

void ActiveRagdollPD3D::set_default_max_torque(real_t value) {
	ERR_FAIL_COND(!valid_gain(value));
	default_max_torque = value;
}
real_t ActiveRagdollPD3D::get_default_max_torque() const { return default_max_torque; }
