import 'dart:isolate';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../native_backend.dart';

String _nativeToString(ffi.Pointer<ffi.Char> nativeStr) {
  if (nativeStr == ffi.nullptr) return '';
  int length = 0;
  final uint8Pointer = nativeStr.cast<ffi.Uint8>();
  while ((uint8Pointer + length).value != 0) {
    length++;
  }
  return utf8.decode(uint8Pointer.asTypedList(length), allowMalformed: true);
}

ffi.Pointer<ffi.Char> _stringToNative(String str) {
  return str.toNativeUtf8().cast<ffi.Char>();
}

class AppApi {
  static Future<String> logout() async {
    return await Isolate.run(() {
      final result = backend.logout();
      return _nativeToString(result);
    });
  }

  static Future<String> getHivesOverviewJson() async {
    return await Isolate.run(() {
      final result = backend.get_hives_overview_json();
      return _nativeToString(result);
    });
  }

  static Future<String> login(String username, String password) async {
    return await Isolate.run(() {
      final cUsername = _stringToNative(username);
      final cPassword = _stringToNative(password);
      final result = backend.login(cUsername, cPassword);
      calloc.free(cUsername);
      calloc.free(cPassword);
      return _nativeToString(result);
    });
  }

  static Future<String> getHiveDetailsJson(int hiveId) async {
    return await Isolate.run(() {
      final result = backend.get_hive_details_json(hiveId);
      return _nativeToString(result);
    });
  }

  static Future<String> parseVarroaStatistics(String logsJson) async {
    return await Isolate.run(() {
      final parseFunc = dylib
          .lookupFunction<
            ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>),
            ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)
          >('parse_varroa_statistics');
      final cLogs = _stringToNative(logsJson);
      final result = parseFunc(cLogs);
      calloc.free(cLogs);
      return _nativeToString(result);
    });
  }

  static Future<String> calculateCombHistory(
    String logsJson,
    int currentB,
    int currentH,
  ) async {
    return await Isolate.run(() {
      final cLogs = _stringToNative(logsJson);
      final result = backend.calculate_comb_history(cLogs, currentB, currentH);
      calloc.free(cLogs);
      return _nativeToString(result);
    });
  }

  static Future<String> submitAction(
    int hiveId,
    int volkId,
    String action,
    String dataJson,
  ) async {
    return await Isolate.run(() {
      final cAction = _stringToNative(action);
      final cData = _stringToNative(dataJson);
      final result = backend.submit_action(hiveId, volkId, cAction, cData);
      calloc.free(cAction);
      calloc.free(cData);
      return _nativeToString(result);
    });
  }
}
