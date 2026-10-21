import 'package:flutter/material.dart';

/// Qingfan desktop design language: quiet spacing, warm porcelain, dark jade.
abstract final class QStyle {
  static const ink = Color(0xFF193F34);
  static const jade = Color(0xFF31745B);
  static const secondary = Color(0xFF7C9589);
  static const canvas = Color(0xFFF8FAF7);
  static const panel = Color(0xFFF5F8F3);
  static const line = Color(0xFFE2EAE3);
  static const selected = Color(0xFFECF4ED);

  static const header = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: ink,
  );
  static const section = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    color: ink,
  );
  static const detail = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: secondary,
  );

  static ThemeData theme() {
    final seed = ColorScheme.fromSeed(
      seedColor: jade,
      brightness: Brightness.light,
      surface: canvas,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: seed,
      scaffoldBackgroundColor: Colors.transparent,
      // Noto Sans CJK SC ships with Ubuntu's fonts-noto-cjk package.
      // Other platforms use the system fallback instead of shipping fonts.
      fontFamily: 'Noto Sans CJK SC',
      fontFamilyFallback: const ['Noto Sans SC', 'sans-serif'],
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 13, height: 1.35, color: ink),
        bodyLarge: TextStyle(fontSize: 14, height: 1.35, color: ink),
        titleMedium: section,
        titleLarge: header,
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: .65),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        hintStyle: detail,
        prefixIconColor: secondary,
        suffixIconColor: secondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: jade, width: 1.2),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: section,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: secondary,
          hoverColor: selected,
          splashFactory: InkRipple.splashFactory,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: jade),
      ),
    );
  }
}

class QPanelHeader extends StatelessWidget {
  const QPanelHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: Row(
          children: [
            Text(title, style: QStyle.header),
            if (subtitle != null) ...[
              const SizedBox(width: 10),
              Text(subtitle!, style: QStyle.detail),
            ],
            const Spacer(),
            IconButton(
              tooltip: '返回时钟',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 19),
            ),
          ],
        ),
      );
}
