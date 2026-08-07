import 'dart:async';

import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/schema/relation_descriptor.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/resource_labels.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:filament_mobile/schema/schema_component.dart';
import 'package:filament_mobile/state/resource_form_provider.dart';

/// A source with one settable answer per endpoint, plus a hold/complete pair
/// so a test can resolve an earlier `/state` call *after* a later one and
/// exercise the sequencing guard.
///
/// Shared between `resource_form_provider_test.dart` and
/// `resource_form_screen_test.dart` — both drive the same provider through the
/// same fake, and a second hand-copied fixture would drift the moment one of
/// them changed.
class FakeSource implements ResourceDataSource {
  FakeSource({
    required this.components,
    List<SchemaComponent>? stateResponse,
    this.stateError,
    this.optionsError,
    this.optionsResponse = const OptionsPage.empty(),
    this.writeResult = const WriteSuccess({}),
    ResourceRecord? record,
    this.recordError,
    this.uploadResult = const UploadFailed('upload not configured'),
  }) : stateResponse = stateResponse ?? components,
       nextRecord =
           record ??
           const ResourceRecord(id: 7, attributes: {'name': 'Stored'});

  final List<SchemaComponent> components;
  final List<SchemaComponent> stateResponse;
  final Object? stateError;
  final Object? optionsError;
  final OptionsPage optionsResponse;

  int optionsCalls = 0;
  String? lastOptionsQuery;
  Map<String, dynamic> lastOptionsValues = const {};

  bool _holdNextOptions = false;
  Completer<OptionsPage>? _heldOptions;

  /// Makes the next options fetch hang, so a test can resolve two out of order.
  void holdNextOptions() => _holdNextOptions = true;

  void completeHeldOptions(OptionsPage page) => _heldOptions?.complete(page);

  @override
  Future<OptionsPage> options(
    String resourceKey, {
    required String field,
    Object? recordId,
    required Map<String, dynamic> values,
    required String query,
  }) {
    optionsCalls++;
    lastOptionsQuery = query;
    lastOptionsValues = values;

    if (_holdNextOptions) {
      _holdNextOptions = false;
      return (_heldOptions = Completer<OptionsPage>()).future;
    }
    if (optionsError != null) return Future.error(optionsError!);
    return Future.value(optionsResponse);
  }

  final WriteResult writeResult;
  final Object? recordError;
  ResourceRecord nextRecord;

  int stateCalls = 0;
  int writeCalls = 0;
  String? lastWrite;
  Map<String, dynamic>? lastPayload;
  Map<String, dynamic>? lastStateValues;

  bool _holdNext = false;
  Completer<List<SchemaComponent>>? _held;
  bool _holdNextRecord = false;
  Completer<ResourceRecord>? _heldRecord;
  bool _holdNextWrite = false;
  Completer<WriteResult>? _heldWrite;

  void holdNextState() => _holdNext = true;

  void completeHeldState(List<SchemaComponent> components) =>
      _held!.complete(components);

  void holdNextRecord() => _holdNextRecord = true;

  void completeHeldRecord() => _heldRecord!.complete(nextRecord);

  /// Holds the *next* create/update so a test can assert on the submitting
  /// window itself — the one thing an instantly-resolving `Future.value()`
  /// cannot exercise, since it can resolve before a second tap even lands.
  void holdNextWrite() => _holdNextWrite = true;

  void completeHeldWrite() => _heldWrite!.complete(writeResult);

  @override
  Future<List<SchemaComponent>> state(
    String resourceKey, {
    Object? recordId,
    required Map<String, dynamic> values,
    required String changed,
  }) {
    stateCalls++;
    lastStateValues = values;

    if (_holdNext) {
      _holdNext = false;
      return (_held = Completer<List<SchemaComponent>>()).future;
    }
    if (stateError != null) return Future.error(stateError!);
    return Future.value(stateResponse);
  }

  @override
  Future<WriteResult> create(String resourceKey, Map<String, dynamic> values) {
    writeCalls++;
    lastWrite = 'create';
    lastPayload = values;
    if (_holdNextWrite) {
      _holdNextWrite = false;
      return (_heldWrite = Completer<WriteResult>()).future;
    }
    return Future.value(writeResult);
  }

  @override
  Future<WriteResult> update(
    String resourceKey,
    Object id,
    Map<String, dynamic> values,
  ) {
    writeCalls++;
    lastWrite = 'update';
    lastPayload = values;
    if (_holdNextWrite) {
      _holdNextWrite = false;
      return (_heldWrite = Completer<WriteResult>()).future;
    }
    return Future.value(writeResult);
  }

  @override
  Future<ResourceRecord> record(String resourceKey, Object id) {
    if (recordError != null) return Future.error(recordError!);

    if (_holdNextRecord) {
      _holdNextRecord = false;
      return (_heldRecord = Completer<ResourceRecord>()).future;
    }
    return Future.value(nextRecord);
  }

  @override
  Future<PanelSchema> panel() async => throw UnimplementedError();

