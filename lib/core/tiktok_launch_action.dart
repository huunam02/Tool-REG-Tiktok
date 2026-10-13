const String tiktokHomeUrl = 'https://www.tiktok.com/?lang=en';
const String tiktokProfileUrl = 'https://www.tiktok.com/profile?lang=en';
const String tiktokLoginUrl =
    'https://www.tiktok.com/login/phone-or-email/email?lang=en';
const String tiktokSignupUrl =
    'https://www.tiktok.com/signup/phone-or-email/email?lang=en';

enum TikTokLaunchAction { browse, login, signup }

extension TikTokLaunchUrl on TikTokLaunchAction {
  String get initialUrl => switch (this) {
        TikTokLaunchAction.browse => tiktokHomeUrl,
        TikTokLaunchAction.login => tiktokLoginUrl,
        TikTokLaunchAction.signup => tiktokSignupUrl,
      };
}
