import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:simha_link/models/emergency.dart';
import 'package:simha_link/services/emergency_database_service.dart';
import 'package:simha_link/services/in_app_notification_service.dart';
import 'package:simha_link/core/utils/app_logger.dart';

/// High-level service for managing emergency workflow and real-time updates
class EmergencyManagementService {
  static final Location _location = Location();
  static Timer? _locationUpdateTimer;
  static String? _currentEmergencyId;
  static String? _currentVolunteerId;
  static StreamSubscription<LocationData>? _locationSubscription;
  
  /// Initialize the emergency management service
  static Future<void> initialize() async {
    AppLogger.logInfo('EmergencyManagementService initialized');
  }

  /// Create a new emergency for an attendee with duplicate prevention
  static Future<Emergency> createEmergency({
    required String attendeeName,
    required String groupId,
    required LatLng location,
    String? message,
  }) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      // Check if user already has an active emergency - ENFORCE ONE PER USER
      final existingEmergency = await EmergencyDatabaseService.getUserActiveEmergency(userId);
      if (existingEmergency != null) {
        AppLogger.logInfo('User already has active emergency, returning existing: ${existingEmergency.emergencyId}');
        
        // Start location tracking for existing emergency
        await _startAttendeeLocationTracking(existingEmergency.emergencyId, groupId, userId);
        
        return existingEmergency;
      }

      final emergency = await EmergencyDatabaseService.createEmergencyWithState(
        attendeeId: userId,
        attendeeName: attendeeName,
        groupId: groupId,
        location: location,
        message: message,
      );

      // Start real-time location tracking for the attendee
      await _startAttendeeLocationTracking(emergency.emergencyId, groupId, userId);

