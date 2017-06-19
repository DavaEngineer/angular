import 'dart:async';

import 'package:analyzer/analyzer.dart';
import 'package:barback/barback.dart';
import 'package:angular/src/transform/common/annotation_matcher.dart';
import 'package:angular/src/transform/common/asset_reader.dart';
import 'package:angular/src/transform/common/mirror_mode.dart';

import 'codegen.dart';
import 'entrypoint_matcher.dart';
import 'rewriter.dart';

/// Finds the call to the Angular2 `ReflectionCapabilities` constructor
/// in `reflectionEntryPoint` and replaces it with a call to
/// `setupReflection` in `newEntryPoint`.
///
/// This only searches the code in `reflectionEntryPoint`, not `part`s,
/// `import`s, `export`s, etc.
Future<String> removeReflectionCapabilities(
  AssetReader reader,
  AssetId reflectionEntryPoint,
  AnnotationMatcher annotationMatcher, {
  MirrorMode mirrorMode: MirrorMode.none,
}) async {
  var code = await reader.readAsString(reflectionEntryPoint);

  var codegen = new Codegen(reflectionEntryPoint);
  return new Rewriter(code, codegen,
          new EntrypointMatcher(reflectionEntryPoint, annotationMatcher),
          mirrorMode: mirrorMode)
      .rewrite(parseCompilationUnit(code, name: reflectionEntryPoint.path));
}