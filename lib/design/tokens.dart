import 'package:flutter/material.dart';

import '../domain/category.dart';

/// 主题标识。UI 稿 v2 有浅色 / 深色两套，顶栏按钮切换，首次启动跟随系统。
enum AppTheme {
  dark('dark', '深色'),
  light('light', '浅色');

  const AppTheme(this.key, this.label);

  final String key;
  final String label;

  static AppTheme fromKey(String? key) =>
      key == 'light' ? AppTheme.light : AppTheme.dark;

  AppTheme get flipped =>
      this == AppTheme.light ? AppTheme.dark : AppTheme.light;
}

/// 一整套颜色令牌。
///
/// 值全部来自 UI 稿 `prototype-v2.html` 的 `:root[data-theme=...]`，
/// 一处都不许自己调 —— 设计稿改了就改这里，别在 widget 里写补偿色。
///
/// 命名沿用旧版 Palette 的语义（surface/raised/text…），这样全项目几百个
/// 引用点不用改；新稿多出来的层次（panel2 / track / seam / hl…）另加字段。
class AppColors {
  const AppColors({
    required this.light,
    required this.ground,
    required this.app,
    required this.surface,
    required this.panel2,
    required this.sunken,
    required this.raised,
    required this.rule,
    required this.control,
    required this.border,
    required this.track,
    required this.seam,
    required this.hl,
    required this.accent,
    required this.hover,
    required this.scrim,
    required this.sel,
    required this.focus,
    required this.text,
    required this.muted,
    required this.faint,
    required this.ghost,
    required this.blkText,
    required this.dim,
    required this.sleep,
    required this.selfcare,
    required this.commute,
    required this.work,
    required this.study,
    required this.exercise,
    required this.leisure,
  });

  final bool light;

  /// 窗口外的桌面底色。窗口是浮在它上面的一张圆角卡片。
  final Color ground;

  /// 窗口卡片自己的底色。
  final Color app;

  /// 主要卡片底（现在该做什么 / 各类容器）。
  final Color surface;

  /// 次级卡片底（接着是 / 两个累计小卡）。
  final Color panel2;

  /// 凹陷区底（时间轴 / 清单 / 输入框）。
  final Color sunken;

  /// 浮起控件底（分段选中项、hover 按钮）。
  final Color raised;

  final Color rule;
  final Color control;
  final Color border;

  /// 未安排 / 进度条轨道 / 环的底圈。
  final Color track;

  /// 环上相邻色块之间的缝。等于窗口底色，所以看起来是「画布透出来」。
  final Color seam;

  /// 指针与中性高亮。深色是纯白，浅色是深灰蓝。
  final Color hl;

  final Color accent;
  final Color hover;

  /// 浮层背后的压暗遮罩。浮层卡片和窗口底色本来是同一套相邻色，
  /// 不加这一层会把「底下内容」和「浮层」读成两块差不多灰的面。
  /// 深色更实（底下本来就暗），浅色用带蓝的深灰压出层次。
  final Color scrim;
  final Color sel;
  final Color focus;

  final Color text;
  final Color muted;
  final Color faint;
  final Color ghost;

  /// 色块上的任务名。深色主题用白，浅色主题用深墨（浅色块上白字读不出来）。
  final Color blkText;

  /// 编辑态里「非高亮块」压暗到的透明度。
  final double dim;

  final Color sleep;
  final Color selfcare;
  final Color commute;
  final Color work;
  final Color study;
  final Color exercise;
  final Color leisure;

  Color of(Category category) => switch (category) {
    Category.sleep => sleep,
    Category.selfcare => selfcare,
    Category.commute => commute,
    Category.work => work,
    Category.study => study,
    Category.exercise => exercise,
    Category.leisure => leisure,
  };

  /// 「未安排」不是第八个分类色，它跟轨道同色。
  Color get unplanned => track;

