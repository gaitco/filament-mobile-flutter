import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_charts/filament_mobile_charts.dart';
import 'package:flutter/material.dart';

import 'http_filament_transport.dart';
import 'in_memory_schema_cache.dart';

/// A minimal host: index -> list -> record, over real HTTP, no styling of
/// its own — `MaterialPanelStateBuilder`'s default is what's on screen.
///
/// Point it at a live Filament panel running `gait/filament-mobile`:
///
/// ```
/// flutter run -d macos \
///   --dart-define=FILAMENT_BASE_URL=https://your-panel.test \
///   --dart-define=FILAMENT_TOKEN=<a Sanctum bearer token>
/// ```
///
/// An unset or expired/foreign token still boots the app: the panel's own
/// 401 reaches `PanelUnauthenticated`, which is exactly what this example
/// exists to demonstrate. The profile menu's "Log out" drops the token at
/// runtime and lands on the same screen, so the signed-out path is one tap
/// away instead of needing a rebuild.
void main() => runApp(const FilamentMobileExampleApp());

const _baseUrl = String.fromEnvironment('FILAMENT_BASE_URL');
const _token = String.fromEnvironment('FILAMENT_TOKEN');

class FilamentMobileExampleApp extends StatelessWidget {
  const FilamentMobileExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'filament_mobile example',
      home: _baseUrl.isEmpty
          ? const _NotConfigured()
          : PanelHome(baseUrl: _baseUrl, token: _token),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Run with --dart-define=FILAMENT_BASE_URL=https://your-panel.test '
            '--dart-define=FILAMENT_TOKEN=<a bearer token>',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Owns the session: logged in renders a [_Session] keyed by the token (so
/// logging back in rebuilds the transport and providers from scratch),
/// logged out renders a plain signed-out screen. This example has no login
/// form — "log in" restores the compile-time token, standing in for
/// whatever real authentication a host app does.
class PanelHome extends StatefulWidget {
  const PanelHome({required this.baseUrl, required this.token, super.key});

  final String baseUrl;
  final String token;

  @override
  State<PanelHome> createState() => _PanelHomeState();
}

class _PanelHomeState extends State<PanelHome> {
  String? _sessionToken;

  @override
  void initState() {
    super.initState();
    _sessionToken = widget.token;
  }

  @override
  Widget build(BuildContext context) {
    final token = _sessionToken;
    if (token == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              const Text('Signed out'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(() => _sessionToken = widget.token),
                child: const Text('Log in'),
              ),
            ],
          ),
        ),
      );
    }
    return _Session(
      key: ValueKey(token),
      baseUrl: widget.baseUrl,
      token: token,
      onLogout: () => setState(() => _sessionToken = null),
    );
  }
}

/// One signed-in session: owns the transport and the panel provider, and
/// wires the package's screens together — navigation is the host's job, per
/// every screen's `onXTap` doc comment.
class _Session extends StatefulWidget {
  const _Session({
    required this.baseUrl,
    required this.token,
    required this.onLogout,
    super.key,
  });

  final String baseUrl;
  final String token;
  final VoidCallback onLogout;

  @override
  State<_Session> createState() => _SessionState();
}

class _SessionState extends State<_Session> {
  late final ResourceDataSource _source = RestResourceDataSource(
    transport: HttpFilamentTransport(
      baseUrl: widget.baseUrl,
      token: () => widget.token,
    ),
    cache: InMemorySchemaCache(),
    // Scoped to the token, not a constant: `/schema` is per-user, so a
    // shared key would let a second signed-in user on this device open the
    // first user's cached panel index — see FilamentSchemaCache's doc
    // comment. The token is this example's only stand-in for "who's signed
    // in" (there is no separate user id here); a real host keys off its own
    // user id or a hash of the token instead of the bearer token itself.
    cacheKey: widget.token,
  );
  late final PanelProvider _panelProvider = PanelProvider(_source);
  late final DashboardProvider _dashboard = DashboardProvider(_source);

