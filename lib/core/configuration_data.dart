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
  const ImportedConfiguration({
    required this.proxy,
    required this.account,
    this.statusAccount = AccountStatus.unregistered,
  });

  final WebViewProxy proxy;
  final AccountCredentials account;
  final AccountStatus statusAccount;

  static List<ImportedConfiguration> parseMany(String input) {
    final lines = input.split(RegExp(r'\r\n|[\r\n]'));
    final records = <ImportedConfiguration>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.trim().isEmpty) continue;
      try {
        records.add(parse(line));
      } on FormatException catch (error) {
        throw FormatException('Dòng ${index + 1}: ${error.message}');
      }
    }
    if (records.isEmpty) {
      throw const FormatException(
          'Nhập ít nhất một cấu hình, mỗi dòng một cấu hình.');
    }
    return records;
  }

  static ImportedConfiguration parse(String input) {
    final line = input.replaceAll(RegExp(r'^[\r\n]+|[\r\n]+$'), '');
    final separator = line.indexOf(' ');
    if (line.contains('\r') ||
        line.contains('\n') ||
        separator <= 0 ||
        separator == line.length - 1 ||
        RegExp(r'\s').hasMatch(line[separator + 1])) {
      throw const FormatException(
        'Nhập một dòng: host:port:user:pass email|mật khẩu TikTok|mật khẩu email OTP[|0/1]. '
        'Proxy và tài khoản cách nhau một dấu cách.',
      );
    }
    final accountParts = line.substring(separator + 1).split('|');
    var statusAccount = AccountStatus.unregistered;
    if (accountParts.length == 4) {
      statusAccount = switch (accountParts.removeLast().trim()) {
        '1' => AccountStatus.registered,
        '0' => AccountStatus.unregistered,
        _ => throw const FormatException(
            'Trạng thái đăng ký phải là 1 (đã đăng ký) hoặc 0 (chưa đăng ký).',
          ),
      };
    }
    return ImportedConfiguration(
      proxy: WebViewProxy.parseImport(line.substring(0, separator)),
      account: AccountCredentials.parseImport(accountParts.join('|')),
      statusAccount: statusAccount,
    );
  }
}
