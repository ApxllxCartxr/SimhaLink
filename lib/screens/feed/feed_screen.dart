import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/feed_post.dart';
import '../../models/user_profile.dart';
import '../../services/feed_service.dart';
import '../../services/firebase_service.dart';
import 'widgets/feed_post_widget.dart';
import 'widgets/create_post_widget.dart';
import 'widgets/hashtag_filter_widget.dart';
import 'post_detail_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedHashtag;
  List<String> _trendingHashtags = [];

  @override
  void initState() {
    super.initState();
    print('🐛 FeedScreen: initState called');
    _tabController = TabController(length: 2, vsync: this);
    _loadTrendingHashtags();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTrendingHashtags() async {
    print('🐛 FeedScreen: Loading trending hashtags...');
    try {
      final hashtags = await FeedService.getTrendingHashtags();
      print('🐛 FeedScreen: Got ${hashtags.length} trending hashtags: $hashtags');
      if (mounted) {
        setState(() {
          _trendingHashtags = hashtags;
        });
        print('🐛 FeedScreen: Updated trending hashtags state');
      }
    } catch (e) {
      print('🐛 FeedScreen: Error loading trending hashtags: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🐛 FeedScreen: build() called');
    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      print('🐛 FeedScreen: No authenticated user, redirecting to auth');
      return const Scaffold(
        body: Center(
          child: Text('Please log in to view the feed'),
        ),
      );
    }

    return StreamBuilder<UserProfile?>(
      stream: UserService.getUserProfileStream(currentUser.uid),
      builder: (context, snapshot) {
        print('🐛 FeedScreen: UserProfile StreamBuilder - connectionState: ${snapshot.connectionState}');
        print('🐛 FeedScreen: UserProfile StreamBuilder - hasData: ${snapshot.hasData}');
        print('🐛 FeedScreen: UserProfile StreamBuilder - hasError: ${snapshot.hasError}');
        
        if (snapshot.hasError) {
          print('🐛 FeedScreen: UserProfile error: ${snapshot.error}');
          return Scaffold(
            appBar: AppBar(title: const Text('Feed')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text('Error loading user profile: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        // Force rebuild
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        
        if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
          print('🐛 FeedScreen: Waiting for user profile data');
          return Scaffold(
            appBar: AppBar(title: const Text('Feed')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data!;
        print('🐛 FeedScreen: Building main UI for user: ${user.displayName} (${user.role})');
        return _buildMainUI(user);
      },
    );
  }

  Widget _buildMainUI(UserProfile user) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getScreenTitle(user)),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Posts'),
            Tab(text: 'Trending'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAllPostsTab(user),
          _buildTrendingTab(user),
        ],
      ),
      floatingActionButton: _canUserCreatePost(user)
          ? FloatingActionButton(
              onPressed: () => _showCreatePostDialog(context, user),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  String _getScreenTitle(UserProfile user) {
    switch (user.role) {
      case UserRole.participant:
        return 'Community Feed';
      case UserRole.volunteer:
      case UserRole.organizer:
        return 'Attendee Feed';
      default:
        return 'Feed';
    }
  }

  bool _canUserCreatePost(UserProfile user) {
    return user.role == UserRole.participant;
  }

  Widget _buildAllPostsTab(UserProfile user) {
    return Column(
      children: [
        // Role indicator for volunteers/organizers
        if (user.role != UserRole.participant)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Text(
              '👀 Viewing attendee posts • You can reply to help',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        
        // Hashtag filter
        if (_trendingHashtags.isNotEmpty)
          HashtagFilterWidget(
            hashtags: _trendingHashtags,
            selectedHashtag: _selectedHashtag,
            onHashtagSelected: (hashtag) {
              setState(() {
                _selectedHashtag = hashtag;
              });
            },
          ),
        
        // Posts list
        Expanded(
          child: StreamBuilder<List<FeedPost>>(
            stream: _selectedHashtag == null
                ? FeedService.getPostsStreamForUser(user)
                : FeedService.getPostsByHashtagStreamForUser(_selectedHashtag!, user),
            builder: (context, snapshot) {
              print('🐛 FeedScreen StreamBuilder: connectionState = ${snapshot.connectionState}');
              print('🐛 FeedScreen StreamBuilder: hasData = ${snapshot.hasData}');
              print('🐛 FeedScreen StreamBuilder: hasError = ${snapshot.hasError}');
              
              if (snapshot.hasError) {
                print('🐛 FeedScreen StreamBuilder: Error = ${snapshot.error}');
                print('🐛 FeedScreen StreamBuilder: StackTrace = ${snapshot.stackTrace}');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text('Error: ${snapshot.error}'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            // Force rebuild to retry
                          });
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              if (!snapshot.hasData) {
                print('🐛 FeedScreen StreamBuilder: No data yet, showing loading...');
                return const Center(child: CircularProgressIndicator());
              }

              final posts = snapshot.data!;
              print('🐛 FeedScreen StreamBuilder: Got ${posts.length} posts');

              if (posts.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user.role == UserRole.participant
                            ? 'No posts yet. Be the first to share!'
                            : 'No attendee posts yet.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _loadTrendingHashtags,
                child: ListView.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    return FeedPostWidget(
                      post: posts[index],
                      currentUser: user,
                      onEdit: (post) => _showEditPostDialog(context, post),
                      onDelete: (post) => _confirmDeletePost(context, post),
                      onTap: (post) => _openPostDetail(context, post),
                      onReply: (post) => _showReplyDialog(context, post, user),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTrendingTab(UserProfile user) {
    return ListView.builder(
      itemCount: _trendingHashtags.length,
      itemBuilder: (context, index) {
        final hashtag = _trendingHashtags[index];
        return ListTile(
          leading: const Icon(Icons.trending_up),
          title: Text('#$hashtag'),
          subtitle: const Text('Trending topic'),
          onTap: () {
            setState(() {
              _selectedHashtag = hashtag;
              _tabController.animateTo(0);
            });
          },
        );
      },
    );
  }

  void _showCreatePostDialog(BuildContext context, UserProfile user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CreatePostWidget(
        user: user,
        onPostCreated: () {
          _loadTrendingHashtags();
        },
      ),
    );
  }

  void _showEditPostDialog(BuildContext context, FeedPost post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CreatePostWidget.edit(
        post: post,
        onPostUpdated: () {
          _loadTrendingHashtags();
        },
      ),
    );
  }

  void _showReplyDialog(BuildContext context, FeedPost post, UserProfile user) {
    if (user.role == UserRole.participant) return; // Only volunteers/organizers can reply
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CreatePostWidget.reply(
        parentPost: post,
        user: user,
        onReplyCreated: () {
          _loadTrendingHashtags();
        },
      ),
    );
  }

  void _openPostDetail(BuildContext context, FeedPost post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(post: post),
      ),
    );
  }

  void _confirmDeletePost(BuildContext context, FeedPost post) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: Text(
          post.isOriginalPost 
              ? 'Are you sure you want to delete this post? All replies will also be deleted.'
              : 'Are you sure you want to delete this reply?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final success = await FeedService.deletePost(
                postId: post.id,
                userId: post.userId,
              );
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(post.isOriginalPost ? 'Post deleted' : 'Reply deleted'),
                  ),
                );
                _loadTrendingHashtags();
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
