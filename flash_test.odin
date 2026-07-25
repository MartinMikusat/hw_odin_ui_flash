package flash

import "core:testing"
import "core:strings"

target :: proc(id: u64, label: string, x, y: f64, anchor := Anchor.Top_Left) -> Target {
	return {id = Target_ID(id), label = label, rect = {x, y, 20, 10}, anchor = anchor}
}

@(test)
labels_normalize_to_lowercase_ascii_letters_and_digits_test :: proc(t: ^testing.T) {
	value := normalize_label("Search timed-transcript 2")
	defer delete(value)
	testing.expect_value(t, value, "searchtimedtranscript2")
}

@(test)
spatial_order_controls_hint_order_only_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{
		target(1, "play", 20, 0),
		target(2, "search", 0, 20),
		target(3, "stop", 0, 0),
	}
	testing.expect_value(t, begin(&state, targets), Begin_Error.None)
	hints := visible_hints(&state)
	testing.expect_value(t, hints[0].target.id, Target_ID(2))
	testing.expect_value(t, hints[0].label, "se")
	testing.expect_value(t, hints[1].target.id, Target_ID(3))
	testing.expect_value(t, hints[2].target.id, Target_ID(1))
}

@(test)
down_axis_and_identical_rectangles_keep_stable_order_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{
		target(8, "first", 4, 4),
		target(9, "second", 4, 4, .Top_Right),
		target(10, "third", 4, 20),
	}
	_ = begin(&state, targets, Config{y_axis = .Down})
	hints := visible_hints(&state)
	testing.expect_value(t, hints[0].target.id, Target_ID(8))
	testing.expect_value(t, hints[1].target.id, Target_ID(9))
	testing.expect_value(t, hints[2].target.id, Target_ID(10))
}

@(test)
compact_mnemonics_do_not_depend_on_target_order_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{
		target(1, "search timed transcript", 0, 0),
		target(2, "set start", 0, 0),
		target(3, "set end", 0, 0),
		target(4, "play", 0, 0),
	}
	_ = begin(&state, targets)
	hints := visible_hints(&state)
	testing.expect_value(t, hints[0].label, "sa")
	testing.expect_value(t, hints[1].label, "sts")
	testing.expect_value(t, hints[2].label, "ste")
	testing.expect_value(t, hints[3].label, "pl")
}

@(test)
typing_filters_hints_and_removes_the_typed_prefix_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{
		target(1, "search timed transcript", 0, 0),
		target(2, "set start", 0, 0),
		target(3, "set end", 0, 0),
	}
	_ = begin(&state, targets)
	testing.expect_value(t, consume(&state, 'S').kind, Input_Result_Kind.Pending)
	testing.expect_value(t, typed_prefix(&state), "s")
	hints := visible_hints(&state)
	testing.expect_value(t, hints[0].label, "a")
	testing.expect_value(t, hints[1].label, "ts")
	testing.expect_value(t, hints[2].label, "te")
}

@(test)
target_activates_when_its_minimum_unique_prefix_is_complete_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{
		target(42, "play", 0, 0),
		target(43, "pause", 0, 0),
	}
	_ = begin(&state, targets)
	testing.expect_value(t, consume(&state, 'p').kind, Input_Result_Kind.Pending)
	result := consume(&state, 'l')
	testing.expect_value(t, result.kind, Input_Result_Kind.Activated)
	testing.expect_value(t, result.target_id, Target_ID(42))
	testing.expect(t, !is_active(&state))
}

@(test)
adding_an_unrelated_target_does_not_change_existing_prefixes_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	base := []Target{target(1, "play", 0, 0), target(2, "pause", 0, 0)}
	_ = begin(&state, base)
	testing.expect_value(t, visible_hints(&state)[0].label, "pl")
	with_source := []Target{
		target(1, "play", 0, 0),
		target(2, "pause", 0, 0),
		target(3, "vital skill smooth voice", 0, 20),
	}
	_ = begin(&state, with_source)
	play_after := visible_hints(&state)[1].label
	testing.expect_value(t, play_after, "pl")
}

@(test)
invalid_key_cancels_and_is_consumed_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{target(1, "play", 0, 0)}
	_ = begin(&state, targets)
	testing.expect_value(t, consume(&state, '-').kind, Input_Result_Kind.Cancelled)
	testing.expect(t, !is_active(&state))
}

@(test)
empty_and_invalid_sessions_remain_inactive_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	testing.expect_value(t, begin(&state, nil), Begin_Error.None)
	testing.expect(t, !is_active(&state))
	invalid := []Target{target(1, "---", 0, 0)}
	testing.expect(t, !label_is_valid(invalid[0].label))
	testing.expect_value(t, begin(&state, invalid), Begin_Error.Invalid_Target_Label)
	testing.expect(t, !is_active(&state))
	testing.expect(t, label_is_valid("play 2"))
}

