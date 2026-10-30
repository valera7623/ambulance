import 'package:flutter/material.dart';

import 'controller.dart';
import 'scope.dart';
import 'theme.dart';
import 'ui/screens.dart';

class SmpApp extends StatelessWidget {
  const SmpApp({required this.controller, super.key});

  final ContentController controller;

  @override
  Widget build(BuildContext context) {
    return ContentScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return MaterialApp(
            title: 'Клинические рекомендации для СМП',
            theme: buildSmpTheme(Brightness.light),
            darkTheme: buildSmpTheme(Brightness.dark),
            themeMode: controller.themeMode,
            home: const HomeScreen(),
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: TextScaler.linear(controller.textScale),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}
