import 'package:flutter/material.dart';
import 'router/app_router.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Your original seed color: RGB(255, 191, 0) - A vibrant Amber
  static const Color _amberSeed = Color.fromRGBO(255, 191, 0, 1);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Flutter Demo',
      routerConfig: appRouter,

      // --- LIGHT THEME ---
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _amberSeed,
          brightness: Brightness.light,
          // Overriding specific colors for a tailored Light Theme
          primary: const Color(
            0xFFD49A00,
          ), // Slightly deeper amber for better accessibility/contrast
          onPrimary: Colors.white, // White text/icons on primary buttons
          secondary: const Color(
            0xFF006A60,
          ), // Complementary deep teal for secondary accents
          onSecondary: Colors.white,
          tertiary: const Color(
            0xFF605E41,
          ), // Earthy olive/grey for subtle tertiary elements
          surface: const Color(
            0xFFFFFBFA,
          ), // Very warm, off-white surface color
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),

      // --- DARK THEME ---
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _amberSeed,
          brightness: Brightness.dark,
          // Overriding specific colors for a tailored Dark Theme
          primary: const Color.fromARGB(
            255,
            255,
            183,
            0,
          ), // Brighter, softer amber so it glows in dark mode
          onPrimary: const Color(
            0xFF402D00,
          ), // Dark brown text on amber buttons for readability
          secondary: const Color(
            0xFF53D5C3,
          ), // Bright minty-teal for dark mode accents
          onSecondary: const Color(0xFF003731),
          tertiary: const Color.fromARGB(
            255,
            255,
            255,
            255,
          ), // Soft, light olive for tertiary elements
          surface: const Color(
            0xFF1E1B16,
          ), // Warm dark grey (looks much better than pure black)
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),

      themeMode: ThemeMode.system,
    );
  }
}