@(test)
duplicate_labels_form_a_group_and_prefix_labels_get_distinct_shortcuts_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	duplicates := []Target{target(1, "Play", 0, 0), target(2, "play!", 0, 0)}
	testing.expect_value(t, begin(&state, duplicates), Begin_Error.None)
	testing.expect_value(t, consume(&state, 'p').kind, Input_Result_Kind.Pending)
	testing.expect_value(t, consume(&state, 'l').kind, Input_Result_Kind.Group_Selected)
	cancel(&state)
	prefixes := []Target{target(1, "play", 0, 0), target(2, "play source", 0, 0)}
	testing.expect_value(t, begin(&state, prefixes), Begin_Error.None)
	testing.expect_value(t, visible_hints(&state)[0].label, "pl")
	testing.expect_value(t, visible_hints(&state)[1].label, "ps")
}

@(test)
cancel_clears_query_hints_and_owned_targets_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{target(1, "play", 0, 0)}
	_ = begin(&state, targets)
	_ = consume(&state, 'p')
	cancel(&state)
	testing.expect(t, !is_active(&state))
	testing.expect_value(t, len(visible_hints(&state)), 0)
	testing.expect_value(t, len(state.targets), 0)
	testing.expect_value(t, len(state.query), 0)
}

@(test)
shared_runs_collapse_to_compact_mnemonics_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{
		target(1, "mark in", 0, 30),
		target(2, "mark out", 0, 20),
		target(3, "filter source register", 0, 10),
		target(4, "faster", 0, 0),
	}
	testing.expect_value(t, begin(&state, targets), Begin_Error.None)
	hints := visible_hints(&state)
	testing.expect_value(t, hints[0].label, "mi")
	testing.expect_value(t, hints[1].label, "mo")
	testing.expect_value(t, hints[2].label, "fi")
	testing.expect_value(t, hints[3].label, "fa")
}

@(test)
colliding_mnemonics_select_cycle_and_activate_a_group_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{
		target(1, "abcdefx", 0, 30),
		target(2, "abcdefy", 0, 20),
		target(3, "ax", 0, 10),
		target(4, "abz", 0, 0),
	}
	testing.expect_value(t, begin(&state, targets), Begin_Error.None)
	testing.expect_value(t, consume(&state, 'a').kind, Input_Result_Kind.Pending)
	testing.expect_value(t, consume(&state, 'b').kind, Input_Result_Kind.Pending)
	testing.expect_value(t, consume(&state, 'c').kind, Input_Result_Kind.Group_Selected)
	testing.expect(t, has_group_selection(&state))
	hints := visible_hints(&state)
	testing.expect_value(t, len(hints), 2)
	testing.expect_value(t, hints[0].label, "abc")
	testing.expect(t, hints[0].selected)
	testing.expect(t, !hints[1].selected)
	testing.expect(t, cycle_selection(&state, .Next))
	hints = visible_hints(&state)
	testing.expect(t, !hints[0].selected)
	testing.expect(t, hints[1].selected)
	result := activate_selection(&state)
	testing.expect_value(t, result.kind, Input_Result_Kind.Activated)
	testing.expect_value(t, result.target_id, Target_ID(2))
	testing.expect(t, !is_active(&state))
}

@(test)
group_selection_wraps_in_both_directions_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{
		target(1, "abcdefx", 0, 20),
		target(2, "abcdefy", 0, 10),
		target(3, "ax", 0, 0),
		target(4, "abz", 0, -10),
	}
	_ = begin(&state, targets)
	_ = consume(&state, 'a')
	_ = consume(&state, 'b')
	_ = consume(&state, 'c')
	testing.expect(t, cycle_selection(&state, .Previous))
	hints := visible_hints(&state)
	testing.expect(t, hints[1].selected)
	testing.expect(t, cycle_selection(&state, .Next))
	hints = visible_hints(&state)
	testing.expect(t, hints[0].selected)
}

@(test)
shortcut_prefix_families_collapse_to_one_group_code_test :: proc(t: ^testing.T) {
	targets := make([dynamic]Labeled_Target)
	defer {
		for &target in targets {delete(target.shortcut)}
		delete(targets)
	}
	append(&targets, Labeled_Target{shortcut = strings.clone("ab")})
	append(&targets, Labeled_Target{shortcut = strings.clone("abc")})
	append(&targets, Labeled_Target{shortcut = strings.clone("abcd")})
	collapse_shortcut_prefixes(&targets, context.allocator)
	for &target in targets {
		testing.expect_value(t, target.shortcut, "ab")
	}
}