  /// 空档的径向细纹。用线色的浅版，不做成斜纹（斜纹会被读成某种活动）。
  /// 深色下 0.42 太淡，track 底色又只比窗口底亮一档，空档几乎看不出来；
  /// 提到 0.58 后纹理线能读出来，但仍不是第八个分类色。
  Color get unplannedHatch => control.withValues(alpha: light ? 0.55 : 0.58);

  /// 同色提亮：高亮描边取分类色自己的强调版，而不是套一圈黑白框。
  /// 深色底提亮（读作「这块亮着」），浅色底加饱和、压一点明度（读作「这块更实」）。
  /// 算法与 UI 稿的 hiStroke 一致，只是用 Flutter 的 HSLColor 实现。
  Color hiStroke(Color base) {
    final hsl = HSLColor.fromColor(base);
    return light
        ? hsl
              .withSaturation((hsl.saturation + 0.20).clamp(0.0, 1.0))
              .withLightness((hsl.lightness - 0.07).clamp(0.48, 1.0))
              .toColor()
        : hsl
              .withSaturation((hsl.saturation + 0.09).clamp(0.0, 1.0))
              .withLightness((hsl.lightness + 0.17).clamp(0.0, 0.88))
              .toColor();
  }

  /// 同色柔光：给高亮块一圈同色辉光，浅色底靠它把块「托」起来，不靠黑框。
  Color hiShadow(Color base, [double? alpha]) {
    final hsl = HSLColor.fromColor(base);
    final c = hsl
        .withSaturation((hsl.saturation + 0.08).clamp(0.0, 1.0))
        .withLightness(
          (hsl.lightness + (light ? -0.24 : 0.12)).clamp(0.0, 0.96),
        )
        .toColor();
    return c.withValues(alpha: alpha ?? (light ? 0.38 : 0.60));
  }

  /// 月历热图。**两套主题的温度方向相反**：深色越亮=越多，浅色越深=越多。
  /// 白底上把颜色提亮只会融进背景，等于没有格子。
  Color heatFill(double t) {
    final v = t.clamp(0.0, 1.0);
    if (light) {
      return Color.fromRGBO(
        (237 - v * 223).round(),
        (241 - v * 101).round(),
        (248 - v * 142).round(),
        1,
      );
    }
    return Color.fromRGBO(
      (26 + v * 8).round(),
      (38 + v * 112).round(),
      (48 + v * 68).round(),
      1,
    );
  }

  Color heatText(double t) {
    if (light) {
      return t > 0.58 ? Colors.white : (t > 0.02 ? text : ghost);
    }
    return t > 0.42 ? const Color(0xFFE8F6F1) : muted;
  }

  /// 顶部那层很淡的蓝色辉光，给纯色背景一点纵深。
  Gradient get backgroundGlow => RadialGradient(
    center: const Alignment(0, -1.15),
    radius: 1.35,
    colors: [
      light ? const Color(0x336096F0) : const Color(0x244EA8FF),
      Colors.transparent,
    ],
    stops: const [0.0, 0.72],
  );

