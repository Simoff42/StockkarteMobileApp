import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'dart:isolate';
import 'dart:async';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// Import our globally instantiated native backend
import '../core/native_backend.dart';

// Note: Ensure MarkingColors is imported from your theme definition file!
import '../main.dart';

ffi.Pointer<ffi.Char> stringToNative(String str) {
  final nativeStr = str.toNativeUtf8();
  return nativeStr.cast<ffi.Char>();
}

String nativeToString(ffi.Pointer<ffi.Char> nativeStr) {
  if (nativeStr == ffi.nullptr) return '';

  int length = 0;
  final uint8Pointer = nativeStr.cast<ffi.Uint8>();
  while ((uint8Pointer + length).value != 0) {
    length++;
  }
  final bytes = uint8Pointer.asTypedList(length);
  return utf8.decode(bytes, allowMalformed: true);
}

Future<String> attemptLogoutInIsolate() async {
  return await Isolate.run(() {
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

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // 1. Add a state variable to hold your data
  List<Map<String, dynamic>> _hives = [];

  // Track the currently selected hive to make it "light up"
  int? _selectedHiveIndex;

  // MapController to handle programmatic panning and zooming
  final MapController _mapController = MapController();

  // Timer to remove the glow effect after a short delay
  Timer? _glowTimer;

  @override
  void initState() {
    super.initState();
    _loadHivesData();
  }

  @override
  void dispose() {
    _glowTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHivesData() async {
    final jsonString = await Isolate.run(() {
      final result = backend.get_hives_overview_json();
      return nativeToString(result);
    });

    if (mounted) {
      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is Map<String, dynamic> &&
          decoded['status'] == 'UNAUTHORIZED') {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Session Expired'),
            content: const Text(
              'Your session has expired or is invalid. Please log in again.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/login');
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      if (decoded is Map<String, dynamic> &&
          decoded.containsKey('status') &&
          decoded['status'] != 'SUCCESS') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decoded['message']?.toString() ?? 'Error loading hives.',
            ),
          ),
        );
        setState(() {
          _hives = [];
        });
        return;
      }

      setState(() {
        List<dynamic> hivesList = [];

        if (decoded is List) {
          // Case 1: JSON is a direct array -> [...]
          hivesList = decoded;
        } else if (decoded is Map<String, dynamic>) {
          // Case 2: JSON is an object containing the array -> {"hives": [...]}
          if (decoded.containsKey('hives') && decoded['hives'] is List) {
            hivesList = decoded['hives'] as List;
          } else if (decoded.containsKey('data') && decoded['data'] is List) {
            hivesList = decoded['data'] as List;
          } else {
            // Fallback: Just grab the first list we can find inside the object
            final fallbackList = decoded.values.firstWhere(
              (v) => v is List,
              orElse: () => null,
            );
            hivesList = fallbackList != null ? fallbackList as List : [decoded];
          }
        } else {
          hivesList = [decoded];
        }

        // 2. Save the parsed data to the state variable
        _hives = hivesList.map((e) => e as Map<String, dynamic>).toList();
      });
    }
  }

  // Converts Swiss Grid LV95 (CH1903+) to WGS84 (Lat/Lng)
  LatLng _convertLV95toWGS84(double e, double n) {
    double y = (e - 2600000) / 1000000.0;
    double x = (n - 1200000) / 1000000.0;

    double lat =
        16.9023892 +
        (3.238272 * x) -
        (0.270978 * y * y) -
        (0.002528 * x * x) -
        (0.0447 * y * y * x) -
        (0.0140 * x * x * x);
    lat = lat * 100.0 / 36.0;

    double lng =
        2.6779094 +
        (4.728982 * y) +
        (0.791484 * y * x) +
        (0.1306 * y * x * x) -
        (0.0436 * y * y * y);
    lng = lng * 100.0 / 36.0;

    return LatLng(lat, lng);
  }

  LatLng? _parseCoordinates(Map<String, dynamic> hive) {
    // 1. Try the new LV95 "coordinates" string format
    final coordString = hive['coordinates']?.toString();
    if (coordString != null && coordString.isNotEmpty) {
      // Remove apostrophes and split
      final cleaned = coordString.replaceAll("'", "");
      final parts = cleaned.split(',');
      if (parts.length >= 2) {
        final e = double.tryParse(parts[0].trim());
        final n = double.tryParse(parts[1].trim());
        if (e != null && n != null) {
          return _convertLV95toWGS84(e, n);
        }
      }
    }

    // 2. Fallback to standard lat/lng format just in case
    final lat = double.tryParse(
      hive['latitude']?.toString() ?? hive['lat']?.toString() ?? '',
    );
    final lng = double.tryParse(
      hive['longitude']?.toString() ?? hive['lng']?.toString() ?? '',
    );
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }

    return null;
  }

  // Helper method to collect all valid parsed coordinates
  List<LatLng> _getValidPoints() {
    final points = <LatLng>[];
    for (final hive in _hives) {
      final coords = _parseCoordinates(hive);
      if (coords != null) points.add(coords);
    }
    return points;
  }

  // Smoothly animates the map to a new location and zoom level
  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final camera = _mapController.camera;
    final latTween = Tween<double>(
      begin: camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom);

    final controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    final Animation<double> animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  // Smoothly animates the map back to fit all hives
  void _resetMapCamera() {
    final validPoints = _getValidPoints();
    if (validPoints.isEmpty) return;

    // Remove any selection highlighting
    setState(() {
      _selectedHiveIndex = null;
      _glowTimer?.cancel();
    });

    if (validPoints.length == 1) {
      _animatedMapMove(validPoints.first, 12.0);
      return;
    }

    final bounds = LatLngBounds.fromPoints(validPoints);

    double targetZoom = 8.0; // safe fallback zoom
    LatLng targetCenter = bounds.center;

    try {
      // Attempt to calculate exact bounds using flutter_map camera evaluations
      final fitResult = CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50.0),
      ).fit(_mapController.camera);

      targetZoom = fitResult.zoom;
      targetCenter = fitResult.center;
    } catch (_) {
      // Fallback relies on bounds center and default zoom if API changes
    }

    _animatedMapMove(targetCenter, targetZoom);
  }

  // Helper method to build map markers mapped to the list colors
  List<Marker> _buildMarkers(List<Color> markingColors) {
    final markers = <Marker>[];
    for (int i = 0; i < _hives.length; i++) {
      final hive = _hives[i];
      final coords = _parseCoordinates(hive);

      if (coords != null) {
        final color = markingColors[i % markingColors.length];
        final isSelected = _selectedHiveIndex == i;

        markers.add(
          Marker(
            point: coords,
            width: isSelected
                ? 70
                : 60, // Slightly enlarge the icon on the map when selected
            height: isSelected ? 70 : 60,
            alignment: Alignment
                .topCenter, // Aligns the bottom tip of the icon to the coordinates
            child: GestureDetector(
              onTap: () {
                setState(() {
                  // Toggle selection on tap
                  _selectedHiveIndex = isSelected ? null : i;
                });

                // Cancel any previously running timer
                _glowTimer?.cancel();

                // Automatically pan and zoom in on the marker if it was just selected
                if (!isSelected) {
                  _animatedMapMove(
                    coords,
                    15.0,
                  ); // 15.0 provides a nice close-up view

                  // Start a timer to remove the glow after 3 seconds
                  _glowTimer = Timer(const Duration(milliseconds: 500), () {
                    if (mounted) {
                      setState(() {
                        _selectedHiveIndex = null;
                      });
                    }
                  });
                }
              },
              child: Tooltip(
                message: hive['name'] ?? 'Hive',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.location_on,
                    color: color,
                    size: isSelected ? 70 : 60,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    // Retrieve the custom colors from the theme using the new public class
    final markingColors =
        Theme.of(context).extension<MarkingColors>()?.colors ?? [Colors.blue];

    // Gather points here to configure the map bounds
    final validPoints = _getValidPoints();

    // Determine the current screen orientation
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // Define the List portion of the UI
    final hivesListWidget = Expanded(
      flex: isLandscape
          ? 1
          : 3, // In landscape it splits 50/50, in portrait it takes more space
      child: RefreshIndicator(
        color: Colors.white,
        onRefresh: _loadHivesData, // Triggers the backend reload
        child: ListView.builder(
          itemCount: _hives.length,
          itemBuilder: (context, index) {
            final color = markingColors[index % markingColors.length];
            return _buildHiveBar(_hives[index], color, index);
          },
        ),
      ),
    );

    // Define the Map portion of the UI
    final mapWidget = Expanded(
      flex: isLandscape ? 1 : 2,
      child: Container(
        margin: const EdgeInsets.all(
          8.0,
        ), // Added a small margin to show off all rounded corners nicely
        clipBehavior:
            Clip.antiAlias, // Ensures the map is clipped to the rounded corners
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          // Round all corners equally regardless of orientation
          borderRadius: BorderRadius.circular(24.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              // Centered the shadow to look balanced on all rounded edges
              offset: const Offset(0, 0),
            ),
          ],
        ),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                // Min and Max Zoom Limits
                minZoom: 5.0,
                maxZoom: 18.0,
                // If we have multiple points, fit them to the bounds tightly (with 50px padding)
                initialCameraFit: validPoints.length > 1
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(validPoints),
                        padding: const EdgeInsets.all(50.0),
                      )
                    : null,
                // Fallback centers and zooms if we have 1 or 0 points
                initialCenter: validPoints.length == 1
                    ? validPoints.first
                    : const LatLng(46.8182, 8.2275), // Switzerland fallback
                initialZoom: validPoints.length == 1 ? 12.0 : 8.0,
                // Prevent rotation of the map to always keep north pointing upwards
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.hivesapp',
                ),
                MarkerLayer(markers: _buildMarkers(markingColors)),
              ],
            ),

            // Map Reset Button
            Positioned(
              top: 16.0,
              right: 16.0,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.aspect_ratio),
                  color: Theme.of(context).colorScheme.tertiary,
                  tooltip: 'Reset Map View',
                  onPressed: _resetMapCamera,
                ),
              ),
            ),
          ],
        ),
      ),
    );

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
              if (mounted && context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      // Automatically switch between Row (Landscape) and Column (Portrait)
      body: _hives.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : isLandscape
          ? Row(children: [hivesListWidget, mapWidget])
          : Column(children: [hivesListWidget, mapWidget]),
    );
  }

  Widget _buildHiveBar(Map<String, dynamic> hive, Color color, int index) {
    final int permission = int.tryParse(hive['permission'].toString()) ?? 0;
    IconData permissionIcon;
    String permissionTooltip;

    switch (permission) {
      case 2:
        permissionIcon = Icons.admin_panel_settings;
        permissionTooltip = 'Admin';
        break;
      case 1:
        permissionIcon = Icons.edit;
        permissionTooltip = 'Editor';
        break;
      case 0:
      default:
        permissionIcon = Icons.visibility;
        permissionTooltip = 'Viewer';
        break;
    }

    final bool isSelected = _selectedHiveIndex == index;

    return GestureDetector(
      onTap: () {
        // Navigates using push to stack the view and trigger slide animations
        context.push('/Hive?id=${hive['id']}');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // Change opacity significantly to simulate a "light up" glow
          color: color.withValues(alpha: isSelected ? 0.4 : 0.1),
          // Increase border width when selected
          border: Border.all(color: color, width: isSelected ? 4 : 2),
          borderRadius: BorderRadius.circular(8),
          // Add a subtle drop shadow when selected
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 12,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isSelected ? 16 : 12,
              height: 60,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hive['name'] ?? 'Unknown',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${hive['location'] ?? 'N/A'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.tag,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${hive['hivenumber'] ?? 'N/A'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Tooltip(
              message: permissionTooltip,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    permissionIcon,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    permissionTooltip,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
