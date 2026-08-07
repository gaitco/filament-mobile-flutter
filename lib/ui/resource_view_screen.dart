import 'package:flutter/material.dart';

import '../data/action_result.dart';
import '../data/record_action.dart';
import '../data/record_can.dart';
import '../data/resource_record.dart';
import '../data/write_result.dart';
import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';
import '../schema/relation_descriptor.dart';
import '../state/resource_view_provider.dart';
import 'entry_registry.dart';
import 'material_panel_state_builder.dart';
import 'relation_section_widget.dart';
import 'semantic_badge.dart';

/// One record's infolist.
///
/// A plain widget with no router dependency, like `ResourceListScreen`: the
/// host decides how it is reached.
class ResourceViewScreen extends StatefulWidget {
  const ResourceViewScreen({
    required this.provider,
    this.registry,
    this.stateBuilder,
    this.strings = const FilamentStrings(),
    this.onEditTap,
    this.onSeeAllTap,
    super.key,
  });

  final ResourceViewProvider provider;
  final EntryRegistry? registry;
  final PanelBodyBuilder? stateBuilder;
  final FilamentStrings strings;

  /// Called with the loaded record when the edit affordance is tapped. The
  /// screen owns no edit form of its own — same division as the list
  /// screen's `onRecordTap` — so a host that never wires this up gets no
  /// edit button at all, never one that renders and silently no-ops on tap.
  final void Function(ResourceRecord record)? onEditTap;

  /// Forwarded to every `RelationSectionWidget`'s `onSeeAllTap` — see that
  /// widget's doc. Task 8 builds the screen this opens.
  final void Function(RelationDescriptor relation, Object recordId)?
  onSeeAllTap;

  @override
  State<ResourceViewScreen> createState() => _ResourceViewScreenState();
}

class _ResourceViewScreenState extends State<ResourceViewScreen> {
  late final EntryRegistry _registry =
      widget.registry ?? EntryRegistry.defaults();

  @override
  void initState() {
    super.initState();
    // Only an untouched provider is loaded — a host-owned provider that has
    // already fetched its record keeps it across a re-mount.
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
          appBar: AppBar(
            title: Text(widget.provider.resource.labels.singular),
            actions: _actions(),
          ),
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

    // Anything not settled is loading — `initial` included. The first frame
    // runs before the post-frame load(), and treating that frame as anything
    // else flashes an empty screen the user never asked for.
    if (!provider.status.isSuccess) return const PanelLoading();

    final record = provider.record;
    if (record == null || provider.resource.infolist.isEmpty) {
      return PanelEmpty(message: widget.strings.empty);
    }

    return PanelData(content: _infolist(context, record));
  }

