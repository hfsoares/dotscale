import 'package:shared_preferences/shared_preferences.dart';

class LastScaleStore {
  static const _key = 'last_scale_id';

  Future<String?> load() async => (await SharedPreferences.getInstance()).getString(_key);

  Future<void> save(String deviceId) async =>
      (await SharedPreferences.getInstance()).setString(_key, deviceId);
}
