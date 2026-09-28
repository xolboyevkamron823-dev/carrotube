import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';

/// Full-size error state with a Retry button.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, this.error, this.onRetry, this.compact = false});
  final Object? error;
  final VoidCallback? onRetry;
  final bool compact;

  static bool _isOffline(Object? e) =>
      e is SocketException || (e?.toString().contains('SocketException') ?? false) || e is HandshakeException;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final offline = _isOffline(error);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
          size: compact ? 32 : 64,
          color: scheme.onSurfaceVariant,
        ),
        SizedBox(height: compact ? 8 : 16),
        Text(
          context.tr(offline ? 'offline' : 'error_loading'),
          textAlign: TextAlign.center,
          style: (compact ? Theme.of(context).textTheme.bodyMedium : Theme.of(context).textTheme.titleMedium)?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        if (!offline && !compact && error != null) ...[
          const SizedBox(height: 6),
          Text(
            error.toString(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (onRetry != null) ...[
          SizedBox(height: compact ? 8 : 20),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              shape: const StadiumBorder(),
              side: BorderSide(color: scheme.outline),
              foregroundColor: scheme.onSurface,
            ),
            child: Text(context.tr('retry')),
          ),
        ],
      ],
    );
    return Center(
      child: Padding(padding: EdgeInsets.all(compact ? 16 : 32), child: content),
    );
  }
}

/// Empty state (icon + message + optional action).
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, this.icon = Icons.video_library_outlined, this.message, this.subtitle, this.action});
  final IconData icon;
  final String? message;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(
              message ?? context.tr('nothing_here'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Footer of an infinite list: spinner while loading more, retry row on error.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({super.key, required this.loading, this.error, this.onRetry});
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tr('retry')),
          ),
        ),
      );
    }
    if (!loading) return const SizedBox(height: 16);
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: YtColors.red)),
      ),
    );
  }
}

/// Calls [onLoadMore] when the wrapped scrollable gets close to its end.
class InfiniteScroll extends StatelessWidget {
  const InfiniteScroll({super.key, required this.child, required this.onLoadMore, this.threshold = 900});
  final Widget child;
  final VoidCallback onLoadMore;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < threshold) onLoadMore();
        return false;
      },
      child: child,
    );
  }
}

/// Small section header ("Up next", "History" ...), optionally with a trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.padding, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null)
                  Text(
                    subtitle!.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.8,
                    ),
                  ),
                Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Shows a short floating snackbar.
void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
}
