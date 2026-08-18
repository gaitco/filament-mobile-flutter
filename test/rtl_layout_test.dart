// Task 4 of the P6f RTL/i18n plan: the six screens obey the panel's
// published direction, and the four widgets measured direction-unsafe flip
// (the fourth, the rich-text blockquote's indent, together with its border).
//
// Fix round 2 adds the two groups the whole-branch review's Important 2
// called for: one test per `isolateBidi` call site, and one per
// overlay route — the seam between a proven helper and the widgets that call
// it, which nothing exercised before.
//
// Every direction assertion below reads `Directionality.of(context)` from a
// BuildContext taken from a genuine descendant widget — never merely checks
// that a `Directionality` ancestor exists somewhere in the tree, which would
// pass against a wrapper that resolves the wrong value. Every geometry
// assertion measures where a widget actually renders (`tester.getTopLeft`/
// `getTopRight`), never the constructor argument it was built with — typing
// `EdgeInsetsDirectional` proves nothing about which edge the pixels land on.
// Every one of those geometry checks is run under BOTH directions, so a fix
// that flips unconditionally (breaking LTR, which already worked) fails here
// exactly as loudly as one that never flips at all.
//
// Task 4b closes the gap Task 4 stated above this comment: GET /dashboard now
// publishes its own `direction`, the same way /schema does, so DashboardScreen
// joins the other five below rather than needing a host-facing parameter.

import 'package:filament_mobile/data/resource_data_source.dart';
import 'package:filament_mobile/data/resource_record.dart';
import 'package:filament_mobile/data/upload_result.dart';
import 'package:filament_mobile/data/write_result.dart';
import 'package:filament_mobile/dashboard/dashboard_data.dart';
import 'package:filament_mobile/data/action_result.dart';
import 'package:filament_mobile/data/options_page.dart';
import 'package:filament_mobile/data/paginated_records.dart';
import 'package:filament_mobile/form/field_registry.dart';
import 'package:filament_mobile/form/field_state.dart';
import 'package:filament_mobile/ports/filament_strings.dart';
import 'package:filament_mobile/schema/schema.dart';
import 'package:filament_mobile/state/dashboard_provider.dart';
import 'package:filament_mobile/state/panel_provider.dart';
import 'package:filament_mobile/state/relation_list_provider.dart';
import 'package:filament_mobile/state/resource_form_provider.dart';
import 'package:filament_mobile/state/resource_list_provider.dart';
import 'package:filament_mobile/state/resource_view_provider.dart';
import 'package:filament_mobile/ui/dashboard_screen.dart';
import 'package:filament_mobile/ui/entries/entry_widgets.dart';
import 'package:filament_mobile/ui/entries/rich_entry_tile.dart';
import 'package:filament_mobile/ui/panel_index_screen.dart';
import 'package:filament_mobile/ui/relation_list_screen.dart';
import 'package:filament_mobile/ui/resource_card.dart';
import 'package:filament_mobile/ui/resource_form_screen.dart';
import 'package:filament_mobile/ui/resource_list_screen.dart';
import 'package:filament_mobile/ui/resource_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_until_found.dart';

/// A [ResourceDataSource] whose every method throws, except the two overridden
/// per test — the same "throw unless a test needs it" shape every screen
/// test file in this suite already uses. Shared here because four of the
/// five screens under test need one.
class _ThrowingSource implements ResourceDataSource {
  @override
  Future<PanelSchema> panel() async => throw UnimplementedError();
  @override
  Future<PanelSchema?> cachedPanel() async => null;
  @override
  Future<PaginatedRecords> list(
    String resourceKey, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async => const PaginatedRecords(
    records: [],
    meta: PageMeta(currentPage: 1, lastPage: 1, perPage: 20, total: 0),
  );
  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async =>
      throw UnimplementedError();
  @override
  Future<PaginatedRecords> relation(
    String resourceKey,
    Object id,
    RelationDescriptor relation, {
    int page = 1,
    String? search,
    String? sort,
    String? direction,
  }) async => const PaginatedRecords(
    records: [],
    meta: PageMeta(currentPage: 1, lastPage: 1, perPage: 20, total: 0),
  );
  @override
  Future<WriteResult> createRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Map<String, dynamic> values,
  ) => throw UnimplementedError();
  @override
  Future<WriteResult> updateRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
    Map<String, dynamic> values,
  ) => throw UnimplementedError();
  @override
  Future<WriteResult> deleteRelation(
    String resourceKey,
    Object id,
    RelationDescriptor relation,
    Object childId,
  ) => throw UnimplementedError();
  @override
  Future<WriteResult> create(String resourceKey, Map<String, dynamic> values) =>
      throw UnimplementedError();
  @override
  Future<WriteResult> update(
    String resourceKey,
    Object id,
    Map<String, dynamic> values,
  ) => throw UnimplementedError();
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
  Future<OptionsPage> options(
    String resourceKey, {
    required String field,
    Object? recordId,
    required Map<String, dynamic> values,
    required String query,
  }) => throw UnimplementedError();
  @override
  Future<List<SchemaComponent>> state(
    String resourceKey, {
    Object? recordId,
    required Map<String, dynamic> values,
    required String changed,
  }) => throw UnimplementedError();
  @override
  Future<DashboardData> dashboard() async => throw UnimplementedError();
  @override
  Future<UploadResult> uploadFile(
    String resourceKey,
    String field, {
    required List<int> bytes,
    required String filename,
  }) => throw UnimplementedError();
}

