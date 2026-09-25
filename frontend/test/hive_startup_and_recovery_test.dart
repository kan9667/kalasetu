import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/storage/hive_box_manager.dart';
import 'package:kalasetu/core/storage/hive_recovery_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_startup_test_');
    HiveBoxManager.resetState();
  });

  tearDown(() async {
    await Hive.close();
    HiveBoxManager.resetState();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('HiveBoxManager Fail-Closed Non-Destructive Startup', () {
    test('Successful init opens all critical and non-critical boxes', () async {
      final report = await HiveBoxManager.init(subDir: tempDir.path);

      expect(report.isHealthy, isTrue);
      expect(report.failedBox, isNull);
      expect(report.error, isNull);
      expect(report.quarantinedPath, isNull);

      // All critical boxes must be open
      for (final boxName in HiveBoxManager.criticalBoxes) {
        expect(Hive.isBoxOpen(boxName), isTrue, reason: 'Box $boxName should be open');
      }
      expect(Hive.isBoxOpen(HiveBoxManager.boxAppSettings), isTrue);
    });

    test('Corrupted critical box triggers quarantine, never deletes, and fails closed', () async {
      // Simulate corrupted products_box.hive on disk
      final boxFile = File('${tempDir.path}/${HiveBoxManager.boxProducts}.hive');
      await boxFile.writeAsString('CORRUPTED_NON_HIVE_BINARY_DATA_GARBAGE');

      final report = await HiveBoxManager.init(subDir: tempDir.path);

      expect(report.isHealthy, isFalse);
      expect(report.failedBox, HiveBoxManager.boxProducts);
      expect(report.error, isNotNull);

      // Invariant: Quarantined backup must be created
      expect(report.quarantinedPath, isNotNull);
      final qFile = File(report.quarantinedPath!);
      expect(qFile.existsSync(), isTrue);
      expect(await qFile.readAsString(), 'CORRUPTED_NON_HIVE_BINARY_DATA_GARBAGE');

      // Invariant: Original file must NOT be deleted
      expect(boxFile.existsSync(), isTrue);

      // Invariant: Cannot access box when manager is in recovery state
      expect(
        () => HiveBoxManager.getBox(HiveBoxManager.boxProducts),
        throwsA(isA<StateError>()),
      );
    });

    test('Corrupted pending_sync_box triggers fail-closed quarantine', () async {
      final boxFile = File('${tempDir.path}/${HiveBoxManager.boxPendingSync}.hive');
      await boxFile.writeAsString('CORRUPTED_SYNC_DATA');

      final report = await HiveBoxManager.init(subDir: tempDir.path);

      expect(report.isHealthy, isFalse);
      expect(report.failedBox, HiveBoxManager.boxPendingSync);
      expect(report.quarantinedPath, isNotNull);
      expect(File(report.quarantinedPath!).existsSync(), isTrue);
      expect(boxFile.existsSync(), isTrue);
    });

    testWidgets('HiveRecoveryApp renders quarantine info and actionable recovery UI', (tester) async {
      const report = HiveRecoveryReport(
        isHealthy: false,
        failedBox: 'products_box',
        error: 'HiveError: Corrupted box header',
        quarantinedPath: '/tmp/quarantine/products_box.hive.quarantine_2026-09-14',
      );

      await tester.pumpWidget(const HiveRecoveryApp(report: report));
      await tester.pumpAndSettle();

      expect(find.text('Data Protection Mode Active'), findsOneWidget);
      expect(find.text('डेटा सुरक्षा मोड सक्रिय है'), findsOneWidget);
      expect(find.text('products_box'), findsOneWidget);
      expect(find.text('/tmp/quarantine/products_box.hive.quarantine_2026-09-14'), findsOneWidget);
      expect(find.text('Copy Quarantine File Path'), findsOneWidget);
      expect(find.text('Close App Safely'), findsOneWidget);
    });
  });
}
