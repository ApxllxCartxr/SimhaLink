import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:simha_link/models/emergency_response.dart';
import 'package:simha_link/models/emergency.dart';

/// Enhanced emergency response card that communicates directly with the emergency database
class EmergencyResponseCard extends StatefulWidget {
  final Emergency? emergency;
  // The volunteer's active emergency response (required for displaying status/timeline)
  final EmergencyResponse? response;
  final Function(EmergencyResponseStatus)? onStatusUpdate;
  final VoidCallback? onViewEmergency;
  final VoidCallback? onCancel;
  final LatLng? volunteerLocation;

  const EmergencyResponseCard({
    super.key,
    this.emergency,
    this.response,
    this.onStatusUpdate,
    this.onViewEmergency,
    this.onCancel,
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

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
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
    return GestureDetector(
      onTap: _toggleCard,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
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
                    size: 20,
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Status text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.response!.status.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        widget.response!.status.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Action button (if next status available)
                if (widget.response!.status.nextStatus != null)
                  _buildQuickActionButton(),
              ],
            ),
          ],
        ),
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
                  'Emergency Response',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            _buildDetailRow(Icons.access_time, 'Started', _formatTimestamp(widget.response!.timestamp)),
            
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
    return Column(
      children: [
        // Primary action button
        if (widget.response!.status.nextStatus != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => widget.onStatusUpdate?.call(widget.response!.status.nextStatus!),
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

  String _getActionButtonText(EmergencyResponseStatus status) {
    switch (status) {
      case EmergencyResponseStatus.enRoute:
        return 'Start Journey';
      case EmergencyResponseStatus.arrived:
        return 'I\'ve Arrived';
      case EmergencyResponseStatus.assisting:
        return 'Start Helping';
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
