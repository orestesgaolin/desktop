import 'package:flutter_deck/flutter_deck.dart';

import 'slides/1.dart';
import 'slides/2.dart';
import 'slides/3.dart';
import 'slides/4.dart';
import 'slides/5.dart';
import 'slides/6.dart';
import 'slides/7.dart';
import 'slides/8.dart';
import 'slides/9.dart';
import 'slides/10.dart';
import 'slides/11.dart';
import 'slides/12.dart';
import 'slides/13.dart';
import 'slides/14.dart';
import 'slides/15.dart';
import 'slides/16.dart';
import 'slides/17.dart';
import 'slides/18.dart';
import 'slides/19.dart';
import 'slides/20.dart';
import 'slides/21.dart';
import 'slides/22.dart';
import 'slides/23.dart';
import 'slides/24.dart';
import 'slides/25.dart';
import 'slides/26.dart';
import 'slides/27.dart';
import 'slides/28.dart';
import 'slides/29.dart';

/// Keep the live poll available without making it part of every rehearsal.
const showAudiencePoll = true;

/// The deck, in presentation order.
List<FlutterDeckSlideWidget> buildSlides() => [
  Slide1(),
  if (showAudiencePoll) Slide2(),
  Slide3(),
  Slide4(),
  Slide5(),
  Slide6(),
  Slide7(),
  Slide8(),
  Slide9(),
  Slide10(),
  Slide11(),
  Slide12(),
  Slide13(),
  Slide14(),
  Slide15(),
  Slide16(),
  Slide17(),
  Slide18(),
  Slide19(),
  Slide20(),
  Slide21(),
  Slide22(),
  Slide23(),
  Slide24(),
  Slide25(),
  Slide26(),
  Slide27(),
  Slide28(),
  Slide29(),
];
