import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/block_reason_label.dart';

void main() {
  test('keyword block shows category and how', () {
    expect(
      blockReasonLabel({'blockSource': 'keyword', 'category': 'adult'}),
      'adult (keyword match)',
    );
  });

  test('list block shows the dataset category', () {
    expect(
      blockReasonLabel({'blockSource': 'list', 'category': 'dangerous_material'}),
      'dangerous material (exact match)',
    );
  });

  test('AI block is labelled AI-detected', () {
    expect(
      blockReasonLabel({'blockSource': 'ai', 'category': 'gambling'}),
      'gambling (AI-detected)',
    );
  });

  test("guardian's own block has no category", () {
    expect(blockReasonLabel({'blockSource': 'parent_rule'}), 'your block list');
  });

  test('app blocks and older entries have no reason', () {
    expect(blockReasonLabel({'packageName': 'com.zhiliaoapp.musically'}), isNull);
    expect(blockReasonLabel({'blockSource': 'something_new'}), isNull);
  });

  test('schedule blocks name the schedule', () {
    expect(
      blockReasonLabel({'blockSource': 'schedule', 'category': 'bedtime'}),
      'bedtime (schedule)',
    );
  });
}