  @override
  void initState() {
    super.initState();
    // PanelIndexScreen used to trigger this load; with the resources moved
    // into the drawer, the session owns it — same untouched-provider guard
    // as the package's own screens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_panelProvider.status.isInitial) _panelProvider.load();
    });
  }

  /// The same icons the Filament sidebar shows for these resources, in
  /// their closest Material shapes — the contract carries no icon, so the
  /// mapping is the host's, keyed on the resource key. An unknown resource
  /// gets a neutral folder.
  IconData _iconFor(ResourceSchema resource) => switch (resource.key) {
    'articles' => Icons.archive_outlined,
    'categories' => Icons.sell_outlined,
    'customers' => Icons.people_alt_outlined,
    'orders' => Icons.shopping_cart_outlined,
    'products' => Icons.view_in_ar_outlined,
    _ => Icons.folder_outlined,
  };

  @override
  Widget build(BuildContext context) {
    // One home page, like the web panel: the dashboard is the body and the
    // resources live in a drawer. DashboardScreen owns no Scaffold/AppBar
    // of its own, and charts come from the companion package's builder —
    // same wiring as main_demo.dart.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          PopupMenuButton<void>(
            tooltip: 'Profile',
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                onTap: widget.onLogout,
                child: const Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 12),
                    Text('Log out'),
                  ],
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsetsDirectional.only(end: 12),
              child: CircleAvatar(child: Icon(Icons.person)),
            ),
          ),
        ],
      ),
      drawer: Drawer(child: _sidebar()),
      body: DashboardScreen(
        provider: _dashboard,
        chartBuilder: flChartBuilder(
          strings: FilamentChartStrings.forLocale('en'),
        ),
        // A stat whose web ->url() targets an opted-in resource arrives
        // with its resourceKey — tapping the tile opens that resource's
        // list, the phone's equivalent of the web tile's link.
        onStatTap: (resourceKey) {
          final resource = _panelProvider.panel?.resource(resourceKey);
          if (resource == null) return;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => _resourceList(resource)),
          );
        },
      ),
    );
  }

  /// The web panel's sidebar, phone-sized: panel title on top, one entry
  /// per resource the user may see. Rebuilt from the provider so entries
  /// appear as soon as `/schema` resolves.
  Widget _sidebar() {
    return ListenableBuilder(
      listenable: _panelProvider,
      builder: (context, _) {
        final panel = _panelProvider.panel;
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: Text(
                  panel?.title ?? '…',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
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
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      final badge? => _badgeChip(badge),
                      null => null,
                    },
                    onTap: () {
                      Navigator.of(context).pop(); // close the drawer
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => _resourceList(resource),
                        ),
                      );
                    },
                  ),
              ],
          ],
        );
      },
    );
  }

  /// Resources by sidebar group, ungrouped first — the same order the web
  /// panel and PanelIndexScreen use.
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

  /// The web sidebar's count badge, phone-sized: value on a tinted pill in
  /// the badge's semantic colour.
  Widget _badgeChip(ResourceBadge badge) {
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

  Widget _resourceList(ResourceSchema resource) {
    // Hoisted for the same reason as viewProvider below: the create flow
    // refreshes this provider after a save, so the list shows the new row.
    final listProvider = ResourceListProvider(
      source: _source,
      resource: resource,
    );
    return ResourceListScreen(
      provider: listProvider,
      // Like onEditTap: the package renders no create button unless the
      // host wires this — and it stays hidden when the resource's
      // permissions.create is false.
      onCreateTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ResourceFormScreen(
              provider: ResourceFormProvider(
                source: _source,
                resource: resource,
                strings: const FilamentStrings(),
              ),
            ),
          ),
        );
        await listProvider.refresh();
      },
      onRecordTap: (record) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => _recordView(resource, record.id),
        ),
      ),
    );
  }

  /// One record's view screen with every affordance wired — shared by the
  /// list's row tap and by targeted entries, which navigate here for a
  /// DIFFERENT resource ('category.name' opening that category), so this
  /// takes the resource explicitly rather than closing over one.
  Widget _recordView(ResourceSchema resource, Object recordId) {
    // Owned here, not inline in the route builder, so the edit flow can
    // reload the same provider after a save and the reopened screen shows
    // the updated record rather than the stale fetch.
    final viewProvider = ResourceViewProvider(
      source: _source,
      resource: resource,
      id: recordId,
    );
    return ResourceViewScreen(
      provider: viewProvider,
      // The package renders no edit button unless the host wires this — an
      // unwired affordance would render and silently no-op, per
      // ResourceViewScreen.onEditTap's doc.
      onEditTap: (record) async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ResourceFormScreen(
              provider: ResourceFormProvider(
                source: _source,
                resource: resource,
                strings: const FilamentStrings(),
                recordId: record.id,
              ),
            ),
          ),
        );
        await viewProvider.load(keepPrevious: true);
      },
      // `onLinkTap` makes a rich-text link tappable — this package takes no
      // URL-launcher dependency, so opening it is entirely the host's call.
      // This example has no such dependency either, so it echoes the href
      // instead of opening it; a host wiring a real `url_launcher` call
      // goes here.
      registry: EntryRegistry.defaults(
        onLinkTap: (href) => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Link tapped: $href'))),
        // A targeted entry ('category.name') navigates to the related
        // record — recursive on purpose: the category's own view gets the
        // same wiring, so a chain of relations stays navigable.
        onRelatedTap: (resourceKey, relatedId) {
          final target = _panelProvider.panel?.resource(resourceKey);
          if (target == null) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => _recordView(target, relatedId),
            ),
          );
        },
      ),
      onSeeAllTap: (relation, ownerId) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RelationListScreen(
            provider: RelationListProvider(
              source: _source,
              resourceKey: resource.key,
              id: ownerId,
              relation: relation,
            ),
          ),
        ),
      ),
    );
  }
}
