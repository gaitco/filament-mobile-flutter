import 'package:flutter/material.dart';

import '../data/record_can.dart';
import '../data/resource_record.dart';
import '../data/write_result.dart';
import '../ports/filament_strings.dart';
import '../ports/panel_view_state.dart';
import '../state/resource_view_provider.dart';
import 'entry_registry.dart';
import 'material_panel_state_builder.dart';

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
    super.key,
  });

  final ResourceViewProvider provider;
  final EntryRegistry? registry;
  final PanelBodyBuilder? stateBuilder;
  final FilamentStrings strings;

  /// Called with the loaded record when the edit affordance is tapped. The
  /// screen owns no edit form of its own — same division as the list
  /// screen's `onRecordTap` — so a host that never wires this up gets a
  /// button that renders (once the record permits it) but does nothing on
  /// tap.
  final void Function(ResourceRecord record)? onEditTap;

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
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(widget.provider.resource.labels.singular),
          actions: _actions(),
        ),
        body: builder(context, _state(context)),
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
      ],
    );
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
      if (recordCan(record, 'update'))
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
    ];
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
        _showError(message);
      // A delete request carries nothing to be invalid — this arm exists only
      // because the switch is exhaustive over the sealed type, not because
      // the server can send it here.
      case WriteInvalid():
        _showError(widget.strings.saveFailed);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
