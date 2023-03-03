import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

//
enum Unit { w, photon, mol }

Map<Unit, String> unitMap = {
  Unit.w: "W\u2219m\u207B\u00B2",
  Unit.photon: "photons\u2219m\u207B\u00B2\u2219S\u207B\u00B9",
  Unit.mol: "\u00B5mol\u2219m\u207B\u00B2\u2219S\u207B\u00B9",
};


class UVVisSpecDeviceResult {
  List<double> sp = [];
  List<double> wl = [];
  double pwl = 0.0;
  double ir = 0.0;
  double pp = 0.0;
  List<double> spRaw = [];
  List<double> wlRaw = [];
}

class UVVisSpecDeviceStatus {
  bool attached = false;
  bool detached = false;
  bool connected = false;
  bool measurestarted = false;
  bool measurestopped = false;
  bool darkcorrected = false;
  bool deviceerror = false;
  bool devicewarn = false;
}

class UvVisSpecDevice {
  SerialPort? _port;
  Timer? _timer;

  final _status = UVVisSpecDeviceStatus();
  final _resultSubject = PublishSubject<UVVisSpecDeviceResult>();
  final _statusSubject = PublishSubject<UVVisSpecDeviceStatus>();
  bool _measuring = false;

  Future<void> initialize() async {
    if(SerialPort.availablePorts.isEmpty) {
      // _status.attached = false;
      // _status.detached = true;
      // _statusSubject.add(_status);
      return;
    }
    _port = SerialPort(SerialPort.availablePorts[0]);
    _port?.config.baudRate = 9600;
    _port?.openReadWrite();
    if(_port!.isOpen) {
      _status.attached = true;
      _status.detached = false;
      _statusSubject.add(_status);
      await measStart();
    }
    // UsbSerial.usbEventStream!.listen((UsbEvent event) async {
    //   if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
    //     _status.attached = true;
    //     _status.detached = false;
    //     _statusSubject.add(_status);
    //     var devices = await UsbSerial.listDevices();
    //     for (var device in devices) {
    //       var res = await _connectTo(device);
    //       if (res) {
    //         await measStart();
    //       }
    //     }
    //   }
    //   if (event.event == UsbEvent.ACTION_USB_DETACHED) {
    //     await measStop();
    //     await _connectTo(null);
    //     _status.detached = true;
    //     _status.attached = false;
    //     _statusSubject.add(_status);
    //   }
    // });

    // var devices = await UsbSerial.listDevices();
    // for (var device in devices) {
    //   var res = await _connectTo(device);
    //   if (res) {
    //     await measStart();
    //   }
    // }
  }

  Future<void> deinitialize() async {
    await measStop();
    //await _connectTo(null);
    _timer?.cancel();
  }

  Future<void> measStart() async {
    if(_status.connected == false) {
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (_measuring) {
        return;
      }
      if (_status.measurestopped) {
        timer.cancel();
        return;
      }
      if (_status.measurestarted) {
        _measuring = true;
        await meas();
        await status();
        _measuring = false;
      }
    });

