@Tags(['shots'])
library;

import 'dart:io';

import 'package:filament_mobile/filament_mobile.dart';
import 'package:filament_mobile_charts/filament_mobile_charts.dart';
import 'package:filament_mobile_example/demo_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the wide-screen layouts into `art/shots/` — the P23 counterpart of
/// `scripts/capture-shots.sh`, which can only reach a phone.
///
/// A widget test rather than a device capture because no simulator here is
/// wider than a phone (making one is the operator's call, and they eat tens of
/// GB), and the macOS app cannot be photographed without granting Screen
/// Recording to the terminal. This renders the SAME real widget tree the app
/// runs — `PanelShell` over [DemoTransport] — at a real desktop size, and
/// drives it by tapping, so nothing here is a mock-up of the layout.
///
/// Run:
///
/// ```
/// flutter test test/shots_test.dart --tags shots \
///   --dart-define=SHOTS=true --dart-define=DEMO_DIR=ltr --update-goldens
/// ```
///
/// Skipped without `SHOTS` (and excluded by tag) because a golden of this size
/// is machine-dependent: font hinting differs enough between machines that CI
/// would fail on a pixel diff that means nothing. These files are artwork, not
/// assertions.
const _enabled = bool.fromEnvironment('SHOTS');

/// Real text needs real fonts: a test binding ships only Ahem, which draws
/// every glyph as a filled box — fine for layout assertions, useless for a
/// screenshot. Roboto and the Material icon font are in the SDK's own cache.
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;

  Future<void> load(String family, Map<String, String> files) async {
    final loader = FontLoader(family);
    for (final entry in files.entries) {
      final file = File('${dir.path}/${entry.value}');
      if (file.existsSync()) {
        loader.addFont(
          Future.value(file.readAsBytesSync().buffer.asByteData()),
        );
      }
    }
    await loader.load();
  }

  await load('Roboto', {
    'regular': 'Roboto-Regular.ttf',
    'medium': 'Roboto-Medium.ttf',
    'bold': 'Roboto-Bold.ttf',
  });
  await load('MaterialIcons', {'regular': 'MaterialIcons-Regular.otf'});
}

void main() {
  setUpAll(_loadFonts);

  /// Writes one shot, then puts the painting flag back: the binding asserts
  /// no test leaves a painting debug variable changed, and that check runs
  /// before any tearDown could restore it.
  Future<void> capture(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../../../art/shots/$name.png'),
    );
    debugDisableShadows = true;
  }

  Future<void> pumpShell(WidgetTester tester, Size logical) async {
    // A test binding paints every shadow as a solid black silhouette so
    // goldens stay comparable across platforms — here that turns the FAB
    // into a black box. Set before the first paint, restored by `capture`.
    debugDisableShadows = false;

    // Captured at 2x: the golden is written in physical pixels, so this is a
    // retina-density image of a `logical`-sized window.
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = logical * 2;
    addTearDown(tester.view.reset);

    // A test binding defaults to the keyboard highlight mode, which paints a
    // focus ring around whatever the last tap focused — in a screenshot that
    // reads as a rendering fault rather than as focus.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;

    final source = RestResourceDataSource(transport: DemoTransport());
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2A3154)),
        home: PanelShell(
          source: source,
          panelProvider: PanelProvider(source),
          strings: FilamentStrings.forLocale('en'),
          chartBuilder: flChartBuilder(strings: const FilamentChartStrings()),
          // The same map `lib/main.dart` passes: the contract carries no
          // icons, so a shot without this shows the folder fallback five
          // times over and misrepresents what a host's sidebar looks like.
          iconFor: (resource) => switch (resource.key) {
            'categories' => Icons.sell_outlined,
            'customers' => Icons.people_alt_outlined,
            'products' => Icons.view_in_ar_outlined,
            'reviews' => Icons.star_outline,
            'staff' => Icons.badge_outlined,
            _ => Icons.folder_outlined,
          },
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openProducts(WidgetTester tester) async {
    await tester.tap(find.text('Products').first);
    await tester.pumpAndSettle();
  }

  testWidgets('expanded: sidebar, table rows, record in the detail pane', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1440, 900));
    await openProducts(tester);
    await tester.tap(find.byType(ResourceRow).first);
    await tester.pumpAndSettle();

    await capture(tester, 'wide-master-detail');
  }, skip: !_enabled);

  testWidgets('expanded: the dashboard beside the sidebar', (tester) async {
    await pumpShell(tester, const Size(1440, 900));

    await capture(tester, 'wide-dashboard');
  }, skip: !_enabled);

  testWidgets('medium: a navigation rail and one pane', (tester) async {
    await pumpShell(tester, const Size(800, 900));
    await openProducts(tester);

    await capture(tester, 'medium-rail');
  }, skip: !_enabled);
}
