import 'package:flutter/material.dart';
import 'package:simha_link/models/broadcast_message.dart';
import 'package:simha_link/services/broadcast_service.dart';
import 'package:simha_link/core/utils/app_logger.dart';
import 'package:simha_link/widgets/loading_button.dart';
import 'package:simha_link/widgets/app_snackbar.dart';
import 'package:simha_link/utils/role_utils.dart';

/// Screen for composing and sending broadcast messages (Organizers only)
class BroadcastComposeScreen extends StatefulWidget {
  const BroadcastComposeScreen({super.key});

  @override
  State<BroadcastComposeScreen> createState() => _BroadcastComposeScreenState();
}

class _BroadcastComposeScreenState extends State<BroadcastComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  
  BroadcastTarget _selectedTarget = BroadcastTarget.allUsers;
  BroadcastPriority _selectedPriority = BroadcastPriority.normal;
  bool _isSending = false;
  bool _isOrganizer = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkOrganizerPermission();
  }

  Future<void> _checkOrganizerPermission() async {
    try {
      final isOrganizer = await RoleUtils.isUserOrganizer();
      if (mounted) {
        setState(() {
          _isOrganizer = isOrganizer;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Error checking organizer permission', e, stackTrace);
      if (mounted) {
        setState(() {
          _isOrganizer = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _sendBroadcast() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    try {
      final success = await BroadcastService.sendBroadcast(
        title: _titleController.text,
        content: _contentController.text,
        target: _selectedTarget,
        priority: _selectedPriority,
      );

      if (mounted) {
        if (success) {
          AppSnackbar.showSuccess(context, 'Broadcast sent successfully!');
          Navigator.of(context).pop(true); // Return success result
        } else {
          AppSnackbar.showError(context, 'Failed to send broadcast. Please try again.');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to send broadcast from UI', e, stackTrace);
      if (mounted) {
        AppSnackbar.showError(context, 'An error occurred while sending the broadcast.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Broadcast'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_isOrganizer
              ? _buildUnauthorizedView()
              : _buildComposeForm(),
    );
  }

  Widget _buildUnauthorizedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.block,
              size: 72,
              color: Colors.red,
            ),
            const SizedBox(height: 24),
            const Text(
              'Organizer Permission Required',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Only organizers can send broadcast messages to participants, volunteers, or all users.',
              style: TextStyle(
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposeForm() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Target Audience Selection
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target Audience',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...BroadcastTarget.values.map((target) => RadioListTile<BroadcastTarget>(
                      title: Text(target.displayName),
                      subtitle: Text(
                        target.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      value: target,
                      groupValue: _selectedTarget,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedTarget = value);
                        }
                      },
                    )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Priority Selection
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Priority Level',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: BroadcastPriority.values.map((priority) {
                        final isSelected = _selectedPriority == priority;
                        return ChoiceChip(
                          label: Text(
                            priority.displayName,
                            style: TextStyle(
                              color: isSelected ? Colors.white : null,
                              fontWeight: isSelected ? FontWeight.bold : null,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedPriority = priority);
                            }
                          },
                          backgroundColor: priority.color.withOpacity(0.2),
                          selectedColor: priority.color,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Message Content
            Expanded(
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Message Content',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Title Field
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.title),
                        ),
                        maxLength: 100,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Title is required';
                          }
                          if (value.trim().length < 3) {
                            return 'Title must be at least 3 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Content Field
                      Expanded(
                        child: TextFormField(
                          controller: _contentController,
                          decoration: const InputDecoration(
                            labelText: 'Message Content',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.message),
                            alignLabelWithHint: true,
                          ),
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          maxLength: 1000,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Message content is required';
                            }
                            if (value.trim().length < 10) {
                              return 'Message must be at least 10 characters';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Send Button
            LoadingButton(
              onPressed: _isSending ? null : _sendBroadcast,
              isLoading: _isSending,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _selectedPriority == BroadcastPriority.urgent
                        ? Icons.priority_high
                        : Icons.send,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isSending 
                        ? 'Sending...' 
                        : 'Send Broadcast to ${_selectedTarget.displayName}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
