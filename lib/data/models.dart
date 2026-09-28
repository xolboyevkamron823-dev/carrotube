/// Plain data models used across the app (independent of youtube_explode types so they
/// can be stored in SQLite and passed around freely).
library;

class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.channelName,
    this.channelId,
    this.duration,
    this.viewCount,
    this.uploadDate,
    this.uploadDateText,
    this.description,
    this.isLive = false,
    this.likeCount,
    this.thumbnail,
  });

  final String id;
  final String title;
  final String channelName;
  final String? channelId;
  final Duration? duration;
  final int? viewCount;
  final DateTime? uploadDate;
  final String? uploadDateText;
  final String? description;
  final bool isLive;
  final int? likeCount;
  final String? thumbnail;

  String get thumbnailUrl => thumbnail ?? 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  String get maxThumbnailUrl => 'https://i.ytimg.com/vi/$id/maxresdefault.jpg';
  String get url => 'https://www.youtube.com/watch?v=$id';

  VideoItem copyWith({String? description, int? likeCount, int? viewCount, DateTime? uploadDate, Duration? duration}) =>
      VideoItem(
        id: id,
        title: title,
        channelName: channelName,
        channelId: channelId,
        duration: duration ?? this.duration,
        viewCount: viewCount ?? this.viewCount,
        uploadDate: uploadDate ?? this.uploadDate,
        uploadDateText: uploadDateText,
        description: description ?? this.description,
        isLive: isLive,
        likeCount: likeCount ?? this.likeCount,
        thumbnail: thumbnail,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'channelName': channelName,
        'channelId': channelId,
        'durationMs': duration?.inMilliseconds,
        'viewCount': viewCount,
        'uploadDate': uploadDate?.millisecondsSinceEpoch,
        'uploadDateText': uploadDateText,
        'isLive': isLive ? 1 : 0,
        'thumbnail': thumbnail,
      };

  factory VideoItem.fromJson(Map<String, Object?> j) => VideoItem(
        id: j['id']! as String,
        title: (j['title'] as String?) ?? '',
        channelName: (j['channelName'] as String?) ?? '',
        channelId: j['channelId'] as String?,
        duration: j['durationMs'] == null ? null : Duration(milliseconds: (j['durationMs']! as num).toInt()),
        viewCount: (j['viewCount'] as num?)?.toInt(),
        uploadDate: j['uploadDate'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['uploadDate']! as num).toInt()),
        uploadDateText: j['uploadDateText'] as String?,
        isLive: j['isLive'] == 1 || j['isLive'] == true,
        thumbnail: j['thumbnail'] as String?,
      );

  @override
  bool operator ==(Object other) => other is VideoItem && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class ChannelItem {
  const ChannelItem({
    required this.id,
    required this.title,
    this.avatarUrl,
    this.bannerUrl,
    this.subscriberCount,
    this.videoCount,
    this.description,
  });

  final String id;
  final String title;
  final String? avatarUrl;
  final String? bannerUrl;
  final int? subscriberCount;
  final int? videoCount;
  final String? description;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'avatarUrl': avatarUrl,
        'bannerUrl': bannerUrl,
        'subscriberCount': subscriberCount,
      };

  factory ChannelItem.fromJson(Map<String, Object?> j) => ChannelItem(
        id: j['id']! as String,
        title: (j['title'] as String?) ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        bannerUrl: j['bannerUrl'] as String?,
        subscriberCount: (j['subscriberCount'] as num?)?.toInt(),
      );
}

class PlaylistItem {
  const PlaylistItem({
    required this.id,
    required this.title,
    this.author,
    this.thumbnailUrl,
    this.videoCount,
    this.description,
  });

  final String id;
  final String title;
  final String? author;
  final String? thumbnailUrl;
  final int? videoCount;
  final String? description;
}

class CommentItem {
  const CommentItem({
    required this.author,
    required this.text,
    required this.likeCount,
    required this.publishedTime,
    required this.replyCount,
    this.channelId,
    this.isHearted = false,
  });