  List<BoxShadow> get cardShadow => light
      ? [
          const BoxShadow(
            color: Color(0x0D17233A),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ]
      : [];

  List<BoxShadow> get windowShadow => light
      ? [
          const BoxShadow(
            color: Color(0x0D17233A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
          const BoxShadow(
            color: Color(0x0817233A),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ]
      : [
          const BoxShadow(
            color: Color(0x7303070E),
            blurRadius: 26,
            offset: Offset(0, 10),
          ),
          const BoxShadow(
            color: Color(0x10FFFFFF),
            blurRadius: 1,
            offset: Offset(0, 1),
          ),
        ];

  ThemeData themeData() {
    final brightness = light ? Brightness.light : Brightness.dark;
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: ground,
      colorScheme: base.colorScheme.copyWith(
        surface: app,
        onSurface: text,
        primary: accent,
        onPrimary: Colors.white,
        outline: border,
      ),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      splashFactory: NoSplash.splashFactory,
      dividerColor: rule,
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: raised,
          borderRadius: BorderRadius.circular(Radii.well),
          border: Border.all(color: border),
        ),
        textStyle: TextStyle(fontSize: 11, color: text),
      ),
    );
  }
}

// ---------------------------------------------------------------- 深色
const AppColors _darkColors = AppColors(
  light: false,
  ground: Color(0xFF0F141C),
  app: Color(0xFF161C27),
  surface: Color(0xFF1D2432),
  panel2: Color(0xFF181F2B),
  sunken: Color(0xFF131923),
  raised: Color(0xFF2D3849),
  rule: Color(0xFF28313F),
  control: Color(0xFF364152),
  border: Color(0xFF28313F),
  track: Color(0xFF2B3442),
  seam: Color(0xFF161C27),
  hl: Color(0xFFFFFFFF),
  accent: Color(0xFF4EA8FF),
  hover: Color(0xFF232C3B),
  scrim: Color(0x99050810),
  sel: Color(0xFF2B3647),
  focus: Color(0xFF3E5C7E),
  text: Color(0xFFEEF3FB),
  muted: Color(0xFFAEBACD),
  faint: Color(0xFF8A99AE),
  ghost: Color(0xFF6B7891),
  blkText: Color(0xFFFFFFFF),
  dim: 0.20,
  sleep: Color(0xFF4E4CA6),
  work: Color(0xFF3E86D8),
  study: Color(0xFF1EC08D),
  exercise: Color(0xFFEE7A32),
  selfcare: Color(0xFF6B7789),
  commute: Color(0xFFC3912C),
  leisure: Color(0xFFBC5580),
);

// ---------------------------------------------------------------- 浅色
const AppColors _lightColors = AppColors(
  light: true,
  ground: Color(0xFFE9EEF7),
  app: Color(0xFFFFFFFF),
  surface: Color(0xFFF3F7FE),
  panel2: Color(0xFFF5F9FE),
  sunken: Color(0xFFFBFCFE),
  raised: Color(0xFFFFFFFF),
  rule: Color(0xFFDFE7F3),
  control: Color(0xFFC9D6E9),
  border: Color(0xFFDFE7F3),
  track: Color(0xFFD8E1F0),
  seam: Color(0xFFFFFFFF),
  hl: Color(0xFF3B4658),
  accent: Color(0xFF2F6FEB),
  hover: Color(0xFFEFF4FB),
  scrim: Color(0x661B2A45),
  sel: Color(0xFFE3EBF8),
  focus: Color(0xFFA6C1EA),
  text: Color(0xFF1B2231),
  muted: Color(0xFF4B5768),
  faint: Color(0xFF77839A),
  ghost: Color(0xFF9AA5B7),
  blkText: Color(0xFF16202E),
  dim: 0.30,
  sleep: Color(0xFFA6A3EE),
  work: Color(0xFF8ABBF0),
  study: Color(0xFF4FD3A6),
  exercise: Color(0xFFF5A268),
  selfcare: Color(0xFFB2BDCE),
  commute: Color(0xFFE8C578),
  leisure: Color(0xFFF0A3C3),
);

/// 全局调色板门面。
///
/// 之所以是「可切换的静态门面」而不是 InheritedWidget：全项目几百个引用点
/// 都写成 `Palette.text` / `Palette.of(c)`，改成 context 依赖要动所有文件，
/// 收益却只是「更 Flutter 一点」。主题是全局行为，切一次整套树重建一次，
/// 静态门面足够，而且 CustomPainter 里也能直接读（画家拿不到 context）。
abstract final class Palette {
  static AppColors _active = _darkColors;

  static AppColors get active => _active;
  static bool get isLight => _active.light;

  static AppTheme get theme => _active.light ? AppTheme.light : AppTheme.dark;

  /// 切换主题。调用方负责紧接着触发一次重建（setState / pumpWidget）。
  static void setTheme(AppTheme theme) =>
      _active = theme == AppTheme.light ? _lightColors : _darkColors;

