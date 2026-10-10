import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/theme_provider.dart';
import 'package:spotiflac_android/services/custom_font_service.dart';

final customFontFamilyProvider = FutureProvider<String?>((ref) {
  final id = ref.watch(themeProvider.select((theme) => theme.customFontId));
  return CustomFontService.instance.restore(id);
});
