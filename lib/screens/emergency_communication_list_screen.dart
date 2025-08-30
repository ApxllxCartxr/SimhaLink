import 'package:flutter/material.dart';
import 'package:simha_link/models/emergency_communication.dart';
import 'package:simha_link/services/emergency_communication_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Screen for displaying emergency communications
/// Shows different views for organizers and volunteers
class EmergencyCommunicationListScreen extends StatefulWidget {
  const EmergencyCommunicationListScreen({super.key});

  @override
  State<EmergencyCommunicationListScreen> createState() => _EmergencyCommunicationListScreenState();
}

class _EmergencyCommunicationListScreenState extends State<EmergencyCommunicationListScreen> {
  String? _userRole;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _getUserRole();
  }

  Future<void> _getUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (mounted) {
        setState(() {
          if (userDoc.exists) {
            final userData = userDoc.data();
            _userRole = userData?['role'] as String?;
          } else {
            _userRole = null;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
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
        title: const Text('Emergency Communications'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildCommunicationsList(),
      floatingActionButton: _userRole?.toLowerCase() == 'volunteer'
          ? FloatingActionButton(
              onPressed: () {
                Navigator.pushNamed(
                  context, 
                  '/emergency_communication_compose',
                );
              },
              backgroundColor: Colors.red.shade700,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildCommunicationsList() {
    return StreamBuilder<List<EmergencyCommunication>>(
      stream: EmergencyCommunicationService.getEmergencyCommunicationsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading communications: ${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }

        final communications = snapshot.data ?? [];
        
        if (communications.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  _userRole?.toLowerCase() == 'volunteer'
                      ? 'You have not sent any emergency\ncommunications yet'
                      : 'No emergency communications\nto review',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: communications.length,
          itemBuilder: (context, index) {
            final comm = communications[index];
            return _buildCommunicationCard(comm);
          },
        );
      },
    );
  }

  Widget _buildCommunicationCard(EmergencyCommunication comm) {
    // Mark as read when viewed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      EmergencyCommunicationService.markAsRead(comm.id);
    });

    // Format date
    final date = '${comm.createdAt.day}/${comm.createdAt.month}/${comm.createdAt.year}';
    final time = '${comm.createdAt.hour}:${comm.createdAt.minute.toString().padLeft(2, '0')}';
    
    // Get priority color
    Color priorityColor;
    switch (comm.priority) {
      case EmergencyPriority.low:
        priorityColor = Colors.blue;
        break;
      case EmergencyPriority.medium:
        priorityColor = Colors.orange;
        break;
      case EmergencyPriority.high:
        priorityColor = Colors.red;
        break;
      case EmergencyPriority.critical:
        priorityColor = Colors.purple;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: priorityColor.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: () => _showCommunicationDetails(comm),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with priority and status
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: priorityColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      comm.priority.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (comm.isResolved)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'RESOLVED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Title and sender
              Text(
                comm.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 4),
              
              Text(
                'From: ${comm.senderName} (${comm.senderRole})',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Message preview
              Text(
                comm.message.length > 100
                    ? '${comm.message.substring(0, 100)}...'
                    : comm.message,
                style: const TextStyle(fontSize: 14),
              ),
              
              const SizedBox(height: 16),
              
              // Footer with date and response indicator
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$date at $time',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const Spacer(),
                  if (comm.respondedBy.isNotEmpty && !comm.isResolved)
                    Row(
                      children: [
                        Icon(
                          Icons.reply,
                          size: 16,
                          color: Colors.green.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Organizer responded',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade600,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCommunicationDetails(EmergencyCommunication comm) {
    final user = FirebaseAuth.instance.currentUser;
    final isOrganizer = _userRole?.toLowerCase() == 'organizer';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            comm.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Priority badge
                    _buildPriorityBadge(comm.priority),
                    
                    const SizedBox(height: 16),
                    
                    // Sender info
                    _buildInfoRow(
                      'From',
                      '${comm.senderName} (${comm.senderRole})',
                    ),
                    
                    _buildInfoRow(
                      'Sent',
                      _formatDateTime(comm.createdAt),
                    ),
                    
                    if (comm.location != null)
                      _buildInfoRow('Location', 'Included (tap to view)'),
                    
                    const Divider(height: 32),
                    
                    // Message content
                    const Text(
                      'Message:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    Text(
                      comm.message,
                      style: const TextStyle(fontSize: 16),
                    ),
                    
                    if (comm.isResolved) ...[
                      const Divider(height: 32),
                      
                      // Resolution info
                      const Text(
                        'Resolution:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      Text(
                        comm.resolution ?? 'No details provided',
                        style: const TextStyle(fontSize: 16),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      Text(
                        'Resolved by organizer on ${_formatDateTime(comm.resolvedAt ?? DateTime.now())}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 24),
                    
                    // Action buttons
                    if (isOrganizer && !comm.isResolved)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                // Mark as responded by this organizer
                                EmergencyCommunicationService.markAsResponded(comm.id);
                                // In a real app, this would open a chat or call screen
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Contact functionality coming soon'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.phone),
                              label: const Text('CONTACT'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _showResolveDialog(comm);
                              },
                              icon: const Icon(Icons.check_circle),
                              label: const Text('RESOLVE'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                    if (!isOrganizer && comm.senderId == user?.uid && !comm.isResolved)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            // In a real app, this would allow updating the emergency
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Update functionality coming soon'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('UPDATE EMERGENCY'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPriorityBadge(EmergencyPriority priority) {
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
    
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        priority.displayName.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final date = '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    final time = '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    return '$date at $time';
  }

  void _showResolveDialog(EmergencyCommunication comm) {
    final resolutionController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Resolve Emergency'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter resolution details:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: resolutionController,
                      decoration: const InputDecoration(
                        hintText: 'How was this emergency handled?',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setState(() {
                            isSubmitting = true;
                          });
                          
                          final success = await EmergencyCommunicationService.resolveEmergencyCommunication(
                            communicationId: comm.id,
                            resolution: resolutionController.text.trim(),
                          );
                          
                          if (mounted) {
                            Navigator.pop(context);
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                      ? 'Emergency marked as resolved'
                                      : 'Failed to resolve emergency',
                                ),
                                backgroundColor: success ? Colors.green : Colors.red,
                              ),
                            );
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('RESOLVE'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
