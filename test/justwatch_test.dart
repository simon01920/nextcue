import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:showtrack/services/justwatch_api.dart';

Map<String, Object> _node(int year, List<(String, String)> offers) => {
      'node': {
        'content': {'originalReleaseYear': year},
        'offers': [
          for (final (name, type) in offers)
            {
              'monetizationType': type,
              'standardWebURL': 'https://example.com/$name',
              'package': {'clearName': name, 'icon': '/icon/1/s100/$name.{format}'},
            },
        ],
      },
    };

void main() {
  String body(List<Map<String, Object>> edges) =>
      jsonEncode({'data': {'popularTitles': {'edges': edges}}});

  test('picks the release-year match, one offer per service, cheapest first', () {
    final b = body([
      _node(2023, [('Wrong', 'FLATRATE')]),
      _node(2008, [('Amazon', 'BUY'), ('Netflix', 'FLATRATE'), ('Amazon', 'RENT')]),
    ]);
    final offers = JustWatchApi.parseOffers(b, year: 2008);
    expect(offers.map((o) => (o.service, o.type)),
        [('Netflix', 'FLATRATE'), ('Amazon', 'RENT')]);
    expect(offers.first.iconUrl, 'https://images.justwatch.com/icon/1/s100/Netflix.png');
  });

  test('falls back to the top result, and survives empty or odd bodies', () {
    expect(JustWatchApi.parseOffers(body([_node(1999, [('A', 'FREE')])]), year: 2008)
        .single.service, 'A');
    expect(JustWatchApi.parseOffers(body([])), isEmpty);
    expect(JustWatchApi.parseOffers('{"errors":[{}]}'), isEmpty);
  });
}
