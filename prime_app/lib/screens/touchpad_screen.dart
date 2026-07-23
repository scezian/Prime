import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../services/api_client.dart';
import '../theme/prime_theme.dart';

/// Full-screen touchpad + keyboard surface. Streams relative move/scroll/
/// click/key events to the daemon over /ws/input.
///
/// Uses Listener (not GestureDetector) so we can track multiple raw
/// pointers ourselves — needed to tell a one-finger drag (move) apart from
/// a two-finger drag (scroll) apart from a two-finger tap (right-click),
/// none of which GestureDetector's single-gesture-arena model handles well
/// together. Same lesson as the InteractiveViewer/RFB gesture conflict.
class TouchpadScreen extends StatefulWidget {
  final ApiClient apiClient;
  const TouchpadScreen({super.key, required this.apiClient});

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen> {
  WebSocketChannel? _channel;
  String _status = 'connecting';

  // Active pointers, keyed by Flutter's pointer id.
  final Map<int, Offset> _pointers = {};
  // Cached previous position per pointer, for delta computation.
  final Map<int, Offset> _lastPositions = {};

  DateTime _lastMoveSent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastScrollSent = DateTime.fromMillisecondsSinceEpoch(0);
  static const _throttle = Duration(milliseconds: 12); // ~80Hz cap

  // Gain multipliers — phone screen is much smaller than a laptop trackpad,
  // so raw finger-travel-in-pixels needs scaling up to feel comparable.
  // 2.5 roughly matches "half the laptop screen per phone-width swipe".
  // Bump higher if it still feels slow, lower if the cursor overshoots.
  static const _moveSensitivity = 2.5;
  static const _scrollSensitivity = 1.8;

  double _accumScrollDy = 0;

  Timer? _tapTimeout;
  bool _dragging = false;

  final FocusNode _kbdFocusNode = FocusNode();
  bool _keyboardOpen = false;

  @override
  void initState() {
    super.initState();
    // Touchpad surface works far better landscape — more width to drag
    // across, and matches how you'd actually hold the phone to use this.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Hide status bar + nav bar so the whole screen is usable drag surface,
    // not just the area between them. immersiveSticky lets a swipe from the
    // edge reveal the bars temporarily without permanently exiting immersive
    // mode (they auto-hide again), which regular `immersive` doesn't do.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _connect();
  }

  void _connect() {
    try {
      // IOWebSocketChannel (not the platform-agnostic WebSocketChannel) is
      // used directly because this app is Android-only and we need the
      // headers param to send X-Auth-Token during the handshake — the
      // generic WebSocketChannel.connect() has no way to attach headers.
      final channel = IOWebSocketChannel.connect(
        widget.apiClient.inputWsUri,
        headers: widget.apiClient.inputWsHeaders,
      );
      _channel = channel;
      channel.stream.listen(
        (_) {}, // daemon doesn't send anything back
        onDone: () {
          if (mounted) setState(() => _status = 'disconnected');
        },
        onError: (e) {
          if (mounted) setState(() => _status = 'error: $e');
        },
      );
      setState(() => _status = 'connected');
    } catch (e) {
      setState(() => _status = 'error: $e');
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {
      // socket likely dropped — ignore, UI shows disconnected state via onDone/onError
    }
  }

  @override
  void dispose() {
    // Restore portrait + system bars when leaving. main.dart never sets an
    // explicit SystemUiMode, so the rest of the app relies on the platform
    // default (status bar + nav bar fully shown, own space reserved) rather
    // than edgeToEdge — home_screen.dart has no SafeArea and its bottom
    // tile gets clipped under the nav bar if we assume edgeToEdge here.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _tapTimeout?.cancel();
    _channel?.sink.close(ws_status.normalClosure);
    _kbdFocusNode.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _lastPositions[event.pointer] = event.localPosition;

    if (_pointers.length == 1) {
      _dragging = false;
      _tapTimeout?.cancel();
    } else if (_pointers.length == 2) {
      // second finger landed — cancel any pending single-finger tap
      _tapTimeout?.cancel();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final last = _lastPositions[event.pointer];
    if (last == null) return;
    final current = event.localPosition;
    final delta = current - last;
    _lastPositions[event.pointer] = current;

    if (_pointers.length == 1) {
      if (delta.distance > 1.5) _dragging = true;
      // Phone touch surface is physically much smaller than a laptop
      // trackpad, so raw 1:1 deltas feel sluggish — scale up so a
      // comfortable thumb swipe covers a proportionate amount of the
      // laptop screen. Tune _moveSensitivity to taste.
      _sendMove(delta.dx * _moveSensitivity, delta.dy * _moveSensitivity);
    } else if (_pointers.length == 2) {
      // Two-finger drag → scroll. Average the two pointers' dy so a slightly
      // uneven two-finger swipe doesn't double-count.
      _accumScrollDy += (delta.dy / 2) * _scrollSensitivity;
      _maybeSendScroll();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final wasTwoFinger = _pointers.length == 2;
    final wasOneFinger = _pointers.length == 1;

    _pointers.remove(event.pointer);
    _lastPositions.remove(event.pointer);

    if (wasOneFinger && !_dragging) {
      // Single tap, no drag → left click.
      _send({'type': 'click', 'button': 'left'});
    } else if (wasTwoFinger && _accumScrollDy.abs() < 3) {
      // Two fingers came down and up without meaningful scroll → right click.
      _send({'type': 'click', 'button': 'right'});
    }

    if (_pointers.isEmpty) {
      _dragging = false;
      _accumScrollDy = 0;
    }
  }

  void _sendMove(double dx, double dy) {
    final now = DateTime.now();
    if (now.difference(_lastMoveSent) < _throttle) return;
    _lastMoveSent = now;
    _send({'type': 'move', 'dx': dx.round(), 'dy': dy.round()});
  }

  void _maybeSendScroll() {
    final now = DateTime.now();
    if (now.difference(_lastScrollSent) < _throttle) return;
    if (_accumScrollDy.abs() < 1) return;
    _lastScrollSent = now;
    // Natural scroll direction: drag up (negative dy) scrolls content up,
    // matching typical laptop touchpad "natural scrolling" convention.
    _send({'type': 'scroll', 'dy': _accumScrollDy.round()});
    _accumScrollDy = 0;
  }

  void _sendKeyChar(String char) {
    _send({'type': 'text', 'text': char});
  }

  void _sendSpecialKey(String code) {
    _send({'type': 'key', 'code': code, 'down': true});
    _send({'type': 'key', 'code': code, 'down': false});
  }

  void _toggleKeyboard() {
    setState(() => _keyboardOpen = !_keyboardOpen);
    if (_keyboardOpen) {
      _kbdFocusNode.requestFocus();
    } else {
      _kbdFocusNode.unfocus();
    }
  }

  Widget _statusDot() {
    final color = _status == 'connected' ? PrimeColors.success : PrimeColors.destructive;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Touchpad'),
            const SizedBox(width: 10),
            _statusDot(),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_keyboardOpen ? Icons.keyboard_hide : Icons.keyboard, color: PrimeColors.mutedForeground),
            onPressed: _toggleKeyboard,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: (_) {
                _pointers.clear();
                _lastPositions.clear();
                _dragging = false;
                _accumScrollDy = 0;
              },
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: PrimeColors.card,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: PrimeColors.border),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, size: 28, color: PrimeColors.mutedForeground.withValues(alpha: 0.3)),
                      const SizedBox(height: 8),
                      Text(
                        'one finger: move & tap-click\ntwo fingers: scroll & tap-right-click',
                        textAlign: TextAlign.center,
                        style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_keyboardOpen) _KeyboardBar(onChar: _sendKeyChar, onSpecial: _sendSpecialKey, focusNode: _kbdFocusNode),
        ],
      ),
    );
  }
}

