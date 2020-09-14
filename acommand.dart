import 'dart:convert';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:args/args.dart';
import 'package:dcache/dcache.dart';
import 'package:uuid/uuid.dart';

Future<ProcessResult> run(String command, {String shell = "sh"}) {
  if (command.startsWith(RegExp('^!'))) {
    var firstSpaceIndex = command.indexOf(RegExp(" "));
    var programName = command.substring(1, firstSpaceIndex);
    var arguments =
        (jsonDecode(command.substring(firstSpaceIndex, command.length))
                as List<dynamic>)
            .cast<String>();
    return Process.run(programName, arguments);
  }
  return Process.run('sh', ['-c', command]);
}

void main(List<String> args) async {
  var parser = new ArgParser();
  parser.addMultiOption('file',
      abbr: "f",
      help: 'Read the content from the files. One line for one loop.',
      valueHelp: 'name=file');
  parser.addMultiOption('command',
      abbr: "c",
      help: 'Read the content from the command. One line for one loop.',
      valueHelp: 'name=command');
  parser.addMultiOption('string',
      abbr: "s",
      help: 'Replace the name with the fixed string',
      valueHelp: 'name=string');
  parser.addMultiOption('tempfile',
      abbr: "t",
      help: 'Replace the name with the tempfile path',
      valueHelp: 'name');
  parser.addMultiOption('uuid',
      abbr: "u", help: 'Replace the name with the uuid', valueHelp: 'name');
  parser.addMultiOption('loop',
      abbr: "l", help: 'generate number', valueHelp: 'name');
  parser.addOption('worker', abbr: 'w', defaultsTo: "5");
  parser.addOption('reduce', abbr: 'r', defaultsTo: "");
  parser.addOption('shell', defaultsTo: "sh");
  parser.addOption('store-stdout',
      defaultsTo: "@stdout", help: "Start from 1. eg: @stdout1.");
  parser.addOption('store-stderr',
      defaultsTo: "@stderr", help: "Start from 1. eg: @stderr1.");

  parser.addFlag('help', abbr: "h", negatable: false);
  parser.addFlag('error',
      defaultsTo: false, help: 'Show the result even if the command failed');
  parser.addFlag('stdout', defaultsTo: true, help: 'Print the stdout');
  parser.addFlag('stderr', defaultsTo: true, help: 'Print the stderr');
  parser.addFlag('header', defaultsTo: true, help: 'Show the header');
  parser.addFlag('last',
      defaultsTo: false, help: 'Show the output of the last command');

  var argResults = parser.parse(args);
  var reduceCommand = argResults['reduce'].toString();
  if (argResults['help']) {
    print("acommand [OPTIONS]... COMMAND [COMMAND]...");
    print(parser.usage);
    return;
  }
  if (argResults.rest.length == 0 && reduceCommand.length == 0) {
    print("acommand [OPTIONS]... COMMAND [COMMAND]...");
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

  var runWrapper = (String command) {
    return run(command, shell: argResults['shell']);
  };

  var worker = int.tryParse(argResults['worker']) ?? 5;
  var done = 0;
  var tempDir = Directory.systemTemp.createTempSync();
  var uuid = Uuid();
  var argList = List<Map<String, String>>();
  var lock = Lock(1);

  // Init args
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
    var setting = Setting(i);
    for (var d in argList) {
      d[setting.name] = setting.value;
    }
  }
  for (var i in argResults['loop']) {
    var setting = Setting(i);
    var position = setting.value.indexOf('-');
    var start = 0;
    if (position == -1) {
      var start = int.tryParse(setting.value) ?? 0;
      for (var d in argList) {
        d[setting.name] = start.toString();
        start++;
      }
    }else{
      start = int.tryParse(setting.value.substring(0, position)) ?? 0;
      var end = int.tryParse(setting.value.substring(position + 1)) ?? argList.length;
      for(var j = start;j < end; j++){
        if((j - start) >= argList.length){
          argList.add(Map<String, String>());
        }
        argList[j - start][setting.name] = j.toString();
      }
    }
  }
  for (var i in argResults['tempfile']) {
    for (var d in argList) {
      var filename = uuid.v4();
      d[i] = "${tempDir.path}/$filename";
      File(d[i]).create();
    }
  }
  for (var i in argResults['uuid']) {
    for (var d in argList) {
      d[i] = uuid.v4();
    }
  }

  var stdout = argResults['store-stdout'].toString();
  var stderr = argResults['store-stderr'].toString();
  for (var i = 0; i < argList.length; i++) {
    if (stdout.length > 0) {
      argList[i][stdout] = '${tempDir.path}/$i-stdout';
    }
    if (stderr.length > 0) {
      argList[i][stderr] = '${tempDir.path}/$i-stderr';
    }
  }

  // map
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
      var commandIndex = 0;
      worker -= 1;
      for (var c in argResults.rest.getRange(0, argResults.rest.length)) {
        for (var k in i.keys) {
          c = c.replaceAll(k, i[k]);
        }

        var privateOldCommand = oldCommand;
        var privateCommandIndex = commandIndex;
        fp = fp?.then((p) async {
          if (p == null) {
            return null;
          }
          if (p.pid != 0 && !argResults['last']) {
            showWrapper(privateOldCommand, p);
          }
          await store(p, i[stdout] + privateCommandIndex.toString(),
              i[stderr] + privateCommandIndex.toString());
          if (p.exitCode == 0) {
            return runWrapper(c);
          }
          return null;
        });
        oldCommand = c;
        commandIndex += 1;
      }
      fp?.then((p) async {
        done += 1;
        worker += 1;
        if (p == null) {
          return null;
        }
        await store(p, i[stdout] + commandIndex.toString(),
            i[stderr] + commandIndex.toString());
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

  // reduce
  if (reduceCommand.length > 0) {
    for (var i in argList[0].keys) {
      if (reduceCommand.contains(i)) {
        var s = '';
        if (i == argResults['store-stdout'] ||
            i == argResults['store-stderr']) {
          var re = RegExp(i + '([0-9])+');
          for (var match in re.allMatches(reduceCommand)) {
            var number = match.group(1);
            s = '';
            for (var j = 0; j < argList.length; j++) {
              s += argList[j][i] + number + ' ';
            }
            reduceCommand = reduceCommand.replaceAll(match.group(0), s);
          }
        } else {
          for (var j = 0; j < argList.length; j++) {
            s += argList[j][i] + ' ';
          }
          reduceCommand = reduceCommand.replaceAll(i, s);
        }
      }
    }
    lock = Lock(1);

    runWrapper(reduceCommand).then((p) {
      show(reduceCommand, p, showError: argResults['error']);
      lock.decrease();
    });

    await lock.wait();
  }
  tempDir.deleteSync(recursive: true);
}

void show(String command, ProcessResult p,
    {bool showError = true,
    bool stdout = true,
    bool stderr = true,
    bool header = true}) {
  if (p == null || p?.pid == 0) {
    return;
  }
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
