import 'package:flutter/material.dart';
import '../models/ion_model.dart';
import 'ion_card.dart';

class DashboardCanvas extends StatelessWidget {
  final List<IonModel> ions;
  final Map<int, double> intensity;
  final bool connected;
  final String timeText;
  final double Function(String ion, double I) toConcentration;
  final String Function(String ion) unitOf;

  final String statusOverride;
  final VoidCallback onRetry;

  const DashboardCanvas({
    super.key,
    required this.ions,
    required this.intensity,
    required this.connected,
    required this.timeText,
    required this.toConcentration,
    required this.unitOf,
    required this.statusOverride,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    const pad = 18.0;
    const designH = 680.0;

    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final usableH = (h - pad * 2).clamp(0.0, double.infinity);

        double s(double v) => v * (usableH / designH);

        final headerH = s(96.0).clamp(76.0, 140.0);
        final intensityH = s(56.0).clamp(44.0, 90.0);
        final bottomH = s(46.0).clamp(40.0, 80.0);

        final gap1 = s(14.0).clamp(8.0, 18.0);
        final gap2 = s(14.0).clamp(8.0, 18.0);
        final gap3 = s(14.0).clamp(8.0, 18.0);

        final cardsAreaH = (usableH -
            headerH -
            intensityH -
            bottomH -
            gap1 -
            gap2 -
            gap3)
            .clamp(0.0, double.infinity);

        return Padding(
          padding: const EdgeInsets.all(pad),
          child: Column(
            children: [
              SizedBox(
                height: headerH,
                child: _ColorHeader(
                  title: '饮食检测',
                  connected: connected,
                  timeText: timeText,
                  statusOverride: statusOverride,
                  onRetry: onRetry,
                  c1: const Color(0xFF7C5CFF),
                  c2: const Color(0xFF36C3FF),
                ),
              ),
              SizedBox(height: gap1),
              SizedBox(height: intensityH, child: _IntensityStrip(intensity: intensity)),
              SizedBox(height: gap2),
              SizedBox(
                height: cardsAreaH,
                child: _TwoRowCards(
                  ions: ions,
                  intensity: intensity,
                  toConcentration: toConcentration,
                  unitOf: unitOf,
                ),
              ),
              SizedBox(height: gap3),
              SizedBox(
                height: bottomH,
                child: _BottomBar(
                  onRecordTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('这里后续接：开始/停止记录 + 导出CSV')),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TwoRowCards extends StatelessWidget {
  final List<IonModel> ions;
  final Map<int, double> intensity;
  final double Function(String ion, double I) toConcentration;
  final String Function(String ion) unitOf;

  const _TwoRowCards({
    required this.ions,
    required this.intensity,
    required this.toConcentration,
    required this.unitOf,
  });

  @override
  Widget build(BuildContext context) {
    final a = ions[0];
    final b = ions[1];
    final c = ions[2];
    final d = ions[3];

    const gap = 14.0;

    Widget card(IonModel m) {
      final I = intensity[m.wavelengthNm] ?? 0;
      final C = toConcentration(m.ion, I);
      return IonCard(
        model: m,
        intensity: I,
        concentration: C,
        unit: unitOf(m.ion),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: card(a)),
              const SizedBox(width: gap),
              Expanded(child: card(b)),
            ],
          ),
        ),
        const SizedBox(height: gap),
        Expanded(
          child: Row(
            children: [
              Expanded(child: card(c)),
              const SizedBox(width: gap),
              Expanded(child: card(d)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorHeader extends StatelessWidget {
  final String title;
  final bool connected;
  final String timeText;
  final String statusOverride;
  final VoidCallback onRetry;
  final Color c1;
  final Color c2;

  const _ColorHeader({
    required this.title,
    required this.connected,
    required this.timeText,
    required this.statusOverride,
    required this.onRetry,
    required this.c1,
    required this.c2,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = statusOverride;
    final statusColor =
    connected ? const Color(0xFF1DBE7C) : const Color(0xFFFFC857);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.14),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Last update · $timeText',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.88),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.24)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                      BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 30,
                child: OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.6)),
                  ),
                  child: const Text('重连'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntensityStrip extends StatelessWidget {
  final Map<int, double> intensity;
  const _IntensityStrip({required this.intensity});

  Widget _chip(String label, String value, Color c1, Color c2) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1.withOpacity(0.18), c2.withOpacity(0.18)],
        ),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String v(int wl) => (intensity[wl] ?? 0).toStringAsFixed(0);

    return Row(
      children: [
        Expanded(child: _chip('520nm', v(520), const Color(0xFFFFB55A), const Color(0xFFFF5B8C))),
        const SizedBox(width: 10),
        Expanded(child: _chip('635nm', v(635), const Color(0xFF7C5CFF), const Color(0xFF36C3FF))),
        const SizedBox(width: 10),
        Expanded(child: _chip('450nm', v(450), const Color(0xFF2E8BFF), const Color(0xFF00D1FF))),
        const SizedBox(width: 10),
        Expanded(child: _chip('590nm', v(590), const Color(0xFF1DBE7C), const Color(0xFFB7F34D))),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  final VoidCallback onRecordTap;
  const _BottomBar({required this.onRecordTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              border: Border.all(color: Colors.black.withOpacity(0.06)),
              boxShadow: [
                BoxShadow(
                  blurRadius: 16,
                  offset: const Offset(0, 10),
                  color: Colors.black.withOpacity(0.06),
                ),
              ],
            ),
            child: InkWell(
              onTap: onRecordTap,
              borderRadius: BorderRadius.circular(16),
              child: const Center(
                child: Text(
                  '开始记录（占位）',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}