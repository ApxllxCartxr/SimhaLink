import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/transport.dart';
import '../../models/transport_booking.dart';
import '../../models/user_profile.dart';
import '../../services/transport_booking_service.dart';
import '../../core/utils/app_logger.dart';
import 'my_bookings_screen.dart';

class TransportBookingScreen extends StatefulWidget {
  final Transport transport;
  final UserProfile user;

  const TransportBookingScreen({
    super.key,
    required this.transport,
    required this.user,
  });

  @override
  State<TransportBookingScreen> createState() => _TransportBookingScreenState();
}

class _TransportBookingScreenState extends State<TransportBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final PageController _pageController = PageController();
  
  int _currentStep = 0;
  bool _isGroupBooking = false;
  int _numberOfTickets = 1;
  List<PassengerController> _passengerControllers = [];
  bool _isLoading = false;
  TransportBooking? _completedBooking;

  @override
  void initState() {
    super.initState();
    _initializePassengers();
  }

  void _initializePassengers() {
    _passengerControllers = List.generate(1, (index) => PassengerController());
    // Pre-fill first passenger with user's info
    _passengerControllers[0].nameController.text = widget.user.displayName;
    _passengerControllers[0].emailController.text = widget.user.email;
  }

  @override
  void dispose() {
    for (final controller in _passengerControllers) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentStep == 3 ? 'Booking Confirmed' : 'Book Transport'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildBookingTypeStep(),
          _buildPassengerDetailsStep(),
          _buildConfirmationStep(),
          _buildBookingCompleteStep(),
        ],
      ),
      bottomNavigationBar: _currentStep < 3 ? _buildBottomNavigation() : null,
    );
  }

  Widget _buildBookingTypeStep() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProgressIndicator(),
          const SizedBox(height: 24),
          
          // Transport Summary Card
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.transport.type == TransportType.bus 
                            ? Icons.directions_bus 
                            : Icons.airport_shuttle,
                        color: Colors.blue,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.transport.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              widget.transport.description,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildRouteInfo(),
                  const SizedBox(height: 12),
                  _buildScheduleInfo(),
                  const SizedBox(height: 12),
                  _buildAvailabilityInfo(),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Booking Type Selection
          const Text(
            'Booking Type',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          Card(
            child: Column(
              children: [
                RadioListTile<bool>(
                  title: const Text('Book for myself'),
                  subtitle: const Text('Single ticket booking'),
                  value: false,
                  groupValue: _isGroupBooking,
                  onChanged: (value) {
                    setState(() {
                      _isGroupBooking = false;
                      _numberOfTickets = 1;
                      _updatePassengerControllers();
                    });
                  },
                ),
                const Divider(height: 1),
                RadioListTile<bool>(
                  title: const Text('Book for my group'),
                  subtitle: const Text('Multiple tickets booking'),
                  value: true,
                  groupValue: _isGroupBooking,
                  onChanged: (value) {
                    setState(() {
                      _isGroupBooking = true;
                      _numberOfTickets = 2;
                      _updatePassengerControllers();
                    });
                  },
                ),
              ],
            ),
          ),
          
          if (_isGroupBooking) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Number of Tickets',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _numberOfTickets > 1 ? () {
                            setState(() {
                              _numberOfTickets--;
                              _updatePassengerControllers();
                            });
                          } : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$_numberOfTickets',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _numberOfTickets < widget.transport.capacity.availableSeats ? () {
                            setState(() {
                              _numberOfTickets++;
                              _updatePassengerControllers();
                            });
                          } : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        const Spacer(),
                        Text(
                          'Max: ${widget.transport.capacity.availableSeats}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPassengerDetailsStep() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProgressIndicator(),
            const SizedBox(height: 24),
            
            Text(
              'Passenger Details',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please provide details for ${_numberOfTickets == 1 ? 'your ticket' : 'all $_numberOfTickets tickets'}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            
            Expanded(
              child: ListView.builder(
                itemCount: _numberOfTickets,
                itemBuilder: (context, index) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  index == 0 ? 'Primary Passenger (You)' : 'Passenger ${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          TextFormField(
                            controller: _passengerControllers[index].nameController,
                            decoration: const InputDecoration(
                              labelText: 'Full Name *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter passenger name';
                              }
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 12),
                          
                          TextFormField(
                            controller: _passengerControllers[index].emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email (Optional)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value != null && value.isNotEmpty) {
                                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                                  return 'Please enter a valid email';
                                }
                              }
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 12),
                          
                          TextFormField(
                            controller: _passengerControllers[index].phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone Number (Optional)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.phone),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationStep() {
    final totalAmount = widget.transport.pricing.isFree 
        ? 0.0 
        : widget.transport.pricing.pricePerTicket * _numberOfTickets;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProgressIndicator(),
          const SizedBox(height: 24),
          
          const Text(
            'Booking Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Transport Details
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Transport Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryRow('Transport', widget.transport.title),
                          _buildSummaryRow('Route', '${widget.transport.route.fromAddress} → ${widget.transport.route.toAddress}'),
                          _buildSummaryRow('Departure', _formatDateTime(widget.transport.schedule.departureTime)),
                          _buildSummaryRow('Distance', '${widget.transport.route.distance.toStringAsFixed(1)} km'),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Passenger Details
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Passengers ($_numberOfTickets)',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...List.generate(_numberOfTickets, (index) {
                            final controller = _passengerControllers[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Colors.blue[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          color: Colors.blue[800],
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      controller.nameController.text,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Pricing Summary
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Payment Summary',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryRow(
                            'Tickets ($_numberOfTickets)', 
                            widget.transport.pricing.isFree 
                                ? 'Free' 
                                : '\$${(widget.transport.pricing.pricePerTicket * _numberOfTickets).toStringAsFixed(2)}'
                          ),
                          if (!widget.transport.pricing.isFree) ...[
                            const Divider(),
                            _buildSummaryRow(
                              'Total Amount', 
                              '\$${totalAmount.toStringAsFixed(2)}',
                              isTotal: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Terms and Conditions
                  Card(
                    color: Colors.orange[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.orange[700]),
                              const SizedBox(width: 8),
                              const Text(
                                'Important Information',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• Please arrive at the pickup location 10 minutes before departure\n'
                            '• Bring a valid ID for verification\n'
                            '• Your QR code will be required for boarding\n'
                            '• Cancellations must be made at least 2 hours before departure',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCompleteStep() {
    if (_completedBooking == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 32),
          
          // Success Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              Icons.check,
              color: Colors.white,
              size: 48,
            ),
          ),
          
          const SizedBox(height: 24),
          
          const Text(
            'Booking Confirmed!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            'Your transport booking has been confirmed.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          
          const SizedBox(height: 32),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // QR Code
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Text(
                            'Your Booking QR Code',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: QrImageView(
                              data: _completedBooking!.bookingDetails.qrCode,
                              version: QrVersions.auto,
                              size: 200.0,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Show this QR code when boarding',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Booking ID: ${_completedBooking!.id}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Booking Details Summary
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Booking Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryRow('Transport', widget.transport.title),
                          _buildSummaryRow('Route', '${widget.transport.route.fromAddress} → ${widget.transport.route.toAddress}'),
                          _buildSummaryRow('Departure', _formatDateTime(widget.transport.schedule.departureTime)),
                          _buildSummaryRow('Passengers', '${_completedBooking!.groupBooking.totalTickets}'),
                          _buildSummaryRow('Status', 'Confirmed'),
                          if (!widget.transport.pricing.isFree)
                            _buildSummaryRow('Total Paid', '\$${_completedBooking!.bookingDetails.totalAmount.toStringAsFixed(2)}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shareBooking(),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.home),
                  label: const Text('Done'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      children: List.generate(4, (index) {
        final isActive = index <= _currentStep;
        
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: isActive ? Colors.blue : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (index < 3) const SizedBox(width: 8),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildRouteInfo() {
    return Row(
      children: [
        const Icon(Icons.location_on, color: Colors.green, size: 16),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            widget.transport.route.fromAddress,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Icon(Icons.arrow_forward, size: 16),
        const SizedBox(width: 4),
        const Icon(Icons.flag, color: Colors.red, size: 16),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            widget.transport.route.toAddress,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleInfo() {
    return Row(
      children: [
        const Icon(Icons.schedule, size: 16),
        const SizedBox(width: 4),
        Text(
          'Departure: ${_formatDateTime(widget.transport.schedule.departureTime)}',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildAvailabilityInfo() {
    final available = widget.transport.capacity.availableSeats;
    final total = widget.transport.capacity.maxOccupants;
    
    return Row(
      children: [
        const Icon(Icons.people, size: 16),
        const SizedBox(width: 4),
        Text(
          '$available/$total seats available',
          style: TextStyle(
            fontSize: 12,
            color: available > 0 ? Colors.green : Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.green : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
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
      child: SafeArea(
        child: Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _previousStep,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Back'),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 16),
            Expanded(
              flex: _currentStep == 0 ? 1 : 2,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _currentStep == 2 ? Colors.green : Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(_getNextButtonText()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getNextButtonText() {
    switch (_currentStep) {
      case 0:
        return 'Continue';
      case 1:
        return 'Review Booking';
      case 2:
        return 'Confirm Booking';
      default:
        return 'Next';
    }
  }

  void _updatePassengerControllers() {
    // Preserve existing data
    final existingData = _passengerControllers.map((c) => {
      'name': c.nameController.text,
      'email': c.emailController.text,
      'phone': c.phoneController.text,
    }).toList();

    // Dispose old controllers
    for (final controller in _passengerControllers) {
      controller.dispose();
    }

    // Create new controllers
    _passengerControllers = List.generate(_numberOfTickets, (index) => PassengerController());

    // Restore data where possible
    for (int i = 0; i < _passengerControllers.length && i < existingData.length; i++) {
      _passengerControllers[i].nameController.text = existingData[i]['name']!;
      _passengerControllers[i].emailController.text = existingData[i]['email']!;
      _passengerControllers[i].phoneController.text = existingData[i]['phone']!;
    }

    // Pre-fill first passenger with user info if it's empty
    if (_passengerControllers.isNotEmpty && _passengerControllers[0].nameController.text.isEmpty) {
      _passengerControllers[0].nameController.text = widget.user.displayName;
      _passengerControllers[0].emailController.text = widget.user.email;
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextStep() {
    if (_currentStep == 1) {
      // Validate passenger details
      if (!_formKey.currentState!.validate()) {
        return;
      }
    }

    if (_currentStep < 2) {
      setState(() {
        _currentStep++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (_currentStep == 2) {
      // Confirm booking
      _confirmBooking();
    }
  }

  Future<void> _confirmBooking() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check if user already has a booking for this transport
      final canBook = await TransportBookingService.canUserBookTransport(
        widget.user.uid,
        widget.transport.id,
      );
      
      if (!canBook) {
        final existingBooking = await TransportBookingService.getUserExistingBooking(
          widget.user.uid,
          widget.transport.id,
        );
        
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          _showExistingBookingDialog(existingBooking!);
        }
        return;
      }

      // Create passenger info list
      final passengers = _passengerControllers.map((controller) {
        return PassengerInfo(
          userId: widget.user.uid,
          name: controller.nameController.text.trim(),
          email: controller.emailController.text.trim().isEmpty 
              ? null 
              : controller.emailController.text.trim(),
          ticketId: '', // Will be generated by service
        );
      }).toList();

      // Create booking
      final booking = await TransportBookingService.createBooking(
        transportId: widget.transport.id,
        bookerUserId: widget.user.uid,
        bookerName: widget.user.displayName,
        passengers: passengers,
        groupId: _isGroupBooking ? 'default_group' : null,
      );

      setState(() {
        _completedBooking = booking;
        _currentStep = 3;
        _isLoading = false;
      });

      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      AppLogger.logError('Booking failed', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booking failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _shareBooking() {
    if (_completedBooking != null) {
      final shareText = '''
🎫 Transport Booking Confirmed!

📍 Route: ${widget.transport.route.fromAddress} → ${widget.transport.route.toAddress}
🚌 Transport: ${widget.transport.title}
📅 Departure: ${_formatDateTime(widget.transport.schedule.departureTime)}
👥 Passengers: ${_completedBooking!.groupBooking.totalTickets}
🆔 Booking ID: ${_completedBooking!.id}

Show your QR code when boarding!
      ''';

      Clipboard.setData(ClipboardData(text: shareText));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking details copied to clipboard'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${_formatTime(dateTime)}';
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _showExistingBookingDialog(TransportBooking existingBooking) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Booking Already Exists'),
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
                  Text('Booked on ${_formatDateTime(existingBooking.bookedAt)}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You can only have one booking per transport. You can modify your existing booking or view it in My Bookings.',
              style: TextStyle(fontSize: 12),
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
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => MyBookingsScreen(
                    user: widget.user,
                    initialBookingId: existingBooking.id,
                  ),
                ),
              );
            },
            child: const Text('View Booking'),
          ),
        ],
      ),
    );
  }
}

class PassengerController {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
  }
}
