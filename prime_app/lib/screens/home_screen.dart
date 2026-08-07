import 'dart:async';
import 'package:flutter/material.dart';
import '../services/biometric_auth.dart';
import '../widgets/liquid_confirm_button.dart';
import '../widgets/marquee_text.dart';
import '../widgets/shimmer_sweep.dart';
import '../services/secure_credentials.dart';
import '../services/api_client.dart';
import '../theme/prime_theme.dart';
import '../widgets/pulse_dot.dart';
import '../widgets/ambient_background.dart';
import 'control_screen.dart';
import 'files_screen.dart';
import 'packages_screen.dart';
import 'settings_screen.dart';
import 'commands_screen.dart';

/// Flip this and hot-reload to compare glass treatments on the power/lock
/// buttons: GlassStyle.frosted (blurred, translucent, subtle red tint) vs
/// GlassStyle.gradient (soft red-to-dark diagonal gradient, no blur).
const _kPowerButtonGlassStyle = GlassStyle.frosted;

class HomeScreen extends StatefulWidget {
  final ApiClient apiClient;

  const HomeScreen({super.key, required this.apiClient});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _status;
  bool _loading = false;
  String? _error;
  bool? _locked;
  Timer? _lockPollTimer;
  Map<String, dynamic>? _nowPlaying;
  Timer? _mediaPollTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollLockStatus();
    _pollNowPlaying();
    _lockPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollLockStatus());
    _mediaPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollNowPlaying());
  }

  @override
  void dispose() {
    _lockPollTimer?.cancel();
    _mediaPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!widget.apiClient.isConfigured) {
      setState(() => _error = 'Not configured. Go to Settings first.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final status = await widget.apiClient.getStatus();
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pollLockStatus() async {
    if (!widget.apiClient.isConfigured) return;
    try {
      final res = await widget.apiClient.getLockStatus();
      if (!mounted) return;
      setState(() => _locked = res['locked'] as bool);
    } catch (_) {
      // best-effort, ignore
    }
  }
  Future<void> _pollNowPlaying() async {
    if (!widget.apiClient.isConfigured) return;
    try {
      final playing = await widget.apiClient.getNowPlaying();
      if (!mounted) return;
      setState(() => _nowPlaying = playing);
    } catch (_) {
      // best-effort, ignore
    }
  }
  Future<void> _mediaPlayPause() async {
    try {
      await widget.apiClient.mediaPlayPause();
      await Future.delayed(const Duration(milliseconds: 300));
      await _pollNowPlaying();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
  Future<void> _mediaNext() async {
    try {
      await widget.apiClient.mediaNext();
      await Future.delayed(const Duration(milliseconds: 300));
      await _pollNowPlaying();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
  Future<void> _mediaPrevious() async {
    try {
      await widget.apiClient.mediaPrevious();
      await Future.delayed(const Duration(milliseconds: 300));
      await _pollNowPlaying();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) {
      // Refresh status in case something changed (e.g. settings) while away.
      _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final actions = <_ActionItem>[
      _ActionItem(
        icon: Icons.tune_outlined,
        label: 'Control',
        subtitle: 'media · system',
        accent: PrimeColors.cpuAccent,
        gradient: PrimeGradients.tileA,
        onTap: () => _open(ControlScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.folder_outlined,
        label: 'Files',
        subtitle: widget.apiClient.host ?? '',
        stat: _status != null
            ? '${(_status!['disk']['free_gb'] as num).toStringAsFixed(0)} GB free'
            : null,
        statColor: PrimeColors.filesAccent,
        accent: PrimeColors.filesAccent,
        gradient: PrimeGradients.tileB,
        onTap: () => _open(FilesScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.inventory_2_outlined,
        label: 'Packages',
        subtitle: 'pacman / paru',
        accent: PrimeColors.packagesAccent,
        gradient: PrimeGradients.tileA,
        onTap: () => _open(PackagesScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.terminal_outlined,
        label: 'Commands',
        subtitle: '17 actions',
        accent: PrimeColors.warning,
        gradient: PrimeGradients.tileB,
        onTap: () => _open(CommandsScreen(apiClient: widget.apiClient)),
      ),
      _ActionItem(
        icon: Icons.settings_outlined,
        label: 'Settings',
        subtitle: 'tailscale · auth',
        stat: widget.apiClient.host,
        statColor: Colors.white,
        accent: PrimeColors.destructive,
        gradient: PrimeGradients.tileA,
        onTap: () => _open(SettingsScreen(
          apiClient: widget.apiClient,
          onSaved: () => Navigator.pop(context),
        )),
      ),
    ];

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
          titleSpacing: 20,
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: PrimeGradients.header,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: PrimeShadows.tile,
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Prime'),
            ],
          ),
        ),
        body: RefreshIndicator(
        color: PrimeColors.primary,
        backgroundColor: PrimeColors.card,
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (_error != null) _ErrorBanner(message: _error!),
            if (_loading && _status == null)
              Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: PrimeColors.primary)),
              ),
            if (_status != null) ...[
              // PRIME_OVERVIEW_CARD_REMOVED
              SizedBox(
                height: 118, // 54 (button row) + 10 (gap) + 54 (button row)
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _MiniNowPlayingCard(
                      apiClient: widget.apiClient,
                      nowPlaying: _nowPlaying,
                      onPlayPause: _mediaPlayPause,
                      onNext: _mediaNext,
                      onPrevious: _mediaPrevious,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 54,
                            height: 54,
                            child: _LockToggleButton(
                              apiClient: widget.apiClient,
                              locked: _locked,
                              onChanged: (v) => setState(() => _locked = v),
                              showLabel: false,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 54,
                            height: 54,
                            child: _PowerActionButton(
                              apiClient: widget.apiClient,
                              commandId: 'logout',
                              label: 'Log Out',
                              icon: Icons.logout,
                              needsConfirm: true,
                              showLabel: false,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          SizedBox(
                            width: 54,
                            height: 54,
                            child: _PowerActionButton(
                              apiClient: widget.apiClient,
                              commandId: 'reboot',
                              label: 'Restart',
                              icon: Icons.restart_alt,
                              needsConfirm: true,
                              expectDaemonDeath: true,
                              showLabel: false,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 54,
                            height: 54,
                            child: _PowerActionButton(
                              apiClient: widget.apiClient,
                              commandId: 'shutdown',
                              label: 'Shutdown',
                              icon: Icons.power_settings_new,
                              needsConfirm: true,
                              expectDaemonDeath: true,
                              showLabel: false,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              ),
            ],
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.02,
              children: actions.take(4).map((a) => _ActionTile(item: a)).toList(),
            ),
            const SizedBox(height: 12),
            _ActionTile(item: actions.last, fullWidth: true),
          ],
        ),
      ),
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final String subtitle;
  final String? stat;
  final Color? statColor;
  final Color accent;
  final Gradient gradient;
  final VoidCallback onTap;
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.stat,
    this.statColor,
    required this.accent,
    required this.gradient,
    required this.onTap,
  });
}

class _ActionTile extends StatefulWidget {
  final _ActionItem item;
  final bool fullWidth;
  const _ActionTile({required this.item, this.fullWidth = false});

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: item.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Container(
          width: widget.fullWidth ? double.infinity : null,
          decoration: BoxDecoration(
            gradient: item.gradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: PrimeShadows.tile,
          ),
          clipBehavior: Clip.antiAlias,
          child: ShimmerSweep(
            period: const Duration(seconds: 4),
            child: Stack(
              children: [
                // Corner glow blobs, matching the bolt.new FeatureTiles decoration.
                Positioned(
                  right: -28,
                  top: -28,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.10)),
                  ),
                ),
                Positioned(
                  left: -24,
                  bottom: -36,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(item.icon, size: 22, color: Colors.white),
                          ),
                          if (item.stat != null)
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  item.stat!,
                                  overflow: TextOverflow.ellipsis,
                                  style: PrimeTheme.text(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                        style: PrimeTheme.text(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: PrimeTheme.text(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.72)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PrimeColors.destructive.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PrimeColors.destructive.withValues(alpha: 0.3)),
      ),
      child: Text(message, style: PrimeTheme.mono(color: PrimeColors.destructive, fontSize: 12)),
    );
  }
}

/// Merged system overview: online pill, hostname/uptime, cpu/mem/disk/net
/// stat row, and the disk usage bar — replaces the old separate host+disk cards.
class _OverviewCard extends StatelessWidget {
  final Map<String, dynamic> status;
  final String host;
  final bool loading;
  final VoidCallback onRefresh;

  const _OverviewCard({
    required this.status,
    required this.host,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final disk = status['disk'] as Map<String, dynamic>;
    final diskUsed = (disk['used_gb'] as num).toDouble();
    final diskTotal = (disk['total_gb'] as num).toDouble();
    final diskFree = (disk['free_gb'] as num).toDouble();
    final diskPct = diskTotal > 0 ? (diskUsed / diskTotal * 100).round() : 0;
    final diskBarColor = diskPct > 80 ? PrimeColors.warning : PrimeColors.primary;

    final cpuPct = (status['cpu_percent'] as num?)?.round() ?? 0;
    final mem = status['memory'] as Map<String, dynamic>?;
    final memUsedGb = mem != null ? (mem['used_gb'] as num).toStringAsFixed(1) : '--';
    final net = status['network'] as Map<String, dynamic>?;
    final downKbps = net != null ? (net['download_kbps'] as num).toDouble() : 0.0;
    final netLabel = downKbps >= 1024
        ? '${(downKbps / 1024).toStringAsFixed(1)}m'
        : '${downKbps.toStringAsFixed(0)}k';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PrimeColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PrimeColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PulseDot(),
              const SizedBox(width: 8),
              Text(
                'ONLINE',
                style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.primary, letterSpacing: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  host,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onRefresh,
                child: AnimatedRotation(
                  turns: loading ? 1 : 0,
                  duration: const Duration(milliseconds: 600),
                  child: Icon(Icons.refresh, size: 16, color: PrimeColors.mutedForeground),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            status['hostname'] ?? '',
            style: PrimeTheme.mono(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            'uptime ${status['daemon_uptime'] ?? ''}',
            style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatTile(icon: Icons.memory, label: 'cpu', value: '$cpuPct%', color: PrimeColors.cpuAccent),
              _StatTile(icon: Icons.developer_board, label: 'mem', value: '${memUsedGb}g', color: PrimeColors.memAccent),
              _StatTile(icon: Icons.sd_card_outlined, label: 'disk', value: '$diskPct%', color: PrimeColors.warning),
              _StatTile(icon: Icons.swap_vert, label: 'net', value: netLabel, color: PrimeColors.netAccent),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('DISK', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground, letterSpacing: 2)),
              const Spacer(),
              Text(
                '${diskUsed.toStringAsFixed(1)} / ${diskTotal.toStringAsFixed(1)} GB',
                style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: diskPct / 100),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: PrimeColors.secondary,
                valueColor: AlwaysStoppedAnimation(diskBarColor),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$diskPct% used', style: PrimeTheme.mono(fontSize: 9, color: diskBarColor)),
              Text('${diskFree.toStringAsFixed(1)} GB free', style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(height: 5),
          Text(label, style: PrimeTheme.mono(fontSize: 9, color: PrimeColors.mutedForeground)),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              value,
              key: ValueKey(value),
              style: PrimeTheme.mono(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini now-playing card: track art, marquee title/artist, progress bar,
/// and transport controls. Stateful so it can drive its own slow gradient
/// sweep + shimmer while something is actively playing.
class _MiniNowPlayingCard extends StatefulWidget {
  final ApiClient apiClient;
  final Map<String, dynamic>? nowPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const _MiniNowPlayingCard({
    required this.apiClient,
    required this.nowPlaying,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<_MiniNowPlayingCard> createState() => _MiniNowPlayingCardState();
}

class _MiniNowPlayingCardState extends State<_MiniNowPlayingCard> with SingleTickerProviderStateMixin {
  late final AnimationController _gradientCtrl;

  @override
  void initState() {
    super.initState();
    _gradientCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _gradientCtrl.dispose();
    super.dispose();
  }

  Widget _buildArt(String? artUrl) {
    const size = 40.0;
    final proxied = widget.apiClient.proxiedArtRequest(artUrl);

    Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.music_note, color: Colors.white, size: 18),
    );

    ImageProvider? provider;
    if (proxied != null) {
      provider = NetworkImage(proxied.url, headers: proxied.headers);
    } else if (artUrl != null && artUrl.startsWith('http')) {
      provider = NetworkImage(artUrl);
    }
    if (provider == null) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image(
        image: provider,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }

  Widget _miniControl(IconData icon, VoidCallback onTap, {bool filled = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: EdgeInsets.all(filled ? 5 : 4),
        child: filled
            ? Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Icon(icon, size: 14, color: PrimeColors.prime700),
              )
            : Icon(icon, size: 17, color: Colors.white.withValues(alpha: 0.85)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nowPlaying = widget.nowPlaying;
    final active = nowPlaying?['active'] == true;
    final playing = nowPlaying?['status'] == 'Playing';

    return AnimatedBuilder(
      animation: _gradientCtrl,
      builder: (context, _) {
        final t = _gradientCtrl.value;
        final begin = Alignment.lerp(Alignment.topLeft, Alignment.topRight, t)!;
        final end = Alignment.lerp(Alignment.bottomRight, Alignment.bottomLeft, t)!;

        return Container(
          padding: EdgeInsets.symmetric(horizontal: active ? 12 : 10, vertical: active ? 10 : 8),
          decoration: BoxDecoration(
            gradient: active
                ? LinearGradient(begin: begin, end: end, colors: [PrimeColors.prime600, PrimeColors.prime800])
                : null,
            color: active ? null : PrimeColors.card,
            borderRadius: BorderRadius.circular(22),
            border: active ? null : Border.all(color: PrimeColors.border),
            boxShadow: active ? PrimeShadows.tile : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: ShimmerSweep(
            active: active,
            period: const Duration(seconds: 4),
            child: !active
                ? Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.music_off, size: 13, color: PrimeColors.mutedForeground),
                        const SizedBox(width: 6),
                        Text('nothing playing', style: PrimeTheme.mono(fontSize: 10, color: PrimeColors.mutedForeground)),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      Positioned(
                        right: -22,
                        top: -22,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.10)),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildArt(nowPlaying!['art_url'] as String?),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    MarqueeText(
                                      text: (nowPlaying['title'] as String?)?.isNotEmpty == true
                                          ? nowPlaying['title'] as String
                                          : 'unknown title',
                                      style: PrimeTheme.text(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                                    ),
                                    Text(
                                      [nowPlaying['artist'], nowPlaying['album']]
                                          .where((s) => s != null && (s as String).isNotEmpty)
                                          .join(' — '),
                                      style: PrimeTheme.mono(fontSize: 9, color: Colors.white.withValues(alpha: 0.75)),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if ((nowPlaying['duration_seconds'] as int? ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: (nowPlaying['position_seconds'] as int) / (nowPlaying['duration_seconds'] as int),
                                  minHeight: 3,
                                  backgroundColor: Colors.white.withValues(alpha: 0.22),
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                ),
                              ),
                            )
                          else
                            const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _miniControl(Icons.skip_previous, widget.onPrevious),
                              _miniControl(playing ? Icons.pause : Icons.play_arrow, widget.onPlayPause, filled: true),
                              _miniControl(Icons.skip_next, widget.onNext),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// Generic confirm(-optional) + biometric + fire power action button, used
/// for Log Out, Restart, and Shutdown. Mirrors the daemon's own
/// `needs_confirm` flag per command in commands.py.
/// `expectDaemonDeath` suppresses the error snackbar for commands where the
/// daemon dies before it can respond (reboot/shutdown).
class _PowerActionButton extends StatelessWidget {
  final ApiClient apiClient;
  final String commandId;
  final String label;
  final IconData icon;
  final bool needsConfirm;
  final bool expectDaemonDeath;
  final bool showLabel;
  const _PowerActionButton({
    required this.apiClient,
    required this.commandId,
    required this.label,
    required this.icon,
    required this.needsConfirm,
    this.expectDaemonDeath = false,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidConfirmButton(
      apiClient: apiClient,
      commandId: commandId,
      label: label,
      icon: icon,
      needsConfirm: needsConfirm,
      expectDaemonDeath: expectDaemonDeath,
      variant: LiquidButtonVariant.filled,
      showLabel: showLabel,
      glassStyle: _kPowerButtonGlassStyle,
    );
  }
}
/// Lock/Unlock toggle. Locking uses the existing fire-and-forget
/// `lock-screen` command. Unlocking sends your stored laptop password to
/// the daemon, which types it into the running hyprlock prompt so
/// hyprlock's own PAM check validates it — not a bypass, the same path a
/// physical keystroke takes. The password lives only in this device's
/// secure storage (Android Keystore-backed) and is sent fresh per
/// request; the daemon never writes it to disk.
class _LockToggleButton extends StatelessWidget {
  final ApiClient apiClient;
  final bool? locked;
  final ValueChanged<bool> onChanged;
  final bool showLabel;

  const _LockToggleButton({
    required this.apiClient,
    required this.locked,
    required this.onChanged,
    this.showLabel = true,
  });

  Future<String?> _promptForPassword(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrimeColors.card,
        title: Text('Laptop Password', style: PrimeTheme.mono(fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stored securely on this device only, never on the laptop.',
              style: PrimeTheme.mono(fontSize: 11, color: PrimeColors.mutedForeground),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              style: PrimeTheme.mono(fontSize: 13),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text('Cancel', style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.mutedForeground)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Save', style: PrimeTheme.mono(fontSize: 12, color: PrimeColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _unlock(BuildContext context) async {
    var password = await SecureCredentials.getUnlockPassword();
    if (password == null || password.isEmpty) {
      if (!context.mounted) return;
      password = await _promptForPassword(context);
      if (password == null || password.isEmpty) return;
      await SecureCredentials.setUnlockPassword(password);
    }
    final res = await apiClient.unlockScreen(password);
    final unlocked = res['unlocked'] == true;
    if (unlocked) {
      onChanged(false);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock failed — check the password and try again')),
      );
    }
  }

  Future<void> _lock(BuildContext context) async {
    await apiClient.runCommand('lock-screen');
    onChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = locked ?? false;
    return LiquidConfirmButton(
      key: ValueKey(isLocked),
      label: isLocked ? 'Unlock' : 'Lock',
      icon: isLocked ? Icons.lock_open : Icons.lock_outline,
      onConfirmed: (ctx) => isLocked ? _unlock(ctx) : _lock(ctx),
      variant: LiquidButtonVariant.filled,
      showLabel: showLabel,
      glassStyle: _kPowerButtonGlassStyle,
    );
  }
}
