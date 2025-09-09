import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simha_link/models/emergency.dart';
import 'package:simha_link/services/emergency_management_service.dart';
import 'package:simha_link/services/in_app_notification_service.dart';
import 'package:intl/intl.dart';
import 'dart:async';

/// Widget to display emergency status for attendees with real-time volunteer updates
/// Designed to look similar to EmergencyResponseCard but for attendees
class AttendeeEmergencyStatusWidget extends StatefulWidget {
  final Emergency emergency;
  final VoidCallback onResolve;
  final VoidCallback onCancel;

  const AttendeeEmergencyStatusWidget({
    super.key,
    required this.emergency,
    required this.onResolve,
    required this.onCancel,
  });

  @override
  State<AttendeeEmergencyStatusWidget> createState() => _AttendeeEmergencyStatusWidgetState();
}

class _AttendeeEmergencyStatusWidgetState extends State<AttendeeEmergencyStatusWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _slideAnimation;
  
  StreamSubscription<Emergency?>? _emergencySubscription;
  Emergency? _currentEmergency;
  
  bool _isExpanded = false;
  final double _cardHeight = 140.0; // Collapsed height
  final double _expandedHeight = 400.0;

  @override
  void initState() {
    super.initState();
    _currentEmergency = widget.emergency;
    
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));
    
    // Start pulsing animation
    _animationController.repeat(reverse: true);
    
    // Set up real-time emergency updates
    _setupRealTimeUpdates();
  }

  @override
  void didUpdateWidget(AttendeeEmergencyStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update current emergency when parent provides new data
    if (oldWidget.emergency.emergencyId != widget.emergency.emergencyId ||
        oldWidget.emergency.updatedAt != widget.emergency.updatedAt) {
      setState(() {
        _currentEmergency = widget.emergency;
      });
      
      // Reset subscription for new emergency
      if (oldWidget.emergency.emergencyId != widget.emergency.emergencyId) {
        _emergencySubscription?.cancel();
        _setupRealTimeUpdates();
      }
    }
  }

  void _setupRealTimeUpdates() {
    // Listen to real-time updates for this specific emergency
    _emergencySubscription = EmergencyManagementService.listenToEmergencyUpdates(widget.emergency.emergencyId)
        .listen((updatedEmergency) {
      if (mounted && updatedEmergency != null) {
        setState(() {
          _currentEmergency = updatedEmergency;
        });
        print('🔄 Real-time update received for emergency: ${updatedEmergency.emergencyId}');
        print('📊 Notifications count: ${updatedEmergency.attendeeNotifications.length}');
        print('� Volunteer responses: ${updatedEmergency.responses.length}');
        print('�🔧 Resolution status: attendee=${updatedEmergency.resolvedBy.attendee}, volunteer=${updatedEmergency.resolvedBy.hasVolunteerCompleted}');
        print('🎯 Emergency fully resolved: ${updatedEmergency.isFullyResolved}');
        
        // DEBUG: Log all volunteer responses
        for (final response in updatedEmergency.responses.values) {
          print('👤 Volunteer ${response.volunteerName}: ${response.status.name} at ${response.respondedAt}');
        }
        
        // If emergency is fully resolved, widget should disappear automatically via build logic
        if (updatedEmergency.isFullyResolved) {
          print('🎯 Emergency is fully resolved, widget will be hidden');
        }
      }
    }, onError: (error) {
      print('❌ Error in emergency stream: $error');
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _slideController.dispose();
    _emergencySubscription?.cancel();
    super.dispose();
  }

  void _toggleCard() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _slideController.forward();
      } else {
        _slideController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use current emergency data (which gets updated in real-time)
    final emergency = _currentEmergency ?? widget.emergency;
    
    print('🔍 DEBUG: AttendeeEmergencyStatusWidget build - Notifications count: ${emergency.attendeeNotifications.length}');
    print('🔧 DEBUG: Emergency status: ${emergency.status.name}');
    print('🔧 DEBUG: Emergency resolvedBy - attendee: ${emergency.resolvedBy.attendee}, hasVolunteerCompleted: ${emergency.resolvedBy.hasVolunteerCompleted}');
    print('🔧 DEBUG: Emergency isFullyResolved: ${emergency.isFullyResolved}, canBeFullyResolved: ${emergency.resolvedBy.canBeFullyResolved}');
    
    // IMPORTANT: Don't render if emergency is fully resolved
    if (emergency.isFullyResolved) {
      print('🎯 DEBUG: Emergency is fully resolved, hiding widget - attendee: ${emergency.resolvedBy.attendee}, volunteer: ${emergency.resolvedBy.hasVolunteerCompleted}');
      return const SizedBox.shrink();
    }
    
    return GestureDetector(
      onTap: _toggleCard,
      onPanUpdate: (details) {
        // Make the card respond to vertical swipes
        if (details.delta.dy < -2) {
          // Swiping up - expand
          if (!_isExpanded) {
            _toggleCard();
          }
        } else if (details.delta.dy > 2) {
          // Swiping down - collapse
          if (_isExpanded) {
            _toggleCard();
          }
        }
      },
      child: AnimatedBuilder(
        animation: _slideAnimation,
        builder: (context, child) {
          final currentHeight = _cardHeight + (_expandedHeight - _cardHeight) * _slideAnimation.value;
          
          return Container(
            height: currentHeight,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Collapsed header
                _buildCardHeader(emergency),
                
                // Expanded content
                if (_isExpanded) ...[
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Resolution Status
                          _buildResolutionStatus(context, emergency),
                          
                          const SizedBox(height: 16),
                          
                          // Volunteer Response Status
                          _buildVolunteerStatusList(context, emergency),
                          
                          const SizedBox(height: 16),
                          
                          // Recent Notifications
                          _buildRecentNotifications(context, emergency),
                          
                          const SizedBox(height: 16),
                          
                          // Action Buttons
                          _buildActionButtons(context, emergency),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Build the collapsible card header similar to EmergencyResponseCard
  Widget _buildCardHeader(Emergency emergency) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Swipe indicator bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Status and emergency info row
          Row(
            children: [
              // Emergency status indicator with pulse animation
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.emergency,
                        color: Colors.red,
                        size: 16,
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(width: 12),
              
              // Emergency info and status text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Active',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Created: ${DateFormat('HH:mm').format(emergency.createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Quick action button (if not resolved by attendee)
              if (!emergency.resolvedBy.attendee)
                _buildQuickActionButton(emergency),
                
              // Expand/collapse indicator
              const SizedBox(width: 8),
              Icon(
                _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: Colors.grey.shade600,
                size: 20,
              ),
            ],
          ),
          
          // Swipe hint when collapsed
          if (!_isExpanded) ...[
            const SizedBox(height: 8),
            Text(
              'Swipe up or tap for details',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build quick action button for collapsed state
  Widget _buildQuickActionButton(Emergency emergency) {
    final resolution = emergency.resolvedBy;
    
    return ElevatedButton.icon(
      onPressed: () async {
        final confirmed = await _showResolveConfirmation(context, emergency);
        if (confirmed) {
          widget.onResolve();
        }
      },
      icon: const Icon(Icons.check, size: 16),
      label: Text(
        resolution.hasVolunteerCompleted ? 'Confirm' : 'Resolve',
        style: const TextStyle(fontSize: 12),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// Show confirmation dialog for resolve action
  Future<bool> _showResolveConfirmation(BuildContext context, Emergency emergency) async {
    final resolution = emergency.resolvedBy;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Emergency as Resolved'),
        content: Text(
          resolution.hasVolunteerCompleted 
              ? 'Are you sure you want to confirm that your emergency has been resolved? This will complete the emergency response process.'
              : 'Are you sure your emergency has been resolved? This will notify volunteers and require their confirmation for full resolution.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text(
              resolution.hasVolunteerCompleted ? 'Confirm' : 'Mark Resolved',
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Show confirmation dialog for cancel action
  Future<bool> _showCancelConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Emergency'),
        content: const Text(
          'Are you sure you want to cancel this emergency? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Emergency'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Emergency'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Widget _buildResolutionStatus(BuildContext context, Emergency emergency) {
    final resolution = emergency.resolvedBy;
    
    if (resolution.canBeFullyResolved) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Emergency can be fully resolved! Both you and volunteers have marked it as complete.',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    if (resolution.attendee && !resolution.hasVolunteerCompleted) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.pending, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Waiting for volunteer confirmation. You marked this as resolved.',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    if (!resolution.attendee && resolution.hasVolunteerCompleted) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.volunteer_activism, color: Colors.blue.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Volunteers have marked this as resolved. Please confirm if you agree.',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, color: Colors.red.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Emergency is active. Waiting for resolution from both parties.',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolunteerStatusList(BuildContext context, Emergency emergency) {
    if (emergency.responses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Looking for volunteers nearby...',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Volunteer Responses (${emergency.responses.length})',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.red.shade800,
          ),
        ),
        const SizedBox(height: 8),
        ...emergency.responses.values.map((response) => _buildVolunteerStatusItem(response)),
      ],
    );
  }

  Widget _buildVolunteerStatusItem(EmergencyVolunteerResponse response) {
    Color statusColor;
    IconData statusIcon;
    
    switch (response.status) {
      case EmergencyVolunteerStatus.responding:
        statusColor = Colors.orange;
        statusIcon = Icons.directions_run;
        break;
      case EmergencyVolunteerStatus.enRoute:
        statusColor = Colors.blue;
        statusIcon = Icons.directions_car;
        break;
      case EmergencyVolunteerStatus.arrived:
        statusColor = Colors.green;
        statusIcon = Icons.location_on;
        break;
      case EmergencyVolunteerStatus.verified:
        statusColor = Colors.purple;
        statusIcon = Icons.verified;
        break;
      case EmergencyVolunteerStatus.assisting:
        statusColor = Colors.teal;
        statusIcon = Icons.medical_services;
        break;
      case EmergencyVolunteerStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  response.volunteerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  response.status.displayName,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            DateFormat('HH:mm').format(response.respondedAt),
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentNotifications(BuildContext context, Emergency emergency) {
    print('🔔 DEBUG: Building notifications, count: ${emergency.attendeeNotifications.length}');
    
    if (emergency.attendeeNotifications.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_none, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'No recent updates from volunteers yet.',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final recentNotifications = emergency.attendeeNotifications
        .where((n) => DateTime.now().difference(n.timestamp).inHours < 24)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (recentNotifications.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Updates (${recentNotifications.length})',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.red.shade800,
          ),
        ),
        const SizedBox(height: 8),
        ...recentNotifications.take(3).map((notification) => _buildNotificationItem(notification)),
      ],
    );
  }

  Widget _buildNotificationItem(AttendeeNotification notification) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notifications, color: Colors.blue.shade600, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.message,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('HH:mm').format(notification.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, Emergency emergency) {
    final resolution = emergency.resolvedBy;
    
    return Column(
      children: [
        Row(
          children: [
            if (!resolution.attendee) ...[
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final confirmed = await _showResolveConfirmation(context, emergency);
                    if (confirmed) {
                      widget.onResolve();
                    }
                  },
                  icon: const Icon(Icons.check, size: 20),
                  label: Text(
                    resolution.hasVolunteerCompleted 
                        ? 'Confirm Resolved'
                        : 'Mark as Resolved',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await _showCancelConfirmation(context);
                  if (confirmed) {
                    widget.onCancel();
                  }
                },
                icon: const Icon(Icons.cancel, size: 20),
                label: const Text(
                  'Cancel Emergency',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.shade400, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (resolution.attendee) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You have marked this emergency as resolved. Waiting for volunteer confirmation.',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
