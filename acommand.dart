import 'dart:convert';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:args/args.dart';
import 'package:dcache/dcache.dart';

Future<ProcessResult> run(String command) {
  return Process.run('bash', ['-c', command]);
}

void main(List<String> args) async {
  var parser = new ArgParser();
  parser.addMultiOption('file',
      abbr: "f",
      help: 'read the content from the files.',
      valueHelp: 'name=file');
  parser.addMultiOption('command',
      abbr: "c", help: 'read the content from the command.');
  parser.addMultiOption('string',
      abbr: "s", help: 'read the content from the command.');
  parser.addOption('command-from', help: 'read the content from the command.');
  parser.addOption('file-from', help: 'read the content from the command.');
  parser.addOption('worker', abbr: 'w', defaultsTo: "5");

  parser.addFlag('help', abbr: "h");
  var results = parser.parse(args);
  if (results['help']) {
    print(parser.usage);
    return;
  }
  if (results.rest.length == 0) {
    print("Please provide command");
    return;
  }

  var worker = int.tryParse(results['worker']) ?? 5;
  var done = 0;

  var argsDict = List<Map<String, String>>();
  for (var i in results['file']) {
    var index = 0;
    var parts = i.toString().split('=');
    var name = parts[0];
    var fileName = parts.getRange(1, parts.length).toList().join('=');
    var content = File(fileName).readAsStringSync();
    for (var line in content.split('\n')) {
      line = line.trim();
      if(line.length == 0){
        continue;
      }
      if (index >= argsDict.length) {
        argsDict.add(Map<String, String>());
      }
      var d = argsDict[index];
      d[name] = line;
      index += 1;
    }
  }

  for (var i in results['command']) {
    var index = 0;
    var parts = i.toString().split('=');
    var name = parts[0];
    var command = parts.getRange(1, parts.length).toList().join('=');
    var p = await run(command);
    for (var line in p.stdout.toString().split('\n')) {
      line = line.trim();
      if (line.length == 0){
        continue;
      }
      if (index >= argsDict.length) {
        argsDict.add(Map<String, String>());
      }
      var d = argsDict[index];
      d[name] = line;
      index += 1;
    }
  }
  if (argsDict.length == 0) {
    argsDict.add(Map<String, String>());
  }
  for (var i in results['string']) {
    var parts = i.toString().split('=');
    var name = parts[0];
    var value = parts.getRange(1, parts.length).toList().join('=');
    for (var d in argsDict) {
      d[name] = value;
    }
  }
  print(argsDict);

  for (var i in argsDict) {
    while (worker <= 0) {
      await Future.delayed(Duration(milliseconds: 1));
    }
    var command = results.rest[0];
    for (var k in i.keys) {
      command = command.replaceAll(k, i[k]);
    }

    var fp = Future.value(ProcessResult(0, 0, "", ""));
    var oldCommand = null;
    worker -= 1;
    for (var c in results.rest.getRange(0, results.rest.length)) {
      for (var k in i.keys) {
        c = c.replaceAll(k, i[k]);
      }

      var privateOldCommand = oldCommand;
      fp = fp?.then((p) {
        if (p == null) {
          return null;
        }
        if (p.pid != 0) {
          show(privateOldCommand, p);
        }
        if (p.exitCode == 0) {
          return run(c);
        }
        return null;
      });
      oldCommand = c;
    }
    fp?.then((p) {
      done += 1;
      worker += 1;
      if (p == null) {
        return null;
      }
      var privateOldCommand = oldCommand;
      show(privateOldCommand, p);
    });
  }

  while (done < argsDict.length) {
    await Future.delayed(Duration(milliseconds: 1));
  }
}

void show(String command, ProcessResult p) {
  var error = '';

  if (p.exitCode != 0) {
    error = ' with error';
  }
  print("cmd$error: $command\nstdout:\n${p.stdout}\nstderr:${p.stderr}");
}
