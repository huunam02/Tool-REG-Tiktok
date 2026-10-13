const String tiktokHomeUrl = 'https://www.tiktok.com/';
const String tiktokProfileUrl = 'https://www.tiktok.com/profile';
const String tiktokLoginUrl =
    'https://www.tiktok.com/login/phone-or-email/email';
const String tiktokSignupUrl =
    'https://www.tiktok.com/signup/phone-or-email/email';

enum TikTokLaunchAction { browse, login, signup }

extension TikTokLaunchUrl on TikTokLaunchAction {
  String get initialUrl => switch (this) {
        TikTokLaunchAction.browse => tiktokHomeUrl,
        TikTokLaunchAction.login => tiktokHomeUrl,
        TikTokLaunchAction.signup => tiktokHomeUrl,
      };
}
