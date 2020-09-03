import 'dart:convert';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:args/args.dart';
import 'package:dcache/dcache.dart';
import 'package:uuid/uuid.dart';

Future<ProcessResult> run(String command, {String shell="sh"}) {
  if (command.startsWith(RegExp('^!'))) {
    var firstSpaceIndex = command.indexOf(RegExp(" "));
    var programName = command.substring(1, firstSpaceIndex);

  var arguments = (jsonDecode(command.substring(firstSpaceIndex, command.length)) as List<dynamic>).cast<String>();
    return Process.run(programName, arguments);
  }
  return Process.run('sh', ['-c', command]);
}

void main(List<String> args) async {
  var parser = new ArgParser();
  parser.addMultiOption('file',
      abbr: "f",
      help: 'read the content from the files.',
      valueHelp: 'name=file');
  parser.addMultiOption('command',
      abbr: "c",
      help: 'read the content from the command.',
      valueHelp: 'name=command');
  parser.addMultiOption('string',
      abbr: "s",
      help: 'replace the name with the string',
      valueHelp: 'name=string');
  parser.addMultiOption('tempfile',
      abbr: "t",
      help: 'replace the name with the tempfile path',
      valueHelp: 'name');
  parser.addMultiOption('uuid',
      abbr: "u", help: 'replace the name with the uuid', valueHelp: 'name');
  parser.addOption('worker', abbr: 'w', defaultsTo: "5");
  parser.addOption('reduce', abbr: 'r', defaultsTo: "");
  parser.addOption('shell', defaultsTo: "sh");

  parser.addFlag('help', abbr: "h", negatable: false);
  parser.addFlag('error',
      defaultsTo: false, help: 'show the result even if the command failed');
  parser.addFlag('stdout', defaultsTo: true, help: 'print the stdout');
  parser.addFlag('stderr', defaultsTo: true, help: 'print the stderr');
  parser.addFlag('header', defaultsTo: true, help: 'show the header');
  parser.addFlag('last',
      defaultsTo: false, help: 'show the output of the last command');

  var argResults = parser.parse(args);
  var reduceCommand = argResults['reduce'].toString();
  if (argResults['help']) {
    print(parser.usage);
    return;
  }
  if (argResults.rest.length == 0 && reduceCommand.length == 0) {
    print("Please provide command");
    print(parser.usage);
    return;
  }

  var showWrapper = (String command, ProcessResult p) {
    show(command, p,
        showError: argResults['error'],
        stdout: argResults['stdout'],
        stderr: argResults['stderr'],
        header: argResults['header']);
  };

  var runWrapper = (String command){
    return run(command, shell: argResults['shell']);
  };

  var worker = int.tryParse(argResults['worker']) ?? 5;
  var done = 0;
  var tempDir = Directory.systemTemp.createTempSync();
  var uuid = Uuid();

  var argList = List<Map<String, String>>();
  for (var i in argResults['file']) {
    var index = 0;
    var parts = i.toString().split('=');
    var name = parts[0];
    var fileName = parts.getRange(1, parts.length).toList().join('=');
    var content = File(fileName).readAsStringSync();
    for (var line in content.split('\n')) {
      line = line.trim();
      if (line.length == 0) {
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
    var p = await runWrapper(command);
    for (var line in p.stdout.toString().split('\n')) {
      line = line.trim();
      if (line.length == 0) {
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
  for (var i in argResults['tempfile']) {
    for (var d in argList) {
      var filename = uuid.v4();
      d[i] = "${tempDir.path}/$filename";
    }
  }
  for (var i in argResults['uuid']) {
    for (var d in argList) {
      d[i] = uuid.v4();
    }
  }
  if (argResults.rest.length > 0) {
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
          if (p.pid != 0 && !argResults['last']) {
            showWrapper(privateOldCommand, p);
          }
          if (p.exitCode == 0) {
            return runWrapper(c);
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
        if (reduceCommand.length == 0) {
          showWrapper(privateOldCommand, p);
        }
      });
    }

    while (done < argList.length) {
      await Future.delayed(Duration(milliseconds: 1));
    }
  }

  if (reduceCommand.length > 0) {
    for (var i in argList[0].keys) {
      if (reduceCommand.contains(i)) {
        var s = '';
        for (var j = 0; j < argList.length; j++) {
          s += argList[j][i] + ' ';
        }
        reduceCommand = reduceCommand.replaceAll(i, s);
      }
    }
    done = 0;

    runWrapper(reduceCommand).then((p) {
      show(reduceCommand, p, showError: argResults['error']);
      done += 1;
    });

    while (done < 1) {
      await Future.delayed(Duration(milliseconds: 1));
    }
  }
  tempDir.deleteSync(recursive: true);
}

void show(String command, ProcessResult p,
    {bool showError = true,
    bool stdout = true,
    bool stderr = true,
    bool header = true}) {
  var error = '';

  if (p.exitCode != 0) {
    if (!showError) {
      return;
    }
    error = ' with error';
  }
  if (header) {
    print("cmd$error: $command\n");
    if (stdout) {
      print("stdout:\n${p.stdout}\n");
    }
    if (stderr) {
      print("stderr:${p.stderr}");
    }
  } else {
    if (stdout) {
      print("${p.stdout}\n");
    }
    if (stderr) {
      print("${p.stderr}");
    }
  }
}
