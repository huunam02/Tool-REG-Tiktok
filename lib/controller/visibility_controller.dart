import 'app_controller.dart';

class VisibilityController extends AppController {
  bool hidden = true;

  void toggle() => mutate(() => hidden = !hidden);
  void reset() => mutate(() => hidden = true);
}
