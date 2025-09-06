import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/feed_post.dart';
import '../../models/user_profile.dart';
import '../../services/feed_service.dart';
import 'widgets/feed_post_widget.dart';
import 'widgets/create_post_widget.dart';

class PostDetailScreen extends StatefulWidget {
  final FeedPost post;

  const PostDetailScreen({
    super.key,
    required this.post,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProfile?>(context);
    
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post Details'),
      ),
      body: Column(
        children: [
          // Original post
          FeedPostWidget(
            post: widget.post,
            currentUser: user,
            onEdit: (post) => _showEditPostDialog(context, post),
            onDelete: (post) => _confirmDeletePost(context, post),
            onTap: (post) {}, // No-op for detail screen
            onReply: (post) => _showReplyDialog(context, post, user),
          ),
          
          const Divider(),
          
          // Replies header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.comment_outlined),
                const SizedBox(width: 8),
                Text(
                  'Replies',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          
          // Replies list
          Expanded(
            child: StreamBuilder<List<FeedPost>>(
              stream: FeedService.getRepliesStream(widget.post.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading replies: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final replies = snapshot.data!;

                if (replies.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.comment_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No replies yet',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (_canUserReply(user)) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Be the first to reply!',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: replies.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: FeedPostWidget(
                        post: replies[index],
                        currentUser: user,
                        onEdit: (post) => _showEditPostDialog(context, post),
                        onDelete: (post) => _confirmDeletePost(context, post),
                        onTap: (post) {}, // No nested navigation
                        onReply: null, // No nested replies for now
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _canUserReply(user)
          ? FloatingActionButton(
              onPressed: () => _showReplyDialog(context, widget.post, user),
              tooltip: 'Reply',
              child: const Icon(Icons.reply),
            )
          : null,
    );
  }

  bool _canUserReply(UserProfile user) {
    return user.role == UserRole.volunteer || user.role == UserRole.organizer;
  }

  void _showEditPostDialog(BuildContext context, FeedPost post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CreatePostWidget.edit(
        post: post,
        onPostUpdated: () {
          setState(() {}); // Refresh the screen
        },
      ),
    );
  }

  void _showReplyDialog(BuildContext context, FeedPost post, UserProfile user) {
    if (!_canUserReply(user)) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CreatePostWidget.reply(
        parentPost: post,
        user: user,
        onReplyCreated: () {
          setState(() {}); // Refresh the replies
        },
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
                if (post.isOriginalPost) {
                  // If original post was deleted, go back
                  Navigator.of(context).pop();
                } else {
                  // If reply was deleted, just refresh
                  setState(() {});
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
