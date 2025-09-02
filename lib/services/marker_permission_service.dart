import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/models/poi.dart';

/// Service for managing marker permissions and deletion rights
class MarkerPermissionService {
  /// Check if current user can delete a specific marker
  static bool canDeleteMarker({
    required String userRole,
    required String? markerId,
    required String? createdBy,
    required MarkerType? markerType,
    String? currentUserId,
  }) {
    // Get current user ID if not provided
    currentUserId ??= FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return false;
    
    // Organizers can delete POI markers they created or manage event POIs
    if (userRole == 'Organizer') {
      return _canOrganizerDelete(markerType, createdBy, currentUserId);
    }
    
    // Users can only delete their own markers (if any)
    if (createdBy != null && createdBy == currentUserId) {
      return _canUserDeleteOwnMarker(markerType);
    }
    
    return false;
  }
  
  /// Check if organizer can delete specific marker type
  static bool _canOrganizerDelete(
    MarkerType? markerType, 
    String? createdBy, 
    String currentUserId
  ) {
    if (markerType == null) return false;
    
    // Organizers can delete all POI types
    switch (markerType) {
      case MarkerType.medical:
      case MarkerType.drinkingWater:
      case MarkerType.accessibility:
      case MarkerType.historical:
      case MarkerType.restroom:
      case MarkerType.food:
      case MarkerType.parking:
      case MarkerType.security:
      case MarkerType.information:
        return true;
      
      case MarkerType.emergency:
        // Emergency markers can only be deleted by creator or admin
        return createdBy == currentUserId;
    }
  }
  
  /// Check if user can delete their own marker
  static bool _canUserDeleteOwnMarker(MarkerType? markerType) {
    if (markerType == null) return false;
    
    // Users can delete their own non-emergency markers
    switch (markerType) {
      case MarkerType.emergency:
        return false; // Emergency markers require special handling
      default:
        return true;
    }
  }
  
  /// Get available actions for a marker based on user permissions
  static List<MarkerAction> getAvailableActions({
    required String userRole,
    required String? markerId,
    required String? createdBy,
    required MarkerType? markerType,
  }) {
    List<MarkerAction> actions = [];
    
    // View action is always available
    actions.add(MarkerAction.view);
    
    // Add edit action for organizers
    if (userRole == 'Organizer' && _canOrganizerEdit(markerType)) {
      actions.add(MarkerAction.edit);
    }
    
    // Add delete action if user has permission
    if (canDeleteMarker(
      userRole: userRole,
      markerId: markerId,
      createdBy: createdBy,
      markerType: markerType,
    )) {
      actions.add(MarkerAction.delete);
    }
    
    return actions;
  }
  
  /// Check if organizer can edit marker
  static bool _canOrganizerEdit(MarkerType? markerType) {
    if (markerType == null) return false;
    
    // Organizers can edit all POI types except active emergencies
    return markerType != MarkerType.emergency;
  }
  
  /// Get confirmation message for marker deletion
  static String getDeletionConfirmationMessage(MarkerType markerType, String markerName) {
    switch (markerType) {
      case MarkerType.emergency:
        return 'Are you sure you want to delete the emergency marker "$markerName"? This action cannot be undone and may affect emergency response.';
      case MarkerType.medical:
        return 'Are you sure you want to delete the medical facility "$markerName"?';
      case MarkerType.security:
        return 'Are you sure you want to delete the security point "$markerName"?';
      default:
        return 'Are you sure you want to delete "$markerName"?';
    }
  }
  
  /// Check if marker deletion requires additional confirmation
  static bool requiresAdditionalConfirmation(MarkerType markerType) {
    switch (markerType) {
      case MarkerType.emergency:
      case MarkerType.medical:
      case MarkerType.security:
        return true;
      default:
        return false;
    }
  }
}

/// Available actions for markers
enum MarkerAction {
  view,
  edit,
  delete,
  duplicate,
  share,
}

/// Extension for marker action display
extension MarkerActionExtension on MarkerAction {
  String get displayName {
    switch (this) {
      case MarkerAction.view:
        return 'View Details';
      case MarkerAction.edit:
        return 'Edit Marker';
      case MarkerAction.delete:
        return 'Delete Marker';
      case MarkerAction.duplicate:
        return 'Duplicate';
      case MarkerAction.share:
        return 'Share Location';
    }
  }
  
  IconData get icon {
    switch (this) {
      case MarkerAction.view:
        return Icons.info_outline;
      case MarkerAction.edit:
        return Icons.edit;
      case MarkerAction.delete:
        return Icons.delete_outline;
      case MarkerAction.duplicate:
        return Icons.copy;
      case MarkerAction.share:
        return Icons.share;
    }
  }
  
  Color get color {
    switch (this) {
      case MarkerAction.delete:
        return Colors.red;
      case MarkerAction.edit:
        return Colors.blue;
      default:
        return Colors.grey.shade700;
    }
  }
}
