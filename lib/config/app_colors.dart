import 'package:flutter/material.dart';

/// App color palette with proper contrast ratios for accessibility
class AppColors {
  AppColors._(); // Private constructor

  // Primary Colors
  static const Color primary = Color(0xFF1A1A1A); // Near black
  static const Color primaryLight = Color(0xFF4A4A4A); // Medium gray
  static const Color primaryDark = Color(0xFF000000); // True black
  
  // Secondary Colors
  static const Color secondary = Color(0xFF2196F3); // Blue
  static const Color secondaryLight = Color(0xFF64B5F6); // Light blue
  static const Color secondaryDark = Color(0xFF1976D2); // Dark blue
  
  // Background Colors
  static const Color background = Color(0xFFFFFFFF); // White
  static const Color backgroundLight = Color(0xFFF8F9FA); // Very light gray
  static const Color backgroundDark = Color(0xFF121212); // Dark mode background
  static const Color surface = Color(0xFFFFFFFF); // White
  static const Color surfaceDark = Color(0xFF1E1E1E); // Dark surface
  
  // Text Colors
  static const Color textPrimary = Color(0xFF212121); // Near black
  static const Color textSecondary = Color(0xFF757575); // Medium gray
  static const Color textHint = Color(0xFFBDBDBD); // Light gray
  static const Color textOnDark = Color(0xFFFFFFFF); // White on dark
  static const Color textOnPrimary = Color(0xFFFFFFFF); // White on primary
  
  // Status Colors
  static const Color success = Color(0xFF4CAF50); // Green
  static const Color successLight = Color(0xFF81C784); // Light green
  static const Color warning = Color(0xFFFF9800); // Orange
  static const Color warningLight = Color(0xFFFFB74D); // Light orange
  static const Color error = Color(0xFFF44336); // Red
  static const Color errorLight = Color(0xFFEF5350); // Light red
  static const Color info = Color(0xFF2196F3); // Blue
  
  // UI Element Colors
  static const Color divider = Color(0xFFE0E0E0); // Light gray divider
  static const Color border = Color(0xFFE0E0E0); // Border color
  static const Color shadow = Color(0x1A000000); // Semi-transparent black
  static const Color overlay = Color(0x80000000); // Semi-transparent overlay
  
  // Chat Colors
  static const Color chatBubbleUser = Color(0xFF2196F3); // Blue for user messages
  static const Color chatBubbleOther = Color(0xFFF5F5F5); // Light gray for others
  static const Color chatTextUser = Color(0xFFFFFFFF); // White text on user bubble
  static const Color chatTextOther = Color(0xFF212121); // Dark text on other bubble
  
  // Map Colors
  static const Color mapUserLocation = Color(0xFF2196F3); // Blue for user
  static const Color mapGroupMembers = Color(0xFF4CAF50); // Green for group
  static const Color mapEmergency = Color(0xFFF44336); // Red for emergency
  static const Color mapPOI = Color(0xFFFF9800); // Orange for POI
  static const Color mapLegendBackground = Color(0xFFFAFAFA); // Very light background
  
  // Role-specific map marker colors
  static const Color mapAttendee = Color(0xFF4CAF50); // Green for attendees
  static const Color mapVolunteer = Color(0xFF2196F3); // Blue for volunteers
  static const Color mapOrganizer = Color(0xFF9C27B0); // Purple for organizers
  static const Color mapCurrentUser = Color(0xFF1976D2); // Dark blue for current user (Google Maps style)
  
  // Role Colors
  static const Color roleVolunteer = Color(0xFF4CAF50); // Green
  static const Color roleOrganizer = Color(0xFF9C27B0); // Purple
  static const Color roleVIP = Color(0xFFFFD700); // Gold
  static const Color roleParticipant = Color(0xFF607D8B); // Blue gray
  
  // Utility methods for getting theme-appropriate colors
  static Color getTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? textOnDark
        : textPrimary;
  }
  
  static Color getBackgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? backgroundDark
        : background;
  }
  
  static Color getSurfaceColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? surfaceDark
        : surface;
  }
  
  // Accessibility helpers
  static bool hasGoodContrast(Color foreground, Color background) {
    final fgLuminance = foreground.computeLuminance();
    final bgLuminance = background.computeLuminance();
    final contrast = (fgLuminance > bgLuminance)
        ? (fgLuminance + 0.05) / (bgLuminance + 0.05)
        : (bgLuminance + 0.05) / (fgLuminance + 0.05);
    return contrast >= 4.5; // WCAG AA standard
  }
}
