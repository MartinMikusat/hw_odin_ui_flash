# Odin UI Flash

A renderer-independent Odin package for selecting visible interface targets with compact keyboard mnemonics.

## AI-assisted development disclosure

Models used:

- **GPT-5.6-Sol**

## Behavior

An application supplies each visible target with an opaque identifier, a functional label, a rectangle, and a badge anchor. The package normalizes each label to lowercase ASCII letters and digits. It removes spaces, punctuation, and non-ASCII characters.

The package keeps the first label character and characters at the earliest divergence points. It generates mnemonics with two to three characters by default. For example, `mark in` becomes `mi` and `mark out` becomes `mo`.

Typing filters targets by their generated mnemonics. A unique mnemonic activates its target immediately. An invalid character or a mnemonic with no matches cancels the session.

Generated mnemonic collisions form one selection group. The package selects the first spatial target. Tab can move forward, Shift-Tab can move backward, and Return can activate the selected target.

Duplicate normalized labels form one selection group. Functional labels can contain prefix relationships.

The package does not render badges or execute application actions. This separation lets Metal, OpenGL, software, and native renderers use the same selection state.

## Integration

Initialize one state object and destroy it during application shutdown:

```odin
import flash "flash:."

jump: flash.State
flash.state_init(&jump)
defer flash.state_destroy(&jump)
```

Build a target snapshot when the leader key is pressed:

```odin
targets := []flash.Target{
	{id=1, label="play", rect={20, 40, 120, 28}, anchor=.Top_Left},
	{id=2, label="pause", rect={160, 40, 120, 28}, anchor=.Top_Left},
}

if flash.begin(&jump, targets) != .None {
	// Report the invalid target label.
}
```

Draw the borrowed hints while the state is active. A hint contains the target, the remaining mnemonic text, and its selection state. The hint for `play` is initially `pl`. After the user types `p`, the hint is `l`.

Pass ASCII letters and digits to `flash.consume`. An `Activated` result contains the opaque target identifier. `Group_Selected` keeps an ambiguous mnemonic active.

Call `cycle_selection` for Tab or Shift-Tab. Call `activate_selection` for Return. Invalid input returns `Cancelled` and closes the session.

Call `flash.cancel` for Escape, pointer input, scrolling, resize, or another interface transition.

## Ordering and coordinates

The default Y-axis direction is `Up`. The package sorts higher top edges first, then sorts left edges first. Use `.Down` when Y coordinates increase toward the bottom of the view. Spatial sorting controls hint order and ambiguity-group traversal.

Targets with identical rectangles keep their registration order. This lets an application use separate badge anchors for primary and secondary actions on one control.

## Ownership

`begin` copies target labels, generated mnemonics, and the target snapshot. The state owns all session storage. `visible_hints` and `typed_prefix` return borrowed strings that remain valid until the next state mutation.

The application owns action payloads and maps each returned `Target_ID` to one payload. Do not put renderer or application pointers in this package.

## Verification

```sh
odin test .
```
