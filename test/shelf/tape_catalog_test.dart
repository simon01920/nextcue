import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/data/mock_repository.dart';
import 'package:showtrack/models/models.dart';
import 'package:showtrack/shelf/labels/tape_label_data.dart';
import 'package:showtrack/shelf/shelf_layout.dart';
import 'package:showtrack/shelf/tape_catalog.dart';
import 'package:showtrack/shelf/tape_source.dart';
import 'package:showtrack/state/app_state.dart';

/// A repository whose artwork resolves from bundled assets (no network):
/// plates stand in for poster, logo, banner and fanart.
class _ArtRepo extends MockRepository {
  const _ArtRepo();

  static const poster = 'assets/plates/hero/rot_09_color.webp'; // 640 wide
  static const logo = 'assets/plates/shelf/rail_color.webp'; // 1068 wide
  static const banner = 'assets/plates/shelf/rail_uv.png'; // 1068 wide
  static const background = 'assets/plates/shelf/bay_0_color.webp'; // 1116

  @override
  Future<MediaTitle> titleById(String id) async => MediaTitle(
        id: id,
        kind: MediaKind.show,
        name: 'Arcane',
        poster: poster,
        yearLine: '2021 - 2024',
        seasons: [
          SeasonRef(number: 1, label: 'Season 1', episodes: [
            for (var n = 1; n <= 9; n++)
              EpisodeRef(id: '$id:1:$n', season: 1, number: n, title: 'E$n'),
          ]),
        ],
      );

  @override
  Future<BrandArt> brandArt(String titleId) async =>
      const BrandArt(clearLogo: logo, banner: banner, background: background);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TapeStates', () {
    test('next episode and state follow AppState like swipe-to-watch', () async {
      final s = AppState();
      final t = await const _ArtRepo().titleById('series-1');
      expect(TapeStates.stateOf(t, s).kind, TapeStateKind.notStarted);
      expect(TapeStates.nextEpisode(t, s)!.id, 'series-1:1:1');
      s.setStatus('series-1', TrackStatus.watching);
      s.setWatched('series-1:1:1', true);
      s.setWatched('series-1:1:2', true);
      final st = TapeStates.stateOf(t, s);
      expect(st.kind, TapeStateKind.watching);
      expect(st.watched, 2);
      expect(st.total, 9);
      expect(st.nextCode, 'S01 E03');
      expect(TapeStates.poseOf('series-1', s, 2), TapePose.pulled);
      s.setStatus('series-1', TrackStatus.completed);
      expect(TapeStates.stateOf(t, s).kind, TapeStateKind.completed);
      expect(TapeStates.poseOf('series-1', s, 2), TapePose.upright);
      expect(TapeStates.poseOf('movie-9', s, 0), TapePose.sealed);
      expect(TapeStates.watchedCounts(s), {'series-1': 2});
    });
  });

  group('TapeCatalog artwork', () {
    test('shelf labels get poster + logo; hero labels all four, bounded',
        () async {
      final s = AppState()..setStatus('series-art', TrackStatus.watching);
      final c = TapeCatalog(repo: const _ArtRepo(), appState: s);
      expect(c.labelKey('series-art'), 'pending');

      final shelf = (await c.labelData('series-art'))!;
      expect(shelf.data.title, 'Arcane');
      expect(shelf.data.year, '2021');
      expect(shelf.data.poster?.width, 340);
      expect(shelf.data.logo?.width, 400);
      expect(shelf.data.banner, isNull, reason: 'shelf atlases skip it');
      expect(shelf.data.background, isNull, reason: 'shelf atlases skip it');
      expect(c.labelKey('series-art'), shelf.key);

      final hero = (await c.labelData('series-art', use: LabelUse.hero))!;
      expect(hero.data.poster?.width, 640, reason: 'never upscaled past 640');
      expect(hero.data.logo?.width, 800);
      expect(hero.data.banner?.width, 760);
      expect(hero.data.background?.width, 960);
      expect(c.labelKey('series-art', use: LabelUse.hero), hero.key);
      expect(hero.key, contains(_ArtRepo.banner));
      expect(hero.key, contains(_ArtRepo.background));

      shelf.dispose();
      hero.dispose();
      expect(hero.data.background!.debugDisposed, isTrue);
      c.dispose();
    });

    test('artwork that arrives late notifies and changes the key', () async {
      final s = AppState();
      final c = TapeCatalog(repo: const _ArtRepo(), appState: s);
      await c.loadTitle('series-late');
      final arrived = Completer<void>();
      var keys = <String>{};
      c.addListener(() {
        keys.add(c.labelKey('series-late', use: LabelUse.hero));
        if (keys.last.contains(_ArtRepo.background) && !arrived.isCompleted) {
          arrived.complete();
        }
      });
      // No patience: prints without artwork now...
      final now = (await c.labelData('series-late',
          use: LabelUse.hero, patience: Duration.zero))!;
      expect(now.data.poster, isNull);
      expect(now.data.background, isNull);
      expect(now.key.split('|').skip(3), everyElement('-'));
      now.dispose();
      // ...and the key moves on as each image lands.
      await arrived.future.timeout(const Duration(seconds: 10));
      final later = (await c.labelData('series-late', use: LabelUse.hero))!;
      expect(later.data.background, isNotNull);
      expect(later.key, c.labelKey('series-late', use: LabelUse.hero));
      later.dispose();
      keys = {};
      c.dispose();
    });

    test('watch-state changes change the label key', () async {
      final s = AppState()..setStatus('series-k', TrackStatus.watching);
      final c = TapeCatalog(repo: const _ArtRepo(), appState: s);
      await c.loadTitle('series-k');
      final before = c.labelKey('series-k');
      s.setWatched('series-k:1:1', true);
      expect(c.labelKey('series-k'), isNot(before));
      expect(c.semanticsLabel('series-k'),
          'Arcane, show, watching, 1 of 9 episodes, next S01 E02');
      c.dispose();
    });
  });
}
