import 'package:flutter/material.dart';
import 'package:simha_link/config/app_colors.dart';

/// Legend widget showing marker meanings based on user role
class MapLegend extends StatelessWidget {
  final String? userRole;

  const MapLegend({
    super.key,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 16,
      left: 16,
      child: Card(
        color: AppColors.mapLegendBackground,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: _buildLegendItems(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLegendItems() {
    List<Widget> items = [
      Text(
        'Map Legend',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 8),
      _buildLegendItem(
        Icons.my_location,
        'Your location',
        AppColors.mapCurrentUser,
      ),
    ];

    // Add role-specific legend items
    if (userRole == 'Attendee') {
      items.addAll([
        _buildLegendItem(
          Icons.person_pin,
          'Group members',
          AppColors.mapAttendee,
        ),
      ]);
    } else if (userRole == 'Volunteer') {
      items.addAll([
        _buildLegendItem(
          Icons.local_hospital,
          'Volunteers',
          AppColors.mapVolunteer,
        ),
        _buildLegendItem(
          Icons.admin_panel_settings,
          'Organizers',
          AppColors.mapOrganizer,
        ),
        _buildLegendItem(
          Icons.emergency,
          'Emergencies',
          AppColors.mapEmergency,
        ),
      ]);
    } else if (userRole == 'Organizer') {
      items.addAll([
        _buildLegendItem(
          Icons.local_hospital,
          'Volunteers',
          AppColors.mapVolunteer,
        ),
        _buildLegendItem(
          Icons.admin_panel_settings,
          'Organizers',
          AppColors.mapOrganizer,
        ),
      ]);
    }

    // Add POI legend
    items.addAll([
      const SizedBox(height: 4),
      Text(
        'Points of Interest',
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          fontSize: 10,
        ),
      ),
      const SizedBox(height: 4),
      _buildPOILegendItem('🚰', 'Water', Colors.blue.shade600),
      _buildPOILegendItem('🚻', 'Restroom', Colors.brown.shade600),
      if (userRole == 'Volunteer' || userRole == 'Organizer')
        _buildPOILegendItem('🏥', 'Medical', Colors.red.shade700),
    ]);

    return items;
  }

  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPOILegendItem(String emoji, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: color, width: 1.5),
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 8),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
