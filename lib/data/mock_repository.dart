import '../models/models.dart';
import 'repository.dart';

/// Mock data seeded with real title/episode identifiers observed during recon
/// (factual metadata) plus short neutral synopses written for the clone.
/// Posters/stills are null → widgets render the gradient placeholder, exactly
/// as TV Time itself does before artwork loads. Extend stage supplies real art.
class MockRepository implements ContentRepository {
  const MockRepository();

  static const _delay = Duration(milliseconds: 220);

  @override
  Future<BrandArt> brandArt(String titleId) =>
      Future.value(const BrandArt());

  /// Episode ids follow the app-wide `titleId:season:number` convention, so
  /// per-title progress (watched counts, +N ahead, history grouping) works on
  /// mock data exactly as it does on live TVDB data.
  EpisodeRef _ep(String owner, int s, int n, String title,
          {int? abs, bool watched = false, DateTime? air, double? rating}) =>
      EpisodeRef(
        id: '$owner:$s:$n',
        season: s,
        number: n,
        absoluteNumber: abs,
        title: title,
        watched: watched,
        airDate: air,
        rating: rating,
        synopsis: 'Episode $n of season $s.',
      );

  MediaTitle _yourLieInApril() => MediaTitle(
        id: '279830',
        kind: MediaKind.show,
        name: 'Your Lie in April',
        yearLine: '2014 - 2015',
        metaLine: '1 season • Ended • Fuji TV',
        genres: const ['Drama', 'Animation', 'Anime', 'Romance', 'Musical'],
        synopsis:
            'A young pianist who lost the ability to hear his own playing '
            'meets a free-spirited violinist who pulls him back toward music.',
        scorePercent: 98,
        starRating: 4.9,
        addedByCount: 305,
        cast: const [
          CastMember(name: 'Natsuki Hanae', role: 'Kousei Arima'),
          CastMember(name: 'Risa Taneda', role: 'Kaori Miyazono'),
          CastMember(name: 'Ayane Sakura', role: 'Tsubaki Sawabe'),
          CastMember(name: 'Ryota Osaka', role: 'Ryouta Watari'),
          CastMember(name: 'Yuki Kaji', role: 'Takeshi Aiza'),
          CastMember(name: 'Saori Hayami', role: 'Emi Igawa'),
          CastMember(name: 'Ai Kayano', role: 'Nagi Aiza'),
        ],
        seasons: [
          SeasonRef(number: 1, label: 'Season 1', episodes: [
            _ep('279830', 1, 1, 'Monotone/Colorful', abs: 1, watched: true, rating: 4.7),
            _ep('279830', 1, 2, 'Friend A', abs: 2, watched: true),
            _ep('279830', 1, 3, 'Inside Spring', abs: 3, watched: true),
            _ep('279830', 1, 4, 'Set Out', abs: 4, watched: true),
            _ep('279830', 1, 5, 'Gray Skies', abs: 5, watched: true),
            _ep('279830', 1, 6, 'The Journey of Two', abs: 6, watched: true),
            _ep('279830', 1, 7, 'Voice of Rain', abs: 7, watched: true),
            _ep('279830', 1, 8, 'Twilight', abs: 8, watched: true),
            _ep('279830', 1, 9, 'Light of Life', abs: 9, watched: true),
            _ep('279830', 1, 10, 'Silent Winter', abs: 10, watched: true),
            _ep('279830', 1, 11, 'Light of Life', abs: 11, watched: true),
            _ep('279830', 1, 12, 'Twinkle Little Star', abs: 12, watched: false),
            _ep('279830', 1, 13, "Love's Sadness", abs: 13, watched: false),
          ]),
        ],
        alsoWatchedPosters: const [],
      );

