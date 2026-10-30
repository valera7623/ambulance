import 'package:flutter/material.dart';

import 'controller.dart';

class ContentScope extends InheritedNotifier<ContentController> {
  const ContentScope({
    required ContentController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ContentController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ContentScope>();
    assert(scope != null, 'ContentScope is missing');
    return scope!.notifier!;
  }
}
