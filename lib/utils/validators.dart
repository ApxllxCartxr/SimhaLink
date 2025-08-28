class Validators {
  /// Validates group name
  static String? validateGroupName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Group name is required';
    }
    
    final trimmedValue = value.trim();
    
    if (trimmedValue.length < 3) {
      return 'Group name must be at least 3 characters';
    }
    
    if (trimmedValue.length > 50) {
      return 'Group name must be less than 50 characters';
    }
    
    // Check for invalid characters
    if (!RegExp(r'^[a-zA-Z0-9\s\-_]+$').hasMatch(trimmedValue)) {
      return 'Group name can only contain letters, numbers, spaces, hyphens, and underscores';
    }
    
    return null;
  }

  /// Validates join code
  static String? validateJoinCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Join code is required';
    }
    
    final trimmedValue = value.trim().toUpperCase();
    
    if (trimmedValue.length != 6) {
      return 'Join code must be exactly 6 characters';
    }
    
    // Check if it contains only alphanumeric characters
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(trimmedValue)) {
      return 'Join code can only contain letters and numbers';
    }
    
    return null;
  }

  /// Validates POI name
  static String? validatePOIName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'POI name is required';
    }
    
    final trimmedValue = value.trim();
    
    if (trimmedValue.length < 2) {
      return 'POI name must be at least 2 characters';
    }
    
    if (trimmedValue.length > 100) {
      return 'POI name must be less than 100 characters';
    }
    
    return null;
  }

  /// Validates POI description
  static String? validatePOIDescription(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Description is optional
    }
    
    final trimmedValue = value.trim();
    
    if (trimmedValue.length > 500) {
      return 'Description must be less than 500 characters';
    }
    
    return null;
  }

  /// Validates email format
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    
    final trimmedValue = value.trim();
    
    // Basic email regex
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    
    if (!emailRegex.hasMatch(trimmedValue)) {
      return 'Please enter a valid email address';
    }
    
    return null;
  }

  /// Validates password strength
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    
    if (value.length > 128) {
      return 'Password must be less than 128 characters';
    }
    
    // Check for at least one letter and one number
    if (!RegExp(r'^(?=.*[A-Za-z])(?=.*\d)').hasMatch(value)) {
      return 'Password must contain at least one letter and one number';
    }
    
    return null;
  }

  /// Validates full name
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }
    
    final trimmedValue = value.trim();
    
    if (trimmedValue.length < 2) {
      return 'Name must be at least 2 characters';
    }
    
    if (trimmedValue.length > 50) {
      return 'Name must be less than 50 characters';
    }
    
    // Check if name contains only letters, spaces, hyphens, and apostrophes
    if (!RegExp(r"^[a-zA-Z\s\-']+$").hasMatch(trimmedValue)) {
      return 'Name can only contain letters, spaces, hyphens, and apostrophes';
    }
    
    return null;
  }

  /// Validates display name
  static String? validateDisplayName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Display name is required';
    }
    
    final trimmedValue = value.trim();
    
    if (trimmedValue.length < 2) {
      return 'Display name must be at least 2 characters';
    }
    
    if (trimmedValue.length > 50) {
      return 'Display name must be less than 50 characters';
    }
    
    // Allow letters, numbers, spaces, and some special characters
    if (!RegExp(r'^[a-zA-Z0-9\s\.\-_]+$').hasMatch(trimmedValue)) {
      return 'Display name can only contain letters, numbers, spaces, dots, hyphens, and underscores';
    }
    
    return null;
  }

  /// Validates chat message
  static String? validateChatMessage(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Message cannot be empty';
    }
    
    final trimmedValue = value.trim();
    
    if (trimmedValue.length > 1000) {
      return 'Message must be less than 1000 characters';
    }
    
    return null;
  }

  /// Validates coordinates
  static String? validateLatitude(double? value) {
    if (value == null) {
      return 'Latitude is required';
    }
    
    if (value < -90 || value > 90) {
      return 'Latitude must be between -90 and 90';
    }
    
    return null;
  }

  static String? validateLongitude(double? value) {
    if (value == null) {
      return 'Longitude is required';
    }
    
    if (value < -180 || value > 180) {
      return 'Longitude must be between -180 and 180';
    }
    
    return null;
  }

  /// Helper method to clean and format input
  static String cleanInput(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Helper method to sanitize text for safe display
  static String sanitizeText(String input) {
    return input
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  /// Check if string is a valid URL
  static bool isValidUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    
    try {
      final uri = Uri.parse(url);
      return uri.isAbsolute && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// Check if phone number format is valid (basic check)
  static String? validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Phone number is optional
    }
    
    final trimmedValue = value.trim();
    
    // Basic phone number regex (allows various formats)
    final phoneRegex = RegExp(r'^\+?[\d\s\-\(\)]{10,15}$');
    
    if (!phoneRegex.hasMatch(trimmedValue)) {
      return 'Please enter a valid phone number';
    }
    
    return null;
  }
}