/// The design spec's own measured defect string: unisolated, `+20` paints to
/// the RIGHT of `8610` under RTL (`bidi_text_test.dart` asserts that baseline
/// directly).
const _phone = 'اتصل بنا على +20 2 2411 8610 اليوم';

/// A plain LTR `MaterialApp` with one RTL island inside it — the exact tree
/// the six screen wraps produce inside an LTR host.
Widget _rtlHost(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

RichDocument _richDoc(List<Map<String, dynamic>> content) =>
    RichDocument.fromJson({
      'doc': {'type': 'doc', 'content': content},
      'text': '',
    }, 'test.__rich');

/// Asserts [_phone]'s first and last digit groups paint in reading order in
/// whichever rendered paragraph actually contains them.
///
/// Reads the paragraph's OWN painted string (`toPlainText()`) rather than the
/// source string, so the isolate characters the widget inserted are part of
/// the offsets being measured — which is what makes deleting the widget's
/// `isolateBidi(...)` call flip this assertion instead of merely
/// changing an invisible character.
void _expectPhoneGroupsInReadingOrder(WidgetTester tester) {
  RenderParagraph? found;
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.byType(RichText),
  )) {
    if (paragraph.text.toPlainText().contains('8610')) {
      found = paragraph;
      break;
    }
  }
  expect(found, isNotNull, reason: 'no rendered paragraph contains "8610"');

  final painted = found!.text.toPlainText();
  double x(String needle) {
    final start = painted.indexOf(needle);
    return found!
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + needle.length),
        )
        .first
        .left;
  }

  expect(
    x('+20'),
    lessThan(x('8610')),
    reason:
        'the leading group must paint left of the trailing one — without '
        'isolateBidi the bidi algorithm reverses them, which is '
        'the defect this branch exists to fix',
  );
}

ResourceSchema _resource(PanelDirection direction) => ResourceSchema(
  key: 'posts',
  labels: const ResourceLabels(singular: 'Post', plural: 'Posts'),
  infolist: const [],
  direction: direction,
);

/// The record screen's published actions sit behind an overflow menu, so a
/// test that reaches one opens it first.
Future<void> _openActions(WidgetTester tester) async {
  await pumpUntilFound(
    tester,
    find.byKey(const ValueKey('record.actions.menu')),
  );
  await tester.tap(find.byKey(const ValueKey('record.actions.menu')));
  await tester.pumpAndSettle();
}

