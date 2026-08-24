import 'package:flutter/widgets.dart';

import '../schema/schema_component.dart';

/// Builds a node under its explicit direction, or directly under [context]
/// when the node inherits the panel direction.
///
/// The inner [Builder] is load-bearing for host registries: their callback's
/// own context must already see the override. Merely wrapping the Widget they
/// returned would make its descendants correct while any direction-sensitive
/// values computed inside the callback still used the host direction.
Widget buildWithComponentDirection(
  BuildContext context,
  ComponentDirection? direction,
  WidgetBuilder builder,
) {
  if (direction == null) return builder(context);

  return Directionality(
    textDirection: switch (direction) {
      ComponentDirection.ltr => TextDirection.ltr,
      ComponentDirection.rtl => TextDirection.rtl,
    },
    child: Builder(builder: builder),
  );
}
