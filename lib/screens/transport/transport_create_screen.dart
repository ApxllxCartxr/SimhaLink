import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../../models/transport.dart';
import '../../models/user_profile.dart';
import '../../services/transport_service.dart';
import '../map/route_picker_screen.dart';

class TransportCreateScreen extends StatefulWidget {
  final UserProfile user;

  const TransportCreateScreen({
    super.key,
    required this.user,
  });

  @override
  State<TransportCreateScreen> createState() => _TransportCreateScreenState();
}

class _TransportCreateScreenState extends State<TransportCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _capacityController = TextEditingController();
  final _priceController = TextEditingController();
  final _fromAddressController = TextEditingController();
  final _toAddressController = TextEditingController();

  TransportType _selectedType = TransportType.bus;
  TransportVisibility _selectedVisibility = TransportVisibility.public;
  DateTime? _selectedDepartureTime;
  LatLng? _fromLocation;
  LatLng? _toLocation;
  List<LatLng> _routePath = [];
  bool _isFree = true;
  bool _isLoading = false;
  List<String> _allowedGroupIds = [];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _capacityController.dispose();
    _priceController.dispose();
    _fromAddressController.dispose();
    _toAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Transport'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveTransport,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildBasicInfoSection(),
            const SizedBox(height: 24),
            _buildRouteSection(),
            const SizedBox(height: 24),
            _buildScheduleSection(),
            const SizedBox(height: 24),
            _buildCapacitySection(),
            const SizedBox(height: 24),
            _buildPricingSection(),
            const SizedBox(height: 24),
            _buildVisibilitySection(),
            const SizedBox(height: 32),
            // Create Transport Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveTransport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: _isLoading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Creating Transport...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'Create Transport',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Basic Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Transport Title',
                hintText: 'e.g., Event Shuttle Bus A',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Brief description of the transport service',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TransportType>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Transport Type',
                border: OutlineInputBorder(),
              ),
              items: TransportType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Row(
                    children: [
                      Icon(_getTransportTypeIcon(type)),
                      const SizedBox(width: 8),
                      Text(_getTransportTypeName(type)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedType = value;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Route Information',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openRoutePicker,
                  icon: const Icon(Icons.map),
                  label: const Text('Pick Route'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _fromAddressController,
              decoration: const InputDecoration(
                labelText: 'From Address',
                hintText: 'Starting location',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on, color: Colors.green),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter starting address';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _toAddressController,
              decoration: const InputDecoration(
                labelText: 'To Address',
                hintText: 'Destination location',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.flag, color: Colors.red),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter destination address';
                }
                return null;
              },
            ),
            if (_fromLocation != null && _toLocation != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Route selected: ${_calculateDistance().toStringAsFixed(1)} km',
                        style: const TextStyle(color: Colors.green),
                      ),
                    ),
                    TextButton(
                      onPressed: _clearRoute,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleSection() {
    return Card(
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
            InkWell(
              onTap: _selectDepartureTime,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Departure Time',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            _selectedDepartureTime != null
                                ? _formatDateTime(_selectedDepartureTime!)
                                : 'Select departure time',
                            style: TextStyle(
                              fontSize: 16,
                              color: _selectedDepartureTime != null
                                  ? Colors.black
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            if (_selectedDepartureTime != null) ...[
              const SizedBox(height: 8),
              Text(
                'Departure in ${_getTimeUntilDeparture()}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCapacitySection() {
    return Card(
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
            TextFormField(
              controller: _capacityController,
              decoration: const InputDecoration(
                labelText: 'Maximum Seats',
                hintText: 'e.g., 50',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.people),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter capacity';
                }
                final capacity = int.tryParse(value);
                if (capacity == null || capacity <= 0) {
                  return 'Please enter a valid capacity';
                }
                if (capacity > 200) {
                  return 'Capacity cannot exceed 200 seats';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingSection() {
    return Card(
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
            SwitchListTile(
              title: const Text('Free Transport'),
              subtitle: const Text('No charge for passengers'),
              value: _isFree,
              onChanged: (value) {
                setState(() {
                  _isFree = value;
                  if (value) {
                    _priceController.clear();
                  }
                });
              },
            ),
            if (!_isFree) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Price per Ticket',
                  hintText: '0.00',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                  suffixText: 'USD',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (!_isFree) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a price';
                    }
                    final price = double.tryParse(value);
                    if (price == null || price < 0) {
                      return 'Please enter a valid price';
                    }
                    if (price > 1000) {
                      return 'Price cannot exceed \$1000';
                    }
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVisibilitySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visibility & Access',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TransportVisibility>(
              value: _selectedVisibility,
              decoration: const InputDecoration(
                labelText: 'Who can see this transport?',
                border: OutlineInputBorder(),
              ),
              items: TransportVisibility.values.map((visibility) {
                return DropdownMenuItem(
                  value: visibility,
                  child: Row(
                    children: [
                      Icon(_getVisibilityIcon(visibility)),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_getVisibilityName(visibility)),
                          Text(
                            _getVisibilityDescription(visibility),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedVisibility = value;
                  });
                }
              },
            ),
            if (_selectedVisibility == TransportVisibility.groupOnly) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Group-only transports are visible to all groups. To restrict to specific groups, configure allowed groups after creation.',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getTransportTypeIcon(TransportType type) {
    switch (type) {
      case TransportType.bus:
        return Icons.directions_bus;
      case TransportType.shuttle:
        return Icons.airport_shuttle;
    }
  }

  String _getTransportTypeName(TransportType type) {
    switch (type) {
      case TransportType.bus:
        return 'Bus';
      case TransportType.shuttle:
        return 'Shuttle';
    }
  }

  IconData _getVisibilityIcon(TransportVisibility visibility) {
    switch (visibility) {
      case TransportVisibility.public:
        return Icons.public;
      case TransportVisibility.groupOnly:
        return Icons.group;
    }
  }

  String _getVisibilityName(TransportVisibility visibility) {
    switch (visibility) {
      case TransportVisibility.public:
        return 'Public';
      case TransportVisibility.groupOnly:
        return 'Groups Only';
    }
  }

  String _getVisibilityDescription(TransportVisibility visibility) {
    switch (visibility) {
      case TransportVisibility.public:
        return 'Available to all attendees';
      case TransportVisibility.groupOnly:
        return 'Only group members can book';
    }
  }

  double _calculateDistance() {
    if (_fromLocation == null || _toLocation == null) return 0.0;
    
    const Distance distance = Distance();
    return distance.as(LengthUnit.Kilometer, _fromLocation!, _toLocation!);
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
    if (_selectedDepartureTime == null) return '';
    
    final now = DateTime.now();
    final difference = _selectedDepartureTime!.difference(now);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} day(s)';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour(s)';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute(s)';
    } else {
      return 'Starting soon';
    }
  }

  void _openRoutePicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => RoutePickerScreen(
          initialFromLocation: _fromLocation,
          initialToLocation: _toLocation,
          initialFromAddress: _fromAddressController.text,
          initialToAddress: _toAddressController.text,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _fromLocation = result['fromLocation'] as LatLng?;
        _toLocation = result['toLocation'] as LatLng?;
        _fromAddressController.text = result['fromAddress'] as String? ?? '';
        _toAddressController.text = result['toAddress'] as String? ?? '';
        
        final routePoints = result['routePoints'] as List<LatLng>?;
        if (routePoints != null) {
          _routePath.clear();
          _routePath.addAll(routePoints);
        }
      });
    }
  }

  void _clearRoute() {
    setState(() {
      _fromLocation = null;
      _toLocation = null;
      _routePath.clear();
    });
  }

  Future<void> _selectDepartureTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      );

      if (time != null && mounted) {
        setState(() {
          _selectedDepartureTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _saveTransport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDepartureTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a departure time')),
      );
      return;
    }

    if (_fromAddressController.text.trim().isEmpty || _toAddressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both starting and destination addresses')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create dummy coordinates if route not picked
      final fromLoc = _fromLocation ?? const LatLng(37.7749, -122.4194); // San Francisco
      final toLoc = _toLocation ?? const LatLng(37.7849, -122.4094); // Near San Francisco

      final route = TransportRoute(
        fromLocation: fromLoc,
        toLocation: toLoc,
        fromAddress: _fromAddressController.text.trim(),
        toAddress: _toAddressController.text.trim(),
        routePath: _routePath.isNotEmpty ? _routePath : [fromLoc, toLoc],
        distance: _calculateDistance(),
      );

      final schedule = TransportSchedule(
        departureTime: _selectedDepartureTime!,
        estimatedArrival: _selectedDepartureTime!.add(const Duration(hours: 1)),
        isRecurring: false,
      );

      final capacity = TransportCapacity(
        maxOccupants: int.parse(_capacityController.text),
        currentOccupants: 0,
      );

      final pricing = TransportPricing(
        isFree: _isFree,
        pricePerTicket: _isFree ? 0.0 : double.parse(_priceController.text),
        currency: 'USD',
      );

      final transport = Transport(
        id: '', // Will be generated by Firebase
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        type: _selectedType,
        route: route,
        schedule: schedule,
        capacity: capacity,
        pricing: pricing,
        organizerId: widget.user.uid,
        organizerName: widget.user.displayName,
        status: TransportStatus.active,
        visibility: _selectedVisibility,
        allowedGroupIds: _allowedGroupIds,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await TransportService.createTransport(transport);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transport created successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating transport: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
