import 'package:filament_mobile/filament_mobile.dart';

/// An in-memory [FilamentTransport] serving a small e-commerce panel.
/// The widget tree above it is the package's real one — only the wire is fake.
class DemoTransport implements FilamentTransport {
  static const _perms = {
    'viewAny': true,
    'view': true,
    'create': true,
    'update': true,
    'delete': true,
  };

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
        ],
      },
    ],
    'infolist': [
      {'type': 'text_entry', 'name': 'name', 'label': 'Name'},
      {'type': 'text_entry', 'name': 'summary', 'label': 'Summary'},
      {'type': 'text_entry', 'name': 'status', 'label': 'Status'},
    ],
  };

  static final Map<String, dynamic> _schema = {
    'version': 1,
    'panel': {
      'id': 'demo',
      'title': 'Acme Admin',
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

  static List<Map<String, dynamic>> _rows(String key) => switch (key) {
    'products' => [
      _row(1, 'Aurora Desk Lamp', 'Warm-dim brass lamp', 'Active', 89),
      _row(2, 'Linen Throw', 'Stonewashed, 130×170', 'Active', 54),
      _row(3, 'Oak Side Table', 'Solid oak, oiled finish', 'Draft', 149),
      _row(4, 'Ceramic Vase Set', 'Set of three, matte glaze', 'Active', 42),
      _row(5, 'Wool Runner', 'Hand-loomed, 80×300', 'Draft', 210),
      _row(6, 'Glass Carafe', 'Borosilicate, 1.2 L', 'Active', 28),
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

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    if (path.endsWith('/schema')) return _schema;

    // /api/mobile-panel/{resource}[/{id}]
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    final key = parts[2];
    if (parts.length > 3) {
      final id = int.parse(parts[3]);
      return {
        'data': _rows(key).firstWhere((r) => r['id'] == id),
        'permissions': const {'view': true, 'update': true, 'delete': true},
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
  Future<FilamentResponse> post(String path, Map<String, dynamic> body) async =>
      const FilamentResponse(
        statusCode: 200,
        body: {
          'data': {'id': 99},
        },
      );

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
}
