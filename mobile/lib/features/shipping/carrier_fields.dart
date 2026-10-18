import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const shippingCarriers = <String>[
  'UPS',
  'USPS',
  'FedEx',
  'DHL',
  'Postal',
  'DoorDash',
  'Uber',
  'Other',
];

int trackingLimitForCarrier(String carrier) {
  switch (carrier.trim().toLowerCase()) {
    case 'ups':
    case 'usps':
    case 'fedex':
      return 34;
    case 'dhl':
      return 39;
    default:
      return 64;
  }
}

String? trackingError(String value, String carrier) {
  final limit = trackingLimitForCarrier(carrier);
  if (value.trim().length > limit) {
    return 'Tracking number exceeds $limit characters for ${carrier.trim().isEmpty ? 'Other' : carrier.trim()}.';
  }
  return null;
}

class CarrierField extends StatefulWidget {
  const CarrierField({super.key, required this.controller, this.onChanged});

  final TextEditingController controller;
  final VoidCallback? onChanged;

  @override
  State<CarrierField> createState() => _CarrierFieldState();
}

class _CarrierFieldState extends State<CarrierField> {
  late final TextEditingController _customController;
  late String _selectedCarrier;
  bool _writingCustomValue = false;
  bool _settingSelection = false;
  bool _syncingCustomController = false;

  String? get _matchingPreset {
    final carrier = widget.controller.text.trim().toLowerCase();
    for (final preset in shippingCarriers.where((item) => item != 'Other')) {
      if (preset.toLowerCase() == carrier) return preset;
    }
    return null;
  }

  String get _carrierSelection => _matchingPreset ?? 'Other';

  @override
  void initState() {
    super.initState();
    _selectedCarrier = _carrierSelection;
    widget.controller.addListener(_handleExternalCarrierChange);
    _customController = TextEditingController(
      text: _selectedCarrier == 'Other' ? widget.controller.text : '',
    )..addListener(_copyCustomValue);
  }

  @override
  void didUpdateWidget(covariant CarrierField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleExternalCarrierChange);
      widget.controller.addListener(_handleExternalCarrierChange);
      _selectedCarrier = _carrierSelection;
      _syncCustomController();
    }
  }

  void _handleExternalCarrierChange() {
    if (_writingCustomValue || _settingSelection) return;
    final selection = _carrierSelection;
    final customValue = selection == 'Other' ? widget.controller.text : '';
    final shouldSync =
        _selectedCarrier != selection ||
        (selection == 'Other' && _customController.text != customValue);
    if (!shouldSync) return;
    _selectedCarrier = selection;
    _syncCustomController();
    if (mounted) setState(() {});
  }

  void _syncCustomController() {
    final customValue = _selectedCarrier == 'Other'
        ? widget.controller.text
        : '';
    if (_customController.text != customValue) {
      _syncingCustomController = true;
      _customController.value = TextEditingValue(
        text: customValue,
        selection: TextSelection.collapsed(offset: customValue.length),
      );
      _syncingCustomController = false;
    }
  }

  void _copyCustomValue() {
    if (_syncingCustomController ||
        _selectedCarrier != 'Other' ||
        widget.controller.text == _customController.text) {
      return;
    }
    _writingCustomValue = true;
    widget.controller.value = TextEditingValue(
      text: _customController.text,
      selection: _customController.selection,
      composing: _customController.value.composing,
    );
    _writingCustomValue = false;
    widget.onChanged?.call();
  }

  void _selectCarrier(String? selection) {
    if (selection == null) return;
    if (selection == 'Other') {
      final previousSelection = _selectedCarrier;
      setState(() {
        _selectedCarrier = 'Other';
        if (previousSelection != 'Other') {
          _settingSelection = true;
          widget.controller.clear();
          _settingSelection = false;
          _customController.clear();
        } else {
          _syncCustomController();
        }
      });
      widget.onChanged?.call();
      return;
    }

    _settingSelection = true;
    widget.controller.value = TextEditingValue(
      text: selection,
      selection: TextSelection.collapsed(offset: selection.length),
    );
    _settingSelection = false;
    _selectedCarrier = selection;
    _customController.clear();
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleExternalCarrierChange);
    _customController
      ..removeListener(_copyCustomValue)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('shipping-carrier-dropdown-$_selectedCarrier'),
          initialValue: _selectedCarrier,
          decoration: const InputDecoration(labelText: 'Carrier'),
          items: shippingCarriers
              .map(
                (carrier) => DropdownMenuItem<String>(
                  value: carrier,
                  child: Text(carrier),
                ),
              )
              .toList(),
          onChanged: _selectCarrier,
        ),
        if (_selectedCarrier == 'Other') ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('shipping-custom-carrier'),
            controller: _customController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Custom carrier'),
          ),
        ],
      ],
    );
  }
}

class TrackingField extends StatelessWidget {
  const TrackingField({
    super.key,
    required this.controller,
    required this.carrier,
    this.onChanged,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String carrier;
  final VoidCallback? onChanged;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    final limit = trackingLimitForCarrier(carrier);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final validation = trackingError(value.text, carrier);
        return TextField(
          controller: controller,
          onChanged: (_) => onChanged?.call(),
          keyboardType: TextInputType.text,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [_CarrierAwareLengthFormatter(limit)],
          decoration: InputDecoration(
            labelText: 'Tracking # (optional)',
            suffixIcon: suffixIcon,
            helperText: validation ?? 'Up to $limit characters',
            helperMaxLines: 2,
            errorText: validation,
            errorMaxLines: 3,
            counterText: '${value.text.length}/$limit',
          ),
        );
      },
    );
  }
}

class _CarrierAwareLengthFormatter extends TextInputFormatter {
  const _CarrierAwareLengthFormatter(this.limit);
  final int limit;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= limit) {
      return newValue;
    }

    if (oldValue.text.length > limit &&
        newValue.text.length < oldValue.text.length) {
      return newValue;
    }

    // Reject the entire edit instead of truncating a pasted identifier. The
    // explicit paste button writes through the controller and remains intact;
    // trackingError then shows the over-limit value for review.
    return oldValue;
  }
}
