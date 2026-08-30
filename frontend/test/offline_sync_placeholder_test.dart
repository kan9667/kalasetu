import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalasetu/core/offline_sync/services/upload_api.dart';

void main() {
  group('offline sync placeholder behavior', () {
    test('image jobs should not complete with a fake enhanced image payload', () async {
      final api = MockUploadApi(failureRate: 0.0);
      final result = await api.uploadImage(
        file: File('test/assets/fake_image.jpg'),
        idempotencyKey: 'demo-key',
        productDraftId: 'demo-draft',
      );

      expect(result.jobId, isNotEmpty);
      expect(result.resultPayload, isNull,
          reason: 'image enhancement should stay pending until the real AI module is implemented');
    });
  });
}