  MediaTitle _zackSnyderJL() => const MediaTitle(
        id: '3d9af89d',
        kind: MediaKind.movie,
        name: "Zack Snyder's Justice League",
        yearLine: '2021',
        metaLine: '4h 2m • Action, Adventure, Fantasy',
        genres: ['Action', 'Adventure', 'Fantasy'],
        synopsis:
            'The director\'s definitive cut assembles a team of heroes to face '
            'an approaching threat of catastrophic proportions.',
        starRating: 4.5,
        addedByCount: 533,
        cast: [
          CastMember(name: 'Ben Affleck', role: 'Bruce Wayne'),
          CastMember(name: 'Ezra Miller', role: 'Barry Allen'),
          CastMember(name: 'Gal Gadot', role: 'Diana Prince'),
          CastMember(name: 'Henry Cavill', role: 'Clark Kent'),
          CastMember(name: 'Ray Fisher', role: 'Victor Stone'),
          CastMember(name: 'Jason Momoa', role: 'Arthur Curry'),
          CastMember(name: 'Jared Leto', role: 'The Joker'),
        ],
      );

  List<WatchlistEntry> _seedWatchlist() {
    MediaTitle show(String id, String name, List<String> genres) => MediaTitle(
          id: id,
          kind: MediaKind.show,
          name: name,
          genres: genres,
          metaLine: 'Ongoing',
        );
    return [
      WatchlistEntry(
        title: _yourLieInApril(),
        upNext: _yourLieInApril().seasons.first.episodes[11],
        unwatchedAhead: 10,
      ),
      WatchlistEntry(
        title: show('mha', 'My Hero Academia', const ['Anime', 'Action']),
        upNext: _ep('mha', 8, 5, "History's Greatest Villain"),
        unwatchedAhead: 6,
      ),
      WatchlistEntry(
        title: show('opm', 'One-Punch Man', const ['Anime', 'Action']),
        upNext: _ep('opm', 3, 3, 'Organism Limits'),
        unwatchedAhead: 1,
      ),
      WatchlistEntry(
        title: show('spy', 'Spy x Family', const ['Anime', 'Comedy']),
        upNext: _ep('spy', 3, 2, 'Avoid Getting Tonitrus Bolts'),
        unwatchedAhead: 11,
      ),
      WatchlistEntry(
        title: show('rag', 'Rent-a-Girlfriend', const ['Anime', 'Romance']),
        upNext: _ep('rag', 4, 4, 'Decision and Girlfriend'),
        unwatchedAhead: 20,
      ),
      WatchlistEntry(
        title: show('fri', "Frieren: Beyond Journey's End", const ['Anime']),
        upNext: _ep('fri', 2, 1, 'Shall We Go, Then?'),
        unwatchedAhead: 9,
      ),
      WatchlistEntry(
        title: show('house', 'House', const ['Drama']),
        upNext: _ep('house', 7, 8, 'Small Sacrifices'),
        unwatchedAhead: 112,
      ),
      WatchlistEntry(
        title: show('trash', 'Trash Taste', const ['Talk']),
        upNext: _ep('trash', 2, 26, 'Last Trash Taste of 2021'),
        unwatchedAhead: 301,
      ),
    ];
  }

  @override
  Future<List<WatchlistEntry>> showWatchlist() async {
    await Future<void>.delayed(_delay);
    return _seedWatchlist();
  }

  @override
  Future<List<UpcomingItem>> showUpcoming() async {
    await Future<void>.delayed(_delay);
    const poster = '';
    const show = 'Mushoku Tensei: Jobless Reincarnation';
    return [
      UpcomingItem(
        showName: show,
        poster: poster,
        episode: _ep('mushoku', 3, 4, '水王級魔術師'),
        airTime: '5:00 PM',
        network: 'TOKYO MX',
        isLatest: true,
      ),
      for (var i = 0; i < 7; i++)
        UpcomingItem(
          showName: show,
          poster: poster,
          episode: _ep('mushoku', 3, 5 + i, 'TBA'),
          daysUntil: 12 + i * 7,
          isLatest: true,
        ),
    ];
  }

