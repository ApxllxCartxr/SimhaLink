import 'package:flutter/material.dart';
import 'package:simha_link/models/poi.dart';
import 'package:simha_link/services/marker_permission_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Widget that shows marker actions when a marker is selected for management
class MarkerActionBottomSheet extends StatelessWidget {
  final POI poi;
  final String userRole;
  final VoidCallback onClose;
  final VoidCallback? onMarkerUpdated;

  const MarkerActionBottomSheet({
    super.key,
    required this.poi,
    required this.userRole,
    required this.onClose,
    this.onMarkerUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final availableActions = MarkerPermissionService.getAvailableActions(
      userRole: userRole,
      markerId: poi.id,
      createdBy: poi.createdBy,
      markerType: poi.type,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(poi.type.iconData, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poi.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      poi.type.displayName,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
          
          if (poi.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              poi.description,
              style: const TextStyle(fontSize: 14),
            ),
          ],
          
          const SizedBox(height: 20),
          
          // Action buttons
          ...availableActions.map((action) => _buildActionTile(context, action)),
          
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildActionTile(BuildContext context, MarkerAction action) {
    return ListTile(
      leading: Icon(action.icon, color: action.color),
      title: Text(
        action.displayName,
        style: TextStyle(color: action.color),
      ),
      onTap: () => _handleAction(context, action),
      contentPadding: EdgeInsets.zero,
    );
  }

  void _handleAction(BuildContext context, MarkerAction action) {
    switch (action) {
      case MarkerAction.view:
        _showMarkerDetails(context);
        break;
      case MarkerAction.edit:
        _editMarker(context);
        break;
      case MarkerAction.delete:
        _deleteMarker(context);
        break;
      case MarkerAction.duplicate:
        _duplicateMarker(context);
        break;
      case MarkerAction.share:
        _shareMarker(context);
        break;
    }
  }

  void _showMarkerDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(poi.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Type', poi.type.displayName),
            _buildDetailRow('Location', '${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}'),
            if (poi.description.isNotEmpty)
              _buildDetailRow('Description', poi.description),
            _buildDetailRow('Created', _formatDate(poi.createdAt)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _editMarker(BuildContext context) {
    // For now, close the bottom sheet
    // In a full implementation, this would open an edit dialog
    onClose();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit functionality coming soon')),
    );
  }

  void _deleteMarker(BuildContext context) {
    final confirmationMessage = MarkerPermissionService.getDeletionConfirmationMessage(
      poi.type,
      poi.name,
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Marker'),
        content: Text(confirmationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _performDelete(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _performDelete(BuildContext context) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Deleting marker...'),
            ],
          ),
        ),
      );

      // Delete from Firestore
      await FirebaseFirestore.instance
          .collection('pois')
          .doc(poi.id)
          .delete();

      // Close loading dialog
      if (context.mounted) Navigator.pop(context);
      
      // Close action sheet
      onClose();
      
      // Show success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${poi.name} deleted successfully')),
        );
      }
      
      // Notify parent to refresh
      onMarkerUpdated?.call();
      
    } catch (e) {
      // Close loading dialog if still open
      if (context.mounted) Navigator.pop(context);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting marker: $e')),
        );
      }
    }
  }

  void _duplicateMarker(BuildContext context) {
    onClose();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Duplicate functionality coming soon')),
    );
  }

  void _shareMarker(BuildContext context) {
    onClose();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share functionality coming soon')),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
