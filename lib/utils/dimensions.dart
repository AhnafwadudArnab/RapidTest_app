import 'package:get/get.dart';

class Dimensions {
  // Screen dimensions
  static double get screenHeight => Get.context?.height ?? 800.0;
  static double get screenWidth => Get.context?.width ?? 400.0;

  // PageView dimensions
  static double get pageView => screenHeight / 3.04;
  static double get pageViewContainers => screenHeight / 4.14;
  static double get pageViewTextContainers => screenHeight / 7.26;

  // Heights
  static double get height3 => screenHeight / 324.44;
  static double get height5 => screenHeight / 194.66;
  static double get height8 => screenHeight / 121.66;
  static double get height10 => screenHeight / 97.33;
  static double get height15 => screenHeight / 64.889;
  static double get height20 => screenHeight / 48.67;
  static double get height30 => screenHeight / 34.76;
  static double get height40 => screenHeight / 24.33;
  static double get height45 => screenHeight / 29.629;
  static double get height49 => screenHeight / 19.86;
  static double get height52 => screenHeight / 18.71;
  static double get height100 => screenHeight / 9.733;
  static double get height130 => screenHeight / 7.48;
  static double get height180 => screenHeight / 5.40;
  static double get height300 => screenHeight / 3.24;

  // Widths
  static double get width4 => screenHeight / 243.33;
  static double get width10 => screenHeight / 97.33;
  static double get width15 => screenHeight / 64.88;
  static double get width20 => screenHeight / 48.67;
  static double get width30 => screenHeight / 32.44;
  static double get width45 => screenHeight / 29.629;
  static double get width100 => screenHeight / 9.733;
  static double get width200 => screenHeight / 4.866;

  // Fonts
  static double get font15 => screenHeight / 64.88;
  static double get font17 => screenHeight / 57.25;
  static double get font20 => screenHeight / 48.67;
  static double get font26 => screenHeight / 37.43;

  // Radii
  static double get radius6 => screenHeight / 162.22;
  static double get radius8 => screenHeight / 121.66;
  static double get radius10 => screenHeight / 97.33;
  static double get radius15 => screenHeight / 64.88;
  static double get radius20 => screenHeight / 48.67;
  static double get radius30 => screenHeight / 32.44;
  static double get radius35 => screenHeight / 27.80;
  static double get radius40 => screenHeight / 24.33;

  // Icon sizes
  static double get iconSize16 => screenHeight / 60.83;
  static double get iconSize24 => screenHeight / 40.55;
  static double get iconSize40 => screenHeight / 24.33;
  static double get iconSize50 => screenHeight / 19.4666;

  // ListView dimensions
  static double get listViewImageSize => screenHeight / 8.2;
  static double get listViewTextContSize => screenHeight / 9.7333;

  // Popular image size
  static double get popularImageSize250 => screenHeight / 3.89;

  // Bottom Navigation Bar
  static double get bottomNavigationBar120 => screenHeight / 8.11;
}
