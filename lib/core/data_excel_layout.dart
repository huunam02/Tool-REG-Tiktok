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
  ...legacyNurtureStatisticsExcelHeaders,
  'Trạng thái',
  'Cập nhật lúc',
];

// Each configuration's Cấu hình nuôi; restored by the importer.
const nurtureSettingsExcelHeaders = [
  'Tỷ lệ thả tim (%)',
  'Tỷ lệ bình luận (%)',
  'Tỷ lệ xem lâu (%)',
  'Nuôi tối thiểu (phút)',
  'Nuôi tối đa (phút)',
];

/// The configuration's phone GPU (a GpuProfile id); restored by the importer.
const gpuProfileExcelHeader = 'Thiết bị GPU';

const dataExcelSheetName = 'Data';
const dataExcelHeaders = [
  ...configurationExcelHeaders,
  gpuProfileExcelHeader,
  ...nurtureSettingsExcelHeaders,
  ...nurtureStatisticsExcelHeaders,
];

/// The combined export before Cấu hình nuôi columns existed.
const previousDataExcelHeaders = [
  ...configurationExcelHeaders,
  ...legacyNurtureStatisticsExcelHeaders,
];

const legacyDataExcelHeaders = [
  ...legacyConfigurationExcelHeaders,
  ...legacyNurtureStatisticsExcelHeaders,
  'Trạng thái',
  'Cập nhật lúc',
];

// Feed or search is chosen at random each session, so the mode and keyword
// are not exported.
const nurtureStatisticsExcelHeaders = [
  'Thời gian xem (ms)',
  'Phút xem',
  'Video đã xem',
  'Video xem hết',
  'Video lướt sớm',
  'Bình luận',
];

/// Earlier exports also listed the last session's mode and keyword.
const legacyNurtureStatisticsExcelHeaders = [
  ...nurtureStatisticsExcelHeaders,
  'Chế độ',
  'Từ khóa',
];

bool matchesExcelHeaders(List<String> cells, List<String> headers) =>
    cells.length == headers.length &&
    List.generate(
      headers.length,
      (i) => cells[i].trim() == headers[i],
    ).every((matches) => matches);
