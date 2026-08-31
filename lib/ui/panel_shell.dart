import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/resource_data_source.dart';
import '../form/field_registry.dart';
import '../ports/filament_file_picker.dart';
import '../ports/filament_event_transport.dart';
import '../ports/filament_strings.dart';
import '../schema/resource_schema.dart';
import '../state/dashboard_provider.dart';
import '../state/panel_provider.dart';
import '../state/relation_list_provider.dart';
import '../state/resource_form_provider.dart';
import '../state/resource_list_provider.dart';
import '../state/resource_view_provider.dart';
import 'dashboard_screen.dart';
import 'entry_registry.dart';
import 'layout.dart';
import 'material_panel_state_builder.dart';
import 'relation_list_screen.dart';
import 'resource_form_screen.dart';
import 'resource_list_screen.dart';
import 'resource_row.dart';
import 'resource_view_screen.dart';
import 'widget_slots.dart';

/// What the expanded detail pane shows for the selected record.
enum _Pane { empty, view, form, create }

/// One UI language the host can switch to (P22): the tag the host's own
/// wiring understands (`'en'`, `'ar'`, whatever the host chose) and the
/// label shown for it in the picker.
///
/// The label is deliberately host-supplied and never translated by this
/// package — a language names itself in its own script ("العربية", not
/// "Arabic"), so it reads the same whichever language is currently active.
class FilamentLanguageOption {
  const FilamentLanguageOption(this.tag, this.label);

  final String tag;
  final String label;
}

/// The one-widget panel: sidebar/rail/drawer, master list and detail pane,
/// laid out by form factor (P23).
///
/// - **compact:** a `Scaffold` with the resources in a drawer and a nested
///   `Navigator` pushing list → view → form, exactly the wiring the example
///   host used to do by hand.
/// - **medium:** a `NavigationRail` in place of the drawer; same single pane.
/// - **expanded:** sidebar | master list (row style, selection highlighted)
///   | detail pane with its own nested `Navigator`, so relation flows push
///   inside the pane and never lose the list.
///
/// All three read one state — the selected resource and record — so a
/// window crossing a breakpoint keeps what the user was looking at.
class PanelShell extends StatefulWidget {
  const PanelShell({
    required this.source,
    required this.panelProvider,
    this.strings = const FilamentStrings(),
    this.registry,
    this.fieldRegistry,
    this.widgetRegistry,
    this.eventTransport,
    this.filePicker,
    this.chartBuilder,
    this.iconFor,
    this.onLogout,
    this.languages = const [],
    this.activeLanguage,
    this.onLanguageSelected,
    this.onLinkTap,
    this.breakpoints = const FilamentBreakpoints(),
    super.key,
  });

  final ResourceDataSource source;
  final PanelProvider panelProvider;
  final FilamentStrings strings;

  /// Null builds `EntryRegistry.defaults` with [onLinkTap] and a related-
  /// record tap that opens the target record in the current pane.
  final EntryRegistry? registry;
  final FieldRegistry? fieldRegistry;

  /// Application-owned widgets forwarded to every package-owned screen.
  final FilamentWidgetRegistry? widgetRegistry;
  final FilamentEventTransport? eventTransport;
  final FilamentFilePicker? filePicker;
  final DashboardChartBuilder? chartBuilder;

  /// Sidebar icon per resource — the contract carries none. Null → folder.
  final IconData Function(ResourceSchema resource)? iconFor;

  /// Adds a profile menu with a log-out item to the dashboard's AppBar.
  final VoidCallback? onLogout;

  /// The UI languages the profile menu offers (P22). Entries render only
  /// when there are at least two — one language is nothing to switch to —
  /// and [onLanguageSelected] is wired; either alone draws nothing.
  final List<FilamentLanguageOption> languages;

  /// The tag of the currently active language, marked with a check in the
  /// menu. Compared to [FilamentLanguageOption.tag] exactly — the host owns
  /// both sides of the comparison.
  final String? activeLanguage;

  /// Called with the chosen [FilamentLanguageOption.tag]. Everything after
  /// the tap is the host's: swap [strings], persist the choice, rebuild.
  /// The shell holds no language state of its own — [activeLanguage] is the
  /// host's word, not an echo of the last tap.
  final ValueChanged<String>? onLanguageSelected;

  final void Function(String href)? onLinkTap;
  final FilamentBreakpoints breakpoints;