  static Color get ground => _active.ground;
  static Color get app => _active.app;
  static Color get surface => _active.surface;
  static Color get panel2 => _active.panel2;
  static Color get sunken => _active.sunken;
  static Color get raised => _active.raised;
  static Color get rule => _active.rule;
  static Color get control => _active.control;
  static Color get border => _active.border;
  static Color get track => _active.track;
  static Color get seam => _active.seam;
  static Color get hl => _active.hl;
  static Color get accent => _active.accent;
  static Color get hover => _active.hover;
  static Color get scrim => _active.scrim;
  static Color get sel => _active.sel;
  static Color get focus => _active.focus;
  static Color get text => _active.text;
  static Color get muted => _active.muted;
  static Color get faint => _active.faint;
  static Color get ghost => _active.ghost;
  static Color get blkText => _active.blkText;
  static Color get unplanned => _active.unplanned;
  static Color get unplannedHatch => _active.unplannedHatch;
  static double get dim => _active.dim;

  static Color get sleep => _active.sleep;
  static Color get selfcare => _active.selfcare;
  static Color get commute => _active.commute;
  static Color get work => _active.work;
  static Color get study => _active.study;
  static Color get exercise => _active.exercise;
  static Color get leisure => _active.leisure;

  static Color of(Category category) => _active.of(category);
  static Color hiStroke(Color base) => _active.hiStroke(base);
  static Color hiShadow(Color base, [double? alpha]) =>
      _active.hiShadow(base, alpha);
  static Color heatFill(double t) => _active.heatFill(t);
  static Color heatText(double t) => _active.heatText(t);
  static List<BoxShadow> get cardShadow => _active.cardShadow;
  static List<BoxShadow> get windowShadow => _active.windowShadow;
  static Gradient get backgroundGlow => _active.backgroundGlow;
  static ThemeData themeData() => _active.themeData();
}

/// 字号阶梯。按 UI 稿 v2 收紧了一档（原来 32 的 hero 在新稿里是 25）。
///
/// 全部是 getter 不是 const —— 颜色必须跟着主题走，
/// 写成 static const 会在编译期把深色文字色焊死，切到浅色就一片糊。
abstract final class TypeScale {
  // 不指定字体族：交给系统默认（Windows 是 Segoe UI + 微软雅黑回退，
  // macOS 是 SF/PingFang，安卓是 Roboto/思源）。写死字体会让另外两端变丑。

  static TextStyle get hero => TextStyle(
    fontSize: 25,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: Palette.text,
    letterSpacing: -0.2,
  );

  static TextStyle get kpi => TextStyle(
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: Palette.text,
  );

  static TextStyle get title => TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: Palette.text,
  );

  static TextStyle get section => TextStyle(
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: Palette.text,
  );

  static TextStyle get body =>
      TextStyle(fontSize: 13, height: 1.45, color: Palette.text);

  static TextStyle get bodyMuted =>
      TextStyle(fontSize: 13, height: 1.45, color: Palette.muted);

  static TextStyle get label =>
      TextStyle(fontSize: 12, height: 1.4, color: Palette.muted);

  static TextStyle get labelSmall =>
      TextStyle(fontSize: 11, height: 1.35, color: Palette.faint);

  /// 卡片上的小标题，带一点字距。UI 稿里「现在该做什么 / 接着是」用这个。
  static TextStyle get cardLabel => TextStyle(
    fontSize: 11,
    height: 1.4,
    letterSpacing: 0.6,
    color: Palette.faint,
  );

  /// 数字统一用等宽数位，避免时间跳动时左右抖。
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];
}

abstract final class Radii {
  static const double window = 16;
  static const double card = 13;
  static const double smallCard = 11;
  static const double well = 9;
  static const double chip = 7;
  static const double pill = 999;
}

abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve spring = Cubic(0.34, 1.56, 0.64, 1);
}

abstract final class Spacing {
  static const double gap = 14;
  static const double pad = 18;
  static const double row = 40;
  static const double controlHeight = 32;

  /// 顶栏固定高度。
  static const double barHeight = 52;

  /// 看板的初始窗口高度：扁比例，和 UI 稿 v2 的预览图一致。
  /// 只是启动尺寸，用户之后可以自由缩放 / 最大化。
  static const double dashboardWindowHeight = 540;
}
