import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_charts/filament_mobile_charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'http_filament_transport.dart';
import 'in_memory_schema_cache.dart';

/// A minimal host: `PanelShell` over real HTTP, no styling of its own — the
/// shell's own layout (drawer, rail, or sidebar + master-detail, by form
/// factor) is what's on screen.
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
///
/// The UI language (P22) is read before the first frame so the app never
/// flashes English on an Arabic device — the preference is per device, and
/// the shell's profile menu is where it changes.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(FilamentMobileExampleApp(prefs: prefs));
}

/// Where the chosen UI language persists between launches.
const _localePrefsKey = 'filament_locale';

const _baseUrl = String.fromEnvironment('FILAMENT_BASE_URL');
const _token = String.fromEnvironment('FILAMENT_TOKEN');

/// Route prefix of the serving package: filament-mobile's default, or
/// `/api/nova-mobile` for a Laravel Nova host running gait/nova-mobile —
/// the contract is identical, only the mount point differs.
const _prefix = String.fromEnvironment(
  'FILAMENT_PREFIX',
  defaultValue: '/api/mobile-panel',
);

/// Lets `onLinkTap` below show a SnackBar without a `BuildContext` of its
/// own: `PanelShell` wraps its own per-pane `ScaffoldMessenger`s in expanded
/// layout, so a context captured above the shell would miss those panes
/// anyway. The app-root messenger this key targets is a fine stand-in for a
/// demo link tap.
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

class FilamentMobileExampleApp extends StatefulWidget {
  const FilamentMobileExampleApp({required this.prefs, super.key});

  final SharedPreferences prefs;

  @override
  State<FilamentMobileExampleApp> createState() =>
      _FilamentMobileExampleAppState();
}

class _FilamentMobileExampleAppState extends State<FilamentMobileExampleApp> {
  late String _localeTag = widget.prefs.getString(_localePrefsKey) ?? 'en';

  void _setLocale(String tag) {
    setState(() => _localeTag = tag);
    widget.prefs.setString(_localePrefsKey, tag);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'filament_mobile example',
      scaffoldMessengerKey: _messengerKey,
      // The app-level locale is what flips text direction and Material's own
      // widget strings (tooltips, pickers); the package's screen strings flip
      // with it via `FilamentStrings.forLocale` in `_Session` below.
      locale: Locale(_localeTag),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: _baseUrl.isEmpty
          ? const _NotConfigured()
          : PanelHome(
              baseUrl: _baseUrl,
              token: _token,
              localeTag: _localeTag,
              onLocaleSelected: _setLocale,
            ),
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
  const PanelHome({
    required this.baseUrl,
    required this.token,
    required this.localeTag,
    required this.onLocaleSelected,
    super.key,
  });

  final String baseUrl;
  final String token;
  final String localeTag;
  final ValueChanged<String> onLocaleSelected;

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
      localeTag: widget.localeTag,
      onLocaleSelected: widget.onLocaleSelected,
      onLogout: () => setState(() => _sessionToken = null),
    );
  }
}

/// One signed-in session: owns the transport and the panel provider, and
/// hands them to `PanelShell`, which owns the rest — layout by form factor,
/// navigation, and every screen the panel exposes.
class _Session extends StatefulWidget {
  const _Session({
    required this.baseUrl,
    required this.token,
    required this.localeTag,
    required this.onLocaleSelected,
    required this.onLogout,
    super.key,
  });

  final String baseUrl;
  final String token;
  final String localeTag;
  final ValueChanged<String> onLocaleSelected;
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
    prefix: _prefix,
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
    return PanelShell(
      source: _source,
      panelProvider: _panelProvider,
      strings: FilamentStrings.forLocale(widget.localeTag),
      // Charts come from the companion package's builder — the core package
      // deliberately ships no charting dependency of its own.
      chartBuilder: flChartBuilder(
        strings: FilamentChartStrings.forLocale(widget.localeTag),
      ),
      iconFor: _iconFor,
      onLogout: widget.onLogout,
      // The UI language picker (P22): labels are endonyms, the tags are this
      // host's own — `forLocale` above and the MaterialApp locale both read
      // them. Persistence is the host's job; this example uses
      // shared_preferences at the app root.
      languages: const [
        FilamentLanguageOption('en', 'English'),
        FilamentLanguageOption('ar', 'العربية'),
      ],
      activeLanguage: widget.localeTag,
      onLanguageSelected: widget.onLocaleSelected,
      // The package takes no URL-launcher dependency, so opening a rich-text
      // link is entirely the host's call. This example has no such
      // dependency either, so it echoes the href instead of opening it; a
      // host wiring a real `url_launcher` call goes here.
      onLinkTap: (href) => _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Link tapped: $href')),
      ),
    );
  }
}
