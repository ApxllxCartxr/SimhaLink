import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:simha_link/services/offline_map_service.dart';
import 'package:simha_link/config/app_colors.dart';

class OfflineMapManagerScreen extends StatefulWidget {
  const OfflineMapManagerScreen({super.key});

  @override
  State<OfflineMapManagerScreen> createState() => _OfflineMapManagerScreenState();
}

class _OfflineMapManagerScreenState extends State<OfflineMapManagerScreen> {
  Map<String, dynamic> _cacheStats = {};
  bool _isLoading = false;
  bool _isOnline = false;
  String _downloadStatus = '';
  int _downloadProgress = 0;
  int _downloadTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadCacheStats();
    _checkConnectivity();
  }

  Future<void> _loadCacheStats() async {
    final stats = await OfflineMapService.getCacheStats();
    setState(() {
      _cacheStats = stats;
    });
  }

  Future<void> _checkConnectivity() async {
    final isOnline = await OfflineMapService.isOnline();
    setState(() {
      _isOnline = isOnline;
    });
  }

  Future<void> _precacheEventArea() async {
    if (!_isOnline) {
      _showErrorSnackbar('Internet connection required to download maps');
      return;
    }

    setState(() {
      _isLoading = true;
      _downloadStatus = 'Starting download...';
      _downloadProgress = 0;
      _downloadTotal = 0;
    });

    try {
      // Default event location (can be customized)
      const eventCenter = LatLng(12.9716, 77.5946); // Bangalore coordinates
      
      await OfflineMapService.precacheEventArea(
        centerLocation: eventCenter,
        eventName: 'Current Event Area',
        radiusKm: 3.0,
        onProgress: (downloaded, total) {
          setState(() {
            _downloadProgress = downloaded;
            _downloadTotal = total;
            _downloadStatus = 'Downloaded $downloaded of $total tiles';
          });
        },
        onComplete: () {
          setState(() {
            _downloadStatus = 'Download complete!';
            _isLoading = false;
          });
          _loadCacheStats();
          _showSuccessSnackbar('Event area cached successfully');
        },
        onError: (error) {
          setState(() {
            _downloadStatus = 'Download failed: $error';
            _isLoading = false;
          });
          _showErrorSnackbar('Download failed: $error');
        },
      );
    } catch (e) {
      setState(() {
        _downloadStatus = 'Error: $e';
        _isLoading = false;
      });
      _showErrorSnackbar('Failed to cache area: $e');
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await _showConfirmationDialog(
      'Clear Offline Cache',
      'This will delete all cached map tiles. You will need to re-download them for offline use.',
    );

    if (confirmed) {
      await OfflineMapService.clearCache();
      await _loadCacheStats();
      _showSuccessSnackbar('Cache cleared successfully');
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<bool> _showConfirmationDialog(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Maps'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadCacheStats();
          await _checkConnectivity();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Connection Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _isOnline ? Icons.wifi : Icons.wifi_off,
                      color: _isOnline ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _isOnline ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),

            // Cache Statistics Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cache Statistics',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStatRow('Total Tiles', '${_cacheStats['totalTiles'] ?? 0}'),
                    _buildStatRow('Total Size', '${_cacheStats['totalSizeMB'] ?? 0} MB'),
                    _buildStatRow('Default Cache', '${_cacheStats['defaultCacheTiles'] ?? 0} tiles'),
                    _buildStatRow('Event Cache', '${_cacheStats['eventCacheTiles'] ?? 0} tiles'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Download Progress Card (shown during download)
            if (_isLoading || _downloadStatus.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Download Progress',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(_downloadStatus),
                      if (_downloadTotal > 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _downloadProgress / _downloadTotal,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${((_downloadProgress / _downloadTotal) * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Action Buttons
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _precacheEventArea,
              icon: const Icon(Icons.download),
              label: Text(_isLoading ? 'Downloading...' : 'Cache Event Area'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: _clearCache,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Clear Cache'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 24),

            // Information Card
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'About Offline Maps',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Cache event areas before the event for offline access\n'
                      '• Cached maps work without internet connection\n'
                      '• Reduces data usage and improves loading speed\n'
                      '• Event area covers 3km radius around the event location',
                      style: TextStyle(color: Colors.blue[700]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
