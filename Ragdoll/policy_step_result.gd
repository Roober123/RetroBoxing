class_name PolicyStepResult
extends RefCounted

var observations: Array = []
var rewards := PackedFloat32Array()
var terminated: Array[bool] = []
var truncated: Array[bool] = []
var terminal_observations: Array = []
