import SwiftUI
import ParsecSDK

// Touch counterpart of GamepadController: same CParsec calls, fed from on-screen controls.
// Uses its own controller id so a physical pad (id 1) at rest doesnt keep zeroing the touch sticks.
final class VirtualGamepadInput: ObservableObject {

	static let controllerId: UInt32 = 2

	private var pressed = Set<ParsecGamepadButton.RawValue>()
	private var axes = [ParsecGamepadAxis.RawValue: Int16]()

	func ButtonFloatToParsecInt(_ value: Float) -> Int16 {
		let newval: Float = (65535.0*value-1.0)/2.0
		return Int16(newval)
	}

	func buttonChangedHandler(_ button: ParsecGamepadButton, _ isPressed: Bool) {
		if isPressed {
			guard pressed.insert(button.rawValue).inserted else { return }
		} else {
			guard pressed.remove(button.rawValue) != nil else { return }
		}
		guard ParsecBackgroundManager.shared.hasActiveConnection else { return }
		CParsec.sendGameControllerButtonMessage(controllerId: VirtualGamepadInput.controllerId, button, pressed: isPressed)
	}

	func triggerChangedHandler(_ axis: ParsecGamepadAxis, _ value: Float) {
		axisChanged(axis, ButtonFloatToParsecInt(value))
	}

	func thumbLstickChangedHandler(_ xvalue: Float, _ yvalue: Float) {
		axisChanged(GAMEPAD_AXIS_LX, ButtonFloatToParsecInt(xvalue))
		axisChanged(GAMEPAD_AXIS_LY, ButtonFloatToParsecInt(yvalue))
	}

	func thumbRstickChangedHandler(_ xvalue: Float, _ yvalue: Float) {
		axisChanged(GAMEPAD_AXIS_RX, ButtonFloatToParsecInt(xvalue))
		axisChanged(GAMEPAD_AXIS_RY, ButtonFloatToParsecInt(yvalue))
	}

	// drag updates arrive far faster than the stick value actually moves, only send real changes
	private func axisChanged(_ axis: ParsecGamepadAxis, _ value: Int16) {
		guard axes[axis.rawValue, default: 0] != value else { return }
		axes[axis.rawValue] = value
		guard ParsecBackgroundManager.shared.hasActiveConnection else { return }
		CParsec.sendGameControllerAxisMessage(controllerId: VirtualGamepadInput.controllerId, axis, value)
	}

	// back to neutral without unplugging, so hiding the overlay doesnt look like a controller disconnect to games
	func releaseAll() {
		for raw in pressed {
			buttonChangedHandler(ParsecGamepadButton(rawValue: raw), false)
		}
		for raw in axes.keys {
			axisChanged(ParsecGamepadAxis(rawValue: raw), 0)
		}
	}
}

struct VirtualGamepadView: View {
	@StateObject var input = VirtualGamepadInput()

	var body: some View {
		VStack {
			Spacer()
			HStack(alignment: .bottom) {
				VStack(alignment: .leading, spacing: 10) {
					HStack(spacing: 8) {
						GamepadTrigger(label: "LT", axis: GAMEPAD_AXIS_TRIGGERL, input: input)
						GamepadPill(label: "LB", button: GAMEPAD_BUTTON_LSHOULDER, input: input)
					}
					HStack(alignment: .top, spacing: 8) {
						GamepadThumbstick { input.thumbLstickChangedHandler($0, $1) }
						GamepadDpad(input: input)
							.padding(.top, 60)
					}
				}
				Spacer()
				HStack(spacing: 16) {
					GamepadRoundButton(systemImage: "rectangle.on.rectangle", button: GAMEPAD_BUTTON_BACK, input: input)
					GamepadRoundButton(systemImage: "line.horizontal.3", button: GAMEPAD_BUTTON_START, input: input)
				}
				Spacer()
				VStack(alignment: .trailing, spacing: 10) {
					HStack(spacing: 8) {
						GamepadPill(label: "RB", button: GAMEPAD_BUTTON_RSHOULDER, input: input)
						GamepadTrigger(label: "RT", axis: GAMEPAD_AXIS_TRIGGERR, input: input)
					}
					HStack(alignment: .top, spacing: 8) {
						GamepadThumbstick { input.thumbRstickChangedHandler($0, $1) }
							.padding(.top, 60)
						GamepadFaceButtons(input: input)
					}
				}
			}
			.padding(.horizontal, 24)
			.padding(.bottom, 16)
		}
		.opacity(0.55)
		.onDisappear { input.releaseAll() }
	}
}

private let gamepadFill = Color.black.opacity(0.5)
private let gamepadStroke = Color.white.opacity(0.7)

// Press tracking shared by every plain button: GestureState resets even when the touch is cancelled,
// so onChange always delivers the release.
struct GamepadPressable<Label: View>: View {
	let onChange: (Bool) -> Void
	let label: (Bool) -> Label
	@GestureState private var isPressed = false

	var body: some View {
		label(isPressed)
			.contentShape(Rectangle())
			.gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, state, _ in state = true })
			.onChange(of: isPressed, perform: onChange)
	}
}

struct GamepadRoundButton: View {
	var label: String = ""
	var systemImage: String?
	var color: Color = .white
	var size: CGFloat = 32
	let button: ParsecGamepadButton
	let input: VirtualGamepadInput

	var body: some View {
		GamepadPressable(onChange: { input.buttonChangedHandler(button, $0) }) { pressed in
			Circle()
				.fill(pressed ? color.opacity(0.6) : gamepadFill)
				.overlay(Circle().stroke(color, lineWidth: 2))
				.overlay(Group {
					if let systemImage = systemImage {
						Image(systemName: systemImage).font(.system(size: size * 0.4, weight: .bold))
					} else {
						Text(label).font(.system(size: size * 0.45, weight: .bold))
					}
				}.foregroundColor(pressed ? .white : color))
				.frame(width: size, height: size)
		}
	}
}

