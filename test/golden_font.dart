import 'dart:io';

import 'package:flutter/services.dart';

/// golden 测试专用：把 Windows 自带的中文字体塞给测试环境。
///
/// flutter_test 的默认字体是 Ahem —— 每个字符都渲染成一个实心方块。
/// 不加载真字体的话，截图里所有文字都是色块，只能验几何，验不了排版。
/// 找不到字体就返回 false，让测试退回"只看几何"的模式。
const goldenFontFamily = 'RoutineReminderTestCJK';

Future<bool> loadGoldenFont() async {
  final file = File(r'C:\Windows\Fonts\simhei.ttf');
  if (!file.existsSync()) return false;
  final bytes = await file.readAsBytes();
  final loader = FontLoader(goldenFontFamily)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
  return true;
}

/// 图标字体也要加载，否则截图里所有 Icons.* 都是空心方框
/// （铃铛、删除、下拉箭头会变成一排「□」，看不出对齐对不对）。
///
/// family 必须叫 `MaterialIcons` —— 这是 IconData 里写死的名字，
/// 换成别的名字 Flutter 依然会去找默认字体，加载了也不生效。
Future<bool> loadGoldenIconFont() async {
  for (final path in _iconFontCandidates()) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
    return true;
  }
  return false;
}

List<String> _iconFontCandidates() {
  const relative =
      'bin/cache/artifacts/material_fonts/materialicons-regular.otf';
  final out = <String>[];

  final envRoot = Platform.environment['FLUTTER_ROOT'];
  if (envRoot != null) out.add('$envRoot/$relative');

  // flutter_tester 位于 <root>/bin/cache/artifacts/engine/... 下，
  // 从它所在目录一路往上找，换机器换盘符都不用改。
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    out.add('${dir.path}/$relative');
    dir = dir.parent;
  }
  return out;
}
