import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// First-run consent on NekoVPN's layout: the tick stays in view above the
/// buttons and unlocks «Согласен». In upstream's dialog it scrolled under the
/// dialog's buttons on a phone.
class NekoConsentBar extends StatefulWidget {
  const NekoConsentBar({
    super.key,
    required this.maxWidth,
    required this.gutter,
    required this.compact,
  });

  final double maxWidth;
  final double gutter;
  final bool compact;

  @override
  State<NekoConsentBar> createState() => _NekoConsentBarState();
}

class _NekoConsentBarState extends State<NekoConsentBar> {
  var _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final exit = ElasticButton(
      child: OutlinedButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(appLocalizations.exit),
      ),
    );
    final agree = ElasticButton(
      enabled: _acknowledged,
      child: FilledButton(
        onPressed: _acknowledged ? () => Navigator.of(context).pop(true) : null,
        child: Text(appLocalizations.agree),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SurfaceLevel.page.colorOf(context.colorScheme),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.maxWidth + widget.gutter * 2,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.gutter,
                vertical: 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  generateGroup([
                    ListItem.checkbox(
                      title: Text(appLocalizations.disclaimerAcknowledgeLabel),
                      value: _acknowledged,
                      onChanged: (value) {
                        setState(() => _acknowledged = value ?? false);
                      },
                    ),
                  ]),
                  if (widget.compact)
                    Row(
                      spacing: 12,
                      children: [
                        Expanded(child: exit),
                        Expanded(child: agree),
                      ],
                    )
                  else
                    Row(spacing: 12, children: [const Spacer(), exit, agree]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