struct GamepadPill: View {
	let label: String
	let button: ParsecGamepadButton
	let input: VirtualGamepadInput

	var body: some View {
		GamepadPressable(onChange: { input.buttonChangedHandler(button, $0) }) { pressed in
			GamepadPillShape(label: label, pressed: pressed)
		}
	}
}

// triggers are axes on an Xbox pad, touch can only give fully pulled or released
struct GamepadTrigger: View {
	let label: String
	let axis: ParsecGamepadAxis
	let input: VirtualGamepadInput

	var body: some View {
		GamepadPressable(onChange: { input.triggerChangedHandler(axis, $0 ? 1 : 0) }) { pressed in
			GamepadPillShape(label: label, pressed: pressed)
		}
	}
}

private struct GamepadPillShape: View {
	let label: String
	let pressed: Bool

	var body: some View {
		RoundedRectangle(cornerRadius: 10)
			.fill(pressed ? Color.white.opacity(0.6) : gamepadFill)
			.overlay(RoundedRectangle(cornerRadius: 10).stroke(gamepadStroke, lineWidth: 2))
			.overlay(Text(label).font(.system(size: 14, weight: .bold)).foregroundColor(.white))
			.frame(width: 60, height: 36)
	}
}

struct GamepadFaceButtons: View {
	let input: VirtualGamepadInput
	private let size: CGFloat = 44

	var body: some View {
		VStack(spacing: 0) {
			GamepadRoundButton(label: "Y", color: .yellow, size: size, button: GAMEPAD_BUTTON_Y, input: input)
			HStack(spacing: size) {
				GamepadRoundButton(label: "X", color: .blue, size: size, button: GAMEPAD_BUTTON_X, input: input)
				GamepadRoundButton(label: "B", color: .red, size: size, button: GAMEPAD_BUTTON_B, input: input)
			}
			GamepadRoundButton(label: "A", color: .green, size: size, button: GAMEPAD_BUTTON_A, input: input)
		}
	}
}

struct GamepadThumbstick: View {
	let onMove: (Float, Float) -> Void
	private let size: CGFloat = 110
	private let knobSize: CGFloat = 50
	@GestureState private var offset: CGSize = .zero

	var body: some View {
		let radius = (size - knobSize) / 2
		ZStack {
			Circle()
				.fill(gamepadFill)
				.overlay(Circle().stroke(gamepadStroke, lineWidth: 2))
			Circle()
				.fill(Color.white.opacity(offset == .zero ? 0.4 : 0.7))
				.frame(width: knobSize, height: knobSize)
				.offset(offset)
		}
		.frame(width: size, height: size)
		.contentShape(Circle())
		.gesture(DragGesture(minimumDistance: 0).updating($offset) { value, state, _ in
			// stick tracks from the touch-down point, so it never jumps on first contact
			var dx = value.translation.width
			var dy = value.translation.height
			let length = (dx * dx + dy * dy).squareRoot()
			if length > radius {
				dx *= radius / length
				dy *= radius / length
			}
			state = CGSize(width: dx, height: dy)
		})
		// screen y grows downward, same as the Parsec axis, so no flip like GamepadController needs
		.onChange(of: offset) { onMove(Float($0.width / radius), Float($0.height / radius)) }
	}
}

struct GamepadDpad: View {
	let input: VirtualGamepadInput
	private let size: CGFloat = 100
	@GestureState private var touch: CGPoint?

	private var directions: (up: Bool, down: Bool, left: Bool, right: Bool) {
		guard let touch = touch else { return (false, false, false, false) }
		let dx = touch.x - size / 2
		let dy = touch.y - size / 2
		// small dead zone in the middle, then 8-way so diagonals press two arrows
		guard (dx * dx + dy * dy).squareRoot() > size * 0.12 else { return (false, false, false, false) }
		let angle = atan2(-dy, dx) * 180 / .pi
		return (angle > 22.5 && angle < 157.5,
				angle < -22.5 && angle > -157.5,
				abs(angle) > 112.5,
				abs(angle) < 67.5)
	}

	var body: some View {
		let dirs = directions
		let arm = size / 3
		ZStack {
			Rectangle().frame(width: arm, height: size)
			Rectangle().frame(width: size, height: arm)
		}
		.foregroundColor(gamepadFill)
		.overlay(VStack(spacing: 0) {
			arrow("arrowtriangle.up.fill", dirs.up).frame(height: arm)
			HStack(spacing: 0) {
				arrow("arrowtriangle.left.fill", dirs.left).frame(width: arm)
				Spacer().frame(width: arm)
				arrow("arrowtriangle.right.fill", dirs.right).frame(width: arm)
			}.frame(height: arm)
			arrow("arrowtriangle.down.fill", dirs.down).frame(height: arm)
		})
		.frame(width: size, height: size)
		.contentShape(Rectangle())
		.gesture(DragGesture(minimumDistance: 0).updating($touch) { value, state, _ in state = value.location })
		.onChange(of: touch) { _ in
			let dirs = directions
			input.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_UP, dirs.up)
			input.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_DOWN, dirs.down)
			input.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_LEFT, dirs.left)
			input.buttonChangedHandler(GAMEPAD_BUTTON_DPAD_RIGHT, dirs.right)
		}
	}

	private func arrow(_ name: String, _ active: Bool) -> some View {
		Image(systemName: name)
			.font(.system(size: 14))
			.foregroundColor(active ? .white : gamepadStroke)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.background(active ? Color.white.opacity(0.4) : Color.clear)
	}
}
