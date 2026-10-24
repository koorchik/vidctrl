import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/app/format.dart';
import 'package:vidctrl/l10n/app_localizations.dart';

void main() {
  final en = Formatter(lookupAppLocalizations(const Locale('en')));
  final uk = Formatter(lookupAppLocalizations(const Locale('uk')));

  group('sizes', () {
    for (final (bytes, shown) in const [
      (999, '1 KB'),
      (340000000, '340 MB'),
      (12300000, '12.3 MB'),
      (1200000000, '1.2 GB'),
      (150000000000, '150 GB'),
    ]) {
      test('$bytes bytes read $shown', () => expect(en.bytes(bytes), shown));
    }

    test('in Ukrainian with its own decimal mark and units', () {
      expect(uk.bytes(1200000000), isNot(en.bytes(1200000000)));
      expect(uk.bytes(1200000000), contains('1,2'));
    });
  });

  group('lengths', () {
    test('a clock reading, with hours only when there are some', () {
      expect(en.clock(const Duration(minutes: 2, seconds: 31)), '2:31');
      expect(
        en.clock(const Duration(hours: 1, minutes: 5, seconds: 9)),
        '1:05:09',
      );
    });

    test('a wait is never "0 seconds", and rounds to minutes', () {
      expect(en.wait(Duration.zero), en.wait(const Duration(seconds: 1)));
      expect(
        en.wait(const Duration(seconds: 89)),
        en.wait(const Duration(minutes: 1)),
      );
      expect(
        en.wait(const Duration(seconds: 91)),
        en.wait(const Duration(minutes: 2)),
      );
    });
  });

  group('change in size', () {
    test('smaller and larger by the nearest percent', () {
      expect(en.sizeChange(1000, 290), contains('71'));
      expect(en.sizeChange(1000, 3400), contains('240'));
    });

    test('only growth is called out as larger', () {
      expect(en.largerBy(1000, 3400), en.sizeChange(1000, 3400));
      expect(en.largerBy(1000, 290), isNull);
      expect(en.largerBy(1000, 1000), isNull);
    });

    test('nothing to say about a file of no size', () {
      expect(en.sizeChange(0, 100), '');
      expect(en.largerBy(0, 100), isNull);
    });

    test('tens of gigabytes do not overflow', () {
      expect(en.sizeChange(90000000000, 30000000000), en.sizeChange(9, 3));
    });
  });

  test('identical pictures score infinity', () {
    expect(en.score(double.infinity), '∞');
    expect(en.score(40.64), '40.6');
  });
}
