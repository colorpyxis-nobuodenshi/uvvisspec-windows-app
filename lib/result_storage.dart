import 'dart:io';
import 'settings.dart';
import 'uvvisspecapp.dart';

class ResultStorage {
  Future<File> write(String filename, ResultReport result) async {
    // final status = await Permission.storage.request();
    final directory = Directory.current.path;
    final file = File('$directory/meas/$filename.csv');

    final wl = result.wl;
      final sp = result.sp;
      final len = sp.length;
      final mdt = result.measureDatetime;
      final pp = result.pp;
      final pw = result.pwl;
      final unit = result.mode == MeasureMode.irradiance
          ? "放射照度[W・m^-2]"
          : result.mode == MeasureMode.insectsIrradiance
              ? "光子数密度[photons・m^-2・S^-1]"
              : "光量子束密度[μmol・m^-2・S^-1]";
      var name = result.filterName;
      await file.writeAsString('測定日, $mdt\r\n', mode: FileMode.append);
      if (result.filterName != "") {
        await file.writeAsString('昆虫タイプ, $name\r\n', mode: FileMode.append);
      }
      await file.writeAsString('波長[nm], $unit\r\n', mode: FileMode.append);
      for (var i = 0; i < len; i++) {
        final v1 = wl[i];
        final v2 = sp[i];
        var contents = '$v1,$v2\r\n';
        await file.writeAsString(contents, mode: FileMode.append);
      }
    return file;
  }
}
