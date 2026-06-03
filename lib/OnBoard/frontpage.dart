import 'package:flutter/material.dart';
import 'package:myproject/All%20in%20one/Registrations/signup.dart';

import '../../Widgets/Big_Contents_models.dart';
import '../../widgets/entry_animation.dart';
import '../../utils/dimensions.dart';

class Onboard extends StatefulWidget {
  const Onboard({super.key});

  @override
  State<Onboard> createState() => _OnboardState();
}

class _OnboardState extends State<Onboard> {
  int currentIndex = 0;
  bool _isAnimating = false;
  late PageController _controller;

  @override
  void initState() {
    _controller = PageController(initialPage: 0);
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final size = MediaQuery.sizeOf(context);
    final cacheWidth =
        (size.width * MediaQuery.devicePixelRatioOf(context)).round();
    final cacheHeight =
        (size.height * 0.48 * MediaQuery.devicePixelRatioOf(context)).round();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final content in contents) {
        precacheImage(
          ResizeImage(
            AssetImage(content.image),
            width: cacheWidth,
            height: cacheHeight,
          ),
          context,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final imageHeight = size.height * 0.48;
    final imageCacheWidth = (size.width * devicePixelRatio).round();
    final imageCacheHeight = (imageHeight * devicePixelRatio).round();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                allowImplicitScrolling: true,
                itemCount: contents.length,
                onPageChanged: (int index) {
                  if (currentIndex != index) {
                    setState(() {
                      currentIndex = index;
                    });
                  }
                },
                itemBuilder: (_, i) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 28,
                              left: 20,
                              right: 20,
                            ),
                            child: Column(
                              children: [
                                EntryAnimation(
                                  index: 0,
                                  child: RepaintBoundary(
                                    child: Image.asset(
                                      contents[i].image,
                                      height: imageHeight,
                                      width: size.width,
                                      fit: BoxFit.contain,
                                      cacheWidth: imageCacheWidth,
                                      cacheHeight: imageCacheHeight,
                                      filterQuality: FilterQuality.low,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                ),
                                SizedBox(height: Dimensions.height30),
                                EntryAnimation(
                                  index: 1,
                                  child: Text(
                                    contents[i].title,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: Dimensions.font26,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                SizedBox(height: Dimensions.height10),
                                EntryAnimation(
                                  index: 2,
                                  child: Text(
                                    contents[i].description,
                                    style: TextStyle(
                                      fontSize: Dimensions.font15,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                contents.length,
                (index) => buildDot(index, context),
              ),
            ),
            AnimatedPressable(
              onTap: () async {
                if (_isAnimating) return;
                if (currentIndex == contents.length - 1) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const SignUpPage()),
                  );
                  return;
                }
                _isAnimating = true;
                try {
                  await _controller.nextPage(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                  );
                } finally {
                  _isAnimating = false;
                }
              },
              borderRadius: BorderRadius.circular(Dimensions.radius35),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Dimensions.radius35),
                  color: Colors.blueAccent,
                ),
                height: 58,
                margin: const EdgeInsets.fromLTRB(40, 22, 40, 28),
                width: double.infinity,
                child: Center(
                  child: Text(
                    currentIndex == contents.length - 1 ? "Start" : "Next",
                    style: TextStyle(
                      fontSize: Dimensions.font20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AnimatedContainer buildDot(int index, BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: Dimensions.height10,
      width: currentIndex == index ? 18 : 7,
      margin: const EdgeInsets.only(right: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Dimensions.radius6),
        color: currentIndex == index ? Colors.blueAccent : Colors.black38,
      ),
    );
  }
}
