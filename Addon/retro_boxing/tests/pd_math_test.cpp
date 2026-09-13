#include "pd_math.hpp"
#include <cassert>
#include <iostream>

using namespace godot;
using namespace retro_boxing;

int main() {
	const Vector3 x(1, 0, 0);
	const real_t degrees = 3.14159265358979323846 / 180;
	const Quaternion identity;
	auto near = [](Vector3 actual, Vector3 expected) { assert(actual.distance_to(expected) < 1e-5); };
	near(rotation_error(identity, identity), Vector3());
	near(rotation_error(identity, Quaternion(x, 30 * degrees)), x * (30 * degrees));
	near(rotation_error(identity, Quaternion(x, -30 * degrees)), x * (-30 * degrees));
	near(rotation_error(Quaternion(x, 179 * degrees), Quaternion(x, -179 * degrees)), x * (2 * degrees));
	const Quaternion target(x, 30 * degrees);
	near(rotation_error(identity, target), rotation_error(identity, -target));
	near(rotation_error(target, -target), Vector3());
	near(pd_torque(x, -x, 8, 2, 0.5, 100), x * 3);
	near(pd_torque(x, Vector3(), 100, 0, 1, 4), x * 4);
	near(pd_torque(x, x, 8, 2, 0, 4), Vector3());
	near(pd_torque(x, x, 8, 2, 1, 0), Vector3());
	near(pd_torque(Vector3(), -x, 8, 2, 1, 4), -x * 2);
	// World rotation changes only the torque frame, not the relative error.
	const Quaternion world(Vector3(0, 1, 0), 90 * degrees);
	const Quaternion reference(Vector3(0, 0, 1), 20 * degrees);
	const Quaternion desired = reference * target;
	near(world.xform(rotation_error(reference, desired)),
		rotation_error(world * reference, world * desired));
	std::cout << "PD math tests passed\n";
}
