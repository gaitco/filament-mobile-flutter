import 'package:flutter/material.dart';

import '../form/field_registry.dart';
import '../form/field_state.dart';
import '../ports/filament_file_picker.dart';
import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';
import '../schema/schema_component.dart';
import '../state/resource_form_provider.dart';
import 'material_panel_state_builder.dart';

/// One resource's create/edit form.
///
/// A plain widget with no router dependency, like `ResourceListScreen` and
/// `ResourceViewScreen`: the host decides how it is reached and owns the
/// provider.
class ResourceFormScreen extends StatefulWidget {
  const ResourceFormScreen({
    required this.provider,
    this.registry,
    this.stateBuilder,
    this.strings = const FilamentStrings(),
    this.filePicker,
    super.key,
  });

  final ResourceFormProvider provider;
  final FieldRegistry? registry;
  final PanelBodyBuilder? stateBuilder;
  final FilamentStrings strings;

  /// Lets the host wire in whatever file-picker plugin it uses. Null keeps
  /// every file field read-only and rendering
  /// [FilamentStrings.filePickerUnavailable] — see [FilamentFilePicker]'s doc
  /// for why that beats a control the host cannot actually drive.
  final FilamentFilePicker? filePicker;

  @override
  State<ResourceFormScreen> createState() => _ResourceFormScreenState();
}

class _ResourceFormScreenState extends State<ResourceFormScreen> {
  late final FieldRegistry _registry =
      widget.registry ?? FieldRegistry.defaults();

  @override
  void initState() {
    super.initState();
    // Only an untouched provider is loaded — a host-owned provider that has
    // already fetched its form keeps it across a re-mount, mirroring the list
    // and view screens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.provider.status.isInitial) widget.provider.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final builder =
        widget.stateBuilder ?? materialPanelStateBuilder(widget.strings);

    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) => withPanelDirection(
        widget.provider.resource.direction,
        Scaffold(
          appBar: AppBar(title: Text(widget.provider.resource.labels.singular)),
          body: builder(context, _state(context)),
        ),
      ),
    );
  }

  PanelViewState _state(BuildContext context) {
    final provider = widget.provider;

    if (provider.status.isFailure) {
      final message = provider.errorMessage ?? widget.strings.loadFailed;
      // Distinguished so a signed-out user is told they were signed out,
      // not that the server is broken — see PanelUnauthenticated's doc.
      if (provider.isUnauthenticated) {
        return PanelUnauthenticated(message: message, retry: provider.load);
      }
      return PanelFailure(message: message, retry: provider.load);
    }

    // Anything not settled is loading — `initial` included. This is the gate
    // that keeps a `/state` response dispatched against outgoing values from
    // ever landing on a form the user can see: as long as no editable field
    // renders while `status != success`, that response has nothing to
    // corrupt, and the next `/state` (or the user's next edit) corrects it
    // regardless. See Task 10's review note on `ResourceFormProvider`.
    if (!provider.status.isSuccess) return const PanelLoading();

    return PanelData(content: _form(context));
  }

  Widget _form(BuildContext context) {
    final provider = widget.provider;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (provider.formError != null) _banner(context, provider.formError!),
        for (final component in provider.components)
          ..._buildNode(context, component),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('form.submit'),
          // Disabled, not merely re-guarded: `ResourceFormProvider.submit()`
          // already refuses a re-entrant call, but a control that still
          // *looks* tappable while a write is in flight invites exactly the
          // double-tap this guards against.
          onPressed: provider.submitting ? null : () => provider.submit(),
          child: provider.submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.strings.save),
        ),
      ],
    );
  }

  Widget _banner(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  /// A hidden node — leaf field or container alike — renders nothing at all,
  /// never merely a greyed-out control: the same subtree-wide gate
  /// `writableFields` applies to the submission payload, applied here to what
  /// reaches the screen.
  List<Widget> _buildNode(BuildContext context, SchemaComponent component) {
    if (component.hidden) return const [];

    return switch (component) {
      LayoutComponent(:final children) => [
        for (final child in children) ..._buildNode(context, child),
      ],
      UnknownComponent(:final children) => [
        for (final child in children) ..._buildNode(context, child),
      ],
      _ when component.name != null => [_field(context, component)],
      // A component with no name holds no value — an infolist entry reaching
      // a form screen, most likely — and there is nothing to render it as.
      _ => const [],
    };
  }

  Widget _field(BuildContext context, SchemaComponent component) {
    final provider = widget.provider;
    final name = component.name!;

    return Padding(
      key: ValueKey('field.$name'),
      padding: const EdgeInsets.only(bottom: 12),
      child: _registry.build(
        context,
        component,
        FieldState(
          value: provider.values[name],
          onChanged: (value) => provider.change(name, value),
          error: provider.fieldErrors[name],
          // Only a RepeaterComponent looks past its own key, to place a
          // row's own error on that row rather than folding it into one
          // message for the whole field.
          errors: provider.fieldErrors,
          enabled: !component.disabled && component.writable,
          // Only where `/schema` withheld the options. Every other field
          // ignores it, and a host that registers its own builder is free to
          // as well. The per-field variant is what a container's children —
          // a remote select inside a repeater row — query through, bound to
          // the child's own name (see FieldState.searchOptionsFor).
          searchOptions: (query) => provider.searchOptions(name, query),
          searchOptionsFor: (field, query) =>
              provider.searchOptions(field, query),
          // File-only, same story: every other field ignores both.
          filePicker: widget.filePicker,
          uploadFile: ({required bytes, required filename}) =>
              provider.uploadFile(name, bytes: bytes, filename: filename),
          strings: widget.strings,
        ),
      ),
    );
  }
}