  @override
  Future<List<MediaTitle>> movieWatchlist() async {
    await Future<void>.delayed(_delay);
    MediaTitle m(String id, String name, String meta, List<String> g) => MediaTitle(
        id: id, kind: MediaKind.movie, name: name, metaLine: meta, genres: g);
    return [
      _zackSnyderJL(),
      m('aw', 'A Whisker Away', '1h 44m • Adventure, Anime, Fantasy, Romance',
          const ['Adventure', 'Anime']),
      m('pl', 'The Platform', '1h 35m • Horror, Thriller',
          const ['Horror', 'Thriller']),
      m('aa', 'Ad Astra', '2h 3m • Drama, Science Fiction',
          const ['Drama', 'Science Fiction']),
      m('ou', 'Once Upon a Time... in Hollywood', '2h 41m • Comedy, Drama',
          const ['Comedy', 'Drama']),
      m('dp', 'Dark Phoenix', '1h 54m • Action, Adventure, Fantasy',
          const ['Action', 'Adventure']),
      m('hb', 'Hellboy', '2h 0m • Action, Adventure, Fantasy',
          const ['Action', 'Adventure']),
      m('pd', 'Pokémon Detective Pikachu', '1h 45m • Action, Adventure, Comedy',
          const ['Action', 'Comedy']),
    ];
  }

  @override
  Future<MediaTitle> titleById(String id) async {
    await Future<void>.delayed(_delay);
    if (id == _zackSnyderJL().id) return _zackSnyderJL();
    return _yourLieInApril();
  }

  @override
  Future<List<Comment>> comments(String titleId) async {
    await Future<void>.delayed(_delay);
    return const [
      Comment(
          user: 'Firewire',
          date: 'so 2. 1. 2016',
          body: '10 pm : I am not gonna cry to this!\n'
              '6 am : Throws phone out of the window crying like a baby! '
              '#truestory',
          likes: 597,
          replies: 6),
      Comment(
          user: 'Alex_sea0',
          date: 'po 29. 1. 2024',
          body: "if you care about your mental health don't watch this",
          likes: 73,
          replies: 2),
      Comment(
          user: 'Siljuvia',
          date: 'so 15. 7. 2017',
          body: 'You\'ll never listen to "Twinkle twinkle little star" in the '
              'same way',
          likes: 287,
          replies: 3),
      Comment(
          user: 'DaysiLok',
          date: 'št 19. 3. 2015',
          body: 'I cried each episode. Really, It was sad and beautiful. '
              'The best anime I ever seen.',
          likes: 374,
          replies: 5),
      Comment(
          user: 'Ashour',
          date: 'so 6. 2. 2016',
          body: "I feel sorry for anyone who doesn't watch anime, and this "
              'anime in particular.',
          likes: 210,
          replies: 4),
    ];
  }

  @override
  Future<List<MediaTitle>> trending(MediaKind kind) async {
    await Future<void>.delayed(_delay);
    final names = kind == MediaKind.movie
        ? ['Obsession', 'Project Hail Mary', 'The Odyssey', 'Moana', 'Jurassic Park', 'Supergirl', 'Toy Story 5']
        : ['LEGO Ninjago', 'iCarly', 'Money Heist', 'Stray Kids', 'Shine on Me'];
    return [
      for (var i = 0; i < names.length; i++)
        MediaTitle(id: 'trend$i', kind: kind, name: names[i]),
    ];
  }

  @override
  Future<List<MediaTitle>> topForYou() async {
    await Future<void>.delayed(_delay);
    const names = [
      'LEGO Ninjago', 'Demon King Daimao', 'Forever Love', 'Shine on Me',
      'Salade Grecque', 'iCarly', 'Stray Kids', 'Money Heist',
    ];
    return [
      for (var i = 0; i < names.length; i++)
        MediaTitle(id: 'top$i', kind: MediaKind.show, name: names[i]),
    ];
  }

