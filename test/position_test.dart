import 'package:flutter_test/flutter_test.dart';
import 'package:myschedule/core/position.dart';

void main() {
  group('Position.between', () {
    test('first card in an empty list gets the step', () {
      expect(Position.between(null, null), Position.step);
    });

    test('dropping at the top goes before the first card', () {
      expect(Position.between(null, 1000), lessThan(1000));
    });

    test('dropping at the bottom goes after the last card', () {
      expect(Position.between(1000, null), greaterThan(1000));
    });

    test('dropping between two cards lands strictly between them', () {
      final p = Position.between(1000, 2000);
      expect(p, greaterThan(1000));
      expect(p, lessThan(2000));
    });

    test('repeated drops into the same gap keep ordering', () {
      // Simulates dragging into the same slot over and over, which is the
      // case that eventually exhausts double precision.
      var prev = 1000.0;
      const next = 2000.0;
      final seen = <double>[];
      for (var i = 0; i < 20; i++) {
        final p = Position.between(prev, next);
        expect(p, greaterThan(prev), reason: 'drop $i must stay after its predecessor');
        expect(p, lessThan(next));
        seen.add(p);
        prev = p;
      }
      // Ordering is preserved across the whole run.
      final sorted = [...seen]..sort();
      expect(seen, sorted);
    });
  });

  group('Position.needsRebalance', () {
    test('is false at the ends of a list', () {
      expect(Position.needsRebalance(null, 1000), isFalse);
      expect(Position.needsRebalance(1000, null), isFalse);
    });

    test('is false for a normal gap', () {
      expect(Position.needsRebalance(1000, 2000), isFalse);
    });

    test('is true once neighbours are too close to split', () {
      expect(Position.needsRebalance(1000, 1000.00001), isTrue);
    });

    test('becomes true after enough subdivisions of one gap', () {
      var prev = 1000.0;
      const next = 1000.1;
      var triggered = false;
      for (var i = 0; i < 60 && !triggered; i++) {
        if (Position.needsRebalance(prev, next)) {
          triggered = true;
          break;
        }
        prev = Position.between(prev, next);
      }
      expect(triggered, isTrue, reason: 'a list must eventually ask to be renumbered');
    });
  });

  group('Position.rebalanced', () {
    test('spaces positions evenly and in order', () {
      final positions = Position.rebalanced(5);
      expect(positions, hasLength(5));
      expect(positions.first, Position.step);
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i], greaterThan(positions[i - 1]));
      }
    });

    test('handles an empty list', () {
      expect(Position.rebalanced(0), isEmpty);
    });
  });
}
