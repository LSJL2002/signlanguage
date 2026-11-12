import 'package:flutter/material.dart';

/// Mode control; the parent owns translation routing.
class TranslationModePill extends StatelessWidget {
  const TranslationModePill({
    super.key,
    required this.isOnlineMode,
    this.onChanged,
  });

  final bool isOnlineMode;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: isOnlineMode,
    label: 'Translation mode',
    child: Material(
      color: isOnlineMode ? const Color(0xFF30835B) : const Color(0xFF636B70),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onChanged == null ? null : () => onChanged!(!isOnlineMode),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              isOnlineMode ? 'Online' : 'Offline',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
