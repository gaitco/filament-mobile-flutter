import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_charts/filament_mobile_charts.dart';
import 'package:flutter/material.dart';

import 'demo_transport.dart';

/// Screenshot host: the real screens over [DemoTransport].
///
/// `--dart-define=DEMO_SCREEN=` boots straight into a target screen so captures
/// need no tapping:
///
/// | value           | screen                                              |
/// |-----------------|-----------------------------------------------------|
/// | `index`         | the panel index (default)                           |
/// | `list`          | products, paginated and searchable                  |
/// | `form`          | the products form — eleven field types, see `DEMO_SCROLL` |
/// | `record`        | a record: entries, rich text, relation section, actions |
/// | `relations`     | the full relation list, with P9's row write controls |
/// | `relation_form` | the child resource's form, which those controls open |
/// | `dashboard`     | stat tiles and charts, drawn by `filament_mobile_charts` |
///
/// Pair with `DEMO_DIR=ltr` for left-to-right captures; the fixture's own
/// default is an Arabic, right-to-left panel.
void main() => runApp(const DemoApp());

const _screen = String.fromEnvironment('DEMO_SCREEN', defaultValue: 'index');

/// `--dart-define=DEMO_SCROLL=950` opens the form already scrolled that far.
///
/// The products form carries eleven field types deliberately, which makes it
/// taller than any phone: a single capture shows the first three and no
/// evidence the rest exist. Rather than fake a shorter form for the README,
/// the same real screen is captured at a few offsets and composed side by side.
///
/// It works without touching the package because `ResourceFormScreen`'s
/// `ListView` passes no controller of its own, and a vertical `ListView` with
/// no controller attaches to the ambient `PrimaryScrollController` — so the
/// host can set the initial offset from outside.
const _scrollOffset = int.fromEnvironment('DEMO_SCROLL');

/// The fixture's locale, mirrored from `demo_transport.dart`'s private
/// `_demoLocale`: its schema publishes `ar` under RTL (the default) and `en`
/// otherwise, and the strings the demo passes should say the same thing the
/// server does. Derived from the same public [demoDirection] rather than
/// duplicating the fixture's `locale:` line.
const _stringsLocale = demoDirection == 'rtl' ? 'ar' : 'en';

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'filament_mobile demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2A3154)),
      home: const _DemoHome(),
    );
  }
}

class _DemoHome extends StatefulWidget {
  const _DemoHome();

  @override
  State<_DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<_DemoHome> {
  late final ResourceDataSource _source = RestResourceDataSource(
    transport: DemoTransport(),
  );
  late final PanelProvider _panel = PanelProvider(_source);
  late final DashboardProvider _dashboard = DashboardProvider(_source);

  /// Null unless [_scrollOffset] was set, so the ordinary demo keeps the
  /// framework's own controller. Built once and disposed below rather than
  /// created inside `build()` — a `ScrollController` per rebuild is the same
  /// leak the package just fixed in `RelationListScreen`.
  late final ScrollController? _formScroll = _scrollOffset == 0
      ? null
      : ScrollController(initialScrollOffset: _scrollOffset.toDouble());

  @override
  void dispose() {
    _formScroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_screen == 'index') return _index();
    // Charts are drawn by the companion package's builder — the core package
    // deliberately ships no charting dependency of its own.
    //
    // The Scaffold is this HOST's, not the screen's: `DashboardScreen` owns no
    // `Scaffold`/`AppBar` on purpose, because `DashboardProvider` carries no
    // title to put in one, so it renders into whatever chrome the host already
    // has. Returned bare as `home:` it therefore painted straight onto the
    // app's black void — light cards on black, which read as a rendering bug
    // and made the dashboard the one screen no screenshot could use. Being the
    // package's reference host, this demo should show the wiring a real host
    // needs rather than the shortcut.
    if (_screen == 'dashboard') {
      return Scaffold(
        appBar: AppBar(
          title: Text(_stringsLocale == 'ar' ? 'لوحة التحكم' : 'Dashboard'),
        ),
        body: DashboardScreen(
          provider: _dashboard,
          chartBuilder: flChartBuilder(
            strings: FilamentChartStrings.forLocale(_stringsLocale),
          ),
        ),
      );
    }
    return FutureBuilder<PanelSchema>(
      future: _source.panel(),
      builder: (context, snapshot) {
        final panel = snapshot.data;
        if (panel == null) return const SizedBox.shrink();
        final products = panel.resources.firstWhere((r) => r.key == 'products');
        if (_screen == 'form') return _form(products);
        // `record` boots straight into the detail screen, which was otherwise
        // reachable only by tapping index → list → row. That made it the one
        // screen the README's screenshot pipeline could not capture, and the
        // one most worth looking at, since it is where entries, relation
        // sections, rich text and the actions menu all render at once.
        if (_screen == 'record') return _viewById(panel, products, 1);
        // `relations` boots the full relation list, which was reachable only by
        // tapping index → list → row → "See all". It is where P9's row writes
        // live — Add in the app bar, a pencil and a bin per row — and each is
        // gated on the CHILD resource's published permissions, so none of them
        // renders without the `childResource` below.
        if (_screen == 'relations') {
          return _relations(panel, products, 1);
        }
        // The form the relation's Add and per-row edit open: the CHILD
        // resource's own, reused whole, which is the part of P9 worth showing
        // beside the list. Reached by tapping `+` in the app, and `+` is not
        // something a screenshot can tap.
        if (_screen == 'relation_form') {
          final reviews = panel.resource('reviews');
          if (reviews != null) return _form(reviews);
        }
        return _list(panel, products);
      },
    );
  }

