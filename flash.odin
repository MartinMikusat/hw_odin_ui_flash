package flash

import "core:mem"
import "core:strings"

DEFAULT_ALPHABET :: "asdfghjklqwertyuiopzxcvbnm"

Target_ID :: distinct u64

Y_Axis_Direction :: enum {
	Up,
	Down,
}

Anchor :: enum {
	Top_Left,
	Top_Right,
	Bottom_Left,
	Bottom_Right,
	Center,
}

Rect :: struct {
	x, y, w, h: f64,
}

Target :: struct {
	id:     Target_ID,
	rect:   Rect,
	anchor: Anchor,
}

Config :: struct {
	alphabet: string,
	y_axis:   Y_Axis_Direction,
}

Begin_Error :: enum {
	None,
	Invalid_Alphabet,
	Too_Many_Targets,
}

Input_Result_Kind :: enum {
	Ignored,
	Pending,
	Activated,
	Cancelled,
}

Input_Result :: struct {
	kind:      Input_Result_Kind,
	target_id: Target_ID,
}

Hint :: struct {
	target:       Target,
	label:        [2]u8,
	label_length: int,
}

Labeled_Target :: struct {
	target:  Target,
	label:   [2]u8,
	ordinal: int,
}

State :: struct {
	allocator: mem.Allocator,
	targets:   [dynamic]Labeled_Target,
	hints:     [dynamic]Hint,
	alphabet:  string,
	prefix:    u8,
	active:    bool,
}

state_init :: proc(state: ^State, allocator := context.allocator) {
	assert(state != nil)
	state^ = State{allocator = allocator}
	state.targets = make([dynamic]Labeled_Target, allocator)
	state.hints = make([dynamic]Hint, allocator)
}

state_destroy :: proc(state: ^State) {
	if state == nil {return}
	if state.alphabet != "" {delete(state.alphabet, state.allocator)}
	delete(state.targets)
	delete(state.hints)
	state^ = {}
}

cancel :: proc(state: ^State) {
	if state == nil {return}
	clear(&state.targets)
	clear(&state.hints)
	state.prefix = 0
	state.active = false
}

is_active :: proc(state: ^State) -> bool {
	return state != nil && state.active
}

visible_hints :: proc(state: ^State) -> []Hint {
	if state == nil || !state.active {return nil}
	return state.hints[:]
}

valid_alphabet :: proc(alphabet: string) -> bool {
	if len(alphabet) < 2 {return false}
	for value, index in alphabet {
		if value < 'a' || value > 'z' {return false}
		for previous in 0 ..< index {
			if alphabet[previous] == u8(value) {return false}
		}
	}
	return true
}

target_precedes :: proc(a, b: Labeled_Target, y_axis: Y_Axis_Direction) -> bool {
	a_top, b_top := a.target.rect.y + a.target.rect.h, b.target.rect.y + b.target.rect.h
	if y_axis == .Down {a_top, b_top = a.target.rect.y, b.target.rect.y}
	if a_top != b_top {
		if y_axis == .Up {return a_top > b_top}
		return a_top < b_top
	}
	if a.target.rect.x != b.target.rect.x {return a.target.rect.x < b.target.rect.x}
	return a.ordinal < b.ordinal
}

sort_targets :: proc(targets: ^[dynamic]Labeled_Target, y_axis: Y_Axis_Direction) {
	for index in 1 ..< len(targets) {
		value := targets[index]
		position := index
		for position > 0 && target_precedes(value, targets[position - 1], y_axis) {
			targets[position] = targets[position - 1]
			position -= 1
		}
		targets[position] = value
	}
}

rebuild_hints :: proc(state: ^State) {
	clear(&state.hints)
	for labeled in state.targets {
		if state.prefix != 0 && labeled.label[0] != state.prefix {continue}
		hint := Hint{target = labeled.target, label = labeled.label, label_length = 2}
		if state.prefix != 0 {
			hint.label[0] = labeled.label[1]
			hint.label_length = 1
		}
		append(&state.hints, hint)
	}
}

begin :: proc(state: ^State, targets: []Target, config := Config{}) -> Begin_Error {
	assert(state != nil, "Call flash.state_init before flash.begin")
	cancel(state)
	alphabet := config.alphabet
	if len(alphabet) == 0 {alphabet = DEFAULT_ALPHABET}
	if !valid_alphabet(alphabet) {return .Invalid_Alphabet}
	if len(targets) > len(alphabet) * len(alphabet) {return .Too_Many_Targets}
	if state.alphabet != "" {delete(state.alphabet, state.allocator)}
	state.alphabet = strings.clone(alphabet, state.allocator)
	for target, ordinal in targets {
		append(&state.targets, Labeled_Target{target = target, ordinal = ordinal})
	}
	sort_targets(&state.targets, config.y_axis)
	for &target, index in state.targets {
		target.label = [2]u8{
			alphabet[index / len(alphabet)],
			alphabet[index % len(alphabet)],
		}
	}
	state.active = len(state.targets) > 0
	if state.active {rebuild_hints(state)}
	return .None
}

normalize_key :: proc(key: u8) -> u8 {
	if key >= 'A' && key <= 'Z' {return key + ('a' - 'A')}
	return key
}

consume :: proc(state: ^State, key: u8) -> Input_Result {
	if !is_active(state) {return {kind = .Ignored}}
	normalized := normalize_key(key)
	if state.prefix == 0 {
		for target in state.targets {
			if target.label[0] != normalized {continue}
			state.prefix = normalized
			rebuild_hints(state)
			return {kind = .Pending}
		}
		cancel(state)
		return {kind = .Cancelled}
	}
	for target in state.targets {
		if target.label[0] == state.prefix && target.label[1] == normalized {
			id := target.target.id
			cancel(state)
			return {kind = .Activated, target_id = id}
		}
	}
	cancel(state)
	return {kind = .Cancelled}
}