  /// No pull-to-refresh. `load()` swaps the whole body — the RefreshIndicator
  /// included — for a spinner, so the gesture would yank its own indicator out
  /// mid-pull. The list screen has the same problem (its `refresh()` also
  /// clears the records and flips to a skeleton), but there the gesture at
  /// least lands on a list-shaped body, and a list is where a user reaches for
  /// the gesture at all. Refreshing in place needs the provider to hold the
  /// old record while reloading, which is a P2 concern, not a brief
  /// requirement.
  Widget _infolist(BuildContext context, ResourceRecord record) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final component in widget.provider.resource.infolist)
          _registry.build(context, component, record),
        ..._relationSections(record),
      ],
    );
  }

  /// One section per relation the server published for this resource — see
  /// `RelationDescriptor`. Always rendered when the resource carries one: a
  /// published relation needs nothing wired to appear, the same read path
  /// `_infolist` above already uses for the record itself.
  List<Widget> _relationSections(ResourceRecord record) {
    return [
      for (final relation in widget.provider.resource.relations)
        RelationSectionWidget(
          key: ValueKey('relation.${relation.key}'),
          relation: relation,
          recordId: record.id,
          fetch: ({int page = 1}) =>
              widget.provider.loadRelation(relation, page: page),
          strings: widget.strings,
          onSeeAllTap: widget.onSeeAllTap,
        ),
    ];
  }

  /// The edit and delete affordances, both gated on the **record**'s
  /// permissions.
  ///
  /// `recordCan(record, ability)`, never `resource.permissions.*`: the
  /// resource block is a capability ("this resource supports updates/deletion"),
  /// the record block is an authorization ("you may do this to THIS record").
  /// Under an ownership policy they disagree for every record the user does
  /// not own, and reading the resource block here would show a button on
  /// records the server will refuse to act on.
  List<Widget> _actions() {
    final record = widget.provider.record;
    if (record == null) return const [];

    return [
      // `onEditTap != null` is part of the gate, not just the handler: a
      // host that never wired it must get no button, never one that renders
      // enabled and silently no-ops on tap.
      if (recordCan(record, 'update') && widget.onEditTap != null)
        IconButton(
          key: const ValueKey('record.edit'),
          icon: const Icon(Icons.edit_outlined),
          tooltip: widget.strings.edit,
          onPressed: () => widget.onEditTap?.call(record),
        ),
      if (recordCan(record, 'delete'))
        IconButton(
          key: const ValueKey('record.delete'),
          icon: const Icon(Icons.delete_outline),
          tooltip: widget.strings.deleteConfirm,
          onPressed: _confirmDelete,
        ),
      // Published, not resolved here: the server already filtered these to
      // what this record may run, the same division as `recordCan` above.
      for (final action in record.actions)
        TextButton(
          key: ValueKey('record.action.${action.name}'),
          style: TextButton.styleFrom(
            foregroundColor: SemanticBadge.colorFor(action.color),
          ),
          onPressed: () => _runAction(action),
          child: Text(action.label),
        ),
    ];
  }

  Future<void> _confirmDelete() async {
    // NOT `Directionality.of(context)` — this `State`'s own `context` is an
    // ANCESTOR of the `Directionality` `build()` wraps around the
    // `Scaffold`, not a descendant of it; see `textDirectionOf`'s doc
    // (`material_panel_state_builder.dart`). Resolved from the schema value
    // directly instead.
    final direction = textDirectionOf(widget.provider.resource.direction);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: direction,
        child: AlertDialog(
          title: Text(widget.strings.deleteConfirmTitle),
          content: Text(widget.strings.deleteConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(widget.strings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(widget.strings.deleteConfirm),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await widget.provider.delete();
    if (!mounted) return;

    switch (result) {
      // A 404 means someone else already deleted it — the record is gone
      // either way, which is the same outcome as deleting it ourselves.
      case WriteSuccess() || WriteGone():
        Navigator.pop(context, true);
      case WriteDenied(:final message) || WriteFailed(:final message):
        _showMessage(message);
      // A delete request carries nothing to be invalid — this arm exists only
      // because the switch is exhaustive over the sealed type, not because
      // the server can send it here.
      case WriteInvalid():
        _showMessage(widget.strings.saveFailed);
    }
  }

  /// Runs [action], asking first when it carries a confirmation.
  ///
  /// Confirmation copy is the action's OWN words, not the package's generic
  /// delete strings — an empty `submit`/`cancel` (the server's fail-closed
  /// shape, see [RecordActionConfirmation]) substitutes the client's own
  /// label, it never means "skip the prompt": [confirmation] being non-null
  /// already decided that.
  Future<void> _runAction(RecordAction action) async {
    final confirmation = action.confirmation;

    if (confirmation != null) {
      // See `_confirmDelete`'s doc — same reason, not `Directionality.of`.
      final direction = textDirectionOf(widget.provider.resource.direction);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Directionality(
          textDirection: direction,
          child: AlertDialog(
            title: Text(confirmation.heading),
            content: confirmation.description == null
                ? null
                : Text(confirmation.description!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  confirmation.cancel.isEmpty
                      ? widget.strings.cancel
                      : confirmation.cancel,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  confirmation.submit.isEmpty
                      ? widget.strings.actionConfirm
                      : confirmation.submit,
                ),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true || !mounted) return;
    }

    final result = await widget.provider.runAction(action);
    if (!mounted) return;

    // The server's own message wins whenever it sent one — it is translated
    // and specific; the package's default is neither.
    //
    // A NULL message on success shows nothing, deliberately. Filament sends a
    // notification only when the action declared a title
    // (`CanNotify::sendSuccessNotification()` guards on `filled($title)`), so
    // an action without one is silent on the web panel, and a `Cancel` — which
    // reaches here as a 200 with no message — is silent there too. Inventing a
    // confirmation the panel never wrote would have the phone claim an outcome
    // the web does not. The re-fetch is the feedback: the record on screen
    // changes under the user.
    //
    // A null FAILURE still falls back, and the asymmetry is Filament's own:
    // it marks failure notifications `->persistent()` and success ones not. A
    // silent failure on the web still leaves a page the user can read; on a
    // phone, a tap that produces nothing at all cannot be told apart from a
    // dead button.
    final message = switch (result) {
      ActionSuccess(:final message) => message,
      ActionFailed(:final message) => message ?? widget.strings.actionFailed,
    };

    if (message != null) _showMessage(message);
  }

  void _showMessage(String message) {
    // No `Directionality` wrap here, unlike the dialogs above, and measured
    // rather than assumed: a `SnackBar` is NOT an overlay route. The
    // `ScaffoldMessenger` hands it to the nearest registered `Scaffold`,
    // which renders it inside its own stack — below the `withPanelDirection`
    // wrap `build()` puts around that `Scaffold`. It inherits the panel's
    // direction on its own.
    //
    // The whole-branch review listed a wrap here as unpinned wiring; it was
    // in fact dead code — deleting it changed nothing measurable, because
    // nothing was broken to begin with. `rtl_layout_test.dart` asserts the
    // rendered snack bar's resolved direction directly, so if this ever
    // stops being true (a snack bar promoted to a route, or the wrap moved
    // above the `Scaffold`) the test says so.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
