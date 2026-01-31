# GDScript Function Helper

a simple Godot 4 plugin that helps you write functions faster with two features:

1. **tab autocomplete** - auto-complete return types and add default return values
2. **generate method** - right-click an undefined function call to generate a stub

*formerly "Function Type Autocomplete"*

## tab autocomplete

just write your function and hit tab.

when you hit tab after writing a function, it:
- adds the return type for you (-> void if you don't specify one)
- puts in a default return value
- keeps your parameters and types intact
- works with partial or complete function declarations

### default return values

here's what you get based on the return type:

```gdscript
# void functions get 'pass'
func do_something() -> void:
    pass

# bools get 'false'
func is_something() -> bool:
    return false

# numbers get zeros
func count_stuff() -> int:
    return 0
func get_speed() -> float:
    return 0.0

# strings get empty quotes
func get_name() -> String:
    return ""

# arrays and dictionaries start empty
func get_items() -> Array:
    return []
func get_data() -> Dictionary:
    return {}

# objects get null
func get_node() -> Node:
    return null
```

### handles different ways of writing functions

```gdscript
# works with complete functions
func do_math(value: int) -> int:
    return 0

# works with incomplete ones
func not_done(value: int
# becomes
func not_done(value: int) -> void:
    pass

# works with arrows
func arrows_are_cool() ->
# becomes
func arrows_are_cool() -> void:
    pass

# works without arrows
func give_string String
# becomes
func give_string() -> String:
    return ""

# keeps your parameters safe
func move_stuff(pos: Vector2, speed: float
# becomes
func move_stuff(pos: Vector2, speed: float) -> void:
    pass
```

## generate method

right-click on a function call that doesn't exist yet and select "Generate Method" from the context menu. it creates a stub method with the right parameters.

```gdscript
# right-click on this
calculate_damage(player, 50, true)

# select "Generate Method", get this
func calculate_damage(arg1: Variant, arg2: int, arg3: bool) -> void:
    pass
```

### type inference

the plugin tries to figure out parameter types from what you pass in:

- `true` / `false` → `bool`
- `5` → `int`
- `3.14` → `float`
- `"hello"` → `String`
- `[]` → `Array`
- `{}` → `Dictionary`
- `Vector2(1, 2)` → `Vector2`
- `$Player` or `%Player` → `Node`
- variables → `Variant`

## need help?

if something's not working, file an issue and provide the following:
- what's going wrong
- what version of Godot you're using
- what operating system you're on