  @override
  Future<List<GroupInfo>> groups() async {
    await Future<void>.delayed(_delay);
    return const [
      GroupInfo(
          id: 'anime',
          name: 'Anime',
          description:
              'Settle the score, once and for all: sub or dub? Discuss your '
              'favorite anime with other TV Time fanatics! (Yes, manga purists '
              'are welcome too)',
          members: 55700,
          comments: 2940,
          joined: true),
      GroupInfo(id: 'kdrama', name: 'K-Drama', members: 47900, comments: 2550),
      GroupInfo(id: 'horror', name: 'Horror', members: 30700, comments: 1160),
      GroupInfo(id: 'sitcoms', name: 'Sitcoms', members: 25500, comments: 878),
      GroupInfo(id: 'hp', name: 'Harry Potter', members: 21200, comments: 581),
      GroupInfo(id: 'romcom', name: 'Rom-Com', members: 12100, comments: 382),
      GroupInfo(id: 'disney', name: 'Disney', members: 8930, comments: 316),
      GroupInfo(id: 'starwars', name: 'Star Wars', members: 6500, comments: 248),
    ];
  }

  @override
  Future<GroupInfo> groupById(String id) async {
    await Future<void>.delayed(_delay);
    final all = await groups();
    return all.firstWhere((g) => g.id == id,
        orElse: () => const GroupInfo(id: 'x', name: 'Group'));
  }

  @override
  Future<List<Person>> following() async {
    await Future<void>.delayed(_delay);
    const names = [
      'HMĐ', 'Anonymous', 'haruyu', 'Soni', 'HEROHERO', 'Willie', 'Ren',
      'Srey Phealong', 'TV Time', 'NinaMochnacka',
    ];
    return [
      for (var i = 0; i < names.length; i++)
        Person(
            id: 'p$i',
            name: names[i],
            followsYou: i != 6 && i != 8,
            following: true),
    ];
  }

  @override
  Future<UserProfile> profile() async {
    await Future<void>.delayed(_delay);
    return const UserProfile(
      name: 'Demo User',
      following: 11,
      followers: 18,
      comments: 39,
      bannerImages: [],
      stats: [
        StatCard(label: 'TV time', units: [
          StatUnit('5', 'MONTHS'),
          StatUnit('6', 'DAYS'),
          StatUnit('5', 'HOURS'),
        ]),
        StatCard(label: 'Episodes watched', value: '5 067'),
        StatCard(label: 'Movie time', units: [
          StatUnit('0', 'MONTHS'),
          StatUnit('12', 'DAYS'),
          StatUnit('10', 'HOURS'),
        ]),
        StatCard(label: 'Movies watched', value: '130'),
      ],
    );
  }

  @override
  Future<List<StatRow>> statTable(String key) async {
    await Future<void>.delayed(_delay);
    switch (key) {
      case 'marathons':
        return const [
          StatRow('The Boys', '5'),
          StatRow('四月は君の嘘', '2'),
          StatRow('僕のヒーローアカデミア', '1'),
          StatRow('無職転生 〜異世界行ったら本気だす〜', '1'),
          StatRow('Gen V', '1'),
        ];
      case 'genres':
        return const [
          StatRow('Drama', '67'),
          StatRow('Anime', '57'),
          StatRow('Action', '52'),
          StatRow('Animation', '47'),
          StatRow('Fantasy', '44'),
        ];
      case 'networks':
        return const [
          StatRow('Tokyo MX', '16'),
          StatRow('Netflix', '15'),
          StatRow('TV Tokyo', '10'),
          StatRow('AT-X', '8'),
          StatRow('Disney+', '6'),
        ];
      default:
        return const [];
    }
  }

  @override
  Future<List<String>> artworkUrls(String titleId,
          {required bool posters}) async =>
      const [];

  @override
  Future<List<MediaTitle>> search(String query, MediaKind? kind) async {
    await Future<void>.delayed(_delay);
    if (query.trim().isEmpty) {
      return [
        ...await trending(MediaKind.movie),
        ...await trending(MediaKind.show),
      ];
    }
    final all = [
      ...await movieWatchlist(),
      _yourLieInApril(),
    ];
    final q = query.toLowerCase();
    return all.where((t) => t.name.toLowerCase().contains(q)).toList();
  }
}