/// Invisible TextField captures the phone's native keyboard (autocomplete
/// etc included) and streams each character over the socket; a modifier
/// row above it covers keys a soft keyboard normally swallows.
class _KeyboardBar extends StatefulWidget {
  final ValueChanged<String> onChar;
  final ValueChanged<String> onSpecial;
  final FocusNode focusNode;

  const _KeyboardBar({required this.onChar, required this.onSpecial, required this.focusNode});

  @override
  State<_KeyboardBar> createState() => _KeyboardBarState();
}

class _KeyboardBarState extends State<_KeyboardBar> {
  final _controller = TextEditingController();

  void _onChanged(String value) {
    if (value.isEmpty) return;
    // Only the newly-typed tail — handles both single chars and
    // autocomplete/predictive-text insertions in one go.
    widget.onChar(value);
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _modKey(String label, String code) {
    return Expanded(
      child: InkWell(
        onTap: () => widget.onSpecial(code),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: PrimeColors.secondary,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(label, style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.foreground)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: PrimeColors.card,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _modKey('Esc', 'KEY_ESC'),
                _modKey('Backspace', 'KEY_BACKSPACE'),
                _modKey('Ctrl', 'KEY_LEFTCTRL'),
                _modKey('Alt', 'KEY_LEFTALT'),
                _modKey('Super', 'KEY_LEFTMETA'),
                _modKey('Del', 'KEY_DELETE'),
                _modKey('↑', 'KEY_UP'),
                _modKey('↓', 'KEY_DOWN'),
                _modKey('←', 'KEY_LEFT'),
                _modKey('→', 'KEY_RIGHT'),
              ],
            ),
            TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: (_) => widget.onSpecial('KEY_ENTER'),
              style: PrimeTheme.mono(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'type here…',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
