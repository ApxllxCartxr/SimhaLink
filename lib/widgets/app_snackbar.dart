import 'package:flutter/material.dart';

/// Utility class for showing consistent snackbars across the app
class AppSnackbar {
  /// Show success message
  static void showSuccess(BuildContext context, String message) {
    _showSnackbar(
      context,
      message,
      backgroundColor: Colors.green,
      icon: Icons.check_circle,
    );
  }

  /// Show error message
  static void showError(BuildContext context, String message) {
    _showSnackbar(
      context,
      message,
      backgroundColor: Colors.red,
      icon: Icons.error,
    );
  }

  /// Show warning message
  static void showWarning(BuildContext context, String message) {
    _showSnackbar(
      context,
      message,
      backgroundColor: Colors.orange,
      icon: Icons.warning,
    );
  }

  /// Show info message
  static void showInfo(BuildContext context, String message) {
    _showSnackbar(
      context,
      message,
      backgroundColor: Colors.blue,
      icon: Icons.info,
    );
  }

  static void _showSnackbar(
    BuildContext context,
    String message, {
    required Color backgroundColor,
    required IconData icon,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
