import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

class Stage2OnnxService {
  static const channel = MethodChannel('com.example.signlanguage/stage2_onnx');

  Future<String> translate(String gloss) async {
    if (gloss.trim().isEmpty) {
      throw StateError('No glosses recognized. Please try another video.');
    }
    final sentence = await channel.invokeMethod<String>('translate', {
      'gloss': gloss,
    });
    if (sentence == null || sentence.trim().isEmpty) {
      throw StateError(
        'No Korean sentence was generated. Please try another video.',
      );
    }
    debugPrint('KSL_STAGE2_RECV chars=${sentence.length} text=$sentence');
    return sentence.trim();
  }
}
