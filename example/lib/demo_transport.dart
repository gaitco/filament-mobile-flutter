import 'package:filament_mobile/filament_mobile.dart';

/// An in-memory [FilamentTransport] serving a small e-commerce panel.
/// The widget tree above it is the package's real one — only the wire is fake.
class DemoTransport implements FilamentTransport, FilamentUploadTransport {
  static const _perms = {
    'viewAny': true,
    'view': true,
    'create': true,
    'update': true,
    'delete': true,
  };

  // One plain action, one that confirms first — exercised on every record so
  // the example app's record screen always has a button to tap.
  static const List<Map<String, dynamic>> _actions = [
    {
      'name': 'feature',
      'label': 'Mark as featured',
      'color': 'success',
      'icon': null,
      'confirmation': null,
    },
    {
      'name': 'archive',
      'label': 'Archive',
      'color': 'warning',
      'icon': null,
      'confirmation': {
        'heading': 'Archive this?',
        'description': 'It will be hidden from the shop until restored.',
        'submit': 'Archive',
        'cancel': 'Cancel',
      },
    },
  ];

  static Map<String, dynamic> _resource(
    String key,
    String singular,
    String plural,
    String icon,
    String group,
  ) => {
    'key': key,
    'group': group,
    'labels': {'singular': singular, 'plural': plural, 'icon': icon},
    'permissions': _perms,
    'recordKey': 'id',
    'card': {
      'title': {'field': 'name'},
      'subtitle': {'field': 'summary'},
      'badges': [
        {
          'field': 'status',
          'colors': {'Active': 'success', 'Draft': 'warning'},
        },
      ],
      'meta': [
        {'field': 'updated_at', 'format': 'date'},
      ],
    },
    'search': {'enabled': true, 'placeholder': 'Search…'},
    'sorts': [
      {
        'key': 'updated_at',
        'label': 'Newest',
        'direction': 'desc',
        'default': true,
      },
      {'key': 'name', 'label': 'Name', 'direction': 'asc'},
    ],
    'form': [
      {
        'type': 'section',
        'label': '$singular details',
        'columns': 2,
        'children': [
          {
            'type': 'text',
            'name': 'name',
            'label': 'Name',
            'rules': {'required': true, 'max': 120},
          },
          {
            'type': 'select',
            'name': 'status',
            'label': 'Status',
            'rules': {'required': true},
            'config': {
              'options': [
                {'value': 'Active', 'label': 'Active'},
                {'value': 'Draft', 'label': 'Draft'},
              ],
            },
          },
          {
            'type': 'number',
            'name': 'price',
            'label': 'Price (USD)',
            'rules': {'required': true, 'numeric': true, 'min': 0},
          },
          {
            'type': 'textarea',
            'name': 'summary',
            'label': 'Summary',
            'columnSpan': 2,
            'rules': {'max': 500},
          },
          {
            'type': 'file',
            'name': 'photo',
            'label': 'Photo',
            'columnSpan': 2,
            'config': {'readOnly': false},
          },
          // Products only (P7): a radio field, so the example exercises
          // RadioFieldWidget against a real form, not just a unit test.
          if (key == 'products')
            {
              'type': 'radio',
              'name': 'shipping_speed',
              'label': 'Shipping speed',
              'columnSpan': 2,
              'rules': {'required': true},
              'config': {
                'options': [
                  {'value': 'standard', 'label': 'Standard (3-5 days)'},
                  {'value': 'express', 'label': 'Express (1-2 days)'},
                ],
              },
            },
          // Products only (P8): a colour field in a NON-DEFAULT format, so the
          // example exercises the never-convert property — a `hex` demo would
          // prove nothing, since `hex` is what the client would fall back to.
          if (key == 'products')
            {
              'type': 'color',
              'name': 'accent',
              'label': 'Accent colour',
              'columnSpan': 2,
              'rules': <String, dynamic>{},
              'config': {'format': 'rgb'},
            },
          // Products only (P8): a bounded time field, so the example exercises
          // a real minDate/maxDate rather than the nulls every date node
          // carried before this release.
          if (key == 'products')
            {
              'type': 'time',
              'name': 'dispatch_at',
              'label': 'Dispatch time',
              'columnSpan': 2,
              'rules': <String, dynamic>{},
              'config': {
                'minDate': '09:00',
                'maxDate': '17:00',
                'seconds': false,
              },
            },
          // Products only (P7): a tags field with a configured separator, so
          // the example exercises TagsFieldWidget's chips and suggestions —
          // the separator changes only what the *server* stores (see the
          // Laravel README's Tags section); the client's value is always a
          // List<String> regardless.
          if (key == 'products')
            {
              'type': 'tags',
              'name': 'labels',
              'label': 'Labels',
              'columnSpan': 2,
              'config': {
                'separator': ',',
                'suggestions': ['new', 'sale', 'bestseller'],
              },
            },
          // Products only (P7): a key/value field, so the example exercises
          // KeyValueFieldWidget's add/remove and its per-cell edit gates.
          if (key == 'products')
            {
              'type': 'keyvalue',
              'name': 'attributes',
              'label': 'Attributes',
              'columnSpan': 2,
              'config': {
                'addable': true,
                'deletable': true,
                'editableKeys': true,
                'editableValues': true,
                'keyLabel': 'Attribute',
                'valueLabel': 'Value',
                'keyPlaceholder': 'e.g. Material',
                'valuePlaceholder': 'e.g. Oak',
              },
            },
          // Products only: a JSON-column repeater (P6c), so the example
          // exercises RepeaterFieldWidget's add/remove affordances and
          // per-row validation against a real form, not just a unit test.
          // 'readOnly' is set explicitly — the real Laravel server only
          // ever publishes that key for a relationship repeater, so an
          // ordinary editable one relies on the client's own default,
          // which currently reads absent as read-only (see the Dart
          // README's Repeater section for the known gap this sidesteps).
          if (key == 'products')
            {
              'type': 'repeater',
              'name': 'variants',
              'label': 'Variants',
              'columnSpan': 2,
              'children': [
                {
                  'type': 'text',
                  'name': 'label',
                  'label': 'Variant',
                  'rules': {'required': true, 'max': 40},
                },
                {
                  'type': 'number',
                  'name': 'price',
                  'label': 'Price (USD)',
                  'rules': {'required': true, 'numeric': true, 'min': 0},
                },
              ],
              'config': {
                'addable': true,
                'deletable': true,
                'minItems': 0,
                'maxItems': 5,
                'itemLabel': null,
                'reorderable': false,
                'readOnly': false,
              },
            },
        ],
      },
    ],
    'infolist': [
      {'type': 'text_entry', 'name': 'name', 'label': 'Name'},
      // Products only (P6e): `summary` is rich there, refined to
      // `rich_entry` exactly as a real `HasRichContent` column would be —
      // the detail screen renders the document, the card beside it (see
      // `_row()`) reads the flattened `summary.__rich.text` instead of this
      // raw field. Every other resource keeps `summary` as plain text_entry,
      // which is the honest default for a column with no rich content.
      {
        'type': key == 'products' ? 'rich_entry' : 'text_entry',
        'name': 'summary',
        'label': 'Summary',
      },
      {'type': 'text_entry', 'name': 'status', 'label': 'Status'},
    ],
    // Products only: a relation manager (P6d), so the example exercises both
    // the record screen's relation section and the "See all" full list —
    // not just a unit test. 'relations' is always present, per the contract;
    // every other resource here publishes the empty array.
    'relations': [
      if (key == 'products')
        {
          'key': 'reviews',
          'label': 'Reviews',
          'card': {
            'title': {'field': 'author'},
            'subtitle': {'field': 'comment'},
          },
          'recordKey': 'id',
        },
    ],
  };

