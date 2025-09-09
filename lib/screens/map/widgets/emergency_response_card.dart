import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:simha_link/models/emergency_response.dart';
import 'package:simha_link/models/emergency.dart';
import 'package:simha_link/services/emergency_management_service.dart';

/// Enhanced emergency response card that communicates directly with the emergency database
class EmergencyResponseCard extends StatefulWidget {
  final Emergency? emergency;
  // The volunteer's active emergency response (required for displaying status/timeline)
  final EmergencyResponse? response;
  final Function(EmergencyResponseStatus)? onStatusUpdate;
  final VoidCallback? onViewEmergency;
  final VoidCallback? onCancel;
  final VoidCallback? onReportFakeAlarm;
  final LatLng? volunteerLocation;

  const EmergencyResponseCard({
    super.key,
    this.emergency,
    this.response,
    this.onStatusUpdate,
    this.onViewEmergency,
    this.onCancel,
    this.onReportFakeAlarm,
    this.volunteerLocation,
  });

  @override
  State<EmergencyResponseCard> createState() => _EmergencyResponseCardState();
}

class _EmergencyResponseCardState extends State<EmergencyResponseCard> with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  
  bool _isExpanded = false;
  double _cardHeight = 120.0; // Collapsed height
  final double _expandedHeight = 300.0;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _slideController.dispose();
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
    if (widget.response == null || !widget.response!.isActive) {
      return const SizedBox.shrink();
    }

    // Debug: Log current status and next status
    print('🎯 DEBUG CARD BUILD: Current status: ${widget.response!.status.name}');
    print('🎯 DEBUG CARD BUILD: Next status: ${widget.response!.status.nextStatus?.name ?? "None"}');
    print('🎯 DEBUG CARD BUILD: Is active: ${widget.response!.isActive}');

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
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Handle and header
                _buildCardHeader(),
                
                // Content
                Expanded(
                  child: _buildCardContent(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          // Drag handle - more prominent
          Container(
            width: 50,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Status and action row
          Row(
            children: [
              // Status indicator
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.response!.status.statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.response!.status.statusIcon,
                  color: widget.response!.status.statusColor,
                  size: 16,
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Status text and person name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.response!.status.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: widget.response!.status.statusColor,
                        fontSize: 14,
                      ),
                    ),
                    if (widget.emergency != null)
                      Text(
                        'Emergency: ${widget.emergency!.attendeeName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              
              // Quick action button
              if (widget.response!.status.nextStatus != null)
                _buildQuickActionButton(),
                
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

  Widget _buildQuickActionButton() {
    final nextStatus = widget.response!.status.nextStatus!;
    
    return ElevatedButton.icon(
      onPressed: () => widget.onStatusUpdate?.call(nextStatus),
      icon: Icon(nextStatus.statusIcon, size: 16),
      label: Text(_getActionButtonText(nextStatus)),
      style: ElevatedButton.styleFrom(
        backgroundColor: nextStatus.statusColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildCardContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emergency details
          _buildEmergencyDetails(),
          
          const SizedBox(height: 20),
          
          // Status timeline
          _buildStatusTimeline(),
          
          const SizedBox(height: 20),
          
          // Action buttons
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildEmergencyDetails() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emergency, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Emergency Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Emergency basic info
            if (widget.emergency != null) ...[
              _buildDetailRow(Icons.person, 'Person', widget.emergency!.attendeeName),
              _buildDetailRow(Icons.location_on, 'Location', 
                '${widget.emergency!.location.latitude.toStringAsFixed(6)}, ${widget.emergency!.location.longitude.toStringAsFixed(6)}'),
              if (widget.emergency!.message != null && widget.emergency!.message!.isNotEmpty)
                _buildDetailRow(Icons.message, 'Message', widget.emergency!.message!),
              _buildDetailRow(Icons.info, 'Status', widget.emergency!.status.displayName),
            ],
            
            // Response timing info
            _buildDetailRow(Icons.access_time, 'Response Started', _formatTimestamp(widget.response!.timestamp)),
            
            if (widget.response!.distanceToEmergency != null)
              _buildDetailRow(
                Icons.straighten, 
                'Distance', 
                '${(widget.response!.distanceToEmergency! / 1000).toStringAsFixed(1)} km'
              ),
              
            if (widget.response!.estimatedArrivalTime != null)
              _buildDetailRow(Icons.schedule, 'ETA', widget.response!.estimatedArrivalTime!),
              
            _buildDetailRow(Icons.update, 'Last Update', _formatTimestamp(widget.response!.lastUpdated ?? widget.response!.timestamp)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline() {
    final allStatuses = [
      EmergencyResponseStatus.responding,
      EmergencyResponseStatus.enRoute,
      EmergencyResponseStatus.arrived,
      EmergencyResponseStatus.verified,
      EmergencyResponseStatus.assisting,
      EmergencyResponseStatus.completed,
    ];
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Progress Timeline',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 12),
            ...allStatuses.map((status) => _buildTimelineItem(status)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(EmergencyResponseStatus status) {
    final currentStatusIndex = EmergencyResponseStatus.values.indexOf(widget.response!.status);
    final statusIndex = EmergencyResponseStatus.values.indexOf(status);
    final isCompleted = statusIndex <= currentStatusIndex;
    final isCurrent = status == widget.response!.status;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Timeline indicator
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted 
                  ? (isCurrent ? status.statusColor : Colors.green)
                  : Colors.grey.shade300,
            ),
            child: Icon(
              isCurrent ? status.statusIcon : (isCompleted ? Icons.check : null),
              color: Colors.white,
              size: 16,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Status text
          Expanded(
            child: Text(
              status.displayName,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCompleted ? Colors.black87 : Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    // Special handling for assisting status - show escalate vs resolve options
    if (widget.response!.status == EmergencyResponseStatus.assisting) {
      return Column(
        children: [
          // Emergency Escalation vs Resolution choice
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: const Text(
              'Choose next action:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          
          // Escalate button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showEscalationDialog(),
              icon: const Icon(Icons.warning),
              label: const Text('🚨 Escalate Emergency'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Resolve button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => widget.onStatusUpdate?.call(EmergencyResponseStatus.completed),
              icon: const Icon(Icons.check_circle),
              label: const Text('✅ Mark as Resolved'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // False alarm button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => widget.onReportFakeAlarm?.call(),
              icon: const Icon(Icons.report_problem),
              label: const Text('⚠️ Report False Alarm'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange, width: 2),
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Secondary actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onViewEmergency,
                  icon: const Icon(Icons.location_on),
                  label: const Text('View Location'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  label: const Text('Cancel', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Regular workflow progression for other statuses
    return Column(
      children: [
        // Primary action button for normal workflow progression
        if (widget.response!.status.nextStatus != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final nextStatus = widget.response!.status.nextStatus!;
                print('🎯 DEBUG CARD: Button pressed for status: ${nextStatus.name}');
                print('🎯 DEBUG CARD: Current status: ${widget.response!.status.name}');
                widget.onStatusUpdate?.call(nextStatus);
              },
              icon: Icon(widget.response!.status.nextStatus!.statusIcon),
              label: Text(_getActionButtonText(widget.response!.status.nextStatus!)),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.response!.status.nextStatus!.statusColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        
        const SizedBox(height: 12),
        
        // Secondary actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onViewEmergency,
                icon: const Icon(Icons.location_on),
                label: const Text('View Location'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            
            const SizedBox(width: 12),
            
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.cancel, color: Colors.red),
                label: const Text('Cancel', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showEscalationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String escalationReason = '';
        return AlertDialog(
          title: const Text('🚨 Escalate Emergency'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This will escalate the emergency to higher authorities. Please provide a reason:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => escalationReason = value,
                decoration: const InputDecoration(
                  hintText: 'Reason for escalation...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // TODO: Implement escalation logic
                _handleEscalation(escalationReason);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Escalate', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _handleEscalation(String reason) async {
    try {
      // Use the existing escalation service
      await EmergencyManagementService.volunteerVerifyEmergency(
        emergencyId: widget.emergency!.emergencyId,
        isReal: true,
        markAsSerious: true,
        escalationReason: reason,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🚨 Emergency escalated: $reason'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
        
        // Update the card to reflect escalation
        widget.onStatusUpdate?.call(EmergencyResponseStatus.completed);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to escalate emergency: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _getActionButtonText(EmergencyResponseStatus status) {
    switch (status) {
      case EmergencyResponseStatus.enRoute:
        return 'Start Journey';
      case EmergencyResponseStatus.arrived:
        return 'I\'ve Arrived';
      case EmergencyResponseStatus.verified:
        return 'Verify Emergency';
      case EmergencyResponseStatus.assisting:
        return 'Start Assisting';
      case EmergencyResponseStatus.completed:
        return 'Mark Resolved';
      default:
        return 'Update Status';
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}
