import 'package:equatable/equatable.dart';

import '../data/resource_record.dart';
import 'json_reader.dart';

/// One file from Spatie's medialibrary — the client's read of an entry in
/// the `<field>.__media` sibling a medialibrary-backed field publishes
/// alongside its raw value (a media-uuid string, or a list of them for a
/// multi-file field). The raw value is what a form submits back; this is
/// what a screen renders.
class MediaItem extends Equatable {
  const MediaItem({
    required this.uuid,
    required this.url,
    this.thumbUrl,
    this.name,
    this.size,
    this.mime,
  });

  final String uuid;
  final String url;
  final String? thumbUrl;
  final String? name;
  final int? size;
  final String? mime;

  /// The thumbnail conversion when the server generated one, otherwise the
  /// original file — the URL a card or a form's preview should render.
  String get displayUrl => thumbUrl ?? url;

  @override
  List<Object?> get props => [uuid, url, thumbUrl, name, size, mime];
}

/// The parsed `<field>.__media` sibling: every [MediaItem] the server could
/// resolve for a medialibrary-backed field's raw uuid token(s).
///
/// An entry missing `uuid` or `url` is dropped rather than failing the whole
/// set — a stale or since-deleted media row is the server's problem to
/// clean up, not a reason to blank every other attachment on the record.
/// Unknown keys are ignored, the same scalar-widening licence [opt] gives
/// every other schema parser in this package.
class MediaSet extends Equatable {
  const MediaSet({required this.items});

  final List<MediaItem> items;

  /// Reads the flat `<field>.__media` sibling off [record]. Null when the
  /// field carries no such sibling (not a medialibrary field, or the field
  /// is simply absent from this record) or the sibling is not a list — both
  /// read as "nothing to show" rather than a parse failure, since a screen
  /// with no media field configured is the ordinary case, not an error one.
  static MediaSet? of(ResourceRecord record, String field) {
    final raw = record.get<List<dynamic>>('$field.__media');
    if (raw == null) return null;
    return MediaSet.fromJson(raw, '$field.__media');
  }

  /// [json] is the `<field>.__media` sibling itself — a list of media maps.
  ///
  /// [path] is accepted for signature parity with [RichDocument.fromJson]'s
  /// precedent, but unused here: a malformed item is dropped, not named in
  /// an exception, so there is never a per-item path to report.
  factory MediaSet.fromJson(List<dynamic> json, String path) {
    final items = <MediaItem>[];

    for (final entry in json) {
      if (entry is! Map<String, dynamic>) continue;

      final uuid = opt<String>(entry, 'uuid');
      final url = opt<String>(entry, 'url');
      if (uuid == null || url == null) continue;

      items.add(
        MediaItem(
          uuid: uuid,
          url: url,
          thumbUrl: opt<String>(entry, 'thumbUrl'),
          name: opt<String>(entry, 'name'),
          size: opt<int>(entry, 'size'),
          mime: opt<String>(entry, 'mime'),
        ),
      );
    }

    return MediaSet(items: items);
  }

  @override
  List<Object?> get props => [items];
}
