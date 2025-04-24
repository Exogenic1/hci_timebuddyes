import 'package:flutter/material.dart';
import 'package:time_buddies/services/language_service.dart';

class LanguageDialog extends StatefulWidget {
  final Function() onLanguageChanged;

  const LanguageDialog({
    super.key,
    required this.onLanguageChanged,
  });

  @override
  State<LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<LanguageDialog> {
  String _selectedLanguageCode = LanguageService.defaultLanguageCode;

  @override
  void initState() {
    super.initState();
    _getCurrentLanguage();
  }

  Future<void> _getCurrentLanguage() async {
    final locale = await LanguageService.getCurrentLocale();
    setState(() {
      _selectedLanguageCode = locale.languageCode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Language'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: LanguageService.supportedLanguages.length,
          itemBuilder: (context, index) {
            final languageCode =
                LanguageService.supportedLanguages.keys.elementAt(index);
            final languageName =
                LanguageService.supportedLanguages[languageCode]!['name']!;

            return RadioListTile<String>(
              title: Text(languageName),
              value: languageCode,
              groupValue: _selectedLanguageCode,
              onChanged: (value) {
                setState(() {
                  _selectedLanguageCode = value!;
                });
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            await LanguageService.setLanguage(_selectedLanguageCode);
            widget.onLanguageChanged();
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
