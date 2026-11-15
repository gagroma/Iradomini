extends Node
# Test tool: the whole between-levels flow. Starts the passage (level 2), jumps to its end, checks the
# church level loads; then fakes the altar win and checks it goes on to the passage of level 3.
#   godot --path . res://scenes/flow_test.tscn

func _ready() -> void:
	Engine.set_meta("ira_level", 2)
	var tree := get_tree()
	var keep := Node.new()
	keep.set_script(load("res://scripts/flow_runner.gd"))
	tree.root.call_deferred("add_child", keep)
