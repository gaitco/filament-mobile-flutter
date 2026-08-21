import 'package:filament_mobile/filament_mobile.dart';

/// `--dart-define=DEMO_DIR=ltr` serves a left-to-right, English panel instead.
///
/// Defaults to **rtl**, and that default is load-bearing rather than a
/// preference: the Arabic panel is what exercises both P6f behaviours end to
/// end — every screen wrapping itself in `Directionality` from this value with
/// no host wiring, and the grouped-digit isolation, which has nothing to prove
/// under LTR. Flipping the default would quietly stop demonstrating the feature
/// the fixture was built for.
///
/// `ltr` exists for the README captures, where an English audience reading a
/// right-to-left screenshot of English labels learns the wrong thing about the
/// package. Both directions are real panels; neither is a mock.
const demoDirection = String.fromEnvironment('DEMO_DIR', defaultValue: 'rtl');

/// Kept in step with [demoDirection] rather than set independently: an `ltr`
/// panel still labelled `ar` would be a panel this server would never emit.
const _demoLocale = demoDirection == 'rtl' ? 'ar' : 'en';

/// Serves each user-facing string in the panel's own locale, as a real
/// Filament server would: an `ar` panel publishes Arabic labels and content,
/// an `en` panel the English the README's LTR captures depend on.
String _t(String en, String ar) => _demoLocale == 'ar' ? ar : en;

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
  // Not const: the labels go through `_t` like every other served string.
  static final List<Map<String, dynamic>> _actions = [
    {
      'name': 'feature',
      'label': _t('Mark as featured', 'تمييز كمميز'),
      'color': 'success',
      'icon': null,
      'confirmation': null,
    },
    {
      'name': 'archive',
      'label': _t('Archive', 'أرشفة'),
      'color': 'warning',
      'icon': null,
      'confirmation': {
        'heading': _t('Archive this?', 'أرشفة هذا العنصر؟'),
        'description': _t(
          'It will be hidden from the shop until restored.',
          'سيُخفى من المتجر حتى تتم استعادته.',
        ),
        'submit': _t('Archive', 'أرشفة'),
        'cancel': _t('Cancel', 'إلغاء'),
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
      // A leading image on every card, falling back to the title's initial
      // for a row whose `photo` is null — the same degradation a real
      // media-library column exercises.
      'leading': {'type': 'image', 'field': 'photo', 'fallback': 'initials'},
      'badges': [
        {
          'field': 'status',
          // Keyed by the status VALUE, so the keys move with the option
          // values below and the `status` each record row carries — all
          // three are the same served string and must translate identically.
          'colors': {
            _t('Active', 'نشط'): 'success',
            _t('Draft', 'مسودة'): 'warning',
          },
        },
      ],
      'meta': [
        {'field': 'updated_at', 'format': 'date'},
      ],
    },
    'search': {'enabled': true, 'placeholder': _t('Search…', 'بحث…')},
    'sorts': [
      {
        'key': 'updated_at',
        'label': _t('Newest', 'الأحدث'),
        'direction': 'desc',
        'default': true,
      },
      {'key': 'name', 'label': _t('Name', 'الاسم'), 'direction': 'asc'},
    ],
    'form': [
      {
        'type': 'section',
        'label': _t('$singular details', 'تفاصيل $singular'),
        'columns': 2,
        'children': [
          {
            'type': 'text',
            'name': 'name',
            'label': _t('Name', 'الاسم'),
            'rules': {'required': true, 'max': 120},
          },
          {
            'type': 'select',
            'name': 'status',
            'label': _t('Status', 'الحالة'),
            'rules': {'required': true},
            'config': {
              'options': [
                {'value': _t('Active', 'نشط'), 'label': _t('Active', 'نشط')},
                {'value': _t('Draft', 'مسودة'), 'label': _t('Draft', 'مسودة')},
              ],
            },
          },
          {
            'type': 'number',
            'name': 'price',
            'label': _t('Price (USD)', 'السعر (دولار)'),
            'rules': {'required': true, 'numeric': true, 'min': 0},
          },
          {
            'type': 'textarea',
            'name': 'summary',
            'label': _t('Summary', 'الملخص'),
            'columnSpan': 2,
            'rules': {'max': 500},
          },
          {
            'type': 'file',
            'name': 'photo',
            'label': _t('Photo', 'الصورة'),
            'columnSpan': 2,
            'config': {'readOnly': false},
          },
          // Products only (P7): a radio field, so the example exercises
          // RadioFieldWidget against a real form, not just a unit test.
          if (key == 'products')
            {
              'type': 'radio',
              'name': 'shipping_speed',
              'label': _t('Shipping speed', 'سرعة الشحن'),
              'columnSpan': 2,
              'rules': {'required': true},
              'config': {
                'options': [
                  // Values stay machine slugs; only the labels are served
                  // in the panel's locale.
                  {
                    'value': 'standard',
                    'label': _t('Standard (3-5 days)', 'عادي (3-5 أيام)'),
                  },
                  {
                    'value': 'express',
                    'label': _t('Express (1-2 days)', 'سريع (1-2 يوم)'),
                  },
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
              'label': _t('Accent colour', 'اللون المميز'),
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
              'label': _t('Dispatch time', 'وقت الإرسال'),
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
              'label': _t('Labels', 'الوسوم'),
              'columnSpan': 2,
              'config': {
                'separator': ',',
                // Content, not chrome: an Arabic shop's tags are Arabic, and
                // the seeded record's `labels` below move with these.
                'suggestions': _demoLocale == 'ar'
                    ? ['جديد', 'تخفيضات', 'الأكثر مبيعاً']
                    : ['new', 'sale', 'bestseller'],
              },
            },
          // Products only (P7): a key/value field, so the example exercises
          // KeyValueFieldWidget's add/remove and its per-cell edit gates.
          if (key == 'products')
            {
              'type': 'keyvalue',
              'name': 'attributes',
              'label': _t('Attributes', 'السمات'),
              'columnSpan': 2,
              'config': {
                'addable': true,
                'deletable': true,
                'editableKeys': true,
                'editableValues': true,
                'keyLabel': _t('Attribute', 'السمة'),
                'valueLabel': _t('Value', 'القيمة'),
                'keyPlaceholder': _t('e.g. Material', 'مثال: المادة'),
                'valuePlaceholder': _t('e.g. Oak', 'مثال: البلوط'),
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
              'label': _t('Variants', 'المتغيرات'),
              'columnSpan': 2,
              'children': [
                {
                  'type': 'text',
                  'name': 'label',
                  'label': _t('Variant', 'المتغير'),
                  'rules': {'required': true, 'max': 40},
                },
                {
                  'type': 'number',
                  'name': 'price',
                  'label': _t('Price (USD)', 'السعر (دولار)'),
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
      {'type': 'image_entry', 'name': 'photo', 'label': _t('Photo', 'الصورة')},
      {'type': 'text_entry', 'name': 'name', 'label': _t('Name', 'الاسم')},
      // Products only (P6e): `summary` is rich there, refined to
      // `rich_entry` exactly as a real `HasRichContent` column would be —
      // the detail screen renders the document, the card beside it (see
      // `_row()`) reads the flattened `summary.__rich.text` instead of this
      // raw field. Every other resource keeps `summary` as plain text_entry,
      // which is the honest default for a column with no rich content.
      {
        'type': key == 'products' ? 'rich_entry' : 'text_entry',
        'name': 'summary',
        'label': _t('Summary', 'الملخص'),
      },
      {'type': 'text_entry', 'name': 'status', 'label': _t('Status', 'الحالة')},
    ],
    // Products only: a relation manager (P6d), so the example exercises both
    // the record screen's relation section and the "See all" full list —
    // not just a unit test. 'relations' is always present, per the contract;
    // every other resource here publishes the empty array.
    'relations': [
      if (key == 'products')
        {
          'key': 'reviews',
          'label': _t('Reviews', 'المراجعات'),
          'card': {
            'title': {'field': 'author'},
            'subtitle': {'field': 'comment'},
          },
          'recordKey': 'id',
          // P9: the child RESOURCE's key, which is what makes this relation
          // writable rather than a read path. A real server publishes it only
          // when exactly one registered resource owns the related model, and
          // its absence is how every relation looked before 0.8.0 — so
          // omitting it here left the demo unable to show the write
          // affordances at all, which is why no screenshot of them existed.
          'resource': 'reviews',
        },
    ],
  };

  static final Map<String, dynamic> _dashboard = {
    // `GET /dashboard` is its own direction carrier — it does not read
    // `/schema` — so an Arabic demo panel has to say so here too, or
    // `DEMO_SCREEN=dashboard` renders LTR under an `rtl` panel.
    'direction': demoDirection,
    'widgets': [
      {
        'type': 'stats',
        // The server publishes the widget's own getHeading()/getDescription()
        // — demo them so the stats card shows its title like the web panel.
        'heading': _t('Store overview', 'نظرة عامة على المتجر'),
        'description': _t('Orders at a glance', 'الطلبات في لمحة'),
        'stats': [
          {
            'label': _t('Orders this week', 'الطلبات هذا الأسبوع'),
            'value': '1,340',
            'description': _t('12% increase', 'زيادة 12%'),
            'descriptionIcon': 'heroicon-m-arrow-trending-up',
            'color': 'success',
            'chart': [7, 12, 9, 15, 22, 19, 27],
          },
          {
            'label': _t('Refunds', 'المرتجعات'),
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
        'heading': _t('Revenue', 'الإيرادات'),
        'description': _t('Last 6 months', 'آخر 6 أشهر'),
        'labels': _demoLocale == 'ar'
            ? ['مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس']
            : ['Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'],
        'datasets': [
          {
            'label': _t('Revenue', 'الإيرادات'),
            'data': [1200, 1900, 1500, 2100, 2400, 2200],
          },
          {
            'label': _t('Costs', 'التكاليف'),
            'data': [800, 1100, 950, 1300, 1500, 1400],
          },
        ],
      },
      {
        'type': 'chart',
        'chartType': 'bar',
        'heading': _t('Orders per channel', 'الطلبات حسب القناة'),
        'description': null,
        'labels': _demoLocale == 'ar'
            ? ['مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس']
            : ['Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'],
        'datasets': [
          {
            'label': _t('Online', 'عبر الإنترنت'),
            'data': [42, 55, 48, 61, 70, 66],
          },
          {
            'label': _t('In store', 'في المتجر'),
            'data': [30, 28, 35, 31, 38, 40],
          },
        ],
      },
      {
        'type': 'chart',
        'chartType': 'pie',
        'heading': _t('Sales by category', 'المبيعات حسب الفئة'),
        'description': null,
        'labels': _demoLocale == 'ar'
            ? ['ملابس', 'أحذية', 'إكسسوارات', 'منزل']
            : ['Apparel', 'Footwear', 'Accessories', 'Home'],
        'datasets': [
          {
            'label': _t('Sales', 'المبيعات'),
            'data': [44, 26, 18, 12],
          },
        ],
      },
      {
        'type': 'chart',
        'chartType': 'doughnut',
        'heading': _t('Traffic sources', 'مصادر الزيارات'),
        'description': null,
        'labels': _demoLocale == 'ar'
            ? ['بحث', 'مباشر', 'تواصل اجتماعي', 'إحالة']
            : ['Search', 'Direct', 'Social', 'Referral'],
        'datasets': [
          {
            'label': _t('Visits', 'الزيارات'),
            'data': [52, 23, 15, 10],
          },
        ],
      },
      {
        'type': 'chart',
        'chartType': 'radar',
        'heading': _t('Support health', 'صحة الدعم'),
        'description': null,
        'labels': _demoLocale == 'ar'
            ? ['السرعة', 'الجودة', 'الوصول', 'الجاهزية', 'رضا العملاء']
            : ['Speed', 'Quality', 'Reach', 'Uptime', 'CSAT'],
        'datasets': [
          {
            'label': _t('This quarter', 'هذا الربع'),
            'data': [70, 82, 65, 90, 77],
          },
          {
            'label': _t('Last quarter', 'الربع الماضي'),
            'data': [60, 75, 58, 84, 70],
          },
        ],
      },
      {
        'type': 'chart',
        'chartType': 'scatter',
        'heading': _t('Order value vs. day', 'قيمة الطلب حسب اليوم'),
        'description': null,
        'labels': _demoLocale == 'ar'
            ? ['اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت', 'أحد']
            : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
        'datasets': [
          {
            'label': _t('Avg. order', 'متوسط الطلب'),
            'data': [85, 120, 95, 140, 160, 210, 175],
          },
        ],
      },
    ],
  };

  static final Map<String, dynamic> _schema = {
    'version': 1,
    'panel': {
      'id': 'demo',
      'title': _t('Acme Admin', 'إدارة أكمي'),
      // 'rtl' so the demo exercises both P6f behaviours end to end: every
      // screen wraps itself in Directionality from this value with no host
      // wiring (see the Dart README's RTL and i18n section), and the
      // grouped-digit isolation below only has anything to prove under RTL.
      'locale': _demoLocale,
      'direction': demoDirection,
      'navigation': [
        {
          'group': _t('Shop', 'المتجر'),
          'resources': ['products', 'categories'],
        },
        {
          'group': _t('People', 'الأشخاص'),
          'resources': ['customers', 'staff'],
        },
      ],
    },
    'resources': [
      _resource(
        'products',
        _t('Product', 'منتج'),
        _t('Products', 'المنتجات'),
        'shopping-bag',
        _t('Shop', 'المتجر'),
      ),
      _resource(
        'categories',
        _t('Category', 'فئة'),
        _t('Categories', 'الفئات'),
        'tag',
        _t('Shop', 'المتجر'),
      ),
      _resource(
        'customers',
        _t('Customer', 'عميل'),
        _t('Customers', 'العملاء'),
        'users',
        _t('People', 'الأشخاص'),
      ),
      _resource(
        'staff',
        _t('Staff member', 'موظف'),
        _t('Staff', 'الموظفون'),
        'briefcase',
        _t('People', 'الأشخاص'),
      ),
      _reviewsResource,
    ],
  };

  /// The child resource behind the `reviews` relation — published so the
  /// relation is WRITABLE (see the `resource` key on the relation descriptor).
  ///
  /// Deliberately NOT built through `_resource()`: that factory carries the
  /// products form with its eleven field types, and a review's create/edit
  /// form should be the three fields a review actually has. A relation row's
  /// form is the child resource's own, reused whole, so this is what a reviewer
  /// sees on Add and on a row's edit.
  ///
  /// Absent from `navigation` on purpose. A child resource reachable only
  /// through its parent is an ordinary shape — Filament resources are not
  /// obliged to be navigable — and listing it in the index would put a
  /// top-level "Reviews" entry beside Products for no reason.
  static final Map<String, dynamic> _reviewsResource = {
    'key': 'reviews',
    'labels': {
      'singular': _t('Review', 'مراجعة'),
      'plural': _t('Reviews', 'المراجعات'),
      'icon': 'star',
    },
    // All three, because the point of the fixture is the affordances: Add
    // comes from `create`, the per-row pencil from `update`, the bin from
    // `delete`. A false flag renders NO control rather than a disabled one, so
    // a partial set here would quietly under-demonstrate the feature.
    'permissions': _perms,
    'recordKey': 'id',
    'card': {
      'title': {'field': 'author'},
      'subtitle': {'field': 'comment'},
    },
    'search': {'enabled': false},
    'sorts': <Map<String, dynamic>>[],
    'form': [
      {
        'type': 'text',
        'name': 'author',
        'label': _t('Author', 'الكاتب'),
        'rules': {'required': true, 'max': 80},
      },
      {
        'type': 'textarea',
        'name': 'comment',
        'label': _t('Comment', 'التعليق'),
        'rules': {'required': true, 'max': 400},
      },
      {
        'type': 'select',
        'name': 'rating',
        'label': _t('Rating', 'التقييم'),
        'rules': {'required': true},
        'config': {
          'options': [
            {'value': '5', 'label': _t('5 — Excellent', '5 — ممتاز')},
            {'value': '4', 'label': _t('4 — Good', '4 — جيد')},
            {'value': '3', 'label': _t('3 — Fair', '3 — مقبول')},
            {'value': '2', 'label': _t('2 — Poor', '2 — ضعيف')},
            {'value': '1', 'label': _t('1 — Bad', '1 — سيئ')},
          ],
        },
      },
    ],
    // Without an infolist the record screen renders "Nothing here yet" over
    // a review that plainly has content — the child resource is opened
    // through the relation's rows, so it needs entries like any other.
    'infolist': [
      {'type': 'text_entry', 'name': 'author', 'label': _t('Author', 'الكاتب')},
      {
        'type': 'text_entry',
        'name': 'comment',
        'label': _t('Comment', 'التعليق'),
      },
      {
        'type': 'text_entry',
        'name': 'rating',
        'label': _t('Rating', 'التقييم'),
      },
    ],
    'relations': <Map<String, dynamic>>[],
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
  /// The first paragraph is served in the panel's locale like every other
  /// string, which is why this map cannot stay `const`. The second paragraph
  /// is P6f's own addition: real Arabic prose (content,
  /// not a client — the panel's own locale, generic e-commerce copy) ending
  /// in a grouped-digit phone number (the Ofcom-reserved fictional London
  /// range, never a real line), `textAlign: 'end'` so it exercises the node
  /// property P6e published and P6f finally honours, and the one place in
  /// this demo where a reader can see `isolateGroupedDigits` do its job: the
  /// digits keep their own left-to-right group order inside the surrounding
  /// right-to-left sentence instead of the bidi algorithm reordering them.
  static final Map<String, dynamic> _auroraRich = {
    'doc': {
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {
              'type': 'text',
              'text': _t(
                'Warm-dim brass lamp with a ',
                'مصباح نحاسي بإضاءة دافئة وتشطيب ',
              ),
            },
            {
              'type': 'text',
              'text': _t('hand-rubbed', 'مصقول يدوياً'),
              'marks': [
                {'type': 'bold'},
              ],
            },
            {'type': 'text', 'text': _t(' finish. See the ', '. راجع ')},
            {
              'type': 'text',
              'text': _t('care guide', 'دليل العناية'),
              'marks': [
                {
                  'type': 'link',
                  'attrs': {'href': 'https://example.test/care'},
                },
              ],
            },
            {'type': 'text', 'text': _t(' for details.', ' للتفاصيل.')},
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
        '${_t('Warm-dim brass lamp with a hand-rubbed finish. See the care '
            'guide for details. ', 'مصباح نحاسي بإضاءة دافئة وتشطيب مصقول يدوياً. راجع دليل العناية '
            'للتفاصيل. ')}للاستفسارات تواصل معنا على +44 20 7946 0958.',
  };

  static List<Map<String, dynamic>> _rows(String key) => switch (key) {
    // The child resource reads its own records through the ordinary record
    // endpoint, exactly as the real client does: `RelationListScreen`'s row
    // edit pushes the CHILD resource's form, and that form prefills from
    // `GET /reviews/{id}` rather than from the relation row it was tapped on.
    // Without this case the edit form would open blank on a row that plainly
    // has content.
    'reviews' => _reviews,
    'products' => [
      {
        ..._row(
          1,
          _t('Aurora Desk Lamp', 'مصباح أورورا المكتبي'),
          _t('Warm-dim brass lamp', 'مصباح نحاسي بإضاءة دافئة'),
          _t('Active', 'نشط'),
          89,
        ),
        'summary.__rich': _auroraRich,
        // Seeds the repeater's rows so opening the record for edit shows
        // them prefilled, not just an empty template with an Add button.
        'variants': [
          {'label': _t('Brass', 'نحاسي'), 'price': 89},
          {'label': _t('Matte black', 'أسود مطفي'), 'price': 95},
        ],
        // P7: seeds the radio, tags and key/value fields so opening this
        // record for edit shows all three prefilled rather than empty.
        'shipping_speed': 'standard',
        'labels': _demoLocale == 'ar'
            ? ['جديد', 'الأكثر مبيعاً']
            : ['new', 'bestseller'],
        'attributes': _demoLocale == 'ar'
            ? {'المادة': 'نحاس', 'التشطيب': 'مصقول يدوياً'}
            : {'Material': 'Brass', 'Finish': 'Hand-rubbed'},
      },
      {
        ..._row(
          2,
          _t('Linen Throw', 'غطاء كتان'),
          _t('Stonewashed, 130×170', 'غسيل حجري، 130×170'),
          _t('Active', 'نشط'),
          54,
        ),
        'summary.__rich': _plainRich(
          _t('Stonewashed, 130×170', 'غسيل حجري، 130×170'),
        ),
      },
      {
        ..._row(
          3,
          _t('Oak Side Table', 'طاولة جانبية من البلوط'),
          _t('Solid oak, oiled finish', 'بلوط مصمت بتشطيب مزيت'),
          _t('Draft', 'مسودة'),
          149,
        ),
        'summary.__rich': _plainRich(
          _t('Solid oak, oiled finish', 'بلوط مصمت بتشطيب مزيت'),
        ),
      },
      {
        ..._row(
          4,
          _t('Ceramic Vase Set', 'طقم مزهريات سيراميك'),
          _t('Set of three, matte glaze', 'ثلاث قطع بطلاء مطفي'),
          _t('Active', 'نشط'),
          42,
        ),
        'summary.__rich': _plainRich(
          _t('Set of three, matte glaze', 'ثلاث قطع بطلاء مطفي'),
        ),
      },
      {
        ..._row(
          5,
          _t('Wool Runner', 'سجادة صوف طويلة'),
          _t('Hand-loomed, 80×300', 'نسج يدوي، 80×300'),
          _t('Draft', 'مسودة'),
          210,
        ),
        'summary.__rich': _plainRich(
          _t('Hand-loomed, 80×300', 'نسج يدوي، 80×300'),
        ),
      },
      {
        ..._row(
          6,
          _t('Glass Carafe', 'إبريق زجاجي'),
          _t('Borosilicate, 1.2 L', 'بوروسيليكات، 1.2 لتر'),
          _t('Active', 'نشط'),
          28,
        ),
        'summary.__rich': _plainRich(
          _t('Borosilicate, 1.2 L', 'بوروسيليكات، 1.2 لتر'),
        ),
      },
      // Rows 7-10 exist so the list genuinely paginates (see `_listPerPage`):
      // six rows fit inside one page of four with a second page of two, which
      // never exercises a third fetch.
      {
        ..._row(
          7,
          _t('Rattan Pendant', 'مصباح راتان معلق'),
          _t('Hand-woven shade, 45 cm', 'غطاء منسوج يدوياً، 45 سم'),
          _t('Active', 'نشط'),
          75,
        ),
        'summary.__rich': _plainRich(
          _t('Hand-woven shade, 45 cm', 'غطاء منسوج يدوياً، 45 سم'),
        ),
      },
      {
        ..._row(
          8,
          _t('Marble Trivet', 'قاعدة رخامية'),
          _t('Carrara, hexagonal', 'كارارا، سداسية'),
          _t('Active', 'نشط'),
          24,
        ),
        'summary.__rich': _plainRich(
          _t('Carrara, hexagonal', 'كارارا، سداسية'),
        ),
      },
      {
        ..._row(
          9,
          _t('Cedar Shelf', 'رف أرز'),
          _t('Wall-mounted, 90 cm', 'يثبت على الحائط، 90 سم'),
          _t('Draft', 'مسودة'),
          66,
        ),
        'summary.__rich': _plainRich(
          _t('Wall-mounted, 90 cm', 'يثبت على الحائط، 90 سم'),
        ),
      },
      {
        ..._row(
          10,
          _t('Jute Basket', 'سلة خيش'),
          _t('Braided, with handles', 'مضفورة بمقابض'),
          _t('Active', 'نشط'),
          19,
        ),
        'summary.__rich': _plainRich(
          _t('Braided, with handles', 'مضفورة بمقابض'),
        ),
      },
    ],
    'categories' => [
      _row(
        1,
        _t('Lighting', 'الإضاءة'),
        _t('Lamps and fixtures', 'مصابيح وتركيبات'),
        _t('Active', 'نشط'),
        0,
      ),
      _row(
        2,
        _t('Textiles', 'المنسوجات'),
        _t('Throws, rugs, cushions', 'أغطية وسجاد ووسائد'),
        _t('Active', 'نشط'),
        0,
      ),
    ],
    'customers' => [
      _row(
        1,
        _t('Nora Malek', 'نورة مالك'),
        'nora@example.com',
        _t('Active', 'نشط'),
        0,
      ),
      _row(
        2,
        _t('Omar Saleh', 'عمر صالح'),
        'omar@example.com',
        _t('Active', 'نشط'),
        0,
      ),
    ],
    _ => [
      _row(
        1,
        _t('Dana Yousef', 'دانا يوسف'),
        _t('Store manager', 'مديرة المتجر'),
        _t('Active', 'نشط'),
        0,
      ),
    ],
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
    // A stable per-row placeholder photo, keyed by name so each card gets a
    // distinct image. picsum.photos serves over plain HTTPS, so the simulator
    // loads it with no ATS exception. A real server publishes a media URL
    // here; null exercises the initials fallback instead.
    'photo': 'https://picsum.photos/seed/${name.hashCode}/200',
  };

  // 'products'/'reviews' is the only populated relation this demo serves —
  // five rows so pagination (per page, below) genuinely has a second page to
  // fetch, rather than a single page that never shows "See all".
  // Not const: the review content goes through `_t` too.
  static final List<Map<String, dynamic>> _reviews = [
    {
      'id': 1,
      'author': _t('Mona K.', 'منى ك.'),
      'comment': _t('Great lamp, sturdy base.', 'مصباح رائع وقاعدة متينة.'),
      'rating': '5',
    },
    {
      'id': 2,
      'author': _t('Sam R.', 'سام ر.'),
      'comment': _t(
        'Exactly as pictured, fast shipping.',
        'مطابق تماماً للصور وشحن سريع.',
      ),
      'rating': '5',
    },
    {
      'id': 3,
      'author': _t('Ben T.', 'بن ت.'),
      'comment': _t('Good value for the price.', 'قيمة جيدة مقابل السعر.'),
      'rating': '4',
    },
    {
      'id': 4,
      'author': _t('Priya N.', 'بريا ن.'),
      'comment': _t('Would buy again.', 'سأشتري مرة أخرى.'),
      'rating': '4',
    },
    {
      'id': 5,
      'author': _t('Leo M.', 'ليو م.'),
      'comment': _t('Packaging could be better.', 'التغليف يمكن أن يكون أفضل.'),
      'rating': '3',
    },
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
    // The real server sorts and searches; a fake wire that ignores both makes
    // the list screen's own controls look broken, which is exactly what a
    // reader tapping the demo concludes.
    final rows = [..._rows(key)];
    final search = query?['search']?.toString().trim().toLowerCase() ?? '';
    if (search.isNotEmpty) {
      rows.retainWhere(
        (r) => '${r['name']} ${r['summary']}'.toLowerCase().contains(search),
      );
    }
    final sort = query?['sort']?.toString() ?? '';
    if (sort.isNotEmpty) {
      final desc = query?['direction']?.toString() == 'desc';
      // ponytail: string compare — right for `name` and ISO `updated_at`,
      // the only sort keys this fixture publishes.
      rows.sort(
        (a, b) => (desc ? -1 : 1) * '${a[sort]}'.compareTo('${b[sort]}'),
      );
    }
    // Paginate AFTER search and sort, as the real server does — a page is a
    // window over the ordered result, not over the raw table.
    const perPage = 4;
    final page = int.tryParse(query?['page']?.toString() ?? '1') ?? 1;
    final start = (page - 1) * perPage;
    final pageRows = start >= rows.length
        ? const <Map<String, dynamic>>[]
        : rows.sublist(start, (start + perPage).clamp(0, rows.length));
    return {
      'data': pageRows,
      'meta': {
        'current_page': page,
        'last_page': (rows.length / perPage).ceil().clamp(1, 999),
        'per_page': perPage,
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
        'feature' => _t('Marked as featured.', 'تم التمييز كمميز.'),
        'archive' => _t('Archived.', 'تمت الأرشفة.'),
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
