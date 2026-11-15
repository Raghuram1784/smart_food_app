import 'dart:io';
import 'dart:convert';
import 'package:integration_test/integration_test_driver_extended.dart';
Future<void> main() async {
 await integrationDriver(onScreenshot:(name,bytes,[args])async{final f=File('docs/f3/screenshots/$name.png');await f.parent.create(recursive:true);await f.writeAsBytes(bytes);return true;},responseDataCallback:(data)async{if(data?['orderId']==null)return;final f=File('docs/f3/device-result.json');await f.parent.create(recursive:true);await f.writeAsString(const JsonEncoder.withIndent('  ').convert(Map.from(data!)..remove('screenshots')));});
}
