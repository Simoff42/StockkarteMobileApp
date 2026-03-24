import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'dart:async';

import 'action_popups.dart';
import '../core/api/api.dart';

class _VarroaChartWidget extends StatefulWidget {
  final List<dynamic> varroaData;
  final List<dynamic> volkLogs;
  final bool isFullscreen;
  final bool initialShowTreatments;

  const _VarroaChartWidget({
    Key? key,
    required this.varroaData,
    required this.volkLogs,
    this.isFullscreen = false,
    this.initialShowTreatments = true,
  }) : super(key: key);

  @override
  State<_VarroaChartWidget> createState() => _VarroaChartWidgetState();
}

class _VarroaChartWidgetState extends State<_VarroaChartWidget> {
  DateTime _chartEndDate = DateTime.now();
  double _chartVisibleDays = 90.0;

  double _baseVisibleDays = 90.0;
  DateTime _baseEndDate = DateTime.now();
  Offset _baseFocalPoint = Offset.zero;

  late bool _showTreatments;

  @override
  void initState() {
    super.initState();
    _showTreatments = widget.initialShowTreatments;
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> sortedData = List.from(widget.varroaData);

    // Sort by date ascending
    sortedData.sort((a, b) {
      final dateA = DateTime.tryParse(a['datum'].toString()) ?? DateTime.now();
      final dateB = DateTime.tryParse(b['datum'].toString()) ?? DateTime.now();
      return dateA.compareTo(dateB);
    });

    List<Map<String, dynamic>> treatments = [];
    for (var log in widget.volkLogs) {
      final action = log['action']?.toString().toLowerCase() ?? '';
      if (action == 'varroa behandeln') {
        final d = DateTime.tryParse(log['datum']?.toString() ?? '');
        if (d != null) {
          treatments.add({'date': d, 'original': log});
        }
      }
    }

    final DateTime maxD = _chartEndDate;
    final DateTime minD = _chartEndDate.subtract(
      Duration(milliseconds: (_chartVisibleDays * 24 * 3600 * 1000).round()),
    );

    double maxPerDay = 0;
    List<Map<String, dynamic>> processedData = [];

    for (var item in sortedData) {
      final perDay = (item['per_day'] as num).toDouble();
      final days = (item['days'] as num).toDouble();
      final endDate =
          DateTime.tryParse(item['datum'].toString()) ?? DateTime.now();

      if (endDate.isBefore(minD)) continue;

      final startDate = endDate.subtract(Duration(days: days.round()));

      if (startDate.isAfter(maxD)) continue;

      final clampedStartDate = startDate.isBefore(minD) ? minD : startDate;
      final clampedEndDate = endDate.isAfter(maxD) ? maxD : endDate;

      if (perDay > maxPerDay) maxPerDay = perDay;

      processedData.add({
        'original': item,
        'startDate': clampedStartDate,
        'endDate': clampedEndDate,
        'perDay': perDay,
      });
    }

    final double totalMilliseconds = maxD
        .difference(minD)
        .inMilliseconds
        .toDouble();
    if (totalMilliseconds <= 0) return const SizedBox.shrink();

    if (maxPerDay == 0) maxPerDay = 1;

    return Container(
      height: widget.isFullscreen ? double.infinity : 300,
      padding: const EdgeInsets.all(16.0),
      decoration: widget.isFullscreen
          ? BoxDecoration(color: Theme.of(context).colorScheme.surface)
          : BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pest_control, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Varroa Drop / Day',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _showTreatments
                      ? Icons.medication
                      : Icons.medication_outlined,
                  color: _showTreatments ? Colors.purple.shade600 : null,
                ),
                tooltip: _showTreatments
                    ? 'Hide Treatments'
                    : 'Show Treatments',
                onPressed: () {
                  setState(() {
                    _showTreatments = !_showTreatments;
                  });
                },
              ),
              IconButton(
                icon: Icon(
                  widget.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                ),
                onPressed: () async {
                  if (widget.isFullscreen) {
                    Navigator.of(context).pop();
                  } else {
                    await SystemChrome.setPreferredOrientations([
                      DeviceOrientation.landscapeRight,
                      DeviceOrientation.landscapeLeft,
                    ]);
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (context) => Scaffold(
                          appBar: AppBar(
                            toolbarHeight: 40,
                            title: const Text(
                              'Varroa Statistics',
                              style: TextStyle(fontSize: 16),
                            ),
                            leading: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                          body: SafeArea(
                            child: _VarroaChartWidget(
                              varroaData: widget.varroaData,
                              volkLogs: widget.volkLogs,
                              isFullscreen: true,
                              initialShowTreatments: _showTreatments,
                            ),
                          ),
                        ),
                      ),
                    );
                    await SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                      DeviceOrientation.portraitDown,
                    ]);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double contentWidth = constraints.maxWidth;
                final double contentHeight = constraints.maxHeight - 60;

                List<Widget> monthMarkers = [];
                DateTime currentMonth = DateTime(minD.year, minD.month + 1, 1);
                double lastMarkerPosition = -100;

