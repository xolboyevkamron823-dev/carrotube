import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Round channel avatar; falls back to a coloured circle with the first letter.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, this.url, required this.name, this.size = 36});
  final String? url;
  final String name;
  final double size;

  static const _palette = <Color>[
    Color(0xFFE53935),
    Color(0xFF8E24AA),
    Color(0xFF3949AB),
    Color(0xFF039BE5),
    Color(0xFF00897B),
    Color(0xFF7CB342),
    Color(0xFFFB8C00),
    Color(0xFF6D4C41),
    Color(0xFF546E7A),
    Color(0xFFD81B60),
  ];

  String get _letter {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final rune = t.runes.first;
    return String.fromCharCode(rune).toUpperCase();
  }

  Widget _fallback() {
    final color = _palette[name.hashCode.abs() % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        _letter,
        style: TextStyle(color: Colors.white, fontSize: size * 0.45, fontWeight: FontWeight.w500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return _fallback();
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: px,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, _) => _fallback(),
        errorWidget: (_, _, _) => _fallback(),
      ),
    );
  }
}
