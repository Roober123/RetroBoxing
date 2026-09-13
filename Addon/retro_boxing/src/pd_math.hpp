#pragma once

#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <cmath>

namespace retro_boxing {

// q_desired * inverse(q_current) is expressed in the parent body's frame.
inline godot::Vector3 rotation_error(const godot::Quaternion &current, const godot::Quaternion &desired) {
	godot::Quaternion error = (desired * current.inverse()).normalized();
	if (error.w < 0) {
		error = -error;
	}
	const godot::Vector3 imaginary(error.x, error.y, error.z);
	const godot::real_t length = imaginary.length();
	if (length < 1e-6) {
		return imaginary * 2;
	}
	return imaginary * (2 * std::atan2(length, error.w) / length);
}

// Both errors must be in the same frame. No delta multiplier: this is torque.
inline godot::Vector3 pd_torque(const godot::Vector3 &error, const godot::Vector3 &velocity_error,
		godot::real_t stiffness, godot::real_t damping, godot::real_t strength, godot::real_t max_torque) {
	return ((error * stiffness + velocity_error * damping) * strength).limit_length(max_torque);
}

} // namespace retro_boxing
