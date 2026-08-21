import 'package:flutter/material.dart';

import '../form/field_registry.dart';
import '../form/field_state.dart';
import '../ports/filament_file_picker.dart';
import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';
import '../schema/schema_component.dart';
import '../state/resource_form_provider.dart';
import 'layout.dart';
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
    this.maxContentWidth,
    this.onSaved,
    super.key,
  });

  final ResourceFormProvider provider;
  final FieldRegistry? registry;
  final PanelBodyBuilder? stateBuilder;
  final FilamentStrings strings;

  /// Called after a successful save INSTEAD of popping the route (the toast
  /// still shows). `PanelShell`'s detail pane wires this to swap back to the
  /// view; absent, the form pops as it always has (P23).
  final VoidCallback? onSaved;

  /// Lets the host wire in whatever file-picker plugin it uses. Null keeps
  /// every file field read-only and rendering
  /// [FilamentStrings.filePickerUnavailable] — see [FilamentFilePicker]'s doc
  /// for why that beats a control the host cannot actually drive.
  final FilamentFilePicker? filePicker;

  /// Maximum width for the form content. Null uses a default based on the
  /// current layout (720 when not compact, unconstrained when compact).
  final double? maxContentWidth;

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

    final listView = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (provider.formError != null) _banner(context, provider.formError!),
        ..._buildSiblings(context, provider.components),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('form.submit'),
          // Disabled, not merely re-guarded: `ResourceFormProvider.submit()`
          // already refuses a re-entrant call, but a control that still
          // *looks* tappable while a write is in flight invites exactly the
          // double-tap this guards against.
          onPressed: provider.submitting ? null : () => _submit(context),
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

    final maxWidth =
        widget.maxContentWidth ??
        (FilamentLayout.isCompact(context) ? null : 720.0);

    if (maxWidth == null) return listView;

    return Center(
      child: ConstrainedBox(
        key: const ValueKey('resource-form-constrained-content'),
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: listView,
      ),
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

  /// Builds one container's worth of children, in order. A hidden node —
  /// leaf field or container alike — renders nothing at all, never merely a
  /// greyed-out control: the same subtree-wide gate `writableFields` applies
  /// to the submission payload, applied here to what reaches the screen.
  ///
  /// Grouping is scoped to THIS list: `translatable` leaves sharing a
  /// head-of-name are siblings in the same form/section/grid the server
  /// declared them in, so the pre-pass below only ever looks within one
  /// recursive call, never across a container boundary.
  /// Save, then leave: the web panel redirects after a successful write and
  /// the phone's equivalent is popping back to wherever the form was pushed
  /// from, with a toast as the confirmation the redirect target would have
  /// shown. The toast goes through the ROOT messenger so it survives the pop
  /// (the form's own Scaffold is gone by the time it would render). A failed
  /// save stays put — the banner and field errors are the whole point of
  /// staying. A form that is not inside a Navigator (a host embedding it)
  /// still saves; it just has nowhere to go.
  Future<void> _submit(BuildContext context) async {
    final saved = await widget.provider.submit();
    if (!saved || !context.mounted) return;

    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(widget.strings.saved)));
    if (widget.onSaved case final onSaved?) {
      onSaved();
      return;
    }
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) navigator.pop();
  }

  List<Widget> _buildSiblings(
    BuildContext context,
    List<SchemaComponent> components,
  ) {
    final groups = _translatableGroups(components);
    final rendered = <String>{};
    final widgets = <Widget>[];

    for (final component in components) {
      if (component.hidden) continue;

      switch (component) {
        case LayoutComponent(:final children):
          widgets.addAll(_buildSiblings(context, children));
        case UnknownComponent(:final children):
          widgets.addAll(_buildSiblings(context, children));
        case _ when component.name != null:
          final head = component.translatable
              ? _translatableHead(component.name!)
              : null;
          final members = head == null ? null : groups[head];
          // A group of one member renders chipless, exactly like a plain
          // field — the chip row only earns its place once there is
          // something to switch between.
          if (members != null && members.length > 1) {
            if (rendered.add(head!)) {
              widgets.add(_translatableGroup(context, head, members));
            }
          } else {
            widgets.add(_field(context, component));
          }
        // A component with no name holds no value — an infolist entry
        // reaching a form screen, most likely — and there is nothing to
        // render it as.
        default:
          break;
      }
    }

    return widgets;
  }

  /// Maps head-of-name (`caption`) to its members (`caption.ar`,
  /// `caption.en`), among the leaves in [components] that are `translatable`
  /// — never guessed at from a dotted name alone, since a non-translatable
  /// dotted field (or a scalar sibling) must render exactly as it does
  /// today.
  Map<String, List<SchemaComponent>> _translatableGroups(
    List<SchemaComponent> components,
  ) {
    final groups = <String, List<SchemaComponent>>{};
    for (final component in components) {
      if (component.hidden || !component.translatable) continue;
      final name = component.name;
      if (name == null) continue;
      final head = _translatableHead(name);
      if (head == null) continue;
      groups.putIfAbsent(head, () => []).add(component);
    }
    return groups;
  }

  /// The name split at the LAST dot — the server publishes no second copy
  /// of the attribute/locale split, so the client derives both halves from
  /// the name it already has. Null for a name with no dot, which the
  /// contract never actually sends alongside `translatable: true`.
  String? _translatableHead(String name) {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? null : name.substring(0, dot);
  }

  /// One translatable attribute, rendered as a single field slot with a
  /// locale-chip row above it. Every member stays a real field underneath —
  /// [_field] is reused unmodified — so [FormValues] and the submission
  /// payload carry every locale regardless of which chip is showing; see
  /// the class-level non-goals on why that must never change.
  Widget _translatableGroup(
    BuildContext context,
    String head,
    List<SchemaComponent> members,
  ) {
    final provider = widget.provider;
    final ordered = _orderByLocale(members, provider.resource.locales);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _LocaleChipGroup(
        key: ValueKey('group.$head'),
        head: head,
        label: _humanize(head),
        members: ordered,
        fieldBuilder: _field,
        errorFor: (name) => provider.fieldErrors[name],
      ),
    );
  }

  /// `panel.locales` orders the chips when non-empty; a locale it does not
  /// mention keeps its original position, appended after every locale it
  /// does — appearance order, unchanged.
  List<SchemaComponent> _orderByLocale(
    List<SchemaComponent> members,
    List<String> locales,
  ) {
    if (locales.isEmpty) return members;

    final ordered = <SchemaComponent>[];
    for (final locale in locales) {
      for (final member in members) {
        if (_localeOf(member) == locale) ordered.add(member);
      }
    }
    for (final member in members) {
      if (!ordered.contains(member)) ordered.add(member);
    }
    return ordered;
  }

  /// Group label = the humanized head attribute — what the scalar would be
  /// called, replacing the per-locale "Ar"/"En" labels the member fields
  /// carry today. No `intl` dependency: this only title-cases the
  /// underscore-separated attribute name the server already sends.
  String _humanize(String head) {
    final words = head.split(RegExp('[._]')).where((word) => word.isNotEmpty);
    return words
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
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
          media: provider.mediaFor(name),
          strings: widget.strings,
        ),
      ),
    );
  }
}

