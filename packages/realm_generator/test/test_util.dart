import 'dart:io';

import 'package:build/build.dart';
import 'package:build_runner_core/build_runner_core.dart' show buildLog;
import 'package:build_test/build_test.dart';
import 'package:dart_style/dart_style.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:realm_generator/realm_generator.dart';
import 'package:test/test.dart';
import 'package:pub_semver/pub_semver.dart';

final _formatter = DartFormatter(
  languageVersion: Version(3, 7, 0),
  lineEnding: '\n',
);

/// Recent `build_test` versions no longer rethrow generator exceptions from
/// `testBuilder`; they're only observable as a SEVERE [LogRecord] whose
/// message is the exception's formatted `toString()`. This wraps that text so
/// tests can still assert on the formatted error output.
class GeneratorError {
  final String _formatted;
  GeneratorError(this._formatted);

  String format([bool color = false]) => _formatted;

  @override
  String toString() => _formatted;
}

/// Builder outputs are recorded under their logical [AssetId], but may be
/// written to the "hidden" on-disk location (`.dart_tool/build/generated/...`)
/// rather than the visible one. Resolve to whichever actually exists.
String _readOutput(TestReaderWriter readerWriter, AssetId id) {
  if (readerWriter.testing.exists(id)) {
    return readerWriter.testing.readString(id);
  }
  final hiddenId = AssetId('pkg', '.dart_tool/build/generated/${id.package}/${id.path}');
  return readerWriter.testing.readString(hiddenId);
}

/// Used to test both correct an erroneous compilation.
/// [source] can be a [File] or a [String].
/// [matcher] can be a [File], [String] or a [Matcher].
/// Both expected and actual output will be formatted with [DartFormatter].
@isTest
void testCompile(
  String description,
  dynamic source,
  dynamic matcher, {
  dynamic skip,
  void Function(LogRecord)? onLog,
}) {
  if (source is Iterable) {
    testCompileMany(description, source, matcher);
    return;
  }

  final assetName = source is File ? source.path : 'source.dart';
  source = source is File ? source.readAsStringSync() : source;
  if (source is! String) throw ArgumentError.value(source, 'source');

  matcher = matcher is File ? matcher.readAsStringSync() : matcher;
  if (matcher is String) {
    final source = _formatter.format(matcher);
    matcher = completion(equals(source));
  }
  if (matcher is! Matcher) throw ArgumentError.value(matcher, 'matcher');

  test(description, () async {
    generate() async {
      final readerWriter = TestReaderWriter(rootPackage: 'pkg');
      await readerWriter.testing.loadIsolateSources();
      LogRecord? severeLog;
      // build_runner's BuildLogLogger drops anything below WARNING unless
      // verbose is enabled, which would otherwise silently swallow the
      // generator's own `log.info(...)` calls (e.g. info_test.dart).
      buildLog.configuration = buildLog.configuration.rebuild((b) => b.verbose = true);
      await testBuilder(
        generateRealmObjects(),
        {'pkg|$assetName': '$source'},
        readerWriter: readerWriter,
        onLog: (log) {
          if (log.level >= Level.SEVERE) severeLog = log;
          onLog?.call(log);
        },
      );
      if (severeLog case final log?) {
        if (log.error != null) throw log.error!;
        // The generator's exception isn't preserved by the build pipeline, only its
        // formatted message ("<builder context>:\n<original message>") is logged.
        throw GeneratorError(log.message.split('\n').skip(1).join('\n'));
      }
      final output = readerWriter.testing.assetsWritten.singleWhere((id) => id.path.endsWith('.realm.dart'));
      return _formatter.format(_readOutput(readerWriter, output));
    }

    expect(generate(), matcher);
  }, skip: skip);
}

@isTest
void testCompileMany(
  String description,
  Iterable<dynamic> sources,
  dynamic matcher,
) async {
  final inputs = switch (sources) {
    Iterable<File> files => files.map((file) {
        return ('pkg|${file.path}', _formatter.format(file.readAsStringSync()));
      }),
    Iterable<String> strings => strings.indexed.map((x) {
        final (index, text) = x;
        return ('pkg|source_$index.dart', _formatter.format(text));
      }),
    _ => throw ArgumentError.value(sources, 'sources'),
  };

  matcher = switch (matcher) {
    Matcher m => m,
    Iterable<String> strings => completion(
        equals(strings.map((e) => _formatter.format(e))),
      ),
    Iterable<File> files => completion(
        equals(files.map((x) => _formatter.format(x.readAsStringSync()))),
      ),
    _ => throw ArgumentError.value(matcher, 'matcher'),
  };

  test(description, () {
    generate() async {
      final readerWriter = TestReaderWriter(rootPackage: 'pkg');
      await readerWriter.testing.loadIsolateSources();
      await testBuilder(
        generateRealmObjects(),
        Map<String, Object>.fromEntries(
          inputs.map((x) {
            final (id, source) = x;
            return MapEntry(id, source);
          }),
        ),
        readerWriter: readerWriter,
      );
      final outputs = readerWriter.testing.assetsWritten.where((id) => id.path.endsWith('.realm.dart'));
      return outputs.map((id) => _readOutput(readerWriter, id));
    }

    expect(generate(), matcher);
  });
}

final _endOfLine = RegExp(r'\r\n?|\n');

extension StringX on String {
  String normalizeLineEndings() => replaceAll(_endOfLine, '\n');
}
