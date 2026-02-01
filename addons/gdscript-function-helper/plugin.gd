@tool
extends EditorPlugin

var current_editor: CodeEdit = null
var last_checked_editor: ScriptEditorBase = null
var pending_function_call: Dictionary = {}
const GENERATE_METHOD_ID = 9999


func _enter_tree() -> void:
	set_process(true)


func _exit_tree() -> void:
	_disconnect_current_editor()
	set_process(false)


func _process(_delta: float) -> void:
	if not is_instance_valid(last_checked_editor):
		last_checked_editor = null
		current_editor = null

	var script_editor: ScriptEditor = get_editor_interface().get_script_editor()
	if not script_editor:
		return

	var editor: ScriptEditorBase = script_editor.get_current_editor()
	if editor != last_checked_editor:
		last_checked_editor = editor
		_update_current_editor(editor)


func _disconnect_current_editor() -> void:
	if is_instance_valid(current_editor):
		if current_editor.gui_input.is_connected(_on_gui_input):
			current_editor.gui_input.disconnect(_on_gui_input)
	current_editor = null


func _update_current_editor(editor: ScriptEditorBase) -> void:
	_disconnect_current_editor()

	if not is_instance_valid(editor):
		return

	var code_edit = editor.get_base_editor() as CodeEdit
	if code_edit and is_instance_valid(code_edit):
		current_editor = code_edit
		if not current_editor.gui_input.is_connected(_on_gui_input):
			current_editor.gui_input.connect(_on_gui_input)


func _find_and_modify_context_menu() -> void:
	var root = get_tree().root
	var menu = _find_context_menu(root)
	if menu:
		_add_generate_method_item(menu)


func _find_context_menu(node: Node) -> PopupMenu:
	if node is PopupMenu and node.visible:
		for i in range(node.item_count):
			var text = node.get_item_text(i)
			if text == "Undo" or text == "Cut" or text == "Copy":
				return node
	for child in node.get_children():
		var result = _find_context_menu(child)
		if result:
			return result
	return null


func _add_generate_method_item(menu: PopupMenu) -> void:
	for i in range(menu.item_count - 1, -1, -1):
		var item_id = menu.get_item_id(i)
		if item_id == GENERATE_METHOD_ID or item_id == GENERATE_METHOD_ID - 1:
			menu.remove_item(i)

	if not menu.id_pressed.is_connected(_on_menu_id_pressed):
		menu.id_pressed.connect(_on_menu_id_pressed)

	var cursor_line = current_editor.get_caret_line()
	var func_call = _get_first_undefined_call_on_line(cursor_line)

	if not func_call.is_empty():
		pending_function_call = func_call
		menu.add_separator("", GENERATE_METHOD_ID - 1)
		menu.add_item("Generate Method: " + func_call.name + "()", GENERATE_METHOD_ID)


func _get_first_undefined_call_on_line(line: int) -> Dictionary:
	var line_text = current_editor.get_line(line)
	var search_start = 0

	while true:
		var paren_pos = line_text.find("(", search_start)
		if paren_pos == -1:
			break

		var func_start = paren_pos - 1
		while func_start >= 0:
			var c = line_text[func_start]
			if not (c.is_valid_identifier() or c == "_"):
				break
			func_start -= 1
		func_start += 1

		if func_start >= paren_pos:
			search_start = paren_pos + 1
			continue

		var func_name = line_text.substr(func_start, paren_pos - func_start)
		if func_name.is_empty() or not func_name[0].is_valid_identifier():
			search_start = paren_pos + 1
			continue

		if func_start > 0 and line_text[func_start - 1] == ".":
			search_start = paren_pos + 1
			continue

		if _is_function_defined(func_name):
			search_start = paren_pos + 1
			continue

		var args_str = ""
		var paren_depth = 1
		var args_start = paren_pos + 1
		var args_end = args_start

		while args_end < line_text.length() and paren_depth > 0:
			var c = line_text[args_end]
			if c == "(":
				paren_depth += 1
			elif c == ")":
				paren_depth -= 1
			args_end += 1

		if paren_depth == 0:
			args_str = line_text.substr(args_start, args_end - args_start - 1)

		var args = _parse_arguments(args_str)
		return {
			"name": func_name,
			"args": args,
			"line": line,
			"col": func_start
		}

	return {}


