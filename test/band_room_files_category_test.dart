import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Band Room Files Category Partitioning', () {
    // Helper function that mirrors the partitioning logic in band_room_chat_screen
    Map<String, Map<String, Map<String, String>>> partitionFiles(Map<String, Map<String, String>> files) {
      final sheetMusic = <String, Map<String, String>>{};
      final videos = <String, Map<String, String>>{};
      final mp3s = <String, Map<String, String>>{};
      final other = <String, Map<String, String>>{};

      files.forEach((fileId, fileData) {
        final explicitCategory = (fileData['Category'] ?? '').toString().toUpperCase().trim();
        if (explicitCategory == 'SHEET MUSIC' || explicitCategory == 'SHEET_MUSIC') {
          sheetMusic[fileId] = fileData;
          return;
        } else if (explicitCategory == 'VIDEOS' || explicitCategory == 'VIDEO') {
          videos[fileId] = fileData;
          return;
        } else if (explicitCategory == 'MP3S' || explicitCategory == 'MP3' || explicitCategory == 'AUDIO') {
          mp3s[fileId] = fileData;
          return;
        } else if (explicitCategory.startsWith('OTHER')) {
          other[fileId] = fileData;
          return;
        }

        final fileName = (fileData['FileName'] ?? '').toLowerCase();
        if (fileName.endsWith('.mp3') ||
            fileName.endsWith('.wav') ||
            fileName.endsWith('.m4a') ||
            fileName.endsWith('.aac') ||
            fileName.endsWith('.flac') ||
            fileName.endsWith('.ogg')) {
          mp3s[fileId] = fileData;
        } else if (fileName.endsWith('.mp4') ||
            fileName.endsWith('.mov') ||
            fileName.endsWith('.avi') ||
            fileName.endsWith('.mkv') ||
            fileName.endsWith('.webm')) {
          videos[fileId] = fileData;
        } else if (fileName.endsWith('.pdf') ||
            fileName.contains('sheet') ||
            fileName.contains('score') ||
            fileName.contains('chart') ||
            fileName.endsWith('.mscz') ||
            fileName.endsWith('.musx') ||
            fileName.endsWith('.xml') ||
            fileName.endsWith('.musicxml')) {
          sheetMusic[fileId] = fileData;
        } else {
          other[fileId] = fileData;
        }
      });

      return {
        'sheetMusic': sheetMusic,
        'videos': videos,
        'mp3s': mp3s,
        'other': other,
      };
    }

    test('1. Correctly categorizes files by explicit Category tag', () {
      final files = {
        'f1': {'FileName': 'notes.txt', 'Category': 'SHEET MUSIC', 'FileUrl': 'http://url1'},
        'f2': {'FileName': 'recording.unknown', 'Category': 'VIDEOS', 'FileUrl': 'http://url2'},
        'f3': {'FileName': 'sample.raw', 'Category': 'MP3s', 'FileUrl': 'http://url3'},
        'f4': {'FileName': 'score.pdf', 'Category': 'OTHER (Pdf, Jpeg, Png...)', 'FileUrl': 'http://url4'},
      };

      final result = partitionFiles(files);
      expect(result['sheetMusic']!.containsKey('f1'), isTrue);
      expect(result['videos']!.containsKey('f2'), isTrue);
      expect(result['mp3s']!.containsKey('f3'), isTrue);
      // f4 has explicit Category 'OTHER (Pdf, Jpeg, Png...)' so it goes to other even if filename ends in .pdf
      expect(result['other']!.containsKey('f4'), isTrue);
    });

    test('2. Falls back to filename heuristics if Category is missing or empty', () {
      final files = {
        'f1': {'FileName': 'song.mp3', 'FileUrl': 'http://url1'},
        'f2': {'FileName': 'rehearsal.mp4', 'FileUrl': 'http://url2'},
        'f3': {'FileName': 'chart.pdf', 'FileUrl': 'http://url3'},
        'f4': {'FileName': 'random.xyz', 'FileUrl': 'http://url4'},
      };

      final result = partitionFiles(files);
      expect(result['mp3s']!.containsKey('f1'), isTrue);
      expect(result['videos']!.containsKey('f2'), isTrue);
      expect(result['sheetMusic']!.containsKey('f3'), isTrue);
      expect(result['other']!.containsKey('f4'), isTrue);
    });

    test('3. Handles case variations in explicit Category', () {
      final files = {
        'f1': {'FileName': 'file1', 'Category': 'sheet music'},
        'f2': {'FileName': 'file2', 'Category': 'video'},
        'f3': {'FileName': 'file3', 'Category': 'mp3'},
        'f4': {'FileName': 'file4', 'Category': 'other'},
      };

      final result = partitionFiles(files);
      expect(result['sheetMusic']!.containsKey('f1'), isTrue);
      expect(result['videos']!.containsKey('f2'), isTrue);
      expect(result['mp3s']!.containsKey('f3'), isTrue);
      expect(result['other']!.containsKey('f4'), isTrue);
    });
  });
}
