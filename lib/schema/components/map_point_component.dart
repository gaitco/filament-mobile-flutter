part of '../schema_component.dart';

/// One geographic point. Numeric strings are accepted because the upstream
/// Filament plugin documents and stores that shape; the mobile client always
/// exposes numbers and sends numbers back.
final class MapPointValue extends Equatable {
  const MapPointValue({required this.lat, required this.lng});

  factory MapPointValue.fromJson(Object? value, String path) {
    if (value is! Map) {
      throw SchemaFormatException(path, 'expected a map point object');
    }

    final lat = _pointNumber(value['lat']);
    final lng = _pointNumber(value['lng']);
    if (lat == null || lng == null) {
      throw SchemaFormatException(
        path,
        'map point must contain numeric lat and lng',
      );
    }

    return MapPointValue(lat: lat, lng: lng);
  }

  final double lat;
  final double lng;

  Map<String, double> toJson() => {'lat': lat, 'lng': lng};

  @override
  List<Object?> get props => [lat, lng];
}

double? _pointNumber(Object? value) => switch (value) {
  num() => value.toDouble(),
  String() => double.tryParse(value),
  _ => null,
};

/// `map_point` and read-only `map_point_entry` share one value/camera model.
/// Rendering is intentionally supplied by the optional maps companion.
final class MapPointComponent extends SchemaComponent {
  MapPointComponent._({
    required _CommonProperties common,
    required this.draggable,
    required this.clickable,
    required this.showMarker,
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.tilesUrl,
    required this.attribution,
    required this.defaultValue,
  }) : super._common(common);

  factory MapPointComponent._fromJson(
    Map<String, dynamic> json,
    _CommonProperties common,
    String path,
  ) {
    final config = opt<Map<String, dynamic>>(json, 'config') ?? const {};
    final rawDefault = config['default'] ?? json['default'];

    return MapPointComponent._(
      common: common,
      draggable: config['draggable'] is bool
          ? config['draggable'] as bool
          : true,
      clickable: config['clickable'] is bool
          ? config['clickable'] as bool
          : false,
      showMarker: config['showMarker'] is bool
          ? config['showMarker'] as bool
          : true,
      zoom: _pointNumber(config['zoom']) ?? 15,
      minZoom: _pointNumber(config['minZoom']) ?? 1,
      maxZoom: _pointNumber(config['maxZoom']) ?? 28,
      tilesUrl: config['tilesUrl'] is String
          ? config['tilesUrl'] as String
          : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      attribution: config['attribution'] is String
          ? config['attribution'] as String
          : null,
      defaultValue: rawDefault == null
          ? null
          : MapPointValue.fromJson(rawDefault, '$path.config.default'),
    );
  }

  final bool draggable;
  final bool clickable;
  final bool showMarker;
  final double zoom;
  final double minZoom;
  final double maxZoom;
  final String tilesUrl;
  final String? attribution;
  final MapPointValue? defaultValue;

  bool get isEntry => type == 'map_point_entry';
}
