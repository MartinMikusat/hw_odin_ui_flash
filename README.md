# Odin UI Flash

A renderer-independent Odin package for selecting visible interface targets from stable name prefixes.

## AI-assisted development disclosure

**This project was built using GPT-5.**

## Behavior

An application supplies each visible target with an opaque identifier, a functional label, a rectangle, and a badge anchor. The package normalizes each label to lowercase ASCII letters and digits. It removes spaces, punctuation, and non-ASCII characters.

The package calculates the shortest unique prefix for each normalized label. A prefix contains at least two characters by default. Adding an unrelated target does not change existing prefixes.

Typing filters targets by their normalized labels. The package activates a target when the typed prefix identifies one target and reaches its required length. An invalid character or a prefix with no matches cancels the session.

Target labels must be unique and prefix-free after normalization. `begin` reports a duplicate or prefix conflict instead of creating an unreachable target.

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
	// Report the invalid or conflicting target label.
}
```

Draw the borrowed hints while the state is active. A hint contains the target and the untyped part of its required prefix. The hint for `play` is initially `pl`. After the user types `p`, the hint is `l`.

Pass ASCII letters and digits to `flash.consume`. An `Activated` result contains the opaque target identifier. Invalid input returns `Cancelled` and closes the session. Call `flash.cancel` for Escape, pointer input, scrolling, resize, or another interface transition.

## Ordering and coordinates

The default Y-axis direction is `Up`. The package sorts higher top edges first, then sorts left edges first. Use `.Down` when Y coordinates increase toward the bottom of the view. Spatial sorting changes only hint draw order. It does not change the required prefixes.

Targets with identical rectangles keep their registration order. This lets an application use separate badge anchors for primary and secondary actions on one control.

## Ownership

`begin` copies target labels, normalizes them, and copies the target snapshot. The state owns all session storage. `visible_hints` and `typed_prefix` return borrowed strings that remain valid until the next state mutation.

The application owns action payloads and maps each returned `Target_ID` to one payload. Do not put renderer or application pointers in this package.

## Verification

```sh
odin test .
```
