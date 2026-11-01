import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swara/l10n/gen/app_localizations.dart';

import '../providers/library_provider.dart';

/// Stop the bulk metadata scan that is currently running and tell the user
/// what happened.
///
/// Shared by the library header and the Settings tiles so both places report
/// the outcome the same way. [LibraryProvider.cancelBulkScan] only resolves
/// once the scan has actually ended, so the message is shown after the last
/// batch finished instead of while it is still winding down.
Future<void> stopBulkMetadataScan(BuildContext context) async {
  final lib = context.read<LibraryProvider>();
  await lib.cancelBulkScan();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      content: Text(AppLocalizations.of(context)!.scanStopped),
    ),
  );
}
