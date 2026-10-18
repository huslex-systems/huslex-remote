// Dytech: small professional controls shared by the client and the console:
// Theme (Auto / Day / Night) and Language (English / Romanian), plus the console sidebar.
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

const String kDytechPanelUrl = 'https://cp-remote.huslex.com';

/// Dytech release number shown in About and in the installer (the RustDesk base version stays 1.5.1).
const int kDytechBuild = 4;

/// Dialog with a QR code that opens the Remote Center on the phone (installable as an app).
void showDytechPhoneDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(translate('Phone app')),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(translate('Scan with your phone camera to open Remote Center. Then choose "Install app" or "Add to Home Screen".'),
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(10),
              child: QrImageView(
                data: kDytechPanelUrl,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () => launchUrlString(kDytechPanelUrl),
              child: const Text('cp-remote.huslex.com',
                  style: TextStyle(
                      fontSize: 13, decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: Text(translate('Close'))),
      ],
    ),
  );
}

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
        IconButton(
          tooltip: translate('Phone app'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(Icons.qr_code_2_rounded, size: 18, color: muted),
          onPressed: () => showDytechPhoneDialog(context),
        ),
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
