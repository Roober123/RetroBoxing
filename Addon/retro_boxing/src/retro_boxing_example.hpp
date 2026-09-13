#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class RetroBoxingExample : public Node {
	GDCLASS(RetroBoxingExample, Node)

protected:
	static void _bind_methods();

public:
	String get_greeting() const;
};

} // namespace godot
