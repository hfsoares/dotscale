import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'scale_container.dart';

abstract interface class ContainerStore {
  Future<List<ScaleContainer>> load();
  Future<void> save(List<ScaleContainer> containers);
}

class PrefsContainerStore implements ContainerStore {
  static const _key = 'containers';

  @override
  Future<List<ScaleContainer>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return [];
    try {
      return [for (final item in jsonDecode(raw) as List) ScaleContainer.fromJson(item as Map<String, Object?>)];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<ScaleContainer> containers) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final c in containers) c.toJson()]));
}
