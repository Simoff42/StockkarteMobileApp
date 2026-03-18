import 'package:flutter/material.dart';
import 'router/app_router.dart';

void main() {
  runApp(const MyApp());
}

class MarkingColors extends ThemeExtension<MarkingColors> {
  final List<Color> colors;

  const MarkingColors({required this.colors});

  @override
  ThemeExtension<MarkingColors> copyWith({List<Color>? colors}) {
    return MarkingColors(colors: colors ?? this.colors);
  }

  @override
  ThemeExtension<MarkingColors> lerp(
    ThemeExtension<MarkingColors>? other,
    double t,
  ) {
    return this;
  }
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
          primary: const Color.fromARGB(255, 220, 171, 38),
          onPrimary: Colors.white,
          secondary: const Color(0xFF006A60),
          onSecondary: Colors.white,
          tertiary: const Color.fromARGB(255, 0, 0, 0),
          surface: const Color(0xFFFFFBFA),
          surfaceContainer: const Color.fromARGB(255, 231, 231, 231),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        // Marking colors for list item differentiation
        extensions: const [
          MarkingColors(
            colors: [
              Color(0xFFE91E63), // Pink
              Color(0xFF2196F3), // Blue
              Color(0xFF4CAF50), // Green
              Color(0xFFFFC107), // Amber
              Color(0xFF9C27B0), // Purple
              Color(0xFF00BCD4), // Cyan
              Color(0xFFFF5722), // Deep Orange
              Color(0xFF795548), // Brown
            ],
          ),
        ],
      ),

      // --- DARK THEME ---
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _amberSeed,
          brightness: Brightness.dark,
          primary: const Color.fromARGB(255, 255, 183, 0),
          onPrimary: const Color(0xFF402D00),
          secondary: const Color(0xFF53D5C3),
          onSecondary: const Color(0xFF003731),
          tertiary: const Color.fromARGB(255, 255, 255, 255),
          surface: const Color(0xFF1E1B16),
          surfaceContainer: const Color.fromARGB(255, 57, 52, 45),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        // Marking colors for list item differentiation
        extensions: const [
          MarkingColors(
            colors: [
              Color(0xFF64B5F6), // Light Blue
              Color(0xFFBA68C8), // Light Purple
              Color(0xFF81C784), // Light Green
              Color(0xFFFFD54F), // Light Amber
              Color(0xFF4DD0E1), // Light Cyan
              Color(0xFFFF8A65), // Light Orange
              Color(0xFFA1887F), // Light Brown
              Color(0xFFFF6B9D), // Light Pink
            ],
          ),
        ],
      ),

      themeMode: ThemeMode.system,
    );
  }
}