func _on_menu_id_pressed(id: int) -> void:
	if id == GENERATE_METHOD_ID and not pending_function_call.is_empty():
		_generate_method(pending_function_call)
		pending_function_call = {}


func _parse_arguments(args_str: String) -> Array:
	var args = []
	if args_str.strip_edges().is_empty():
		return args

	var current_arg = ""
	var paren_depth = 0
	var bracket_depth = 0
	var brace_depth = 0
	var in_string = false
	var string_char = ""

	for i in range(args_str.length()):
		var c = args_str[i]

		if in_string:
			current_arg += c
			if c == string_char and (i == 0 or args_str[i - 1] != "\\"):
				in_string = false
			continue

		if c == '"' or c == "'":
			in_string = true
			string_char = c
			current_arg += c
			continue

		if c == "(":
			paren_depth += 1
		elif c == ")":
			paren_depth -= 1
		elif c == "[":
			bracket_depth += 1
		elif c == "]":
			bracket_depth -= 1
		elif c == "{":
			brace_depth += 1
		elif c == "}":
			brace_depth -= 1

		if c == "," and paren_depth == 0 and bracket_depth == 0 and brace_depth == 0:
			if not current_arg.strip_edges().is_empty():
				args.append(_infer_type(current_arg.strip_edges()))
			current_arg = ""
		else:
			current_arg += c

	if not current_arg.strip_edges().is_empty():
		args.append(_infer_type(current_arg.strip_edges()))

	return args


func _infer_type(value: String) -> Dictionary:
	if value == "true" or value == "false":
		return {"name": "flag", "type": "bool"}

	if value.is_valid_int():
		return {"name": "n", "type": "int"}

	if value.is_valid_float():
		return {"name": "x", "type": "float"}

	if (value.begins_with('"') and value.ends_with('"')) or (value.begins_with("'") and value.ends_with("'")):
		return {"name": "text", "type": "String"}

	if value.begins_with("[") and value.ends_with("]"):
		return {"name": "arr", "type": "Array"}

	if value.begins_with("{") and value.ends_with("}"):
		return {"name": "dict", "type": "Dictionary"}

	var constructors = ["Vector2", "Vector3", "Vector4", "Vector2i", "Vector3i", "Vector4i", "Color", "Rect2", "Rect2i", "Transform2D", "Transform3D", "Basis", "Quaternion", "AABB", "Plane", "NodePath", "StringName", "RID", "Callable", "Signal"]
	for constructor in constructors:
		if value.begins_with(constructor + "("):
			return {"name": constructor.to_snake_case(), "type": constructor}

	if value.begins_with("$") or value.begins_with("%"):
		return {"name": "node", "type": "Node"}

	return {"name": value.to_snake_case() if value.is_valid_identifier() else "arg", "type": "Variant"}


func _is_function_defined(func_name: String) -> bool:
	var full_text = current_editor.text
	var pattern = "func " + func_name + "("
	return pattern in full_text


func _generate_method(func_call: Dictionary) -> void:
	var func_name: String = func_call.name
	var args: Array = func_call.args

	var params_str = ""
	var used_names = {}
	for i in range(args.size()):
		var arg = args[i]
		var name = arg.name
		var counter = 1
		while name in used_names:
			name = arg.name + str(counter)
			counter += 1
		used_names[name] = true

		if i > 0:
			params_str += ", "
		params_str += name + ": " + arg.type

	var new_func = "\n\nfunc " + func_name + "(" + params_str + ") -> void:\n\tpass"

	var full_text = current_editor.text
	var new_text = full_text + new_func

	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	undo_redo.create_action("Generate Method: " + func_name)
	undo_redo.add_do_method(self, "_set_text", new_text)
	undo_redo.add_undo_method(self, "_set_text", full_text)
	undo_redo.commit_action()

	var lines = new_text.split("\n")
	var target_line = lines.size() - 2
	call_deferred("_update_caret", target_line, 1, current_editor.get_v_scroll())


