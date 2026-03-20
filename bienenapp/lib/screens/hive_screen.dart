import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;
import 'dart:convert';
import 'dart:isolate';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// Import your globally instantiated native backend
import '../core/native_backend.dart';

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

Future<String> fetchHiveDetailsInIsolate(int id) async {
  return await Isolate.run(() {
    final result = backend.get_hive_details_json(id);
    return nativeToString(result);
  });
}

class _ThemeRefreshIndicator extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const _ThemeRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      strokeWidth: 3.0,
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        await onRefresh();
      },
      child: child,
    );
  }
}

class HiveScreen extends StatefulWidget {
  final String id;

  const HiveScreen({super.key, required this.id});

  @override
  State<HiveScreen> createState() => _HiveScreenState();
}

class _HiveScreenState extends State<HiveScreen> {
  Map<String, dynamic>? _hiveDetails;
  bool _isLoading = true;

  // --- Scroll & Time Scroller State ---
  final ScrollController _logScrollController = ScrollController();

  // Use ValueNotifiers to isolate rebuilds to JUST the floating badge
  final ValueNotifier<String> _currentScrollCategory = ValueNotifier<String>(
    '',
  );
  final ValueNotifier<bool> _isScrollingLogs = ValueNotifier<bool>(false);
  Timer? _scrollHideTimer;
  int _selectedLogYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadHiveDetails();
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    _currentScrollCategory.dispose();
    _isScrollingLogs.dispose();
    _scrollHideTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHiveDetails() async {
    final int hiveId = int.tryParse(widget.id) ?? 0;
    final jsonString = await fetchHiveDetailsInIsolate(hiveId);

    if (mounted) {
      try {
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
                decoded['message']?.toString() ?? 'Error loading hive details.',
              ),
            ),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }

        setState(() {
          if (decoded is Map<String, dynamic>) {
            _hiveDetails = decoded;
          } else if (decoded is List && decoded.isNotEmpty) {
            _hiveDetails = decoded.first as Map<String, dynamic>;
          }
          _isLoading = false;
        });
      } catch (e) {
        debugPrint('Error parsing hive details: $e');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _goBackToHome(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _copyToClipboard(String label, String text) {
    if (text == 'N/A' || text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied to clipboard!')));
  }

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
    final coordString = hive['coordinates']?.toString();
    if (coordString != null && coordString.isNotEmpty) {
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

  String _getLogCategory(String dateString) {
    final logDate = DateTime.tryParse(dateString);
    if (logDate == null) return 'Older';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logDay = DateTime(logDate.year, logDate.month, logDate.day);
    final difference = today.difference(logDay).inDays;

    if (difference <= 7) {
      return 'Last 7 Days';
    } else if (difference <= 30) {
      return 'Older than a week';
    } else if (difference <= 60) {
      return 'Older than a month';
    } else {
      const monthNames = [
        '',
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      final monthName = monthNames[logDate.month];
      final yearStr = logDate.year == now.year ? '' : ' ${logDate.year}';
      return '$monthName$yearStr';
    }
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required double width,
    required Widget content,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(icon, size: 18, color: Colors.orange.shade400),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title.toUpperCase(),
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (trailing != null) trailing,
                  ],
                ),
                const SizedBox(height: 12),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    if (_hiveDetails == null || _hiveDetails!.isEmpty) {
      return _ThemeRefreshIndicator(
        onRefresh: _loadHiveDetails,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Text(
                  'Could not load details for Hive ${widget.id}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hive = _hiveDetails!['hive'] as Map<String, dynamic>? ?? {};

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 800;
        final bool isMedium = constraints.maxWidth > 500 && !isWide;

        final double spacing = 16.0;
        final double fullWidth = constraints.maxWidth - (spacing * 2);

        final double thirdWidth = isWide
            ? (fullWidth - (spacing * 2)) / 3
            : (isMedium ? (fullWidth - spacing) / 2 : fullWidth);

        final double twoThirdsWidth = isWide
            ? (thirdWidth * 2) + spacing
            : fullWidth;

        final double pairedWidth = (fullWidth - spacing) / 2;

        final String valName = hive['name']?.toString() ?? 'N/A';
        final String valHiveNum = hive['hivenumber']?.toString() ?? 'N/A';
        final String valStreet = hive['street']?.toString() ?? 'N/A';
        final String valLocation = hive['place']?.toString() ?? 'N/A';
        final String ownerName =
            '${hive['owner_firstname'] ?? ''} ${hive['owner_lastname'] ?? ''}'
                .trim();
        final String valOwner = ownerName.isNotEmpty ? ownerName : 'N/A';
        final String valVet = hive['veterinarian']?.toString() ?? 'N/A';
        final String valInspector = hive['inspector']?.toString() ?? 'N/A';
        final String valDate =
            hive['datum']?.toString() ??
            hive['creation_date']?.toString() ??
            'N/A';

        final permissionLvl =
            int.tryParse(hive['permission']?.toString() ?? '') ?? 0;
        String permLabel = 'Viewer';
        Color permColor = Colors.grey.shade700;
        Color permBg = Colors.grey.shade200;
        IconData permIcon = Icons.visibility;

        if (permissionLvl == 2) {
          permLabel = 'Admin';
          permColor = Colors.red.shade700;
          permBg = Colors.red.shade50;
          permIcon = Icons.admin_panel_settings;
        } else if (permissionLvl == 1) {
          permLabel = 'Editor';
          permColor = Colors.orange.shade700;
          permBg = Colors.orange.shade50;
          permIcon = Icons.edit;
        }

        final coords = _parseCoordinates(hive);
        final String coordsText = coords != null
            ? '${coords.latitude.toStringAsFixed(4)}, ${coords.longitude.toStringAsFixed(4)}'
            : 'N/A';

        return _ThemeRefreshIndicator(
          onRefresh: _loadHiveDetails,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _buildInfoCard(
                  title: 'Name',
                  icon: Icons.hexagon_outlined,
                  width: pairedWidth,
                  onTap: () => _copyToClipboard('Name', valName),
                  content: Text(
                    valName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildInfoCard(
                  title: 'Hive Number',
                  icon: Icons.numbers,
                  width: pairedWidth,
                  onTap: () => _copyToClipboard('Hive Number', valHiveNum),
                  content: Text(
                    valHiveNum,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildInfoCard(
                  title: 'Street',
                  icon: Icons.signpost_outlined,
                  width: pairedWidth,
                  onTap: () => _copyToClipboard('Street', valStreet),
                  content: Text(
                    valStreet,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildInfoCard(
                  title: 'Place',
                  icon: Icons.location_on_outlined,
                  width: pairedWidth,
                  onTap: () => _copyToClipboard('Place', valLocation),
                  content: Text(
                    valLocation,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildInfoCard(
                  title: 'Map & Coordinates',
                  icon: Icons.map_outlined,
                  width: fullWidth,
                  onTap: () async {
                    if (coords != null) {
                      final url = Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query=${coords.latitude},${coords.longitude}',
                      );
                      try {
                        final launched = await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                        if (!launched) {
                          final fallbackLaunched = await launchUrl(
                            url,
                            mode: LaunchMode.platformDefault,
                          );
                          if (!fallbackLaunched) {
                            _copyToClipboard('Coordinates', coordsText);
                          }
                        }
                      } catch (e) {
                        _copyToClipboard('Coordinates', coordsText);
                      }
                    } else {
                      _copyToClipboard('Coordinates', coordsText);
                    }
                  },
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (coords != null) ...[
                        IgnorePointer(
                          child: Container(
                            height: 150,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: coords,
                                initialZoom: 15.0,
                                interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.none,
                                ),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.example.hivesapp',
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: coords,
                                      width: 40,
                                      height: 40,
                                      alignment: Alignment.topCenter,
                                      child: Icon(
                                        Icons.location_on,
                                        color: Colors.blue.shade600,
                                        size: 40,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            coordsText,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontFamily: 'monospace',
                                  letterSpacing: 1.2,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildInfoCard(
                  title: 'Your Permission',
                  icon: Icons.security_outlined,
                  width: thirdWidth,
                  onTap: () => _copyToClipboard('Permission Level', permLabel),
                  content: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: permBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(permIcon, size: 16, color: permColor),
                        const SizedBox(width: 6),
                        Text(
                          permLabel,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: permColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildInfoCard(
                  title: 'Owner',
                  icon: Icons.person_outline,
                  width: thirdWidth,
                  onTap: () => _copyToClipboard('Owner', valOwner),
                  content: Text(
                    valOwner,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildInfoCard(
                  title: 'Creation Date',
                  icon: Icons.calendar_today_outlined,
                  width: thirdWidth,
                  onTap: () => _copyToClipboard('Creation Date', valDate),
                  content: Text(
                    valDate,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildInfoCard(
                  title: 'Veterinarian',
                  icon: Icons.medical_services_outlined,
                  width: pairedWidth,
                  onTap: () => _copyToClipboard('Veterinarian', valVet),
                  content: Text(
                    valVet,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildInfoCard(
                  title: 'Inspector',
                  icon: Icons.assignment_ind_outlined,
                  width: pairedWidth,
                  onTap: () => _copyToClipboard('Inspector', valInspector),
                  content: Text(
                    valInspector,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVolkTile(
    Map<String, dynamic> volk,
    double tileWidth,
    BuildContext context,
  ) {
    final String volkId = volk['id']?.toString() ?? '';
    final String nummer = volk['nummer']?.toString() ?? 'N/A';
    final String konigin = volk['konigin']?.toString() ?? 'unmarkiert';
    String datum = volk['datum']?.toString() ?? 'N/A';

    if (datum != 'N/A') {
      if (datum.contains(' ')) {
        datum = datum.split(' ')[0];
      } else if (datum.contains('T')) {
        datum = datum.split('T')[0];
      }
    }

    Color qColor = Colors.grey.shade300;
    Color qTextColor = Colors.black87;
    String qText = konigin.toUpperCase();

    switch (konigin.toLowerCase()) {
      case 'rot':
        qColor = Colors.red;
        qTextColor = Colors.white;
        break;
      case 'grün':
      case 'gruen':
        qColor = Colors.green;
        qTextColor = Colors.white;
        break;
      case 'blau':
        qColor = Colors.blue;
        qTextColor = Colors.white;
        break;
      case 'gelb':
        qColor = Colors.yellow;
        qTextColor = Colors.black87;
        break;
      case 'weiss':
        qColor = Colors.white;
        qTextColor = Colors.black87;
        break;
      case 'kk':
        qColor = Colors.black87;
        qTextColor = Colors.white;
        qText = 'KK (KEINE KÖNIGIN)';
        break;
      case 'unmarkiert':
        qColor = Colors.grey.shade400;
        qTextColor = Colors.black87;
        break;
    }

    return Container(
      width: tileWidth,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16.0),
          onTap: () {
            if (volkId.isNotEmpty) {
              context.push('/volk/?hive_id=${widget.id}&volk_id=$volkId');
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error: Missing Volk ID')),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Fixed layout issue: the Container correctly builds and encapsulates the Big Number
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Center(
                    child: Text(
                      nummer,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.bug_report,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: qColor,
                              borderRadius: BorderRadius.circular(6),
                              border: qColor == Colors.white
                                  ? Border.all(color: Colors.grey.shade300)
                                  : null,
                            ),
                            child: Text(
                              qText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: qTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            datum,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVolksTab() {
    List<dynamic> volksList = [];

    if (_hiveDetails != null) {
      if (_hiveDetails!.containsKey('volks') &&
          _hiveDetails!['volks'] is List) {
        volksList = _hiveDetails!['volks'];
      } else if (_hiveDetails!.containsKey('hive') &&
          _hiveDetails!['hive']['volks'] is List) {
        volksList = _hiveDetails!['hive']['volks'];
      }
    }

    if (volksList.isEmpty) {
      return _ThemeRefreshIndicator(
        onRefresh: _loadHiveDetails,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.hive_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Volks recorded yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final activeVolks = volksList.where((v) {
      final activeVal = (v as Map)['active']?.toString();
      return activeVal == '1' || activeVal == 'true' || activeVal == null;
    }).toList();

    final inactiveVolks = volksList.where((v) {
      final activeVal = (v as Map)['active']?.toString();
      return activeVal == '0' || activeVal == 'false';
    }).toList();

    int compareVolksByNummer(dynamic a, dynamic b) {
      final String numA = (a as Map)['nummer']?.toString() ?? '';
      final String numB = (b as Map)['nummer']?.toString() ?? '';
      final int? intA = int.tryParse(numA);
      final int? intB = int.tryParse(numB);

      if (intA != null && intB != null) {
        return intA.compareTo(intB);
      }
      return numA.compareTo(numB);
    }

    int compareVolksByDate(dynamic a, dynamic b) {
      final String dateAStr = (a as Map)['datum']?.toString() ?? '';
      final String dateBStr = (b as Map)['datum']?.toString() ?? '';

      final DateTime? dateA = DateTime.tryParse(dateAStr);
      final DateTime? dateB = DateTime.tryParse(dateBStr);

      if (dateA != null && dateB != null) {
        return dateB.compareTo(dateA);
      }
      return dateBStr.compareTo(dateAStr);
    }

    activeVolks.sort(compareVolksByNummer);
    inactiveVolks.sort(compareVolksByDate);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 800;
        final bool isMedium = constraints.maxWidth > 500 && !isWide;
        final double spacing = 16.0;
        final double fullWidth = constraints.maxWidth - (spacing * 2);

        final double tileWidth = isWide
            ? (fullWidth - (spacing * 2)) / 3
            : (isMedium ? (fullWidth - spacing) / 2 : fullWidth);

        return _ThemeRefreshIndicator(
          onRefresh: _loadHiveDetails,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (activeVolks.isNotEmpty)
                  Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: activeVolks
                        .map(
                          (v) => _buildVolkTile(
                            v as Map<String, dynamic>,
                            tileWidth,
                            context,
                          ),
                        )
                        .toList(),
                  ),

                if (activeVolks.isEmpty && inactiveVolks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      'No active Volks.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                if (inactiveVolks.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: Text(
                        'Old Volks (${inactiveVolks.length})',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(top: 16.0),
                      initiallyExpanded: false,
                      children: [
                        Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: inactiveVolks
                              .map(
                                (v) => _buildVolkTile(
                                  v as Map<String, dynamic>,
                                  tileWidth,
                                  context,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogTile(Map<String, dynamic> log, BuildContext context) {
    final String wetter = log['wetter']?.toString() ?? '';
    final String temperatur = log['temperatur']?.toString() ?? '';
    final String action = log['action']?.toString() ?? 'Unknown Action';
    final String befund = log['befund']?.toString() ?? '';
    final String datum = log['datum']?.toString() ?? 'N/A';
    final String kommentar = log['kommentar']?.toString() ?? '';
    final String volkId = log['id']?.toString() ?? '';

    IconData actionIcon;
    Color actionColor = Theme.of(context).colorScheme.primary;

    switch (action.toLowerCase()) {
      case 'kontrolle':
        actionIcon = Icons.fact_check_outlined;
        actionColor = Colors.blue.shade600;
        break;
      case 'varroa zählen':
      case 'varroa zaehlen':
        actionIcon = Icons.pest_control;
        actionColor = Colors.orange.shade700;
        break;
      case 'varroa behandeln':
        actionIcon = Icons.medication_outlined;
        actionColor = Colors.purple.shade600;
        break;
      case 'behandlung entfernen':
        actionIcon = Icons.healing_outlined;
        actionColor = Colors.deepPurple.shade400;
        break;
      case 'volk auflösen':
      case 'volk aufloesen':
        actionIcon = Icons.group_remove_outlined;
        actionColor = Colors.red.shade600;
        break;
      case 'volk vereinigen':
        actionIcon = Icons.group_add_outlined;
        actionColor = Colors.teal.shade600;
        break;
      case 'volk umziehen':
        actionIcon = Icons.local_shipping_outlined;
        actionColor = Colors.indigo.shade600;
        break;
      case 'volk erstellt':
        actionIcon = Icons.add_circle_outline;
        actionColor = Colors.lightBlue.shade600;
        break;
      case 'ableger erstellt':
        actionIcon = Icons.call_split;
        actionColor = Colors.greenAccent.shade700;
        break;
      case 'ausbauen':
        actionIcon = Icons.build_outlined;
        actionColor = Colors.green.shade600;
        break;
      case 'reduktion':
        actionIcon = Icons.remove_circle_outline;
        actionColor = Colors.brown.shade600;
        break;
      case 'füttern':
      case 'fuettern':
        actionIcon = Icons.restaurant;
        actionColor = Colors.orange.shade500;
        break;
      case 'futter entfernen':
        actionIcon = Icons.cleaning_services_outlined;
        actionColor = Colors.grey.shade600;
        break;
      case 'honig ernten':
        actionIcon = Icons.hive;
        actionColor = Colors.amber.shade600;
        break;
      case 'neue königin':
      case 'neue koenigin':
        actionIcon = Icons.star_outline;
        actionColor = Colors.yellow.shade800;
        break;
      case 'königin markiert':
      case 'koenigin markiert':
        actionIcon = Icons.brush_outlined;
        actionColor = Colors.pink.shade500;
        break;
      case 'schwarm einlogiert':
        actionIcon = Icons.home_work_outlined;
        actionColor = Colors.lightGreen.shade700;
        break;
      case 'stand auswintern':
        actionIcon = Icons.wb_sunny_outlined;
        actionColor = Colors.orangeAccent.shade400;
        break;
      case 'stand einwintern':
        actionIcon = Icons.ac_unit;
        actionColor = Colors.cyan.shade600;
        break;
      case 'freitext':
        actionIcon = Icons.notes;
        actionColor = Colors.blueGrey.shade600;
        break;
      default:
        actionIcon = Icons.event_note_outlined;
        actionColor = Theme.of(context).colorScheme.secondary;
    }

    IconData weatherIcon = Icons.cloud_outlined;
    final wLower = wetter.toLowerCase();
    if (wLower.contains('sonnig')) {
      weatherIcon = Icons.wb_sunny_outlined;
    } else if (wLower.contains('regen')) {
      weatherIcon = Icons.water_drop_outlined;
    } else if (wLower.contains('leicht bewölkt') ||
        wLower.contains('leicht bewoelkt')) {
      weatherIcon = Icons.wb_cloudy_outlined;
    } else if (wLower.contains('bewölkt') || wLower.contains('bewoelkt')) {
      weatherIcon = Icons.cloud_outlined;
    } else if (wLower.isNotEmpty) {
      weatherIcon = Icons.thermostat_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(actionIcon, color: actionColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (volkId.isNotEmpty)
                        Text(
                          'Volk $volkId',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                    ],
                  ),
                ),
                Text(
                  datum,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            if (wetter.isNotEmpty ||
                temperatur.isNotEmpty ||
                befund.isNotEmpty ||
                kommentar.isNotEmpty)
              const Divider(height: 32),

            if (wetter.isNotEmpty || temperatur.isNotEmpty) ...[
              Row(
                children: [
                  if (wetter.isNotEmpty) ...[
                    Icon(
                      weatherIcon,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      wetter,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 24),
                  ],
                  if (temperatur.isNotEmpty) ...[
                    Icon(
                      Icons.thermostat_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$temperatur°C',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],

            if (befund.isNotEmpty) ...[
              Text(
                'BEFUND',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(befund, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
            ],

            if (kommentar.isNotEmpty) ...[
              Text(
                'KOMMENTAR',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                kommentar,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogTab() {
    List<dynamic> logsList = [];

    if (_hiveDetails != null) {
      if (_hiveDetails!.containsKey('logs') && _hiveDetails!['logs'] is List) {
        logsList = _hiveDetails!['logs'];
      } else if (_hiveDetails!.containsKey('hive') &&
          _hiveDetails!['hive']['logs'] is List) {
        logsList = _hiveDetails!['hive']['logs'];
      }
    }

    Set<int> availableYears = {DateTime.now().year};
    for (final log in logsList) {
      final String dateStr = (log as Map)['datum']?.toString() ?? '';
      final DateTime? logDate = DateTime.tryParse(dateStr);
      if (logDate != null) {
        availableYears.add(logDate.year);
      }
    }

    List<int> sortedYears = availableYears.toList()
      ..sort((a, b) => b.compareTo(a));

    List<dynamic> filteredLogs = logsList.where((log) {
      final String dateStr = (log as Map)['datum']?.toString() ?? '';
      final DateTime? logDate = DateTime.tryParse(dateStr);
      if (logDate != null) {
        return logDate.year == _selectedLogYear;
      }
      return false;
    }).toList();

    filteredLogs.sort((a, b) {
      final String dateAStr = (a as Map)['datum']?.toString() ?? '';
      final String dateBStr = (b as Map)['datum']?.toString() ?? '';

      final DateTime? dateA = DateTime.tryParse(dateAStr);
      final DateTime? dateB = DateTime.tryParse(dateBStr);

      if (dateA != null && dateB != null) {
        return dateB.compareTo(dateA);
      }
      return dateBStr.compareTo(dateAStr);
    });

    final List<dynamic> listItems = [];
    String? currentCategory;

    for (final log in filteredLogs) {
      final String dateStr = (log as Map)['datum']?.toString() ?? '';
      final String category = _getLogCategory(dateStr);

      if (category != currentCategory) {
        listItems.add(category);
        currentCategory = category;
      }
      listItems.add(log);
    }

    Widget content;

    if (filteredLogs.isEmpty) {
      content = _ThemeRefreshIndicator(
        onRefresh: _loadHiveDetails,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    logsList.isEmpty
                        ? 'No log entries recorded yet'
                        : 'No log entries for $_selectedLogYear',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      content = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (ScrollNotification notification) {
                  if (notification is ScrollUpdateNotification) {
                    final metrics = notification.metrics;
                    if (metrics.maxScrollExtent > 0 && listItems.isNotEmpty) {
                      // Map the scroll percentage directly to the index array
                      final double progress =
                          (metrics.pixels / metrics.maxScrollExtent).clamp(
                            0.0,
                            1.0,
                          );
                      final int estimatedIndex =
                          (progress * (listItems.length - 1)).round();

                      final item = listItems[estimatedIndex];

                      String category = item is String
                          ? item
                          : _getLogCategory(
                              (item as Map)['datum']?.toString() ?? '',
                            );

                      if (category != _currentScrollCategory.value) {
                        _currentScrollCategory.value = category;
                        Future.microtask(() => HapticFeedback.selectionClick());
                      }
                    }

                    if (!_isScrollingLogs.value) {
                      _isScrollingLogs.value = true;
                    }

                    _scrollHideTimer?.cancel();
                    _scrollHideTimer = Timer(
                      const Duration(milliseconds: 1200),
                      () {
                        if (mounted) {
                          _isScrollingLogs.value = false;
                        }
                      },
                    );
                  }
                  return false;
                },
                child: Scrollbar(
                  controller: _logScrollController,
                  interactive: true,
                  thickness: 8.0,
                  radius: const Radius.circular(4.0),
                  child: _ThemeRefreshIndicator(
                    onRefresh: _loadHiveDetails,
                    child: ListView.builder(
                      cacheExtent: 3000,
                      controller: _logScrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16.0),
                      itemCount: listItems.length,
                      itemBuilder: (context, index) {
                        final item = listItems[index];

                        if (item is String) {
                          return Padding(
                            padding: const EdgeInsets.only(
                              top: 24.0,
                              bottom: 16.0,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 8.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_month,
                                        size: 16,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        item.toUpperCase(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onPrimaryContainer,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.2,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Divider(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant
                                        .withValues(alpha: 0.5),
                                    thickness: 2,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return _buildLogTile(
                          item as Map<String, dynamic>,
                          context,
                        );
                      },
                    ),
                  ),
                ),
              ),

              // UI isolated with AnimatedBuilder, completely eliminating entire screen rebuilds
              AnimatedBuilder(
                animation: Listenable.merge([
                  _isScrollingLogs,
                  _currentScrollCategory,
                ]),
                builder: (context, child) {
                  return AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    top: 32.0,
                    right: 24.0,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity:
                          _isScrollingLogs.value &&
                              _currentScrollCategory.value.isNotEmpty
                          ? 1.0
                          : 0.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 10.0,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          _currentScrollCategory.value.toUpperCase(),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.surface,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    int currentIndex = sortedYears.indexOf(_selectedLogYear);

    return Column(
      children: [
        Expanded(child: content),
        const Divider(height: 1, thickness: 1),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: currentIndex < sortedYears.length - 1
                    ? () {
                        setState(() {
                          _selectedLogYear = sortedYears[currentIndex + 1];
                        });
                      }
                    : null,
              ),
              const SizedBox(width: 16),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return SimpleDialog(
                        title: const Text('Select Year'),
                        children: sortedYears.map((year) {
                          return SimpleDialogOption(
                            onPressed: () {
                              setState(() {
                                _selectedLogYear = year;
                              });
                              Navigator.pop(context);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: Text(
                                year.toString(),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: year == _selectedLogYear
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: year == _selectedLogYear
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_selectedLogYear',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: currentIndex > 0
                    ? () {
                        setState(() {
                          _selectedLogYear = sortedYears[currentIndex - 1];
                        });
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChemTile(
    Map<String, dynamic> chem,
    double tileWidth,
    BuildContext context,
    bool isActive,
  ) {
    final String name = chem['name']?.toString() ?? 'Unknown Chemical';
    final String menge = chem['menge']?.toString() ?? '-';
    final String edatum = chem['edatum']?.toString() ?? '-';
    final String expdatum = chem['expdatum']?.toString() ?? '';
    final String quelle = chem['quelle']?.toString() ?? '-';

    // Inactive fields
    final String rdatum = chem['rdatum']?.toString() ?? '-';
    final String entsorgung = chem['entsorgung']?.toString() ?? '-';
    final String rmenge = chem['rmenge']?.toString() ?? '-';

    final bool noExpiration =
        expdatum.isEmpty ||
        expdatum == '00-00-0000' ||
        expdatum.contains('-1-11-30');

    final Color iconColor = isActive
        ? Colors.teal.shade600
        : Colors.grey.shade500;
    final Color bgColor = isActive
        ? Theme.of(context).colorScheme.surface
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);

    return Container(
      width: tileWidth,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (Icon, Name, Menge)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.science, color: iconColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isActive
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: isActive ? 1 : 0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              menge,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer
                                    .withValues(alpha: isActive ? 1 : 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Standard details
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Added: $edatum',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Source: $quelle',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      noExpiration
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_rounded,
                      size: 14,
                      color: isActive && !noExpiration
                          ? Colors.orange.shade700
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      noExpiration ? 'Does not expire' : 'Expires: $expdatum',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isActive && !noExpiration
                            ? Colors.orange.shade700
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: isActive && !noExpiration
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Inactive details banner
          if (!isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: 0.3),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'DISPOSED ($rdatum)',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Amount: $rmenge',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Method: $entsorgung',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChemicalsTab() {
    List<dynamic> chemsList = [];

    // Safely extract chemicals array
    if (_hiveDetails != null) {
      if (_hiveDetails!.containsKey('chemicals') &&
          _hiveDetails!['chemicals'] is List) {
        chemsList = _hiveDetails!['chemicals'];
      } else if (_hiveDetails!.containsKey('hive') &&
          _hiveDetails!['hive']['chemicals'] is List) {
        chemsList = _hiveDetails!['hive']['chemicals'];
      }
    }

    if (chemsList.isEmpty) {
      return _ThemeRefreshIndicator(
        onRefresh: _loadHiveDetails,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.science_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No chemicals recorded yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final activeChems = chemsList.where((c) {
      final activeVal = (c as Map)['active']?.toString();
      return activeVal == '1' || activeVal == 'true' || activeVal == null;
    }).toList();

    final inactiveChems = chemsList.where((c) {
      final activeVal = (c as Map)['active']?.toString();
      return activeVal == '0' || activeVal == 'false';
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 800;
        final bool isMedium = constraints.maxWidth > 500 && !isWide;
        final double spacing = 16.0;
        final double fullWidth = constraints.maxWidth - (spacing * 2);

        final double tileWidth = isWide
            ? (fullWidth - (spacing * 2)) / 3
            : (isMedium ? (fullWidth - spacing) / 2 : fullWidth);

        return _ThemeRefreshIndicator(
          onRefresh: _loadHiveDetails,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (activeChems.isNotEmpty)
                  Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: activeChems
                        .map(
                          (c) => _buildChemTile(
                            c as Map<String, dynamic>,
                            tileWidth,
                            context,
                            true,
                          ),
                        )
                        .toList(),
                  ),

                if (activeChems.isEmpty && inactiveChems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      'No active chemicals.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                if (inactiveChems.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: Text(
                        'Disposed Chemicals (${inactiveChems.length})',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(top: 16.0),
                      initiallyExpanded: false,
                      children: [
                        Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: inactiveChems
                              .map(
                                (c) => _buildChemTile(
                                  c as Map<String, dynamic>,
                                  tileWidth,
                                  context,
                                  false,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserTile(
    Map<String, dynamic> user,
    double tileWidth,
    BuildContext context,
  ) {
    final String firstName = user['firstname']?.toString() ?? '';
    final String lastName = user['lastname']?.toString() ?? '';
    final String username = user['username']?.toString() ?? '';
    final int permission =
        int.tryParse(user['permission']?.toString() ?? '') ?? 0;

    final String fullName = '$firstName $lastName'.trim();
    final String displayName = fullName.isNotEmpty
        ? fullName
        : (username.isNotEmpty ? username : 'Unknown User');
    final String initials = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : '?';

    String permLabel = 'Viewer';
    Color permColor = Colors.grey.shade700;
    Color permBg = Colors.grey.shade200;
    IconData permIcon = Icons.visibility;

    if (permission == 2) {
      permLabel = 'Owner';
      permColor = Colors.red.shade700;
      permBg = Colors.red.shade50;
      permIcon = Icons.admin_panel_settings;
    } else if (permission == 1) {
      permLabel = 'Editor';
      permColor = Colors.orange.shade700;
      permBg = Colors.orange.shade50;
      permIcon = Icons.edit;
    }

    return Container(
      width: tileWidth,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: permColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initials,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: permColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (fullName.isNotEmpty && username.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '@$username',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: permBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(permIcon, size: 14, color: permColor),
                  const SizedBox(width: 4),
                  Text(
                    permLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: permColor,
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

  Widget _buildPermissionsTab() {
    List<dynamic> usersList = [];

    // Safely extract users array
    if (_hiveDetails != null) {
      if (_hiveDetails!.containsKey('users_perm_list') &&
          _hiveDetails!['users_perm_list'] is List) {
        usersList = _hiveDetails!['users_perm_list'];
      } else if (_hiveDetails!.containsKey('hive') &&
          _hiveDetails!['hive']['users_perm_list'] is List) {
        usersList = _hiveDetails!['hive']['users_perm_list'];
      }
    }

    if (usersList.isEmpty) {
      return _ThemeRefreshIndicator(
        onRefresh: _loadHiveDetails,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.group_off_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No users found',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Sort users: Highest permission first, then alphabetically by firstname
    usersList.sort((a, b) {
      final int permA =
          int.tryParse((a as Map)['permission']?.toString() ?? '') ?? 0;
      final int permB =
          int.tryParse((b as Map)['permission']?.toString() ?? '') ?? 0;

      if (permA != permB) {
        return permB.compareTo(permA); // Descending (Owner -> Editor -> Viewer)
      }

      final String nameA = a['firstname']?.toString().toLowerCase() ?? '';
      final String nameB = b['firstname']?.toString().toLowerCase() ?? '';
      return nameA.compareTo(nameB);
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 800;
        final bool isMedium = constraints.maxWidth > 500 && !isWide;
        final double spacing = 16.0;
        final double fullWidth = constraints.maxWidth - (spacing * 2);

        final double tileWidth = isWide
            ? (fullWidth - (spacing * 2)) / 3
            : (isMedium ? (fullWidth - spacing) / 2 : fullWidth);

        return _ThemeRefreshIndicator(
          onRefresh: _loadHiveDetails,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: usersList
                      .map(
                        (u) => _buildUserTile(
                          u as Map<String, dynamic>,
                          tileWidth,
                          context,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String pageTitle = _isLoading
        ? 'Loading...'
        : (_hiveDetails?['hive']?['name'] ?? 'Hive Details');

    Widget titleWidget;
    if (_isLoading || _hiveDetails == null) {
      titleWidget = Text(pageTitle);
    } else {
      final int permission =
          int.tryParse(
            _hiveDetails!['hive']?['permission']?.toString() ?? '',
          ) ??
          0;
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

      titleWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(pageTitle),
          const SizedBox(width: 8),
          Tooltip(
            message: permissionTooltip,
            child: Icon(
              permissionIcon,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final int currentPermission =
        int.tryParse(_hiveDetails?['hive']?['permission']?.toString() ?? '') ??
        0;
    final bool isAdmin = currentPermission == 2;
    // Info, Volks, Log, Chem = 4 tabs for standard users. +1 for Admins
    final int tabCount = _isLoading ? 1 : (isAdmin ? 5 : 4);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBackToHome(context);
      },
      child: DefaultTabController(
        length: tabCount,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Home',
              onPressed: () => _goBackToHome(context),
            ),
            title: titleWidget,
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () async {
                  HapticFeedback.heavyImpact();
                  await attemptLogoutInIsolate();
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  children: [
                    _buildInfoTab(),
                    _buildVolksTab(),
                    _buildLogTab(),
                    _buildChemicalsTab(),
                    if (isAdmin) _buildPermissionsTab(),
                  ],
                ),
          bottomNavigationBar: _isLoading
              ? null
              : Container(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: SafeArea(
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelPadding: const EdgeInsets.symmetric(vertical: 4.0),
                      tabs: [
                        const Tab(text: 'Info', icon: Icon(Icons.info_outline)),
                        const Tab(
                          text: 'Volks',
                          icon: Icon(Icons.hive_outlined),
                        ),
                        const Tab(text: 'Log', icon: Icon(Icons.receipt_long)),
                        const Tab(
                          text: 'Chem',
                          icon: Icon(Icons.science_outlined),
                        ),
                        if (isAdmin)
                          const Tab(
                            text: 'Perms',
                            icon: Icon(Icons.admin_panel_settings),
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