  @override
  Future<PanelSchema?> cachedPanel() async => null;

  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
  }) async => throw UnimplementedError();

  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async => throw UnimplementedError();

  @override
  Future<WriteResult> destroy(String resourceKey, Object id) =>
      throw UnimplementedError();

  @override
  Future<ActionResult> runAction(
    String resourceKey,
    Object id,
    String action,
  ) => throw UnimplementedError();

  @override
  Future<DashboardData> dashboard() => throw UnimplementedError();

  final UploadResult uploadResult;

  int uploadCalls = 0;
  String? lastUploadField;
  List<int>? lastUploadBytes;
  String? lastUploadFilename;

  bool _holdNextUpload = false;
  Completer<UploadResult>? _heldUpload;

  /// Holds the *next* upload so a test can assert on the in-flight window —
  /// the same reason [holdNextWrite] exists: a `Future.value()` can resolve
  /// before a second tap even lands.
  void holdNextUpload() => _holdNextUpload = true;

  void completeHeldUpload() => _heldUpload!.complete(uploadResult);

  @override
  Future<UploadResult> uploadFile(
    String resourceKey,
    String field, {
    required List<int> bytes,
    required String filename,
  }) {
    uploadCalls++;
    lastUploadField = field;
    lastUploadBytes = bytes;
    lastUploadFilename = filename;

    if (_holdNextUpload) {
      _holdNextUpload = false;
      return (_heldUpload = Completer<UploadResult>()).future;
    }
    return Future.value(uploadResult);
  }
}

/// Three flat fields — `name`, `country_id`, `city_id` — parsed through the
/// real [SchemaComponent.fromJson] so a fixture can never drift from what the
/// wire actually produces.
///
/// [reveal] writes `hidden: false` explicitly. That matches the default, so it
/// changes no bytes; it is there because a `/state` response that reveals a
/// field is what the server really sends, and the test it appears in
/// discriminates on whether the provider *applies* that response at all.
List<SchemaComponent> formWith({
  String? live,
  String? hidden,
  String? reveal,
  String? required,
  String? label,
}) {
  Map<String, dynamic> node(String name, String type, String defaultLabel) => {
    'type': type,
    'name': name,
    'label': name == 'name' && label != null ? label : defaultLabel,
    if (live == name) 'live': true,
    if (hidden == name) 'hidden': true,
    if (reveal == name) 'hidden': false,
    if (required == name) 'rules': {'required': true},
    if (type == 'select')
      'config': {
        'options': [
          {'value': 1, 'label': 'One'},
          {'value': 3, 'label': 'Three'},
        ],
      },
  };

  final nodes = [
    node('name', 'text', 'Name'),
    node('country_id', 'select', 'Country'),
    node('city_id', 'select', 'City'),
  ];

  return List.generate(
    nodes.length,
    (index) => SchemaComponent.fromJson(nodes[index], 'form[$index]'),
  );
}

/// One `file` field, read-only unless [readOnly] says otherwise — mirrors
/// [FileComponent]'s own default so a fixture that forgets to set it fails
/// the same way an older server response would. [disabled] is a *host* or
/// closure-driven gate (`->disabled(...)`, a disabled ancestor `Section`) —
/// deliberately independent of [readOnly], which is the server's own file
/// rule: the two must be testable apart, since neither can substitute for
/// the other. Shared between `file_upload_field_test.dart` (widget level)
/// and `resource_form_provider_test.dart` (provider level) so the field's
/// shape can't drift between the two.
List<SchemaComponent> fileForm({
  bool readOnly = false,
  bool disabled = false,
}) => [
  SchemaComponent.fromJson({
    'type': 'file',
    'name': 'photo',
    'label': 'Photo',
    'disabled': disabled,
    'config': {'readOnly': readOnly},
  }, 'form[0]'),
];

SchemaComponent? findComponent(List<SchemaComponent> components, String name) {
  for (final component in components) {
    if (component.name == name) return component;
  }
  return null;
}

ResourceSchema schemaFor(List<SchemaComponent> form) => ResourceSchema(
  key: 'banners',
  labels: const ResourceLabels(singular: 'Banner', plural: 'Banners'),
  form: form,
);

ResourceFormProvider providerFor(FakeSource source, {Object? recordId}) =>
    ResourceFormProvider(
      source: source,
      resource: schemaFor(source.components),
      strings: const FilamentStrings(),
      recordId: recordId,
    );

/// An editable repeater whose item template holds a scalar child and a NESTED
/// repeater — the shape the server publishes as `outer readOnly: false`,
/// `inner readOnly: true` (verified against the real `SchemaWalker`). Parsed
/// through [SchemaComponent.fromJson] like every other fixture here, so it
/// cannot drift from what the wire produces.
List<SchemaComponent> nestedRepeaterForm() => [
  SchemaComponent.fromJson({
    'type': 'repeater',
    'name': 'outer_rows',
    'label': 'Outer rows',
    'config': {'addable': true, 'deletable': true, 'readOnly': false},
    'children': [
      {'type': 'text', 'name': 'note', 'label': 'Note'},
      {
        'type': 'repeater',
        'name': 'inner_rows',
        'label': 'Inner rows',
        'config': {'addable': true, 'deletable': true, 'readOnly': true},
        'children': [
          {'type': 'text', 'name': 'x', 'label': 'X'},
        ],
      },
    ],
  }, 'test'),
];
