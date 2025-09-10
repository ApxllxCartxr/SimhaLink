import 'package:flutter/material.dart';
import '../../models/transport.dart';
import '../../models/transport_booking.dart';
import '../../models/user_profile.dart';
import '../../services/transport_booking_service.dart';
import '../map/transport_route_display_screen.dart';
import 'transport_booking_screen.dart';
import 'my_bookings_screen.dart';

class TransportDetailScreen extends StatefulWidget {
  final Transport transport;
  final UserProfile user;

  const TransportDetailScreen({
    super.key,
    required this.transport,
    required this.user,
  });

  @override
  State<TransportDetailScreen> createState() => _TransportDetailScreenState();
}

class _TransportDetailScreenState extends State<TransportDetailScreen> {
  bool _isLoading = false;
  bool _hasBooked = false;

  @override
  void initState() {
    super.initState();
    _checkIfUserBooked();
  }

  Future<void> _checkIfUserBooked() async {
    final hasBooked = await TransportBookingService.hasUserBookedTransport(
      widget.user.uid,
      widget.transport.id,
    );
    if (mounted) {
      setState(() {
        _hasBooked = hasBooked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.transport.title),
        actions: [
          if (widget.user.role == UserRole.organizer &&
              widget.transport.organizerId == widget.user.uid)
            IconButton(
              onPressed: _showManageOptions,
              icon: const Icon(Icons.settings),
              tooltip: 'Manage Transport',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderCard(),
            _buildRouteCard(),
            _buildScheduleCard(),
            _buildCapacityCard(),
            _buildPricingCard(),
            if (widget.transport.status == TransportStatus.active &&
                !_hasBooked &&
                widget.transport.capacity.availableSeats > 0)
              _buildBookingSection(),
            if (_hasBooked) _buildBookedSection(),
            const SizedBox(height: 100), // Space for FAB
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getTransportTypeColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getTransportTypeIcon(),
                    color: _getTransportTypeColor(),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.transport.title,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.transport.description,
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
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.person, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  'Organized by ${widget.transport.organizerName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Icon(
                  widget.transport.visibility == TransportVisibility.public
                      ? Icons.public
                      : Icons.group,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.transport.visibility == TransportVisibility.public
                      ? 'Public'
                      : 'Groups Only',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Route Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'From',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        widget.transport.route.fromAddress,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.flag, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'To',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        widget.transport.route.toAddress,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.straighten, color: Colors.grey.shade600, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Distance: ${widget.transport.route.distance.toStringAsFixed(1)} km',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showRoute,
                  icon: const Icon(Icons.map, size: 16),
                  label: const Text('View Route'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Schedule',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.schedule, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Departure',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        _formatDateTime(widget.transport.schedule.departureTime),
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _getTimeUntilDeparture(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.access_time, color: Colors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Estimated Arrival',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        _formatDateTime(widget.transport.schedule.estimatedArrival),
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapacityCard() {
    final capacity = widget.transport.capacity;
    final occupancyPercentage = capacity.currentOccupants / capacity.maxOccupants;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Capacity',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${capacity.currentOccupants} / ${capacity.maxOccupants} seats',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${capacity.availableSeats} seats available',
                        style: TextStyle(
                          color: capacity.availableSeats > 0 
                              ? Colors.green.shade600 
                              : Colors.red.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                CircularProgressIndicator(
                  value: occupancyPercentage,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    occupancyPercentage >= 1.0
                        ? Colors.red
                        : occupancyPercentage >= 0.8
                            ? Colors.orange
                            : Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: occupancyPercentage,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                occupancyPercentage >= 1.0
                    ? Colors.red
                    : occupancyPercentage >= 0.8
                        ? Colors.orange
                        : Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pricing',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.transport.pricing.isFree
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    widget.transport.pricing.isFree
                        ? Icons.money_off
                        : Icons.attach_money,
                    color: widget.transport.pricing.isFree
                        ? Colors.blue
                        : Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.transport.pricing.isFree ? 'Free' : 'Paid',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        widget.transport.pricing.isFree
                            ? 'No charge'
                            : '\$${widget.transport.pricing.pricePerTicket.toStringAsFixed(2)} per ticket',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Book Your Seat',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _bookTransport,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.confirmation_number),
            label: Text(_isLoading ? 'Booking...' : 'Book Now'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          if (!widget.transport.pricing.isFree) ...[
            const SizedBox(height: 8),
            Text(
              'You will be charged \$${widget.transport.pricing.pricePerTicket.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookedSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Booking Confirmed',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Text(
                  'You have already booked this transport',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _viewBooking,
            child: const Text('View Ticket'),
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

  Widget? _buildFloatingActionButton() {
    if (widget.user.role == UserRole.organizer &&
        widget.transport.organizerId == widget.user.uid) {
      return FloatingActionButton(
        onPressed: _showManageOptions,
        child: const Icon(Icons.settings),
      );
    }
    return null;
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

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);
    
    if (difference.inDays == 0) {
      return 'Today at ${_formatTime(dateTime)}';
    } else if (difference.inDays == 1) {
      return 'Tomorrow at ${_formatTime(dateTime)}';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${_formatTime(dateTime)}';
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getTimeUntilDeparture() {
    final now = DateTime.now();
    final difference = widget.transport.schedule.departureTime.difference(now);
    
    if (difference.inDays > 0) {
      return 'Departs in ${difference.inDays} day(s)';
    } else if (difference.inHours > 0) {
      return 'Departs in ${difference.inHours} hour(s)';
    } else if (difference.inMinutes > 0) {
      return 'Departs in ${difference.inMinutes} minute(s)';
    } else if (difference.inMinutes >= -30) {
      return 'Departing now';
    } else {
      return 'Departed';
    }
  }

  Future<void> _bookTransport() async {
    // Check for existing booking first
    final existingBooking = await TransportBookingService.getUserExistingBooking(
      widget.user.uid,
      widget.transport.id,
    );
    
    if (existingBooking != null) {
      _showExistingBookingDialog(existingBooking);
      return;
    }
    
    // Navigate to the detailed booking screen
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => TransportBookingScreen(
          transport: widget.transport,
          user: widget.user,
        ),
      ),
    );

    // If booking was successful, refresh the state
    if (result == true && mounted) {
      await _checkIfUserBooked();
    }
  }

  void _viewBooking() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('My Bookings screen coming soon!')),
    );
  }

  void _showRoute() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransportRouteDisplayScreen(
          transport: widget.transport,
        ),
      ),
    );
  }

  void _showManageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Manage Transport',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('View Bookings'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bookings management coming soon!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Transport'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Transport editing coming soon!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.red),
              title: const Text('Cancel Transport'),
              textColor: Colors.red,
              onTap: () {
                Navigator.pop(context);
                _showCancelConfirmation();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Transport'),
        content: const Text('Are you sure you want to cancel this transport? This action cannot be undone and all bookings will be cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Transport cancellation coming soon!')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel Transport'),
          ),
        ],
      ),
    );
  }

  void _showExistingBookingDialog(TransportBooking existingBooking) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Existing Booking Found'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You already have a confirmed booking for this transport:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Booking #${existingBooking.id.substring(0, 8).toUpperCase()}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('${existingBooking.groupBooking.totalTickets} tickets'),
                  Text('Booked on ${_formatDate(existingBooking.bookedAt)}'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MyBookingsScreen(
                    user: widget.user,
                    initialBookingId: existingBooking.id,
                  ),
                ),
              );
            },
            child: const Text('Manage Booking'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}
