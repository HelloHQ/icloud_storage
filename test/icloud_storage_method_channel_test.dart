import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage/icloud_storage_method_channel.dart';
import 'package:icloud_storage/models/icloud_file.dart';

void main() {
  MethodChannelICloudStorage platform = MethodChannelICloudStorage();
  const MethodChannel channel = MethodChannel('icloud_storage');
  late MethodCall mockMethodCall;
  const containerId = 'containerId';

  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      mockMethodCall = methodCall;
      switch (methodCall.method) {
        case 'gather':
          return [
            {
              'relativePath': 'relativePath',
              'sizeInBytes': 100,
              'creationDate': 1.0,
              'contentChangeDate': 1.0,
              'isDownloading': true,
              'downloadStatus':
                  'NSMetadataUbiquitousItemDownloadingStatusNotDownloaded',
              'isUploading': false,
              'isUploaded': false,
              'hasUnresolvedConflicts': false,
            }
          ];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('gather tests:', () {
    test('maps meta data correctly', () async {
      final files = await platform.gather(containerId: containerId);
      expect(files.last.relativePath, 'relativePath');
      expect(files.last.sizeInBytes, 100);
      expect(
          files.last.creationDate, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(files.last.contentChangeDate,
          DateTime.fromMillisecondsSinceEpoch(1000));
      expect(files.last.isDownloading, true);
      expect(files.last.downloadStatus, DownloadStatus.notDownloaded);
      expect(files.last.isUploading, false);
      expect(files.last.isUploaded, false);
      expect(files.last.hasUnresolvedConflicts, false);
    });

    test('gather with update', () async {
      await platform.gather(
        containerId: containerId,
        onUpdate: (stream) {},
      );
      expect((mockMethodCall.arguments['containerId'] as String), containerId);
      expect(
          (mockMethodCall.arguments['eventChannelName'] as String).isNotEmpty,
          true);
    });

    test('the update stream maps native events to ICloudFile', () async {
      Stream<List<ICloudFile>>? updates;
      await platform.gather(
        containerId: containerId,
        onUpdate: (stream) => updates = stream,
      );
      final eventChannelName =
          mockMethodCall.arguments['eventChannelName'] as String;

      expect(updates, isNotNull);
      final firstEvent = updates!.first;

      // The native side pushes the same map shape `gather` returns.
      await messenger.handlePlatformMessage(
        eventChannelName,
        const StandardMethodCodec().encodeSuccessEnvelope([
          {
            'relativePath': 'streamed/file',
            'sizeInBytes': 42,
            'creationDate': 1.0,
            'contentChangeDate': 1.0,
            'isDownloading': false,
            'downloadStatus':
                'NSMetadataUbiquitousItemDownloadingStatusCurrent',
            'isUploading': false,
            'isUploaded': true,
            'hasUnresolvedConflicts': false,
          }
        ]),
        (_) {},
      );

      final files = await firstEvent;
      expect(files, hasLength(1));
      expect(files.single.relativePath, 'streamed/file');
      expect(files.single.downloadStatus, DownloadStatus.current);
    });

    test('omits a file it cannot map instead of failing the whole gather',
        () async {
      messenger.setMockMethodCallHandler(channel,
          (MethodCall methodCall) async {
        mockMethodCall = methodCall;
        if (methodCall.method != 'gather') return null;
        return [
          {
            'relativePath': 'good/file',
            'sizeInBytes': 100,
            'creationDate': 1.0,
            'contentChangeDate': 1.0,
            'isDownloading': false,
            'downloadStatus':
                'NSMetadataUbiquitousItemDownloadingStatusNotDownloaded',
            'isUploading': false,
            'isUploaded': true,
            'hasUnresolvedConflicts': false,
          },
          // Missing every field ICloudFile.fromMap requires.
          <dynamic, dynamic>{'relativePath': 'unmappable/file'},
        ];
      });

      final files = await platform.gather(containerId: containerId);
      expect(files, hasLength(1));
      expect(files.single.relativePath, 'good/file');
    });
  });

  group('upload tests:', () {
    test('upload', () async {
      await platform.upload(
        containerId: containerId,
        filePath: '/dir/file',
        destinationRelativePath: 'dest',
      );
      expect((mockMethodCall.arguments['containerId'] as String), containerId);
      expect(
          (mockMethodCall.arguments['localFilePath'] as String), '/dir/file');
      expect((mockMethodCall.arguments['cloudFileName'] as String), 'dest');
      expect((mockMethodCall.arguments['eventChannelName'] as String), '');
    });

    test('upload with onProgress', () async {
      await platform.upload(
        containerId: containerId,
        filePath: '/dir/file',
        destinationRelativePath: 'dest',
        onProgress: (stream) => {},
      );
      expect(
          (mockMethodCall.arguments['eventChannelName'] as String).isNotEmpty,
          true);
    });
  });

  group('download tests:', () {
    test('download', () async {
      await platform.download(
        containerId: containerId,
        relativePath: 'file',
        destinationFilePath: '/dir/dest',
      );
      expect((mockMethodCall.arguments['containerId'] as String), containerId);
      expect(
          (mockMethodCall.arguments['localFilePath'] as String), '/dir/dest');
      expect((mockMethodCall.arguments['cloudFileName'] as String), 'file');
      expect((mockMethodCall.arguments['eventChannelName'] as String), '');
    });

    test('upload with onProgress', () async {
      await platform.download(
        containerId: containerId,
        relativePath: 'file',
        destinationFilePath: '/dir/dest',
        onProgress: (stream) => {},
      );
      expect(
          (mockMethodCall.arguments['eventChannelName'] as String).isNotEmpty,
          true);
    });
  });

  test('delete', () async {
    await platform.delete(
      containerId: containerId,
      relativePath: 'file',
    );
    expect((mockMethodCall.arguments['containerId'] as String), containerId);
    expect((mockMethodCall.arguments['cloudFileName'] as String), 'file');
  });

  test('move', () async {
    await platform.move(
        containerId: containerId,
        fromRelativePath: 'from',
        toRelativePath: 'to');
    expect((mockMethodCall.arguments['containerId'] as String), containerId);
    expect((mockMethodCall.arguments['atRelativePath'] as String), 'from');
    expect((mockMethodCall.arguments['toRelativePath'] as String), 'to');
  });
}
