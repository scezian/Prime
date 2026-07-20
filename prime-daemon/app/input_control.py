"""
Virtual mouse + keyboard input via /dev/uinput (evdev), driven by the
Prime Android app's touchpad screen over /ws/input. Bypasses Wayland's
protocol-level block on synthetic input entirely.
"""
from evdev import UInput, ecodes as e


class InputError(Exception):
    pass


# evdev.ecodes.keys maps code -> name(s) for real keyboard keys only —
# unlike sweeping vars(e), this excludes pseudo-constants like KEY_MAX/
# KEY_CNT that aren't valid codes and make UI_SET_KEYBIT reject the whole
# capability set with EINVAL.
_KEY_CODES = list(e.keys.keys())

_CAPABILITIES = {
    e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE, *_KEY_CODES],
    e.EV_REL: [e.REL_X, e.REL_Y, e.REL_WHEEL, e.REL_HWHEEL],
}

_ui: UInput | None = None


def _device() -> UInput:
    global _ui
    if _ui is None:
        _ui = UInput(_CAPABILITIES, name="prime-virtual-input")
    return _ui


_BUTTON_MAP = {"left": e.BTN_LEFT, "right": e.BTN_RIGHT, "middle": e.BTN_MIDDLE}


def move(dx: int, dy: int) -> None:
    ui = _device()
    ui.write(e.EV_REL, e.REL_X, dx)
    ui.write(e.EV_REL, e.REL_Y, dy)
    ui.syn()


def scroll(dy: int) -> None:
    ui = _device()
    ui.write(e.EV_REL, e.REL_WHEEL, dy)
    ui.syn()


def _btn_code(button: str) -> int:
    code = _BUTTON_MAP.get(button)
    if code is None:
        raise InputError(f"unknown button: {button}")
    return code


def click(button: str = "left") -> None:
    code = _btn_code(button)
    ui = _device()
    ui.write(e.EV_KEY, code, 1)
    ui.syn()
    ui.write(e.EV_KEY, code, 0)
    ui.syn()


def button_down(button: str = "left") -> None:
    ui = _device()
    ui.write(e.EV_KEY, _btn_code(button), 1)
    ui.syn()


def button_up(button: str = "left") -> None:
    ui = _device()
    ui.write(e.EV_KEY, _btn_code(button), 0)
    ui.syn()


def key_event(code: str, down: bool) -> None:
    """code is an evdev KEY_* name, e.g. 'KEY_ENTER', 'KEY_A', 'KEY_LEFTCTRL'."""
    keycode = getattr(e, code, None)
    if not isinstance(keycode, int):
        raise InputError(f"unknown key code: {code}")
    ui = _device()
    ui.write(e.EV_KEY, keycode, 1 if down else 0)
    ui.syn()


_SHIFT_SYMBOLS = {
    '!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7',
    '*': '8', '(': '9', ')': '0', '_': '-', '+': '=', '{': '[', '}': ']',
    '|': '\\', ':': ';', '"': "'", '<': ',', '>': '.', '?': '/', '~': '`',
}
_SYMBOL_CODES = {
    '-': e.KEY_MINUS, '=': e.KEY_EQUAL, '[': e.KEY_LEFTBRACE, ']': e.KEY_RIGHTBRACE,
    '\\': e.KEY_BACKSLASH, ';': e.KEY_SEMICOLON, "'": e.KEY_APOSTROPHE,
    ',': e.KEY_COMMA, '.': e.KEY_DOT, '/': e.KEY_SLASH, '`': e.KEY_GRAVE,
}


def type_text(text: str) -> None:
    """Types literal text char-by-char, using shift for uppercase/symbols."""
    ui = _device()
    for ch in text:
        shift = False
        base = ch
        if ch.isalpha() and ch.isupper():
            shift, base = True, ch.lower()
        elif ch in _SHIFT_SYMBOLS:
            shift, base = True, _SHIFT_SYMBOLS[ch]

        if base == ' ':
            keycode = e.KEY_SPACE
        elif base == '\n':
            keycode = e.KEY_ENTER
        elif base.isalnum():
            keycode = getattr(e, f"KEY_{base.upper()}", None)
        else:
            keycode = _SYMBOL_CODES.get(base)

        if not isinstance(keycode, int):
            continue  # skip unsupported chars

        if shift:
            ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 1)
            ui.syn()
        ui.write(e.EV_KEY, keycode, 1)
        ui.syn()
        ui.write(e.EV_KEY, keycode, 0)
        ui.syn()
        if shift:
            ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 0)
            ui.syn()
