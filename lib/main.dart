import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:window_size/window_size.dart';
import 'uvvisspec.dart';
import 'settings.dart';
import 'result_storage.dart';
import 'uvvisspecapp.dart';

void main() {
  const double windowWidth = 600;
  const double windowHeight = 730;
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    WidgetsFlutterBinding.ensureInitialized();
    setWindowTitle('分光放射照度計アプリ');
    setWindowMinSize(Size(windowWidth, windowHeight));
    setWindowMaxSize(Size(windowWidth, windowHeight));
    getCurrentScreen().then((screen) {
      setWindowFrame(Rect.fromCenter(
        center: screen!.frame.center,
        width: windowWidth,
        height: windowHeight,
      ));
    });
  }

  runApp(MyApp());
} 

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const Home(),
      theme: ThemeData(
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(color: Colors.blueGrey),
      ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return HomeState();
  }
}

class HomeState extends State<Home> {
  final ResultStorage storage = ResultStorage();
  final UvVisSpecDevice device = UvVisSpecDevice();
  final ResultConverter resultConverter = ResultConverter();

  var _peekPower = 0.0;
  var _peekWavelength = 0.0;
  var _irradiance = 0.0;
  var _unit = "W\u2219m\u207B\u00B2";

  late List<double> _spectralData = List.generate(50, (index) => 1.0);
  late List<double> _spectralWl = List.generate(50, (index) => 0.0);
  late ResultReport _currentResult = ResultReport();
  var _settings = Settings();
  var _showWarning = true;
  var _measuring = false;
  var _connected = false;
  // var _timer;

  @override
  void initState() {
    super.initState();

    resultConverter.initialize();

    device.statusStream.listen((event) async {
      if (event.detached) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (x) => AlertDialog(
            content: const Text('デバイスが切断されました.\r\nアプリを終了します.'),
            actions: [
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  SystemNavigator.pop();
                },
              ),
            ],
          ),
        );

