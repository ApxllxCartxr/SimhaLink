import 'package:flutter/material.dart';
import 'package:simha_link/models/user_location.dart';
import 'package:simha_link/models/poi.dart';
import 'package:simha_link/config/app_colors.dart';

/// Info panel widget for displaying selected user or POI information
class MapInfoPanel extends StatelessWidget {
  final UserLocation? selectedMember;
  final POI? selectedPOI;
  final String routeInfo;
  final bool isLoadingRoute;
  final VoidCallback? onClose;

  const MapInfoPanel({
    super.key,
    this.selectedMember,
    this.selectedPOI,
    required this.routeInfo,
    required this.isLoadingRoute,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedMember == null && selectedPOI == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Card(
        color: AppColors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: selectedMember != null
              ? _buildMemberInfo()
              : _buildPOIInfo(),
        ),
      ),
    );
  }

  Widget _buildMemberInfo() {
    final member = selectedMember!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              member.isEmergency ? Icons.emergency : _getRoleIcon(member.userRole),
              color: member.isEmergency
                  ? AppColors.mapEmergency
                  : _getRoleColor(member.userRole),
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.userName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (member.userRole != null)
                    Text(
                      member.userRole!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                icon: Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: onClose,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
        if (member.isEmergency) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.mapEmergency.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.mapEmergency, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning,
                  color: AppColors.mapEmergency,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  'EMERGENCY',
                  style: TextStyle(
                    color: AppColors.mapEmergency,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (routeInfo.isNotEmpty) ...[
          const SizedBox(height: 8),
          Divider(color: AppColors.border),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.directions_walk,
                color: AppColors.textSecondary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: isLoadingRoute
                    ? Text(
                        'Calculating route...',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      )
                    : Text(
                        routeInfo,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                      ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Last updated: ${_formatTimestamp(member.lastUpdated)}',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildPOIInfo() {
    final poi = selectedPOI!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _getPOIColor(poi.type), width: 2),
              ),
              child: Center(
                child: Text(
                  POI.getPoiIcon(poi.type),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    poi.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    poi.type.toString().split('.').last.replaceAllMapped(
                          RegExp(r'[A-Z]'),
                          (match) => ' ${match.group(0)}',
                        ).trim(),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                icon: Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: onClose,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
        if (poi.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            poi.description,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
        ],
        if (routeInfo.isNotEmpty) ...[
          const SizedBox(height: 8),
          Divider(color: AppColors.border),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.directions_walk,
                color: AppColors.textSecondary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: isLoadingRoute
                    ? Text(
                        'Calculating route...',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      )
                    : Text(
                        routeInfo,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  IconData _getRoleIcon(String? role) {
    switch (role) {
      case 'Volunteer':
        return Icons.local_hospital;
      case 'Organizer':
        return Icons.admin_panel_settings;
      case 'Attendee':
      default:
        return Icons.person_pin;
    }
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'Volunteer':
        return AppColors.mapVolunteer;
      case 'Organizer':
        return AppColors.mapOrganizer;
      case 'Attendee':
      default:
        return AppColors.mapAttendee;
    }
  }

  Color _getPOIColor(MarkerType type) {
    switch (type) {
      case MarkerType.emergency:
        return AppColors.mapEmergency;
      case MarkerType.medical:
        return Colors.red.shade700;
      case MarkerType.security:
        return Colors.blue.shade700;
      case MarkerType.drinkingWater:
        return Colors.blue.shade600;
      case MarkerType.restroom:
        return Colors.brown.shade600;
      case MarkerType.food:
        return Colors.orange.shade700;
      case MarkerType.historical:
        return Colors.purple.shade600;
      case MarkerType.accessibility:
        return Colors.green.shade600;
      case MarkerType.parking:
        return Colors.grey.shade700;
      default:
        return AppColors.primary;
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
      return '${difference.inDays}d ago';
    }
  }
}
