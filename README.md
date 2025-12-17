MirageConnect

MirageConnect is a Bluetooth Low Energy (BLE)–based system for securely transferring credentials to nearby IoT devices. It simplifies device provisioning by enabling fast, low-power, and reliable credential exchange without requiring manual network setup or complex input interfaces.

Purpose

Provisioning credentials (like Wi-Fi keys, access tokens, or API secrets) to IoT devices is often error-prone and time-consuming, especially on headless or embedded hardware.
MirageConnect solves this by using BLE to transfer credentials directly from a host app to an IoT target device in a secure and automated way.

Features

BLE-based credential transfer — Uses Bluetooth Low Energy for short-range, low-power communication.

Secure provisioning — Credentials are shared only with intended nearby devices.

Multi-platform clients — Includes support for Android, iOS, and desktop where applicable.

Modular structure — Code separated into client implementations (android, ios, web, etc.) and shared libraries (lib).

Ease of use — Designed to work with minimal user interaction during the provisioning workflow.

Note: Platform folders contain the native code and build configs for each supported environment.

-- Getting Started --

Prerequisites: Device with BLE support, appropriate SDK (Android Studio / Xcode / compatible build tools), and necessary developer certificates (for mobile platforms).

1. Clone the Repository
git clone https://github.com/mirage-grt/Mirage-Connect.git
cd Mirage-Connect

2. Pick a Platform

Android: Open android/ in Android Studio

iOS: Open ios/ in Xcode

Desktop / other: Follow platform-specific instructions

3. Build & Run

Each platform has its own build instructions — open the corresponding project, install dependencies, and deploy to a BLE-capable device.

How It Works

Host app scans for BLE devices in proximity.

It identifies target IoT devices that support MirageConnect protocol.

The host sends credential payloads (e.g., network keys).

The IoT device receives and stores credentials securely.

BLE communication uses standard GATT characteristics for write-only credential transfer with optional encryption.

Dependencies

BLE libraries specific to platforms (Android BLE API, CoreBluetooth on iOS, etc.)

(Optional) Secure storage utilities for holding sensitive keys on either side

Testing

There is a test/ folder with sample test suites for BLE operations and credential payload validation. Use platform testing tools or custom scripts to verify behavior.
