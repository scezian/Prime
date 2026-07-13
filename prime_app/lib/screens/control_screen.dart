import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/prime_theme.dart';

class ControlScreen extends StatefulWidget {
  final ApiClient apiClient;

  const ControlScreen({super.key, required this.apiClient});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  Map<String, dynamic>? _nowPlaying;
  int _volume = 0;
  bool _muted = false;
  double? _draggingVolume;
  int _brightness = 0;
  double? _draggingBrightness;
  int _kbdBacklight = 0;
  double? _draggingKbdBacklight;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadAll(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!widget.apiClient.isConfigured) {
      if (!silent) setState(() => _error = 'Not configured. Go to Settings first.');
      return;
    }
    try {
      final playing = await widget.apiClient.getNowPlaying();
      final vol = await widget.apiClient.getVolume();
      final brightness = await widget.apiClient.getBrightness();
      final kbdBacklight = await widget.apiClient.getKbdBacklight();
      if (!mounted) return;
      setState(() {
        _nowPlaying = playing;
        _volume = vol['volume'] as int;
        _muted = vol['muted'] as bool;
        if (_draggingBrightness == null) _brightness = brightness['percent'] as int;
        if (_draggingKbdBacklight == null) _kbdBacklight = kbdBacklight['percent'] as int;
        _error = null;
      });
    } catch (e) {
      if (!silent && mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _playPause() async {
    try {
      await widget.apiClient.mediaPlayPause();
      await Future.delayed(const Duration(milliseconds: 300));
      await _loadAll(silent: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _next() async {
    try {
      await widget.apiClient.mediaNext();
      await Future.delayed(const Duration(milliseconds: 300));
      await _loadAll(silent: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _previous() async {
    try {
      await widget.apiClient.mediaPrevious();
      await Future.delayed(const Duration(milliseconds: 300));
      await _loadAll(silent: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _onVolumeChangeEnd(double value) async {
    final level = value.round();
    setState(() {
      _volume = level;
      _draggingVolume = null;
    });
    try {
      await widget.apiClient.setVolume(level);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _onBrightnessChangeEnd(double value) async {
    final level = value.round();
    setState(() {
      _brightness = level;
      _draggingBrightness = null;
    });
    try {
      await widget.apiClient.setBrightness(level);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _onKbdBacklightChangeEnd(double value) async {
    setState(() => _draggingKbdBacklight = null);
    try {
      final res = await widget.apiClient.setKbdBacklight(value.round());
      setState(() => _kbdBacklight = res['percent'] as int);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _toggleMute() async {
    try {
      final res = await widget.apiClient.toggleMute();
      setState(() {
        _volume = res['volume'] as int;
        _muted = res['muted'] as bool;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final displayVolume = _draggingVolume ?? _volume.toDouble();
    final displayBrightness = _draggingBrightness ?? _brightness.toDouble();
    final displayKbdBacklight = _draggingKbdBacklight ?? _kbdBacklight.toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Control')),
      body: RefreshIndicator(
        color: PrimeColors.primary,
        backgroundColor: PrimeColors.card,
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: PrimeColors.destructive.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: PrimeColors.destructive.withValues(alpha: 0.3)),
                ),
                child: Text(_error!, style: PrimeTheme.mono(color: PrimeColors.destructive, fontSize: 12)),
              ),
            _NowPlayingCard(
              apiClient: widget.apiClient,
              nowPlaying: _nowPlaying,
              onPlayPause: _playPause,
              onNext: _next,
              onPrevious: _previous,
              formatTime: _formatTime,
            ),
            const SizedBox(height: 16),
            Text('VOLUME', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
            const SizedBox(height: 8),
            _SliderCard(
              value: displayVolume,
              leadingIcon: _muted ? Icons.volume_off : (displayVolume > 50 ? Icons.volume_up : Icons.volume_down),
              iconColor: _muted ? PrimeColors.destructive : PrimeColors.primary,
              activeColor: _muted ? PrimeColors.mutedForeground : PrimeColors.primary,
              onIconTap: _toggleMute,
              onChanged: (v) => setState(() => _draggingVolume = v),
              onChangeEnd: _onVolumeChangeEnd,
            ),
            const SizedBox(height: 16),
            Text('BRIGHTNESS', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
            const SizedBox(height: 8),
            _SliderCard(
              value: displayBrightness,
              leadingIcon: displayBrightness > 50 ? Icons.brightness_high : Icons.brightness_low,
              iconColor: PrimeColors.warning,
              activeColor: PrimeColors.warning,
              onIconTap: null,
              onChanged: (v) => setState(() => _draggingBrightness = v),
              onChangeEnd: _onBrightnessChangeEnd,
            ),
            const SizedBox(height: 16),
            Text('KEYBOARD BACKLIGHT', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
            const SizedBox(height: 8),
            _SliderCard(
              value: displayKbdBacklight,
              leadingIcon: Icons.keyboard,
              iconColor: PrimeColors.primary,
              activeColor: PrimeColors.primary,
              onIconTap: null,
              onChanged: (v) => setState(() => _draggingKbdBacklight = v),
              onChangeEnd: _onKbdBacklightChangeEnd,
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderCard extends StatelessWidget {
  final double value;
  final IconData leadingIcon;
  final Color iconColor;
  final Color activeColor;
  final VoidCallback? onIconTap;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderCard({
    required this.value,
    required this.leadingIcon,
    required this.iconColor,
    required this.activeColor,
    required this.onIconTap,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PrimeColors.border),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onIconTap,
            child: Icon(leadingIcon, size: 20, color: iconColor),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: activeColor,
                inactiveTrackColor: PrimeColors.secondary,
                thumbColor: activeColor,
                overlayColor: activeColor.withValues(alpha: 0.15),
                trackHeight: 3,
              ),
              child: Slider(
                value: value.clamp(0, 100),
                min: 0,
                max: 100,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${value.round()}',
              textAlign: TextAlign.right,
              style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingCard extends StatefulWidget {
  final ApiClient apiClient;
  final Map<String, dynamic>? nowPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final String Function(int) formatTime;

  const _NowPlayingCard({
    required this.apiClient,
    required this.nowPlaying,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.formatTime,
  });

  @override
  State<_NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<_NowPlayingCard> with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(vsync: this, duration: const Duration(seconds: 12));
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _syncSpin(bool playing) {
    if (playing && !_spinController.isAnimating) {
      _spinController.repeat();
    } else if (!playing && _spinController.isAnimating) {
      _spinController.stop();
    }
  }

  Widget _buildArt(String? artUrl) {
    const size = 64.0;
    final proxied = widget.apiClient.proxiedArtRequest(artUrl);

    Widget fallback = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: PrimeColors.secondary, shape: BoxShape.circle),
      child: const Icon(Icons.music_note, color: PrimeColors.mutedForeground, size: 24),
    );

    ImageProvider? provider;
    if (proxied != null) {
      provider = NetworkImage(proxied.url, headers: proxied.headers);
    } else if (artUrl != null && artUrl.startsWith('http')) {
      provider = NetworkImage(artUrl);
    }

    if (provider == null) return fallback;

    return ClipOval(
      child: Image(
        image: provider,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nowPlaying = widget.nowPlaying;
    final active = nowPlaying?['active'] == true;
    final playing = nowPlaying?['status'] == 'Playing';
    _syncSpin(playing);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PrimeColors.border),
      ),
      child: !active
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('nothing playing', style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground)),
              ),
            )
          : Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    RotationTransition(
                      turns: _spinController,
                      child: _buildArt(nowPlaying!['art_url'] as String?),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (nowPlaying['title'] as String?)?.isNotEmpty == true ? nowPlaying['title'] : 'unknown title',
                            style: PrimeTheme.mono(fontSize: 15, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [nowPlaying['artist'], nowPlaying['album']]
                                .where((s) => s != null && (s as String).isNotEmpty)
                                .join(' — '),
                            style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if ((nowPlaying['duration_seconds'] as int? ?? 0) > 0) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (nowPlaying['position_seconds'] as int) / (nowPlaying['duration_seconds'] as int),
                      minHeight: 3,
                      backgroundColor: PrimeColors.secondary,
                      valueColor: const AlwaysStoppedAnimation(PrimeColors.primary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.formatTime(nowPlaying['position_seconds'] as int),
                          style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground)),
                      Text(widget.formatTime(nowPlaying['duration_seconds'] as int),
                          style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: widget.onPrevious,
                      icon: const Icon(Icons.skip_previous, color: PrimeColors.foreground),
                      iconSize: 26,
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: widget.onPlayPause,
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: PrimeColors.primary, shape: BoxShape.circle),
                        child: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          color: PrimeColors.primaryForeground,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: widget.onNext,
                      icon: const Icon(Icons.skip_next, color: PrimeColors.foreground),
                      iconSize: 26,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
