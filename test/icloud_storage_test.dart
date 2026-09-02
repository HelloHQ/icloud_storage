import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage/icloud_storage.dart';
import 'package:icloud_storage/icloud_storage_platform_interface.dart';
import 'package:icloud_storage/icloud_storage_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockIcloudStoragePlatform
    with MockPlatformInterfaceMixin
    implements ICloudStoragePlatform {
  final List<String> _calls = [];
  List<String> get calls => _calls;

  String _moveToRelativePath = '';
  String get moveToRelativePath => _moveToRelativePath;

  String _uploadDestinationRelativePath = '';
  String get uploadDestinationRelativePath => _uploadDestinationRelativePath;

  @override
  Future<List<ICloudFile>> gather({
    required String containerId,
    StreamHandler<List<ICloudFile>>? onUpdate,
  }) async {
    return [];
  }

  @override
  Future<void> upload(
      {required String containerId,
      required String filePath,
      required String destinationRelativePath,
      StreamHandler<double>? onProgress}) async {
    _uploadDestinationRelativePath = destinationRelativePath;
    _calls.add('upload');
  }

  @override
  Future<void> download(
      {required String containerId,
      required String relativePath,
      required String destinationFilePath,
      StreamHandler<double>? onProgress}) async {
    _calls.add('download');
  }

  @override
  Future<void> delete(
      {required String containerId, required String relativePath}) async {
    _calls.add('delete');
  }

  @override
  Future<void> move(
      {required String containerId,
      required String fromRelativePath,
      required String toRelativePath}) async {
    _moveToRelativePath = toRelativePath;
    _calls.add('move');
  }
}

void main() {
  final ICloudStoragePlatform initialPlatform = ICloudStoragePlatform.instance;

  test('$MethodChannelICloudStorage is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelICloudStorage>());
  });

  group('ICloudStorage static functions:', () {
    const containerId = 'containerId';
    MockIcloudStoragePlatform fakePlatform = MockIcloudStoragePlatform();
    ICloudStoragePlatform.instance = fakePlatform;

    test('gather', () async {
      expect(await ICloudStorage.gather(containerId: containerId), []);
    });

    group('upload tests:', () {
      test('upload without destinationRelativePath specified', () async {
        await ICloudStorage.upload(
            containerId: containerId, filePath: '/dir/file');
        expect(fakePlatform.uploadDestinationRelativePath, 'file');
        expect(fakePlatform.calls.last, 'upload');
      });

      test('upload with destinationRelativePath specified', () async {
        await ICloudStorage.upload(
            containerId: containerId,
            filePath: '/dir/file',
            destinationRelativePath: 'destFile');
        expect(fakePlatform.uploadDestinationRelativePath, 'destFile');
        expect(fakePlatform.calls.last, 'upload');
      });

      test('upload with invalid filePath', () async {
        expect(
          () async => await ICloudStorage.upload(
              containerId: containerId, filePath: ''),
          throwsException,
        );
      });

      test('upload with invalid destinationRelativePath - 2 slahes', () async {
        expect(
          () async => await ICloudStorage.upload(
              containerId: containerId,
              filePath: 'dir/file',
              destinationRelativePath: 'dir//file'),
          throwsException,
        );
      });

      test('upload with invalid destinationRelativePath - dots in front',
          () async {
        expect(
          () async => await ICloudStorage.upload(
              containerId: containerId,
              filePath: 'dir/file',
              destinationRelativePath: '..file'),
          throwsException,
        );
      });

      test('upload with invalid destinationRelativePath - colon', () async {
        expect(
          () async => await ICloudStorage.upload(
              containerId: containerId,
              filePath: 'dir/file',
              destinationRelativePath: 'dir:file'),
          throwsException,
        );
      });
    });

    group('download tests:', () {
      test('download', () async {
        await ICloudStorage.download(
          containerId: containerId,
          relativePath: 'file',
          destinationFilePath: '/dir/file',
        );
        expect(fakePlatform.calls.last, 'download');
      });

      test('download with invalid relativePath', () async {
        expect(
          () async => await ICloudStorage.download(
            containerId: containerId,
            relativePath: 'file/',
            destinationFilePath: 'dir/file',
          ),
          throwsException,
        );
      });

      test('download with empty destinationFilePath', () async {
        expect(
          () async => await ICloudStorage.download(
            containerId: containerId,
            relativePath: 'file',
            destinationFilePath: '',
          ),
          throwsException,
        );
      });

      test('download with invalid destinationFilePath', () async {
        expect(
          () async => await ICloudStorage.download(
            containerId: containerId,
            relativePath: 'file',
            destinationFilePath: 'dir/file/',
          ),
          throwsException,
        );
      });
    });

    group('delete tests:', () {
      test('delete', () async {
        await ICloudStorage.delete(
            containerId: containerId, relativePath: 'file');
        expect(fakePlatform.calls.last, 'delete');
      });

      test('delete with invalid relativePath', () async {
        expect(
          () async => await ICloudStorage.delete(
              containerId: containerId, relativePath: 'dir//file'),
          throwsA(isA<InvalidArgumentException>()),
        );
      });
    });

    group('move tests:', () {
      test('move', () async {
        await ICloudStorage.move(
            containerId: containerId,
            fromRelativePath: 'from',
            toRelativePath: 'to');
        expect(fakePlatform.calls.last, 'move');
      });

      test('move with invalid fromRelativePath', () async {
        expect(
          () async => await ICloudStorage.move(
              containerId: containerId,
              fromRelativePath: '.hidden',
              toRelativePath: 'to'),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('move with invalid toRelativePath', () async {
        expect(
          () async => await ICloudStorage.move(
              containerId: containerId,
              fromRelativePath: 'from',
              toRelativePath: 'dir:file'),
          throwsA(isA<InvalidArgumentException>()),
        );
      });
    });

    group('rename tests:', () {
      test('rename', () async {
        await ICloudStorage.rename(
          containerId: containerId,
          relativePath: 'dir/file1',
          newName: 'file2',
        );
        expect(fakePlatform.moveToRelativePath, 'dir/file2');
      });

      test('rename with invalid relativePath', () async {
        expect(
          () async => await ICloudStorage.rename(
              containerId: containerId,
              relativePath: 'dir//file1',
              newName: 'file2'),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('rename with a newName that is a path, not a name', () async {
        expect(
          () async => await ICloudStorage.rename(
              containerId: containerId,
              relativePath: 'dir/file1',
              newName: 'sub/file2'),
          throwsA(isA<InvalidArgumentException>()),
        );
      });

      test('rename with an empty newName', () async {
        expect(
          () async => await ICloudStorage.rename(
              containerId: containerId, relativePath: 'dir/file1', newName: ''),
          throwsA(isA<InvalidArgumentException>()),
        );
      });
    });

    test('InvalidArgumentException names the offending argument', () {
      expect(
        InvalidArgumentException('invalid newName').toString(),
        'InvalidArgumentException: invalid newName',
      );
    });
  });
}
