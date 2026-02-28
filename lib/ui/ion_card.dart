import 'package:flutter/material.dart';
import '../models/ion_model.dart';

class IonCard extends StatelessWidget {
  final IonModel model;
  final double intensity;
  final double concentration;
  final String unit;

  const IonCard({
    super.key,
    required this.model,
    required this.intensity,
    required this.concentration,
    required this.unit,
  });

  String _status(double c) {
    if (c < 1.0) return '偏低';
    if (c > 5.0) return '偏高';
    return '正常';
  }

  Widget _ionTitleSup(String ion, double s) {
    final m = RegExp(r'^([A-Za-z]+)(.*)$').firstMatch(ion);
    final base = m?.group(1) ?? ion;
    final charge = (m?.group(2) ?? '').trim();

    final baseStyle = TextStyle(
      fontSize: 20 * s,
      fontWeight: FontWeight.w900,
      color: Colors.white,
    );

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: base, style: baseStyle),
          if (charge.isNotEmpty)
            WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Transform.translate(
                offset: Offset(0, -6 * s),
                child: Text(
                  charge,
                  style: TextStyle(
                    fontSize: 12 * s,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _status(concentration);

    // ✅ 关键：卡片内部基于自身尺寸计算缩放 s，字体/间距随卡片变化
    return LayoutBuilder(
      builder: (context, c) {
        final s = (c.maxWidth / 170.0).clamp(0.88, 1.15);

        final pad = (14.0 * s).clamp(11.0, 16.0);
        final bigNum = 30.0 * s;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [model.c1, model.c2],
            ),
            boxShadow: [
              BoxShadow(
                blurRadius: 22,
                offset: const Offset(0, 12),
                color: Colors.black.withOpacity(0.12),
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(1.2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              color: Colors.white.withOpacity(0.14),
              border: Border.all(color: Colors.white.withOpacity(0.20)),
            ),
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部行
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IconBubble(icon: model.icon, s: s),
                      SizedBox(width: 10 * s),
                      Flexible(child: _ionTitleSup(model.ion, s)),
                      SizedBox(width: 8 * s),
                      _Pill(label: label, s: s),
                    ],
                  ),

                  SizedBox(height: 8 * s),
                  Text(
                    '波长 ${model.wavelengthNm} nm · ${model.food}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontWeight: FontWeight.w700,
                      fontSize: 13.0 * s,
                      height: 1.15,
                    ),
                  ),

                  // 中间吃掉空间，保证底部 I= 永远在卡片内
                  const SizedBox(height: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '浓度',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5 * s,
                          ),
                        ),
                        SizedBox(height: 6 * s),

                        // ✅ 大数字用 FittedBox：再窄也不会溢出/重叠
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  concentration.toStringAsFixed(2),
                                  style: TextStyle(
                                    fontSize: bigNum,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 6 * s),
                            Padding(
                              padding: EdgeInsets.only(bottom: 2 * s),
                              child: Text(
                                unit,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.0 * s,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 底部固定：I=
                  Text(
                    'I=${intensity.toStringAsFixed(2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontWeight: FontWeight.w700,
                      fontSize: 13.0 * s,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final double s;
  const _IconBubble({required this.icon, required this.s});

  @override
  Widget build(BuildContext context) {
    final size = (34.0 * s).clamp(30.0, 38.0);
    final iconSize = (18.0 * s).clamp(16.0, 20.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final double s;
  const _Pill({required this.label, required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 12.0 * s,
        ),
      ),
    );
  }
}