      AppLogger.logInfo('NEW emergency created by attendee: ${emergency.emergencyId}');
      return emergency;
    } catch (e) {
      AppLogger.logError('Error creating emergency', e);
      rethrow;
    }
  }

  /// Resolve emergency with complete cleanup
  static Future<void> resolveEmergency(String emergencyId) async {
    try {
      await EmergencyDatabaseService.resolveEmergencyWithCleanup(emergencyId);
      
      // Stop location tracking
      await _stopAttendeeLocationTracking();
      
      AppLogger.logInfo('Emergency resolved by attendee: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error resolving emergency', e);
      rethrow;
    }
  }

  /// Start real-time location tracking for attendee during emergency
  static Future<void> _startAttendeeLocationTracking(String emergencyId, String groupId, String attendeeId) async {
    try {
      // Stop any existing tracking
      await _stopAttendeeLocationTracking();
      
      _currentEmergencyId = emergencyId;
      _currentVolunteerId = attendeeId; // Reuse for attendee tracking

      // Configure location settings for high accuracy during emergency
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 3000, // 3 seconds for emergency
        distanceFilter: 2, // 2 meters
      );

      // Start location updates for attendee
      _locationSubscription = _location.onLocationChanged.listen(
        (LocationData locationData) {
          if (locationData.latitude != null && 
              locationData.longitude != null &&
              _currentEmergencyId != null) {
            
            final currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
            
            // Update emergency location in real-time
            EmergencyDatabaseService.updateEmergencyLocation(
              emergencyId: _currentEmergencyId!,
              groupId: groupId,
              attendeeId: attendeeId,
              location: currentLocation,
            ).catchError((error) {
              AppLogger.logError('Error updating attendee emergency location', error);
            });
          }
        },
        onError: (error) {
          AppLogger.logError('Attendee location tracking error', error);
        },
      );

      AppLogger.logInfo('Started real-time location tracking for attendee emergency: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error starting attendee location tracking', e);
    }
  }

  /// Stop attendee location tracking
  static Future<void> _stopAttendeeLocationTracking() async {
    try {
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      _locationUpdateTimer?.cancel();
      _locationUpdateTimer = null;
      _currentEmergencyId = null;
      _currentVolunteerId = null;

      AppLogger.logInfo('Stopped attendee location tracking');
    } catch (e) {
      AppLogger.logError('Error stopping attendee location tracking', e);
    }
  }

  /// Volunteer responds to an emergency
  static Future<void> volunteerRespond({
    required String emergencyId,
    required String volunteerName,
    required LatLng volunteerLocation,
  }) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      await EmergencyDatabaseService.addVolunteerResponse(
        emergencyId: emergencyId,
        volunteerId: userId,
        volunteerName: volunteerName,
        volunteerLocation: volunteerLocation,
      );

      // Start real-time location tracking for this volunteer
      await _startVolunteerLocationTracking(emergencyId, userId);

      AppLogger.logInfo('Volunteer responded to emergency: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error volunteer responding to emergency', e);
      rethrow;
    }
  }

  /// Update volunteer status
  static Future<void> updateVolunteerStatus({
    required String emergencyId,
    required EmergencyVolunteerStatus status,
    String? estimatedArrivalTime,
  }) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      // Get current location
      LatLng? currentLocation;
      try {
        final locationData = await _location.getLocation();
        if (locationData.latitude != null && locationData.longitude != null) {
          currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
        }
      } catch (e) {
        AppLogger.logWarning('Could not get current location for status update', e);
      }

      await EmergencyDatabaseService.updateVolunteerStatus(
        emergencyId: emergencyId,
        volunteerId: userId,
        status: status,
        currentLocation: currentLocation,
        estimatedArrivalTime: estimatedArrivalTime,
      );

      // Stop location tracking if volunteer completed or cancelled
      if (status == EmergencyVolunteerStatus.completed || 
          status == EmergencyVolunteerStatus.unavailable) {
        await _stopVolunteerLocationTracking();
      }

      AppLogger.logInfo('Volunteer status updated: ${status.name}');
    } catch (e) {
      AppLogger.logError('Error updating volunteer status', e);
      rethrow;
    }
  }

  /// Cancel volunteer response
  static Future<void> cancelVolunteerResponse(String emergencyId) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      await EmergencyDatabaseService.removeVolunteerResponse(
        emergencyId: emergencyId,
        volunteerId: userId,
      );

      await _stopVolunteerLocationTracking();

      AppLogger.logInfo('Volunteer response cancelled: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error cancelling volunteer response', e);
      rethrow;
    }
  }

  /// Listen to group emergencies
  static StreamSubscription<List<Emergency>> listenToGroupEmergencies(
    String groupId,
    Function(List<Emergency>) onEmergenciesChanged,
  ) {
    return EmergencyDatabaseService.getGroupEmergencies(groupId).listen(
      onEmergenciesChanged,
      onError: (error) {
        AppLogger.logError('Error listening to group emergencies', error);
      },
    );
  }

  /// Listen to ALL emergencies across ALL groups (for volunteers)
  static StreamSubscription<List<Emergency>> listenToAllEmergencies(
    Function(List<Emergency>) onEmergenciesChanged,
  ) {
    return EmergencyDatabaseService.getAllEmergencies().listen(
      onEmergenciesChanged,
      onError: (error) {
        AppLogger.logError('Error listening to all emergencies', error);
      },
    );
  }

  /// Listen to volunteer's active responses
  static StreamSubscription<List<Emergency>> listenToVolunteerResponses(
    String volunteerId,
    Function(List<Emergency>) onResponsesChanged,
  ) {
    return EmergencyDatabaseService.getVolunteerActiveResponses(volunteerId).listen(
      onResponsesChanged,
      onError: (error) {
        AppLogger.logError('Error listening to volunteer responses', error);
      },
    );
  }

  /// Start real-time location tracking for volunteer
  static Future<void> _startVolunteerLocationTracking(String emergencyId, String volunteerId) async {
    try {
      // Stop any existing tracking
      await _stopVolunteerLocationTracking();
      
      _currentEmergencyId = emergencyId;
      _currentVolunteerId = volunteerId;

      // Check location permissions
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          throw Exception('Location service not enabled');
        }
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          throw Exception('Location permission not granted');
        }
      }

      // Configure location settings for high accuracy during emergency
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 5000, // 5 seconds
        distanceFilter: 5, // 5 meters
      );

      // Start location updates
      _locationSubscription = _location.onLocationChanged.listen(
        (LocationData locationData) {
          if (locationData.latitude != null && 
              locationData.longitude != null &&
              _currentEmergencyId != null &&
              _currentVolunteerId != null) {
            
            final currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
            
            // Update location in database (fire and forget)
            EmergencyDatabaseService.updateVolunteerLocation(
              emergencyId: _currentEmergencyId!,
              volunteerId: _currentVolunteerId!,
              location: currentLocation,
            ).catchError((error) {
              AppLogger.logError('Error updating volunteer location', error);
            });
          }
        },
        onError: (error) {
          AppLogger.logError('Location tracking error', error);
        },
      );

      AppLogger.logInfo('Started location tracking for volunteer: $volunteerId');
    } catch (e) {
      AppLogger.logError('Error starting volunteer location tracking', e);
    }
  }

  /// Stop volunteer location tracking
  static Future<void> _stopVolunteerLocationTracking() async {
    try {
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      _locationUpdateTimer?.cancel();
      _locationUpdateTimer = null;
      _currentEmergencyId = null;
      _currentVolunteerId = null;

      AppLogger.logInfo('Stopped volunteer location tracking');
    } catch (e) {
      AppLogger.logError('Error stopping volunteer location tracking', e);
    }
  }

  /// Get emergency statistics
  static Future<Map<String, int>> getEmergencyStats(String groupId) {
    return EmergencyDatabaseService.getEmergencyStats(groupId);
  }

  /// Clean up service
  static Future<void> dispose() async {
    try {
      await _stopVolunteerLocationTracking();
      
      AppLogger.logInfo('EmergencyManagementService disposed');
    } catch (e) {
      AppLogger.logError('Error disposing EmergencyManagementService', e);
    }
  }

  // ========== NEW: Enhanced Volunteer Response Pipeline Methods ==========

  /// Volunteer accepts emergency (Step 1: Unverified → Accepted)
  static Future<void> volunteerAcceptEmergency({
    required String emergencyId,
    required String volunteerName,
    required LatLng volunteerLocation,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await EmergencyDatabaseService.acceptEmergency(
        emergencyId: emergencyId,
        volunteerId: user.uid,
        volunteerName: volunteerName,
        volunteerLocation: volunteerLocation,
      );

      AppLogger.logInfo('Volunteer ${user.uid} accepted emergency $emergencyId');
      
      // Store current emergency for tracking
      _currentEmergencyId = emergencyId;
      _currentVolunteerId = user.uid;
      
    } catch (e) {
      AppLogger.logError('Error accepting emergency', e);
      rethrow;
    }
  }

  /// Volunteer marks as arrived (Step 2: Accepted → In Progress) 
  static Future<void> volunteerMarkArrived({
    required String emergencyId,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await EmergencyDatabaseService.markVolunteerArrived(
        emergencyId: emergencyId,
        volunteerId: user.uid,
      );

      AppLogger.logInfo('Volunteer ${user.uid} marked as arrived at emergency $emergencyId');
      
    } catch (e) {
      AppLogger.logError('Error marking volunteer arrived', e);
      rethrow;
    }
  }

  /// Volunteer verifies emergency (Step 3: In Progress → Verified/Fake/Escalated)
  static Future<void> volunteerVerifyEmergency({
    required String emergencyId,
    required bool isReal,
    bool markAsSerious = false,
    String? escalationReason,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Determine escalation reason
      String? finalEscalationReason;
      if (isReal && markAsSerious) {
        finalEscalationReason = escalationReason ?? 'Marked as serious by volunteer';
      }

      await EmergencyDatabaseService.verifyEmergency(
        emergencyId: emergencyId,
        volunteerId: user.uid,
        isReal: isReal,
        escalationReason: finalEscalationReason,
      );

      if (isReal) {
        if (markAsSerious) {
          AppLogger.logInfo('Volunteer ${user.uid} verified emergency $emergencyId as REAL and ESCALATED');
        } else {
          AppLogger.logInfo('Volunteer ${user.uid} verified emergency $emergencyId as REAL');
        }
      } else {
        AppLogger.logInfo('Volunteer ${user.uid} marked emergency $emergencyId as FAKE');
      }
      
    } catch (e) {
      AppLogger.logError('Error verifying emergency', e);
      rethrow;
    }
  }

  /// Volunteer resolves emergency (Step 4: Testing - Only volunteer can resolve)
  static Future<void> volunteerResolveEmergency({
    required String emergencyId,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await EmergencyDatabaseService.markResolvedByVolunteer(
        emergencyId: emergencyId,
        volunteerId: user.uid,
      );

      AppLogger.logInfo('Volunteer ${user.uid} resolved emergency $emergencyId');
      
      // Clear current emergency tracking
      if (_currentEmergencyId == emergencyId) {
        _currentEmergencyId = null;
        _currentVolunteerId = null;
      }
      
    } catch (e) {
      AppLogger.logError('Error resolving emergency by volunteer', e);
      rethrow;
    }
  }

  /// Get volunteer-visible emergencies (filters out fake emergencies)
  static Stream<List<Emergency>> listenToVolunteerVisibleEmergencies(String groupId) {
    return EmergencyDatabaseService.getVolunteerVisibleEmergencies(groupId);
  }

  /// Calculate distance between volunteer and emergency
  static double calculateDistanceToEmergency(LatLng volunteerLocation, LatLng emergencyLocation) {
    return EmergencyDatabaseService.calculateDistance(volunteerLocation, emergencyLocation);
  }

  /// Format distance for display
  static String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()}m away';
    } else {
      final km = distanceInMeters / 1000;
      return '${km.toStringAsFixed(1)}km away';
    }
  }

  /// Get current emergency status for volunteer
  static Future<Emergency?> getCurrentVolunteerEmergency() async {
    try {
      if (_currentEmergencyId == null) return null;
      
      return await EmergencyDatabaseService.getEmergency(_currentEmergencyId!);
    } catch (e) {
      AppLogger.logError('Error getting current volunteer emergency', e);
      return null;
    }
  }

  // =====================================================================
  // ENHANCED ATTENDEE NOTIFICATION AND DUAL RESOLUTION SYSTEM
  // =====================================================================

  /// Notify attendee of volunteer status changes
  static Future<void> notifyAttendeeOfVolunteerStatus({
    required String emergencyId,
    required String volunteerId,
    required String volunteerName,
    required EmergencyVolunteerStatus newStatus,
    LatLng? volunteerLocation,
  }) async {
    try {
      print('🔔 DEBUG: Starting notification process for emergency: $emergencyId');
      print('👤 DEBUG: Volunteer: $volunteerName, Status: ${newStatus.name}');
      
      // CRITICAL FIX: Update the volunteer status in the emergency FIRST
      // This ensures the real-time listeners pick up the change
      await EmergencyDatabaseService.updateVolunteerStatus(
        emergencyId: emergencyId,
        volunteerId: volunteerId,
        status: newStatus,
        currentLocation: volunteerLocation,
      );
      
      print('✅ DEBUG: Volunteer status updated in database');
      
      // Get emergency details AFTER updating volunteer status
      final emergency = await EmergencyDatabaseService.getEmergency(emergencyId);
      if (emergency == null) {
        print('❌ DEBUG: Emergency not found: $emergencyId');
        return;
      }

      print('✅ DEBUG: Emergency found, current notifications: ${emergency.attendeeNotifications.length}');
      print('👥 DEBUG: Current volunteer responses: ${emergency.responses.length}');

      // Calculate distance if volunteer location available
      String locationInfo = '';
      if (volunteerLocation != null) {
        final distance = calculateDistanceToEmergency(volunteerLocation, emergency.location);
        locationInfo = ' (${formatDistance(distance)})';
      }

      // Create status message
      final statusMessage = _getStatusMessageForAttendee(newStatus, volunteerName, locationInfo);
      print('📝 DEBUG: Status message: $statusMessage');

      // Create notification object
      final notification = AttendeeNotification(
        timestamp: DateTime.now(),
        volunteerId: volunteerId,
        volunteerName: volunteerName,
        status: newStatus.name,
        message: statusMessage,
        volunteerLocation: volunteerLocation,
      );

      print('📮 DEBUG: Created notification for volunteer: $volunteerName');

      // Update emergency with attendee notification
      final updatedNotifications = List<AttendeeNotification>.from(emergency.attendeeNotifications);
      updatedNotifications.add(notification);

      print('📋 DEBUG: Updated notifications count: ${updatedNotifications.length}');

      // CRITICAL: Force update with new timestamp to trigger Firestore listeners
      await EmergencyDatabaseService.updateEmergency(
        emergencyId,
        emergency.copyWith(
          attendeeNotifications: updatedNotifications,
          updatedAt: DateTime.now(), // Force timestamp update
          // IMPORTANT: Ensure volunteer responses are preserved
          responses: emergency.responses,
        ),
      );

      print('💾 DEBUG: Emergency updated in database successfully');
      print('🔄 DEBUG: This should trigger real-time listeners');
      AppLogger.logInfo('Attendee notified: $statusMessage');
    } catch (e) {
      print('❌ DEBUG: Error in notification: $e');
      AppLogger.logError('Error notifying attendee of volunteer status', e);
    }
  }

  /// Get status message for attendee notifications
  static String _getStatusMessageForAttendee(
    EmergencyVolunteerStatus status,
    String volunteerName,
    String locationInfo,
  ) {
    switch (status) {
      case EmergencyVolunteerStatus.responding:
        return '🚨 $volunteerName is responding to your emergency$locationInfo';
      case EmergencyVolunteerStatus.enRoute:
        return '🏃 $volunteerName is on their way$locationInfo';
      case EmergencyVolunteerStatus.arrived:
        return '📍 $volunteerName has arrived at your location';
      case EmergencyVolunteerStatus.verified:
        return '✅ $volunteerName confirmed your emergency is real';
      case EmergencyVolunteerStatus.assisting:
        return '🤝 $volunteerName is now assisting you';
      case EmergencyVolunteerStatus.completed:
        return '✅ $volunteerName has completed their assistance';
      default:
        return '$volunteerName updated their status to ${status.name}';
    }
  }

  /// Enhanced attendee mark resolved (dual resolution system)
  static Future<void> attendeeMarkResolved({
    required String emergencyId,
    String? notes,
  }) async {
    try {
      final emergency = await EmergencyDatabaseService.getEmergency(emergencyId);
      if (emergency == null) throw Exception('Emergency not found');

      // Update attendee resolution status
      final updatedResolution = emergency.resolvedBy.copyWith(
        attendee: true,
        attendeeResolvedAt: DateTime.now(),
        attendeeResolutionNotes: notes,
      );

      final updatedEmergency = emergency.copyWith(
        resolvedBy: updatedResolution,
        updatedAt: DateTime.now(),
      );

      await EmergencyDatabaseService.updateEmergency(emergencyId, updatedEmergency);

      // Check if emergency can be fully resolved
      if (updatedResolution.canBeFullyResolved) {
        // Both parties have resolved - mark as fully resolved
        await _fullyResolveEmergency(emergencyId, emergency.groupId);
        
        // Notify all volunteers
        await _notifyVolunteersOfFullResolution(emergency);
      } else {
        // Notify volunteers that attendee has marked as resolved
        await _notifyVolunteersAttendeeResolved(emergency);
      }

      // Stop location tracking for attendee
      await _stopAttendeeLocationTracking();

      AppLogger.logInfo('Attendee marked emergency as resolved: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error marking emergency as resolved by attendee', e);
      rethrow;
    }
  }

  /// Enhanced volunteer mark resolved (dual resolution system)
  static Future<void> volunteerMarkResolved({
    required String emergencyId,
    String? notes,
  }) async {
    try {
      final emergency = await EmergencyDatabaseService.getEmergency(emergencyId);
      if (emergency == null) throw Exception('Emergency not found');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Create volunteer resolution
      final volunteerResolution = VolunteerResolution(
        volunteerId: currentUser.uid,
        volunteerName: currentUser.displayName ?? 'Unknown Volunteer',
        resolvedAt: DateTime.now(),
        notes: notes,
      );

      // Update volunteer resolution status
      final updatedVolunteerResolutions = Map<String, VolunteerResolution>.from(
        emergency.resolvedBy.volunteerResolutions,
      );
      updatedVolunteerResolutions[currentUser.uid] = volunteerResolution;

      final updatedResolution = emergency.resolvedBy.copyWith(
        hasVolunteerCompleted: true,
        lastVolunteerResolvedAt: DateTime.now(),
        volunteerResolutions: updatedVolunteerResolutions,
      );

      final updatedEmergency = emergency.copyWith(
        resolvedBy: updatedResolution,
        updatedAt: DateTime.now(),
      );

      await EmergencyDatabaseService.updateEmergency(emergencyId, updatedEmergency);

      // Check if emergency can be fully resolved
      if (updatedResolution.canBeFullyResolved) {
        // Both parties have resolved - mark as fully resolved
        await _fullyResolveEmergency(emergencyId, emergency.groupId);
        
        // Notify attendee of full resolution
        await _notifyAttendeeOfFullResolution(emergency);
      } else {
        // Notify attendee that volunteer has marked as resolved
        await _notifyAttendeeVolunteerResolved(emergency, currentUser);
      }

      AppLogger.logInfo('Volunteer marked emergency as resolved: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error marking emergency as resolved by volunteer', e);
      rethrow;
    }
  }

  /// Fully resolve emergency when both parties agree
  static Future<void> _fullyResolveEmergency(String emergencyId, String groupId) async {
    await EmergencyDatabaseService.updateEmergencyStatus(
      emergencyId,
      EmergencyStatus.resolved,
      fullyResolvedAt: DateTime.now(),
    );
    
    AppLogger.logInfo('Emergency fully resolved: $emergencyId');
  }

  /// Notify volunteers of full resolution
  static Future<void> _notifyVolunteersOfFullResolution(Emergency emergency) async {
    try {
      // Send notification to all volunteers who responded
      for (final response in emergency.responses.values) {
        // For now, send global notification - could be personalized per volunteer
        InAppNotificationService.instance.showNotification(
          title: '✅ Emergency Resolved',
          message: 'Emergency in ${emergency.groupId} has been fully resolved by all parties.',
          type: InAppNotificationType.success,
        );
        // Break after first to avoid duplicate notifications
        break;
      }
      
      // If no volunteers responded, still log completion
      if (emergency.responses.isEmpty) {
        AppLogger.logInfo('No volunteers to notify for emergency: ${emergency.emergencyId}');
      }
      AppLogger.logInfo('Volunteers notified of full resolution: ${emergency.emergencyId}');
    } catch (e) {
      AppLogger.logError('Error notifying volunteers of full resolution', e);
    }
  }

  /// Notify attendee of full resolution
  static Future<void> _notifyAttendeeOfFullResolution(Emergency emergency) async {
    try {
      InAppNotificationService.instance.showNotification(
        title: '🎉 Emergency Fully Resolved',
        message: 'Your emergency has been completely resolved by all parties. Thank you for using our emergency system safely.',
        type: InAppNotificationType.success,
      );
      AppLogger.logInfo('Attendee notified of full resolution: ${emergency.emergencyId}');
    } catch (e) {
      AppLogger.logError('Error notifying attendee of full resolution', e);
    }
  }

  /// Notify volunteers that attendee has resolved
  static Future<void> _notifyVolunteersAttendeeResolved(Emergency emergency) async {
    try {
      // Send notification to all responding volunteers
      if (emergency.responses.isNotEmpty) {
        // Could implement individual notifications per volunteer here
        InAppNotificationService.instance.showNotification(
          title: '👍 Attendee Marked Resolved',
          message: 'The attendee has marked their emergency as resolved. Please confirm if you agree.',
          type: InAppNotificationType.info,
        );
      }
      
      AppLogger.logInfo('Volunteers notified attendee resolved: ${emergency.emergencyId}');
    } catch (e) {
      AppLogger.logError('Error notifying volunteers attendee resolved', e);
    }
  }

  /// Notify attendee that volunteer has resolved
  static Future<void> _notifyAttendeeVolunteerResolved(Emergency emergency, User volunteer) async {
    final notification = AttendeeNotification(
      timestamp: DateTime.now(),
      volunteerId: volunteer.uid,
      volunteerName: volunteer.displayName ?? 'Unknown Volunteer',
      status: 'completed',
      message: '✅ ${volunteer.displayName ?? 'Volunteer'} has marked your emergency as resolved. Please confirm if you agree.',
    );

    // Add notification to emergency
    final updatedNotifications = List<AttendeeNotification>.from(emergency.attendeeNotifications);
    updatedNotifications.add(notification);

    await EmergencyDatabaseService.updateEmergency(
      emergency.emergencyId,
      emergency.copyWith(
        attendeeNotifications: updatedNotifications,
        updatedAt: DateTime.now(),
      ),
    );

    AppLogger.logInfo('Attendee notified volunteer resolved: ${emergency.emergencyId}');
  }

  // ========== Enhanced Resolution & Cancellation System ==========

  /// Enhanced attendee resolution with in-app notifications
  static Future<void> attendeeResolveEmergencyV2({
    required String emergencyId,
    String? notes,
  }) async {
    try {
      final emergency = await EmergencyDatabaseService.getEmergency(emergencyId);
      if (emergency == null) throw Exception('Emergency not found');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Update attendee resolution status
      final updatedResolution = emergency.resolvedBy.copyWith(
        attendee: true,
        attendeeResolvedAt: DateTime.now(),
        attendeeResolutionNotes: notes,
      );

      final updatedEmergency = emergency.copyWith(
        resolvedBy: updatedResolution,
        updatedAt: DateTime.now(),
      );

      await EmergencyDatabaseService.updateEmergency(emergencyId, updatedEmergency);

      // Check if emergency can be fully resolved
      if (updatedResolution.canBeFullyResolved) {
        // Both parties have resolved - mark as fully resolved
        await _fullyResolveEmergency(emergencyId, emergency.groupId);
        
        // Show completion notification
        InAppNotificationService.instance.showResolutionNotification(
          title: '🎉 Emergency Resolved!',
          message: 'Your emergency has been fully resolved by both you and the volunteer.',
          emergencyId: emergencyId,
          isComplete: true,
        );
        
        // Notify all volunteers
        await _notifyVolunteersOfFullResolution(emergency);
      } else {
        // Show partial resolution notification
        InAppNotificationService.instance.showResolutionNotification(
          title: '✅ Marked as Resolved',
          message: 'Waiting for volunteer confirmation to complete resolution.',
          emergencyId: emergencyId,
          isComplete: false,
        );
        
        // Notify volunteers that attendee has marked as resolved
        await _notifyVolunteersAttendeeResolved(emergency);
      }

      // Stop location tracking for attendee
      await _stopAttendeeLocationTracking();

      AppLogger.logInfo('Attendee marked emergency as resolved: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error marking emergency as resolved by attendee', e);
      
      // Show error notification
      InAppNotificationService.instance.showNotification(
        title: '❌ Resolution Failed',
        message: 'Failed to mark emergency as resolved. Please try again.',
        type: InAppNotificationType.error,
      );
      rethrow;
    }
  }

  /// Enhanced volunteer resolution with in-app notifications
  static Future<void> volunteerResolveEmergencyV2({
    required String emergencyId,
    String? notes,
  }) async {
    try {
      final emergency = await EmergencyDatabaseService.getEmergency(emergencyId);
      if (emergency == null) throw Exception('Emergency not found');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Create volunteer resolution
      final volunteerResolution = VolunteerResolution(
        volunteerId: currentUser.uid,
        volunteerName: currentUser.displayName ?? 'Unknown Volunteer',
        resolvedAt: DateTime.now(),
        notes: notes,
      );

      // Update volunteer resolution status
      final updatedVolunteerResolutions = Map<String, VolunteerResolution>.from(
        emergency.resolvedBy.volunteerResolutions,
      );
      updatedVolunteerResolutions[currentUser.uid] = volunteerResolution;

      final updatedResolution = emergency.resolvedBy.copyWith(
        hasVolunteerCompleted: true,
        lastVolunteerResolvedAt: DateTime.now(),
        volunteerResolutions: updatedVolunteerResolutions,
      );

      final updatedEmergency = emergency.copyWith(
        resolvedBy: updatedResolution,
        updatedAt: DateTime.now(),
      );

      await EmergencyDatabaseService.updateEmergency(emergencyId, updatedEmergency);

      // Check if emergency can be fully resolved
      if (updatedResolution.canBeFullyResolved) {
        // Both parties have resolved - mark as fully resolved
        await _fullyResolveEmergency(emergencyId, emergency.groupId);
        
        // Show completion notification
        InAppNotificationService.instance.showResolutionNotification(
          title: '🎉 Emergency Completed!',
          message: 'You have successfully completed the emergency assistance.',
          emergencyId: emergencyId,
          isComplete: true,
        );
        
        // Notify attendee of full resolution
        await _notifyAttendeeOfFullResolution(emergency);
      } else {
        // Show partial resolution notification
        InAppNotificationService.instance.showResolutionNotification(
          title: '✅ Assistance Completed',
          message: 'Waiting for attendee confirmation to fully resolve emergency.',
          emergencyId: emergencyId,
          isComplete: false,
        );
        
        // Notify attendee that volunteer has marked as resolved
        await _notifyAttendeeVolunteerResolved(emergency, currentUser);
      }

      AppLogger.logInfo('Volunteer marked emergency as resolved: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error marking emergency as resolved by volunteer', e);
      
      // Show error notification
      InAppNotificationService.instance.showNotification(
        title: '❌ Resolution Failed',
        message: 'Failed to mark emergency as completed. Please try again.',
        type: InAppNotificationType.error,
      );
      rethrow;
    }
  }

  /// Cancel emergency by attendee - FIXED to match FAB toggle functionality
  static Future<void> cancelEmergency({
    required String emergencyId,
    required String reason,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      print('🚫 DEBUG: Cancelling emergency: $emergencyId with reason: $reason');

      // FIXED: Get emergency data BEFORE cleanup (to notify volunteers)
      final emergency = await EmergencyDatabaseService.getEmergency(emergencyId);
      if (emergency == null) throw Exception('Emergency not found');

      // Notify volunteers BEFORE cleanup
      await _notifyVolunteersCancellation(emergency, reason);

      // FIXED: Use the same cleanup method as FAB toggle for consistency
      await EmergencyDatabaseService.resolveEmergencyWithCleanup(emergencyId);

      print('✅ DEBUG: Emergency cleanup completed');

      // FIXED: Use the same notification style as FAB toggle
      InAppNotificationService.instance.showNotification(
        title: '✅ Emergency Cancelled',
        message: 'Your emergency has been cancelled successfully. All volunteers have been notified.',
        type: InAppNotificationType.success, // Changed to success to match FAB
      );

      // FIXED: Use the same location tracking cleanup as FAB
      await _stopAttendeeLocationTracking();

      AppLogger.logInfo('Emergency cancelled with cleanup: $emergencyId - $reason');
    } catch (e) {
      AppLogger.logError('Error cancelling emergency', e);
      
      // Show error notification
      InAppNotificationService.instance.showNotification(
        title: '❌ Cancellation Failed',
        message: 'Failed to cancel emergency. Please try again.',
        type: InAppNotificationType.error,
      );
      rethrow;
    }
  }

  /// Mark emergency as false alarm by volunteer
  static Future<void> markEmergencyAsFake({
    required String emergencyId,
    required String reason,
  }) async {
    try {
      final emergency = await EmergencyDatabaseService.getEmergency(emergencyId);
      if (emergency == null) throw Exception('Emergency not found');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Update emergency status to fake
      await EmergencyDatabaseService.updateEmergencyStatus(
        emergencyId,
        EmergencyStatus.fake,
      );

      // Add verification details
      await EmergencyDatabaseService.verifyEmergency(
        emergencyId: emergencyId,
        volunteerId: currentUser.uid,
        isReal: false,
        escalationReason: reason,
      );

      // Show fake alarm notification
      InAppNotificationService.instance.showNotification(
        title: '⚠️ False Alarm Reported',
        message: 'Emergency has been marked as a false alarm.',
        type: InAppNotificationType.warning,
      );

      // Notify attendee
      await _notifyAttendeeFakeAlarm(emergency, currentUser.displayName ?? 'Volunteer', reason);

      AppLogger.logInfo('Emergency marked as fake: $emergencyId - $reason');
    } catch (e) {
      AppLogger.logError('Error marking emergency as fake', e);
      
      // Show error notification
      InAppNotificationService.instance.showNotification(
        title: '❌ Failed to Report',
        message: 'Failed to mark emergency as false alarm.',
        type: InAppNotificationType.error,
      );
      rethrow;
    }
  }

  /// Enhanced volunteer status update with in-app notifications
  static Future<void> updateVolunteerStatusV2({
    required String emergencyId,
    required EmergencyVolunteerStatus status,
    String? notes,
    String? estimatedArrivalTime,
  }) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      final emergency = await EmergencyDatabaseService.getEmergency(emergencyId);
      if (emergency == null) throw Exception('Emergency not found');

      // Get current location
      LatLng? currentLocation;
      try {
        final locationData = await _location.getLocation();
        if (locationData.latitude != null && locationData.longitude != null) {
          currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
        }
      } catch (e) {
        AppLogger.logWarning('Could not get current location for status update', e);
      }

      // Get volunteer name for notifications
      final volunteerName = FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown Volunteer';
      
      print('🔄 DEBUG: Updating volunteer status to ${status.name}');
      
      // FIXED: Don't call updateVolunteerStatus twice - it's called in notifyAttendeeOfVolunteerStatus
      // await EmergencyDatabaseService.updateVolunteerStatus(...) // REMOVED
      
      // Send notification to attendee about status change (this also updates the status)
      await notifyAttendeeOfVolunteerStatus(
        emergencyId: emergencyId,
        volunteerId: userId,
        volunteerName: volunteerName,
        newStatus: status,
        volunteerLocation: currentLocation,
      );

      print('✅ DEBUG: Notification sent to attendee');

      // Show in-app notification to volunteer
      String volunteerMessage;
      switch (status) {
        case EmergencyVolunteerStatus.responding:
          volunteerMessage = 'You are now responding to the emergency';
          break;
        case EmergencyVolunteerStatus.enRoute:
          volunteerMessage = 'En route to emergency location';
          break;
        case EmergencyVolunteerStatus.arrived:
          volunteerMessage = 'You have arrived at the emergency location';
          break;
        case EmergencyVolunteerStatus.assisting:
          volunteerMessage = 'You are now assisting the attendee';
          break;
        case EmergencyVolunteerStatus.completed:
          volunteerMessage = 'Assistance completed';
          break;
        default:
          volunteerMessage = 'Status updated to ${status.displayName}';
      }

      InAppNotificationService.instance.showVolunteerStatusNotification(
        volunteerName: 'You',
        status: volunteerMessage,
        emergencyId: emergencyId,
      );

      // Stop location tracking if volunteer completed or cancelled
      if (status == EmergencyVolunteerStatus.completed || 
          status == EmergencyVolunteerStatus.unavailable) {
        await _stopVolunteerLocationTracking();
      }

      AppLogger.logInfo('Volunteer status updated: ${status.name}');
    } catch (e) {
      AppLogger.logError('Error updating volunteer status', e);
      
      // Show error notification
      InAppNotificationService.instance.showNotification(
        title: '❌ Status Update Failed',
        message: 'Failed to update your status. Please try again.',
        type: InAppNotificationType.error,
      );
      rethrow;
    }
  }

  // ========== Notification Helper Methods ==========

  /// Notify volunteers about emergency cancellation
  static Future<void> _notifyVolunteersCancellation(Emergency emergency, String reason) async {
    try {
      // Send notifications to all responding volunteers
      for (final response in emergency.responses.values) {
        if (response.status != EmergencyVolunteerStatus.unavailable) {
          // Send notification to each responding volunteer
          InAppNotificationService.instance.showNotification(
            title: '❌ Emergency Cancelled',
            message: 'Emergency in ${emergency.groupId} has been cancelled by the attendee. Reason: $reason',
            type: InAppNotificationType.warning,
          );
          
          AppLogger.logInfo('Notifying volunteer ${response.volunteerName} of cancellation');
        }
      }
      
      // If no volunteers to notify
      if (emergency.responses.isEmpty) {
        AppLogger.logInfo('No volunteers to notify of cancellation for emergency: ${emergency.emergencyId}');
      }
    } catch (e) {
      AppLogger.logError('Error notifying volunteers of cancellation', e);
    }
  }

  /// Notify attendee about false alarm determination
  static Future<void> _notifyAttendeeFakeAlarm(Emergency emergency, String volunteerName, String reason) async {
    final notification = AttendeeNotification(
      timestamp: DateTime.now(),
      volunteerId: 'system',
      volunteerName: volunteerName,
      status: 'false_alarm',
      message: '⚠️ $volunteerName has determined this was a false alarm: $reason',
    );

    // Add notification to emergency
    final updatedNotifications = List<AttendeeNotification>.from(emergency.attendeeNotifications);
    updatedNotifications.add(notification);

    await EmergencyDatabaseService.updateEmergency(
      emergency.emergencyId,
      emergency.copyWith(
        attendeeNotifications: updatedNotifications,
        updatedAt: DateTime.now(),
      ),
    );

    AppLogger.logInfo('Attendee notified of false alarm: ${emergency.emergencyId}');
  }

  /// Listen to user's emergency status for attendees
  static Stream<Emergency?> listenToUserEmergencyStatus(String userId) {
    return EmergencyDatabaseService.listenToUserEmergencyStatus(userId);
  }

  /// Listen to specific emergency updates for real-time sync
  static Stream<Emergency?> listenToEmergencyUpdates(String emergencyId) {
    return EmergencyDatabaseService.listenToEmergencyUpdates(emergencyId);
  }
}
