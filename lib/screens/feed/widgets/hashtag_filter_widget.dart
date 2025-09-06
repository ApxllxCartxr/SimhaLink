import 'package:flutter/material.dart';

class HashtagFilterWidget extends StatelessWidget {
  final List<String> hashtags;
  final String? selectedHashtag;
  final Function(String?) onHashtagSelected;

  const HashtagFilterWidget({
    super.key,
    required this.hashtags,
    this.selectedHashtag,
    required this.onHashtagSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: hashtags.length + 1, // +1 for "All" option
        itemBuilder: (context, index) {
          if (index == 0) {
            // "All" option
            return Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: FilterChip(
                label: const Text('All'),
                selected: selectedHashtag == null,
                onSelected: (selected) {
                  onHashtagSelected(null);
                },
                backgroundColor: Colors.grey.shade200,
                selectedColor: Theme.of(context).primaryColor.withOpacity(0.3),
              ),
            );
          }

          final hashtag = hashtags[index - 1];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('#$hashtag'),
              selected: selectedHashtag == hashtag,
              onSelected: (selected) {
                onHashtagSelected(selected ? hashtag : null);
              },
              backgroundColor: Colors.grey.shade200,
              selectedColor: Theme.of(context).primaryColor.withOpacity(0.3),
            ),
          );
        },
      ),
    );
  }
}
