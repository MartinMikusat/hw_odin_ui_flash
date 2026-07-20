package flash

import "core:mem"
import "core:strings"

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
	label:  string,
	rect:   Rect,
	anchor: Anchor,
}

Config :: struct {
	y_axis:                Y_Axis_Direction,
	minimum_prefix_length: int,
}

Begin_Error :: enum {
	None,
	Invalid_Target_Label,
	Duplicate_Target_Label,
	Prefix_Conflict,
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
	target: Target,
	label:  string,
}

Labeled_Target :: struct {
	target:          Target,
	normalized:      string,
	required_length: int,
	ordinal:         int,
}

State :: struct {
	allocator: mem.Allocator,
	targets:   [dynamic]Labeled_Target,
	hints:     [dynamic]Hint,
	query:     [dynamic]u8,
	active:    bool,
}

state_init :: proc(state: ^State, allocator := context.allocator) {
	assert(state != nil)
	state^ = State{allocator = allocator}
	state.targets = make([dynamic]Labeled_Target, allocator)
	state.hints = make([dynamic]Hint, allocator)
	state.query = make([dynamic]u8, allocator)
}

clear_targets :: proc(state: ^State) {
	for &target in state.targets {
		delete(target.target.label, state.allocator)
		delete(target.normalized, state.allocator)
	}
	clear(&state.targets)
}

state_destroy :: proc(state: ^State) {
	if state == nil {return}
	clear_targets(state)
	delete(state.targets)
	delete(state.hints)
	delete(state.query)
	state^ = {}
}

cancel :: proc(state: ^State) {
	if state == nil {return}
	clear_targets(state)
	clear(&state.hints)
	clear(&state.query)
	state.active = false
}

is_active :: proc(state: ^State) -> bool {
	return state != nil && state.active
}

visible_hints :: proc(state: ^State) -> []Hint {
	if state == nil || !state.active {return nil}
	return state.hints[:]
}

typed_prefix :: proc(state: ^State) -> string {
	if state == nil || !state.active {return ""}
	return string(state.query[:])
}

normalize_character :: proc(value: u8) -> (u8, bool) {
	if value >= 'A' && value <= 'Z' {return value + ('a' - 'A'), true}
	if value >= 'a' && value <= 'z' || value >= '0' && value <= '9' {return value, true}
	return 0, false
}

normalize_label :: proc(label: string, allocator := context.allocator) -> string {
	bytes := make([dynamic]u8, 0, len(label), allocator)
	defer delete(bytes)
	for value in label {
		if value > 127 {continue}
		if normalized, ok := normalize_character(u8(value)); ok {append(&bytes, normalized)}
	}
	return strings.clone(string(bytes[:]), allocator)
}

common_prefix_length :: proc(a, b: string) -> int {
	count := min(len(a), len(b))
	for index in 0 ..< count {
		if a[index] != b[index] {return index}
	}
	return count
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

starts_with_query :: proc(value: string, query: []u8) -> bool {
	if len(query) > len(value) {return false}
	for character, index in query {
		if value[index] != character {return false}
	}
	return true
}

rebuild_hints :: proc(state: ^State) {
	clear(&state.hints)
	for &labeled in state.targets {
		if !starts_with_query(labeled.normalized, state.query[:]) {continue}
		start := min(len(state.query), labeled.required_length)
		append(
			&state.hints,
			Hint{
				target = labeled.target,
				label = labeled.normalized[start:labeled.required_length],
			},
		)
	}
}

begin :: proc(state: ^State, targets: []Target, config := Config{}) -> Begin_Error {
	assert(state != nil, "Call flash.state_init before flash.begin")
	cancel(state)
	minimum := config.minimum_prefix_length
	if minimum <= 0 {minimum = 2}
	for target, ordinal in targets {
		label := strings.clone(target.label, state.allocator)
		normalized := normalize_label(target.label, state.allocator)
		if len(normalized) == 0 {
			delete(label, state.allocator)
			delete(normalized, state.allocator)
			cancel(state)
			return .Invalid_Target_Label
		}
		owned_target := target
		owned_target.label = label
		append(
			&state.targets,
			Labeled_Target{
				target = owned_target,
				normalized = normalized,
				required_length = min(minimum, len(normalized)),
				ordinal = ordinal,
			},
		)
	}
	for &target, index in state.targets {
		for &other, other_index in state.targets {
			if index == other_index {continue}
			common := common_prefix_length(target.normalized, other.normalized)
			if common == len(target.normalized) {
				error := Begin_Error.Prefix_Conflict
				if len(target.normalized) == len(other.normalized) {error = .Duplicate_Target_Label}
				cancel(state)
				return error
			}
			target.required_length = max(target.required_length, common + 1)
		}
	}
	sort_targets(&state.targets, config.y_axis)
	state.active = len(state.targets) > 0
	if state.active {rebuild_hints(state)}
	return .None
}

consume :: proc(state: ^State, key: u8) -> Input_Result {
	if !is_active(state) {return {kind = .Ignored}}
	normalized, valid := normalize_character(key)
	if !valid {
		cancel(state)
		return {kind = .Cancelled}
	}
	append(&state.query, normalized)
	match_count := 0
	match: ^Labeled_Target
	for &target in state.targets {
		if !starts_with_query(target.normalized, state.query[:]) {continue}
		match = &target
		match_count += 1
	}
	if match_count == 0 {
		cancel(state)
		return {kind = .Cancelled}
	}
	if match_count == 1 && len(state.query) >= match.required_length {
		id := match.target.id
		cancel(state)
		return {kind = .Activated, target_id = id}
	}
	rebuild_hints(state)
	return {kind = .Pending}
}