  static final Map<String, dynamic> _dashboard = {
    // `GET /dashboard` is its own direction carrier — it does not read
    // `/schema` — so an Arabic demo panel has to say so here too, or
    // `DEMO_SCREEN=dashboard` renders LTR under an `rtl` panel.
    'direction': 'rtl',
    'widgets': [
      {
        'type': 'stats',
        // The server publishes the widget's own getHeading()/getDescription()
        // — demo them so the stats card shows its title like the web panel.
        'heading': 'Store overview',
        'description': 'Orders at a glance',
        'stats': [
          {
            'label': 'Orders this week',
            'value': '1,340',
            'description': '12% increase',
            'descriptionIcon': 'heroicon-m-arrow-trending-up',
            'color': 'success',
            'chart': [7, 12, 9, 15, 22, 19, 27],
          },
          {
            'label': 'Refunds',
            'value': '3',
            'description': null,
            'descriptionIcon': null,
            'color': null,
            'chart': null,
          },
        ],
      },
      {
        'type': 'chart',
        'chartType': 'line',
        'heading': 'Revenue',
        'description': 'Last 6 months',
        'labels': ['Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'],
        'datasets': [
          {
            'label': 'Revenue',
            'data': [1200, 1900, 1500, 2100, 2400, 2200],
          },
        ],
      },
    ],
  };

