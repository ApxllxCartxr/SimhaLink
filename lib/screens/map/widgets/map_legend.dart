import 'package:flutter/material.dart';
import 'package:simha_link/config/app_colors.dart';

/// Legend widget showing marker meanings based on user role
/// Now with collapsible functionality positioned at bottom left
class MapLegend extends StatefulWidget {
  final String? userRole;

  const MapLegend({
    super.key,
    required this.userRole,
  });

  @override
  State<MapLegend> createState() => _MapLegendState();
}

class _MapLegendState extends State<MapLegend> with TickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: const Offset(0, 0)).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 100, // Position above navigation bar (adjust as needed)
      left: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapsible legend content
          SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _isExpanded ? _buildLegendCard() : const SizedBox.shrink(),
            ),
          ),
          // Toggle button
          const SizedBox(height: 8),
          _buildToggleButton(),
        ],
      ),
    );
  }

  Widget _buildToggleButton() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.mapLegendBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _toggleExpanded,
          child: Center(
            child: AnimatedRotation(
              turns: _isExpanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Icon(
                _isExpanded ? Icons.keyboard_arrow_down : Icons.info_outline,
                color: AppColors.textPrimary,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendCard() {
    return Card(
      color: AppColors.mapLegendBackground,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 200,
          maxHeight: 300,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: _buildLegendItems(),
            ),
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
    if (widget.userRole == 'Attendee') {
      items.addAll([
        _buildLegendItem(
          Icons.person_pin,
          'Group members',
          AppColors.mapAttendee,
        ),
      ]);
    } else if (widget.userRole == 'Volunteer') {
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
    } else if (widget.userRole == 'Organizer') {
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
      if (widget.userRole == 'Volunteer' || widget.userRole == 'Organizer')
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
