import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Event from the YouTube IFrame player.
class EmbedEvent {
  const EmbedEvent(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
}

/// Plays YouTube videos with YouTube's official embedded (IFrame API) player in a
/// WebView. This is the supported way for third-party apps to play YouTube content.
/// Its audio is produced inside the web view, so the Carrozzeria DSP does not apply to it
/// (DSP applies to downloaded files and other audio played by the native player).
class EmbedPlayer {
  EmbedPlayer() {
    final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('Carro', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        // Keep the page on the player: taps on the YouTube logo etc. must not navigate away.
        onNavigationRequest: (r) => r.isMainFrame && !r.url.startsWith(_variant.baseUrl)
            ? NavigationDecision.prevent
            : NavigationDecision.navigate,
      ));
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    _loadPage();
  }

  /// Page setups that YouTube accepts as an embedder. The first one is what the
  /// youtube_player_iframe package uses on mobile (page + player on youtube-nocookie.com);
  /// the others are fallbacks when YouTube answers with embed error 152/153.
  static const _variants = <_EmbedVariant>[
    _EmbedVariant('https://www.youtube-nocookie.com', 'https://www.youtube-nocookie.com', null),
    _EmbedVariant('https://www.youtube.com', 'https://www.youtube.com', null),
    _EmbedVariant('https://carrotube.app', 'https://www.youtube.com', 'https://carrotube.app'),
  ];
  int _variantIndex = 0;
  _EmbedVariant get _variant => _variants[_variantIndex];

  void _loadPage() {
    final v = _variant;
    final origin = v.origin == null ? '' : "origin: '${v.origin}', widget_referrer: '${v.origin}', ";
    final html = _html.replaceAll('__HOST__', v.host).replaceAll('__ORIGIN__', origin);
    controller.loadHtmlString(html, baseUrl: '${v.baseUrl}/');
  }

  /// Switches to the next embedder setup (after error 152/153). Returns false when all
  /// setups were tried.
  bool tryNextVariant() {
    if (_variantIndex + 1 >= _variants.length) return false;
    _variantIndex++;
    _loadPage();
    return true;
  }

  late final WebViewController controller;
  final _events = StreamController<EmbedEvent>.broadcast();
  Stream<EmbedEvent> get events => _events.stream;

  void _onMessage(JavaScriptMessage m) {
    try {
      final j = (jsonDecode(m.message) as Map).cast<String, dynamic>();
      _events.add(EmbedEvent(j['type'] as String? ?? '', j));
    } catch (e) {
      debugPrint('embed message: $e');
    }
  }

  Future<void> _js(String code) async {
    try {
      await controller.runJavaScript(code);
    } catch (e) {
      debugPrint('embed js: $e');
    }
  }

  Future<void> load(String videoId, {double startSeconds = 0, bool autoplay = true}) =>
      _js('carroLoad(${jsonEncode(videoId)}, $startSeconds, $autoplay)');
  Future<void> play() => _js('player && player.playVideo()');
  Future<void> pause() => _js('player && player.pauseVideo()');
  Future<void> stop() => _js('player && player.stopVideo()');
  Future<void> seek(Duration d) => _js('player && player.seekTo(${d.inMilliseconds / 1000}, true)');
  Future<void> setRate(double r) => _js('player && player.setPlaybackRate($r)');

  void dispose() => _events.close();

  static const _html = '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
html,body{margin:0;padding:0;background:#000;width:100%;height:100%;overflow:hidden}
#p{position:absolute;left:0;top:0;width:100%;height:100%}
</style>
</head><body>
<div id="p"></div>
<script>
var player = null, ready = false, pending = null, timer = null;
function send(o) { try { Carro.postMessage(JSON.stringify(o)); } catch (e) {} }
window.onerror = function(msg) { send({type: 'jserror', message: String(msg)}); };
function onYouTubeIframeAPIReady() {
  player = new YT.Player('p', {
    width: '100%', height: '100%',
    host: '__HOST__',
    playerVars: {playsinline: 1, controls: 0, rel: 0, iv_load_policy: 3, __ORIGIN__
                 fs: 0, disablekb: 1, enablejsapi: 1, autoplay: 0},
    events: {
      onReady: function() {
        ready = true;
        send({type: 'ready'});
        if (pending) { carroLoad(pending[0], pending[1], pending[2]); pending = null; }
        timer = setInterval(tick, 250);
      },
      onStateChange: function(e) { send({type: 'state', s: e.data}); tick(); },
      onError: function(e) { send({type: 'error', code: e.data}); },
      onPlaybackRateChange: function(e) { send({type: 'rate', r: e.data}); }
    }
  });
}
function tick() {
  if (!player || !player.getCurrentTime) return;
  send({type: 'time', t: player.getCurrentTime() || 0, d: player.getDuration() || 0,
        b: player.getVideoLoadedFraction() || 0, s: player.getPlayerState()});
}
function carroLoad(id, start, autoplay) {
  if (!ready) { pending = [id, start, autoplay]; return; }
  if (autoplay) player.loadVideoById({videoId: id, startSeconds: start});
  else player.cueVideoById({videoId: id, startSeconds: start});
}
</script>
<script src="https://www.youtube.com/iframe_api"></script>
</body></html>
''';
}

final embedPlayerProvider = Provider<EmbedPlayer>((ref) {
  final p = EmbedPlayer();
  ref.onDispose(p.dispose);
  return p;
});

/// The embedded player's surface. Only one instance may be on screen at a time; the
/// underlying WebView (and playback) survives when this widget is rebuilt elsewhere.
class EmbedPlayerSurface extends ConsumerWidget {
  const EmbedPlayerSurface({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(embedPlayerProvider);
    return IgnorePointer(child: WebViewWidget(controller: p.controller));
  }
}

class _EmbedVariant {
  const _EmbedVariant(this.baseUrl, this.host, this.origin);
  final String baseUrl;
  final String host;
  final String? origin;
}

/// Human-readable IFrame API error.
String embedErrorText(int code) => switch (code) {
      2 => 'Invalid video id (2)',
      5 => 'HTML5 player error (5)',
      100 => 'Video not found or private (100)',
      101 || 150 => 'The owner does not allow playback in other apps (150)',
      152 || 153 => 'YouTube embed configuration error ($code)',
      _ => 'YouTube player error ($code)',
    };
