import 'package:flutter/material.dart';

class ErrorHandler {
  static void showError(BuildContext context, String message, {String? title, VoidCallback? onRetry}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 4),
        action: onRetry != null
            ? SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green[600],
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  static void showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue[600],
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  static void showErrorDialog(
    BuildContext context,
    String title,
    String message, {
    String? primaryButtonText,
    String? secondaryButtonText,
    VoidCallback? onPrimaryPressed,
    VoidCallback? onSecondaryPressed,
  }) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            if (secondaryButtonText != null)
              TextButton(
                onPressed: onSecondaryPressed ?? () => Navigator.of(dialogContext).pop(),
                child: Text(secondaryButtonText),
              ),
            TextButton(
              onPressed: onPrimaryPressed ?? () => Navigator.of(dialogContext).pop(),
              child: Text(primaryButtonText ?? 'OK'),
            ),
          ],
        );
      },
    );
  }

  /// Handles common Firebase errors and returns user-friendly messages
  static String getFirebaseErrorMessage(dynamic error) {
    final String errorMessage = error.toString().toLowerCase();
    
    if (errorMessage.contains('network')) {
      return 'Network error. Please check your connection and try again.';
    } else if (errorMessage.contains('permission-denied')) {
      return 'You don\'t have permission to perform this action.';
    } else if (errorMessage.contains('not-found')) {
      return 'The requested data was not found.';
    } else if (errorMessage.contains('already-exists')) {
      return 'This item already exists.';
    } else if (errorMessage.contains('invalid-argument')) {
      return 'Invalid data provided. Please check your input.';
    } else if (errorMessage.contains('unauthenticated')) {
      return 'Please log in to continue.';
    } else if (errorMessage.contains('quota-exceeded')) {
      return 'Service temporarily unavailable. Please try again later.';
    } else {
      return 'An unexpected error occurred. Please try again.';
    }
  }
}
