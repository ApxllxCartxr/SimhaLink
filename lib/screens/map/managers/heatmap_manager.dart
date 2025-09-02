import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// HeatmapPointsManager
/// Queries recent location points for a group and exposes a stream of LatLng
class HeatmapPointsManager {
  final String groupId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot>? _sub;
  final _controller = StreamController<List<LatLng>>.broadcast();

  HeatmapPointsManager({required this.groupId});

  Stream<List<LatLng>> get pointsStream => _controller.stream;

  void start({Duration window = const Duration(minutes: 5)}) {
    _sub?.cancel();
    final cutoff = DateTime.now().subtract(window);
    _sub = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('locations')
        .where('lastUpdated', isGreaterThan: Timestamp.fromDate(cutoff))
        .snapshots()
        .listen((snap) {
      final points = <LatLng>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) points.add(LatLng(lat, lng));
      }
      _controller.add(points);
    }, onError: (_) {
      // ignore errors for POC
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _controller.close();
  }
}
