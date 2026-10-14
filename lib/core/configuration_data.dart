import 'app_configuration.dart';
import 'otp_api.dart';

enum AccountStatus {
  unregistered('Chưa đăng ký'),
  registered('Đã đăng ký');

  const AccountStatus(this.label);
  final String label;
}

class AccountCredentials {
  const AccountCredentials({
    required this.email,
    required this.password,
    required this.mailboxPassword,
  });

  final String email;
  final String password;
  final String mailboxPassword;

  void validate() {
    if (!OtpApiConfiguration.isEmail(email.trim())) {
      throw const FormatException('Email trong dữ liệu import không hợp lệ.');
    }
    if (password.trim().isEmpty || mailboxPassword.trim().isEmpty) {
      throw const FormatException(
        'Nhập đủ mật khẩu TikTok và mật khẩu email OTP.',
      );
    }
  }

  static AccountCredentials parseImport(String input) {
    final line = input.replaceAll(RegExp(r'^[\r\n]+|[\r\n]+$'), '');
    final parts = line.split('|');
    if (line.contains('\n') || line.contains('\r') || parts.length != 3) {
      throw const FormatException(
        'Nhập một dòng: email|mật khẩu TikTok|mật khẩu email OTP.',
      );
    }
    final account = AccountCredentials(
      email: parts[0].trim(),
      password: parts[1],
      mailboxPassword: parts[2],
    );
    account.validate();
    return account;
  }
}

bool sameAccount(AccountCredentials? first, AccountCredentials? second) =>
    first?.email == second?.email &&
    first?.password == second?.password &&
    first?.mailboxPassword == second?.mailboxPassword;

class ImportedConfiguration {
  const ImportedConfiguration({required this.proxy, required this.account});

  final WebViewProxy proxy;
  final AccountCredentials account;

  static ImportedConfiguration parse(String input) {
    final line = input.replaceAll(RegExp(r'^[\r\n]+|[\r\n]+$'), '');
    final separator = line.indexOf(' ');
    if (line.contains('\r') ||
        line.contains('\n') ||
        separator <= 0 ||
        separator == line.length - 1 ||
        RegExp(r'\s').hasMatch(line[separator + 1])) {
      throw const FormatException(
        'Nhập một dòng: host:port:user:pass email|mật khẩu TikTok|mật khẩu email OTP. '
        'Proxy và tài khoản cách nhau một dấu cách.',
      );
    }
    return ImportedConfiguration(
      proxy: WebViewProxy.parseImport(line.substring(0, separator)),
      account: AccountCredentials.parseImport(line.substring(separator + 1)),
    );
  }
}
