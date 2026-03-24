import '../bridge_web.dart';

class AppApi {
  static Future<String> logout() async {
    return NativeBackendWeb.logout();
  }

  static Future<String> getHivesOverviewJson() async {
    return NativeBackendWeb.getHivesOverviewJson();
  }

  static Future<String> login(String username, String password) async {
    return NativeBackendWeb.login(username, password);
  }

  static Future<String> getHiveDetailsJson(int hiveId) async {
    return NativeBackendWeb.getHiveDetailsJson(hiveId);
  }

  static Future<String> parseVarroaStatistics(String logsJson) async {
    return NativeBackendWeb.parseVarroaStatistics(logsJson);
  }

  static Future<String> calculateCombHistory(
    String logsJson,
    int currentB,
    int currentH,
  ) async {
    return NativeBackendWeb.calculateCombHistory(logsJson, currentB, currentH);
  }

  static Future<String> submitAction(
    int hiveId,
    int volkId,
    String action,
    String dataJson,
  ) async {
    return NativeBackendWeb.submitAction(hiveId, volkId, action, dataJson);
  }
}
