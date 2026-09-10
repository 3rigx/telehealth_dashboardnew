/// One serial (COM) port as reported by Windows PnP, with enough metadata to
/// tell the ports apart in the settings picker.
///
/// The dashboard used to enumerate ports with
/// `[System.IO.Ports.SerialPort]::GetPortNames()`, which returns bare strings
/// ("COM6", "COM7", …) with no device info. A single Unicorn-over-Bluetooth
/// setup exposes *several* SPP ports (the dongle's local incoming ports plus one
/// outgoing port bound to the headset), and re-pairing can leave stale entries
/// behind — so the picker showed a confusing list with no way to tell which
/// port is the headset. Querying `Win32_PnPEntity` instead gives us the friendly
/// name, the PnP id and the present/absent flag, which is what these fields hold.
class SerialPortInfo {
  /// The COM identifier, e.g. `COM7`. This is the value stored in settings and
  /// pushed to Unity — everything downstream still keys off the bare port name.
  final String port;

  /// Windows' friendly device name, e.g. "Standard Serial over Bluetooth link
  /// (COM7)" or "USB Serial Port (COM3)". Falls back to [port] when unknown.
  final String friendlyName;

  /// Whether the device is currently attached. Re-pairing a Bluetooth headset
  /// can leave a *phantom* port registered for the old COM number; filtering on
  /// this drops those so only live ports are offered.
  final bool present;

  /// The raw `PNPDeviceID`. Kept for [isBoundBluetooth] and diagnostics.
  final String pnpId;

  const SerialPortInfo({
    required this.port,
    required this.friendlyName,
    this.present = true,
    this.pnpId = '',
  });

  /// True when this looks like an *outgoing* Bluetooth SPP port bound to a
  /// specific remote device (the paired headset), rather than one of the
  /// dongle's own local server ports.
  ///
  /// Bound ports carry the remote device's address/VID&PID in their PnP id
  /// (`BTHENUM\…_VID&xxxx_PID&yyyy\…<mac>…`); the dongle's local incoming ports
  /// are tagged `LOCALMFG` and exist whether or not anything is paired. On a
  /// clinical rig the one bound SPP device is the Unicorn, so this is the port
  /// the EEG picker suggests.
  bool get isBoundBluetooth {
    final id = pnpId.toUpperCase();
    return id.contains('BTHENUM') && !id.contains('LOCALMFG');
  }

  /// True when this looks like a directly-attached USB serial device — the FSR
  /// insole's Arduino — as opposed to a Bluetooth SPP port (the EEG). Genuine
  /// Arduinos use USB VID 2341; clones use CH340/CP210x bridges; Windows' generic
  /// driver names it "USB Serial Device". This is the port the FSR picker suggests.
  bool get isUsbSerial {
    final id = pnpId.toUpperCase();
    if (id.contains('BTHENUM')) return false; // Bluetooth SPP → that's the EEG
    final name = friendlyName.toUpperCase();
    return id.contains('VID_2341') || // Arduino SA
        name.contains('ARDUINO') ||
        name.contains('CH340') ||
        name.contains('CP210') ||
        name.contains('USB SERIAL') ||
        name.contains('USB-SERIAL');
  }

  /// Bare-name fallback for hosts where the richer PnP query is unavailable
  /// (WMI blocked, non-Windows). Marked present with no PnP metadata.
  factory SerialPortInfo.bare(String port) =>
      SerialPortInfo(port: port, friendlyName: port);
}