  final String author;
  final String text;
  final int likeCount;
  final String publishedTime;
  final int replyCount;
  final String? channelId;
  final bool isHearted;
}

/// Local (on-device) playlist.
class LocalPlaylist {
  const LocalPlaylist({required this.id, required this.name, required this.created, this.count = 0, this.cover});

  final int id;
  final String name;
  final DateTime created;
  final int count;
  final String? cover;
}

enum DownloadStatus { queued, running, done, failed, canceled }

class DownloadItem {
  const DownloadItem({
    required this.video,
    required this.audioOnly,
    required this.status,
    this.progress = 0,
    this.filePath,
    this.videoFilePath,
    this.sizeBytes = 0,
    this.error,
    required this.createdAt,
  });

  final VideoItem video;
  final bool audioOnly;
  final DownloadStatus status;
  final double progress;

  /// Audio file (m4a) - always present for finished downloads.
  final String? filePath;

  /// Video-only mp4 (video downloads keep audio and video as separate files and the native
  /// player muxes them on the fly, so every download stays playable through the DSP).
  final String? videoFilePath;
  final int sizeBytes;
  final String? error;
  final DateTime createdAt;

  DownloadItem copyWith({
    DownloadStatus? status,
    double? progress,
    String? filePath,
    String? videoFilePath,
    int? sizeBytes,
    String? error,
  }) =>
      DownloadItem(
        video: video,
        audioOnly: audioOnly,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        filePath: filePath ?? this.filePath,
        videoFilePath: videoFilePath ?? this.videoFilePath,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        error: error,
        createdAt: createdAt,
      );
}

/// One entry in a search result list.
sealed class SearchEntry {
  const SearchEntry();
}

class SearchVideoEntry extends SearchEntry {
  const SearchVideoEntry(this.video);
  final VideoItem video;
}

class SearchChannelEntry extends SearchEntry {
  const SearchChannelEntry(this.channel);
  final ChannelItem channel;
}

class SearchPlaylistEntry extends SearchEntry {
  const SearchPlaylistEntry(this.playlist);
  final PlaylistItem playlist;
}

/// Search filters shown in the filter sheet (YouTube allows one "sp" filter at a time).
enum SearchType { all, videos, channels, playlists }

enum SearchDuration { any, short, long }

enum SearchUploadDate { any, hour, today, week, month, year }

class SearchFilters {
  const SearchFilters({
    this.type = SearchType.all,
    this.duration = SearchDuration.any,
    this.uploadDate = SearchUploadDate.any,
  });

  final SearchType type;
  final SearchDuration duration;
  final SearchUploadDate uploadDate;

  bool get isDefault => type == SearchType.all && duration == SearchDuration.any && uploadDate == SearchUploadDate.any;

  SearchFilters copyWith({SearchType? type, SearchDuration? duration, SearchUploadDate? uploadDate}) => SearchFilters(
        type: type ?? this.type,
        duration: duration ?? this.duration,
        uploadDate: uploadDate ?? this.uploadDate,
      );
}

/// Available stream choices of a video (for the quality selector).
class StreamChoice {
  const StreamChoice({required this.label, required this.height, required this.url, required this.muxed});
  final String label;
  final int height;
  final String url;
  final bool muxed;
}

/// Resolved playable URLs for one video.
class ResolvedStreams {
  const ResolvedStreams({
    required this.audioUrl,
    required this.headers,
    required this.videoChoices,
    this.muxedUrl,
    required this.resolvedAt,
    this.audioBitrateKbps,
    this.audioCodec,
  });

  final String audioUrl;
  final Map<String, String> headers;
  final List<StreamChoice> videoChoices;
  final String? muxedUrl;
  final DateTime resolvedAt;
  final int? audioBitrateKbps;
  final String? audioCodec;

  /// YouTube stream URLs live ~6 h; refresh a little earlier.
  bool get isStale => DateTime.now().difference(resolvedAt) > const Duration(hours: 5);
}
