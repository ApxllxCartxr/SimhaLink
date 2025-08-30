import 'package:flutter/material.dart';
import 'package:simha_link/models/emergency_communication.dart';
import 'package:simha_link/services/emergency_communication_service.dart';

/// Screen for volunteers to send emergency communications to organizers
class EmergencyCommunicationScreen extends StatefulWidget {
  const EmergencyCommunicationScreen({super.key});

  @override
  State<EmergencyCommunicationScreen> createState() => _EmergencyCommunicationScreenState();
}

class _EmergencyCommunicationScreenState extends State<EmergencyCommunicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  
  EmergencyPriority _selectedPriority = EmergencyPriority.medium;
  bool _isLoading = false;
  String? _currentLocation;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendEmergencyCommunication() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await EmergencyCommunicationService.sendEmergencyCommunication(
        title: _titleController.text.trim(),
        message: _messageController.text.trim(),
        priority: _selectedPriority,
        location: _currentLocation,
      );

      if (mounted) {
        if (result != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Emergency communication sent to organizers'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send emergency communication'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Communication'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info text
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.amber),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This message will be sent to all organizers in your group. '
                              'Use this for urgent matters that require organizer assistance.',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Priority selection
                    const Text(
                      'Priority Level',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPrioritySelector(),
                    
                    const SizedBox(height: 24),
                    
                    // Title field
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                        hintText: 'Brief summary of the emergency',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a title';
                        }
                        if (value.length > 100) {
                          return 'Title must be less than 100 characters';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Message field
                    TextFormField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        border: OutlineInputBorder(),
                        hintText: 'Describe the situation in detail',
                        alignLabelWithHint: true,
                      ),
                      maxLines: 5,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a message';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Include location checkbox
                    CheckboxListTile(
                      title: const Text('Include my current location'),
                      value: _currentLocation != null,
                      activeColor: Colors.red.shade700,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) {
                        setState(() {
                          // In a real app, this would get the actual location
                          _currentLocation = value == true 
                              ? 'lat:0.0,lng:0.0' // Placeholder
                              : null;
                        });
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Send button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _sendEmergencyCommunication,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'SEND EMERGENCY COMMUNICATION',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPrioritySelector() {
    return Column(
      children: EmergencyPriority.values.map((priority) {
        Color color;
        switch (priority) {
          case EmergencyPriority.low:
            color = Colors.blue;
            break;
          case EmergencyPriority.medium:
            color = Colors.orange;
            break;
          case EmergencyPriority.high:
            color = Colors.red;
            break;
          case EmergencyPriority.critical:
            color = Colors.purple;
            break;
        }
        
        return RadioListTile<EmergencyPriority>(
          title: Text(
            priority.displayName,
            style: TextStyle(
              color: color,
              fontWeight: _selectedPriority == priority 
                  ? FontWeight.bold 
                  : FontWeight.normal,
            ),
          ),
          value: priority,
          groupValue: _selectedPriority,
          activeColor: color,
          onChanged: (value) {
            setState(() {
              _selectedPriority = value!;
            });
          },
        );
      }).toList(),
    );
  }
}
