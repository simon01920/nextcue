import '../models/models.dart';

/// Repository interface — the seam the Extend stage swaps for live TVDB/AniList.
/// The UI depends only on this, never on a concrete source.
abstract class ContentRepository {
  Future<List<WatchlistEntry>> showWatchlist();
  Future<List<UpcomingItem>> showUpcoming();
  Future<List<MediaTitle>> movieWatchlist();
  Future<MediaTitle> titleById(String id);
  Future<List<Comment>> comments(String titleId);
  Future<List<MediaTitle>> trending(MediaKind kind);
  Future<List<MediaTitle>> topForYou();
  Future<List<GroupInfo>> groups();
  Future<GroupInfo> groupById(String id);
  Future<List<Person>> following();
  Future<UserProfile> profile();
  Future<List<StatRow>> statTable(String key);
  Future<List<MediaTitle>> search(String query, MediaKind? kind);

  /// Alternate artwork (poster or banner/background) URLs for the picker.
  Future<List<String>> artworkUrls(String titleId, {required bool posters}) =>
      Future.value(const []);

  /// Clear-logo + background art for the VHS favourites shelf.
  Future<BrandArt> brandArt(String titleId) =>
      Future.value(const BrandArt());
}
