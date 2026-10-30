import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Same formula as the bot: sha256 of `slug|code|title` after strip and lower.
String makeStableKey(String? departmentSlug, String? displayCode, String title) {
  final slug = ((departmentSlug == null || departmentSlug.isEmpty)
          ? 'therapy'
          : departmentSlug)
      .trim()
      .toLowerCase();
  final code = (displayCode ?? '').trim().toLowerCase();
  final lowered = title.trim().toLowerCase();
  final clipped = lowered.length > 500 ? lowered.substring(0, 500) : lowered;
  return sha256.convert(utf8.encode('$slug|$code|$clipped')).toString();
}
