package flash

import "core:testing"

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
minimum_unique_prefixes_do_not_depend_on_target_order_test :: proc(t: ^testing.T) {
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
	testing.expect_value(t, hints[0].label, "sea")
	testing.expect_value(t, hints[1].label, "sets")
	testing.expect_value(t, hints[2].label, "sete")
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
	testing.expect_value(t, hints[0].label, "ea")
	testing.expect_value(t, hints[1].label, "ets")
	testing.expect_value(t, hints[2].label, "ete")
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
	testing.expect_value(t, begin(&state, invalid), Begin_Error.Invalid_Target_Label)
	testing.expect(t, !is_active(&state))
}

@(test)
duplicate_and_prefix_labels_are_rejected_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	duplicates := []Target{target(1, "Play", 0, 0), target(2, "play!", 0, 0)}
	testing.expect_value(t, begin(&state, duplicates), Begin_Error.Duplicate_Target_Label)
	prefixes := []Target{target(1, "play", 0, 0), target(2, "play source", 0, 0)}
	testing.expect_value(t, begin(&state, prefixes), Begin_Error.Prefix_Conflict)
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
