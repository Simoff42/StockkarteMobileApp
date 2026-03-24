import 'package:flutter/material.dart';
import 'dart:convert';
import '../core/api/api.dart';

Future<void> showActionPopup(
  BuildContext context,
  String actionKey,
  Map<String, dynamic>? volkDetails,
  int hiveId,
  int volkId,
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 600),
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ActionFormWidget(
          actionKey: actionKey,
          volkDetails: volkDetails,
          hiveId: hiveId,
          volkId: volkId,
        ),
      );
    },
  );
}

class ActionFormWidget extends StatefulWidget {
  final String actionKey;
  final Map<String, dynamic>? volkDetails;
  final int hiveId;
  final int volkId;

  const ActionFormWidget({
    super.key,
    required this.actionKey,
    this.volkDetails,
    required this.hiveId,
    required this.volkId,
  });

  @override
  State<ActionFormWidget> createState() => _ActionFormWidgetState();
}

class _ActionFormWidgetState extends State<ActionFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _formData = {};
  final Map<String, TextEditingController> _textControllers = {};

  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();

    _formData['wetter'] = null;
    _formData['temperatur'] = '';
    _formData['kommentar'] = widget.volkDetails?['kommentar']?.toString() ?? '';

    if (widget.actionKey == 'schwarmE' ||
        widget.actionKey == 'reduktion' ||
        widget.actionKey == 'ausbauen' ||
        widget.actionKey == 'volkV') {
      _formData['brutwaben'] =
          widget.volkDetails?['brutwaben']?.toString() ?? '0';
      _formData['honigwaben'] =
          widget.volkDetails?['honigwaben']?.toString() ??
          '0'; // Brutwaben klein
      _formData['honigraum'] =
          widget.volkDetails?['honigraum']?.toString() ?? '0';
    }

    if (widget.actionKey == 'det') {
      _formData['herkunft'] = widget.volkDetails?['herkunft']?.toString() ?? '';
    }

    if (widget.actionKey == 'varroaTent') {
      _formData['befund'] = 'Varroabehandlung beendet';
    }
  }

  @override
  void dispose() {
    for (var controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String getTitle() {
    switch (widget.actionKey) {
      case 'futter':
        return 'Füttern';
      case 'schwarmE':
        return 'Schwarm einlogieren';
      case 'futterE':
        return 'Futter entfernen';
      case 'varroaTn':
        return 'Varroa behandeln';
      case 'varroaC':
        return 'Varroa zählen';
      case 'ausbauen':
        return 'Ausbauen';
      case 'reduktion':
        return 'Reduktion';
      case 'kontrolle':
        return 'Volk kontrollieren';
      case 'ernte':
        return 'Honig ernten';
      case 'neueK':
        return 'Neue Königin';
      case 'volkV':
        return 'Volk vereinigen';
      case 'volkA':
        return 'Volk auflösen';
      case 'volkU':
        return 'Volk umziehen';
      case 'det':
        return 'Herkunft & Kommentar bearbeiten';
      case 'freitext':
        return 'Freitext';
      case 'koniginm':
        return 'Königin markieren';
      case 'varroaTent':
        return 'Varroabehandlung beenden';
      default:
        return 'Aktion';
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: () => _selectDate(context),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Datum',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_selectedDate.day.toString().padLeft(2, '0')}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.year}',
            ),
            const Icon(Icons.calendar_today, size: 20),
          ],
        ),
      ),
    );
  }

  TextEditingController _getController(String key) {
    if (!_textControllers.containsKey(key)) {
      _textControllers[key] = TextEditingController(
        text: _formData[key]?.toString() ?? '',
      );
      _textControllers[key]!.addListener(() {
        _formData[key] = _textControllers[key]!.text;
      });
    }
    return _textControllers[key]!;
  }

  Widget _buildTextField(
    String label,
    String key, {
    bool isNumber = false,
    int maxLines = 1,
    bool required = false,
  }) {
    return TextFormField(
      controller: _getController(key),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.multiline,
      maxLines: maxLines,
      validator: required
          ? (val) {
              if (val == null || val.trim().isEmpty) return 'Pflichtfeld';
              return null;
            }
          : null,
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String key, {
    bool required = false,
  }) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      value: _formData[key] is String && items.contains(_formData[key])
          ? _formData[key]
          : null,
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: (val) => setState(() => _formData[key] = val),
      validator: required
          ? (val) => val == null || val.isEmpty ? 'Pflichtfeld' : null
          : null,
    );
  }

  List<Widget> _buildFormFields() {
    List<Widget> fields = [];
    bool showWeatherTemp = widget.actionKey != 'det';
    bool showDate = widget.actionKey != 'det';

    if (showDate) {
      fields.add(_buildDatePicker());
      fields.add(const SizedBox(height: 16));
    }

    if (showWeatherTemp) {
      fields.add(
        _buildDropdown(
          'Wetter',
          ['sonnig', 'bewölkt', 'leicht bewölkt', 'regen'],
          'wetter',
          required: true,
        ),
      );
      fields.add(const SizedBox(height: 16));
      fields.add(
        _buildTextField(
          'Temperatur (°C)',
          'temperatur',
          isNumber: true,
          required: true,
        ),
      );
      fields.add(const SizedBox(height: 16));
    }

    switch (widget.actionKey) {
      case 'futter':
        fields.add(
          _buildDropdown(
            'Typ',
            ['Futterteig', 'Zuckerwasser', 'alte Waben'],
            'typ',
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField('Menge', 'menge', isNumber: true, required: true),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(_buildDropdown('Einheit', ['ml', 'g', 'kg'], 'einheit'));
        fields.add(const SizedBox(height: 16));
        break;
      case 'schwarmE':
        fields.add(
          _buildDropdown(
            'Königin',
            ['unmarkiert', 'rot', 'gelb', 'grün', 'blau', 'weiss', 'kk'],
            'koenigin',
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField(
            'Kastennummer',
            'nummer',
            isNumber: true,
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField(
            'Brutwaben',
            'brutwaben',
            isNumber: true,
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField(
            'Brutwaben klein',
            'honigwaben',
            isNumber: true,
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField(
            'Honigraum',
            'honigraum',
            isNumber: true,
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(_buildTextField('Herkunft', 'herkunft'));
        fields.add(const SizedBox(height: 16));
        break;
      case 'futterE':
      case 'ernte':
        break;
      case 'varroaTn':
        fields.add(
          _buildDropdown(
            'Behandlung',
            ['Sommer', 'Winter', 'Not', 'Schwarm'],
            'behandlung',
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildDropdown(
            'Typ',
            [
              'verdampfen',
              'träuffeln',
              'sprühen',
              'Bannwabe',
              'FAM Dispenser',
              'andere',
            ],
            'typ',
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField('Tierarzneimittel', 'mittel', required: true),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(_buildTextField('Dosierung', 'dosierung', isNumber: true));
        fields.add(const SizedBox(height: 16));
        break;
      case 'varroaC':
        fields.add(
          _buildTextField('Anzahl', 'anzahl', isNumber: true, required: true),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(_buildTextField('In Tagen', 'tage', isNumber: true));
        fields.add(const SizedBox(height: 16));
        break;
      case 'ausbauen':
      case 'reduktion':
        fields.add(
          _buildTextField(
            'Brutwaben',
            'brutwaben',
            isNumber: true,
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField(
            'Brutwaben klein',
            'honigwaben',
            isNumber: true,
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField(
            'Honigraum',
            'honigraum',
            isNumber: true,
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        break;
      case 'kontrolle':
        fields.add(
          _buildDropdown(
            'Königin',
            [
              'keine Königin gesichtet',
              'blaue Königin',
              'rote Königin',
              'grüne Königin',
              'weisse Königin',
              'gelbe Königin',
              'unmarkierte Königin',
              'keine Königin',
            ],
            'koenigin',
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField('Brut (z.B. frische Brut, verdeckelte Brut)', 'brut'),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildDropdown(
            'Futter',
            ['Ok', 'nicht Ok'],
            'futter',
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        break;
      case 'neueK':
      case 'koniginm':
        fields.add(
          _buildDropdown('Farbe', [
            'blau',
            'rot',
            'grün',
            'weiss',
            'gelb',
            'unmarkiert',
          ], 'koenigin'),
        );
        fields.add(const SizedBox(height: 16));
        break;
      case 'volkV':
        fields.add(
          _buildTextField(
            'Vereinigen mit (Volk Nr)',
            'vereinigen_mit',
            isNumber: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField(
            'Brutwaben',
            'brutwaben',
            isNumber: true,
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField(
            'Brutwaben klein',
            'honigwaben',
            isNumber: true,
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildTextField(
            'Honigraum',
            'honigraum',
            isNumber: true,
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        fields.add(
          _buildDropdown('Königin', [
            'keine Königin gesichtet',
            'blaue Königin',
            'rote Königin',
            'grüne Königin',
            'weisse Königin',
            'gelbe Königin',
            'unmarkierte Königin',
            'keine Königin',
          ], 'koenigin'),
        );
        fields.add(const SizedBox(height: 16));
        break;
      case 'volkA':
        fields.add(_buildTextField('Grund', 'grund', required: true));
        fields.add(const SizedBox(height: 16));
        break;
      case 'volkU':
        fields.add(
          _buildTextField(
            'Neuer Kasten',
            'kasten',
            isNumber: true,
            required: true,
          ),
        );
        fields.add(const SizedBox(height: 16));
        break;
      case 'det':
        fields.add(_buildTextField('Herkunft', 'herkunft', required: true));
        fields.add(const SizedBox(height: 16));
        break;
      case 'freitext':
      case 'varroaTent':
        fields.add(_buildTextField('Befund', 'befund', required: true));
        fields.add(const SizedBox(height: 16));
        break;
    }

    fields.add(_buildTextField('Kommentar', 'kommentar', maxLines: 3));

    return fields;
  }

  void _saveForm() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      _formData['datum'] = _selectedDate.toIso8601String();

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final jsonStr = jsonEncode(_formData);
      final result = await AppApi.submitAction(
        widget.hiveId,
        widget.volkId,
        widget.actionKey,
        jsonStr,
      );

      if (mounted) {
        Navigator.pop(context); // Close the loading spinner
        if (result == "SUCCESS") {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${getTitle()} gespeichert')));
          Navigator.pop(context); // Close the bottom sheet
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler beim Speichern: $result')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  getTitle(),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                    children: _buildFormFields(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _saveForm,
                    child: const Text(
                      'Speichern',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
