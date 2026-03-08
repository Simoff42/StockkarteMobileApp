import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;
import 'dart:convert';

// Import our globally instantiated native backend
import '../core/native_backend.dart';
import '../cppasync.dart';

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

Future<String> attemptLogoutInIsolate() async {
  return await Isolate.run(() {
    final dylib = ffi.DynamicLibrary.open('libnative_backend.so');
    final result = backend.logout();
    return nativeToString(result);
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.title});

  final String title;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _loadHivesData();
  }

  Future<void> _loadHivesData() async {
    await Isolate.run(() {
      backend.load_hives_overview();
    });

    if (mounted) {
      setState(() {});
    }
  }

  void _incrementCounter() {
    setState(() {
      backend.add_one();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        title: Text(widget.title),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              HapticFeedback.heavyImpact();
              await attemptLogoutInIsolate();
              // Navigate back to login screen after logout
              if (mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              backend.get_value().toString(),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.heavyImpact();
          _incrementCounter();
        },
        tooltip: 'Increment',
        child: const Icon(Icons.add, color: Colors.black),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