  @override
  State<PanelShell> createState() => _PanelShellState();
}

class _PanelShellState extends State<PanelShell> {
  late final DashboardProvider _dashboard = DashboardProvider(widget.source);
  final _listProviders = <String, ResourceListProvider>{};
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _detailKey = GlobalKey<NavigatorState>();
  final _masterFocus = FocusNode();

  /// Providers owned by routes pushed imperatively (forms, related views,
  /// relation lists). Disposed when their route pops — or, since a nested
  /// navigator unmounting never completes those pushes, whenever the
  /// navigator hosting them goes away (a breakpoint crossing, [dispose]).
  final _pushed = <ChangeNotifier>{};

  ResourceSchema? _selectedResource;
  Object? _selectedRecordId;
  ResourceViewProvider? _viewProvider;
  ResourceFormProvider? _formProvider;
  _Pane _pane = _Pane.empty;
  FilamentFormFactor? _factor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.panelProvider.status.isInitial) widget.panelProvider.load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not `FilamentLayout.of`: this widget installs that layout itself, so
    // its own context sits above it. Same breakpoints, measured directly.
    final factor = widget.breakpoints.of(MediaQuery.sizeOf(context).width);
    if (_factor != null && _factor != factor) {
      if (factor == FilamentFormFactor.expanded) {
        // Widening: the compact stack is discarded with its subtree; the
        // selection it held becomes the detail pane.
        _pane = _selectedRecordId == null ? _Pane.empty : _Pane.view;
      } else if (_pane == _Pane.create) {
        // ponytail: a half-filled create form has no compact route to land
        // on, so narrowing drops it. Keep the provider if that ever matters.
        _pane = _Pane.empty;
      }
      _dropFormProvider();
      // compact↔medium keep the same keyed navigator; only expanded swaps
      // navigators, stranding whatever routes were pushed on the old one.
      if (factor == FilamentFormFactor.expanded ||
          _factor == FilamentFormFactor.expanded) {
        _disposePushed();
      }
    }
    _factor = factor;
  }

  void _disposePushed() {
    final stale = _pushed.toList();
    _pushed.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final provider in stale) {
        provider.dispose();
      }
    });
  }

  @override
  void dispose() {
    _dashboard.dispose();
    for (final provider in _listProviders.values) {
      provider.dispose();
    }
    _viewProvider?.dispose();
    _formProvider?.dispose();
    for (final provider in _pushed) {
      provider.dispose();
    }
    _masterFocus.dispose();
    super.dispose();
  }

  ResourceListProvider _listFor(ResourceSchema resource) =>
      _listProviders.putIfAbsent(
        resource.key,
        () => ResourceListProvider(source: widget.source, resource: resource),
      );

  void _selectResource(ResourceSchema? resource) {
    setState(() {
      _selectedResource = resource;
      _selectRecord(null);
    });
  }

  /// Inside `setState` only. Swaps the view provider when the id changes;
  /// the old one is disposed after this frame, once the screen that listened
  /// to it has unmounted.
  void _selectRecord(Object? id, {_Pane pane = _Pane.view}) {
    if (id != _selectedRecordId) {
      final stale = _viewProvider;
      if (stale != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => stale.dispose());
      }
      _viewProvider = id == null
          ? null
          : ResourceViewProvider(
              source: widget.source,
              resource: _selectedResource!,
              id: id,
            );
    }
    _selectedRecordId = id;
    _pane = id == null ? _Pane.empty : pane;
    _dropFormProvider();
  }

  void _dropFormProvider() {
    final stale = _formProvider;
    _formProvider = null;
    if (stale != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => stale.dispose());
    }
  }

  ResourceFormProvider _newFormProvider(
    ResourceSchema resource, {
    Object? recordId,
  }) => ResourceFormProvider(
    source: widget.source,
    resource: resource,
    strings: widget.strings,
    recordId: recordId,
  );

  @override
  Widget build(BuildContext context) {
    return FilamentLayout(
      breakpoints: widget.breakpoints,
      // The panel's direction mirrors the rail/sidebar row; each screen
      // inside re-applies it for its own subtree as it always has.
      child: ListenableBuilder(
        listenable: widget.panelProvider,
        builder: (context, _) => withPanelDirection(
          widget.panelProvider.panel?.direction ?? PanelDirection.ltr,
          Builder(
            builder: (context) => switch (FilamentLayout.of(context)) {
              FilamentFormFactor.compact => _singlePane(withDrawer: true),
              FilamentFormFactor.medium => Row(
                children: [
                  _rail(),
                  const VerticalDivider(width: 1),
                  Expanded(child: _singlePane(withDrawer: false)),
                ],
              ),
              FilamentFormFactor.expanded => _expanded(),
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- compact

  /// The nested navigator whose stack mirrors the selection: home → list →
  /// view as pages, the form pushed on top as a plain route. A back press
  /// reports the removed page so the selection follows it.
  Widget _singlePane({required bool withDrawer}) {
    final resource = _selectedResource;
    final recordId = _selectedRecordId;

    return NavigatorPopHandler(
      onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
      child: Navigator(
        key: _navigatorKey,
        pages: [
          MaterialPage<void>(
            key: const ValueKey('home'),
            child: _home(withDrawer: withDrawer),
          ),
          if (resource != null)
            MaterialPage<void>(
              key: ValueKey('list/${resource.key}'),
              child: _list(resource, compact: true),
            ),
          if (resource != null && recordId != null)
            MaterialPage<bool>(
              key: ValueKey('view/${resource.key}/$recordId'),
              child: _view(resource, _viewProvider!, swapsPane: false),
              // The view pops `true` once a delete went through.
              onPopInvoked: (didPop, result) {
                if (result == true) _listFor(resource).refresh();
              },
            ),
        ],
        onDidRemovePage: (page) {
          final key = (page.key as ValueKey<String>).value;
          if (key.startsWith('view/')) {
            setState(() => _selectRecord(null));
          } else if (key.startsWith('list/')) {
            _selectResource(null);
          }
        },
      ),
    );
  }

  Widget _home({required bool withDrawer}) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.strings.dashboardTitle),
        actions: [
          if (widget.onLogout != null || _switchableLanguages.isNotEmpty)
            _profileMenu(),
        ],
      ),
      drawer: withDrawer ? Drawer(child: _sidebarList()) : null,
      body: _dashboardScreen(),
    );
  }

  /// The language entries the profile menu draws — empty unless the host
  /// wired [PanelShell.onLanguageSelected] and offered at least two.
  List<FilamentLanguageOption> get _switchableLanguages =>
      widget.onLanguageSelected != null && widget.languages.length >= 2
      ? widget.languages
      : const [];

  Widget _profileMenu() {
    final languages = _switchableLanguages;
    return PopupMenuButton<void>(
      itemBuilder: (context) => [
        for (final language in languages)
          PopupMenuItem<void>(
            onTap: () => widget.onLanguageSelected!(language.tag),
            child: Row(
              children: [
                if (language.tag == widget.activeLanguage)
                  const Icon(Icons.check)
                else
                  const SizedBox(width: 24),
                const SizedBox(width: 12),
                Text(language.label),
              ],
            ),
          ),
        if (languages.isNotEmpty && widget.onLogout != null)
          const PopupMenuDivider(),
        if (widget.onLogout != null)
          PopupMenuItem<void>(
            onTap: widget.onLogout,
            child: Row(
              children: [
                const Icon(Icons.logout),
                const SizedBox(width: 12),
                Text(widget.strings.logOut),
              ],
            ),
          ),
      ],
      child: const Padding(
        padding: EdgeInsetsDirectional.only(end: 12),
        child: CircleAvatar(child: Icon(Icons.person)),
      ),
    );
  }

  Widget _dashboardScreen() {
    return DashboardScreen(
      provider: _dashboard,
      widgetRegistry: widget.widgetRegistry,
      chartBuilder: widget.chartBuilder,
      strings: widget.strings,
      pollInterval: widget.panelProvider.panel?.poll?.dashboard,
      eventTransport: widget.eventTransport,
      realtimeChannels: [
        for (final resource
            in widget.panelProvider.panel?.resources ??
                const <ResourceSchema>[])
          if (resource.channel case final channel?) channel,
      ],
      onStatTap: (resourceKey) {
        final resource = widget.panelProvider.panel?.resource(resourceKey);
        if (resource != null) _selectResource(resource);
      },
    );
  }

  Widget _list(ResourceSchema resource, {required bool compact}) {
    final provider = _listFor(resource);

    return ResourceListScreen(
      provider: provider,
      widgetRegistry: widget.widgetRegistry,
      eventTransport: widget.eventTransport,
      strings: widget.strings,
      rowStyle: compact ? null : ListRowStyle.row,
      selectedRecordId: compact ? null : _selectedRecordId,
      onRecordTap: (record) => setState(() => _selectRecord(record.id)),
      onCreateTap: compact
          ? () => _pushCreate(_navigatorKey.currentState!, resource, provider)
          : () => setState(() {
              _selectRecord(null);
              _pane = _Pane.create;
              _formProvider = _newFormProvider(resource);
            }),
    );
  }

  Future<void> _pushCreate(
    NavigatorState navigator,
    ResourceSchema resource,
    ResourceListProvider list,
  ) async {
    await _push(navigator, _form(_newFormProvider(resource)), owns: []);
    await list.refresh();
  }

  /// Pushes [screen] on [navigator], owning [owns] for the route's lifetime
  /// — see [_pushed]. A form's own provider is inferred, so callers pass
  /// only the extras.
  Future<void> _push(
    NavigatorState navigator,
    Widget screen, {
    required List<ChangeNotifier> owns,
  }) {
    final owned = [...owns, if (screen is ResourceFormScreen) screen.provider];
    _pushed.addAll(owned);
    return navigator
        .push(MaterialPageRoute<void>(builder: (_) => screen))
        .whenComplete(() {
          for (final provider in owned) {
            if (_pushed.remove(provider)) provider.dispose();
          }
        });
  }

  Widget _form(ResourceFormProvider provider, {VoidCallback? onSaved}) {
    return ResourceFormScreen(
      provider: provider,
      widgetRegistry: widget.widgetRegistry,
      registry: widget.fieldRegistry,
      strings: widget.strings,
      filePicker: widget.filePicker,
      onSaved: onSaved,
    );
  }

  /// One record's view with every affordance wired. Related records and
  /// relation lists always push on the navigator the view sits in. Edit
  /// swaps the detail pane to the form only for the pane's OWN record
  /// ([swapsPane]); the compact stack and any pushed related view push the
  /// form on top instead and reload on return, so a related record's edit
  /// never replaces the pane under it.
  Widget _view(
    ResourceSchema resource,
    ResourceViewProvider provider, {
    required bool swapsPane,
  }) {
    return Builder(
      builder: (context) => ResourceViewScreen(
        provider: provider,
        widgetRegistry: widget.widgetRegistry,
        eventTransport: widget.eventTransport,
        strings: widget.strings,
        registry:
            widget.registry ??
            EntryRegistry.defaults(
              onLinkTap: widget.onLinkTap,
              onRelatedTap: (resourceKey, relatedId) {
                final target = widget.panelProvider.panel?.resource(
                  resourceKey,
                );
                if (target == null) return;
                final related = ResourceViewProvider(
                  source: widget.source,
                  resource: target,
                  id: relatedId,
                );
                _push(
                  Navigator.of(context),
                  _view(target, related, swapsPane: false),
                  owns: [related],
                );
              },
            ),
        onEditTap: (record) async {
          if (swapsPane) {
            setState(() {
              _pane = _Pane.form;
              _formProvider = _newFormProvider(resource, recordId: record.id);
            });
            return;
          }
          await _push(
            Navigator.of(context),
            _form(_newFormProvider(resource, recordId: record.id)),
            owns: [],
          );
          await provider.load(keepPrevious: true);
        },
        onSeeAllTap: (relation, ownerId) {
          final childResource = relation.resource == null
              ? null
              : widget.panelProvider.panel?.resource(relation.resource!);
          final relationList = RelationListProvider(
            source: widget.source,
            resourceKey: resource.key,
            id: ownerId,
            relation: relation,
          );
          _push(
            Navigator.of(context),
            RelationListScreen(
              provider: relationList,
              childResource: childResource,
              fieldRegistry: widget.fieldRegistry,
              widgetRegistry: widget.widgetRegistry,
              strings: widget.strings,
              filePicker: widget.filePicker,
              onRecordTap: childResource == null
                  ? null
                  : (record) {
                      final related = ResourceViewProvider(
                        source: widget.source,
                        resource: childResource,
                        id: record.id,
                      );
                      _push(
                        Navigator.of(context),
                        _view(childResource, related, swapsPane: false),
                        owns: [related],
                      );
                    },
            ),
            owns: [relationList],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- sidebar

  /// Drawer (compact) and sidebar (expanded) share this list.
  Widget _sidebarList() {
    return ListenableBuilder(
      listenable: widget.panelProvider,
      builder: (context, _) {
        final panel = widget.panelProvider.panel;
        final theme = Theme.of(context);

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: Text(
                  panel?.title ?? '…',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: Text(widget.strings.dashboardTitle),
              selected: _selectedResource == null,
              onTap: () => _tapEntry(context, null),
            ),
            if (panel == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final MapEntry(key: group, value: resources) in _grouped(
                panel.resources,
              ).entries) ...[
                if (group != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      16,
                      16,
                      4,
                    ),
                    child: Text(
                      group,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                for (final resource in resources)
                  ListTile(
                    leading: Icon(_iconFor(resource)),
                    title: Text(resource.labels.plural),
                    trailing: switch (resource.badge) {
                      final badge? => _badgeChip(context, badge),
                      null => null,
                    },
                    selected: resource.key == _selectedResource?.key,
                    onTap: () => _tapEntry(context, resource),
                  ),
              ],
          ],
        );
      },
    );
  }

  /// A drawer entry closes the drawer first; the expanded sidebar sits in
  /// no Scaffold of its own, so there is nothing to close there.
  void _tapEntry(BuildContext context, ResourceSchema? resource) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
    _selectResource(resource);
  }

  IconData _iconFor(ResourceSchema resource) =>
      widget.iconFor?.call(resource) ?? Icons.folder_outlined;

  /// Resources by sidebar group, ungrouped first — the web panel's order.
  Map<String?, List<ResourceSchema>> _grouped(List<ResourceSchema> resources) {
    final grouped = <String?, List<ResourceSchema>>{
      for (final resource in resources)
        if (resource.group == null) null: [],
    };
    for (final resource in resources) {
      (grouped[resource.group] ??= []).add(resource);
    }
    return grouped;
  }

  Widget _badgeChip(BuildContext context, ResourceBadge badge) {
    final color = switch (badge.color) {
      'success' => Colors.green,
      'warning' => Colors.orange,
      'danger' => Colors.red,
      'info' => Colors.blue,
      _ => Theme.of(context).colorScheme.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        badge.value,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  Widget _rail() {
    return ListenableBuilder(
      listenable: widget.panelProvider,
      builder: (context, _) {
        final resources = widget.panelProvider.panel?.resources ?? const [];
        final selected = _selectedResource == null
            ? 0
            : 1 + resources.indexWhere((r) => r.key == _selectedResource!.key);

        return NavigationRail(
          // Labels always: `iconFor` is optional and every resource without
          // one falls back to the same folder glyph, so a label-less rail is
          // a column of identical icons.
          labelType: NavigationRailLabelType.all,
          selectedIndex: selected < 0 ? null : selected,
          onDestinationSelected: (index) =>
              _selectResource(index == 0 ? null : resources[index - 1]),
          destinations: [
            NavigationRailDestination(
              icon: const Icon(Icons.dashboard_outlined),
              label: Text(widget.strings.dashboardTitle),
            ),
            for (final resource in resources)
              NavigationRailDestination(
                icon: Icon(_iconFor(resource)),
                label: Text(resource.labels.plural),
              ),
          ],
        );
      },
    );
  }

  // --------------------------------------------------------------- expanded

  /// Keyboard selection lives above the whole row, not on the master
  /// alone: the detail pane's navigator takes focus whenever it shows a
  /// page, and ↑/↓/Enter/Esc must keep working from there. The actions
  /// disable themselves while a text field or a button holds focus (see
  /// [_ShellAction]), so those keys reach the widget that owns them.
  Widget _expanded() {
    final resource = _selectedResource;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(-1),
        SingleActivator(LogicalKeyboardKey.enter): _OpenIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _ClearIntent(),
      },
      child: Actions(
        actions: {
          _MoveIntent: _ShellAction<_MoveIntent>(
            _masterFocus,
            onInvoke: (intent) => _move(intent.delta),
          ),
          _OpenIntent: _ShellAction<_OpenIntent>(
            _masterFocus,
            onInvoke: (_) => setState(() {
              if (_selectedRecordId != null) _pane = _Pane.view;
            }),
          ),
          _ClearIntent: _ShellAction<_ClearIntent>(
            _masterFocus,
            onInvoke: (_) => setState(() => _selectRecord(null)),
          ),
        },
        child: Row(
          children: [
            Material(
              key: const ValueKey('panel.sidebar'),
              child: SizedBox(width: 240, child: _sidebarList()),
            ),
            const VerticalDivider(width: 1),
            if (resource == null)
              Expanded(child: _home(withDrawer: false))
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      // 40% of what is left after the sidebar, never under
                      // 360 — a flex ratio alone would squeeze the master
                      // to ~240 at the expanded threshold.
                      SizedBox(
                        width: math.max(360, 0.4 * constraints.maxWidth),
                        // Per-pane messengers: one shared messenger shows
                        // a toast in EVERY Scaffold it knows, so a save
                        // would toast the master and the detail at once.
                        child: ScaffoldMessenger(
                          child: Focus(
                            focusNode: _masterFocus,
                            autofocus: true,
                            child: _list(resource, compact: false),
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: ScaffoldMessenger(child: _detail(resource)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// ↓ with nothing selected lands on the first row; no wrap at either end.
  /// Moves the highlight only — Enter opens it — so a user can skim the
  /// list without every keystroke fetching a record.
  void _move(int delta) {
    final resource = _selectedResource;
    if (resource == null) return;
    final records = _listFor(resource).records;
    if (records.isEmpty) return;
    final current = records.indexWhere((r) => r.id == _selectedRecordId);
    final next = (current + delta).clamp(0, records.length - 1);
    final pane = _pane == _Pane.empty ? _Pane.empty : _Pane.view;
    setState(() => _selectRecord(records[next].id, pane: pane));
  }

  /// The pane's own navigator: an empty placeholder page underneath, the
  /// current pane as a second page keyed on what it shows. Changing the
  /// selection swaps that page — no push — while relation lists pushed from
  /// inside it stack on top. Popping the pane page (the view's delete, the
  /// form's back arrow) steps the state back one notch.
  Widget _detail(ResourceSchema resource) {
    final list = _listFor(resource);

    return NavigatorPopHandler(
      onPopWithResult: (_) => _detailKey.currentState?.maybePop(),
      child: Navigator(
        key: _detailKey,
        pages: [
          MaterialPage<void>(
            key: const ValueKey('empty'),
            child: Scaffold(
              body: Center(child: Text(widget.strings.noRecordSelected)),
            ),
          ),
          if (_pane != _Pane.empty)
            MaterialPage<bool>(
              key: ValueKey('$_pane/$_selectedRecordId'),
              child: _paneContent(resource, list),
              onPopInvoked: (didPop, result) {
                // The view pops `true` once a delete went through.
                if (result == true) list.refresh();
              },
            ),
        ],
        onDidRemovePage: (page) {
          if (page.key == const ValueKey('empty')) return;
          setState(() {
            if (_pane == _Pane.form) {
              _pane = _Pane.view;
              _dropFormProvider();
            } else {
              _selectRecord(null);
            }
          });
        },
      ),
    );
  }

  Widget _paneContent(ResourceSchema resource, ResourceListProvider list) {
    switch (_pane) {
      case _Pane.empty:
        return const SizedBox.shrink();
      case _Pane.view:
        return _view(resource, _viewProvider!, swapsPane: true);
      case _Pane.form:
        final form = _formProvider!;
        return _form(
          form,
          onSaved: () {
            setState(() {
              _pane = _Pane.view;
              _dropFormProvider();
            });
            _viewProvider?.load(keepPrevious: true);
            list.refresh();
          },
        );
      case _Pane.create:
        final form = _formProvider!;
        return _form(
          form,
          onSaved: () {
            setState(() => _selectRecord(form.savedRecordId));
            list.refresh();
          },
        );
    }
  }
}

/// A shell shortcut that yields whenever the focused widget owns the key
/// itself: a text field (↑/↓/Enter/Esc edit text) or anything focused
/// outside the master pane that is not a bare route scope (a button, whose
/// Enter must activate it). Disabled actions make the `Shortcuts` above
/// report the key as ignored, so it propagates to the widget's own handler.
class _ShellAction<T extends Intent> extends CallbackAction<T> {
  _ShellAction(this.master, {required super.onInvoke});

  final FocusNode master;

  @override
  bool get isActionEnabled {
    final focus = FocusManager.instance.primaryFocus;
    // The node's context is the `Focus` EditableText builds, so look up.
    final context = focus?.context;
    if (context != null &&
        context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    return focus is FocusScopeNode || master.hasFocus;
  }
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);
  final int delta;
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}

class _ClearIntent extends Intent {
  const _ClearIntent();
}