                final monthNames = [
                  'Jan',
                  'Feb',
                  'Mar',
                  'Apr',
                  'May',
                  'Jun',
                  'Jul',
                  'Aug',
                  'Sep',
                  'Oct',
                  'Nov',
                  'Dec',
                ];

                monthMarkers.add(
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Text(
                      '${monthNames[minD.month - 1]} ${minD.year}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
                lastMarkerPosition = 0;

                while (currentMonth.isBefore(maxD)) {
                  final leftOffset =
                      (currentMonth.difference(minD).inMilliseconds /
                          totalMilliseconds) *
                      contentWidth;

                  if (leftOffset - lastMarkerPosition >= 40) {
                    final monthName = monthNames[currentMonth.month - 1];

                    monthMarkers.add(
                      Positioned(
                        left: leftOffset,
                        top: 0,
                        bottom: 20,
                        child: Container(
                          width: 1,
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    );

                    monthMarkers.add(
                      Positioned(
                        left: leftOffset + 4,
                        top: 0,
                        child: Text(
                          '$monthName ${currentMonth.year}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    );
                    lastMarkerPosition = leftOffset;
                  }

                  currentMonth = DateTime(
                    currentMonth.year,
                    currentMonth.month + 1,
                    1,
                  );
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (details) {
                    _baseVisibleDays = _chartVisibleDays;
                    _baseEndDate = _chartEndDate;
                    _baseFocalPoint = details.localFocalPoint;
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      double newVisibleDays = (_baseVisibleDays / details.scale)
                          .clamp(7.0, 365.0 * 10);
                      double ratio = _baseFocalPoint.dx / contentWidth;
                      double dx =
                          details.localFocalPoint.dx - _baseFocalPoint.dx;
                      double daysPan = -(dx / contentWidth) * newVisibleDays;

                      double endDaysOffset =
                          daysPan +
                          (newVisibleDays - _baseVisibleDays) * (1 - ratio);

                      _chartVisibleDays = newVisibleDays;
                      _chartEndDate = _baseEndDate.add(
                        Duration(
                          milliseconds: (endDaysOffset * 24 * 3600 * 1000)
                              .round(),
                        ),
                      );

                      final now = DateTime.now();
                      if (_chartEndDate.isAfter(now)) {
                        _chartEndDate = now;
                      }
                    });
                  },
                  child: SizedBox(
                    width: contentWidth,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 20,
                          height: 1,
                          child: Container(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        ...monthMarkers,
                        ...processedData.map((item) {
                          final original =
                              item['original'] as Map<String, dynamic>;
                          final startDate = item['startDate'] as DateTime;
                          final endDate = item['endDate'] as DateTime;
                          final perDay = item['perDay'] as double;

                          final leftOffset =
                              (startDate.difference(minD).inMilliseconds /
                                  totalMilliseconds) *
                              contentWidth;
                          final rightOffset =
                              (maxD.difference(endDate).inMilliseconds /
                                  totalMilliseconds) *
                              contentWidth;
                          final itemWidth =
                              contentWidth - leftOffset - rightOffset;

                          final barHeight =
                              (perDay / maxPerDay) * contentHeight;
                          final displayHeight = barHeight < 4 ? 4.0 : barHeight;
                          final displayWidth = itemWidth < 2 ? 2.0 : itemWidth;

                          return Positioned(
                            left: leftOffset + (displayWidth / 2),
                            bottom: 20,
                            child: FractionalTranslation(
                              translation: const Offset(-0.5, 0.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (displayWidth >= 10 ||
                                      _chartVisibleDays < 180)
                                    Text(
                                      perDay.toStringAsFixed(1),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                    ),
                                  if (displayWidth >= 10 ||
                                      _chartVisibleDays < 180)
                                    const SizedBox(height: 2),
                                  Tooltip(
                                    message:
                                        'Date: ${original['datum']}\nCount: ${original['count']}\nDays: ${original['days']}\nPer Day: ${perDay.toStringAsFixed(2)}',
                                    child: Container(
                                      width: displayWidth,
                                      height: displayHeight,
                                      decoration: BoxDecoration(
                                        color: perDay > 1.0
                                            ? Colors.red.shade400.withValues(
                                                alpha: 0.8,
                                              )
                                            : Colors.teal.shade400.withValues(
                                                alpha: 0.8,
                                              ),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(2),
                                            ),
                                        border: Border.all(
                                          color: Colors.black.withValues(
                                            alpha: 0.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        if (_showTreatments)
                          ...treatments
                              .where((t) {
                                final d = t['date'] as DateTime;
                                return !d.isBefore(minD) && !d.isAfter(maxD);
                              })
                              .map((t) {
                                final date = t['date'] as DateTime;
                                final original =
                                    t['original'] as Map<String, dynamic>;
                                final befund =
                                    original['befund']?.toString() ?? '';
                                final kommentar =
                                    original['kommentar']?.toString() ?? '';

                                final leftOffset =
                                    (date.difference(minD).inMilliseconds /
                                        totalMilliseconds) *
                                    contentWidth;

                                String tooltipMsg =
                                    'Varroa Treatment\nDate: ${date.day}.${date.month}.${date.year}';
                                if (befund.isNotEmpty)
                                  tooltipMsg += '\nBefund: $befund';
                                if (kommentar.isNotEmpty)
                                  tooltipMsg += '\nNote: $kommentar';

                                return Positioned(
                                  left: leftOffset,
                                  top: 0,
                                  bottom: 20,
                                  child: FractionalTranslation(
                                    translation: const Offset(-0.5, 0.0),
                                    child: Tooltip(
                                      message: tooltipMsg,
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.shade50,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.purple.shade400,
                                                width: 2,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.1),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              Icons.medication,
                                              color: Colors.purple.shade700,
                                              size: 18,
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              width: 3,
                                              color: Colors.purple.shade400
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                        ...processedData.map((item) {
                          final endDate = item['endDate'] as DateTime;
                          final dateLabel = '${endDate.day}.${endDate.month}.';
                          final rightOffset =
                              (maxD.difference(endDate).inMilliseconds /
                                  totalMilliseconds) *
                              contentWidth;
                          final rightEdge = contentWidth - rightOffset;

                          if (_chartVisibleDays > 120) {
                            return const SizedBox.shrink();
                          }

                          return Positioned(
                            left: rightEdge - 20,
                            bottom: 0,
                            width: 40,
                            child: Text(
                              dateLabel,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 9,
                                  ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CombHistoryChartWidget extends StatefulWidget {
  final List<dynamic> volkLogs;
  final bool isFullscreen;
  final bool initialShowBrut;
  final bool initialShowHonig;
  final bool initialShowSuper;
  final bool initialShowHarvests;

  const _CombHistoryChartWidget({
    Key? key,
    required this.volkLogs,
    this.isFullscreen = false,
    this.initialShowBrut = true,
    this.initialShowHonig = true,
    this.initialShowSuper = true,
    this.initialShowHarvests = true,
  }) : super(key: key);

  @override
  State<_CombHistoryChartWidget> createState() =>
      _CombHistoryChartWidgetState();
}

class _CombChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final DateTime minD;
  final DateTime maxD;
  final int maxCombs;
  final bool showBrut;
  final bool showHonig;
  final bool showSuper;
  final Color brutColor;
  final Color honigColor;
  final Color superColor;

  _CombChartPainter({
    required this.data,
    required this.minD,
    required this.maxD,
    required this.maxCombs,
    required this.showBrut,
    required this.showHonig,
    required this.showSuper,
    required this.brutColor,
    required this.honigColor,
    required this.superColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double totalMs = maxD.difference(minD).inMilliseconds.toDouble();
    if (totalMs <= 0) return;

    void drawLine(String key, Color color) {
      final paint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      bool first = true;

      for (var item in data) {
        final val = item[key] as int?;
        if (val == null) continue;

        final date = item['date'] as DateTime;
        final x = (date.difference(minD).inMilliseconds / totalMs) * size.width;
        final y = size.height - ((val / maxCombs) * size.height);

        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }

      if (!first) {
        canvas.drawPath(path, paint);
      }
    }

    if (showSuper) drawLine('super', superColor);
    if (showHonig) drawLine('honig', honigColor);
    if (showBrut) drawLine('brut', brutColor);
  }

  @override
  bool shouldRepaint(covariant _CombChartPainter oldDelegate) => true;
}

class _CombHistoryChartWidgetState extends State<_CombHistoryChartWidget> {
  DateTime _chartEndDate = DateTime.now();
  double _chartVisibleDays = 90.0;

  double _baseVisibleDays = 90.0;
  DateTime _baseEndDate = DateTime.now();
  Offset _baseFocalPoint = Offset.zero;

  late bool _showBrut;
  late bool _showHonig;
  late bool _showSuper;
  late bool _showHarvests;

  @override
  void initState() {
    super.initState();
    _showBrut = widget.initialShowBrut;
    _showHonig = widget.initialShowHonig;
    _showSuper = widget.initialShowSuper;
    _showHarvests = widget.initialShowHarvests;
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> sortedLogs = List.from(widget.volkLogs);

    sortedLogs.sort((a, b) {
      final dateA = DateTime.tryParse(a['datum'].toString()) ?? DateTime.now();
      final dateB = DateTime.tryParse(b['datum'].toString()) ?? DateTime.now();
      return dateA.compareTo(dateB);
    });

    List<Map<String, dynamic>> combData = [];
    int maxCombs = 10;

    int? lastB;
    int? lastH;
    int? lastS;
    Map<String, dynamic>? lastOriginal;

    bool isDissolved = false;
    DateTime? dissolvedDate;

    for (var log in sortedLogs) {
      final date = DateTime.tryParse(log['datum']?.toString() ?? '');
      if (date == null) continue;

      final action = log['action']?.toString().toLowerCase() ?? '';
      if (action == 'volk auflösen' || action == 'volk aufloesen') {
        isDissolved = true;
        dissolvedDate = date;
      }

      final bStr = log['brutwaben']?.toString();
      final hStr = log['honigwaben']?.toString();
      final sStr = log['honigraum']?.toString();

      int? b;
      int? h;
      int? s;

      if (bStr != null && bStr.isNotEmpty && bStr != 'N/A') {
        final match = RegExp(r'\d+').firstMatch(bStr);
        if (match != null) b = int.tryParse(match.group(0)!);
      }
      if (hStr != null && hStr.isNotEmpty && hStr != 'N/A') {
        final match = RegExp(r'\d+').firstMatch(hStr);
        if (match != null) h = int.tryParse(match.group(0)!);
      }
      if (sStr != null && sStr.isNotEmpty && sStr != 'N/A') {
        final match = RegExp(r'\d+').firstMatch(sStr);
        if (match != null) s = int.tryParse(match.group(0)!);
      }

      if (b != null || h != null || s != null) {
        combData.add({
          'date': date,
          'brut': b,
          'honig': h,
          'super': s,
          'original': log,
        });

        lastB = b;
        lastH = h;
        lastS = s;
        lastOriginal = log;

        if (b != null && b > maxCombs) maxCombs = b;
        if (h != null && h > maxCombs) maxCombs = h;
        if (s != null && s > maxCombs) maxCombs = s;
      }
    }

    if (combData.isNotEmpty) {
      DateTime extensionDate = isDissolved && dissolvedDate != null
          ? dissolvedDate
          : DateTime.now();
      DateTime lastDate = combData.last['date'] as DateTime;

      if (extensionDate.isAfter(lastDate)) {
        combData.add({
          'date': extensionDate,
          'brut': lastB,
          'honig': lastH,
          'super': lastS,
          'original': lastOriginal ?? {},
          'isExtension': true,
        });
      }
    }

    final DateTime maxD = _chartEndDate;
    final DateTime minD = _chartEndDate.subtract(
      Duration(milliseconds: (_chartVisibleDays * 24 * 3600 * 1000).round()),
    );

    final double totalMilliseconds = maxD
        .difference(minD)
        .inMilliseconds
        .toDouble();
    if (totalMilliseconds <= 0) return const SizedBox.shrink();

    final Color brutColor = Theme.of(context).colorScheme.tertiary;
    final Color honigColor = Theme.of(context).colorScheme.primary;
    final Color superColor = Colors.amber.shade700;

    List<Map<String, dynamic>> honeyHarvests = [];
    for (var log in sortedLogs) {
      final action = log['action']?.toString().toLowerCase() ?? '';
      if (action == 'honig ernten') {
        final d = DateTime.tryParse(log['datum']?.toString() ?? '');
        if (d != null) {
          honeyHarvests.add({'date': d, 'original': log});
        }
      }
    }

    return Container(
      height: widget.isFullscreen ? double.infinity : 300,
      padding: const EdgeInsets.all(16.0),
      decoration: widget.isFullscreen
          ? BoxDecoration(color: Theme.of(context).colorScheme.surface)
          : BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.stacked_bar_chart, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Comb History',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => setState(() => _showBrut = !_showBrut),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 12,
                            color: _showBrut ? brutColor : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'B',
                            style: TextStyle(
                              color: _showBrut ? brutColor : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => setState(() => _showHonig = !_showHonig),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 12,
                            color: _showHonig ? honigColor : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'H',
                            style: TextStyle(
                              color: _showHonig ? honigColor : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => setState(() => _showSuper = !_showSuper),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 12,
                            color: _showSuper ? superColor : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'S',
                            style: TextStyle(
                              color: _showSuper ? superColor : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => setState(() => _showHarvests = !_showHarvests),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Icon(
                        _showHarvests ? Icons.hive : Icons.hive_outlined,
                        size: 22,
                        color: _showHarvests
                            ? Colors.amber.shade800
                            : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  widget.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                ),
                onPressed: () async {
                  if (widget.isFullscreen) {
                    Navigator.of(context).pop();
                  } else {
                    await SystemChrome.setPreferredOrientations([
                      DeviceOrientation.landscapeRight,
                      DeviceOrientation.landscapeLeft,
                    ]);
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (context) => Scaffold(
                          appBar: AppBar(
                            toolbarHeight: 40,
                            title: const Text(
                              'Comb History',
                              style: TextStyle(fontSize: 16),
                            ),
                            leading: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                          body: SafeArea(
                            child: _CombHistoryChartWidget(
                              volkLogs: widget.volkLogs,
                              isFullscreen: true,
                              initialShowBrut: _showBrut,
                              initialShowHonig: _showHonig,
                              initialShowSuper: _showSuper,
                              initialShowHarvests: _showHarvests,
                            ),
                          ),
                        ),
                      ),
                    );
                    await SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                      DeviceOrientation.portraitDown,
                    ]);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double contentWidth = constraints.maxWidth;
                final double contentHeight = constraints.maxHeight - 60;

                List<Widget> monthMarkers = [];
                DateTime currentMonth = DateTime(minD.year, minD.month + 1, 1);
                double lastMarkerPosition = -100;

                final monthNames = [
                  'Jan',
                  'Feb',
                  'Mar',
                  'Apr',
                  'May',
                  'Jun',
                  'Jul',
                  'Aug',
                  'Sep',
                  'Oct',
                  'Nov',
                  'Dec',
                ];

                monthMarkers.add(
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Text(
                      '${monthNames[minD.month - 1]} ${minD.year}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
                lastMarkerPosition = 0;

                while (currentMonth.isBefore(maxD)) {
                  final leftOffset =
                      (currentMonth.difference(minD).inMilliseconds /
                          totalMilliseconds) *
                      contentWidth;

                  if (leftOffset - lastMarkerPosition >= 40) {
                    final monthName = monthNames[currentMonth.month - 1];

                    monthMarkers.add(
                      Positioned(
                        left: leftOffset,
                        top: 0,
                        bottom: 20,
                        child: Container(
                          width: 1,
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    );

                    monthMarkers.add(
                      Positioned(
                        left: leftOffset + 4,
                        top: 0,
                        child: Text(
                          '$monthName ${currentMonth.year}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    );
                    lastMarkerPosition = leftOffset;
                  }

                  currentMonth = DateTime(
                    currentMonth.year,
                    currentMonth.month + 1,
                    1,
                  );
                }

                List<Widget> yAxisMarkers = [];
                int step = (maxCombs > 20) ? 10 : ((maxCombs > 10) ? 5 : 2);
                if (step == 0) step = 1;
                for (int i = step; i <= maxCombs; i += step) {
                  final bottomOffset = 20 + (i / maxCombs) * contentHeight;

                  yAxisMarkers.add(
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: bottomOffset,
                      height: 1,
                      child: Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  );

                  yAxisMarkers.add(
                    Positioned(
                      left: 4,
                      bottom: bottomOffset + 2,
                      child: Text(
                        i.toString(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (details) {
                    _baseVisibleDays = _chartVisibleDays;
                    _baseEndDate = _chartEndDate;
                    _baseFocalPoint = details.localFocalPoint;
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      double newVisibleDays = (_baseVisibleDays / details.scale)
                          .clamp(7.0, 365.0 * 10);
                      double ratio = _baseFocalPoint.dx / contentWidth;
                      double dx =
                          details.localFocalPoint.dx - _baseFocalPoint.dx;
                      double daysPan = -(dx / contentWidth) * newVisibleDays;

                      double endDaysOffset =
                          daysPan +
                          (newVisibleDays - _baseVisibleDays) * (1 - ratio);

                      _chartVisibleDays = newVisibleDays;
                      _chartEndDate = _baseEndDate.add(
                        Duration(
                          milliseconds: (endDaysOffset * 24 * 3600 * 1000)
                              .round(),
                        ),
                      );

                      final now = DateTime.now();
                      if (_chartEndDate.isAfter(now)) {
                        _chartEndDate = now;
                      }
                    });
                  },
                  child: SizedBox(
                    width: contentWidth,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 20,
                          height: 1,
                          child: Container(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        ...yAxisMarkers,
                        ...monthMarkers,
                        Positioned(
                          left: 0,
                          bottom: 20,
                          right: 0,
                          height: contentHeight,
                          child: ClipRect(
                            child: CustomPaint(
                              painter: _CombChartPainter(
                                data: combData,
                                minD: minD,
                                maxD: maxD,
                                maxCombs: maxCombs,
                                showBrut: _showBrut,
                                showHonig: _showHonig,
                                showSuper: _showSuper,
                                brutColor: brutColor,
                                honigColor: honigColor,
                                superColor: superColor,
                              ),
                            ),
                          ),
                        ),
                        ...combData
                            .where((item) {
                              final d = item['date'] as DateTime;
                              return !d.isBefore(minD) && !d.isAfter(maxD);
                            })
                            .expand((item) {
                              if (item['isExtension'] == true) {
                                return <Widget>[];
                              }

                              final date = item['date'] as DateTime;
                              final leftOffset =
                                  (date.difference(minD).inMilliseconds /
                                      totalMilliseconds) *
                                  contentWidth;

                              List<Widget> dots = [];

                              void addDot(
                                String key,
                                Color color,
                                String label,
                              ) {
                                final val = item[key] as int?;
                                if (val == null) return;

                                final bottomOffset =
                                    20 + (val / maxCombs) * contentHeight;
                                final original =
                                    item['original'] as Map<String, dynamic>;

                                dots.add(
                                  Positioned(
                                    left: leftOffset,
                                    bottom: bottomOffset,
                                    child: FractionalTranslation(
                                      translation: const Offset(-0.5, 0.5),
                                      child: Tooltip(
                                        message:
                                            'Date: ${date.day}.${date.month}.${date.year}\n$label: $val\nAction: ${original['action'] ?? '-'}',
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: color,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.surface,
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.2,
                                                ),
                                                blurRadius: 2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              if (_showSuper)
                                addDot('super', superColor, 'Honey Super');
                              if (_showHonig)
                                addDot('honig', honigColor, 'Honey Box');
                              if (_showBrut)
                                addDot('brut', brutColor, 'Brood Box');

                              return dots;
                            }),
                        if (_showHarvests)
                          ...honeyHarvests
                              .where((t) {
                                final d = t['date'] as DateTime;
                                return !d.isBefore(minD) && !d.isAfter(maxD);
                              })
                              .map((t) {
                                final date = t['date'] as DateTime;
                                final original =
                                    t['original'] as Map<String, dynamic>;
                                final befund =
                                    original['befund']?.toString() ?? '';
                                final kommentar =
                                    original['kommentar']?.toString() ?? '';

                                final leftOffset =
                                    (date.difference(minD).inMilliseconds /
                                        totalMilliseconds) *
                                    contentWidth;

                                String tooltipMsg =
                                    'Honey Harvest\nDate: ${date.day}.${date.month}.${date.year}';
                                if (befund.isNotEmpty)
                                  tooltipMsg += '\nBefund: $befund';
                                if (kommentar.isNotEmpty)
                                  tooltipMsg += '\nNote: $kommentar';

                                return Positioned(
                                  left: leftOffset,
                                  top: 0,
                                  bottom: 20,
                                  child: FractionalTranslation(
                                    translation: const Offset(-0.5, 0.0),
                                    child: Tooltip(
                                      message: tooltipMsg,
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade50,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.amber.shade600,
                                                width: 2,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.1),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              Icons.hive,
                                              color: Colors.amber.shade800,
                                              size: 18,
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              width: 3,
                                              color: Colors.amber.shade500
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                        ...combData.map((item) {
                          final endDate = item['date'] as DateTime;
                          final dateLabel = '${endDate.day}.${endDate.month}.';
                          final rightOffset =
                              (maxD.difference(endDate).inMilliseconds /
                                  totalMilliseconds) *
                              contentWidth;
                          final rightEdge = contentWidth - rightOffset;

                          if (_chartVisibleDays > 120) {
                            return const SizedBox.shrink();
                          }

                          if (endDate.isBefore(minD) || endDate.isAfter(maxD)) {
                            return const SizedBox.shrink();
                          }

                          return Positioned(
                            left: rightEdge - 20,
                            bottom: 0,
                            width: 40,
                            child: Text(
                              dateLabel,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 9,
                                  ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
  List<dynamic>? _varroaStats;

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

  Future<void> _loadVarroaStats() async {
    if (_volkLogs == null || _volkLogs!.isEmpty) return;

    final logsJson = jsonEncode(_volkLogs);
    final statsJsonString = await AppApi.parseVarroaStatistics(logsJson);

    if (mounted) {
      setState(() {
        try {
          _varroaStats = jsonDecode(statsJsonString);
        } catch (e) {
          debugPrint('Error parsing varroa stats: $e');
        }
      });
    }
  }

  Future<void> _loadVolkDetails() async {
    final int hiveId = int.tryParse(widget.hiveId) ?? 0;
    final jsonString = await AppApi.getHiveDetailsJson(hiveId);

    Map<String, dynamic>? tempVolkDetails;
    List<dynamic>? tempVolkLogs;
    int tempPermission = 0;
    String tempHiveName = '';

    try {
      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is Map<String, dynamic> &&
          decoded['status'] == 'UNAUTHORIZED') {
        if (mounted) {
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
        }
        return;
      }

      if (decoded is Map<String, dynamic> &&
          decoded.containsKey('status') &&
          decoded['status'] != 'SUCCESS') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                decoded['message']?.toString() ?? 'Error loading volk details.',
              ),
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      Map<String, dynamic>? hiveData;

      if (decoded is Map<String, dynamic>) {
        hiveData = decoded;
      } else if (decoded is List && decoded.isNotEmpty) {
        hiveData = decoded.first as Map<String, dynamic>;
      }

      if (hiveData != null) {
        if (hiveData.containsKey('hive') && hiveData['hive'] is Map) {
          tempPermission =
              int.tryParse(hiveData['hive']['permission']?.toString() ?? '') ??
              0;
          tempHiveName = hiveData['hive']['name']?.toString() ?? '';
        } else {
          tempPermission =
              int.tryParse(hiveData['permission']?.toString() ?? '') ?? 0;
          tempHiveName = hiveData['name']?.toString() ?? '';
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
            tempVolkDetails = v;
            break;
          }
        }

        List<dynamic> allLogs = [];
        if (hiveData.containsKey('hive') &&
            hiveData['hive'].containsKey('logs')) {
          allLogs = hiveData['hive']['logs'];
        } else if (hiveData.containsKey('logs')) {
          allLogs = hiveData['logs'];
        }

        tempVolkLogs = allLogs
            .where((i) => i['id'].toString() == widget.volkId.toString())
            .toList();
      }
    } catch (e) {
      debugPrint('Error parsing volk details: $e');
    }

    if (tempVolkLogs != null && tempVolkLogs.isNotEmpty) {
      final bCount = _extractNumber(
        tempVolkDetails?['brutwaben']?.toString() ?? '0',
      );
      final hCount = _extractNumber(
        tempVolkDetails?['honigwaben']?.toString() ?? '0',
      );

      final logsJson = jsonEncode(tempVolkLogs);
      final historyJsonString = await AppApi.calculateCombHistory(
        logsJson,
        bCount,
        hCount,
      );
      try {
        tempVolkLogs = jsonDecode(historyJsonString);
      } catch (e) {
        debugPrint('Error parsing comb history: $e');
      }
    }

    if (mounted) {
      setState(() {
        _permission = tempPermission;
        _hiveName = tempHiveName;
        _volkDetails = tempVolkDetails;
        _volkLogs = tempVolkLogs;
        _isLoading = false;
      });
      _loadVarroaStats();
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

  void _showActionMenu() {
    final bool isSchwarm =
        _volkDetails?['konigin']?.toString().toLowerCase() == 'schwarm';

    bool canRemoveFutter = true;
    if (_volkLogs != null) {
      final futterEntfernenLogs = _volkLogs!
          .where(
            (log) =>
                log['action']?.toString().toLowerCase() == 'futter entfernen',
          )
          .toList();
      if (futterEntfernenLogs.isNotEmpty) {
        futterEntfernenLogs.sort((a, b) {
          final dateA =
              DateTime.tryParse(a['datum'].toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final dateB =
              DateTime.tryParse(b['datum'].toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return dateB.compareTo(dateA); // Descending
        });
        final lastLog = futterEntfernenLogs.first;
        if (lastLog['befund']?.toString() == 'Futter entfernt') {
          canRemoveFutter = false;
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        if (isSchwarm) {
          return SafeArea(
            child: Wrap(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Aktionen',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.home_work_outlined),
                  title: const Text('Schwarm einlogieren'),
                  onTap: () async {
                    Navigator.pop(context);
                    await showActionPopup(
                      context,
                      'schwarmE',
                      _volkDetails,
                      int.tryParse(widget.hiveId) ?? 0,
                      int.tryParse(widget.volkId) ?? 0,
                    );
                    _loadVolkDetails();
                  },
                ),
              ],
            ),
          );
        }

        final Map<String, List<Map<String, dynamic>>> categories = {
          'Gesundheit & Fütterung': [
            {'title': 'Füttern', 'icon': Icons.restaurant, 'action': 'futter'},
            if (canRemoveFutter)
              {
                'title': 'Futter entfernen',
                'icon': Icons.cleaning_services_outlined,
                'action': 'futterE',
              },
            {
              'title': 'Varroa behandeln',
              'icon': Icons.medication_outlined,
              'action': 'varroaTn',
            },
            {
              'title': 'Varroa Behandlung entfernen',
              'icon': Icons.healing_outlined,
              'action': 'varroaTent',
            },
            {
              'title': 'Varroa zählen',
              'icon': Icons.pest_control,
              'action': 'varroaC',
            },
          ],
          'Kontrolle & Waben': [
            {
              'title': 'Volk kontrollieren',
              'icon': Icons.fact_check_outlined,
              'action': 'kontrolle',
            },
            {
              'title': 'Ausbauen',
              'icon': Icons.build_outlined,
              'action': 'ausbauen',
            },
            {
              'title': 'Reduktion',
              'icon': Icons.remove_circle_outline,
              'action': 'reduktion',
            },
            {'title': 'Honig ernten', 'icon': Icons.hive, 'action': 'ernte'},
          ],
          'Königin & Volk': [
            {
              'title': 'Neue Königin hinzufügen',
              'icon': Icons.star_outline,
              'action': 'neueK',
            },
            {
              'title': 'Königin markieren',
              'icon': Icons.brush_outlined,
              'action': 'koniginm',
            },
            {
              'title': 'Volk vereinigen',
              'icon': Icons.group_add_outlined,
              'action': 'volkV',
            },
            {
              'title': 'Volk auflösen',
              'icon': Icons.group_remove_outlined,
              'action': 'volkA',
            },
            {
              'title': 'Volk umziehen',
              'icon': Icons.local_shipping_outlined,
              'action': 'volkU',
            },
          ],
          'Sonstiges': [
            {
              'title': 'Herkunft/ Kommentar bearbeiten',
              'icon': Icons.edit_note,
              'action': 'det',
            },
            {'title': 'Freitext', 'icon': Icons.notes, 'action': 'freitext'},
          ],
        };

        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            builder: (context, scrollController) {
              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Text(
                      'Aktionen',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        String categoryName = categories.keys.elementAt(index);
                        List<Map<String, dynamic>> actions =
                            categories[categoryName]!;

                        IconData categoryIcon;
                        switch (categoryName) {
                          case 'Gesundheit & Fütterung':
                            categoryIcon = Icons.medical_services_outlined;
                            break;
                          case 'Kontrolle & Waben':
                            categoryIcon = Icons.grid_view_outlined;
                            break;
                          case 'Königin & Volk':
                            categoryIcon = Icons.groups_outlined;
                            break;
                          case 'Sonstiges':
                          default:
                            categoryIcon = Icons.more_horiz_outlined;
                            break;
                        }

                        return ExpansionTile(
                          leading: Icon(
                            categoryIcon,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(
                            categoryName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          children: actions.map((actionItem) {
                            return ListTile(
                              contentPadding: const EdgeInsets.only(
                                left: 56,
                                right: 16,
                              ),
                              leading: Icon(
                                actionItem['icon'] as IconData,
                                size: 20,
                              ),
                              title: Text(actionItem['title'] as String),
                              onTap: () async {
                                Navigator.pop(context);
                                await showActionPopup(
                                  context,
                                  actionItem['action'] as String,
                                  _volkDetails,
                                  int.tryParse(widget.hiveId) ?? 0,
                                  int.tryParse(widget.volkId) ?? 0,
                                );
                                _loadVolkDetails();
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
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
      String rawText, {
      int primaryCount = 0,
      Color? primaryColor,
      int secondaryCount = 0,
      Color? secondaryColor,
      bool isSuper = false,
      bool isBrood = false,
    }) {
      final double boxHeight = isSuper ? 50.0 : (isBrood ? 80.0 : 70.0);
      final int totalCombs = primaryCount + secondaryCount;

      List<Widget> combWidgets = [];
      for (int i = 0; i < primaryCount; i++) {
        if (combWidgets.length >= 20) break;
        combWidgets.add(
          Container(
            width: 8,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: primaryColor ?? Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),
        );
      }
      for (int i = 0; i < secondaryCount; i++) {
        if (combWidgets.length >= 20) break;
        combWidgets.add(
          Container(
            width: 8,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: secondaryColor ?? Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),
        );
      }

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
            if (totalCombs > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: combWidgets,
                  ),
                ),
              ),
            if (totalCombs == 0)
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
    hiveStack.add(
      buildBox(
        'Honey Box',
        superStr == 'N/A' || superStr.isEmpty ? '0' : superStr,
        primaryCount: sCount,
        primaryColor: Theme.of(context).colorScheme.primary,
        isSuper: true,
      ),
    );

    // Brood Box (Contains both Brood and Honey combs)
    hiveStack.add(
      buildBox(
        'Brood Box',
        'B: $brutStr | H: $honigStr',
        primaryCount: bCount,
        primaryColor: Theme.of(
          context,
        ).colorScheme.tertiary.withValues(alpha: 0.7),
        secondaryCount: hCount,
        secondaryColor: Theme.of(context).colorScheme.primary,
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
      return _ThemeRefreshIndicator(
        onRefresh: _loadVolkDetails,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Text(
                  'Could not load details for Volk ${widget.volkId}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final volk = _volkDetails!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth > 800
            ? 800
            : constraints.maxWidth;
        final double spacing = 16.0;
        final double fullWidth = availableWidth - (spacing * 2);

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

        return _ThemeRefreshIndicator(
          onRefresh: _loadVolkDetails,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
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
                      onTap: () =>
                          _copyToClipboard('Queen Year', valKoniginJahr),
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
              ),
            ),
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
      content = _ThemeRefreshIndicator(
        onRefresh: _loadVolkDetails,
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
                    onRefresh: _loadVolkDetails,
                    child: ListView.builder(
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

  Widget _buildStatisticsTab() {
    return _ThemeRefreshIndicator(
      onRefresh: _loadVolkDetails,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            children: [
              _VarroaChartWidget(
                varroaData: _varroaStats ?? [],
                volkLogs: _volkLogs ?? [],
              ),
              const SizedBox(height: 16),
              _CombHistoryChartWidget(volkLogs: _volkLogs ?? []),
            ],
          ),
        ),
      ),
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
        length: 3,
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
                  await AppApi.logout();
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
                    _buildLogTab(),
                    _buildStatisticsTab(),
                  ],
                ),
          floatingActionButton: (!_isLoading && _permission >= 1)
              ? SizedBox(
                  width: 72.0,
                  height: 72.0,
                  child: FloatingActionButton(
                    onPressed: _showActionMenu,
                    child: const Icon(Icons.edit_note, size: 36.0),
                  ),
                )
              : null,
          bottomNavigationBar: Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: SafeArea(
              child: Center(
                heightFactor: 1.0,
                child: SizedBox(
                  width: 800,
                  child: const TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelPadding: EdgeInsets.symmetric(vertical: 4.0),
                    tabs: [
                      Tab(text: 'Info', icon: Icon(Icons.info_outline)),
                      Tab(text: 'Log', icon: Icon(Icons.receipt_long)),
                      Tab(text: 'Statistics', icon: Icon(Icons.bar_chart)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
