import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../models/transport.dart';
import '../../models/transport_booking.dart';
import '../../models/user_profile.dart';
import '../../services/transport_booking_service.dart';
import '../../core/utils/app_logger.dart';

class TransportRouteDisplayScreen extends StatefulWidget {
  final Transport transport;
  final UserProfile? currentUser;
  final bool showBookedPassengers;

  const TransportRouteDisplayScreen({
    super.key,
    required this.transport,
    this.currentUser,
    this.showBookedPassengers = true,
  });

  @override
  State<TransportRouteDisplayScreen> createState() => _TransportRouteDisplayScreenState();
}

class _TransportRouteDisplayScreenState extends State<TransportRouteDisplayScreen> {
  final MapController _mapController = MapController();
  List<TransportBooking> _bookings = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _showRouteDetails = true;
  bool _showPassengerMarkers = true;

  @override
  void initState() {
    super.initState();
    if (widget.showBookedPassengers) {
      _loadBookings();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadBookings() async {
    try {
      // Get bookings for this transport
      final bookingsStream = TransportBookingService.getTransportBookings(widget.transport.id);
      final bookings = await bookingsStream.first;
      
      if (mounted) {
        setState(() {
          _bookings = bookings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading passenger data: $e';
          _isLoading = false;
        });
      }
      AppLogger.logError('Error loading transport bookings', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.transport.title),
        actions: [
          IconButton(
            onPressed: _showMapOptions,
            icon: const Icon(Icons.layers),
            tooltip: 'Map Options',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTransportInfo(),
          Expanded(child: _buildMap()),
          if (widget.showBookedPassengers) _buildPassengerInfo(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fitMapToRoute,
        child: const Icon(Icons.center_focus_strong),
        tooltip: 'Center Route',
      ),
    );
  }

  Widget _buildTransportInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getTransportTypeColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getTransportTypeIcon(),
                  color: _getTransportTypeColor(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.transport.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _formatDepartureTime(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusChip(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.route, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                '${widget.transport.route.distance.toStringAsFixed(1)} km',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              Icon(Icons.people, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                '${widget.transport.capacity.currentOccupants}/${widget.transport.capacity.maxOccupants} seats',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadBookings,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.transport.route.fromLocation,
        initialZoom: 13.0,
        maxZoom: 18.0,
        minZoom: 3.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.simha_link',
        ),
        // Route polyline
        if (_showRouteDetails)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.transport.route.routePath,
                strokeWidth: 6.0,
                color: _getTransportTypeColor(),
                borderStrokeWidth: 2.0,
                borderColor: Colors.white,
              ),
            ],
          ),
        // Markers
        MarkerLayer(
          markers: [
            // Start location marker
            Marker(
              point: widget.transport.route.fromLocation,
              width: 50,
              height: 50,
              child: _buildLocationMarker(
                icon: Icons.location_on,
                color: Colors.green,
                label: 'START',
              ),
            ),
            // End location marker
            Marker(
              point: widget.transport.route.toLocation,
              width: 50,
              height: 50,
              child: _buildLocationMarker(
                icon: Icons.flag,
                color: Colors.red,
                label: 'END',
              ),
            ),
            // Passenger markers (if enabled and available)
            if (_showPassengerMarkers && widget.showBookedPassengers)
              ..._buildPassengerMarkers(),
          ],
        ),
      ],
    );
  }

  Widget _buildLocationMarker({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  List<Marker> _buildPassengerMarkers() {
    final markers = <Marker>[];
    
    // Create markers for booked passengers
    // For demonstration, we'll distribute them along the route
    final totalPassengers = _bookings.fold<int>(
      0,
      (sum, booking) => sum + booking.groupBooking.totalTickets,
    );

    if (totalPassengers > 0) {
      // Create passenger cluster marker at start location
      markers.add(
        Marker(
          point: widget.transport.route.fromLocation,
          width: 60,
          height: 60,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.groups,
                  color: Colors.white,
                  size: 20,
                ),
                Text(
                  '$totalPassengers',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildPassengerInfo() {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final totalPassengers = _bookings.fold<int>(
      0,
      (sum, booking) => sum + booking.groupBooking.totalTickets,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'Booked Passengers',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$totalPassengers passengers',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (_bookings.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'No passengers booked yet',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ] else ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _bookings.length,
                itemBuilder: (context, index) {
                  return _buildBookingCard(_bookings[index]);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookingCard(TransportBooking booking) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            booking.bookerName,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${booking.groupBooking.totalTickets} ticket(s)',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: _getBookingStatusColor(booking.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _getBookingStatusText(booking.status),
              style: TextStyle(
                fontSize: 8,
                color: _getBookingStatusColor(booking.status),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    Color color;
    String text;
    
    switch (widget.transport.status) {
      case TransportStatus.active:
        color = Colors.green;
        text = 'Active';
        break;
      case TransportStatus.full:
        color = Colors.orange;
        text = 'Full';
        break;
      case TransportStatus.cancelled:
        color = Colors.red;
        text = 'Cancelled';
        break;
      case TransportStatus.departed:
        color = Colors.blue;
        text = 'Departed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _getTransportTypeColor() {
    switch (widget.transport.type) {
      case TransportType.bus:
        return Colors.blue;
      case TransportType.shuttle:
        return Colors.green;
    }
  }

  IconData _getTransportTypeIcon() {
    switch (widget.transport.type) {
      case TransportType.bus:
        return Icons.directions_bus;
      case TransportType.shuttle:
        return Icons.airport_shuttle;
    }
  }

  Color _getBookingStatusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.confirmed:
        return Colors.green;
      case BookingStatus.cancelled:
        return Colors.red;
      case BookingStatus.completed:
        return Colors.blue;
    }
  }

  String _getBookingStatusText(BookingStatus status) {
    switch (status) {
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.completed:
        return 'Completed';
    }
  }

  String _formatDepartureTime() {
    final departureTime = widget.transport.schedule.departureTime;
    final now = DateTime.now();
    final difference = departureTime.difference(now);
    
    if (difference.inDays == 0) {
      return 'Today at ${_formatTime(departureTime)}';
    } else if (difference.inDays == 1) {
      return 'Tomorrow at ${_formatTime(departureTime)}';
    } else {
      return '${departureTime.day}/${departureTime.month} at ${_formatTime(departureTime)}';
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _fitMapToRoute() {
    final bounds = LatLngBounds.fromPoints([
      widget.transport.route.fromLocation,
      widget.transport.route.toLocation,
    ]);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  void _showMapOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Map Options',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Show Route'),
              subtitle: const Text('Display transport route on map'),
              value: _showRouteDetails,
              onChanged: (value) {
                setState(() {
                  _showRouteDetails = value;
                });
                Navigator.pop(context);
              },
            ),
            if (widget.showBookedPassengers)
              SwitchListTile(
                title: const Text('Show Passengers'),
                subtitle: const Text('Display booked passenger markers'),
                value: _showPassengerMarkers,
                onChanged: (value) {
                  setState(() {
                    _showPassengerMarkers = value;
                  });
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}
