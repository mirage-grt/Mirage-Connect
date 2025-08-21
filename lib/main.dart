import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mirage Connect',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      home: const DeviceScanScreen(),
    );
  }
}

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key});
  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  // Map remoteId -> latest scan info
  final Map<String, _DeviceRowData> _devices = {};
  bool scanning = false;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<bool>? _isScanningSub;

  @override
  void initState() {
    super.initState();
    _scanResultsSub = FlutterBluePlus.scanResults.listen((List<ScanResult> results) {
      bool changed = false;
      for (final ScanResult result in results) {
        final BluetoothDevice device = result.device;
        final String remoteId = device.remoteId.str;
        final String advName = result.advertisementData.advName.trim();
        final String platformName = device.platformName.trim();
        final List<String> advUuids =
            result.advertisementData.serviceUuids.map((u) => u.str).toList();
        final String displayName = advName.isNotEmpty
            ? advName
            : (platformName.isNotEmpty ? platformName : '(unknown device)');

        final existing = _devices[remoteId];
        if (existing == null ||
            existing.name != displayName ||
            existing.rssi != result.rssi ||
            existing.advServiceUuids.join(',') != advUuids.join(',')) {
          _devices[remoteId] = _DeviceRowData(
            device: device,
            name: displayName,
            mac: remoteId,
            rssi: result.rssi,
            advServiceUuids: advUuids,
          );
          changed = true;
        }
      }
      if (changed) {
        setState(() {});
      }
    });
    _isScanningSub = FlutterBluePlus.isScanning.listen((isScanning) {
      setState(() {
        scanning = isScanning;
      });
    });
    startScan();
  }

  @override
  void dispose() {
    _scanResultsSub?.cancel();
    _isScanningSub?.cancel();
    super.dispose();
  }

  Future<void> startScan() async {
    setState(() {
      _devices.clear();
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
  }

  @override
  Widget build(BuildContext context) {
    final items = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mirage Connect'),
        actions: [
          IconButton(
            tooltip: 'Scan',
            icon: scanning
                ? const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: scanning ? null : startScan,
          ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bluetooth_searching,
                        size: 64, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      scanning ? 'Scanning for devices...' : 'No devices found',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (!scanning)
                      ElevatedButton.icon(
                        onPressed: startScan,
                        icon: const Icon(Icons.search),
                        label: const Text('Scan Again'),
                      ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final row = items[index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: const Icon(Icons.bluetooth),
                    ),
                    title: Text(row.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.mac),
                        if (row.advServiceUuids.isNotEmpty)
                          Text(
                            'AD UUIDs: ${_formatAdvUuids(row.advServiceUuids)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    trailing: _RssiChip(rssi: row.rssi),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WifiCredentialsScreen(
                            device: row.device,
                            preferredUuid: row.advServiceUuids.isNotEmpty ? row.advServiceUuids.first : null,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: scanning ? null : startScan,
        icon: const Icon(Icons.bluetooth_searching),
        label: Text(scanning ? 'Scanning...' : 'Scan'),
      ),
    );
  }
}

extension on _DeviceScanScreenState {
  String _formatAdvUuids(List<String> uuids) {
    final int maxToShow = 2;
    final List<String> lowered = uuids.map((e) => e.toLowerCase()).toList();
    final List<String> shown = lowered.take(maxToShow).toList();
    final int more = uuids.length - shown.length;
    return more > 0 ? '${shown.join(', ')} +$more' : shown.join(', ');
  }
}

class WifiCredentialsScreen extends StatefulWidget {
  final BluetoothDevice device;
  final String? preferredUuid; // from advertisement if present
  const WifiCredentialsScreen({super.key, required this.device, this.preferredUuid});
  @override
  State<WifiCredentialsScreen> createState() => _WifiCredentialsScreenState();
}

class _WifiCredentialsScreenState extends State<WifiCredentialsScreen> {
  final TextEditingController ssidController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  BluetoothCharacteristic? txCharacteristic;
  BluetoothService? targetService;
  bool _writeWithoutResponse = false;
  String _connectError = '';
  List<BluetoothService> _services = [];

  Future<void> connectAndDiscover() async {
    _connectError = '';
    try {
      await widget.device.connect(autoConnect: false);
      if (Platform.isAndroid) {
        try {
          await widget.device.requestMtu(247);
        } catch (_) {}
      }
      // Small delay helps some peripherals after connection
      await Future.delayed(const Duration(milliseconds: 300));

      final List<BluetoothService> services = await widget.device.discoverServices();
      BluetoothCharacteristic? chosen;
      BluetoothService? chosenService;
      bool useWriteWithoutResponse = false;

      // If a preferred UUID was advertised, try to target that service/characteristic first
      final String? preferred = widget.preferredUuid?.toLowerCase();

      for (final BluetoothService service in services) {
        final String serviceUuid = service.uuid.str.toLowerCase();
        final bool serviceMatches = preferred != null && serviceUuid.contains(preferred);
        for (final BluetoothCharacteristic c in service.characteristics) {
          final String charUuid = c.uuid.str.toLowerCase();
          final bool charMatches = preferred != null && charUuid.contains(preferred);
          final bool preferThis = (serviceMatches || charMatches);
          if (c.properties.writeWithoutResponse) {
            if (chosen == null || preferThis) {
              chosen = c;
              chosenService = service;
              useWriteWithoutResponse = true;
            }
            break;
          }
          if (c.properties.write) {
            if (chosen == null || preferThis) {
              chosen = c;
              chosenService = service;
              useWriteWithoutResponse = false;
            }
            break;
          }
        }
        if (chosen != null && (preferred == null || serviceMatches)) break;
      }

      if (mounted) {
        setState(() {
          txCharacteristic = chosen;
          targetService = chosenService;
          _writeWithoutResponse = useWriteWithoutResponse;
          _services = services;
        });
      }
    } catch (e) {
      _connectError = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connect/discover failed: $_connectError')),
        );
      }
    }
  }

  void sendCredentials() async {
    if (txCharacteristic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No writable characteristic found!')),
      );
      return;
    }
    final Map<String, String> creds = {
      'ssid': ssidController.text.trim(),
      'password': passwordController.text.trim(),
    };
    String jsonStr = jsonEncode(creds);
    List<int> bytes = utf8.encode(jsonStr);
    await txCharacteristic!.write(bytes, withoutResponse: _writeWithoutResponse);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Credentials sent!')),
    );
    await widget.device.disconnect();
  }

  @override
  void initState() {
    super.initState();
    connectAndDiscover();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Send WiFi to ${widget.device.platformName.isNotEmpty ? widget.device.platformName : widget.device.remoteId.str}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wi‑Fi Credentials',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ssidController,
                      decoration: const InputDecoration(
                        labelText: 'SSID',
                        prefixIcon: Icon(Icons.wifi),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: sendCredentials,
                      icon: const Icon(Icons.send),
                      label: const Text('Send Credentials'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Device Info'),
              subtitle: Text('MAC: ${widget.device.remoteId.str}'),
            ),
            if (txCharacteristic != null) ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Target GATT'),
              subtitle: Text(
                'Service: ${targetService?.uuid.str.toLowerCase() ?? 'unknown'}\nChar: ${txCharacteristic?.uuid.str.toLowerCase()}',
              ),
            ),
            if (_services.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discovered GATT Services',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ..._services.map((s) => _GattServiceTile(service: s)).toList(),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceRowData {
  final BluetoothDevice device;
  final String name;
  final String mac;
  final int rssi;
  final List<String> advServiceUuids;
  const _DeviceRowData({required this.device, required this.name, required this.mac, required this.rssi, required this.advServiceUuids});
}

class _RssiChip extends StatelessWidget {
  final int rssi;
  const _RssiChip({required this.rssi});
  @override
  Widget build(BuildContext context) {
    Color color;
    if (rssi >= -60) {
      color = Colors.green;
    } else if (rssi >= -80) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }
    return Chip(
      label: Text('$rssi dBm'),
      avatar: Icon(Icons.network_wifi, size: 16, color: color),
    );
  }
}

class _GattServiceTile extends StatelessWidget {
  final BluetoothService service;
  const _GattServiceTile({required this.service});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 8.0),
      title: Text('Service: ${service.uuid.str.toLowerCase()}'),
      childrenPadding: const EdgeInsets.only(left: 16.0, right: 8.0, bottom: 8.0),
      children: service.characteristics.map((c) {
        final List<String> props = [];
        if (c.properties.read) props.add('read');
        if (c.properties.write) props.add('write');
        if (c.properties.writeWithoutResponse) props.add('writeNR');
        if (c.properties.notify) props.add('notify');
        if (c.properties.indicate) props.add('indicate');
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
          leading: const Icon(Icons.vpn_key, size: 18),
          title: Text('Char: ${c.uuid.str.toLowerCase()}'),
          subtitle: Text(props.join(', ')),
        );
      }).toList(),
    );
  }
}
