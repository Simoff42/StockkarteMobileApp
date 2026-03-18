import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;
import 'dart:convert';
import 'dart:isolate';
import 'dart:async';

// Import your globally instantiated native backend
import '../core/native_backend.dart';

// Reuse native string helpers for logout functionality
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

class VolkScreen extends StatefulWidget {
  final String hiveId;
  final String volkId;

  const VolkScreen({super.key, required this.hiveId, required this.volkId});

  @override
  State<VolkScreen> createState() => _VolkScreenState();
}

class _VolkScreenState extends State<VolkScreen> {
  Map<String, dynamic>? _volkDetails;
  bool _isLoading = true;
  int _permission = 0;
  String _hiveName = '';
  List<dynamic>? _volkLogs;

  // --- Scroll & Time Scroller State ---
  final ScrollController _logScrollController = ScrollController();
  final ValueNotifier<String> _currentScrollCategory = ValueNotifier<String>(
    '',
  );
  final ValueNotifier<bool> _isScrollingLogs = ValueNotifier<bool>(false);
  Timer? _scrollHideTimer;
  int _selectedLogYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadVolkDetails();
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    _currentScrollCategory.dispose();
    _isScrollingLogs.dispose();
    _scrollHideTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadVolkDetails() async {
    final int hiveId = int.tryParse(widget.hiveId) ?? 0;
    final jsonString = await fetchHiveDetailsInIsolate(hiveId);

    if (mounted) {
      setState(() {
        try {
          final dynamic decoded = jsonDecode(jsonString);
          Map<String, dynamic>? hiveData;

          if (decoded is Map<String, dynamic>) {
            hiveData = decoded;
          } else if (decoded is List && decoded.isNotEmpty) {
            hiveData = decoded.first as Map<String, dynamic>;
          }

          if (hiveData != null) {
            if (hiveData.containsKey('hive') && hiveData['hive'] is Map) {
              _permission =
                  int.tryParse(
                    hiveData['hive']['permission']?.toString() ?? '',
                  ) ??
                  0;
              _hiveName = hiveData['hive']['name']?.toString() ?? '';
            } else {
              _permission =
                  int.tryParse(hiveData['permission']?.toString() ?? '') ?? 0;
              _hiveName = hiveData['name']?.toString() ?? '';
            }
            List<dynamic> volksList = [];
            if (hiveData.containsKey('volks') && hiveData['volks'] is List) {
              volksList = hiveData['volks'];
            } else if (hiveData.containsKey('hive') &&
                hiveData['hive']['volks'] is List) {
              volksList = hiveData['hive']['volks'];
            }

            for (var v in volksList) {
              if (v is Map<String, dynamic> &&
                  v['id']?.toString() == widget.volkId) {
                _volkDetails = v;
                break;
              }
            }

            List<dynamic> allLogs = [];

            allLogs = hiveData['hive']['logs'];

            _volkLogs = allLogs
                .where((i) => i['id'].toString() == widget.volkId.toString())
                .toList();
          }
        } catch (e) {
          debugPrint('Error parsing volk details: $e');
        }
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard(String label, String text) {
    if (text == 'N/A' || text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied to clipboard!')));
  }

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop(); // Reverses the animation back to the HiveScreen
    } else {
      // Safe fallback just in case the user arrived here directly via a deep link
      context.go('/Hive?id=${widget.hiveId}');
    }
  }

  int _extractNumber(String val) {
    final match = RegExp(r'\d+').firstMatch(val);
    if (match != null) {
      return int.parse(match.group(0)!);
    }
    return 0;
  }

  Widget _buildGraphicalHive(String brutStr, String honigStr, String superStr) {
    final int bCount = _extractNumber(brutStr);
    final int hCount = _extractNumber(honigStr);
    final int sCount = _extractNumber(superStr);

    List<Widget> hiveStack = [];

    // Roof
    hiveStack.add(
      Container(
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.onSecondary.withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              offset: const Offset(0, 2),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );

    Widget buildBox(
      String label,
      int combsCount,
      Color combColor,
      String rawText, {
      bool isSuper = false,
      bool isBrood = false,
    }) {
      final double boxHeight = isSuper ? 50.0 : (isBrood ? 80.0 : 70.0);
      return Container(
        height: boxHeight,
        margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 1),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              offset: const Offset(0, 2),
              blurRadius: 2,
            ),
          ],
        ),
        child: Stack(
          children: [
            if (combsCount > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: List.generate(
                      combsCount > 20 ? 20 : combsCount,
                      (index) => Container(
                        width: 8,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: combColor,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (combsCount == 0 && !isSuper)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: Text(
                    'No Combs',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$label: $rawText',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Honey Supers
    if (sCount > 0) {
      int displaySupers = sCount > 4 ? 4 : sCount;
      for (int i = 0; i < displaySupers; i++) {
        hiveStack.add(
          buildBox(
            'Honey Super',
            0,
            Colors.transparent,
            sCount > 1 ? '${i + 1}/$sCount' : superStr,
            isSuper: true,
          ),
        );
      }
    } else if (superStr != 'N/A' && superStr.isNotEmpty && superStr != '0') {
      hiveStack.add(
        buildBox('Honey Super', 0, Colors.transparent, superStr, isSuper: true),
      );
    }

    // Honey Box
    hiveStack.add(
      buildBox(
        'Honey Box',
        hCount,
        Theme.of(context).colorScheme.primary,
        honigStr,
      ),
    );

    // Brood Box
    hiveStack.add(
      buildBox(
        'Brood Box',
        bCount,
        Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.7),
        brutStr,
        isBrood: true,
      ),
    );

    // Bottom Board
    hiveStack.add(
      Container(
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              offset: const Offset(0, 3),
              blurRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 60,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Column(mainAxisSize: MainAxisSize.min, children: hiveStack),
        ),
      ),
    );
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
    if (_volkDetails == null || _volkDetails!.isEmpty) {
      return Center(
        child: Text(
          'Could not load details for Volk ${widget.volkId}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    final volk = _volkDetails!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double spacing = 16.0;
        final double fullWidth = constraints.maxWidth - (spacing * 2);

        final double halfWidth = (fullWidth - spacing) / 2;

        final String valNummer = volk['nummer']?.toString() ?? 'N/A';
        final String valKonigin = volk['konigin']?.toString() ?? 'unmarkiert';
        final String valKoniginJahr = volk['konigin_jahr']?.toString() ?? 'N/A';
        final String valDatum = volk['datum']?.toString() ?? 'N/A';
        final String valKommentar =
            volk['kommentar']?.toString() ??
            volk['bemerkung']?.toString() ??
            volk['notes']?.toString() ??
            '';
        final String valActive =
            (volk['active']?.toString() == '1' ||
                volk['active']?.toString() == 'true' ||
                volk['active'] == null)
            ? 'Active'
            : 'Inactive';
        final String valHerkunft = volk['herkunft']?.toString() ?? 'N/A';
        final String valHonigwaben = volk['honigwaben']?.toString() ?? 'N/A';
        final String valBrutwaben = volk['brutwaben']?.toString() ?? 'N/A';
        final String valHonigraum = volk['honigraum']?.toString() ?? 'N/A';
        final String valTyp = volk['typ']?.toString() ?? 'N/A';

        Color qColor = Colors.grey.shade300;
        Color qTextColor = Colors.black87;
        String qText = valKonigin.toUpperCase();

        switch (valKonigin.toLowerCase()) {
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

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              _buildInfoCard(
                title: 'Number',
                icon: Icons.numbers,
                width: fullWidth,
                onTap: () => _copyToClipboard('Number', valNummer),
                content: Text(
                  valNummer,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _buildInfoCard(
                title: 'Type',
                icon: Icons.category_outlined,
                width: halfWidth,
                onTap: () => _copyToClipboard('Type', valTyp),
                content: Text(
                  valTyp,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _buildInfoCard(
                title: 'Status',
                icon: Icons.info_outline,
                width: halfWidth,
                onTap: () => _copyToClipboard('Status', valActive),
                content: Row(
                  children: [
                    Icon(
                      valActive == 'Active'
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      color: valActive == 'Active'
                          ? Colors.green.shade600
                          : Colors.red.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      valActive,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              _buildInfoCard(
                title: 'Queen',
                icon: Icons.bug_report,
                width: halfWidth,
                onTap: () => _copyToClipboard('Queen', valKonigin),
                content: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
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
              ),
              _buildInfoCard(
                title: 'Queen Year',
                icon: Icons.event,
                width: halfWidth,
                onTap: () => _copyToClipboard('Queen Year', valKoniginJahr),
                content: Text(
                  valKoniginJahr,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _buildInfoCard(
                title: 'Origin',
                icon: Icons.place_outlined,
                width: halfWidth,
                onTap: () => _copyToClipboard('Origin', valHerkunft),
                content: Text(
                  valHerkunft,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _buildInfoCard(
                title: 'Creation Date',
                icon: Icons.calendar_today_outlined,
                width: halfWidth,
                onTap: () => _copyToClipboard('Creation Date', valDatum),
                content: Text(
                  valDatum,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _buildInfoCard(
                title: 'Volk Configuration',
                icon: Icons.stacked_bar_chart,
                width: fullWidth,
                content: _buildGraphicalHive(
                  valBrutwaben,
                  valHonigwaben,
                  valHonigraum,
                ),
              ),
              if (valKommentar.isNotEmpty)
                _buildInfoCard(
                  title: 'Notes',
                  icon: Icons.notes,
                  width: fullWidth,
                  onTap: () => _copyToClipboard('Notes', valKommentar),
                  content: Text(
                    valKommentar,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        );
      },
    );
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

  Widget _buildLogTile(Map<String, dynamic> log, BuildContext context) {
    final String wetter = log['wetter']?.toString() ?? '';
    final String temperatur = log['temperatur']?.toString() ?? '';
    final String action = log['action']?.toString() ?? 'Unknown Action';
    final String befund = log['befund']?.toString() ?? '';
    final String datum = log['datum']?.toString() ?? 'N/A';
    final String kommentar = log['kommentar']?.toString() ?? '';

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
                  child: Text(
                    action,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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
                      temperatur,
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
    if (_volkLogs != null) {
      logsList = List.from(_volkLogs!);
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
      content = Center(
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
                  child: ListView.builder(
                    controller: _logScrollController,
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
              Text(
                '$_selectedLogYear',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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

  @override
  Widget build(BuildContext context) {
    final String volkName = 'Volk ${_volkDetails?['nummer'] ?? widget.volkId}';
    final String pageTitle = _isLoading
        ? 'Loading...'
        : (_hiveName.isNotEmpty ? '$_hiveName / $volkName' : volkName);

    Widget titleWidget;
    if (_isLoading || _volkDetails == null) {
      titleWidget = Text(pageTitle);
    } else {
      IconData permissionIcon;
      String permissionTooltip;

      switch (_permission) {
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack(context);
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Hive',
              onPressed: () => _goBack(context),
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
              : TabBarView(children: [_buildInfoTab(), _buildLogTab()]),
          bottomNavigationBar: Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: const SafeArea(
              child: TabBar(
                indicatorSize: TabBarIndicatorSize.tab,
                labelPadding: EdgeInsets.symmetric(vertical: 4.0),
                tabs: [
                  Tab(text: 'Info', icon: Icon(Icons.info_outline)),
                  Tab(text: 'Log', icon: Icon(Icons.receipt_long)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
