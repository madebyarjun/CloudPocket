import 'package:flutter/material.dart';
import 'package:cloud_pocket/ui/theme.dart';

const cpMotionCurve = Cubic(0.32, 0.72, 0.0, 1.0);

class CpSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<CloudPocketColors>() ?? CloudPocketColors.light;
        final viewInsets = MediaQuery.of(ctx).viewInsets;

        return Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: viewInsets.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 38x5 Grabber
                    Center(
                      child: Container(
                        width: 38,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: colors.thumb,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                    builder(ctx),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CpHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String description;
  final String? helpLinkText;
  final VoidCallback? onHelpTap;

  const CpHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.description,
    this.helpLinkText,
    this.onHelpTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: colors.label,
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colors.fill,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.close_rounded, size: 16, color: colors.label2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: TextStyle(
            fontSize: 15,
            height: 1.35,
            color: colors.label2,
            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
          ),
        ),
        if (helpLinkText != null && onHelpTap != null) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onHelpTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.fill,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.help_outline_rounded, size: 14, color: colors.blue),
                  const SizedBox(width: 6),
                  Text(
                    helpLinkText!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.label,
                      fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class CpFieldItem {
  final TextEditingController controller;
  final String hint;
  final String? helperText;
  final IconData icon;
  final Color? iconColor;
  final Color? iconBg;
  final bool obscureText;
  final TextInputType keyboardType;
  final Widget? suffixIcon;
  final double suffixWidth;
  final ValueChanged<String>? onChanged;

  const CpFieldItem({
    required this.controller,
    required this.hint,
    this.helperText,
    required this.icon,
    this.iconColor,
    this.iconBg,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
    this.suffixWidth = 44,
    this.onChanged,
  });
}

class CpFieldGroup extends StatelessWidget {
  final List<CpFieldItem> fields;
  final String? errorMessage;

  const CpFieldGroup({
    super.key,
    required this.fields,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: colors.sep,
                    indent: 48,
                  ),
                _buildFieldRow(fields[i], colors),
              ],
            ],
          ),
        ),
        // Helper texts underneath each field if provided
        for (final field in fields) ...[
          if (field.helperText != null && field.helperText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: Text(
                field.helperText!,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.label2,
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
              ),
            ),
        ],
        if (errorMessage != null && errorMessage!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              errorMessage!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.red,
                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFieldRow(CpFieldItem item, CloudPocketColors colors) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: item.iconBg ?? colors.card,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              item.icon,
              size: 17,
              color: item.iconColor ?? colors.label2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: item.controller,
              obscureText: item.obscureText,
              keyboardType: item.keyboardType,
              onChanged: item.onChanged,
              style: TextStyle(
                fontSize: 15,
                color: colors.label,
                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
              ),
              decoration: InputDecoration(
                hintText: item.hint,
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: colors.label2.withOpacity(0.8),
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (item.suffixIcon != null)
            SizedBox(
              width: item.suffixWidth,
              height: 44,
              child: Center(child: item.suffixIcon),
            ),
        ],
      ),
    );
  }
}

class CpButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isSecondary;
  final Color? backgroundColor;
  final Color? textColor;

  const CpButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isSecondary = false,
    this.backgroundColor,
    this.textColor,
  });

  @override
  State<CpButton> createState() => _CpButtonState();
}

class _CpButtonState extends State<CpButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final enabled = widget.onPressed != null && !widget.isLoading;

    final bg = widget.isSecondary
        ? (widget.backgroundColor ?? colors.fill)
        : (widget.backgroundColor ?? colors.blue);
    final fg = widget.isSecondary
        ? (widget.textColor ?? colors.label)
        : (widget.textColor ?? Colors.white);

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _isPressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _isPressed = false) : null,
      onTap: enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 500),
        curve: cpMotionCurve,
        child: Container(
          height: 52,
          width: double.infinity,
          decoration: BoxDecoration(
            color: enabled ? bg : bg.withOpacity(widget.isSecondary ? 0.5 : 0.35),
            borderRadius: BorderRadius.circular(17),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: widget.isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.text,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: enabled ? fg : fg.withOpacity(0.5),
                      fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
