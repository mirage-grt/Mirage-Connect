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
        final String displayName = advName.isNotEmpty
            ? advName
            : (platformName.isNotEmpty ? platformName : '(unknown device)');

        final existing = _devices[remoteId];
        if (existing == null ||
            existing.name != displayName ||
            existing.rssi != result.rssi) {
          _devices[remoteId] = _DeviceRowData(
            device: device,
            name: displayName,
            mac: remoteId,
            rssi: result.rssi,
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
                    subtitle: Text(row.mac),
                    trailing: _RssiChip(rssi: row.rssi),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WifiCredentialsScreen(device: row.device),
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

class WifiCredentialsScreen extends StatefulWidget {
  final BluetoothDevice device;
  const WifiCredentialsScreen({super.key, required this.device});
  @override
  State<WifiCredentialsScreen> createState() => _WifiCredentialsScreenState();
}

class _WifiCredentialsScreenState extends State<WifiCredentialsScreen> {
  final TextEditingController ssidController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  BluetoothCharacteristic? txCharacteristic;
  bool _writeWithoutResponse = false;
  String _connectError = '';

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
      bool useWriteWithoutResponse = false;

      for (final BluetoothService service in services) {
        for (final BluetoothCharacteristic c in service.characteristics) {
          if (c.properties.writeWithoutResponse) {
            chosen = c;
            useWriteWithoutResponse = true;
            break;
          }
          if (c.properties.write) {
            chosen = c;
            useWriteWithoutResponse = false;
            break;
          }
        }
        if (chosen != null) break;
      }

      if (mounted) {
        setState(() {
          txCharacteristic = chosen;
          _writeWithoutResponse = useWriteWithoutResponse;
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
            )
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
  const _DeviceRowData({required this.device, required this.name, required this.mac, required this.rssi});
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
