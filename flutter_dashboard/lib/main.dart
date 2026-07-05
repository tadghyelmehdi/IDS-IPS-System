import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String API_BASE_URL = 'http://192.168.0.172:5000';

void main() => runApp(const IDSApp());

class IDSApp extends StatelessWidget {
  const IDSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IDS/IPS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05080F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF1744),
          error: Color(0xFFFF1744),
        ),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  Map<String, dynamic> _stats = {};
  List<dynamic> _alerts = [];
  List<String> _blocked = [];
  bool _online = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    Timer.periodic(const Duration(seconds: 3), (_) => _fetch());
  }

  Future<void> _fetch() async {
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$API_BASE_URL/stats')).timeout(const Duration(seconds: 3)),
        http.get(Uri.parse('$API_BASE_URL/alerts')).timeout(const Duration(seconds: 3)),
      ]);
      if (results[0].statusCode == 200 && results[1].statusCode == 200) {
        final sd = json.decode(results[0].body);
        final ad = json.decode(results[1].body);
        if (mounted) setState(() {
          _stats = sd['stats'];
          _blocked = List<String>.from(sd['blocked_ips'] ?? []);
          _alerts = ad['alerts'];
          _online = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _online = false);
    }
  }

  Future<void> _unblock(String ip) async {
    try {
      await http.delete(Uri.parse('$API_BASE_URL/unblock/$ip')).timeout(const Duration(seconds: 3));
      _fetch();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$ip debloquee'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF00E676).withValues(alpha: 0.9),
        ));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned(top: -200, right: -200, child: Container(width: 500, height: 500,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [const Color(0xFF00E5FF).withValues(alpha: 0.04), Colors.transparent]),
            ),
          )),
          Positioned(bottom: -150, left: -150, child: Container(width: 400, height: 400,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [const Color(0xFF7C4DFF).withValues(alpha: 0.03), Colors.transparent]),
            ),
          )),
          Row(
            children: [
              _Sidebar(tab: _tab, online: _online, onSelect: (i) => setState(() => _tab = i)),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _Dashboard(stats: _stats, alerts: _alerts, blocked: _blocked, online: _online),
                    _AlertsScreen(alerts: _alerts),
                    _BlockedScreen(blocked: _blocked, onUnblock: _unblock),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── ANIMATED COUNTER ───────────────────────────────────────

class _AnimatedCount extends ImplicitlyAnimatedWidget {
  final int value;
  final TextStyle style;
  const _AnimatedCount({
    super.key, required this.value, required this.style,
    super.duration = const Duration(milliseconds: 600), super.curve = Curves.easeOutCubic,
  });

  @override
  _AnimatedCountState createState() => _AnimatedCountState();
}

class _AnimatedCountState extends AnimatedWidgetBaseState<_AnimatedCount> {
  IntTween? _count;

  @override
  Widget build(BuildContext context) {
    return Text('${_count?.evaluate(animation) ?? widget.value}', style: widget.style);
  }

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _count = visitor(_count, widget.value, (dynamic v) => IntTween(begin: v, end: v)) as IntTween?;
  }
}

// ── SIDEBAR ─────────────────────────────────────────────────

class _Sidebar extends StatefulWidget {
  final int tab; final bool online; final ValueChanged<int> onSelect;
  const _Sidebar({required this.tab, required this.online, required this.onSelect});

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> with SingleTickerProviderStateMixin {
  int _hover = -1;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulse = Tween(begin: 0.0, end: 1.0).animate(_pulseCtrl);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.dashboard_rounded, 'Dashboard'),
      (Icons.warning_amber_rounded, 'Alertes'),
      (Icons.block_rounded, 'IPs bloques'),
    ];
    return Container(
      width: 220,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.08))),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [const Color(0xFF0A0E1A), const Color(0xFF05080F)],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: 0.15), blurRadius: 12)],
                  ),
                  child: const Icon(Icons.shield_rounded, color: Color(0xFF00E5FF), size: 24),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IDS/IPS', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    Text('Security Monitor', style: TextStyle(color: Color(0xFF5A6A7A), fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(height: 1, color: const Color(0xFF00E5FF).withValues(alpha: 0.06)),
          const SizedBox(height: 16),
          ...List.generate(3, (i) {
            final sel = i == widget.tab;
            final hov = i == _hover;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: MouseRegion(
                onEnter: (_) => setState(() => _hover = i),
                onExit: (_) => setState(() => _hover = -1),
                child: GestureDetector(
                  onTap: () => widget.onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF00E5FF).withValues(alpha: 0.1) : (hov ? Colors.white.withValues(alpha: 0.03) : Colors.transparent),
                      borderRadius: BorderRadius.circular(10),
                      border: sel ? Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.25)) : null,
                      boxShadow: sel ? [BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: 0.1), blurRadius: 8)] : null,
                    ),
                    child: Row(
                      children: [
                        Icon(items[i].$1, color: sel ? const Color(0xFF00E5FF) : (hov ? const Color(0xFF8899AA) : const Color(0xFF5A6A7A)), size: 20),
                        const SizedBox(width: 12),
                        Text(items[i].$2, style: TextStyle(
                          color: sel ? const Color(0xFF00E5FF) : (hov ? const Color(0xFF8899AA) : const Color(0xFF5A6A7A)),
                          fontSize: 14, fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        )),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF05080F).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: (widget.online ? const Color(0xFF00E5FF) : const Color(0xFFFF1744)).withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, _) => Container(
                    width: 6 + _pulse.value * 3,
                    height: 6 + _pulse.value * 3,
                    decoration: BoxDecoration(
                      color: widget.online ? const Color(0xFF00E5FF) : const Color(0xFFFF1744),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (widget.online ? const Color(0xFF00E5FF) : const Color(0xFFFF1744))
                              .withValues(alpha: 0.3 + _pulse.value * 0.4),
                          blurRadius: 2 + _pulse.value * 6,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(widget.online ? 'Connecte' : 'Hors ligne',
                    style: TextStyle(
                      color: widget.online ? const Color(0xFF00E5FF) : const Color(0xFFFF1744),
                      fontSize: 12, fontWeight: FontWeight.w500,
                    )),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF05080F).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF00E676), shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Color(0xFF00E676), blurRadius: 4)])),
                const SizedBox(width: 10),
                const Text('Systeme actif', style: TextStyle(color: Color(0xFF00E676), fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── DASHBOARD ───────────────────────────────────────────────

class _Dashboard extends StatelessWidget {
  final Map<String, dynamic> stats; final List<dynamic> alerts;
  final List<String> blocked; final bool online;
  const _Dashboard({required this.stats, required this.alerts, required this.blocked, required this.online});

  @override
  Widget build(BuildContext context) {
    final total = (stats['total_analysed'] ?? 0) as int;
    final atk = (stats['total_attacks'] ?? 0) as int;
    final norm = (stats['total_normal'] ?? 0) as int;
    final blk = (stats['total_blocked'] ?? 0) as int;
    final atkPct = total > 0 ? atk / total * 100 : 0.0;
    final normPct = total > 0 ? norm / total * 100 : 0.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0, backgroundColor: Colors.transparent,
        title: const Text('Tableau de bord', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (online ? const Color(0xFF00E5FF) : const Color(0xFFFF1744)).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: (online ? const Color(0xFF00E5FF) : const Color(0xFFFF1744)).withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(
                  color: online ? const Color(0xFF00E5FF) : const Color(0xFFFF1744),
                  shape: BoxShape.circle,
                  boxShadow: online ? [BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: 0.6), blurRadius: 6)] : null,
                )),
                const SizedBox(width: 6),
                Text(online ? 'EN LIGNE' : 'HORS LIGNE',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1,
                        color: online ? const Color(0xFF00E5FF) : const Color(0xFFFF1744))),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _MetricCard(icon: Icons.analytics_rounded, label: 'Analyses', value: total, color: const Color(0xFF00E5FF))),
                const SizedBox(width: 16),
                Expanded(child: _MetricCard(icon: Icons.bug_report_rounded, label: 'Attaques', value: atk, color: const Color(0xFFFF1744))),
                const SizedBox(width: 16),
                Expanded(child: _MetricCard(icon: Icons.check_circle_rounded, label: 'Normal', value: norm, color: const Color(0xFF00E676))),
                const SizedBox(width: 16),
                Expanded(child: _MetricCard(icon: Icons.block_rounded, label: 'Bloques', value: blk, color: const Color(0xFFFFAB00))),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.08)),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [const Color(0xFF00E5FF).withValues(alpha: 0.03), const Color(0xFF0A0E1A).withValues(alpha: 0.4)],
                      ),
                      boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: 0.04), blurRadius: 24)],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _Legend(color: const Color(0xFF00E676), label: 'Normal (${normPct.toStringAsFixed(1)}%)'),
                            _Legend(color: const Color(0xFFFF1744), label: 'Attaque (${atkPct.toStringAsFixed(1)}%)'),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: 140, height: 140,
                          child: CustomPaint(
                            painter: _DonutPainter(normal: normPct / 100, attack: atkPct / 100),
                            child: Center(
                              child: Text('${total > 0 ? (normPct + atkPct).toStringAsFixed(0) : "0"}%',
                                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            height: 12,
                            child: total > 0
                                ? Row(
                                    children: [
                                      Flexible(flex: norm, child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00E676),
                                          boxShadow: [BoxShadow(color: const Color(0xFF00E676).withValues(alpha: 0.3), blurRadius: 6)],
                                        ),
                                      )),
                                      Flexible(flex: atk, child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF1744),
                                          boxShadow: [BoxShadow(color: const Color(0xFFFF1744).withValues(alpha: 0.3), blurRadius: 6)],
                                        ),
                                      )),
                                    ],
                                  )
                                : Container(color: Colors.grey.withValues(alpha: 0.15)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Total: $total paquets', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Alertes recentes', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text('${alerts.length} total', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...alerts.take(6).map((a) => _AlertTile(alert: a)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon; final String label; final int value; final Color color;
  const _MetricCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.1)),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.05), const Color(0xFF0A0E1A).withValues(alpha: 0.4)],
        ),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 16),
          BoxShadow(color: color.withValues(alpha: 0.04), blurRadius: 32, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 16),
          _AnimatedCount(
            value: value,
            style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w800, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color; final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
      ],
    );
  }
}

