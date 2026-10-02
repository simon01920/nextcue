import 'package:flutter/foundation.dart';

/// Domain models. Kept storage-agnostic so the Extend stage can back them with
/// TheTVDB / AniList without touching the UI. Poster/still/banner are asset keys
/// or (later) remote URLs — the widgets don't care which.

enum MediaKind { show, movie }

@immutable
class CastMember {
  final String name;
  final String role;
  final String? photo;
  const CastMember({required this.name, required this.role, this.photo});
}

@immutable
class EpisodeRef {
  final String id;
  final int season;
  final int number;
  final int? absoluteNumber;
  final String title;
  final String? still;
  final DateTime? airDate;
  final bool watched;
  final String? synopsis;
  final double? rating;

  const EpisodeRef({
    required this.id,
    required this.season,
    required this.number,
    this.absoluteNumber,
    required this.title,
    this.still,
    this.airDate,
    this.watched = false,
    this.synopsis,
    this.rating,
  });

  String get code => 'S${_p(season)} | E${_p(number)}';
  String get codeWithAbs =>
      absoluteNumber != null ? '$code (E${_p(absoluteNumber!)})' : code;

  static String _p(int n) => n.toString().padLeft(2, '0');

  EpisodeRef copyWith({bool? watched}) => EpisodeRef(
        id: id,
        season: season,
        number: number,
        absoluteNumber: absoluteNumber,
        title: title,
        still: still,
        airDate: airDate,
        watched: watched ?? this.watched,
        synopsis: synopsis,
        rating: rating,
      );
}

@immutable
class SeasonRef {
  final int number;
  final String label;
  final List<EpisodeRef> episodes;
  const SeasonRef({
    required this.number,
    required this.label,
    required this.episodes,
  });

  int get watchedCount => episodes.where((e) => e.watched).length;
  int get total => episodes.length;
  double get progress => total == 0 ? 0 : watchedCount / total;
}

@immutable
class MediaTitle {
  final String id;
  final MediaKind kind;
  final String name;
  final String? poster;
  final String? banner;
  final String yearLine; // "2014 - 2015" or "2021"
  final String metaLine; // "1 season • Ended • Fuji TV" or "4h 2m • Action…"
  final List<String> genres;
  final String? synopsis;
  final double? scorePercent; // 98
  final double? starRating; // 4.9
  final int? addedByCount; // 305
  final List<CastMember> cast;
  final List<SeasonRef> seasons;
  final List<String> alsoWatchedPosters;

  const MediaTitle({
    required this.id,
    required this.kind,
    required this.name,
    this.poster,
    this.banner,
    this.yearLine = '',
    this.metaLine = '',
    this.genres = const [],
    this.synopsis,
    this.scorePercent,
    this.starRating,
    this.addedByCount,
    this.cast = const [],
    this.seasons = const [],
    this.alsoWatchedPosters = const [],
  });

  bool get isShow => kind == MediaKind.show;
}

/// Branding artwork for the VHS shelf: transparent clear-logo plus a
/// background/fanart still, both optional.
@immutable
class BrandArt {
  final String? clearLogo;
  final String? background;
  const BrandArt({this.clearLogo, this.background});
}

@immutable
class UpcomingItem {
  final String showName;
  final String poster;
  final EpisodeRef episode;
  final String? airTime; // "5:00 PM"
  final String? network; // "TOKYO MX"
  final int? daysUntil; // 12
  final bool isLatest;

  /// Owning title id, so rows/tiles can navigate to the series. Defaults to
  /// the prefix of the canonical episode id (`titleId:season:number`).
  final String? _titleId;
  String get titleId =>
      _titleId ?? (episode.id.contains(':') ? episode.id.split(':').first : '');

  const UpcomingItem({
    required this.showName,
    required this.poster,
    required this.episode,
    String? titleId,
    this.airTime,
    this.network,
    this.daysUntil,
    this.isLatest = false,
  }) : _titleId = titleId;
}

@immutable
class WatchlistEntry {
  final MediaTitle title;
  final EpisodeRef? upNext;
  final int unwatchedAhead; // "+10"
  const WatchlistEntry({
    required this.title,
    this.upNext,
    this.unwatchedAhead = 0,
  });
}

@immutable
class Comment {
  final String user;
  final String? avatar;
  final String date;
  final String body;
  final int likes;
  final int replies;
  const Comment({
    required this.user,
    this.avatar,
    required this.date,
    required this.body,
    this.likes = 0,
    this.replies = 0,
  });
}

@immutable
class GroupInfo {
  final String id;
  final String name;
  final String? thumb;
  final String? banner;
  final String description;
  final int members; // in thousands display handled at UI
  final int comments;
  final bool joined;
  const GroupInfo({
    required this.id,
    required this.name,
    this.thumb,
    this.banner,
    this.description = '',
    this.members = 0,
    this.comments = 0,
    this.joined = false,
  });
}

@immutable
class Person {
  final String id;
  final String name;
  final String? avatar;
  final bool followsYou;
  final bool following;
  const Person({
    required this.id,
    required this.name,
    this.avatar,
    this.followsYou = false,
    this.following = false,
  });
}

@immutable
class StatCard {
  final String label;
  final String value; // "5 067" or composite handled by widget
  final List<StatUnit> units; // for TV time 5mo 6d 5h
  const StatCard({required this.label, this.value = '', this.units = const []});
}

@immutable
class StatUnit {
  final String number;
  final String unit;
  const StatUnit(this.number, this.unit);
}

@immutable
class StatRow {
  final String label;
  final String value;
  const StatRow(this.label, this.value);
}

@immutable
class UserProfile {
  final String name;
  final String? avatar;
  final List<String> bannerImages;
  final int following;
  final int followers;
  final int comments;
  final List<StatCard> stats;
  const UserProfile({
    required this.name,
    this.avatar,
    this.bannerImages = const [],
    this.following = 0,
    this.followers = 0,
    this.comments = 0,
    this.stats = const [],
  });
}