func _on_gui_input(event: InputEvent) -> void:
	if not is_instance_valid(current_editor):
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		call_deferred("_find_and_modify_context_menu")

	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		var cursor_line: int = current_editor.get_caret_line()
		var current_line: String = current_editor.get_line(cursor_line)
		current_line = current_line.strip_edges(false, true)
		var parts: PackedStringArray = current_line.split(" ", false)

		if parts.size() >= 2 and parts[0] == "func":
			get_viewport().set_input_as_handled()

			var indent: String = ""
			for c in current_line:
				if c == " " or c == "\t":
					indent += c
				else:
					break

			var func_signature: String = current_line.substr(current_line.find(parts[1]))
			var return_type: String = "void"

			if "->" in func_signature:
				var parts_arrow = func_signature.split("->", true, 1)
				return_type = parts_arrow[1].strip_edges()
				if return_type == "":
					return_type = "void"
				func_signature = parts_arrow[0].strip_edges()
			elif ")" in func_signature:
				var after_paren = func_signature.split(")", true, 1)
				if after_paren.size() > 1:
					var potential_return = after_paren[1].strip_edges()
					if potential_return != "":
						return_type = potential_return
						func_signature = after_paren[0] + ")"
			elif parts.size() > 2:
				var last_part = parts[-1]
				if not "(" in last_part:
					return_type = last_part
					func_signature = func_signature.substr(0, func_signature.rfind(" " + last_part)).strip_edges()

			if "(" in func_signature:
				var param_start = func_signature.find("(")
				var param_end = func_signature.find(")")
				if param_end == -1:
					param_end = func_signature.length()

				var before_params = func_signature.substr(0, param_start + 1)
				var params = func_signature.substr(param_start + 1, param_end - param_start - 1)
				var after_params = "" if param_end == func_signature.length() else func_signature.substr(param_end)

				if ":" in params:
					params = params.strip_edges()

				func_signature = before_params + params + (")" if after_params == "" else after_params)
			else:
				func_signature += "()"

			if func_signature.ends_with(":"):
				func_signature = func_signature.substr(0, func_signature.length() - 1)

			var new_line: String = indent + "func " + func_signature + " -> " + return_type + ":"

			var body_line: String
			if return_type == "void":
				body_line = indent + "\tpass"
			else:
				var default_value = _get_default_value(return_type)
				body_line = indent + "\treturn " + default_value

			var current_scroll: int = current_editor.get_v_scroll()
			var full_text: String = current_editor.text
			var lines: PackedStringArray = full_text.split("\n")
			lines[cursor_line] = new_line
			lines.insert(cursor_line + 1, body_line)
			var new_text: String = "\n".join(lines)

			var undo_redo: EditorUndoRedoManager = get_undo_redo()
			undo_redo.create_action("Add Function Return Type")
			undo_redo.add_do_method(self, "_set_text", new_text)
			undo_redo.add_undo_method(self, "_set_text", full_text)
			undo_redo.commit_action()

			call_deferred("_update_caret", cursor_line + 1, indent.length() + 5, current_scroll)


func _get_default_value(return_type: String) -> String:
	match return_type:
		"bool":
			return "false"
		"int":
			return "0"
		"float":
			return "0.0"
		"String":
			return '""'
		"Array", "PackedStringArray", "PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array", "PackedVector2Array", "PackedVector3Array", "PackedColorArray", "PackedVector4Array":
			return "[]"
		"Dictionary":
			return "{}"
		_:
			return "null"


func _set_text(text: String) -> void:
	if is_instance_valid(current_editor):
		current_editor.text = text


func _update_caret(line: int, column: int, scroll: int) -> void:
	if is_instance_valid(current_editor):
		current_editor.set_v_scroll(scroll)
		current_editor.set_caret_line(line)
		current_editor.set_caret_column(column)
		current_editor.grab_focus()