  static final Map<String, dynamic> _schema = {
    'version': 1,
    'panel': {
      'id': 'demo',
      'title': 'Acme Admin',
      // 'rtl' so the demo exercises both P6f behaviours end to end: every
      // screen wraps itself in Directionality from this value with no host
      // wiring (see the Dart README's RTL and i18n section), and the
      // grouped-digit isolation below only has anything to prove under RTL.
      'locale': 'ar',
      'direction': 'rtl',
      'navigation': [
        {
          'group': 'Shop',
          'resources': ['products', 'categories'],
        },
        {
          'group': 'People',
          'resources': ['customers', 'staff'],
        },
      ],
    },
    'resources': [
      _resource('products', 'Product', 'Products', 'shopping-bag', 'Shop'),
      _resource('categories', 'Category', 'Categories', 'tag', 'Shop'),
      _resource('customers', 'Customer', 'Customers', 'users', 'People'),
      _resource('staff', 'Staff member', 'Staff', 'briefcase', 'People'),
    ],
  };

  /// A `<field>.__rich` sibling built from plain text — one paragraph, no
  /// marks. Real Laravel output runs the column through TipTap's own
  /// renderer (design spec, "But it must be Filament's own renderer"); this
  /// transport has no such column to convert, so it hand-authors the same
  /// small shape instead. Good enough for every product but the one below
  /// that exists to show the fuller vocabulary.
  static Map<String, dynamic> _plainRich(String text) => {
    'doc': {
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {'type': 'text', 'text': text},
          ],
        },
      ],
    },
    'text': text,
  };

  /// The one product with a genuinely rich document — a bold run and a
  /// link — so both screens exercise the full node/mark vocabulary
  /// (design spec, "Wire shape"), not just a paragraph of plain text.
  /// `onLinkTap` is wired in both examples (see `main_demo.dart`), so
  /// tapping "care guide" here actually does something.
  ///
  /// The second paragraph is P6f's own addition: real Arabic prose (content,
  /// not a client — the panel's own locale, generic e-commerce copy) ending
  /// in a grouped-digit phone number (the Ofcom-reserved fictional London
  /// range, never a real line), `textAlign: 'end'` so it exercises the node
  /// property P6e published and P6f finally honours, and the one place in
  /// this demo where a reader can see `isolateGroupedDigits` do its job: the
  /// digits keep their own left-to-right group order inside the surrounding
  /// right-to-left sentence instead of the bidi algorithm reordering them.
  static const Map<String, dynamic> _auroraRich = {
    'doc': {
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {'type': 'text', 'text': 'Warm-dim brass lamp with a '},
            {
              'type': 'text',
              'text': 'hand-rubbed',
              'marks': [
                {'type': 'bold'},
              ],
            },
            {'type': 'text', 'text': ' finish. See the '},
            {
              'type': 'text',
              'text': 'care guide',
              'marks': [
                {
                  'type': 'link',
                  'attrs': {'href': 'https://example.test/care'},
                },
              ],
            },
            {'type': 'text', 'text': ' for details.'},
          ],
        },
        {
          'type': 'paragraph',
          'attrs': {'textAlign': 'end'},
          'content': [
            {
              'type': 'text',
              'text': 'للاستفسارات تواصل معنا على +44 20 7946 0958.',
            },
          ],
        },
      ],
    },
    'text':
        'Warm-dim brass lamp with a hand-rubbed finish. See the care '
        'guide for details. للاستفسارات تواصل معنا على +44 20 7946 0958.',
  };

  static List<Map<String, dynamic>> _rows(String key) => switch (key) {
    'products' => [
      {
        ..._row(1, 'Aurora Desk Lamp', 'Warm-dim brass lamp', 'Active', 89),
        'summary.__rich': _auroraRich,
        // Seeds the repeater's rows so opening the record for edit shows
        // them prefilled, not just an empty template with an Add button.
        'variants': [
          {'label': 'Brass', 'price': 89},
          {'label': 'Matte black', 'price': 95},
        ],
        // P7: seeds the radio, tags and key/value fields so opening this
        // record for edit shows all three prefilled rather than empty.
        'shipping_speed': 'standard',
        'labels': ['new', 'bestseller'],
        'attributes': {'Material': 'Brass', 'Finish': 'Hand-rubbed'},
      },
      {
        ..._row(2, 'Linen Throw', 'Stonewashed, 130×170', 'Active', 54),
        'summary.__rich': _plainRich('Stonewashed, 130×170'),
      },
      {
        ..._row(3, 'Oak Side Table', 'Solid oak, oiled finish', 'Draft', 149),
        'summary.__rich': _plainRich('Solid oak, oiled finish'),
      },
      {
        ..._row(
          4,
          'Ceramic Vase Set',
          'Set of three, matte glaze',
          'Active',
          42,
        ),
        'summary.__rich': _plainRich('Set of three, matte glaze'),
      },
      {
        ..._row(5, 'Wool Runner', 'Hand-loomed, 80×300', 'Draft', 210),
        'summary.__rich': _plainRich('Hand-loomed, 80×300'),
      },
      {
        ..._row(6, 'Glass Carafe', 'Borosilicate, 1.2 L', 'Active', 28),
        'summary.__rich': _plainRich('Borosilicate, 1.2 L'),
      },
    ],
    'categories' => [
      _row(1, 'Lighting', 'Lamps and fixtures', 'Active', 0),
      _row(2, 'Textiles', 'Throws, rugs, cushions', 'Active', 0),
    ],
    'customers' => [
      _row(1, 'Nora Malek', 'nora@example.com', 'Active', 0),
      _row(2, 'Omar Saleh', 'omar@example.com', 'Active', 0),
    ],
    _ => [_row(1, 'Dana Yousef', 'Store manager', 'Active', 0)],
  };

  static Map<String, dynamic> _row(
    int id,
    String name,
    String summary,
    String status,
    num price,
  ) => {
    'id': id,
    'name': name,
    'summary': summary,
    'status': status,
    'price': price,
    'updated_at': '2026-08-0${(id % 6) + 1}T10:00:00Z',
  };

  // 'products'/'reviews' is the only populated relation this demo serves —
  // five rows so pagination (per page, below) genuinely has a second page to
  // fetch, rather than a single page that never shows "See all".
  static const List<Map<String, dynamic>> _reviews = [
    {'id': 1, 'author': 'Mona K.', 'comment': 'Great lamp, sturdy base.'},
    {
      'id': 2,
      'author': 'Sam R.',
      'comment': 'Exactly as pictured, fast shipping.',
    },
    {'id': 3, 'author': 'Ben T.', 'comment': 'Good value for the price.'},
    {'id': 4, 'author': 'Priya N.', 'comment': 'Would buy again.'},
    {'id': 5, 'author': 'Leo M.', 'comment': 'Packaging could be better.'},
  ];

  static List<Map<String, dynamic>> _relationRows(
    String resourceKey,
    String relationKey,
  ) => switch ((resourceKey, relationKey)) {
    ('products', 'reviews') => _reviews,
    _ => const [],
  };

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    if (path.endsWith('/schema')) return _schema;
    if (path.endsWith('/dashboard')) return _dashboard;

    // /api/mobile-panel/{resource}[/{id}[/relations/{relation}]]
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    final key = parts[2];

    // .../{resource}/{id}/relations/{relation} — checked before the plain
    // record branch below, since both shapes have more than 3 segments.
    if (parts.length > 5 && parts[4] == 'relations') {
      final allRows = _relationRows(key, parts[5]);
      const perPage = 3;
      final page = int.tryParse(query?['page']?.toString() ?? '1') ?? 1;
      final start = (page - 1) * perPage;
      final pageRows = start >= allRows.length
          ? const <Map<String, dynamic>>[]
          : allRows.sublist(start, (start + perPage).clamp(0, allRows.length));
      return {
        'data': pageRows,
        'meta': {
          'current_page': page,
          'last_page': (allRows.length / perPage).ceil().clamp(1, 999),
          'per_page': perPage,
          'total': allRows.length,
        },
      };
    }

    if (parts.length > 3) {
      final id = int.parse(parts[3]);
      return {
        'data': _rows(key).firstWhere((r) => r['id'] == id),
        'permissions': const {'view': true, 'update': true, 'delete': true},
        'actions': _actions,
      };
    }
    final rows = _rows(key);
    return {
      'data': rows,
      'meta': {
        'current_page': 1,
        'last_page': 1,
        'per_page': 20,
        'total': rows.length,
      },
    };
  }

  @override
  Future<FilamentResponse> post(String path, Map<String, dynamic> body) async {
    // .../{resource}/{record}/actions/{action} — the run-action path.
    if (path.contains('/actions/')) {
      final action = path.split('/').last;
      final message = switch (action) {
        'feature' => 'Marked as featured.',
        'archive' => 'Archived.',
        _ => null,
      };
      return FilamentResponse(statusCode: 200, body: {'message': message});
    }

    return const FilamentResponse(
      statusCode: 200,
      body: {
        'data': {'id': 99},
      },
    );
  }

  @override
  Future<FilamentResponse> put(String path, Map<String, dynamic> body) async =>
      const FilamentResponse(
        statusCode: 200,
        body: {
          'data': {'id': 1},
        },
      );

  @override
  Future<FilamentResponse> delete(String path) async =>
      const FilamentResponse(statusCode: 200, body: {});

  @override
  Future<FilamentResponse> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    String field = 'file',
  }) async =>
      FilamentResponse(statusCode: 200, body: {'path': 'demo/$filename'});
}
