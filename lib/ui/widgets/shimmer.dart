import 'package:flutter/material.dart';

/// YouTube-style loading shimmer: a soft highlight sweeping over grey placeholder shapes.
/// Wrap a whole group of [SkeletonBox]es in one [Shimmer] so they animate in sync.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF272727) : const Color(0xFFE5E5E5);
    final highlight = dark ? const Color(0xFF3D3D3D) : const Color(0xFFF7F7F7);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [base, base, highlight, base, base],
          stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
          transform: _SlideGradient(_c.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);
  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    // Sweep from fully left of the bounds to fully right.
    final dx = (t * 2 - 1) * bounds.width * 1.2;
    return Matrix4.translationValues(dx, 0, 0);
  }
}

/// A grey placeholder shape (must sit inside a [Shimmer] to animate).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius = 4, this.circle = false});
  final double? width;
  final double? height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF272727) : const Color(0xFFE5E5E5),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton of a big home-feed [VideoCard].
class VideoCardSkeleton extends StatelessWidget {
  const VideoCardSkeleton({super.key, this.horizontalPadding = 12});
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: const AspectRatio(aspectRatio: 16 / 9, child: SkeletonBox(radius: 12)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(width: 36, height: 36, circle: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SkeletonBox(height: 14),
                      const SizedBox(height: 8),
                      FractionallySizedBox(widthFactor: 0.6, child: const SkeletonBox(height: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton of a compact [VideoTile].
class VideoTileSkeleton extends StatelessWidget {
  const VideoTileSkeleton({super.key, this.thumbWidth = 160});
  final double thumbWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: thumbWidth,
            child: const AspectRatio(aspectRatio: 16 / 9, child: SkeletonBox(radius: 8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(height: 13),
                const SizedBox(height: 6),
                const SkeletonBox(height: 13),
                const SizedBox(height: 10),
                FractionallySizedBox(widthFactor: 0.5, child: const SkeletonBox(height: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton of a channel row.
class ChannelTileSkeleton extends StatelessWidget {
  const ChannelTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SkeletonBox(width: 56, height: 56, circle: true),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [SkeletonBox(height: 14, width: 160), SizedBox(height: 8), SkeletonBox(height: 11, width: 100)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton of a square music card in a horizontal shelf.
class SquareCardSkeleton extends StatelessWidget {
  const SquareCardSkeleton({super.key, this.size = 150});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: size, height: size, radius: 6),
          const SizedBox(height: 8),
          SkeletonBox(width: size * 0.9, height: 12),
          const SizedBox(height: 6),
          SkeletonBox(width: size * 0.6, height: 11),
        ],
      ),
    );
  }
}

/// Column of [count] skeletons inside one shimmer.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, required this.itemBuilder, this.count = 6});
  final Widget Function(int index) itemBuilder;
  final int count;

  /// Home-feed style list.
  factory SkeletonList.cards({int count = 4}) =>
      SkeletonList(count: count, itemBuilder: (_) => const VideoCardSkeleton());

  /// Compact list.
  factory SkeletonList.tiles({int count = 8}) =>
      SkeletonList(count: count, itemBuilder: (_) => const VideoTileSkeleton());

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < count; i++) itemBuilder(i)]),
    );
  }
}

/// Horizontal shelf of square skeletons.
class ShelfSkeleton extends StatelessWidget {
  const ShelfSkeleton({super.key, this.size = 150});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size + 52,
      child: Shimmer(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, _) => SquareCardSkeleton(size: size),
        ),
      ),
    );
  }
}
