1) Ajouter cet import avec les autres imports :

import 'download_helper.dart';


2) REMPLACER le bouton « Importer CSV » par :

OutlinedButton.icon(
  icon: const Icon(Icons.file_download),
  label: const Text('Importer CSV'),
  onPressed: () async {
    final result = await FilePicker.platform.pickFiles(
      type: kIsWeb ? FileType.any : FileType.custom,
      allowedExtensions: kIsWeb ? null : ['csv'],
      withData: true,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;

    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de lire ce fichier.'),
          ),
        );
      }
      return;
    }

    if (kIsWeb && !file.name.toLowerCase().endsWith('.csv')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Veuillez sélectionner un fichier CSV.'),
          ),
        );
      }
      return;
    }

    final count =
        await context.read<AppState>().importCsvFr(bytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import terminé : $count ligne(s) importées'),
        ),
      );
    }
  },
),


3) Dans _showExportSheet(), REMPLACER uniquement le onTap de
« Enregistrer le fichier CSV » par :

onTap: () async {
  Navigator.pop(ctx);

  final state = context.read<AppState>();
  final bytes = state.buildCsvBytesFr();
  final name = state.buildCsvXFileFr().name;

  try {
    if (kIsWeb) {
      await downloadBytes(bytes, name);
      state.markExportDone();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fichier téléchargé ✅'),
          ),
        );
      }
      return;
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Enregistrer le CSV',
      fileName: name,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (path != null) {
      state.markExportDone();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null
                ? 'Enregistrement annulé'
                : 'Fichier enregistré ✅',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur export : $e')),
      );
    }
  }
},


4) Ne supprime PAS file_picker :
Android continue d'utiliser saveFile().
Web utilise désormais le téléchargement natif du navigateur.

5) Le workflow PWA n'a pas besoin d'être modifié pour cette correction.
