import 'dart:io';

import 'package:logging/logging.dart';
import 'package:term_glyph/term_glyph.dart';
import 'package:test/test.dart';

import 'test_util.dart';

void main() async {
  const directory = 'test/info_test_data';
  ascii = false; // force unicode glyphs

  await for (final infoFile in Directory(directory).list(recursive: true).where((f) => f.path.endsWith('.expected')).cast<File>()) {
    final sourceFile = File(infoFile.path.replaceFirst('.expected', '.dart'));
    String? firstLog;
    testCompile(
      'log from compile $sourceFile',
      sourceFile,
      completion(predicate((_) {
        return firstLog?.normalizeLineEndings() == infoFile.readAsStringSync().normalizeLineEndings();
      })),
      onLog: (record) {
        // build_runner prefixes every builder log with a "Generating ... on
        // <file>:\n" builder-context line; the generator's own message follows
        // it. Progress-reporting noise ("Running X", "[generate (n)] ...") uses
        // the same prefix but has no such continuation, so skip those.
        if (firstLog == null && record.level == Level.INFO && record.message.contains('\n')) {
          final message = record.message.split('\n').skip(1).join('\n');
          if (message.trim().isNotEmpty && !message.startsWith('[generate') && !message.startsWith('Running ')) {
            firstLog = message;
          }
        }
      },
    );
  }
}
