import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';

void main() {
  test('公告模型解析本地化内容和展示时间', () {
    final announcement = NimbusAnnouncement.fromJson({
      'id': 'announcement-1',
      'title': '维护通知',
      'body': '今晚会有短时维护。',
      'language': 'zh-CN',
      'startsAt': '2026-07-10T12:00:00.000Z',
      'endsAt': '2026-07-10T13:00:00.000Z',
      'updatedAt': '2026-07-10T11:00:00.000Z',
    });

    expect(announcement.id, 'announcement-1');
    expect(announcement.title, '维护通知');
    expect(announcement.body, '今晚会有短时维护。');
    expect(announcement.language, 'zh-CN');
    expect(announcement.startsAt?.toUtc(), DateTime.utc(2026, 7, 10, 12));
    expect(announcement.endsAt?.toUtc(), DateTime.utc(2026, 7, 10, 13));
  });
}
