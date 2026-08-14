import 'dart:typed_data';

abstract class HidDevice {
  const HidDevice({
    required this.vendorId,
    required this.productId,
    required this.serialNumber,
    required this.productName,
    this.usagePage,
    this.usage,
    this.path,
    this.interfaceNumber,
  });

  final int vendorId;
  final int productId;
  final String serialNumber;
  final String productName;
  final int? usagePage;
  final int? usage;

  /// Platform-specific device path (e.g. `/dev/hidraw4` on Linux, the
  /// `hid#vid_...&mi_02#...` string on Windows). Used to open the exact
  /// interface of a composite device.
  final String? path;

  /// USB interface number (USB devices only, else -1).
  final int? interfaceNumber;

  /// Open the device by its enum-reported vendor/product id.
  Future<bool> open();

  /// Open the exact interface by its platform-specific [path].
  Future<bool> openPath(String path);

  /// Last error string reported by the HID library, if any.
  String? get lastError => null;

  Future<void> close();

  Stream<List<int>> read(int length, int duration);

  Future<bool> write(Uint8List bytes);

  Future<Uint8List> getFeatures(Uint8List input);

  Future<int> setFeatures(Uint8List input);
}
