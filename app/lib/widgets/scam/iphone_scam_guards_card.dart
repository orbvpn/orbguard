// iPhone-only part of the Scam shield: the two scam guards iOS lets an app
// offer, and exactly what each one needs from the person.
//
// Scam texts: the OrbGuardSmsFilter Message Filter extension sorts texts from
// unknown senders on the device. iOS gives the app no way to read whether it
// is turned on, so this card only says where to turn it on (iOS 26: Messages,
// Filter button, Manage Filtering, Text Message Filter).
//
// Scam calls: the OrbGuardCallDirectory extension blocks the numbers kept
// here. The on/off state is read from CXCallDirectoryManager, and Settings can
// be opened at Call Blocking & Identification. Numbers are saved even while it
// is off, and the card says they are blocked only once it is on.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/platform/call_directory_platform_service.dart';

class IphoneScamGuardsCard extends StatefulWidget {
  const IphoneScamGuardsCard({super.key, CallDirectoryPlatformService? service})
      : _service = service;

  final CallDirectoryPlatformService? _service;

  @override
  State<IphoneScamGuardsCard> createState() => _IphoneScamGuardsCardState();
}

enum _CallsState { checking, on, off, unavailable }

class _IphoneScamGuardsCardState extends State<IphoneScamGuardsCard>
    with WidgetsBindingObserver {
  late final CallDirectoryPlatformService _service =
      widget._service ?? CallDirectoryPlatformService.instance;
  final _numberController = TextEditingController();

  _CallsState _calls = _CallsState.checking;
  List<int> _blocked = const [];
  String? _numberError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _numberController.dispose();
    super.dispose();
  }

  // Back from Settings: read the switch again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await _service.status();
      final blocked = await _service.blockedNumbers();
      if (!mounted) return;
      setState(() {
        _blocked = blocked;
        if (status == null || status['containerAvailable'] != true) {
          _calls = _CallsState.unavailable;
        } else {
          _calls = status['extensionEnabled'] == true
              ? _CallsState.on
              : _CallsState.off;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _calls = _CallsState.unavailable);
    }
  }

  Future<void> _block() async {
    final number = CallDirectoryPlatformService.parseInternationalNumber(
        _numberController.text);
    if (number == null) {
      setState(() => _numberError = 'Add the country code, starting with +.');
      return;
    }
    await _run(() async {
      final list = await _service.block(number);
      _numberController.clear();
      return list;
    });
  }

  Future<void> _unblock(int number) => _run(() => _service.unblock(number));

  Future<void> _run(Future<List<int>> Function() edit) async {
    setState(() {
      _busy = true;
      _numberError = null;
    });
    try {
      final list = await edit();
      if (mounted) setState(() => _blocked = list);
    } on PlatformException {
      if (mounted) {
        setState(() => _numberError = "Couldn't save the list. Try again.");
      }
    } on CallDirectoryUnavailableException {
      if (mounted) setState(() => _calls = _CallsState.unavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _callsLine() {
    switch (_calls) {
      case _CallsState.checking:
        return 'Checking...';
      case _CallsState.on:
        return _blocked.isEmpty
            ? 'On. Add a number below to block it.'
            : 'On. Your iPhone stops calls from the numbers below.';
      case _CallsState.off:
        return 'Off. Open Settings, tap Apps, then Phone, then Call Blocking '
            '& Identification, and turn on OrbGuard. Numbers you add here '
            'are blocked once it is on.';
      case _CallsState.unavailable:
        return "This build can't keep a block list.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.text2;
    return GlassCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('On this iPhone', style: BrandText.title(color: Brand.text)),
          const SizedBox(height: 14),
          _guardRow(
            icon: 'chat_round',
            title: 'Scam texts',
            body: 'OrbGuard can sort texts from unknown senders, on your '
                'iPhone. Texts from your contacts are never sent to it. Open '
                'Messages, tap the Filter button at the top right, tap Manage '
                'Filtering, then Text Message Filter, and turn on OrbGuard.',
            muted: muted,
          ),
          const SizedBox(height: 14),
          const GlassDivider(),
          const SizedBox(height: 14),
          _guardRow(
            icon: 'call_cancel_rounded',
            title: 'Scam calls',
            body: _callsLine(),
            muted: muted,
          ),
          if (_calls == _CallsState.off) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: BrandButton(
                label: 'Open Settings',
                variant: BrandButtonVariant.secondary,
                compact: true,
                expand: false,
                onPressed: () => _service.openSettings(),
              ),
            ),
          ],
          if (_calls == _CallsState.on || _calls == _CallsState.off) ...[
            const SizedBox(height: 14),
            _numberField(muted),
            if (_numberError != null) ...[
              const SizedBox(height: 6),
              Text(_numberError!,
                  style: BrandText.body(size: 13, color: AppColors.errorInk)),
            ],
            for (final number in _blocked) _blockedRow(number, muted),
          ],
        ],
      ),
    );
  }

  Widget _guardRow({
    required String icon,
    required String title,
    required String body,
    required Color muted,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DuotoneIcon(icon, size: 22, color: Brand.text),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: BrandText.title(size: 15, color: Brand.text)),
              const SizedBox(height: 4),
              Text(body, style: BrandText.body(size: 13.5, color: muted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _numberField(Color muted) {
    return Row(
      children: [
        Expanded(
          child: GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _numberController,
              keyboardType: TextInputType.phone,
              enabled: !_busy,
              style: BrandText.body(size: 15, color: Brand.text),
              decoration: InputDecoration(
                hintText: '+1 555 010 0123',
                hintStyle: BrandText.body(size: 15, color: muted),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _block(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        BrandButton(
          label: 'Block',
          variant: BrandButtonVariant.secondary,
          compact: true,
          expand: false,
          isLoading: _busy,
          onPressed: _busy ? null : _block,
        ),
      ],
    );
  }

  Widget _blockedRow(int number, Color muted) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text('+$number',
                style: BrandText.mono(size: 14, color: Brand.text)),
          ),
          BrandButton(
            label: 'Unblock',
            variant: BrandButtonVariant.secondary,
            compact: true,
            expand: false,
            onPressed: _busy ? null : () => _unblock(number),
          ),
        ],
      ),
    );
  }
}
