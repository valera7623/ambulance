import 'package:flutter/services.dart';

const _share = MethodChannel('ru.smp.smp_guide/share');

Future<void> sharePlainText(String text) async {
  try {
    await _share.invokeMethod<void>('share', text);
  } on MissingPluginException {
    // The host has no share sheet. The handbook text stays on screen.
  }
}
