import 'package:flutter_test/flutter_test.dart';
import 'package:lazynote_flutter/features/entry/command_parser.dart';
import 'package:lazynote_flutter/features/entry/command_router.dart';

void main() {
  const router = CommandRouter();

  test('returns noop intent for empty input', () {
    final intent = router.route('   ');
    expect(intent, isA<NoopIntent>());
  });

  test('routes plain text to search intent', () {
    final intent = router.route('search text');
    expect(intent, isA<SearchIntent>());

    final search = intent as SearchIntent;
    expect(search.text, 'search text');
    expect(search.limit, 10);
  });

  test('normalizes requested search limit to max 10', () {
    final intent = router.route('query', requestedSearchLimit: 50);
    final search = intent as SearchIntent;
    expect(search.limit, 10);
  });

  test('routes valid command to command intent', () {
    final intent = router.route('> task pay rent');
    expect(intent, isA<CommandIntent>());

    final command = (intent as CommandIntent).command;
    expect(command, isA<CreateTaskCommand>());
  });

  test('routes invalid command to parse error intent', () {
    final intent = router.route('> schedule 03/15/2026 18:00-17:00 test');
    expect(intent, isA<ParseErrorIntent>());

    final parseError = intent as ParseErrorIntent;
    expect(parseError.code, 'schedule_range_invalid');
  });
}
