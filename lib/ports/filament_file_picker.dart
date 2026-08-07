import '../schema/schema_component.dart';

/// Picks a file for [field] on the host's behalf.
///
/// Choosing a file needs a platform plugin, and this package's two runtime
/// dependencies (`flutter`, `equatable`) are a headline feature — so, same
/// escape hatch as `DashboardChartBuilder`, the host supplies this to
/// `ResourceFormScreen` instead of the package picking a plugin for it.
///
/// Returning `null` means the user cancelled; `FileFieldWidget` does nothing
/// in that case, the same as any other cancelled picker.
///
/// Lives in `ports/`, not next to `ResourceFormScreen`, because
/// `form/field_state.dart` needs the type too — a form field built by a
/// host's own [FieldRegistry] entry gets the same picker `ResourceFormScreen`
/// was given.
typedef FilamentFilePicker =
    Future<PickedFile?> Function(SchemaComponent field);

/// What a [FilamentFilePicker] hands back: the raw bytes and the filename to
/// upload them under. One instance is used once, right after it is picked,
/// so it carries no equality of its own.
class PickedFile {
  const PickedFile({required this.bytes, required this.filename});

  final List<int> bytes;
  final String filename;
}
