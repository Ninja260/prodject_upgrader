import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';

enum PackageType { dart, flutter }

/// {@template sample_command}
///
/// `project_upgrader sample`
/// A [Command] to exemplify a sub command
/// {@endtemplate}
class UpgradeCommand extends Command<int> {
  /// {@macro sample_command}
  UpgradeCommand({required Logger logger}) : _logger = logger {
    argParser
      ..addOption(
        'path',
        abbr: 'p',
        help: 'The path to the project to upgrade',
        defaultsTo: '.',
      )
      ..addFlag(
        'modify-sdk',
        abbr: 'm',
        help: 'Modify the sdk version',
      )
      ..addOption(
        'local-packages-parent',
        abbr: 'l',
        help: 'The parent path of local packages',
        // defaultsTo: 'packages',
      );
  }

  @override
  String get description =>
      'Command to upgrade the provided dart or flutter project';
  // String get description => 'A sample sub command that just prints one joke';

  @override
  String get name => 'upgrade';

  final Logger _logger;

  dynamic get sdkVersion => null;

  @override
  Future<int> run() async {
    var path = argResults?['path'].toString();

    if (path == '.') {
      path = Directory.current.path;
    } else {
      final file = File(path!);
      path = file.absolute.path;
    }
    if (!FileSystemEntity.isDirectorySync(path)) {
      _logger.err('The provided path is not a directory');
      return ExitCode.usage.code;
    }

    var packageParent = argResults?['local-packages-parent'] as String?;

    if (packageParent != null) {
      packageParent = p.join(path, packageParent);
      if (!FileSystemEntity.isDirectorySync(packageParent)) {
        _logger.err('The provided package parent path is not a directory');
        return ExitCode.usage.code;
      }
    }

    final isToModifySdk = argResults?['modify-sdk'] as bool;

    final dir = p.basename(path);
    _logger.info('Started upgrading project: $dir\n');

    if (packageParent != null) {
      final directories = await _getDirectoriesAsync(packageParent);
      for (final directory in directories) {
        await _upgradePackage(directory.absolute.path, isToModifySdk);
      }
    }

    await _upgradePackage(path, isToModifySdk);

    return ExitCode.success.code;
  }

  Future<PackageType> _getPackageTypeOfDirectory(String dir) async {
    final yamlFile = File(p.join(dir, 'pubspec.yaml'));

    if (!yamlFile.existsSync()) {
      _logger.err('No pubspec.yaml file found in $dir');
      throw Exception();
    }

    final content = await yamlFile.readAsString();
    final yamlEditor = YamlEditor(content);

    try {
      yamlEditor.parseAt(
        [
          'dependencies',
          'flutter',
        ],
      );

      return PackageType.flutter;
    } on Object catch (_) {
      return PackageType.dart;
    }
  }

  Future<List<Directory>> _getDirectoriesAsync(String initialPath) async {
    final dir = Directory(initialPath);
    final directories = <Directory>[];

    if (dir.existsSync()) {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          directories.add(entity);
        }
      }
    }

    return directories;
  }

  Future<void> _upgradePackage(String dir, bool isToModifySdk) async {
    try {
      final packageType = await _getPackageTypeOfDirectory(dir);

      if (isToModifySdk) await _modifySdk(dir);

      final baseName = p.basename(dir);

      final progress = _logger.progress('Upgrading $baseName');
      final result = await Process.run(
        switch (packageType) {
          PackageType.dart => 'dart',
          PackageType.flutter => 'flutter',
        },
        ['pub', 'upgrade', '--major-versions'],
        runInShell: true,
        workingDirectory: dir,
      );
      progress.complete('$baseName is upgraded!');

      if (result.exitCode != 0) {
        progress.fail('Failed to upgrade $baseName');
      }
    } on Object catch (e) {
      _logger.err(e.toString());
    }
  }

  Future<void> _modifySdk(String dir) async {
    final yamlFile = File(p.join(dir, 'pubspec.yaml'));

    final content = await yamlFile.readAsString();
    final yamlEditor = YamlEditor(content);

    try {
      final sdkVersion = await _getSdkVersion();

      yamlEditor.update(['environment', 'sdk'], '^$sdkVersion');
    } on Object catch (_) {}

    try {
      yamlEditor.remove(['environment', 'flutter']);
    } on Object catch (_) {
      // do nothing
    }

    await yamlFile.writeAsString(yamlEditor.toString());
  }

  Future<String> _getSdkVersion() async {
    final result = await Process.run(
      'flutter',
      ['--version'],
      runInShell: true,
    );
    final output = result.stdout.toString();

    final regExp = RegExp(r'Dart\s+([\d\.]+)');
    final Match? match = regExp.firstMatch(output);

    if (match != null) {
      // The version number is captured in group 1
      final dartVersion = match.group(1);
      return dartVersion!;
    } else {
      throw Exception();
    }
  }
}
