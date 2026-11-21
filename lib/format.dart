import 'package:easy_localization/easy_localization.dart';

/// Number formats follow the device region; texts follow the app language.
String moneyLocale = 'en';

/// Device region, e.g. "IT". The week starts on Sunday only where that is the norm.
String deviceRegion = '';
const _sundayFirst = {'US', 'CA', 'MX', 'BR', 'JP', 'KR', 'IL', 'PH', 'AU', 'IN', 'SA', 'HK', 'TW'};
int get firstWeekday => _sundayFirst.contains(deviceRegion) ? 0 : 1;

NumberFormat get _money => NumberFormat.simpleCurrency(locale: moneyLocale, name: 'EUR');

/// Uses a real minus sign for negative amounts.
String money(int cents) => cents < 0 ? '−${_money.format(-cents / 100)}' : _money.format(cents / 100);

/// Signed amount with a real minus sign and an explicit `+` for positives.
String signedMoney(int cents) => cents > 0 ? '+${money(cents)}' : money(cents);

/// Splits a formatted amount around its cents so they can be drawn smaller:
/// "€1,284.50" gives ("€1,284", ".50", ""); "1.284,50 €" gives ("1.284", ",50", " €").
(String, String, String) splitCents(String formatted) {
  final m = RegExp('${RegExp.escape(decimalSeparator())}\\d{2}').allMatches(formatted).lastOrNull;
  if (m == null) return (formatted, '', '');
  return (formatted.substring(0, m.start), m[0]!, formatted.substring(m.end));
}

String decimalSeparator() => NumberFormat.decimalPattern(moneyLocale).symbols.DECIMAL_SEP;

String groupInt(int n) => NumberFormat.decimalPattern(moneyLocale).format(n);

String dayLabel(DateTime d, String lang, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime.utc(n.year, n.month, n.day);
  final day = DateTime.utc(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'day.today'.tr();
  if (diff == 1) return 'day.yesterday'.tr();
  if (day.year == today.year) return DateFormat.MMMEd(lang).format(d);
  return DateFormat.yMMMEd(lang).format(d);
}

String monthName(DateTime d, String lang) => DateFormat.MMMM(lang).format(d);
