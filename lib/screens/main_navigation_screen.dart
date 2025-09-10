import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/screens/auth_wrapper.dart';


import 'package:simha_link/screens/group_creation_screen.dart';
import 'package:simha_link/screens/map_screen.dart';
import 'package:simha_link/screens/solo_map_screen.dart';
import 'package:simha_link/screens/profile_screen.dart';
import 'package:simha_link/screens/group_chat_screen.dart';
import 'package:simha_link/screens/feed/feed_screen.dart';
import 'package:simha_link/services/auth_service.dart';
import 'package:simha_link/services/emergency_communication_service.dart';
import 'package:simha_link/utils/user_preferences.dart';
 

/// Main navigation container with a bottom navigation bar
/// Handles routing between main screens and maintaining navigation state
class MainNavigationScreen extends StatefulWidget {
  final String? groupId; // Made nullable to support solo mode
  
  const MainNavigationScreen({
    super.key,
    required this.groupId,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  String? _groupId; // Made nullable
  bool _isInSoloMode = false;
  // _userRole removed - role-specific UI now handled elsewhere
  bool _isLoading = true;
  bool _isLeavingGroup = false;
  bool _isLoggingOut = false;
  StreamSubscription<User?>? _authSubscription;
  Timer? _groupStatusTimer;

  @override
  void initState() {
    super.initState();
    print('[DEBUG] MainNavigationScreen: initState called');
    _groupId = widget.groupId;
    _isInSoloMode = widget.groupId == null || widget.groupId!.isEmpty; // Initial check - if no valid group ID, solo mode
    print('[DEBUG] MainNavigationScreen: Group ID set to: $_groupId');
    print('[DEBUG] MainNavigationScreen: Solo mode (initial): $_isInSoloMode');
    _checkSoloMode(); // Async check that will update if needed
    _startGroupStatusMonitoring(); // Start monitoring for group status changes
    print('[DEBUG] MainNavigationScreen: Calling _getUserRole()');
    _getUserRole();
    // Aggressive fallback: listen for global auth state changes and
    // force navigation to the auth wrapper when the user signs out.
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      print('[DEBUG] MainNavigationScreen: Auth state changed - User: ${user?.uid ?? 'null'}');
      if (user == null) {
        print('[DEBUG] MainNavigationScreen: User signed out, navigating to AuthWrapper');
        // Ensure this runs after the current frame to avoid navigation during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const AuthWrapper()),
              (_) => false,
            );
          } catch (e) {
            print('[ERROR] MainNavigationScreen: Navigation error: $e');
            // ignore navigation errors - this is a best-effort fallback
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _groupStatusTimer?.cancel();
    super.dispose();
  }

  void _startGroupStatusMonitoring() {
    // Check for group status changes every 2 seconds
    _groupStatusTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      try {
        final currentGroupId = await UserPreferences.getUserGroupId();
        
        // Check if group status has changed
        if (currentGroupId != _groupId) {
          print('[DEBUG] MainNavigationScreen: Group status changed from $_groupId to $currentGroupId');
          
          setState(() {
            _groupId = currentGroupId;
            _isInSoloMode = currentGroupId == null || currentGroupId.isEmpty;
          });
          
          print('[DEBUG] MainNavigationScreen: Updated to solo mode: $_isInSoloMode');
        }
      } catch (e) {
        print('[ERROR] MainNavigationScreen: Error monitoring group status: $e');
      }
    });
  }

  Future<void> _checkSoloMode() async {
    try {
      // If user has a valid group ID, they should NOT be in solo mode
      if (widget.groupId != null && widget.groupId!.isNotEmpty) {
        print('[DEBUG] MainNavigationScreen: User has group ID, setting solo mode to false');
        if (mounted && _isInSoloMode) {
          setState(() {
            _isInSoloMode = false;
          });
        }
        return;
      }
      
      // Only check UserPreferences if no group ID is provided
      final isInSoloModeFromPrefs = await UserPreferences.isUserInSoloMode();
      final newSoloMode = true; // If no group ID, definitely solo mode
      
      print('[DEBUG] MainNavigationScreen: Solo mode from prefs: $isInSoloModeFromPrefs');
      print('[DEBUG] MainNavigationScreen: Final solo mode: $newSoloMode');
      
      if (mounted && newSoloMode != _isInSoloMode) {
        setState(() {
          _isInSoloMode = newSoloMode;
        });
      }
    } catch (e) {
      print('[ERROR] MainNavigationScreen: Error checking solo mode: $e');
      final fallbackSoloMode = widget.groupId == null || widget.groupId!.isEmpty;
      if (mounted && fallbackSoloMode != _isInSoloMode) {
        setState(() {
          _isInSoloMode = fallbackSoloMode;
        });
      }
    }
  }

  Future<void> _getUserRole() async {
    print('[DEBUG] MainNavigationScreen: Starting _getUserRole()');
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('[DEBUG] MainNavigationScreen: No current user found');
        return;
      }
      
      print('[DEBUG] MainNavigationScreen: User found: ${user.uid}');
      print('[DEBUG] MainNavigationScreen: Group ID: $_groupId');

