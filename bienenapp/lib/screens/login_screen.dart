import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vibration/vibration.dart';
import '../core/native_backend.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;
import '../cppasync.dart';
import 'dart:isolate';

//function to transform strings to send strings to the backend
ffi.Pointer<ffi.Char> stringToNative(String str) {
  final nativeStr = str.toNativeUtf8();
  return nativeStr.cast<ffi.Char>();
}

//function to transform strings from the backend to strings
String nativeToString(ffi.Pointer<ffi.Char> nativeStr) {
  return nativeStr.cast<Utf8>().toDartString();
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

Future<bool> attemptLoginInIsolate(String username, String password) async {
  return await Isolate.run(() {
    // 1. Initialize the C++ library INSIDE the background thread
    final dylib = ffi.DynamicLibrary.open('libnative_backend.so');
    // final backend = NativeLibrary(dylib);

    // 2. Do the pointer math here
    // (You can use your stringToNative function if it is also top-level,
    // but doing it inline here guarantees zero capture issues)
    final cUsername = username.toNativeUtf8();
    final cPassword = password.toNativeUtf8();

    // 3. Call C++
    final result = backend.login(
      cUsername.cast<ffi.Char>(),
      cPassword.cast<ffi.Char>(),
    );

    // 4. Free the memory
    calloc.free(cUsername);
    calloc.free(cPassword);

    return result;
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
              const Icon(Icons.lock_outline, size: 80, color: Colors.green),
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
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : FilledButton(
                        onPressed: () async {
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
                          if (loginSuccess) {
                            context.go('/home');
                            if (await Vibration.hasCustomVibrationsSupport() ??
                                false) {
                              Vibration.vibrate(pattern: [0, 20, 50]);
                            } else {
                              Vibration.vibrate();
                            }
                          } else {
                            // vibrate the device to provide haptic feedback on failed login

                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Login Failed'),
                                content: const Text(
                                  'Invalid username or password. Please try again.',
                                ),
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
                        child: const Text(
                          'Login',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
