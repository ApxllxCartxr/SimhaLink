import 'package:flutter/material.dart';
import '../../../models/feed_post.dart';
import '../../../models/user_profile.dart';
import '../../../services/feed_service.dart';

class CreatePostWidget extends StatefulWidget {
  final UserProfile? user;
  final FeedPost? post;
  final FeedPost? parentPost;
  final VoidCallback? onPostCreated;
  final VoidCallback? onPostUpdated;
  final VoidCallback? onReplyCreated;

  const CreatePostWidget({
    super.key,
    required this.user,
    this.onPostCreated,
  }) : post = null, 
       parentPost = null,
       onPostUpdated = null, 
       onReplyCreated = null;

  const CreatePostWidget.edit({
    super.key,
    required this.post,
    this.onPostUpdated,
  }) : user = null, 
       parentPost = null,
       onPostCreated = null, 
       onReplyCreated = null;

  const CreatePostWidget.reply({
    super.key,
    required this.parentPost,
    required this.user,
    this.onReplyCreated,
  }) : post = null,
       onPostCreated = null, 
       onPostUpdated = null;

  @override
  State<CreatePostWidget> createState() => _CreatePostWidgetState();
}

class _CreatePostWidgetState extends State<CreatePostWidget> {
  late TextEditingController _controller;
  bool _isLoading = false;
  
  bool get _isEditing => widget.post != null;
  bool get _isReplying => widget.parentPost != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.post?.content ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _getTitle(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Parent post preview for replies
            if (_isReplying && widget.parentPost != null)
              _buildParentPostPreview(),
            
            TextField(
              controller: _controller,
              maxLines: null,
              minLines: 3,
              maxLength: 280, // Twitter-like limit
              decoration: InputDecoration(
                hintText: _getHintText(),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {}); // To update button state
              },
            ),
            
            const SizedBox(height: 16),
            
            // Hashtag preview
            if (_controller.text.isNotEmpty)
              _buildHashtagPreview(),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                const Icon(Icons.location_on, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _isReplying 
                        ? 'Same location as original post'
                        : 'Location will be captured automatically',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _canPost ? _handlePost : null,
                  child: _isLoading 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_getButtonText()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getTitle() {
    if (_isEditing) return 'Edit Post';
    if (_isReplying) return 'Reply to Post';
    return 'Create Post';
  }

  String _getHintText() {
    if (_isReplying) {
      return 'Write your reply... Use #hashtags to categorize';
    }
    return 'What\'s happening? Use #hashtags to categorize your post...';
  }

  String _getButtonText() {
    if (_isEditing) return 'Update';
    if (_isReplying) return 'Reply';
    return 'Post';
  }

  Widget _buildParentPostPreview() {
    final parentPost = widget.parentPost!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Replying to ${parentPost.userName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            parentPost.content,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildHashtagPreview() {
    final hashtags = FeedService.extractHashtags(_controller.text);
    if (hashtags.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hashtags:',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: hashtags.map((hashtag) => Chip(
            label: Text('#$hashtag'),
            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            labelStyle: TextStyle(
              color: Theme.of(context).primaryColor,
              fontSize: 12,
            ),
          )).toList(),
        ),
      ],
    );
  }

  bool get _canPost => _controller.text.trim().isNotEmpty && !_isLoading;

  Future<void> _handlePost() async {
    if (!_canPost) return;

    setState(() {
      _isLoading = true;
    });

    try {
      bool success;
      if (_isEditing) {
        success = await FeedService.updatePost(
          postId: widget.post!.id,
          newContent: _controller.text.trim(),
          userId: widget.post!.userId,
        );
      } else {
        final user = widget.user!;
        final postId = await FeedService.createPost(
          content: _controller.text.trim(),
          user: user,
          parentPostId: widget.parentPost?.id,
        );
        success = postId != null;
      }

      if (success && mounted) {
        Navigator.of(context).pop();
        if (_isEditing) {
          widget.onPostUpdated?.call();
        } else if (_isReplying) {
          widget.onReplyCreated?.call();
        } else {
          widget.onPostCreated?.call();
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getSuccessMessage()),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getErrorMessage()),
            backgroundColor: Colors.red,
          ),
        );
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

  String _getSuccessMessage() {
    if (_isEditing) return 'Post updated!';
    if (_isReplying) return 'Reply posted!';
    return 'Post created!';
  }

  String _getErrorMessage() {
    if (_isEditing) return 'Failed to update post';
    if (_isReplying) return 'Failed to post reply';
    return 'Failed to create post';
  }
}
