import 'package:filament_mobile/schema/panel_schema.dart';
import 'package:filament_mobile/schema/resource_schema.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _panelJson(Object? notifications) => {
  'version': 1,
  'panel': {
    'id': 'mobile',
    'title': 'Panel',
    if (notifications != null) 'notifications': notifications,
  },
};

void main() {
  group('NotificationsConfig (P21)', () {
    test('absent reads as feature off, never a parse error', () {
      final panel = PanelSchema.fromJson(_panelJson(null));
      expect(panel.notifications, isNull);
    });

    test('a non-map node reads as absent', () {
      expect(NotificationsConfig.fromJson('yes'), isNull);
      expect(NotificationsConfig.fromJson(30), isNull);
      expect(NotificationsConfig.fromJson(const [30]), isNull);
    });

    test(
      'a bad poll drops the WHOLE node — the panel.poll fail-closed rule',
      () {
        for (final poll in [null, '30', 0, 3601, 1.5]) {
          expect(
            NotificationsConfig.fromJson({'poll': poll}),
            isNull,
            reason: 'poll=$poll must fail the node closed',
          );
        }
      },
    );

    test('a valid node parses poll seconds and the channel', () {
      final panel = PanelSchema.fromJson(
        _panelJson(const {'poll': 30, 'channel': 'App.Models.User.7'}),
      );

      expect(panel.notifications?.poll, const Duration(seconds: 30));
      expect(panel.notifications?.channel, 'App.Models.User.7');
    });

    test('channel trims, and blank or wrong-typed reads as poll-only', () {
      expect(
        NotificationsConfig.fromJson(const {
          'poll': 30,
          'channel': '  App.Models.User.7  ',
        })?.channel,
        'App.Models.User.7',
      );

      for (final channel in [null, '', '   ', 7]) {
        final config = NotificationsConfig.fromJson({
          'poll': 30,
          'channel': channel,
        });
        expect(config, isNotNull, reason: 'poll survives channel=$channel');
        expect(config?.channel, isNull);
      }
    });

    test('the poll bounds are 1..3600 inclusive', () {
      expect(
        NotificationsConfig.fromJson(const {'poll': 1})?.poll,
        const Duration(seconds: 1),
      );
      expect(
        NotificationsConfig.fromJson(const {'poll': 3600})?.poll,
        const Duration(seconds: 3600),
      );
    });
  });
}
