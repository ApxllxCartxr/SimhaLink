import 'package:flutter/material.dart';
import 'package:simha_link/services/state_sync_service.dart';
import 'package:simha_link/utils/user_preferences.dart';

/// Debug widget to show current state synchronization status
class StateSyncStatusWidget extends StatefulWidget {
  const StateSyncStatusWidget({super.key});

  @override
  State<StateSyncStatusWidget> createState() => _StateSyncStatusWidgetState();
}

class _StateSyncStatusWidgetState extends State<StateSyncStatusWidget> {
  Map<String, dynamic>? _syncStatus;
  String? _localGroupId;
  bool _isValidating = false;
  bool? _isConsistent;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final syncStatus = StateSyncService.getSyncStatus();
    final localGroupId = await UserPreferences.getUserGroupId();
    
    setState(() {
      _syncStatus = syncStatus;
      _localGroupId = localGroupId;
    });
  }

  Future<void> _validateConsistency() async {
    setState(() {
      _isValidating = true;
    });

    try {
      final isConsistent = await StateSyncService.validateStateConsistency();
      setState(() {
        _isConsistent = isConsistent;
      });
    } finally {
      setState(() {
        _isValidating = false;
      });
    }
  }

  Future<void> _forceSync() async {
    await StateSyncService.forceSyncState();
    await _refreshStatus();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ State sync completed'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.sync, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'State Sync Status',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: _refreshStatus,
                  tooltip: 'Refresh Status',
                ),
              ],
            ),
            const Divider(height: 16),
            
            // Local State
            _buildStatusRow(
              'Local Group ID',
              _localGroupId ?? 'None',
              _localGroupId != null ? Colors.green : Colors.orange,
            ),
            
            // Sync Status
            if (_syncStatus != null) ...[
              _buildStatusRow(
                'User Syncing',
                _syncStatus!['userDocSyncing']?.toString() ?? 'false',
                _syncStatus!['userDocSyncing'] == true ? Colors.green : Colors.red,
              ),
              _buildStatusRow(
                'Group Syncing',
                _syncStatus!['groupDocSyncing']?.toString() ?? 'false',
                _syncStatus!['groupDocSyncing'] == true ? Colors.green : Colors.red,
              ),
              _buildStatusRow(
                'Sync User ID',
                _syncStatus!['userId']?.toString() ?? 'None',
                _syncStatus!['userId'] != null ? Colors.green : Colors.orange,
              ),
              _buildStatusRow(
                'Sync Group ID',
                _syncStatus!['groupId']?.toString() ?? 'None',
                _syncStatus!['groupId'] != null ? Colors.green : Colors.orange,
              ),
            ],
            
            // Consistency Check
            if (_isConsistent != null)
              _buildStatusRow(
                'State Consistent',
                _isConsistent! ? 'Yes' : 'No',
                _isConsistent! ? Colors.green : Colors.red,
              ),
            
            const SizedBox(height: 12),
            
            // Action Buttons
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isValidating ? null : _validateConsistency,
                  icon: _isValidating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle, size: 16),
                  label: Text(_isValidating ? 'Validating...' : 'Validate'),
                ),
                ElevatedButton.icon(
                  onPressed: _forceSync,
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Force Sync'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