/// The locale half of a translatable leaf's name — everything after the
/// LAST dot. Shared between the state's own ordering pass and
/// [_LocaleChipGroupState], which needs it to label each chip.
String _localeOf(SchemaComponent component) {
  final name = component.name!;
  return name.substring(name.lastIndexOf('.') + 1);
}

/// One translatable attribute's field slot: a row of locale chips above
/// whichever member is currently selected. Selection is presentation-only —
/// it decides which already-wired [_field] renders, never what
/// [ResourceFormProvider] holds or submits.
class _LocaleChipGroup extends StatefulWidget {
  const _LocaleChipGroup({
    required this.head,
    required this.label,
    required this.members,
    required this.fieldBuilder,
    required this.errorFor,
    super.key,
  });

  final String head;
  final String label;

  /// Already ordered by the caller (`panel.locales`, else appearance).
  final List<SchemaComponent> members;
  final Widget Function(BuildContext, SchemaComponent) fieldBuilder;
  final String? Function(String name) errorFor;

  @override
  State<_LocaleChipGroup> createState() => _LocaleChipGroupState();
}

class _LocaleChipGroupState extends State<_LocaleChipGroup> {
  int _selected = 0;

  /// The member names that carried an error the last time [_syncSelectionToError]
  /// ran, joined into one comparable value; `null` before the first sync.
  /// This whole widget rebuilds on every keystroke anywhere in the form (one
  /// `ChangeNotifier` for the whole screen), not just an edit to one of THESE
  /// members, so without this the force-switch below would reapply on every
  /// unrelated rebuild instead of once per genuinely new error.
  String? _lastSyncedErrorSignature;

