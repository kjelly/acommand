import 'dart:convert';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:args/args.dart';
import 'package:dcache/dcache.dart';


Future<ProcessResult> run(String command){
  return Process.run('bash', ['-c', command]);
}


void main(List<String> args) async {
  var parser = new ArgParser();
  parser.addMultiOption('file',
      abbr: "f", help: 'read the content from the files.', valueHelp: 'name=file');
  parser.addMultiOption('command',
      abbr: "c", help: 'read the content from the command.');
  parser.addMultiOption('string',
      abbr: "s", help: 'read the content from the command.');
  parser.addOption('command-from', help: 'read the content from the command.');
  parser.addOption('file-from', help: 'read the content from the command.');
  parser.addFlag('help', abbr: "h");
  var results = parser.parse(args);
  if (results['help']) {
    print(parser.usage);
    return;
  }
  if (results.rest.length == 0){
    print("Please provide command");
    return;
  }
  var argsDict = List<Map<String, String>>();
  for (var i in results['file']){
    var index = 0;
    var parts = i.toString().split('=');
    var name = parts[0];
    var fileName = parts.getRange(1, parts.length).toList().join('=');
    var content = File(fileName).readAsStringSync();
    print(content);
    for(var line in content.split('\n')){
      if(index >= argsDict.length){
        argsDict.add(Map<String, String>());
      }
      var d = argsDict[index];
      d[name] = line;
      index += 1;
    }
  }
  if(argsDict.length == 0){
    argsDict.add(Map<String, String>());
  }
  for (var i in results['string']){
    var parts = i.toString().split('=');
    var name = parts[0];
    var value = parts.getRange(1, parts.length).toList().join('=');
    for(var d in argsDict){
      d[name] = value;
    }

  }
  print(argsDict);

  for(var i in argsDict){
    var command = results.rest[0];
    for(var k in i.keys){
      command = command.replaceAll(k, i[k]);
    }

    run(command).then((p){
      print("cmd: $command \nstdout:\n${p.stdout}\nstderr:${p.stderr}");

    });
  }

}