      if (mounted) {
        print('[DEBUG] MainNavigationScreen: Setting _isLoading = false');
        setState(() {
          _isLoading = false;
        });
        print('[DEBUG] MainNavigationScreen: _isLoading set to false successfully');
      } else {
        print('[DEBUG] MainNavigationScreen: Widget not mounted, skipping setState');
      }
    } catch (e) {
      print('[ERROR] MainNavigationScreen: Error in _getUserRole: $e');
      if (mounted) {
        print('[DEBUG] MainNavigationScreen: Setting _isLoading = false due to error');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    print('[DEBUG] MainNavigationScreen: Build called - _isLoading: $_isLoading');
    // Check if it's a narrow screen (like a phone)
    final isPhone = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      body: _isLoading
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
                Text(
                  'Loading group data...',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Group ID: $_groupId',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            )
          : IndexedStack(
              index: _selectedIndex,
              children: _isInSoloMode ? [
                // Solo mode pages
                const ProfileScreen(),
                const SoloMapScreen(),
                const FeedScreen(),
                GroupChatScreen(groupId: _groupId), // null groupId for solo mode
              ] : [
                // Group mode pages
                const ProfileScreen(),
                MapScreen(groupId: _groupId!), // Safe to use ! here since not in solo mode
                const FeedScreen(),
                GroupChatScreen(groupId: _groupId),
              ],
            ),
      bottomNavigationBar: isPhone
          ? _buildBottomNavigationBar()
          : null,
      floatingActionButton: isPhone
          ? null // We're using the bottom nav for navigation
          : _buildFloatingActionButtons(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      endDrawer: _buildDrawer(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed, // Add this to show all tabs
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
      selectedItemColor: Colors.red,
      unselectedItemColor: Colors.grey,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.map),
          label: 'Map',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.feed),
          label: 'Feed',
        ),
        BottomNavigationBarItem(
          icon: _buildBadgedIcon(
            icon: Icons.chat,
            stream: EmergencyCommunicationService.getUnreadCountStream(),
          ),
          label: 'Chat',
        ),
      ],
    );
  }

  Widget _buildBadgedIcon({
    required IconData icon,
    required Stream<int> stream,
  }) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon),
            if (count > 0)
              Positioned(
                right: -8,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget? _buildFloatingActionButtons() {
    // For tablet/desktop layout
    return null; // Would implement a floating action menu here
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Colors.red.shade800,
            ),
            accountName: const Text('User Name'), // Would get from Firebase
            accountEmail: Text(FirebaseAuth.instance.currentUser?.email ?? ''),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                FirebaseAuth.instance.currentUser?.email?.substring(0, 1).toUpperCase() ?? '',
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.red.shade800,
                ),
              ),
            ),
          ),
          
          // Menu items
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('Map'),
            selected: _selectedIndex == 0,
            onTap: () {
              Navigator.pop(context);
              _onItemTapped(0);
            },
          ),
          
          ListTile(
            leading: const Icon(Icons.group),
            title: const Text('Group Info'),
            onTap: () {
              Navigator.pop(context);
              // Would navigate to group info
            },
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('Leave Group'),
            onTap: () {
              Navigator.pop(context);
              _showLeaveGroupConfirmation();
            },
          ),
          
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () {
              Navigator.pop(context);
              _showLogoutConfirmation();
            },
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              // Would show about dialog
            },
          ),
        ],
      ),
    );
  }

  void _showLeaveGroupConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group?'),
        content: const Text(
          'You will be removed from this group and will need to create or join a new group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: _handleLeaveGroup,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('LEAVE GROUP'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLeaveGroup() async {
    if (_isLeavingGroup) return;
    
    setState(() {
      _isLeavingGroup = true;
    });
    
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Leaving group...'),
            ],
          ),
        ),
      );
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _groupId == null) {
        Navigator.pop(context); // Close loading dialog
        return;
      }
      
      // Leave group and clean up
      await UserPreferences.leaveGroupAndCleanup(_groupId!, user.uid);
      
      if (mounted) {
        // Close loading dialog
        Navigator.pop(context);
        
        // IMPORTANT: Use direct navigation instead of named routes
        // This avoids conditional rendering which can cause navigation issues
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const GroupCreationScreen()),
        );
      }
    } catch (e) {
      // Handle errors
      if (mounted) {
        // Close loading dialog if open
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error leaving group: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLeavingGroup = false;
        });
      }
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text(
          'You will be signed out of your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: _handleLogout,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('LOGOUT'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    if (_isLoggingOut) return;
    
    setState(() {
      _isLoggingOut = true;
    });
    
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Logging out...'),
            ],
          ),
        ),
      );
      
      // Sign out (uses AuthService for proper cleanup)
      await AuthService().signOut();
      
      // Force reset to login screen using root navigator
      if (mounted) {
        // Pop the dialog first
        Navigator.of(context, rootNavigator: true).pop();
        
        // Completely clear the navigation stack and show the AuthWrapper
        // (AuthWrapper will read auth state and show the correct screen).
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
          (_) => false, // Remove all routes
        );
      }
    } catch (e) {
      // Handle errors
      if (mounted) {
        // Close loading dialog if open
        Navigator.of(context, rootNavigator: true).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }
}
