Map<String, Object?> ledgerDocument({bool long = false}) => {
      'schema': 1,
      'opponent': 'I-No',
      'player': 'Ky',
      'focus': ['c3', 'unknown', 'c1'],
      'ledger': {
        'total_damage': 10469,
        'replays': 12,
        'covered_by_cards': 2506,
        'categories': [
          for (final key in ['neutral', 'pressing'])
            {
              'key': key,
              'label': long
                  ? 'Hit during a very long situation with several moves and a long explanation of the damage'
                  : 'Hit in $key',
              'damage': key == 'neutral' ? 3100 : 1550,
              'events': 41,
              'share': 0.296,
              'starters': [
                for (var i = 0; i < (long ? 5 : 1); i++)
                  {
                    'move': long
                        ? 'A very long starter move name number $i'
                        : 'j.S',
                    'damage': 900,
                    'events': 9,
                    'counter_hits': 2,
                    'examples': [
                      {
                        'replay': 3,
                        'round': 2,
                        'video_time': 512.4,
                        'damage': 141
                      },
                      {
                        'replay': 4,
                        'round': 1,
                        'video_time': null,
                        'damage': 70
                      },
                      if (long)
                        {
                          'replay': 5,
                          'round': 3,
                          'video_time': 620.9,
                          'damage': 100
                        },
                    ],
                  },
              ],
              if (key == 'pressing')
                'his_moves': [
                  {'move': 'f.S', 'events': 4, 'damage': 300},
                  {'move': '2K', 'events': 2, 'damage': 50},
                ],
            },
        ],
      },
      'cards': [
        for (var i = 1; i <= 6; i++)
          {
            'id': 'c$i',
            'title': long
                ? 'Ky blocked an exceptionally long move name with a detailed description of the situation $i'
                : 'Situation $i',
            'header': long
                ? '21 times · I-No hit Ky 15 times · 1234 damage'
                : '9 times',
            'flagged': i == 2,
            'kind': i == 4 ? 'guard_crush' : 'situation',
            'flags': [
              {'kind': 'losing', 'reason': 'Repeatedly hit in this situation'}
            ],
            'answers': [
              {
                'text': 'Ky blocked',
                'count': 9,
                'got_hit': 3,
                'won': 0,
                'pressure': 5,
                'neutral': 1,
                'damage': 240
              },
              {
                'text': 'Ky attacked',
                'count': 2,
                'got_hit': 0,
                'won': 2,
                'pressure': 0,
                'neutral': 0,
                'damage': 0
              },
            ],
            'reversal_note':
                "S Vapor Thrust would have beaten I-No's next attack 15 of the 21 times Ky blocked (a blocked or baited reversal is punished).",
            'sequences': [
              {
                'id': 'c$i-s1',
                'follow_up': 'f.S',
                'answer': 'block',
                'outcome': 'hit'
              },
            ],
          },
      ],
    };

Map<String, Object?> eventDocument({bool focus = true, bool long = false}) {
  final json = ledgerDocument(long: long);
  json['focus'] = focus ? ['e2', 'c1'] : <String>[];
  final cards = json['cards'] as List;
  for (final kind in [
    'pressing',
    'wakeup',
    'guarding',
    'throw',
    'future_kind'
  ]) {
    final id = 'e${cards.length - 5}';
    cards.insert(0, {
      'id': id,
      'kind': kind,
      'title': 'I-No hit Ky out of $kind',
      'header':
          '11 times · 606 damage · 8 in startup, 1 while active, 2 in recovery',
      'lead_in_text': 'What beat Ky 6P: j.S x7, 2H x2, 2K x2',
      'count': 11,
      'damage': 606,
      'flagged': false,
      'sequences': [
        {
          'id': '$id-s1',
          'line': 'I-No j.S > Ky 6P',
          'result':
              'I-No counter-hit Ky (96 damage) · Ky 6P was on frame 5 of 9 startup',
          'recording': {'file_name': '$id.txt', 'text': 'W10', 'frames': 10},
          'clip': {'file': '$id.mp4'},
        },
      ],
    });
  }
  final ledger = json['ledger'] as Map;
  final category = (ledger['categories'] as List).first as Map;
  category['cards'] = ['missing', 'e1', 'c2', 'c5'];
  return json;
}

Map<String, Object?> trendDocument({int sets = 2}) {
  final json = eventDocument();
  for (final card in json['cards'] as List) {
    (card as Map)['trend_text'] = 'Earlier set: ${card['id']}. Now seen again.';
  }
  final previous = {
    'batch_label': 'earlier',
    'date': '2026-10-20',
    'replays': 6
  };
  json['trend'] = <String, Object?>{
    'sets': <Object?>[
      for (var i = 0; i < sets; i++)
        {
          'batch_label': 'batch-$i',
          'date': '2026-10-${(i + 1).toString().padLeft(2, '0')}',
          'replays': i == sets - 1 ? 12 : 5,
          'hp_replays': i == sets - 1 ? 12 : 0,
          'damage_per_replay': i == sets - 1 ? 872.4 : null,
          'current': i == sets - 1,
        },
    ],
    'ledger': {
      'previous': previous,
      'text': 'Damage per replay, compared with 2026-10-20 (6 replays)',
      'total': {'now': 872.4, 'before': 910.0, 'delta': -37.6},
      'categories': <Object?>[
        {
          'key': 'pressing',
          'label': 'Hit while pressing a button',
          'now': 279.8,
          'before': 301.5,
          'delta': -21.7
        },
        {
          'key': 'neutral',
          'label': 'Hit in neutral',
          'now': 20.3,
          'before': 8.0,
          'delta': 12.3
        },
        {
          'key': 'throw',
          'label': 'Thrown',
          'now': 10.0,
          'before': 10.0,
          'delta': 0.0
        },
      ],
    },
    'cards': {
      'previous': previous,
      'text': 'Cards compared with 2026-10-20 (6 replays)',
      'gone': <Object?>[
        {
          'title': "Ky blocked I-No's 5H",
          'kind': 'situation',
          'text': '5 times in 5 replays (1.0 per replay), I-No hit Ky 2 times'
        },
      ],
    },
  };
  return json;
}
