import "package:photos/db/ml/usearch_clip_vector_db.dart";
import "package:photos/services/machine_learning/semantic_search/query_result.dart";

abstract class ClipVectorDB {
  static ClipVectorDB get instance => UsearchClipVectorDB.instance;
  static ClipVectorDB get localGalleryInstance =>
      UsearchClipVectorDB.localGalleryInstance;

  Future<bool> isReady();
  Future<void> warmup();
  Future<List<QueryResult>> searchSimilaritiesWithinThreshold(
    List<double> query,
    double minimumSimilarity,
  );
  Future<Map<int, List<(int, double)>>> bulkSearchNearestForFiles(
    List<int> fileIDs, {
    required int count,
    required double maxDistance,
    required bool exact,
  });
}
