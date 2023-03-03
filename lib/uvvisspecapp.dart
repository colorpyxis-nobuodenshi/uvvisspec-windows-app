import 'dart:collection';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'settings.dart';
import 'uvvisspec.dart';

class Settings {
  Unit unit = Unit.w;
  FilterSpectralIntensityType filter = FilterSpectralIntensityType.None;
  double sumRangeMin = 310;
  double sumRangeMax = 800;
  String deviceExposureTime = "AUTO";
  MeasureMode measureMode = MeasureMode.irradiance;
  IntegrateLigthIntensityRange integrateLigthIntensityRange =
      IntegrateLigthIntensityRange.all;
}

enum FilterSpectralIntensityType {
  AllInsects,
  Azamiuma,
  Hachi,
  Ga350,
  Ga550,
  Ga350550,
  Y,
  None
}

Map<FilterSpectralIntensityType, String> filterNameMap = {
  FilterSpectralIntensityType.AllInsects: "UV誘引光",
  FilterSpectralIntensityType.Azamiuma: "アザミウマ",
  FilterSpectralIntensityType.Hachi: "ハチ",
  FilterSpectralIntensityType.Ga350: "ガ全般",
  FilterSpectralIntensityType.Ga550: "タバコスズメガ、ヒトリガ、オオタバコガ、コナガ",
  FilterSpectralIntensityType.Ga350550: "ハスモンヨトウ",
  FilterSpectralIntensityType.None: "",
  FilterSpectralIntensityType.Y: "視感度",
};

class ResultReport {
  List<double> sp = List.generate(491, (index) => 0.0);
  List<double> wl = List.generate(491, (index) => 310.0 + index);
  double pwl = 0.0;
  double ir = 0.0;
  double pp = 0.0;
  int wlRangeMin = 310;
  int wlRangeMax = 800;
  MeasureMode mode = MeasureMode.irradiance;
  String measureDatetime = "";
  FilterSpectralIntensityType isi = FilterSpectralIntensityType.Azamiuma;
  String filterName = "";
}

class ResultConverter {
  var _map = HashMap<FilterSpectralIntensityType, List<double>>();

  void initialize() {
    Future(() async {
      _map = await _readIncectsSpectralIntensity();
    });
  }

  Future<HashMap<FilterSpectralIntensityType, List<double>>>
      _readIncectsSpectralIntensity() async {
    final loadedData =
        await rootBundle.loadString('assets/filterspectralintensity.csv');
    var isil1 = <double>[];
    var isil2 = <double>[];
    var isil3 = <double>[];
    var isil4 = <double>[];
    var isil5 = <double>[];
    var isil6 = <double>[];
    var isil7 = <double>[];

    var lines = loadedData.split('\n');
    for (var i = 1; i < lines.length; i++) {
      //debugPrint('${lines[i]}');
      var v = lines[i].split((','));
      isil1.add(double.parse(v[1]));
      isil2.add(double.parse(v[2]));
      isil3.add(double.parse(v[3]));
      isil4.add(double.parse(v[4]));
      isil5.add(double.parse(v[5]));
      isil6.add(double.parse(v[6]));
      isil7.add(double.parse(v[7]));
    }
    var map = HashMap<FilterSpectralIntensityType, List<double>>();
    map[FilterSpectralIntensityType.AllInsects] = isil1;
    map[FilterSpectralIntensityType.Azamiuma] = isil2;
    map[FilterSpectralIntensityType.Hachi] = isil3;
    map[FilterSpectralIntensityType.Ga350] = isil4;
    map[FilterSpectralIntensityType.Ga550] = isil5;
    map[FilterSpectralIntensityType.Ga350550] = isil6;
    map[FilterSpectralIntensityType.Y] = isil7;

    return map;
  }

  Future<ResultReport> convert(
      UVVisSpecDeviceResult uvsr, Settings settings) async {
    final mode = settings.measureMode;
    final unit = settings.unit;
    final p1 = [...uvsr.sp];
    final wl = [...uvsr.wl];
    var p2 = List.generate(p1.length, (index) => 1.0);
    var p3 = List.generate(p1.length, (index) => 1.0);
    var p4 = List.generate(p1.length, (index) => 1.0);

    if (unit == Unit.w && unit == Unit.mol) {
      for (var i = 0; i < p1.length; i++) {
        p2[i] = p1[i];
        p3[i] = p2[i] * wl[i] * 5.03E+15;
        p4[i] = p2[i] * wl[i] / 0.1237 * 10E-3;
      }
    } else {
      final l = _map[settings.filter];
      if (l != null) {
        for (var i = 0; i < p1.length; i++) {
          p2[i] = p1[i] * l[i];
          p3[i] = p2[i] * wl[i] * 5.03E+15;
          p4[i] = p2[i] * wl[i] / 0.1237 * 10E-3;
        }
      } else {
        for (var i = 0; i < p1.length; i++) {
          p2[i] = p1[i];
          p3[i] = p2[i] * wl[i] * 5.03E+15;
          p4[i] = p2[i] * wl[i] / 0.1237 * 10E-3;
        }
      }
    }
    var p = unit == Unit.w
        ? p2
        : unit == Unit.photon
            ? p3
            : unit == Unit.mol
                ? p4
                : p2;
    var p5 = [...p];
    final l1 = settings.sumRangeMin;
    final l2 = settings.sumRangeMax;
    for (var i = 0; i < wl.length; i++) {
      if (wl[i] < l1) {
        p[i] = 0;
      }
      if (wl[i] > l2) {
        p[i] = 0;
      }
    }
    var pp = p.reduce(max);
    var pwl = wl[p.indexWhere((x) => (x == pp))];
    var ir = 0.0;
    for (var i = 0; i < wl.length; i++) {
      ir += p[i];
    }

    var res = ResultReport();
    res.sp = p5;
    res.wl = wl;
    res.ir = ir;
    res.pp = pp;
    res.pwl = pwl;
    res.filterName = filterNameMap[settings.filter]!;
    //res.unit = unit;
    res.mode = mode;
    return res;
  }
}
