import "package:photos/db/ml/usearch_cluster_centroid_vector_db.dart";

typedef ClusterCentroidMatches = ({
  List<(String, double)> matches,
  bool reachedCount,
});

abstract class ClusterCentroidVectorDB {
  static ClusterCentroidVectorDB get instance =>
      UsearchClusterCentroidVectorDB.instance;
  static ClusterCentroidVectorDB get localGalleryInstance =>
      UsearchClusterCentroidVectorDB.localGalleryInstance;

  Future<bool> isReady();
  Future<void> warmup();
  Future<List<List<(String, double)>>> bulkSearchNearestAllowed(
    List<List<double>> queries,
    Set<String> allowedClusterIDs, {
    required double maxDistance,
    int count = 10,
  });
  Future<Map<String, ClusterCentroidMatches>> bulkSearchNearestForClusters(
    Set<String> queryClusterIDs, {
    required Set<String> candidateClusterIDs,
    required int count,
    double? maxDistance,
  });
}
