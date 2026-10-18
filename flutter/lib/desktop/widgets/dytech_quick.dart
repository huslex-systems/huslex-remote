// Dytech: small professional controls shared by the client and the console:
// Theme (Auto / Day / Night) and Language (English / Romanian), plus the console sidebar.
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';

class DytechQuickBar extends StatelessWidget {
  const DytechQuickBar({Key? key}) : super(key: key);

  PopupMenuItem<String> _item(String value, String label, bool selected) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        children: [
          SizedBox(
              width: 22,
              child: selected ? const Icon(Icons.check, size: 16) : null),
          Text(translate(label), style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          tooltip: translate('Theme'),
          padding: EdgeInsets.zero,
          icon: Icon(Icons.brightness_6_outlined, size: 18, color: muted),
          enabled: !isOptionFixed(kCommConfKeyTheme),
          onSelected: (v) async {
            await MyTheme.changeDarkMode(MyTheme.themeModeFromString(v));
          },
          itemBuilder: (_) {
            final cur = MyTheme.getThemeModePreference().toShortString();
            return [
              _item('system', 'Auto', cur == 'system'),
              _item('light', 'Day', cur == 'light'),
              _item('dark', 'Night', cur == 'dark'),
            ];
          },
        ),
        PopupMenuButton<String>(
          tooltip: translate('Language'),
          padding: EdgeInsets.zero,
          icon: Icon(Icons.language, size: 18, color: muted),
          enabled: !isOptionFixed(kCommConfKeyLang),
          onSelected: (v) async {
            await bind.mainSetLocalOption(key: kCommConfKeyLang, value: v);
            reloadAllWindows();
            bind.mainChangeLanguage(lang: v);
          },
          itemBuilder: (_) {
            var cur = bind.mainGetLocalOption(key: kCommConfKeyLang);
            if (cur != 'ro') cur = 'en';
            return [
              _item('en', 'English', cur == 'en'),
              _item('ro', 'Română', cur == 'ro'),
            ];
          },
        ),
      ],
    );
  }
}

/// Discreet "by Dytech" signature.
class DytechByLine extends StatelessWidget {
  const DytechByLine({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Text('by Dytech',
        style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.6,
            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7)));
  }
}

/// Left side of the console: brand, section and quick controls.
class DytechConsoleSidebar extends StatelessWidget {
  const DytechConsoleSidebar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 200,
      color: scheme.background,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            loadIcon(34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(translate('Remote Console'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MyTheme.accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.desktop_windows_outlined, size: 18),
              const SizedBox(width: 10),
              Text(translate('Stations'), style: const TextStyle(fontSize: 13)),
            ]),
          ),
          const Spacer(),
          const Divider(height: 20),
          Row(children: const [
            DytechQuickBar(),
            Spacer(),
            DytechByLine(),
          ]),
        ],
      ),
    );
  }
}
