#include "retro_boxing_example.hpp"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void RetroBoxingExample::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_greeting"), &RetroBoxingExample::get_greeting);
}

String RetroBoxingExample::get_greeting() const {
	return "Hello from the Retro Boxing GDExtension.";
}
