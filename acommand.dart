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

  parser.addFlag('help', abbr: "h", negatable: false);
  parser.addFlag('error', defaultsTo: false, help: 'show the result even if the command failed');
  var argResults = parser.parse(args);
  if (argResults['help']) {
    print(parser.usage);
    return;
  }
  if (argResults.rest.length == 0) {
    print("Please provide command");
    print(parser.usage);
    return;
  }

  var worker = int.tryParse(argResults['worker']) ?? 5;
  var done = 0;

  var argList = List<Map<String, String>>();
  for (var i in argResults['file']) {
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
      if (index >= argList.length) {
        argList.add(Map<String, String>());
      }
      var d = argList[index];
      d[name] = line;
      index += 1;
    }
  }

  for (var i in argResults['command']) {
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
      if (index >= argList.length) {
        argList.add(Map<String, String>());
      }
      var d = argList[index];
      d[name] = line;
      index += 1;
    }
  }
  if (argList.length == 0) {
    argList.add(Map<String, String>());
  }
  for (var i in argResults['string']) {
    var parts = i.toString().split('=');
    var name = parts[0];
    var value = parts.getRange(1, parts.length).toList().join('=');
    for (var d in argList) {
      d[name] = value;
    }
  }
  for (var i in argList) {
    while (worker <= 0) {
      await Future.delayed(Duration(milliseconds: 1));
    }
    var command = argResults.rest[0];
    for (var k in i.keys) {
      command = command.replaceAll(k, i[k]);
    }

    var fp = Future.value(ProcessResult(0, 0, "", ""));
    var oldCommand = null;
    worker -= 1;
    for (var c in argResults.rest.getRange(0, argResults.rest.length)) {
      for (var k in i.keys) {
        c = c.replaceAll(k, i[k]);
      }

      var privateOldCommand = oldCommand;
      fp = fp?.then((p) {
        if (p == null) {
          return null;
        }
        if (p.pid != 0) {
          show(privateOldCommand, p, showError: argResults['error']);
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
      show(privateOldCommand, p, showError: argResults['error']);
    });
  }

  while (done < argList.length) {
    await Future.delayed(Duration(milliseconds: 1));
  }
}

void show(String command, ProcessResult p, {bool showError=true}) {
  var error = '';

  if (p.exitCode != 0) {
    if(!showError){
      return;
    }
    error = ' with error';
  }
  print("cmd$error: $command\nstdout:\n${p.stdout}\nstderr:${p.stderr}");
}
