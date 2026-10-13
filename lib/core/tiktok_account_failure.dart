/// Translate account errors that TikTok logs without displaying in its dialog.
/// Never retain raw console messages: they may contain account information.
class TikTokAccountFailure {
  const TikTokAccountFailure(this.title, this.message,
      {required this.priority});

  final String title;
  final String message;
  final int priority;

  static const rateLimited = TikTokAccountFailure(
    'TikTok đang giới hạn số lần thử',
    'TikTok báo đã đạt số lần thử tối đa. App đã dừng thao tác tài khoản. '
        'Hãy chờ rồi thử lại sau; TikTok chưa cho biết thời gian chờ.',
    priority: 3,
  );

  static const regionFailed = TikTokAccountFailure(
    'TikTok không lấy được khu vực tài khoản',
    'TikTok báo lỗi khi lấy region. App đã dừng thao tác tài khoản. '
        'Chưa xác định được nguyên nhân từ phản hồi này.',
    priority: 2,
  );

  static TikTokAccountFailure? fromConsole(String message) {
    final accountMessage = RegExp(
      r'account-api|email bind failed|get region err|\b(login|sign\s*up):',
      caseSensitive: false,
    ).hasMatch(message);
    if (!accountMessage) return null;
    if (RegExp(
            r'maximum number of attempts reached|too many (attempts|requests)',
            caseSensitive: false)
        .hasMatch(message)) {
      return rateLimited;
    }
    if (RegExp(r'get region err', caseSensitive: false).hasMatch(message)) {
      return regionFailed;
    }
    final code = RegExp(
      r'account-api error:\s*\[(\d+)\]|email bind failed:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(message);
    if (code == null) return null;
    final number = code.group(1) ?? code.group(2);
    return TikTokAccountFailure(
      'TikTok chưa xử lý được yêu cầu tài khoản',
      'TikTok báo lỗi tài khoản (mã $number). App đã dừng thao tác. '
          'Mã lỗi này chưa cho biết nguyên nhân cụ thể.',
      priority: 1,
    );
  }
}
