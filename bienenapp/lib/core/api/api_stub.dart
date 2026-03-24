class AppApi {
  static Future<String> logout() async => throw UnsupportedError('Unsupported');
  static Future<String> getHivesOverviewJson() async =>
      throw UnsupportedError('Unsupported');
  static Future<String> login(String username, String password) async =>
      throw UnsupportedError('Unsupported');
  static Future<String> getHiveDetailsJson(int hiveId) async =>
      throw UnsupportedError('Unsupported');
  static Future<String> parseVarroaStatistics(String logsJson) async =>
      throw UnsupportedError('Unsupported');
  static Future<String> calculateCombHistory(
    String logsJson,
    int currentB,
    int currentH,
  ) async => throw UnsupportedError('Unsupported');
  static Future<String> submitAction(
    int hiveId,
    int volkId,
    String action,
    String dataJson,
  ) async => throw UnsupportedError('Unsupported');
}
