import 'dart:js_interop';

// Bind Emscripten's ccall natively
@JS('Module.ccall')
external JSAny? _ccall(
  JSString ident,
  JSString returnType,
  JSArray<JSString> argTypes,
  JSArray<JSAny?> args,
);

/// A cleaner Dart wrapper for _ccall
JSAny? ccall(
  String ident,
  String returnType,
  List<String> argTypes,
  List<JSAny?> args,
) {
  return _ccall(
    ident.toJS,
    returnType.toJS,
    argTypes.map((e) => e.toJS).toList().toJS,
    args.toJS,
  );
}

class NativeBackendWeb {
  static int getValue() {
    final res = ccall('get_value', 'number', [], []) as JSNumber?;
    return res?.toDartInt ?? 0;
  }

  static void addOne() {
    ccall('add_one', 'null', [], []);
  }

  static String login(String username, String password) {
    final res =
        ccall(
              'login',
              'string',
              ['string', 'string'],
              [username.toJS, password.toJS],
            )
            as JSString?;
    return res?.toDart ?? "";
  }

  static String logout() {
    final res = ccall('logout', 'string', [], []) as JSString?;
    return res?.toDart ?? "";
  }

  static String getHivesOverviewJson() {
    final res = ccall('get_hives_overview_json', 'string', [], []) as JSString?;
    return res?.toDart ?? "";
  }

  static String getHiveDetailsJson(int hiveId) {
    final res =
        ccall('get_hive_details_json', 'string', ['number'], [hiveId.toJS])
            as JSString?;
    return res?.toDart ?? "";
  }

  static String calculateCombHistory(
    String logsJson,
    int currentB,
    int currentH,
  ) {
    final res =
        ccall(
              'calculate_comb_history',
              'string',
              ['string', 'number', 'number'],
              [logsJson.toJS, currentB.toJS, currentH.toJS],
            )
            as JSString?;
    return res?.toDart ?? "";
  }

  static String parseVarroaStatistics(String logsJson) {
    final res =
        ccall('parse_varroa_statistics', 'string', ['string'], [logsJson.toJS])
            as JSString?;
    return res?.toDart ?? "";
  }

  static String submitAction(
    int hiveId,
    int volkId,
    String action,
    String dataJson,
  ) {
    final res =
        ccall(
              'submit_action',
              'string',
              ['number', 'number', 'string', 'string'],
              [hiveId.toJS, volkId.toJS, action.toJS, dataJson.toJS],
            )
            as JSString?;
    return res?.toDart ?? "";
  }
}
