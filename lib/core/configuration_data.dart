import 'app_configuration.dart';
import 'otp_api.dart';
import 'account_password.dart';
import 'nurture_data.dart';

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
    String? dataMail,
    String? mailboxPassword,
  }) : mailboxPassword = dataMail ?? mailboxPassword ?? '';

  final String email;
  final String password;
  // Keep the existing storage column readable for saved configurations.
  final String mailboxPassword;
  String get dataMail => mailboxPassword;

  static String emailFromDataMail(String value) =>
      value.split('|').first.trim();

  static bool isValidDataMail(String value) {
    final parts = value.trim().split('|');
    return parts.length == 5 &&
        OtpApiConfiguration.isEmail(parts.first) &&
        parts.every((part) => part.trim().isNotEmpty) &&
        !value.contains(RegExp(r'[\r\n]'));
  }

  void validate() {
    if (!OtpApiConfiguration.isEmail(email.trim())) {
      throw const FormatException('Email trong dữ liệu import không hợp lệ.');
    }
    if (password.trim().isEmpty || mailboxPassword.trim().isEmpty) {
      throw const FormatException('Nhập đủ mật khẩu TikTok và Data Mail.');
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
    this.nurtureSettings,
  });

  /// Null for "Mặc định của máy": exports leave the Proxy column empty.
  final WebViewProxy? proxy;
  final AccountCredentials account;
  final AccountStatus statusAccount;

  /// Cấu hình nuôi from an exported workbook; null keeps the form's values.
  final NurtureSettings? nurtureSettings;

  ImportedConfiguration copyWith({NurtureSettings? nurtureSettings}) =>
      ImportedConfiguration(
        proxy: proxy,
        account: account,
        statusAccount: statusAccount,
        nurtureSettings: nurtureSettings ?? this.nurtureSettings,
      );

  /// An empty proxy field keeps the device's own connection.
  static WebViewProxy? parseImportedProxy(String value) =>
      value.trim().isEmpty ? null : WebViewProxy.parseImport(value);

  static List<ImportedConfiguration> parseMany(String input) {
    if (RegExp(
      r'^[^\r\n|]+\.(xlsx|xls|txt)$',
      caseSensitive: false,
    ).hasMatch(input.trim())) {
      throw const FormatException(
        'Đây là tên hoặc đường dẫn file. Chọn Import data > Từ file để đọc dữ liệu Excel/TXT.',
      );
    }
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
        'Nhập ít nhất một cấu hình, mỗi dòng một cấu hình.',
      );
    }
    return records;
  }

  static ImportedConfiguration parse(String input) {
    final line = input.replaceAll(RegExp(r'^[\r\n]+|[\r\n]+$'), '');
    final parts = line.split('|');
    if (!line.contains(RegExp(r'[\r\n]')) &&
        (parts.length == 7 || parts.length == 8)) {
      final dataMail = parts.sublist(1, 6).join('|').trim();
      if (!AccountCredentials.isValidDataMail(dataMail)) {
        throw const FormatException(
          'Data Mail cần đủ email|mật khẩu|refresh token|client ID|email phụ.',
        );
      }
      final status = parts.length == 8 ? parts.last.trim() : '0';
      if (status != '0' && status != '1') {
        throw const FormatException('Trạng thái đăng ký phải là 0 hoặc 1.');
      }
      return ImportedConfiguration(
        proxy: parseImportedProxy(parts.first),
        account: AccountCredentials(
          email: AccountCredentials.emailFromDataMail(dataMail),
          password: parts[6].trim().isEmpty
              ? generateAccountPassword()
              : parts[6],
          dataMail: dataMail,
        ),
        statusAccount: status == '1'
            ? AccountStatus.registered
            : AccountStatus.unregistered,
      );
    }
    if (line.contains('\r') ||
        line.contains('\n') ||
        (parts.length != 4 && parts.length != 5)) {
      throw const FormatException(
        'Nhập một dòng: host:port:user:pass|Data Mail|mật khẩu TikTok[|0/1]. '
        'Các trường ngăn cách bằng dấu |.',
      );
    }
    final proxy = parts.first;
    final accountParts = parts.skip(1).toList();
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
    if (accountParts.length == 3 && accountParts[1].trim().isEmpty) {
      accountParts[1] = generateAccountPassword();
    }
    return ImportedConfiguration(
      proxy: parseImportedProxy(proxy),
      account: AccountCredentials.parseImport(accountParts.join('|')),
      statusAccount: statusAccount,
    );
  }
}