    _status.measurestarted = true;
    _status.measurestopped = false;
    _statusSubject.add(_status);
  }

  Future<void> measStop() async {
    _status.measurestarted = false;
    _status.measurestopped = true;
    _statusSubject.add(_status);
  }

  Future<void> meas() async {

    try {
      
      var res = trantsaction(_port!, "MEAS\n");
      if (res == null) {
        _status.detached = true;
        _statusSubject.add(_status);
        return;
      }
      var values = res.split('\r');
      var len = values.length - 1;
      var wl = <double>[];
      var p = <double>[];
      for (var i = 0; i < len; i++) {
        var values2 = values[i].split(':');
        wl.add(double.parse(values2[0]));
        p.add(double.parse(values2[1]));
        if (p[i] < 1e-9) {
          p[i] = 0.0;
        }
      }

      var r = _correct(wl, p);
      var wl2 = r[0];
      var p2 = r[1];
      var pp = p2.reduce(max);
      var pwl = wl2[p2.indexWhere((x) => (x == pp))];
      var ir = 0.0;
      for (var i = 0; i < wl2.length; i++) {
        ir += p2[i];
      }

      var result = UVVisSpecDeviceResult();
      result.wlRaw = wl;
      result.spRaw = p;
      result.ir = ir;
      result.pwl = pwl;
      result.sp = p2;
      result.wl = wl2;
      result.pp = pp;
      _resultSubject.add(result);
    } catch (e) {
      return;
    }
  }

  Future<void> dark() async {
    trantsaction(_port!, "DARK\n");
  }

  Future<void> status() async {
    var res = trantsaction(_port!, "ST?\n");
    var v = res?.split('/')[1].split(':');
    if (v != null) {
      var status = v[0];
      _status.devicewarn = status == "W" ? true : false;
      _status.deviceerror = status == "E" ? true : false;
      _statusSubject.add(_status);
    }
  }

  Future<void> changeExposureTime(String exp) async {
    var msg = "EXP/100us\n";
    switch (exp) {
      case "AUTO":
        msg = "EXP/AUTO\n";
        break;
      // case "20us":
      //   msg = "EXP/20us\n";
      //   break;
      // case "50us":
      //   msg = "EXP/50us\n";
      //   break;
      case "100us":
        msg = "EXP/100us\n";
        break;
      case "1ms":
        msg = "EXP/1ms\n";
        break;
      case "10ms":
        msg = "EXP/10ms\n";
        break;
      case "100ms":
        msg = "EXP/100ms\n";
        break;
      default:
    }
    // _port?.write(
    //     const AsciiEncoder().convert(msg));
    trantsaction(_port!, msg);
  }

  Stream<UVVisSpecDeviceResult> get resultStream {
    return _resultSubject.stream;
  }

  Stream<UVVisSpecDeviceStatus> get statusStream {
    return _statusSubject.stream;
  }

  // Future<bool> _connectTo(UsbDevice? device) async {
  //   if (_transaction != null) {
  //     _transaction?.dispose();
  //     _transaction = null;
  //   }

  //   if (_port != null) {
  //     _port?.close();
  //     _port = null;
  //   }

  //   if (device == null) {
  //     _status.connected = false;
  //     _statusSubject.add(_status);
  //     return false;
  //   }

  //   _port = await device.create();
  //   var res = await _port?.open();
  //   if (res == null || res == false) {
  //     _status.connected = false;
  //     _statusSubject.add(_status);
  //     return false;
  //   }

  //   await _port?.setDTR(false);
  //   await _port?.setRTS(false);
  //   await _port?.setPortParameters(
  //       9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

  //   _transaction = Transaction.stringTerminated(
  //       (_port!.inputStream) as Stream<Uint8List>, Uint8List.fromList([10]));

    
  //   var res5 = await _transaction?.transaction(_port!,
  //       const AsciiEncoder().convert('EXP/AUTO\n'), const Duration(seconds: 60));

  //   _status.connected = true;
  //   _statusSubject.add(_status);

  //   return true;
  // }

  List<List<double>> _correct(List<double> wl, List<double> sp) {
    var wlMax = 800;
    var wlMin = 310;
    var len = wlMax - wlMin + 1;
    var wl2 = List.generate(len, (index) => (index + wlMin).toDouble());
    var sp2 = List.generate(len, (index) => 0.0);
    //var sp3 = List.generate(len, (index) => 0.0);
    //var z = _makeSplineTable(wl, sp);
    for (var i = 0; i < len; i++) {
      //sp2[i] = _interporateLinear(wl2[i], wl, sp);
      //sp2[i] = _interporateSpline(wl2[i], wl, sp, z);
      sp2[i] = _interporateLagrange(wl2[i], wl, sp);
      // if (sp2[i] < 0.0) {
      //   sp2[i] = 0.0;
      // }
    }
    for (var i = 2; i < len-2; i++) {
      sp2[i] = (sp2[i-2] * (-3) + sp2[i-1] * 12 + sp2[i] * 17 + sp2[i+1] * 12 + sp2[i+2] * (-3)) / 35;
      if(sp2[i] < 0.0) {
        sp2[i] = 0.0;
      }
    }
    return [wl2, sp2];
  }

  List<double> _makeSplineTable(List<double> x, List<double> y) {
    var n = x.length;
    var h = List.generate(n, (index) => 0.0);
    var d = List.generate(n, (index) => 0.0);
    var z = List.generate(n, (index) => 0.0);

    z[0] = 0;
    z[n - 1] = 0;
    for (int i = 0; i < n - 1; i++) {
      h[i] = x[i + 1] - x[i];
      d[i + 1] = (y[i + 1] - y[i]) / h[i];
    }
    z[1] = d[2] - d[1] - h[0] * z[0];
    d[1] = 2 * (x[2] - x[0]);
    for (int i = 1; i < n - 2; i++) {
      double t = h[i] / d[i];
      z[i + 1] = d[i + 2] - d[i + 1] - z[i] * t;
      d[i + 1] = 2 * (x[i + 2] - x[i]) - h[i] * t;
    }
    z[n - 2] -= h[n - 2] * z[n - 1];
    for (int i = n - 2; i > 0; i--) {
      z[i] = (z[i] - h[i] * z[i + 1]) / d[i];
    }
    return z;
  }

  double _interporateSpline(
      double t, List<double> x, List<double> y, List<double> z) {
    int i, j, k;
    double d, h;
    var n = z.length;

    i = 0;
    j = n - 1;
    while (i < j) {
      k = (i + j) ~/ 2;
      if (x[k] < t) {
        i = k + 1;
      } else {
        j = k;
      }
    }
    if (i > 0) i--;
    h = x[i + 1] - x[i];
    d = t - x[i];
    return (((z[i + 1] - z[i]) * d / h + z[i] * 3) * d +
                ((y[i + 1] - y[i]) / h - (z[i] * 2 + z[i + 1]) * h)) *
            d +
        y[i];
  }

  double _interporateLinear(double v, List<double> v1, List<double> v2) {
    var x1 = 0.0;
    var x2 = 0.0;
    var y1 = 0.0;
    var y2 = 0.0;
    var x = 0.0;
    var t2 = 1;
    var t1 = 1;
    var len = v1.length;

    if(v < v1[0]) {
      return v2[0];
    }

    for (var i = 1; i < len; i++) {
      x = v1[i];
      if (x > v) {
        t2 = i;
        x2 = x;
        break;
      }
    }
    t1 = t2 - 1;

    x1 = v1[t1];

    y1 = v2[t1];
    y2 = v2[t2];

    var value = (x2 - x1) == 0.0 ? 0.0 : y1 + (y2 - y1) * (v - x1) / (x2 - x1);

    if (value < 0.0) {
      value = 0.0;
    }

    return value;
  }

  double _interporateLagrange(double x, List<double> v1, List<double> v2) {
    var t1 = 2;
    
    if(x < v1[0]) {
      return v2[0];
    }

    for (var i = 2; i < v1.length - 1; i++) {
      t1 = i;
      if (v1[i] > x) {
        break;
      }
    }

    var xx = [v1[t1 - 2], v1[t1 - 1], v1[t1], v1[t1 + 1]];
    var yy = [v2[t1 - 2], v2[t1 - 1], v2[t1], v2[t1 + 1]];
    var p = 0.0;
    var s = 0.0;
    var n2 = xx.length;
    for (var j = 0; j < n2; j++) {
      p = yy[j];
      for (var i = 0; i < n2; i++) {
        if (i == j) continue;
        if ((xx[j] - xx[i]) != 0.0) p *= (x - xx[i]) / (xx[j] - xx[i]);
      }
      s += p;
    }
    if (s < 0) {
      s = 0.0;
    }
    return s;
  }

  String? trantsaction(SerialPort port, String msg){
    port.flush();
    port.write(const AsciiEncoder().convert(msg));
    while(port.bytesToWrite > 0);
    String res = "";
    while(true){
      final v1 = port.read(1);
      final v2 = String.fromCharCodes(v1);
      res = res + v2;
      if(v2 == "\n") break;
    }

    return res;
  }
}
