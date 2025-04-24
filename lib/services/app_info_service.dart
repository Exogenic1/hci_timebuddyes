import 'package:package_info_plus/package_info_plus.dart';

class AppInfoService {
  // Get app version information
  static Future<Map<String, String>> getAppInfo() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();

    return {
      'appName': packageInfo.appName,
      'packageName': packageInfo.packageName,
      'version': packageInfo.version,
      'buildNumber': packageInfo.buildNumber,
    };
  }
}
