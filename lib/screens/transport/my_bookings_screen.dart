import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/transport_booking.dart';
import '../../models/user_profile.dart';
import '../../services/transport_booking_service.dart';

class MyBookingsScreen extends StatefulWidget {
  final UserProfile user;
  final String? initialBookingId;

  const MyBookingsScreen({
    super.key,
    required this.user,
    this.initialBookingId,
  });

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  String _searchQuery = '';
  BookingStatus? _filterStatus;
  String _sortBy = 'date'; // 'date', 'status', 'amount'
  bool _sortAscending = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _showFilterOptions,
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter & Sort',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndFilters(),
          Expanded(
            child: StreamBuilder<List<TransportBooking>>(
              stream: TransportBookingService.getUserBookings(widget.user.uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                List<TransportBooking> bookings = snapshot.data!;
                
                // Apply filters and search
                bookings = _applyFiltersAndSearch(bookings);

                if (bookings.isEmpty) {
                  return _buildEmptyState();
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: bookings.length,
                    itemBuilder: (context, index) {
                      return _buildEnhancedBookingCard(bookings[index]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search bookings...',
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
          if (_filterStatus != null || _searchQuery.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildActiveFilters(),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveFilters() {
    return Row(
      children: [
        if (_searchQuery.isNotEmpty)
          Chip(
            label: Text('Search: "$_searchQuery"'),
            onDeleted: () => setState(() => _searchQuery = ''),
            deleteIcon: const Icon(Icons.close, size: 18),
          ),
        if (_filterStatus != null) ...[
          if (_searchQuery.isNotEmpty) const SizedBox(width: 8),
          Chip(
            label: Text('Status: ${_getStatusText(_filterStatus!)}'),
            onDeleted: () => setState(() => _filterStatus = null),
            deleteIcon: const Icon(Icons.close, size: 18),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(
            'Error loading bookings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => setState(() {}),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilters = _searchQuery.isNotEmpty || _filterStatus != null;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilters ? Icons.search_off : Icons.confirmation_number_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            hasFilters ? 'No bookings found' : 'No bookings yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilters 
                ? 'Try adjusting your search or filters'
                : 'Book a transport to see your tickets here',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: hasFilters 
                ? _clearAllFilters
                : () => Navigator.of(context).pop(),
            icon: Icon(hasFilters ? Icons.clear : Icons.directions_bus),
            label: Text(hasFilters ? 'Clear Filters' : 'Browse Transports'),
          ),
        ],
      ),
    );
  }

  List<TransportBooking> _applyFiltersAndSearch(List<TransportBooking> bookings) {
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      bookings = bookings.where((booking) {
        final query = _searchQuery.toLowerCase();
        return booking.id.toLowerCase().contains(query) ||
               booking.bookerName.toLowerCase().contains(query) ||
               booking.groupBooking.passengers.any((p) => 
                   p.name.toLowerCase().contains(query));
      }).toList();
    }

    // Apply status filter
    if (_filterStatus != null) {
      bookings = bookings.where((b) => b.status == _filterStatus).toList();
    }

    // Apply sorting
    bookings.sort((a, b) {
      int comparison = 0;
      
      switch (_sortBy) {
        case 'date':
          comparison = a.bookedAt.compareTo(b.bookedAt);
          break;
        case 'status':
          comparison = a.status.index.compareTo(b.status.index);
          break;
        case 'amount':
          comparison = a.bookingDetails.totalAmount.compareTo(b.bookingDetails.totalAmount);
          break;
      }
      
      return _sortAscending ? comparison : -comparison;
    });

    return bookings;
  }

  void _clearAllFilters() {
    setState(() {
      _searchQuery = '';
      _filterStatus = null;
    });
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filter & Sort Options',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            Text(
              'Filter by Status',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filterStatus == null,
                  onSelected: (_) => setState(() => _filterStatus = null),
                ),
                ...BookingStatus.values.map((status) => FilterChip(
                  label: Text(_getStatusText(status)),
                  selected: _filterStatus == status,
                  onSelected: (_) => setState(() => _filterStatus = status),
                )),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Text(
              'Sort by',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _sortBy,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'date', child: Text('Date')),
                      DropdownMenuItem(value: 'status', child: Text('Status')),
                      DropdownMenuItem(value: 'amount', child: Text('Amount')),
                    ],
                    onChanged: (value) => setState(() => _sortBy = value!),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: () => setState(() => _sortAscending = !_sortAscending),
                  icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                  tooltip: _sortAscending ? 'Ascending' : 'Descending',
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedBookingCard(TransportBooking booking) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: InkWell(
        onTap: () => _showBookingDetails(booking),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getStatusColor(booking.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getStatusIcon(booking.status),
                      color: _getStatusColor(booking.status),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Booking #${booking.id.substring(0, 8).toUpperCase()}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${booking.groupBooking.totalTickets} ${booking.groupBooking.totalTickets == 1 ? 'ticket' : 'tickets'}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(booking.status),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Booking Info Row
              Row(
                children: [
                  Icon(Icons.event, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Booked on ${_formatDate(booking.bookedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  _buildAmountChip(booking.bookingDetails.totalAmount),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Passengers Preview
              if (booking.groupBooking.passengers.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.people, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          booking.groupBooking.passengers.take(2)
                              .map((p) => p.name)
                              .join(', ') +
                              (booking.groupBooking.passengers.length > 2 
                                  ? ' +${booking.groupBooking.passengers.length - 2} more'
                                  : ''),
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              // Action Buttons
              if (booking.status == BookingStatus.confirmed) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showQRTicket(booking),
                        icon: const Icon(Icons.qr_code, size: 18),
                        label: const Text('Show QR'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _shareBooking(booking),
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Share'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    if (booking.canCancel) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _cancelBooking(booking),
                          icon: const Icon(Icons.cancel, size: 18),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ] else if (booking.status == BookingStatus.cancelled) ...[
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline, color: Colors.red.shade700, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'This booking was cancelled',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (booking.status == BookingStatus.completed) ...[
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.verified, color: Colors.blue.shade700, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Journey completed',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountChip(double amount) {
    if (amount <= 0) {
      return Container(
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
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '\$${amount.toStringAsFixed(2)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.green.shade700,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatusChip(BookingStatus status) {
    Color color = _getStatusColor(status);
    String text = _getStatusText(status);

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

  Color _getStatusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.confirmed:
        return Colors.green;
      case BookingStatus.cancelled:
        return Colors.red;
      case BookingStatus.completed:
        return Colors.blue;
    }
  }

  String _getStatusText(BookingStatus status) {
    switch (status) {
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.completed:
        return 'Completed';
    }
  }

  IconData _getStatusIcon(BookingStatus status) {
    switch (status) {
      case BookingStatus.confirmed:
        return Icons.check_circle;
      case BookingStatus.cancelled:
        return Icons.cancel;
      case BookingStatus.completed:
        return Icons.verified;
    }
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  void _showBookingDetails(TransportBooking booking) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Booking Details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Status Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _getStatusColor(booking.status).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getStatusIcon(booking.status),
                                color: _getStatusColor(booking.status),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getStatusText(booking.status),
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Booking #${booking.id.substring(0, 8).toUpperCase()}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Booking Information
                    Text(
                      'Booking Information',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildDetailRow('Booking ID', '#${booking.id.substring(0, 8).toUpperCase()}'),
                            _buildDetailRow('Status', _getStatusText(booking.status)),
                            _buildDetailRow('Total Tickets', '${booking.groupBooking.totalTickets}'),
                            _buildDetailRow('Total Amount', 
                                booking.bookingDetails.totalAmount > 0 
                                    ? '\$${booking.bookingDetails.totalAmount.toStringAsFixed(2)}'
                                    : 'FREE'),
                            _buildDetailRow('Booked On', _formatDateTime(booking.bookedAt)),
                            _buildDetailRow('Booked By', booking.bookerName),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Passengers
                    if (booking.groupBooking.passengers.isNotEmpty) ...[
                      Text(
                        'Passengers (${booking.groupBooking.passengers.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: booking.groupBooking.passengers
                                .map((passenger) => _buildEnhancedPassengerRow(passenger))
                                .toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // Quick Actions
                    Text(
                      'Quick Actions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            if (booking.status == BookingStatus.confirmed) ...[
                              ListTile(
                                leading: const Icon(Icons.qr_code),
                                title: const Text('Show QR Code'),
                                subtitle: const Text('Display boarding pass'),
                                onTap: () {
                                  Navigator.pop(context);
                                  _showQRTicket(booking);
                                },
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.swap_horiz, color: Colors.purple),
                                title: const Text('Transfer Tickets'),
                                subtitle: const Text('Transfer to group members'),
                                onTap: () {
                                  Navigator.pop(context);
                                  _showTransferOptions(booking);
                                },
                              ),
                              const Divider(height: 1),
                            ],
                            ListTile(
                              leading: const Icon(Icons.share),
                              title: const Text('Share Booking'),
                              subtitle: const Text('Copy details to clipboard'),
                              onTap: () {
                                Navigator.pop(context);
                                _shareBooking(booking);
                              },
                            ),
                            if (booking.canCancel) ...[
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.cancel, color: Colors.red),
                                title: const Text('Cancel Booking'),
                                subtitle: const Text('Cancel this booking'),
                                onTap: () {
                                  Navigator.pop(context);
                                  _cancelBooking(booking);
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancedPassengerRow(PassengerInfo passenger) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.person,
              size: 16,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passenger.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (passenger.email?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    passenger.email!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Text(
              '#${passenger.ticketId.substring(0, 6)}',
              style: TextStyle(
                fontSize: 10,
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${_formatDate(dateTime)} at ${_formatTime(dateTime)}';
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showQRTicket(TransportBooking booking) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'QR Ticket',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // QR Code Display
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: QrImageView(
                  data: booking.bookingDetails.qrCode,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Booking Details
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      'Booking #${booking.id.substring(0, 8).toUpperCase()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${booking.groupBooking.totalTickets} ${booking.groupBooking.totalTickets == 1 ? 'ticket' : 'tickets'}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Booked by: ${booking.bookerName}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Instructions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Show this QR code to the driver when boarding',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareBooking(booking),
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
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

  void _shareBooking(TransportBooking booking) {
    final shareText = '''
🎫 Transport Booking Details

📱 Booking ID: ${booking.id.substring(0, 8).toUpperCase()}
👥 Passengers: ${booking.groupBooking.totalTickets}
📅 Booked on: ${_formatDate(booking.bookedAt)}
💰 Amount: ${booking.bookingDetails.totalAmount > 0 ? '\$${booking.bookingDetails.totalAmount.toStringAsFixed(2)}' : 'FREE'}
📍 Status: ${_getStatusText(booking.status)}

Passengers:
${booking.groupBooking.passengers.map((p) => '• ${p.name}').join('\n')}

Generated by SimhaLink Transport Hub
    ''';

    Clipboard.setData(ClipboardData(text: shareText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Booking details copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _cancelBooking(TransportBooking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: Text(
          'Are you sure you want to cancel this booking? '
          '${booking.bookingDetails.totalAmount > 0 ? 'You may be charged a cancellation fee.' : ''}'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Booking'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await TransportBookingService.cancelBooking(booking.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Booking cancelled successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error cancelling booking: $e')),
          );
        }
      }
    }
  }

  void _showTransferOptions(TransportBooking booking) async {
    try {
      // Get current user's group ID
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      
      if (!userDoc.exists) {
        _showErrorDialog('User profile not found');
        return;
      }
      
      final userData = userDoc.data()!;
      final groupId = userData['groupId'] as String?;
      
      if (groupId == null) {
        _showErrorDialog('You must be in a group to transfer tickets');
        return;
      }
      
      // Get group members for transfer
      final groupMembers = await TransportBookingService.getGroupMembersForTransfer(
        currentUserId: currentUser.uid,
        groupId: groupId,
      );
      
      if (groupMembers.isEmpty) {
        _showErrorDialog('No other group members available for transfer');
        return;
      }
      
      if (!mounted) return;
      
      // Show transfer selection dialog
      _showTicketTransferDialog(booking, groupMembers);
      
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Error loading group members: ${e.toString()}');
      }
    }
  }

  void _showTicketTransferDialog(TransportBooking booking, List<Map<String, dynamic>> groupMembers) {
    String? selectedTicketId;
    String? selectedMemberId;
    final noteController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Transfer Ticket'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Group info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You can only transfer tickets to members of your group',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Select ticket
                const Text(
                  'Select Ticket to Transfer',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: booking.groupBooking.passengers.map((passenger) {
                      final isSelected = selectedTicketId == passenger.ticketId;
                      final isCurrentUser = passenger.userId == FirebaseAuth.instance.currentUser?.uid;
                      
                      return InkWell(
                        onTap: isCurrentUser ? () {
                          setState(() {
                            selectedTicketId = isSelected ? null : passenger.ticketId;
                          });
                        } : null,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? Colors.blue.shade50 
                                : (isCurrentUser ? Colors.white : Colors.grey.shade50),
                            border: isSelected 
                                ? Border.all(color: Colors.blue.shade300) 
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: isCurrentUser 
                                    ? (isSelected ? Colors.blue : Colors.grey) 
                                    : Colors.grey.shade400,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      passenger.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: isCurrentUser ? Colors.black : Colors.grey.shade500,
                                      ),
                                    ),
                                    Text(
                                      'Ticket #${passenger.ticketId.substring(0, 8)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isCurrentUser ? Colors.grey.shade600 : Colors.grey.shade400,
                                      ),
                                    ),
                                    if (!isCurrentUser)
                                      Text(
                                        'Cannot transfer other\'s tickets',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange.shade600,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Select recipient
                const Text(
                  'Transfer To',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: groupMembers.map((member) {
                      final isSelected = selectedMemberId == member['uid'];
                      
                      return InkWell(
                        onTap: () {
                          setState(() {
                            selectedMemberId = isSelected ? null : member['uid'];
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.green.shade50 : Colors.white,
                            border: isSelected ? Border.all(color: Colors.green.shade300) : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: isSelected ? Colors.green : Colors.grey,
                              ),
                              const SizedBox(width: 12),
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.blue.shade100,
                                child: Text(
                                  member['displayName']?.substring(0, 1).toUpperCase() ?? 'U',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member['displayName'] ?? 'Unknown User',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    if (member['email']?.isNotEmpty == true)
                                      Text(
                                        member['email'],
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Group Member',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Transfer note
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Transfer Note (Optional)',
                    hintText: 'Add a message for the recipient...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (selectedTicketId != null && selectedMemberId != null)
                  ? () => _executeTicketTransfer(
                      context,
                      selectedTicketId!,
                      selectedMemberId!,
                      groupMembers.firstWhere((m) => m['uid'] == selectedMemberId),
                      noteController.text.trim(),
                    )
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Transfer Ticket'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeTicketTransfer(
    BuildContext dialogContext,
    String ticketId,
    String toUserId,
    Map<String, dynamic> toUser,
    String transferNote,
  ) async {
    Navigator.pop(dialogContext); // Close dialog
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Transferring ticket...'),
          ],
        ),
      ),
    );
    
    try {
      final currentUser = FirebaseAuth.instance.currentUser!;
      
      await TransportBookingService.transferTicketToGroupMember(
        ticketId: ticketId,
        fromUserId: currentUser.uid,
        toUserId: toUserId,
        toUserName: toUser['displayName'] ?? 'Unknown User',
        toUserEmail: toUser['email'] ?? '',
        transferNote: transferNote.isEmpty ? null : transferNote,
      );
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ticket transferred to ${toUser['displayName']} successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        _showErrorDialog('Failed to transfer ticket: ${e.toString()}');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Error'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group, size: 48, color: Colors.orange.shade600),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ticket transfers are only allowed between members of the same group for security and organization purposes.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }
}