  @override
  void initState() {
    super.initState();
    _syncSelectionToError();
  }

  @override
  void didUpdateWidget(covariant _LocaleChipGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected >= widget.members.length) _selected = 0;
    _syncSelectionToError();
  }

  /// An error keyed to a member that is not the visible one force-switches
  /// the chip to it — the web plugin's own rule, because an error hiding
  /// behind a chip is a save the user cannot see how to fix. Mutates the
  /// field directly rather than through `setState`: both call sites
  /// ([initState], [didUpdateWidget]) run before this frame's [build], so
  /// the plain assignment is already picked up without an extra rebuild.
  ///
  /// Guarded twice over against this widget's own rebuild churn, which fires
  /// far more often than the error set actually changes:
  ///
  ///  - it bails immediately when the error signature is unchanged since the
  ///    last sync, so a user's deliberate tap to a clean chip survives every
  ///    later rebuild while some OTHER member's error sits there untouched —
  ///    the force-switch is a one-time reveal of a NEW error, not a standing
  ///    rule reapplied every frame;
  ///  - when the signature HAS changed, it still leaves the selection alone
  ///    if the currently visible member already carries an error itself:
  ///    that error is already on screen, nothing hidden needs revealing, and
  ///    with two members erroring at once this is what stops them fighting
  ///    over the chip instead of settling on whichever was visible first.
  void _syncSelectionToError() {
    final signature = _errorSignature();
    if (signature == _lastSyncedErrorSignature) return;
    _lastSyncedErrorSignature = signature;

    final visible = widget.members[_selected].name;
    if (visible != null && widget.errorFor(visible) != null) return;

    for (var index = 0; index < widget.members.length; index++) {
      if (index == _selected) continue;
      final name = widget.members[index].name;
      if (name != null && widget.errorFor(name) != null) {
        _selected = index;
        return;
      }
    }
  }

  /// Which members currently carry an error, in member order — the value
  /// [_syncSelectionToError] compares against its last run. Names alone are
  /// enough signal: two different error MESSAGES on the same name are still
  /// just "this member has an error", which is all a force-switch cares
  /// about. Joined on a NUL character, which a field name can never
  /// contain, unlike a comma or dot either of which one legitimately could.
  String _errorSignature() => [
    for (final member in widget.members)
      if (member.name != null && widget.errorFor(member.name!) != null)
        member.name,
  ].join('\u0000');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (var index = 0; index < widget.members.length; index++)
              ChoiceChip(
                key: ValueKey(
                  'locale-chip.${widget.head}.'
                  '${_localeOf(widget.members[index])}',
                ),
                label: Text(_localeOf(widget.members[index]).toUpperCase()),
                selected: index == _selected,
                onSelected: (_) => setState(() => _selected = index),
              ),
          ],
        ),
        const SizedBox(height: 8),
        widget.fieldBuilder(context, widget.members[_selected]),
      ],
    );
  }
}
