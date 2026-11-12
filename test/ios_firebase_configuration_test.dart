import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _plistName = 'GoogleService-Info.plist';
const _projectPath = 'ios/Runner.xcodeproj/project.pbxproj';
const _objectId = '[A-F0-9]{24}';

Iterable<RegExpMatch> _objects(String project, String section) {
  final start = '/* Begin $section section */';
  final end = '/* End $section section */';
  final contents = project
      .split(start)
      .singleWhere((part) => part.contains(end))
      .split(end)
      .first;
  return RegExp(
    '^\\s*($_objectId)(?: /\\*[^\\r\\n]*\\*/)? = \\{(.*?)\\};',
    multiLine: true,
    dotAll: true,
  ).allMatches(contents);
}

List<String> _ids(String object, String field) {
  final list = RegExp(
    '\\b$field = \\((.*?)\\);',
    dotAll: true,
  ).firstMatch(object)!.group(1)!;
  final withoutComments = list.replaceAll(RegExp(r'/\*.*?\*/'), '');
  return RegExp(
    _objectId,
  ).allMatches(withoutComments).map((match) => match.group(0)!).toList();
}

void main() {
  test('Runner copies exactly one Firebase configuration plist', () {
    expect(File('ios/Runner/$_plistName').existsSync(), isTrue);
    final project = File(_projectPath).readAsStringSync();
    final references = _objects(project, 'PBXFileReference').where((match) {
      final path = RegExp(r'\bpath = "?([^";]+)"?;').firstMatch(match[2]!);
      return path?[1]?.split('/').last == _plistName;
    });
    expect(references, hasLength(1));
    final reference = references.single;
    final referenceId = reference[1]!;
    expect(reference[2], contains('path = $_plistName;'));
    expect(reference[2], contains('sourceTree = "<group>";'));

    final groups = _objects(project, 'PBXGroup');
    final runnerGroup = groups.singleWhere(
      (match) => match[2]!.contains('path = Runner;'),
    );
    expect(
      _ids(runnerGroup[2]!, 'children').where((id) => id == referenceId),
      hasLength(1),
    );
    expect(
      groups
          .expand((match) => _ids(match[2]!, 'children'))
          .where((id) => id == referenceId),
      hasLength(1),
    );

    final buildFiles = _objects(project, 'PBXBuildFile').where(
      (match) => RegExp('\\bfileRef = $referenceId\\b').hasMatch(match[2]!),
    );
    expect(buildFiles, hasLength(1));
    final buildFileId = buildFiles.single[1]!;

    final resources = {
      for (final match in _objects(project, 'PBXResourcesBuildPhase'))
        match[1]!: _ids(match[2]!, 'files'),
    };
    final targets = _objects(project, 'PBXNativeTarget');
    final runner = targets.singleWhere(
      (match) => match[2]!.contains('name = Runner;'),
    );
    final runnerTests = targets.singleWhere(
      (match) => match[2]!.contains('name = RunnerTests;'),
    );
    final runnerPhases = _ids(
      runner[2]!,
      'buildPhases',
    ).where(resources.containsKey);
    expect(runnerPhases, hasLength(1));
    final runnerResourceId = runnerPhases.single;
    expect(
      resources[runnerResourceId]!.where((id) => id == buildFileId),
      hasLength(1),
    );
    expect(
      _ids(runnerTests[2]!, 'buildPhases'),
      isNot(contains(runnerResourceId)),
    );
    expect(
      resources.values
          .expand((files) => files)
          .where((id) => id == buildFileId),
      hasLength(1),
    );
  });
}
