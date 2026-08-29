import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage/models/icloud_file.dart';

/// Builds the map shape the native side sends up through the `gather` channel.
/// [downloadStatus] is the only field the tests below vary.
Map<dynamic, dynamic> nativeFileMap({
  String downloadStatus =
      'NSMetadataUbiquitousItemDownloadingStatusNotDownloaded',
}) =>
    {
      'relativePath': 'dir/file',
      'sizeInBytes': 100,
      'creationDate': 1.0,
      'contentChangeDate': 2.0,
      'isDownloading': false,
      'downloadStatus': downloadStatus,
      'isUploading': false,
      'isUploaded': true,
      'hasUnresolvedConflicts': false,
    };

void main() {
  group('ICloudFile.fromMap download status mapping:', () {
    test('maps NotDownloaded', () {
      final file = ICloudFile.fromMap(nativeFileMap(
          downloadStatus:
              'NSMetadataUbiquitousItemDownloadingStatusNotDownloaded'));
      expect(file.downloadStatus, DownloadStatus.notDownloaded);
    });

    test('maps Downloaded', () {
      final file = ICloudFile.fromMap(nativeFileMap(
          downloadStatus:
              'NSMetadataUbiquitousItemDownloadingStatusDownloaded'));
      expect(file.downloadStatus, DownloadStatus.downloaded);
    });

    test('maps Current', () {
      final file = ICloudFile.fromMap(nativeFileMap(
          downloadStatus: 'NSMetadataUbiquitousItemDownloadingStatusCurrent'));
      expect(file.downloadStatus, DownloadStatus.current);
    });

    test('throws on an unknown status key', () {
      expect(
        () => ICloudFile.fromMap(
            nativeFileMap(downloadStatus: 'SomeFutureStatusKey')),
        throwsA('NSMetadataUbiquitousItemDownloadingStatusKey is not handled'),
      );
    });
  });

  group('ICloudFile.fromMap field mapping:', () {
    test('converts the NSDate seconds-since-epoch doubles to DateTime', () {
      final file = ICloudFile.fromMap(nativeFileMap());
      expect(file.creationDate, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(file.contentChangeDate, DateTime.fromMillisecondsSinceEpoch(2000));
    });

    test('carries the remaining fields through unchanged', () {
      final file = ICloudFile.fromMap(nativeFileMap());
      expect(file.relativePath, 'dir/file');
      expect(file.sizeInBytes, 100);
      expect(file.isDownloading, false);
      expect(file.isUploading, false);
      expect(file.isUploaded, true);
      expect(file.hasUnresolvedConflicts, false);
    });
  });
}