void main() {
  group('screens resolve the panel\'s published direction — read via '
      'Directionality.of(context) at a genuine descendant, not merely the '
      'presence of a Directionality ancestor', () {
    testWidgets('ResourceListScreen', (tester) async {
      Future<TextDirection> resolvedFor(PanelDirection direction) async {
        final provider = ResourceListProvider(
          source: _ThrowingSource(),
          resource: _resource(direction),
        );
        await tester.pumpWidget(
          MaterialApp(home: ResourceListScreen(provider: provider)),
        );
        final context = tester.element(find.text('Posts'));
        return Directionality.of(context);
      }

      expect(await resolvedFor(PanelDirection.ltr), TextDirection.ltr);
      expect(await resolvedFor(PanelDirection.rtl), TextDirection.rtl);
    });

    testWidgets('ResourceViewScreen', (tester) async {
      Future<TextDirection> resolvedFor(PanelDirection direction) async {
        final provider = ResourceViewProvider(
          source: _ThrowingSource(),
          resource: _resource(direction),
          id: 1,
        );
        await tester.pumpWidget(
          MaterialApp(home: ResourceViewScreen(provider: provider)),
        );
        final context = tester.element(find.text('Post'));
        return Directionality.of(context);
      }

      expect(await resolvedFor(PanelDirection.ltr), TextDirection.ltr);
      expect(await resolvedFor(PanelDirection.rtl), TextDirection.rtl);
    });

    testWidgets('ResourceFormScreen', (tester) async {
      Future<TextDirection> resolvedFor(PanelDirection direction) async {
        // recordId: null — create mode, load() never touches the source,
        // so the throwing fake is never exercised.
        final provider = ResourceFormProvider(
          source: _ThrowingSource(),
          resource: _resource(direction),
          strings: const FilamentStrings(),
          recordId: null,
        );
        await tester.pumpWidget(
          MaterialApp(home: ResourceFormScreen(provider: provider)),
        );
        final context = tester.element(find.text('Post'));
        return Directionality.of(context);
      }

      expect(await resolvedFor(PanelDirection.ltr), TextDirection.ltr);
      expect(await resolvedFor(PanelDirection.rtl), TextDirection.rtl);
    });

    testWidgets('RelationListScreen', (tester) async {
      final relationLtr = RelationDescriptor.fromJson(const {
        'key': 'tags',
        'label': 'Tags',
        'card': {
          'title': {'field': 'name'},
        },
      }, 'r');
      // Walks the REAL propagation chain end to end — panel JSON through
      // `PanelSchema.fromJson` → `ResourceSchema.fromJson` →
      // `RelationDescriptor.listFromJson` — not `RelationDescriptor.fromJson`
      // called directly with an explicit `direction:` override. The direct
      // form (used for `relationLtr` above, fine there since that's the
      // no-propagation default) would keep passing even if
      // `resource_schema.dart` stopped forwarding its own `direction` into
      // `RelationDescriptor.listFromJson` — review finding 4: dropping that
      // one line left every test in this file green except
      // `relation_descriptor_test.dart`'s own unit test. Deriving the
      // relation from a fully parsed panel closes that gap here too.
      final relationRtl = PanelSchema.fromJson({
        'version': 1,
        'panel': {'id': 'mobile', 'title': 'Panel', 'direction': 'rtl'},
        'resources': [
          {
            'key': 'posts',
            'labels': {'singular': 'Post', 'plural': 'Posts'},
            'relations': [
              {
                'key': 'tags',
                'label': 'Tags',
                'card': {
                  'title': {'field': 'name'},
                },
              },
            ],
          },
        ],
      }).resource('posts')!.relations.single;

      Future<TextDirection> resolvedFor(RelationDescriptor relation) async {
        final provider = RelationListProvider(
          source: _ThrowingSource(),
          resourceKey: 'posts',
          id: 1,
          relation: relation,
        );
        await tester.pumpWidget(
          MaterialApp(home: RelationListScreen(provider: provider)),
        );
        final context = tester.element(find.text('Tags'));
        return Directionality.of(context);
      }

      expect(await resolvedFor(relationLtr), TextDirection.ltr);
      expect(await resolvedFor(relationRtl), TextDirection.rtl);
    });

    testWidgets('PanelIndexScreen', (tester) async {
      Future<TextDirection> resolvedFor(String rawDirection) async {
        final source = _PanelSource(direction: rawDirection);
        final provider = PanelProvider(source);
        await tester.pumpWidget(
          MaterialApp(
            // A fresh key per call: without one, Flutter reuses the same
            // State across the two pumpWidget calls below (same widget
            // type, same tree position) and calls didUpdateWidget instead
            // of initState — so the second provider's load() would never
            // fire and this would hang waiting for a load that never
            // started, not for a direction bug.
            home: PanelIndexScreen(
              key: ValueKey(rawDirection),
              provider: provider,
              onResourceTap: (_) {},
            ),
          ),
        );
        // The panel loads asynchronously via a post-frame callback.
        await pumpUntilFound(tester, find.text('Posts'));
        final context = tester.element(find.text('Posts'));
        return Directionality.of(context);
      }

      expect(await resolvedFor('ltr'), TextDirection.ltr);
      expect(await resolvedFor('rtl'), TextDirection.rtl);
    });

    testWidgets('DashboardScreen', (tester) async {
      // Walks the real propagation chain end to end: GET /dashboard's raw
      // JSON, through DashboardData.fromJson, to DashboardScreen's own wrap —
      // not a hand-built DashboardData(direction: PanelDirection.rtl), which
      // would prove nothing about the parse step.
      Future<TextDirection> resolvedFor(String rawDirection) async {
        final provider = DashboardProvider(
          _DashboardSource(direction: rawDirection),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DashboardScreen(
                key: ValueKey(rawDirection),
                provider: provider,
              ),
            ),
          ),
        );
        await pumpUntilFound(tester, find.text('Orders'));
        final context = tester.element(find.text('Orders'));
        return Directionality.of(context);
      }

      expect(await resolvedFor('ltr'), TextDirection.ltr);
      expect(await resolvedFor('rtl'), TextDirection.rtl);
    });
  });

  group('RichEntryTile — the blockquote indent flips with direction', () {
    RichDocument doc(Map<String, dynamic> root) =>
        RichDocument.fromJson({'doc': root, 'text': ''}, 'test.__rich');

    final document = doc({
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {'type': 'text', 'text': 'plain'},
          ],
        },
        {
          'type': 'blockquote',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {'type': 'text', 'text': 'quoted'},
              ],
            },
          ],
        },
      ],
    });

    testWidgets(
      'LTR keeps the 12px left indent this widget always had — a fix that '
      'flips unconditionally regresses this exact assertion',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: RichEntryTile(document: document)),
          ),
        );

        final plainX = tester.getTopLeft(find.text('plain')).dx;
        final quotedX = tester.getTopLeft(find.text('quoted')).dx;

        expect(quotedX - plainX, closeTo(12, 0.5));
      },
    );

    testWidgets(
      'RTL moves the start-side indent off the left edge — the quoted '
      'text now sits flush with a plain paragraph, not indented from the left',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: RichEntryTile(document: document)),
            ),
          ),
        );

        final plainX = tester.getTopLeft(find.text('plain')).dx;
        final quotedX = tester.getTopLeft(find.text('quoted')).dx;

        expect(quotedX - plainX, closeTo(0, 0.5));
      },
    );
  });

  group('RichEntryTile — a rich node\'s textAlign is honoured', () {
    RichDocument doc(Map<String, dynamic> root) =>
        RichDocument.fromJson({'doc': root, 'text': ''}, 'test.__rich');

    testWidgets(
      'a paragraph and a heading both carry their published textAlign onto '
      'the rendered Text.rich',
      (tester) async {
        final document = doc({
          'type': 'doc',
          'content': [
            {
              'type': 'paragraph',
              'attrs': {'textAlign': 'center'},
              'content': [
                {'type': 'text', 'text': 'centered para'},
              ],
            },
            {
              'type': 'heading',
              'attrs': {'level': 1, 'textAlign': 'end'},
              'content': [
                {'type': 'text', 'text': 'end heading'},
              ],
            },
            {
              'type': 'paragraph',
              'attrs': {'textAlign': 'justify'},
              'content': [
                {'type': 'text', 'text': 'justified para'},
              ],
            },
          ],
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: RichEntryTile(document: document)),
          ),
        );

        expect(
          tester.widget<Text>(find.text('centered para')).textAlign,
          TextAlign.center,
        );
        expect(
          tester.widget<Text>(find.text('end heading')).textAlign,
          TextAlign.end,
        );
        expect(
          tester.widget<Text>(find.text('justified para')).textAlign,
          TextAlign.justify,
        );
      },
    );

    testWidgets(
      'an absent textAlign leaves Text.rich with no forced alignment',
      (tester) async {
        final document = doc({
          'type': 'doc',
          'content': [
            {
              'type': 'paragraph',
              'content': [
                {'type': 'text', 'text': 'unaligned'},
              ],
            },
          ],
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: RichEntryTile(document: document)),
          ),
        );

        expect(tester.widget<Text>(find.text('unaligned')).textAlign, isNull);
      },
    );

    testWidgets(
      'end visibly shifts the text toward the trailing edge — geometry, not '
      'just the constructor argument, proves the value actually renders',
      (tester) async {
        // `getTopLeft` on the `Text` widget measures the *paragraph's own
        // box*, which `Text.rich` sizes to the full 300px it was stretched
        // to regardless of textAlign — that box's position never moves.
        // `textAlign` only changes where the GLYPHS paint inside that box,
        // which `RenderParagraph.getBoxesForSelection` reports (the same
        // technique the design spec's own bidi measurement used, and what
        // `tester.tapOnText` relies on internally) — measuring the glyph,
        // not the box, is what actually proves textAlign rendered.
        Future<double> xForAlign(String align) async {
          final document = doc({
            'type': 'doc',
            'content': [
              {
                'type': 'paragraph',
                'attrs': {'textAlign': align},
                'content': [
                  {'type': 'text', 'text': 'hi'},
                ],
              },
            ],
          });
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(align),
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  child: RichEntryTile(document: document),
                ),
              ),
            ),
          );
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text('hi'),
          );
          return paragraph
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 2),
              )
              .first
              .left;
        }

        final startX = await xForAlign('start');
        final endX = await xForAlign('end');

        expect(
          endX,
          greaterThan(startX + 100),
          reason:
              'a short "hi" run should sit near the left under start and '
              'near the right under end, once the paragraph spans the full '
              '300px width',
        );
      },
    );
  });

  group('field_widgets — the repeater\'s two unsafe widgets flip', () {
    RepeaterComponent repeater({String? error}) =>
        SchemaComponent.fromJson(const {
              'type': 'repeater',
              'name': 'items',
              'children': [
                {'type': 'text', 'name': 'sku', 'label': 'SKU'},
              ],
              'config': {'addable': true, 'deletable': true, 'readOnly': false},
            }, 'test')
            as RepeaterComponent;

    Future<double> removeButtonRightEdge(
      WidgetTester tester,
      TextDirection direction,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: SizedBox(
                width: 300,
                child: Builder(
                  builder: (context) => FieldRegistry.defaults().build(
                    context,
                    repeater(),
                    FieldState(
                      value: [
                        {'sku': 'a'},
                      ],
                      onChanged: (_) {},
                      enabled: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return tester
          .getTopRight(find.byKey(const ValueKey('repeater.remove.0')))
          .dx;
    }

    testWidgets(
      'LTR keeps the remove control on the right, same as the original '
      'Alignment.centerRight',
      (tester) async {
        final rightEdge = await removeButtonRightEdge(
          tester,
          TextDirection.ltr,
        );
        // 300px container minus the row Card's own padding: the button's
        // right edge should sit near the container's right side.
        expect(rightEdge, greaterThan(200));
      },
    );

    testWidgets(
      'RTL moves the trailing edge to the left — the remove control is no '
      'longer stuck on the fixed right AlignmentDirectional.centerEnd left '
      'behind',
      (tester) async {
        final ltrRightEdge = await removeButtonRightEdge(
          tester,
          TextDirection.ltr,
        );
        final rtlRightEdge = await removeButtonRightEdge(
          tester,
          TextDirection.rtl,
        );

        expect(rtlRightEdge, lessThan(ltrRightEdge - 100));
      },
    );

    // Measured relative to `_ErrorText`'s OWN immediate `Padding` ancestor,
    // not the screen — the outer `RepeaterFieldWidget` Column also uses
    // `CrossAxisAlignment.start`, which (correctly, and independently of
    // this fix) repositions the whole padded box to the opposite side of
    // the column under RTL. Measuring against the screen's absolute x=0
    // conflates that pre-existing, direction-aware Column behaviour with
    // the one thing this test is actually about: which side the 12px inset
    // itself sits on. Isolating the immediate ancestor's box removes that
    // confound.
    Future<double> errorTextInsetFromOwnPadding(
      WidgetTester tester,
      TextDirection direction,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Builder(
                builder: (context) => FieldRegistry.defaults().build(
                  context,
                  repeater(),
                  const FieldState(
                    value: <Map<String, Object?>>[],
                    onChanged: _noop,
                    enabled: true,
                    error: 'مطلوب',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final paddingBox = tester.getTopLeft(
        find
            .ancestor(of: find.text('مطلوب'), matching: find.byType(Padding))
            .first,
      );
      final textBox = tester.getTopLeft(find.text('مطلوب'));
      return textBox.dx - paddingBox.dx;
    }

    testWidgets(
      'LTR keeps the error text 12px in from its own padding box\'s left '
      'edge, same as the original EdgeInsets.only(left: 12)',
      (tester) async {
        final inset = await errorTextInsetFromOwnPadding(
          tester,
          TextDirection.ltr,
        );
        expect(inset, closeTo(12, 0.5));
      },
    );

    testWidgets(
      'RTL moves the inset to the padding box\'s right edge — the text now '
      'sits flush with the LEFT of its own padding box instead of 12px in',
      (tester) async {
        final inset = await errorTextInsetFromOwnPadding(
          tester,
          TextDirection.rtl,
        );
        expect(inset, closeTo(0, 0.5));
      },
    );
  });

  // Fix round 1 (review findings on 45066d5).

  group('RichEntryTile — the blockquote border flips with the indent '
      '(review finding 1)', () {
    RichDocument doc(Map<String, dynamic> root) =>
        RichDocument.fromJson({'doc': root, 'text': ''}, 'test.__rich');

    testWidgets(
      'the border resolves to the same side as the start-side indent, in '
      'both directions — not left, unconditionally, which paints the bar '
      'under the text once the indent has moved to the right under RTL',
      (tester) async {
        final document = doc({
          'type': 'doc',
          'content': [
            {
              'type': 'blockquote',
              'content': [
                {
                  'type': 'paragraph',
                  'content': [
                    {'type': 'text', 'text': 'quoted'},
                  ],
                },
              ],
            },
          ],
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: RichEntryTile(document: document)),
          ),
        );

        final decoratedBox = tester.widget<DecoratedBox>(
          find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).border != null,
          ),
        );
        final border = (decoratedBox.decoration as BoxDecoration).border!;

        // `BoxBorder.dimensions` is what `RenderDecoratedBox` actually reads
        // (via `ShapeBorder.dimensions`/`getInnerPath`) to know how much
        // space the border occupies on each side — an `EdgeInsetsGeometry`
        // that a plain `Border` reports as already-resolved `EdgeInsets`
        // (direction-agnostic: `.resolve()` on those is a no-op) and a
        // `BorderDirectional` reports as `EdgeInsetsDirectional`, which
        // `.resolve(direction)` genuinely remaps. Resolving both directions
        // on the one border object under test is what actually distinguishes
        // the two: a plain `Border(left: ...)` keeps reporting the same
        // fixed left/right split for `rtl` as for `ltr`, which fails this
        // test's RTL half exactly the way finding 1 measured if the border
        // is ever hardcoded again.
        final ltrResolved = border.dimensions.resolve(TextDirection.ltr);
        expect(
          ltrResolved.left,
          3,
          reason: 'LTR: the bar stays on the left, same side as the indent',
        );
        expect(ltrResolved.right, 0);

        final rtlResolved = border.dimensions.resolve(TextDirection.rtl);
        expect(
          rtlResolved.right,
          3,
          reason:
              'RTL: the bar must move to the right, the same side the '
              'start-side indent moved to — not stay left, under the text',
        );
        expect(rtlResolved.left, 0);
      },
    );
  });

  group(
    'overlay routes inherit the screen\'s direction (review finding 2)',
    () {
      testWidgets(
        'the sort bottom sheet resolves the same direction as the screen '
        'that opened it',
        (tester) async {
          final resource = ResourceSchema(
            key: 'posts',
            labels: const ResourceLabels(singular: 'Post', plural: 'Posts'),
            sorts: const [ResourceSort(key: 'name', label: 'Name')],
            direction: PanelDirection.rtl,
          );
          final provider = ResourceListProvider(
            source: _ThrowingSource(),
            resource: resource,
          );

          await tester.pumpWidget(
            MaterialApp(home: ResourceListScreen(provider: provider)),
          );
          final screenDirection = Directionality.of(
            tester.element(find.text('Posts')),
          );

          await tester.tap(find.byIcon(Icons.sort));
          await tester.pumpAndSettle();

          final sheetDirection = Directionality.of(
            tester.element(find.text('Name')),
          );

          expect(screenDirection, TextDirection.rtl);
          expect(
            sheetDirection,
            screenDirection,
            reason:
                'a bottom sheet opened from an RTL screen must render RTL '
                'too — Directionality is a plain InheritedWidget, not an '
                'InheritedTheme, so a route pushed onto the Navigator does '
                'not inherit it on its own',
          );
        },
      );

      testWidgets(
        'the delete confirmation dialog resolves the same direction as the '
        'screen that opened it',
        (tester) async {
          final source = _DeletableRecordSource();
          final provider = ResourceViewProvider(
            source: source,
            // The delete affordance gates on the RECORD's own permissions
            // (`recordCan`), not this resource-level block — see
            // `ResourceViewScreen._actions()`'s doc — so only `direction`
            // matters here; `_DeletableRecordSource.record()` supplies the
            // per-record `delete: true` that actually shows the button.
            resource: ResourceSchema(
              key: 'posts',
              labels: const ResourceLabels(singular: 'Post', plural: 'Posts'),
              direction: PanelDirection.rtl,
            ),
            id: 1,
          );

          await tester.pumpWidget(
            MaterialApp(home: ResourceViewScreen(provider: provider)),
          );
          await pumpUntilFound(
            tester,
            find.byKey(const ValueKey('record.delete')),
          );
          final screenDirection = Directionality.of(
            tester.element(find.text('Post')),
          );

          await tester.tap(find.byKey(const ValueKey('record.delete')));
          await tester.pumpAndSettle();

          final dialogDirection = Directionality.of(
            tester.element(find.byType(AlertDialog)),
          );

          expect(screenDirection, TextDirection.rtl);
          expect(dialogDirection, screenDirection);
        },
      );

      // Fix round 2, review finding 2: the two above were the only overlays
      // with a test. Deleting the wrap on any of the five below left all 627
      // tests green — which is also how finding 1 (the select dropdown, last
      // in this group) got through. One test per overlay, so the rule is
      // "every overlay is covered", not "two representative ones are".

      testWidgets('the date and time pickers resolve the field\'s direction', (
        tester,
      ) async {
        await tester.pumpWidget(
          _rtlHost(
            Builder(
              builder: (context) => FieldRegistry.defaults().build(
                context,
                SchemaComponent.fromJson(const {
                  'type': 'datetime',
                  'name': 'published_at',
                  'label': 'Published',
                }, 'form[0]'),
                const FieldState(value: null, onChanged: _noop, enabled: true),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(InputDecorator));
        await tester.pumpAndSettle();
        expect(
          Directionality.of(tester.element(find.byType(DatePickerDialog))),
          TextDirection.rtl,
          reason:
              'showDatePicker mounts a route above the field, so it needs '
              'the explicit builder: wrap to inherit the panel direction',
        );

        // Through to the time picker: `datetime` chains the two, and each
        // carries its own `builder:`.
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(
          Directionality.of(tester.element(find.byType(TimePickerDialog))),
          TextDirection.rtl,
        );
      });

      testWidgets('the time field\'s picker resolves the field\'s direction', (
        tester,
      ) async {
        // A `time` field opens showTimePicker directly, with no date step in
        // front of it — a second overlay, and the rule this group settled on
        // is "every overlay is covered", not "a representative one is".
        await tester.pumpWidget(
          _rtlHost(
            Builder(
              builder: (context) => FieldRegistry.defaults().build(
                context,
                SchemaComponent.fromJson(const {
                  'type': 'time',
                  'name': 'opens_at',
                  'label': 'Opens at',
                }, 'form[0]'),
                const FieldState(value: null, onChanged: _noop, enabled: true),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(InputDecorator));
        await tester.pumpAndSettle();

        expect(
          Directionality.of(tester.element(find.byType(TimePickerDialog))),
          TextDirection.rtl,
        );
      });

      testWidgets(
        'the remote-select search sheet resolves the field\'s direction',
        (tester) async {
          await tester.pumpWidget(
            _rtlHost(
              Builder(
                builder: (context) => FieldRegistry.defaults().build(
                  context,
                  SchemaComponent.fromJson(const {
                    'type': 'select',
                    'name': 'company_id',
                    'label': 'Company',
                    'config': {'optionsUrl': '/api/mobile-panel/x/options'},
                  }, 'form[0]'),
                  FieldState(
                    value: null,
                    onChanged: _noop,
                    enabled: true,
                    searchOptions: (_) async => const OptionsPage(
                      options: [SelectOption(value: 3, label: 'Acme Ltd')],
                      hasMore: false,
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.byType(InkWell));
          await tester.pumpAndSettle();

          expect(
            Directionality.of(tester.element(find.text('Acme Ltd'))),
            TextDirection.rtl,
          );
        },
      );

      testWidgets(
        'the action confirmation dialog and the snack bar that follows it '
        'both resolve the screen\'s direction',
        (tester) async {
          final provider = ResourceViewProvider(
            source: _ActionRecordSource(),
            resource: ResourceSchema(
              key: 'posts',
              labels: const ResourceLabels(singular: 'Post', plural: 'Posts'),
              direction: PanelDirection.rtl,
            ),
            id: 1,
          );

          await tester.pumpWidget(
            MaterialApp(home: ResourceViewScreen(provider: provider)),
          );
          await _openActions(tester);

          await tester.tap(find.text('Archive'));
          await tester.pumpAndSettle();
          expect(
            Directionality.of(tester.element(find.byType(AlertDialog))),
            TextDirection.rtl,
            reason:
                'the action confirmation is a route, same as the delete '
                'dialog above',
          );

          await tester.tap(find.text('Yes, archive'));
          await tester.pumpAndSettle();

          // `_ActionRecordSource` answers with a failure message, so the
          // snack bar carries server text — the string most likely to be
          // Arabic, and the one the wrap exists for.
          expect(
            Directionality.of(
              tester.element(
                find.descendant(
                  of: find.byType(SnackBar),
                  matching: find.text('تعذر الأرشفة'),
                ),
              ),
            ),
            TextDirection.rtl,
          );
        },
      );

      testWidgets(
        'the select field\'s dropdown menu resolves the field\'s direction '
        '(review finding 1)',
        (tester) async {
          // Flutter's `_DropdownRoutePage` reads `Directionality.maybeOf`
          // from the ROUTE's context, and `_DropdownButtonState._handleTap`
          // captures only `InheritedTheme.capture(...)` — which
          // `Directionality` is not part of. So an RTL panel embedded in an
          // LTR host rendered its field RTL and its open option list LTR.
          await tester.pumpWidget(
            _rtlHost(
              Builder(
                builder: (context) => FieldRegistry.defaults().build(
                  context,
                  SchemaComponent.fromJson(const {
                    'type': 'select',
                    'name': 'status',
                    'label': 'Status',
                    'config': {
                      'options': [
                        {'value': 'a', 'label': 'ألفا'},
                        {'value': 'b', 'label': 'بيتا'},
                      ],
                    },
                  }, 'form[0]'),
                  const FieldState(value: 'a', onChanged: _noop, enabled: true),
                ),
              ),
            ),
          );

          await tester.tap(find.byType(DropdownButtonFormField<Object?>));
          await tester.pumpAndSettle();

          // `.last` is the menu route's copy: the closed button keeps its own
          // offstage IndexedStack items, and the route is pushed above them.
          final label = find.text('بيتا').last;

          expect(Directionality.of(tester.element(label)), TextDirection.rtl);

          // The fix has TWO halves and both need pinning — the half-pinned
          // fix is this project's signature defect (the padding that flipped
          // while its border didn't; the isolation applied before the lookup
          // that used the same string as a key). `DropdownMenuItem`'s default
          // `AlignmentDirectional.centerStart` resolves against the ROUTE's
          // direction, which is still the host's LTR, so without the
          // already-resolved `Alignment` a short Arabic label sits pinned to
          // the LEFT of a full-width menu while its own text runs RTL.
          //
          // Measured against the item's own box rather than the screen, so
          // this says "the label hugs the trailing edge", not "the label is
          // somewhere right of centre" — the menu is as wide as the field,
          // which is the full 800px test surface.
          final itemBox = find
              .ancestor(of: label, matching: find.byType(Align))
              .last;
          final itemLeft = tester.getTopLeft(itemBox).dx;
          final itemRight = tester.getTopRight(itemBox).dx;
          final labelLeft = tester.getTopLeft(label).dx;

          expect(
            labelLeft - itemLeft,
            greaterThan(itemRight - labelLeft),
            reason:
                'the option label must sit nearer its item box\'s trailing '
                '(right, under RTL) edge than its leading one — an '
                'AlignmentDirectional here would resolve in the route\'s '
                'LTR direction and pin it left',
          );
        },
      );
    },
  );

  // Fix round 2 (whole-branch review findings 1–3).

  group('every isolateBidi call site is pinned (review finding 2)', () {
    // The whole-branch review's central finding: the *helper* was proved by
    // measured glyph order and every *screen wrap* by a resolved-direction
    // read, but the SEAM between them was not tested at all — deleting the
    // `isolateBidi(...)` call from `EntryTile`, `ResourceCard._text`
    // or `RichEntryTile._span` left all 627 tests green. One test per call
    // site, below, so that deleting any one of them reds a named test.
    //
    // The two sites that were already pinned before this round keep their
    // existing homes rather than being duplicated here:
    //   - `semantic_badge.dart:49`  → `entry_registry_test.dart`
    //   - `dashboard_screen.dart:181/184` → `dashboard_screen_test.dart`
    //
    // Each assertion measures where the digit groups actually PAINT, never
    // that a U+2066 got inserted — a `contains(LRI)` assertion passes whether
    // or not the text renders in order. The baseline that `_phone` genuinely
    // reverses when NOT isolated is asserted once, in `bidi_text_test.dart`'s
    // positive case; it is a property of the string under RTL, so it is not
    // re-derived per widget here.

    testWidgets('EntryTile — an infolist text entry', (tester) async {
      await tester.pumpWidget(
        _rtlHost(const EntryTile(label: 'الهاتف', value: _phone)),
      );
      _expectPhoneGroupsInReadingOrder(tester);
    });

    testWidgets('ResourceCard._text — a card title', (tester) async {
      await tester.pumpWidget(
        _rtlHost(
          ResourceCard(
            layout: const CardLayout(titleField: 'phone'),
            record: ResourceRecord.fromJson(const {
              'id': 1,
              'phone': _phone,
            }, 'id'),
          ),
        ),
      );
      _expectPhoneGroupsInReadingOrder(tester);
    });

    testWidgets('RichEntryTile._span — a plain text leaf', (tester) async {
      await tester.pumpWidget(
        _rtlHost(
          RichEntryTile(
            document: _richDoc([
              {
                'type': 'paragraph',
                'content': [
                  {'type': 'text', 'text': _phone},
                ],
              },
            ]),
          ),
        ),
      );
      _expectPhoneGroupsInReadingOrder(tester);
    });

    testWidgets('RichEntryTile._span — the non-text inline fallback', (
      tester,
    ) async {
      // An inline node outside the closed vocabulary falls back to its
      // descendant text, and that fallback isolates too — a separate call
      // from the text-leaf one above, so it needs its own pin.
      await tester.pumpWidget(
        _rtlHost(
          RichEntryTile(
            document: _richDoc([
              {
                'type': 'paragraph',
                'content': [
                  {
                    'type': 'mention',
                    'content': [
                      {'type': 'text', 'text': _phone},
                    ],
                  },
                ],
              },
            ]),
          ),
        ),
      );
      _expectPhoneGroupsInReadingOrder(tester);
    });

    testWidgets('RichEntryTile._blockNode — the unknown-block fallback', (
      tester,
    ) async {
      await tester.pumpWidget(
        _rtlHost(
          RichEntryTile(
            document: _richDoc([
              {
                'type': 'callout',
                'content': [
                  {'type': 'text', 'text': _phone},
                ],
              },
            ]),
          ),
        ),
      );
      _expectPhoneGroupsInReadingOrder(tester);
    });
  });

  group('RichEntryTile\'s textAlign stretch degrades safely under unbounded '
      'width (review finding 5)', () {
    RichDocument doc(Map<String, dynamic> root) =>
        RichDocument.fromJson({'doc': root, 'text': ''}, 'test.__rich');

    RichDocument alignedParagraph(String text, String align) => doc({
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'attrs': {'textAlign': align},
          'content': [
            {'type': 'text', 'text': text},
          ],
        },
      ],
    });

    testWidgets('an unbounded horizontal parent renders a textAlign-carrying '
        'paragraph with no exception — RichEntryTile is exported public API, '
        'so a host embedding it in a horizontal scroller must not crash', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: RichEntryTile(
                document: alignedParagraph('unbounded', 'center'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('unbounded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a bounded parent still makes textAlign effective — the unbounded '
      'guard above must not regress the geometry finding 2 fixed',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                child: RichEntryTile(document: alignedParagraph('hi', 'end')),
              ),
            ),
          ),
        );

        final paragraph = tester.renderObject<RenderParagraph>(find.text('hi'));
        final left = paragraph
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 2),
            )
            .first
            .left;

        expect(
          left,
          greaterThan(100),
          reason:
              'an end-aligned "hi" should still sit near the right of a '
              '300px box — same geometry the earlier textAlign test '
              'measured, now re-checked after the unbounded-width guard',
        );
      },
    );
  });
}

void _noop(Object? value) {}

/// A [ResourceDataSource] whose `record()` alone answers, with one record
/// the current user may delete — the only two things the delete-dialog
/// direction test needs. Every other method throws, same shape as
/// `_ThrowingSource`.
class _DeletableRecordSource extends _ThrowingSource {
  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async =>
      ResourceRecord.fromJson(
        const {'id': 1, 'name': 'Post 1'},
        'id',
        permissions: const {'delete': true},
      );
}

/// A [ResourceDataSource] serving one record carrying a confirming action,
/// whose `runAction` fails with a server-written Arabic message — the two
/// overlays the action path opens (the confirmation dialog and the snack bar
/// reporting the outcome).
class _ActionRecordSource extends _ThrowingSource {
  @override
  Future<ResourceRecord> record(String resourceKey, Object id) async =>
      ResourceRecord.fromJson(
        const {'id': 1, 'name': 'Post 1'},
        'id',
        actions: const [
          {
            'name': 'archive',
            'label': 'Archive',
            'confirmation': {
              'heading': 'Archive this?',
              'submit': 'Yes, archive',
              'cancel': 'Never mind',
            },
          },
        ],
      );

  @override
  Future<ActionResult> runAction(
    String resourceKey,
    Object id,
    String action,
  ) async => const ActionFailed('تعذر الأرشفة');
}

/// A [ResourceDataSource] whose `panel()` alone answers, with one resource
/// and the given raw `direction` string — the only two things
/// `PanelIndexScreen`'s test needs.
class _PanelSource extends _ThrowingSource {
  _PanelSource({required this.direction});

  final String direction;

  @override
  Future<PanelSchema> panel() async => PanelSchema.fromJson({
    'version': 1,
    'panel': {'id': 'mobile', 'title': 'Panel', 'direction': direction},
    'resources': [
      {
        'key': 'posts',
        'labels': {'singular': 'Post', 'plural': 'Posts'},
      },
    ],
  });
}

/// A [ResourceDataSource] whose `dashboard()` alone answers, one stat widget
/// and the given raw `direction` string — the only two things
/// `DashboardScreen`'s test needs.
class _DashboardSource extends _ThrowingSource {
  _DashboardSource({required this.direction});

  final String direction;

  @override
  Future<DashboardData> dashboard() async => DashboardData.fromJson({
    'widgets': [
      {
        'type': 'stats',
        'stats': [
          {'label': 'Orders', 'value': '1'},
        ],
      },
    ],
    'direction': direction,
  });
}
