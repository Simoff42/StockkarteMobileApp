import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vibration/vibration.dart';
import '../core/native_backend.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;
import '../cppasync.dart';
import 'dart:isolate';
import 'dart:convert';

ffi.Pointer<ffi.Char> stringToNative(String str) {
  final nativeStr = str.toNativeUtf8();
  return nativeStr.cast<ffi.Char>();
}

String nativeToString(ffi.Pointer<ffi.Char> nativeStr) {
  if (nativeStr == ffi.nullptr) return '';

  int length = 0;
  final uint8Pointer = nativeStr.cast<ffi.Uint8>();
  while (uint8Pointer.elementAt(length).value != 0) {
    length++;
  }
  final bytes = uint8Pointer.asTypedList(length);
  return utf8.decode(bytes, allowMalformed: true);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

Future<String> attemptLoginInIsolate(String username, String password) async {
  return await Isolate.run(() {
    final dylib = ffi.DynamicLibrary.open('libnative_backend.so');

    final cUsername = username.toNativeUtf8();
    final cPassword = password.toNativeUtf8();

    final result = backend.login(
      cUsername.cast<ffi.Char>(),
      cPassword.cast<ffi.Char>(),
    );

    calloc.free(cUsername);
    calloc.free(cPassword);

    return nativeToString(result);
  });
}

class _LoginScreenState extends State<LoginScreen> {
  late TextEditingController usernameController;
  late TextEditingController passwordController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController();
    passwordController = TextEditingController();
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80),
              const SizedBox(height: 32),
              Text(
                'Welcome Back',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.password),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all<Color>(
                      Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                  onPressed: _isLoading
                      ? null
                      : () async {
                          HapticFeedback.heavyImpact();
                          final username = usernameController.text;
                          final password = passwordController.text;

                          setState(() {
                            _isLoading = true;
                          });

                          final loginSuccess = await attemptLoginInIsolate(
                            username,
                            password,
                          );
                          setState(() {
                            _isLoading = false;
                          });

                          debugPrint('Login response: $loginSuccess');
                          if (loginSuccess == "SUCCESS") {
                            context.go('/home');
                            if (await Vibration.hasCustomVibrationsSupport() ??
                                false) {
                              Vibration.vibrate(pattern: [0, 20, 50]);
                            } else {
                              Vibration.vibrate();
                            }
                          } else {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Login Failed'),
                                content: Text(switch (loginSuccess) {
                                  "FAILED" => "Invalid username or password.",
                                  "TIMEOUT" =>
                                    "The server took too long to respond. Please try again.",
                                  "NETWORK_ERROR" =>
                                    "Could not connect to the server. Please check your internet connection.",
                                  "BAD_REQUEST" =>
                                    "The server rejected the request. Please contact support.",
                                  "INTERNAL_SERVER_ERROR" =>
                                    "The server encountered an error. Please try again later.",
                                  "HTTP_ERROR" =>
                                    "An unexpected HTTP error occurred. Please try again.",
                                  "UNAUTHORIZED" =>
                                    "You are not authorized to perform this action.",
                                  "NOT_FOUND" =>
                                    "The requested resource was not found on the server.",
                                  "ERROR" =>
                                    "An unknown error occurred on the server. Please try again.",
                                  _ => "An unknown error occurred.",
                                }),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                            if (await Vibration.hasCustomVibrationsSupport() ??
                                false) {
                              Vibration.vibrate(
                                pattern: [0, 100, 50, 100, 50, 100, 50],
                              );
                            } else {
                              Vibration.vibrate();
                            }
                          }
                        },
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text('Login', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