  Widget _index() => PanelIndexScreen(
    provider: _panel,
    strings: FilamentStrings.forLocale(_stringsLocale),
    // `_panel.panel` is non-null by the time a resource can be tapped — the
    // index cannot render a row until the schema it lists has loaded.
    onResourceTap: (resource) => Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => _list(_panel.panel, resource)),
    ),
  );

  Widget _list(PanelSchema? panel, ResourceSchema resource) =>
      ResourceListScreen(
        provider: ResourceListProvider(source: _source, resource: resource),
        strings: FilamentStrings.forLocale(_stringsLocale),
        onRecordTap: (record) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => _view(panel, resource, record),
          ),
        ),
      );

  Widget _view(
    PanelSchema? panel,
    ResourceSchema resource,
    ResourceRecord record,
  ) => _viewById(panel, resource, record.id);

  Widget _viewById(PanelSchema? panel, ResourceSchema resource, Object id) =>
      ResourceViewScreen(
        provider: ResourceViewProvider(
          source: _source,
          resource: resource,
          id: id,
        ),
        strings: FilamentStrings.forLocale(_stringsLocale),
        // `onLinkTap` makes a rich-text link tappable — this package takes
        // no URL-launcher dependency, so opening it is entirely the host's
        // call. This demo has no such dependency either, so it echoes the
        // href instead of opening it; a host wiring a real `url_launcher`
        // call goes here.
        registry: EntryRegistry.defaults(
          onLinkTap: (href) => ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Link tapped: $href'))),
        ),
        onEditTap: (record) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => _form(resource, recordId: record.id),
          ),
        ),
        onSeeAllTap: (relation, recordId) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                _relationList(panel, resource, relation, recordId),
          ),
        ),
      );

  /// The full relation list for [resource]'s only relation, for
  /// `DEMO_SCREEN=relations`. Resolves the relation off the schema rather than
  /// naming it, so it follows the fixture instead of duplicating it.
  Widget _relations(
    PanelSchema panel,
    ResourceSchema resource,
    Object recordId,
  ) {
    final relation = resource.relations.first;

    return _relationList(panel, resource, relation, recordId);
  }

  /// Shared by the tap-through path and the direct boot, so the screenshot and
  /// the app a reader actually taps through cannot show different affordances.
  ///
  /// `childResource` is what a host resolves from its already-loaded panel —
  /// `panel.resource(relation.resource)` — and it is the whole write story: the
  /// relation descriptor's `resource` key names the child, that child's own
  /// `permissions` gate Add / edit / delete, and its `form` is what those
  /// controls open. Null (an old server, or a relation with no single owning
  /// resource) renders no control at all rather than a disabled one.
  Widget _relationList(
    PanelSchema? panel,
    ResourceSchema resource,
    RelationDescriptor relation,
    Object recordId,
  ) => RelationListScreen(
    provider: RelationListProvider(
      source: _source,
      resourceKey: resource.key,
      id: recordId,
      relation: relation,
    ),
    strings: FilamentStrings.forLocale(_stringsLocale),
    // Threaded in rather than read off `_panel`: only the index path loads
    // that provider, so a direct `DEMO_SCREEN=relations` boot would have found
    // it null and rendered the list with no affordances at all — the one thing
    // this screen exists to show.
    childResource: relation.resource == null
        ? null
        : panel?.resource(relation.resource!),
    filePicker: _pickFile,
  );

  Widget _form(ResourceSchema resource, {Object? recordId}) {
    final screen = ResourceFormScreen(
      provider: ResourceFormProvider(
        source: _source,
        resource: resource,
        strings: FilamentStrings.forLocale(_stringsLocale),
        recordId: recordId ?? 1,
      ),
      strings: FilamentStrings.forLocale(_stringsLocale),
      filePicker: _pickFile,
    );

    // Unwrapped unless an offset was asked for, so the ordinary demo behaves
    // exactly as before — the wrap exists only to let a capture start partway
    // down a form taller than the phone. See [_scrollOffset].
    if (_formScroll == null) return screen;

    return PrimaryScrollController(controller: _formScroll, child: screen);
  }

  // A real host wires image_picker or file_picker here. The demo ships no
  // such dependency, so it returns a small synthetic byte list under a fixed
  // filename — enough to exercise the upload wiring, not to pick a real file.
  Future<PickedFile?> _pickFile(SchemaComponent field) async =>
      const PickedFile(bytes: [1, 2, 3, 4], filename: 'demo-photo.png');
}
