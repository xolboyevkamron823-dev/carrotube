import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

/// Network image with a grey placeholder and an optional fallback URL (e.g. maxres ->
/// hqdefault, since not every video has a maxres thumbnail).
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fallbackUrl, this.fit = BoxFit.cover, this.cacheWidth});
  final String? url;
  final String? fallbackUrl;
  final BoxFit fit;

  /// Decode width in logical pixels (multiplied by the device pixel ratio).
  final double? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final placeholder = ColoredBox(color: dark ? const Color(0xFF272727) : const Color(0xFFE5E5E5));
    final u = url;
    if (u == null || u.isEmpty) {
      return fallbackUrl == null ? placeholder : NetImage(fallbackUrl, fit: fit, cacheWidth: cacheWidth);
    }
    final px = cacheWidth == null ? null : (cacheWidth! * MediaQuery.devicePixelRatioOf(context)).round();
    return CachedNetworkImage(
      imageUrl: u,
      fit: fit,
      memCacheWidth: px,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => fallbackUrl != null && fallbackUrl != u
          ? NetImage(fallbackUrl, fit: fit, cacheWidth: cacheWidth)
          : placeholder,
    );
  }
}

/// 16:9 thumbnail with rounded corners, duration badge and LIVE badge.
class VideoThumbnail extends StatelessWidget {
  const VideoThumbnail({
    super.key,
    required this.video,
    this.radius = 12,
    this.showBadges = true,
    this.highRes = false,
    this.cacheWidth,
    this.progress,
  });

  final VideoItem video;
  final double radius;
  final bool showBadges;
  final bool highRes;
  final double? cacheWidth;

  /// Optional red "watched" / download progress bar at the bottom (0..1).
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetImage(
              highRes ? video.maxThumbnailUrl : video.thumbnailUrl,
              fallbackUrl: highRes ? video.thumbnailUrl : null,
              cacheWidth: cacheWidth,
            ),
            if (showBadges && video.isLive)
              const Positioned(right: 6, bottom: 6, child: LiveBadge())
            else if (showBadges && video.duration != null && video.duration! > Duration.zero)
              Positioned(right: 6, bottom: 6, child: DurationBadge(video.duration!)),
            if (progress != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress!.clamp(0, 1),
                  minHeight: 3,
                  color: YtColors.red,
                  backgroundColor: Colors.white.withValues(alpha: 0.35),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DurationBadge extends StatelessWidget {
  const DurationBadge(this.duration, {super.key});
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4)),
      child: Text(
        formatDuration(duration),
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500, height: 1.3),
      ),
    );
  }
}

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(color: YtColors.red, borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sensors, size: 13, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            context.tr('live_badge'),
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// "Channel · 1.2M views · 3 days ago" for a video.
String videoMetaLine(BuildContext context, VideoItem v, {bool withChannel = true}) {
  final lang = Localizations.localeOf(context).languageCode;
  final parts = <String>[
    if (withChannel && v.channelName.isNotEmpty) v.channelName,
    if (v.viewCount != null && v.viewCount! > 0) context.tr('views_n', {'n': compactNumber(v.viewCount)}),
    if (v.uploadDate != null)
      timeAgo(v.uploadDate, lang: lang)
    else if (v.uploadDateText != null && v.uploadDateText!.isNotEmpty)
      v.uploadDateText!,
  ];
  return parts.join(' · ');
}
