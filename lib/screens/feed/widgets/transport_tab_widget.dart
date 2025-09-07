import 'package:flutter/material.dart';
import '../../../models/transport.dart';
import '../../../models/transport_booking.dart';
import '../../../models/user_profile.dart';
import '../../../services/transport_service.dart';
import '../../../services/transport_booking_service.dart';
import '../../transport/transport_create_screen.dart';
import '../../transport/transport_detail_screen.dart';
import '../../transport/transport_booking_screen.dart';
import '../../transport/my_bookings_screen.dart';

class TransportTabWidget extends StatefulWidget {
  final UserProfile user;

  const TransportTabWidget({
    super.key,
    required this.user,
  });

  @override
  State<TransportTabWidget> createState() => _TransportTabWidgetState();
}

class _TransportTabWidgetState extends State<TransportTabWidget> {
  String _searchQuery = '';
  bool _showMyBookings = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildSearchAndFilter(),
        Expanded(
          child: _showMyBookings
              ? _buildMyBookingsView()
              : _buildAvailableTransportsView(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.directions_bus,
            color: Theme.of(context).primaryColor,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transport Hub',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                Text(
                  _getSubtitle(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (_canCreateTransport())
            IconButton(
              onPressed: _navigateToCreateTransport,
              icon: const Icon(Icons.add_circle),
              tooltip: 'Create Transport',
            ),
        ],
      ),
    );
  }

  String _getSubtitle() {
    if (_showMyBookings) {
      return 'Your booked transports';
    }
    
    switch (widget.user.role) {
      case UserRole.organizer:
        return 'Manage transport options for attendees';
      case UserRole.volunteer:
        return 'Help attendees with transport';
      case UserRole.participant:
        return 'Book transport to the event';
      default:
        return 'Available transport options';
    }
  }

  bool _canCreateTransport() {
    return widget.user.role == UserRole.organizer;
  }

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search transport options...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Available'),
                      icon: Icon(Icons.directions_bus),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('My Bookings'),
                      icon: Icon(Icons.confirmation_number),
                    ),
                  ],
                  selected: {_showMyBookings},
                  onSelectionChanged: (Set<bool> selected) {
                    setState(() {
                      _showMyBookings = selected.first;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableTransportsView() {
    return StreamBuilder<List<Transport>>(
      stream: TransportService.getAvailableTransports(userProfile: widget.user),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('Error loading transports: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        List<Transport> transports = snapshot.data!;
        
        // Filter by search query
        if (_searchQuery.isNotEmpty) {
          transports = transports.where((transport) =>
              transport.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              transport.description.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
        }

        if (transports.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.directions_bus_outlined,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'No transports found for "$_searchQuery"'
                      : _getEmptyStateMessage(),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_canCreateTransport() && _searchQuery.isEmpty) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _navigateToCreateTransport,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Transport'),
                  ),
                ],
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: transports.length,
            itemBuilder: (context, index) {
              return _buildTransportCard(transports[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildMyBookingsView() {
    return StreamBuilder<List<TransportBooking>>(
      stream: TransportBookingService.getUserBookings(widget.user.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('Error loading bookings: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final bookings = snapshot.data!;

        if (bookings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.confirmation_number_outlined,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No bookings yet',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Book a transport to see your tickets here',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() => _showMyBookings = false),
                  child: const Text('Browse Transports'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: bookings.length,
            itemBuilder: (context, index) {
              return _buildBookingCard(bookings[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildTransportCard(Transport transport) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToTransportDetail(transport),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getTransportTypeColor(transport.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getTransportTypeIcon(transport.type),
                      color: _getTransportTypeColor(transport.type),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transport.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          transport.description,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(transport.status),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(transport.schedule.departureTime),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.people, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${transport.capacity.availableSeats} seats left',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (!transport.pricing.isFree)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '\$${transport.pricing.pricePerTicket.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'FREE',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _navigateToTransportDetail(transport),
                      icon: const Icon(Icons.info_outline, size: 16),
                      label: const Text('Details'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: transport.capacity.availableSeats > 0 
                          ? () => _navigateToBooking(transport)
                          : null,
                      icon: const Icon(Icons.confirmation_number, size: 16),
                      label: Text(transport.capacity.availableSeats > 0 
                          ? 'Book Now' 
                          : 'Sold Out'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: transport.capacity.availableSeats > 0 
                            ? Colors.green 
                            : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookingCard(TransportBooking booking) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToBookingDetail(booking),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getBookingStatusColor(booking.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getBookingStatusIcon(booking.status),
                      color: _getBookingStatusColor(booking.status),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Booking #${booking.id.substring(0, 8)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${booking.groupBooking.totalTickets} ticket(s)',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildBookingStatusChip(booking.status),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.confirmation_number, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Booked on ${_formatDate(booking.bookedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (booking.bookingDetails.totalAmount > 0)
                    Text(
                      '\$${booking.bookingDetails.totalAmount.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    Text(
                      'FREE',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(TransportStatus status) {
    Color color;
    String text;
    
    switch (status) {
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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBookingStatusChip(BookingStatus status) {
    Color color;
    String text;
    
    switch (status) {
      case BookingStatus.confirmed:
        color = Colors.green;
        text = 'Confirmed';
        break;
      case BookingStatus.cancelled:
        color = Colors.red;
        text = 'Cancelled';
        break;
      case BookingStatus.completed:
        color = Colors.blue;
        text = 'Completed';
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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getTransportTypeColor(TransportType type) {
    switch (type) {
      case TransportType.bus:
        return Colors.blue;
      case TransportType.shuttle:
        return Colors.green;
    }
  }

  IconData _getTransportTypeIcon(TransportType type) {
    switch (type) {
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

  IconData _getBookingStatusIcon(BookingStatus status) {
    switch (status) {
      case BookingStatus.confirmed:
        return Icons.check_circle;
      case BookingStatus.cancelled:
        return Icons.cancel;
      case BookingStatus.completed:
        return Icons.verified;
    }
  }

  String _getEmptyStateMessage() {
    switch (widget.user.role) {
      case UserRole.organizer:
        return 'No transport options created yet.\nCreate the first transport for attendees.';
      case UserRole.volunteer:
        return 'No transport options available.\nCheck back later or contact organizers.';
      case UserRole.participant:
        return 'No transport options available yet.\nCheck back later for updates.';
      default:
        return 'No transport options available.';
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  void _navigateToCreateTransport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TransportCreateScreen(user: widget.user),
      ),
    );
  }

  void _navigateToTransportDetail(Transport transport) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TransportDetailScreen(
          transport: transport,
          user: widget.user,
        ),
      ),
    );
  }

  void _navigateToBookingDetail(TransportBooking booking) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MyBookingsScreen(
          user: widget.user,
          initialBookingId: booking.id,
        ),
      ),
    );
  }

  void _navigateToBooking(Transport transport) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TransportBookingScreen(
          transport: transport,
          user: widget.user,
        ),
      ),
    );
  }
}
