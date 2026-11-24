import 'package:flutter_test/flutter_test.dart';
import 'package:mhm_net5g/core/format.dart';

void main() {
  test('cycle start uses reset day', () {
    expect(cycleStart(DateTime(2026, 11, 20), 16), DateTime(2026, 11, 16));
    expect(cycleStart(DateTime(2026, 11, 10), 16), DateTime(2026, 10, 16));
    expect(lteBandMask(3), '4');
  });
}
