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
	y_axis:                 Y_Axis_Direction,
	minimum_shortcut_length: int,
	maximum_shortcut_length: int,
}

Begin_Error :: enum {
	None,
	Invalid_Target_Label,
}

Input_Result_Kind :: enum {
	Ignored,
	Pending,
	Group_Selected,
	Activated,
	Cancelled,
}

Selection_Direction :: enum {
	Previous,
	Next,
}

Input_Result :: struct {
	kind:      Input_Result_Kind,
	target_id: Target_ID,
}

Hint :: struct {
	target: Target,
	label:  string,
	selected: bool,
}

Labeled_Target :: struct {
	target:     Target,
	normalized: string,
	shortcut:   string,
	ordinal:    int,
}

State :: struct {
	allocator: mem.Allocator,
	targets:   [dynamic]Labeled_Target,
	hints:     [dynamic]Hint,
	query:     [dynamic]u8,
	active:    bool,
	group_active: bool,
	group_selection: int,
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
		delete(target.shortcut, state.allocator)
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
	state.group_active = false
	state.group_selection = 0
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

label_is_valid :: proc(label: string) -> bool {
	for value in label {
		if value > 127 {continue}
		if _, ok := normalize_character(u8(value)); ok {return true}
	}
	return false
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

is_prefix :: proc(prefix, value: string) -> bool {
	if len(prefix) > len(value) {return false}
	for index in 0 ..< len(prefix) {
		if value[index] != prefix[index] {return false}
	}
	return true
}

build_shortcut :: proc(
	target_index: int,
	targets: []Labeled_Target,
	minimum, maximum: int,
	allocator: mem.Allocator,
) -> string {
	normalized := targets[target_index].normalized
	selected := make([]bool, len(normalized), context.temp_allocator)
	defer delete(selected, context.temp_allocator)
	selected[0] = true
	for &other, other_index in targets {
		if other_index == target_index {continue}
		difference := common_prefix_length(normalized, other.normalized)
		if difference < len(normalized) {selected[difference] = true}
	}
	selected_count := 0
	for value in selected {if value {selected_count += 1}}
	for index := 1; index < len(selected) && selected_count < minimum; index += 1 {
		if selected[index] {continue}
		selected[index] = true
		selected_count += 1
	}
	bytes := make([dynamic]u8, 0, min(maximum, selected_count), context.temp_allocator)
	defer delete(bytes)
	for value, index in normalized {
		if !selected[index] {continue}
		append(&bytes, u8(value))
		if len(bytes) >= maximum {break}
	}
	return strings.clone(string(bytes[:]), allocator)
}

collapse_shortcut_prefixes :: proc(targets: ^[dynamic]Labeled_Target, allocator: mem.Allocator) {
	changed := true
	for changed {
		changed = false
		for &target, index in targets {
			for other_index in index + 1 ..< len(targets) {
				other := &targets[other_index]
				shorter := target.shortcut
				longer := other.shortcut
				replace_other := true
				if len(shorter) > len(longer) {
					shorter, longer = longer, shorter
					replace_other = false
				}
				if len(shorter) == len(longer) || !is_prefix(shorter, longer) {continue}
				if replace_other {
					delete(other.shortcut, allocator)
					other.shortcut = strings.clone(shorter, allocator)
				} else {
					delete(target.shortcut, allocator)
					target.shortcut = strings.clone(shorter, allocator)
				}
				changed = true
			}
		}
	}
}

group_count :: proc(state: ^State) -> int {
	if state == nil || !state.group_active {return 0}
	count := 0
	for &target in state.targets {
		if target.shortcut == string(state.query[:]) {count += 1}
	}
	return count
}

rebuild_hints :: proc(state: ^State) {
	clear(&state.hints)
	group_index := 0
	for &labeled in state.targets {
		if !starts_with_query(labeled.shortcut, state.query[:]) {continue}
		label := labeled.shortcut[min(len(state.query), len(labeled.shortcut)):]
		selected := false
		if state.group_active && len(state.query) == len(labeled.shortcut) {
			label = labeled.shortcut
			selected = group_index == state.group_selection
			group_index += 1
		}
		append(
			&state.hints,
			Hint{
				target = labeled.target,
				label = label,
				selected = selected,
			},
		)
	}
}

begin :: proc(state: ^State, targets: []Target, config := Config{}) -> Begin_Error {
	assert(state != nil, "Call flash.state_init before flash.begin")
	cancel(state)
	minimum := config.minimum_shortcut_length
	if minimum <= 0 {minimum = 2}
	maximum := config.maximum_shortcut_length
	if maximum <= 0 {maximum = 3}
	maximum = max(minimum, maximum)
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
				ordinal = ordinal,
			},
		)
	}
	for &target, index in state.targets {
		target.shortcut = build_shortcut(index, state.targets[:], minimum, maximum, state.allocator)
	}
	collapse_shortcut_prefixes(&state.targets, state.allocator)
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
		if !starts_with_query(target.shortcut, state.query[:]) {continue}
		match = &target
		match_count += 1
	}
	if match_count == 0 {
		cancel(state)
		return {kind = .Cancelled}
	}
	if match_count == 1 && len(state.query) == len(match.shortcut) {
		id := match.target.id
		cancel(state)
		return {kind = .Activated, target_id = id}
	}
	exact := true
	for &target in state.targets {
		if !starts_with_query(target.shortcut, state.query[:]) {continue}
		if len(target.shortcut) != len(state.query) {exact = false; break}
	}
	if exact {
		state.group_active = true
		state.group_selection = 0
		rebuild_hints(state)
		return {kind = .Group_Selected}
	}
	rebuild_hints(state)
	return {kind = .Pending}
}

has_group_selection :: proc(state: ^State) -> bool {
	return state != nil && state.active && state.group_active
}

cycle_selection :: proc(state: ^State, direction: Selection_Direction) -> bool {
	count := group_count(state)
	if count <= 1 {return false}
	if direction == .Next {
		state.group_selection = (state.group_selection + 1) % count
	} else {
		state.group_selection = (state.group_selection + count - 1) % count
	}
	rebuild_hints(state)
	return true
}

activate_selection :: proc(state: ^State) -> Input_Result {
	if !has_group_selection(state) {return {kind = .Ignored}}
	group_index := 0
	for &target in state.targets {
		if target.shortcut != string(state.query[:]) {continue}
		if group_index == state.group_selection {
			id := target.target.id
			cancel(state)
			return {kind = .Activated, target_id = id}
		}
		group_index += 1
	}
	cancel(state)
	return {kind = .Cancelled}
}
