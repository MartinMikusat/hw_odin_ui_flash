package flash

import "core:testing"

target :: proc(id: u64, x, y: f64, anchor := Anchor.Top_Left) -> Target {
	return {id = Target_ID(id), rect = {x, y, 20, 10}, anchor = anchor}
}

@(test)
spatial_order_uses_top_then_left_for_up_axis_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{target(1, 20, 0), target(2, 0, 20), target(3, 0, 0)}
	testing.expect_value(t, begin(&state, targets), Begin_Error.None)
	hints := visible_hints(&state)
	testing.expect_value(t, hints[0].target.id, Target_ID(2))
	testing.expect_value(t, hints[1].target.id, Target_ID(3))
	testing.expect_value(t, hints[2].target.id, Target_ID(1))
}

@(test)
spatial_order_supports_down_axis_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{target(1, 0, 20), target(2, 0, 0)}
	_ = begin(&state, targets, Config{y_axis = .Down})
	testing.expect_value(t, visible_hints(&state)[0].target.id, Target_ID(2))
}

@(test)
identical_rectangles_keep_registration_order_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{target(8, 4, 4), target(9, 4, 4, .Top_Right)}
	_ = begin(&state, targets)
	testing.expect_value(t, visible_hints(&state)[0].target.id, Target_ID(8))
	testing.expect_value(t, visible_hints(&state)[1].target.id, Target_ID(9))
}

@(test)
labels_use_the_configured_alphabet_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{target(1, 0, 20), target(2, 0, 10), target(3, 0, 0)}
	_ = begin(&state, targets, Config{alphabet = "abc"})
	hints := visible_hints(&state)
	testing.expect_value(t, hints[0].label, [2]u8{'a', 'a'})
	testing.expect_value(t, hints[1].label, [2]u8{'a', 'b'})
	testing.expect_value(t, hints[2].label, [2]u8{'a', 'c'})
}

@(test)
first_key_filters_and_exposes_suffix_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{target(1, 0, 30), target(2, 0, 20), target(3, 0, 10)}
	_ = begin(&state, targets, Config{alphabet = "ab"})
	testing.expect_value(t, consume(&state, 'a').kind, Input_Result_Kind.Pending)
	hints := visible_hints(&state)
	testing.expect_value(t, len(hints), 2)
	testing.expect_value(t, hints[0].label_length, 1)
	testing.expect_value(t, hints[0].label[0], u8('a'))
	testing.expect_value(t, hints[1].label[0], u8('b'))
}

@(test)
second_key_activates_and_closes_session_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{target(42, 0, 0)}
	_ = begin(&state, targets)
	_ = consume(&state, 'A')
	result := consume(&state, 'A')
	testing.expect_value(t, result.kind, Input_Result_Kind.Activated)
	testing.expect_value(t, result.target_id, Target_ID(42))
	testing.expect(t, !is_active(&state))
}

@(test)
invalid_key_cancels_and_is_consumed_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{target(1, 0, 0)}
	_ = begin(&state, targets)
	testing.expect_value(t, consume(&state, 'z').kind, Input_Result_Kind.Cancelled)
	testing.expect(t, !is_active(&state))
}

@(test)
empty_session_does_not_activate_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	testing.expect_value(t, begin(&state, nil), Begin_Error.None)
	testing.expect(t, !is_active(&state))
	testing.expect_value(t, consume(&state, 'a').kind, Input_Result_Kind.Ignored)
}

@(test)
capacity_and_alphabet_validation_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := [5]Target{}
	testing.expect_value(t, begin(&state, targets[:], Config{alphabet = "ab"}), Begin_Error.Too_Many_Targets)
	testing.expect_value(t, begin(&state, nil, Config{alphabet = "aa"}), Begin_Error.Invalid_Alphabet)
	testing.expect_value(t, begin(&state, nil, Config{alphabet = "A"}), Begin_Error.Invalid_Alphabet)
}

@(test)
cancel_clears_an_active_session_test :: proc(t: ^testing.T) {
	state: State
	state_init(&state)
	defer state_destroy(&state)
	targets := []Target{target(1, 0, 0)}
	_ = begin(&state, targets)
	cancel(&state)
	testing.expect(t, !is_active(&state))
	testing.expect_value(t, len(visible_hints(&state)), 0)
}
