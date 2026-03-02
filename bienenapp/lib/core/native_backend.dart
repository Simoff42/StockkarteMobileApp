import 'dart:ffi';
import 'dart:io';

// Note: Ensure your generated_bindings.dart is accessible here,
// adjust the import path if you placed it somewhere else.
import '../generated_bindings.dart';

// Load the library once
final dylib = Platform.isAndroid || Platform.isLinux
    ? DynamicLibrary.open('libnative_backend.so')
    : DynamicLibrary.open('native_backend.dll');

// Instantiate the auto-generated class.
// We make this available globally just like in your original code.
final backend = NativeLibrary(dylib);
