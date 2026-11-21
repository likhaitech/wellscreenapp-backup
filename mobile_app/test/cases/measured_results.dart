// Reads a measured-result file from the repository (ml/...), for the test
// cases whose plan says "Measured result file". The numbers come from the
// evaluation that was actually run; the test checks them and prints them.

import 'dart:io';

String measuredFile(String pathFromRepoRoot) =>
    File('../$pathFromRepoRoot').readAsStringSync();
