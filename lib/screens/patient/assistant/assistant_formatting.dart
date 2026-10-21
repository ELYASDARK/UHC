import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../../../core/utils/locale_utils.dart';

String formatAssistantDate(String yyyyMmDd, BuildContext context) {
  final date = DateTime.tryParse(yyyyMmDd);
  if (date == null) return yyyyMmDd;
  return intl.DateFormat.yMMMMEEEEd(safeIntlLocale(context)).format(date);
}