// ── ALERT TILE ──────────────────────────────────────────────

class _AlertTile extends StatelessWidget {
  final Map<String, dynamic> alert;
  const _AlertTile({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isAttack = alert['prediction'] == 'Attaque';
    final blocked = alert['blocked'] == true;
    final color = blocked ? const Color(0xFFFFAB00) : isAttack ? const Color(0xFFFF1744) : const Color(0xFF00E676);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: 0.1)),
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.03), const Color(0xFF0A0E1A).withValues(alpha: 0.3)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(blocked ? Icons.block_rounded : isAttack ? Icons.warning_rounded : Icons.check_circle_rounded,
                      color: color, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${alert["src_ip"]}  ->  ${alert["dst_ip"]}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
                      Text(isAttack ? '${alert["attack_type"]}  -  ${alert["timestamp"]}' : 'Normal  -  ${alert["timestamp"]}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.15)),
                  ),
                  child: Text(alert["status"] ?? '', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── ALERTS SCREEN ───────────────────────────────────────────

class _AlertsScreen extends StatelessWidget {
  final List<dynamic> alerts;
  const _AlertsScreen({required this.alerts});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0, backgroundColor: Colors.transparent,
        title: Row(
          children: [
            const Text('Alertes', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFFF1744).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text('${alerts.length}', style: const TextStyle(color: Color(0xFFFF1744), fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
      body: alerts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_rounded, size: 48, color: Colors.grey[800]),
                  const SizedBox(height: 12),
                  Text('Aucune alerte', style: TextStyle(color: Colors.grey[600], fontSize: 15)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: alerts.length,
              itemBuilder: (_, i) => _AlertTile(alert: alerts[i]),
            ),
    );
  }
}

// ── BLOCKED SCREEN ──────────────────────────────────────────

class _BlockedScreen extends StatelessWidget {
  final List<String> blocked;
  final ValueChanged<String> onUnblock;
  const _BlockedScreen({required this.blocked, required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0, backgroundColor: Colors.transparent,
        title: Row(
          children: [
            const Text('IPs bloques', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFFFAB00).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text('${blocked.length}', style: const TextStyle(color: Color(0xFFFFAB00), fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
      body: blocked.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 48, color: Colors.grey[800]),
                  const SizedBox(height: 12),
                  Text('Aucune IP bloquee', style: TextStyle(color: Colors.grey[600], fontSize: 15)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: blocked.length,
              itemBuilder: (_, i) {
                final ip = blocked[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFAB00).withValues(alpha: 0.08)),
                    gradient: LinearGradient(
                      colors: [const Color(0xFFFFAB00).withValues(alpha: 0.03), const Color(0xFF0A0E1A).withValues(alpha: 0.3)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFAB00).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [BoxShadow(color: const Color(0xFFFFAB00).withValues(alpha: 0.1), blurRadius: 8)],
                        ),
                        child: const Icon(Icons.block_rounded, color: Color(0xFFFFAB00), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(ip, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w500)),
                      ),
                      TextButton(
                        onPressed: () => onUnblock(ip),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676).withValues(alpha: 0.1),
                          foregroundColor: const Color(0xFF00E676),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                        ),
                        child: const Text('Debloquer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ── DONUT PAINTER ───────────────────────────────────────────

class _DonutPainter extends CustomPainter {
  final double normal; final double attack;
  _DonutPainter({required this.normal, required this.attack});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 10;
    const sw = 20.0;

    if (normal + attack == 0) {
      canvas.drawCircle(c, r, Paint()
        ..color = Colors.grey.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke..strokeWidth = sw..strokeCap = StrokeCap.round);
      return;
    }

    void drawArc(double start, double sweep, Color color) {
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(rect, start, sweep, false, Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke..strokeWidth = sw + 8..strokeCap = StrokeCap.round);
      canvas.drawArc(rect, start, sweep, false, Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke..strokeWidth = sw + 4..strokeCap = StrokeCap.round);
      canvas.drawArc(rect, start, sweep, false, Paint()
        ..color = color
        ..style = PaintingStyle.stroke..strokeWidth = sw..strokeCap = StrokeCap.round);
    }

    if (normal > 0) drawArc(-math.pi / 2, normal * 2 * math.pi, const Color(0xFF00E676));
    if (attack > 0) drawArc(-math.pi / 2 + normal * 2 * math.pi, attack * 2 * math.pi, const Color(0xFFFF1744));
  }

  @override
  bool shouldRepaint(covariant _DonutPainter o) => o.normal != normal || o.attack != attack;
}