        await Future.delayed(const Duration(seconds: 5));
        Navigator.of(context).pop();
        SystemNavigator.pop();
      }
      setState(() {
        _connected = event.connected;
        _measuring = event.measurestarted;

        if (event.devicewarn || event.deviceerror) {
          _showWarning = true;
          return;
        }
        _showWarning = false;
      });
    });
    device.resultStream.listen((event) async {
      _currentResult = await resultConverter.convert(event, _settings);

      var p1 = [..._currentResult.sp];
      var wl1 = [..._currentResult.wl];
      var pp1 = _currentResult.pp;
      var ir1 = _currentResult.ir;
      var pwl1 = _currentResult.pwl;
      var vmax = p1.reduce(max);
      for (var i = 0; i < p1.length; i++) {
        p1[i] /= vmax;
      }

      setState(() {
        _spectralData = p1;
        _spectralWl = wl1;
        _irradiance = ir1;
        _peekWavelength = pwl1;
        _peekPower = pp1;
      });
    });

    device.initialize();
  }

  @override
  void dispose() {
    super.dispose();
    Future(() async {
      await device.measStop();
      await device.deinitialize();
    });
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    var integratedLightIntensityLabel = "放射照度";
    switch (_settings.measureMode) {
      case MeasureMode.irradiance:
        integratedLightIntensityLabel = "放射照度";
        break;
      case MeasureMode.insectsIrradiance:
        integratedLightIntensityLabel = "光子数密度";
        break;
      case MeasureMode.ppfd:
        integratedLightIntensityLabel = "光量子束密度";
        break;
    }
    if (_settings.sumRangeMin == 310 && _settings.sumRangeMax == 800) {
    } else if (_settings.sumRangeMin == 310 && _settings.sumRangeMax == 400) {
      integratedLightIntensityLabel += " 310 - 400 nm (UV)";
    } else if (_settings.sumRangeMin == 400 && _settings.sumRangeMax == 500) {
      integratedLightIntensityLabel += " 400 - 500 nm (B)";
    } else if (_settings.sumRangeMin == 500 && _settings.sumRangeMax == 600) {
      integratedLightIntensityLabel += " 500 - 600 nm (G)";
    } else if (_settings.sumRangeMin == 600 && _settings.sumRangeMax == 700) {
      integratedLightIntensityLabel += " 600 - 700 nm (R)";
    } else if (_settings.sumRangeMin == 700 && _settings.sumRangeMax == 800) {
      integratedLightIntensityLabel += " 700 - 800 nm (FR)";
    } else if (_settings.sumRangeMin == 400 && _settings.sumRangeMax == 700) {
      integratedLightIntensityLabel += " 400 - 700 nm";
    } else {
      integratedLightIntensityLabel += " (" +
          _settings.sumRangeMin.toInt().toString() +
          " - " +
          _settings.sumRangeMax.toInt().toString() +
          " nm)";
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('分光放射照度計アプリ'),
        actions: <Widget>[
          //(_connected) ? const Icon(Icons.check_circle_outline) : const Icon(Icons.highlight_off_outlined),
          (_showWarning) ? const Icon(Icons.warning) : const SizedBox.shrink(),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await device.measStop();
              var prevExp = _settings.deviceExposureTime;
              _settings = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => SettingsPage(_settings)));

              setState(() {
                _unit = unitMap[_settings.unit]!;
              });

              if (_settings.deviceExposureTime != prevExp) {
                await device.changeExposureTime(_settings.deviceExposureTime);
              }
              //debugPrint(_settings.deviceExposureTime);

              await device.measStart();
            },
          ),
        ],
      ),
      body: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
            Container(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  SizedBox(
                      width: width,
                      height: height / 100 * 30,
                      child: Card(
                        child: SpectralLineChart.create(
                            _spectralWl,
                            _spectralData,
                            _settings.sumRangeMin,
                            _settings.sumRangeMax),
                      )),
                  SizedBox(
                    height: height / 100 * 20,
                    width: width,
                    child: Card(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          Visibility(
                              child: Text(
                                filterNameMap[_settings.filter].toString(),
                                style: const TextStyle(fontSize: 14),
                              ),
                              visible: _settings.measureMode ==
                                  MeasureMode.insectsIrradiance),
                          Text(
                            integratedLightIntensityLabel,
                            style: const TextStyle(fontSize: 16),
                          ),
                          Text(
                            _irradiance == 0 ? "0"
                                :_irradiance * 1000 < 1
                                ? _irradiance.toStringAsExponential(3)
                                : _irradiance > 1000
                                    ? _irradiance.toStringAsExponential(3)
                                    : _irradiance.toStringAsPrecision(4),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 36,
                              color: Colors.blue.shade600,
                            ),
                          ),
                          Text(_unit, style: const TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: height / 100 * 15,
                    width: width,
                    child: Card(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          const Text(
                            "ピーク光強度",
                            style: TextStyle(
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            _peekPower == 0 ? "0"
                                : _peekPower * 1000 < 1
                                ? _peekPower.toStringAsExponential(3)
                                : _peekPower > 1000
                                    ? _peekPower.toStringAsExponential(3)
                                    : _peekPower.toStringAsPrecision(4),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 36,
                              color: Colors.blue.shade600,
                            ),
                          ),
                          Text(_unit + "\u2219nm\u207B\u00B9",
                              style: const TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: height / 100 * 15,
                    width: width,
                    child: Card(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          const Text(
                            "ピーク波長",
                            style: TextStyle(
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            _peekWavelength.toStringAsFixed(0),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 36,
                              color: Colors.blue.shade600,
                            ),
                          ),
                          const Text("nm", style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(5, 5, 5, 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  SizedBox(
                    height: 40,
                    width: 120,
                    child: ElevatedButton(
                      onPressed: () async {
                        await device.measStop();

                        var res = await showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (x) => AlertDialog(
                                  content:
                                      const Text('ダーク補正をします.\r\n遮光してください.'),
                                  actions: [
                                    TextButton(
                                      child: const Text('Cancel'),
                                      onPressed: () =>
                                          Navigator.of(context).pop(0),
                                    ),
                                    TextButton(
                                      child: const Text('OK'),
                                      onPressed: () =>
                                          Navigator.of(context).pop(1),
                                    ),
                                  ],
                                ));

                        if (res == 1) {
                          showDialog(
                              context: context,
                              builder: (x) {
                                return AlertDialog(
                                  content: Container(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: const <Widget>[
                                            Padding(
                                                child: SizedBox(
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 3),
                                                    width: 32,
                                                    height: 32),
                                                padding: EdgeInsets.only(
                                                    bottom: 16)),
                                            Padding(
                                                child: Text(
                                                  'しばらくお待ちください...',
                                                  style:
                                                      TextStyle(fontSize: 16),
                                                  textAlign: TextAlign.center,
                                                ),
                                                padding:
                                                    EdgeInsets.only(bottom: 4))
                                          ])),
                                );
                              });

                          await device.dark();

                          Navigator.of(context).pop();

                          // dialog = const AlertDialog(
                          //   content: Text('ダーク補正しました.'),
                          // );
                          // await showDialog(context: context, builder: (x) => dialog);
                        }
                        await device.measStart();
                      },
                      child: const Text("DARK"),
                      style: ElevatedButton.styleFrom(
                          shape: const StadiumBorder(), backgroundColor: Colors.white38),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    width: 120,
                    child: ElevatedButton(
                      onPressed: () async {
                        setState(() {});
                        if (_measuring) {
                          await device.measStop();
                          return;
                        }
                        await device.measStart();
                      },
                      child:
                          !_measuring ? const Text("MEAS") : const Text("HOLD"),
                      style: ElevatedButton.styleFrom(
                          shape: const StadiumBorder(), backgroundColor: !_measuring
                              ? Colors.green
                              : Colors.blue.shade800),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    width: 120,
                    child: ElevatedButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final filename =
                            '${now.year}${now.month.toString().padLeft(2, "0")}${now.day.toString().padLeft(2, "0")}${now.hour.toString().padLeft(2, "0")}${now.minute.toString().padLeft(2, "0")}${now.second.toString().padLeft(2, "0")}';
                        _currentResult.measureDatetime = now.toString();
                        storage.write(filename, _currentResult);
                        var dialog = const AlertDialog(
                          content: Text("保存しました."),
                        );
                        await showDialog(
                            context: context, builder: (x) => dialog);
                      },
                      child: const Text("STORE"),
                      style: ElevatedButton.styleFrom(
                          shape: const StadiumBorder(), backgroundColor: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ])),
    );
  }
}

class SpectralLineChart extends StatelessWidget {
  final charts.Series<dynamic, num>? series;
  final bool? animate;
  final double sumRangeMin;
  final double sumRangeMax;
  SpectralLineChart(
      this.series, this.animate, this.sumRangeMin, this.sumRangeMax);

  factory SpectralLineChart.create(List<double> wl, List<double> opticalPower,
      double sumRangeMin, double sumRangeMax) {
    return SpectralLineChart(_createSpectralChartData(wl, opticalPower), false,
        sumRangeMin, sumRangeMax);
  }

  static charts.Series<LinearSpectral, int> _createSpectralChartData(
      List<double> wl, List<double> opticalPower) {
    List<LinearSpectral> l = [];
    for (var i = 0; i < wl.length; i++) {
      l.add(LinearSpectral(wl[i], opticalPower[i]));
    }

    return charts.Series<LinearSpectral, int>(
      id: 'Spectral',
      colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
      areaColorFn: (_, __) => charts.MaterialPalette.transparent,
      domainFn: (LinearSpectral sp, _) => sp.waveLength.toInt(),
      measureFn: (LinearSpectral sp, _) => sp.opticalPower,
      data: l,
      strokeWidthPxFn: (datum, index) => 4,
    );
  }

  @override
  Widget build(BuildContext context) {
    return charts.LineChart([series!],
        animate: animate,
        defaultRenderer: charts.LineRendererConfig(
            includeArea: true, stacked: false, radiusPx: 6, roundEndCaps: true),
        domainAxis: const charts.NumericAxisSpec(
            viewport: charts.NumericExtents(300.0, 800.0),
            showAxisLine: false,
            renderSpec: charts.SmallTickRendererSpec(
              labelStyle: charts.TextStyleSpec(
                fontSize: 15,
                color: charts.MaterialPalette.white,
              ),
              tickLengthPx: 0,
            ),
            tickProviderSpec: charts.BasicNumericTickProviderSpec(
                dataIsInWholeNumbers: true, desiredTickCount: 9)),
        primaryMeasureAxis: const charts.NumericAxisSpec(
            renderSpec: charts.NoneRenderSpec(), showAxisLine: false),
        behaviors: [
          charts.ChartTitle('nm',
              titleStyleSpec: const charts.TextStyleSpec(
                  color: charts.MaterialPalette.white, fontSize: 15),
              innerPadding: 0,
              behaviorPosition: charts.BehaviorPosition.bottom,
              titleOutsideJustification: charts.OutsideJustification.end),
          charts.RangeAnnotation([
            charts.LineAnnotationSegment(
              sumRangeMin, charts.RangeAnnotationAxisType.domain,
              color: charts.ColorUtil.fromDartColor(Colors.white),
              strokeWidthPx: 2,
              startLabel: sumRangeMin.toInt().toString() + "",
              labelStyleSpec: const charts.TextStyleSpec(
                  color: charts.MaterialPalette.white),
              //labelDirection: charts.AnnotationLabelDirection.horizontal
            ),
            charts.LineAnnotationSegment(
              sumRangeMax, charts.RangeAnnotationAxisType.domain,
              color: charts.ColorUtil.fromDartColor(Colors.white),
              strokeWidthPx: 2,
              endLabel: sumRangeMax.toInt().toString() + "",
              labelStyleSpec: const charts.TextStyleSpec(
                  color: charts.MaterialPalette.white),
              //labelDirection: charts.AnnotationLabelDirection.horizontal
            ),
          ]),
        ]);
  }
}

class LinearSpectral {
  final double waveLength;
  final double opticalPower;

  LinearSpectral(this.waveLength, this.opticalPower);
}
