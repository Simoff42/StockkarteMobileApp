import 'dart:ffi' as ffi;
import 'dart:isolate';
import './generated_bindings.dart';

/// A reusable wrapper to run any C++ function on a background thread.
Future<T> runCppAsync<T>(T Function(NativeLibrary backend) cppLogic) async {
  // Spin up the background thread
  return await Isolate.run(() {
    // 1. Initialize the C++ library inside this background thread
    final dylib = ffi.DynamicLibrary.open('libnative_backend.so');
    final backend = NativeLibrary(dylib);

    // 2. Execute whatever specific logic you passed into the wrapper
    // The result of type <T> is automatically returned to the main thread
    return cppLogic(backend);
  });
}
