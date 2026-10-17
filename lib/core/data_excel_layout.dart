// Keep the first five columns compatible with the configuration importer.
const configurationExcelHeaders = [
  'Proxy',
  'Email',
  'Password',
  'Mail Password',
  'status(Đã dăng ký)',
  'User-Agent',
  'Múi giờ',
  'Đã sử dụng',
];

// Previous export layouts remain readable by the importer.
const legacyConfigurationExcelHeaders = [
  'Proxy',
  'Email',
  'Password',
  'Mail Password',
  'Status',
  'ID cấu hình',
  'Tên cấu hình',
  'User-Agent',
  'Múi giờ',
  'Đã sử dụng',
  'Proxy URL',
];

const nurtureExcelSheetName = 'Nuoi acc';
const nurtureExcelHeaders = [
  'Email',
  'ID cấu hình',
  'Tên cấu hình',
  ...nurtureStatisticsExcelHeaders,
  'Trạng thái',
  'Cập nhật lúc',
];

const dataExcelSheetName = 'Data';
const dataExcelHeaders = [
  ...configurationExcelHeaders,
  ...nurtureStatisticsExcelHeaders,
];

const legacyDataExcelHeaders = [
  ...legacyConfigurationExcelHeaders,
  ...nurtureStatisticsExcelHeaders,
  'Trạng thái',
  'Cập nhật lúc',
];

const nurtureStatisticsExcelHeaders = [
  'Thời gian xem (ms)',
  'Phút xem',
  'Video đã xem',
  'Video xem hết',
  'Video lướt sớm',
  'Bình luận',
  'Chế độ',
  'Từ khóa',
];

bool matchesExcelHeaders(List<String> cells, List<String> headers) =>
    cells.length == headers.length &&
    List.generate(
      headers.length,
      (i) => cells[i].trim() == headers[i],
    ).every((matches) => matches);
