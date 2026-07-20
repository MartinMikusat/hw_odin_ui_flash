# Odin UI Flash

A renderer-independent Odin package for selecting visible interface targets with short keyboard labels.

## AI-assisted development disclosure

**This project was built using GPT-5.**

## Behavior

An application supplies visible targets with opaque identifiers, rectangles, and badge anchors. The package sorts the targets and assigns deterministic two-letter labels. It consumes the two label characters and returns the selected identifier.

The package does not render labels or execute application actions. This separation lets Metal, OpenGL, software, and native renderers use the same selection state.

The default alphabet is `asdfghjklqwertyuiopzxcvbnm`. Labels use lowercase ASCII characters. Input is case-insensitive.

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
	{id=1, rect={20, 40, 120, 28}, anchor=.Top_Left},
	{id=2, rect={160, 40, 120, 28}, anchor=.Top_Left},
}

if flash.begin(&jump, targets) != .None {
	// Report the configuration or capacity error.
}
```

Draw the borrowed hints while the state is active. A hint contains the target rectangle, anchor, label bytes, and label length. After the first character, the package removes nonmatching hints and exposes only the second character.

Pass label characters to `flash.consume`. An `Activated` result contains the opaque target identifier. An invalid character returns `Cancelled` and closes the session. Call `flash.cancel` for Escape, pointer input, scrolling, resize, or another interface transition.

## Ordering and coordinates

The default Y-axis direction is `Up`. The package sorts higher top edges first, then sorts left edges first. Use `.Down` when Y coordinates increase toward the bottom of the view. Targets with identical rectangles keep their registration order.

The package supports at most `alphabet_length²` targets in one session. `begin` rejects a larger snapshot and leaves the state inactive.

## Ownership

`begin` copies and sorts the target snapshot. The state owns its target, hint, and alphabet storage. `visible_hints` returns a borrowed slice that remains valid until the next state mutation.

The application owns action payloads and maps each returned `Target_ID` to one payload. Do not put renderer or application pointers in this package.

## Verification

```sh
odin test .
```
