// Dytech: installer window. Detects an existing installation and offers
// Install / Update / Reinstall / Uninstall with plain, corporate wording.
import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/widgets/dytech_quick.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' show join;
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

class InstallPage extends StatefulWidget {
  const InstallPage({Key? key}) : super(key: key);

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _InstallPageState() {
    Get.put<DesktopTabController>(tabController);
    const label = "install";
    tabController.add(TabInfo(
        key: label,
        label: label,
        closable: false,
        page: _InstallPageBody(
          key: const ValueKey(label),
        )));
  }

  @override
  void dispose() {
    super.dispose();
    Get.delete<DesktopTabController>();
  }

  @override
  Widget build(BuildContext context) {
    return DragToResizeArea(
      resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
      enableResizeEdges: windowManagerEnableResizeEdges,
      child: Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: DesktopTab(controller: tabController)),
      ),
    );
  }
}

class _InstallPageBody extends StatefulWidget {
  const _InstallPageBody({Key? key}) : super(key: key);

  @override
  State<_InstallPageBody> createState() => _InstallPageBodyState();
}

class _InstallPageBodyState extends State<_InstallPageBody>
    with WindowListener {
  static const _printerStatusTimeout = Duration(seconds: 5);

  late final TextEditingController controller;
  final RxBool startmenu = true.obs;
  final RxBool desktopicon = true.obs;
  final RxBool printer = false.obs;
  final RxBool showProgress = false.obs;
  final RxBool btnEnabled = true.obs;
  final RxBool cancelEnabled = true.obs;

  // Existing installation (null until known / not installed).
  final Rx<Map<String, dynamic>?> info = Rx<Map<String, dynamic>?>(null);
  final RxBool infoLoaded = false.obs;
  final RxString message = ''.obs;
  final RxBool messageIsError = false.obs;
  final RxBool finished = false.obs;

  // todo move to theme.
  final buttonStyle = OutlinedButton.styleFrom(
    textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
    padding: EdgeInsets.symmetric(vertical: 15, horizontal: 12),
  );

  _InstallPageBodyState() {
    controller = TextEditingController(text: bind.installInstallPath());
    final installOptions = jsonDecode(bind.installInstallOptions());
    startmenu.value = installOptions['STARTMENUSHORTCUTS'] != '0';
    desktopicon.value = installOptions['DESKTOPSHORTCUTS'] != '0';
    printer.value = installOptions['PRINTER'] == '1';
  }

  Future<void> _loadInfo() async {
    try {
      final s = await bind.mainGetCommon(key: 'dytech-install-info');
      if (s.isNotEmpty) {
        final m = jsonDecode(s);
        if (m is Map<String, dynamic>) info.value = m;
      }
    } catch (e) {
      debugPrint('install info failed: $e');
    }
    infoLoaded.value = true;
  }

  /// new | update | same | newer
  String get mode {
    final m = info.value;
    if (m == null || m['installed'] != true) return 'new';
    final inst = '${m['build'] ?? ''}';
    final cur = '${m['this_build'] ?? ''}';
    if (inst.isEmpty || cur.isEmpty) return 'update';
    final c = cur.compareTo(inst);
    if (c > 0) return 'update';
    if (c < 0) return 'newer';
    return 'same';
  }

  Future<void> _loadPrinterStatus() async {
    btnEnabled.value = false;
    showProgress.value = true;
    try {
      final status = await bind
          .mainGetCommon(key: 'is-printer-installed')
          .timeout(_printerStatusTimeout);
      printer.value = status == 'true';
      if (status != 'true' && status != 'false') {
        debugPrint('Failed to check printer installation status: $status');
      }
    } catch (e) {
      printer.value = false;
      debugPrint('Failed to check printer installation status: $e');
    } finally {
      showProgress.value = false;
      btnEnabled.value = true;
    }
  }

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
    _loadInfo();
    if (printer.value) {
      _loadPrinterStatus();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    gFFI.close();
    super.onWindowClose();
    windowManager.setPreventClose(false);
    windowManager.close();
  }

  InkWell Option(RxBool option, {String label = ''}) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => btnEnabled.value ? option.value = !option.value : null,
      child: Row(
        children: [
          Obx(
            () => Checkbox(
              visualDensity: VisualDensity(horizontal: -4, vertical: -4),
              value: option.value,
              onChanged: (v) =>
                  btnEnabled.value ? option.value = !option.value : null,
            ).marginOnly(right: 8),
          ),
          Expanded(
            child: Text(translate(label)),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, bool isDarkTheme) {
    final m = mode;
    if (m == 'new') {
      return const SizedBox.shrink();
    }
    final inst = info.value ?? {};
    late final IconData icon;
    late final String title;
    late final String detail;
    final installedBuild = '${inst['build'] ?? ''}';
    final thisBuild = '${inst['this_build'] ?? ''}';
    final version = '${inst['version'] ?? ''}';
    switch (m) {
      case 'update':
        icon = Icons.system_update_alt_rounded;
        title = translate('An older version is installed');
        detail =
            '${translate('Installed')}: $version ($installedBuild)\n${translate('This installer')}: ${inst['this_version'] ?? ''} · build $kDytechBuild ($thisBuild)';
        break;
      case 'newer':
        icon = Icons.info_outline_rounded;
        title = translate('A newer version is already installed');
        detail =
            '${translate('Installed')}: $version ($installedBuild)\n${translate('This installer')}: ${inst['this_version'] ?? ''} · build $kDytechBuild ($thisBuild)';
        break;
      default:
        icon = Icons.check_circle_outline_rounded;
        title = translate('Already installed and up to date');
        detail = '${translate('Installed')}: $version ($installedBuild)';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MyTheme.accent.withOpacity(isDarkTheme ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MyTheme.accent.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 30, color: MyTheme.accent).marginOnly(right: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(detail, style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(
                    '${translate('Install location')}: ${inst['path'] ?? controller.text}',
                    style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compat(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Row(
      children: [
        Icon(Icons.verified_outlined, size: 16, color: muted)
            .marginOnly(right: 8),
        Expanded(
          child: Text(
            translate(
                'Compatible with Windows 10 and Windows 11 (64-bit): Home, Pro, Enterprise and Education.'),
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final double em = 13;
    final isDarkTheme = MyTheme.currentThemeMode() == ThemeMode.dark;
    return Scaffold(
        backgroundColor: null,
        body: SingleChildScrollView(
          child: Obx(() {
            final m = infoLoaded.value ? mode : 'new';
            final existing = m != 'new';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    loadIcon(40).marginOnly(right: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(appName,
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          Text(
                              translate(existing
                                  ? 'Manage this installation'
                                  : 'Setup'),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 1.6 * em),
                if (existing) _statusCard(context, isDarkTheme),
                if (existing) SizedBox(height: 1.2 * em),
                Row(
                  children: [
                    Text('${translate('Installation Path')}:')
                        .marginOnly(right: 10),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        readOnly: true,
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.all(0.75 * em),
                        ),
                      ).workaroundFreezeLinuxMint().marginOnly(right: 10),
                    ),
                    if (!existing)
                      Obx(
                        () => OutlinedButton.icon(
                          icon: Icon(Icons.folder_outlined, size: 16),
                          onPressed:
                              btnEnabled.value ? selectInstallPath : null,
                          style: buttonStyle,
                          label: Text(translate('Change Path')),
                        ),
                      )
                  ],
                ).marginSymmetric(vertical: 1.2 * em),
                if (!existing) ...[
                  Option(startmenu, label: 'Create start menu shortcuts')
                      .marginOnly(bottom: 7),
                  Option(desktopicon, label: 'Create desktop icon')
                      .marginOnly(bottom: 7),
                  Option(printer, label: 'Install {$appName} Printer'),
                ],
                Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDarkTheme
                          ? Color.fromARGB(135, 87, 87, 90)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 32)
                            .marginOnly(right: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(translate('agreement_tip'))
                                .marginOnly(bottom: em),
                            InkWell(
                              hoverColor: Colors.transparent,
                              onTap: () =>
                                  launchUrlString('https://dytech.ro'),
                              child: Row(children: [
                                Icon(Icons.launch_outlined, size: 16)
                                    .marginOnly(right: 5),
                                Text(
                                  translate('End-user license agreement'),
                                  style: const TextStyle(
                                      decoration: TextDecoration.underline),
                                )
                              ]),
                            ),
                          ],
                        )
                      ],
                    )).marginSymmetric(vertical: 1.2 * em),
                Obx(() => message.value.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          message.value,
                          style: TextStyle(
                              fontSize: 13,
                              color: messageIsError.value
                                  ? Theme.of(context).colorScheme.error
                                  : null),
                        ),
                      )),
                Row(
                  children: [
                    Expanded(
                      // NOT use Offstage to wrap LinearProgressIndicator
                      child: Obx(() => showProgress.value
                          ? LinearProgressIndicator().marginOnly(right: 10)
                          : Offstage()),
                    ),
                    Obx(
                      () => OutlinedButton.icon(
                        icon: Icon(Icons.close_rounded, size: 16),
                        label: Text(translate(finished.value ? 'Close' : 'Cancel')),
                        onPressed: cancelEnabled.value
                            ? () => windowManager.close()
                            : null,
                        style: buttonStyle,
                      ).marginOnly(right: 10),
                    ),
                    if (existing)
                      Obx(
                        () => OutlinedButton.icon(
                          icon: Icon(Icons.delete_outline_rounded, size: 16),
                          label: Text(translate('Uninstall')),
                          onPressed: btnEnabled.value && !finished.value
                              ? _uninstall
                              : null,
                          style: buttonStyle,
                        ).marginOnly(right: 10),
                      ),
                    Obx(
                      () => ElevatedButton.icon(
                        icon: Icon(
                            m == 'update'
                                ? Icons.system_update_alt_rounded
                                : (existing
                                    ? Icons.restart_alt_rounded
                                    : Icons.done_rounded),
                            size: 16),
                        label: Text(translate(m == 'update'
                            ? 'Update'
                            : (existing ? 'Reinstall' : 'Accept and Install'))),
                        onPressed: btnEnabled.value && !finished.value
                            ? install
                            : null,
                        style: buttonStyle,
                      ),
                    ),
                    Offstage(
                      offstage: existing || bind.installShowRunWithoutInstall(),
                      child: Obx(
                        () => OutlinedButton.icon(
                          icon: Icon(Icons.screen_share_outlined, size: 16),
                          label: Text(translate('Run without install')),
                          onPressed: btnEnabled.value
                              ? () => bind.installRunWithoutInstall()
                              : null,
                          style: buttonStyle,
                        ).marginOnly(left: 10),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 1.4 * em),
                _compat(context),
              ],
            ).paddingSymmetric(horizontal: 4 * em, vertical: 2.4 * em);
          }),
        ));
  }

  void install() {
    do_install() {
      btnEnabled.value = false;
      cancelEnabled.value = false;
      showProgress.value = true;
      message.value = translate(mode == 'new'
          ? 'Installing, please wait…'
          : 'Updating, please wait…');
      messageIsError.value = false;
      String args = '';
      if (startmenu.value) args += ' startmenu';
      if (desktopicon.value) args += ' desktopicon';
      if (printer.value) args += ' printer';
      bind.installInstallMe(options: args, path: controller.text);
    }

    do_install();
  }

  Future<void> _uninstall() async {
    final ok = await showDialog<bool>(
      context: this.context,
      builder: (c) => AlertDialog(
        title: Text(translate('Uninstall')),
        content: Text(translate(
            'Remote access to this computer will stop. Do you want to uninstall?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: Text(translate('Cancel'))),
          TextButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: Text(translate('Uninstall'))),
        ],
      ),
    );
    if (ok != true) return;
    btnEnabled.value = false;
    cancelEnabled.value = false;
    showProgress.value = true;
    message.value = translate('Uninstalling, please wait…');
    messageIsError.value = false;
    String r = '';
    try {
      r = await bind.mainGetCommon(key: 'dytech-uninstall');
    } catch (e) {
      r = 'error:$e';
    }
    showProgress.value = false;
    cancelEnabled.value = true;
    if (r == 'ok') {
      finished.value = true;
      message.value = translate('Uninstalled successfully. You can close this window.');
      messageIsError.value = false;
    } else {
      btnEnabled.value = true;
      message.value =
          translate('Could not uninstall. Close the application and try again.');
      try {
        bind.mainGetCommon(key: 'dytech-log:installer U01 uninstall failed: ${r.length > 100 ? r.substring(0, 100) : r}');
      } catch (_) {}
      messageIsError.value = true;
      debugPrint('uninstall failed: $r');
    }
  }

  void selectInstallPath() async {
    String? install_path = await FilePicker.platform
        .getDirectoryPath(initialDirectory: controller.text);
    if (install_path != null) {
      controller.text = join(install_path, await bind.mainGetAppName());
    }
  }
}
