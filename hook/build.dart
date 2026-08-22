import 'package:flutter_gpu_shaders/build.dart';
// ignore: depend_on_referenced_packages -- dev_dependency, available to hooks.
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'playground.shaderbundle.json',
    );
  });
}
