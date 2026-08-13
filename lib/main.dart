// lib/main.dart — Suivis douleur + CSV FR + Réglages exportés + pubs AdMob
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

/// Active / désactive les pubs en fonction du build :
///   - par défaut : false (aucune pub)
///   - build avec : flutter build apk --dart-define=SHOW_ADS=true
const bool kShowAds = bool.fromEnvironment('SHOW_ADS', defaultValue: false);

/// ID de bannière **PROD** AdMob Android
const String kBannerAdUnitIdAndroid =
    'ca-app-pub-8341770383248834/5762205942';

const kAppTitle = 'Suivis douleur';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr_FR';

  if (kShowAds && !kIsWeb) {
    await MobileAds.instance.initialize();
  }

  runApp(const MyApp());
}

/* ============================== APP ============================== */

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..load(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: kAppTitle,
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const RootScaffold(),
      ),
    );
  }
}

/* =========================== ROOT SHELL ========================== */

class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int index = 0;
  bool _backupReminderShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBackupReminder();
    });
  }

  Future<void> _checkBackupReminder() async {
    if (_backupReminderShown) return;
    _backupReminderShown = true;

    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('lastExportAt');
    DateTime? last;

    if (raw != null && raw.isNotEmpty) {
      last = DateTime.tryParse(raw);
    }

    final now = DateTime.now();
    bool shouldRemind;

    if (last == null) {
      shouldRemind = true;
    } else {
      final diff = now.difference(last).inDays;
      shouldRemind = diff >= 7;
    }

    if (!shouldRemind || !mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pensez à sauvegarder'),
        content: const Text(
          'Vous n’avez pas exporté vos données depuis plus d’une semaine.\n\n'
          'Conseil : utilisez l’export CSV dans l’onglet Réglages pour garder '
          'une copie de sécurité sur votre drive ou ordinateur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const PlanningPage(), const SettingsPage()];
    final labels = ['Planning', 'Réglages'];
    final icons = [Icons.calendar_month, Icons.settings];

    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          for (int i = 0; i < pages.length; i++)
            NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
        ],
      ),
    );
  }
}

/* ======================= DATA / STATE GLOBALE ==================== */

class DayEntry {
  final Map<String, int> painLevels;
  final Set<String> activities;

  DayEntry({Map<String, int>? painLevels, Set<String>? activities})
      : painLevels = Map.of(painLevels ?? {}),
        activities = Set.of(activities ?? {});

  int maxPain() {
    if (painLevels.values.isEmpty) return 0;
    return painLevels.values.reduce((a, b) => a > b ? a : b);
  }

  Map<String, dynamic> toJson() => {
        'painLevels': painLevels,
        'activities': activities.toList(),
      };

  factory DayEntry.fromJson(Map<String, dynamic> json) => DayEntry(
        painLevels: (json['painLevels'] as Map?)
                ?.map((k, v) => MapEntry('$k', (v as num).toInt())) ??
            {},
        activities:
            ((json['activities'] as List?) ?? []).map((e) => '$e').toSet(),
      );
}

/// Enum de parsing CSV
enum Section { none, pain, act, entries }

class AppState extends ChangeNotifier {
  List<String> painCategories = [
    'Genoux G',
    'Genoux D',
    'Sciatique G',
    'Sciatique D',
    'Dos H',
    'Dos B',
    'Cervicales',
  ];

  List<String> activityTypes = [
    'Marche boulot',
    'Marche sport',
    'Balade',
    'Elliptique',
    'Gainage',
    'Abdos',
    'Pompes',
    'Traction',
    'Dips',
    'Levé de poids',
    'Sexe',
  ];

  final Map<String, DayEntry> entries = {};
  DateTime? lastExportAt;

  static String _key(DateTime local) => DateFormat('yyyy-MM-dd')
      .format(DateTime.utc(local.year, local.month, local.day));

  DayEntry entryFor(DateTime day) => entries[_key(day)] ?? DayEntry();

  /* ----------------------- Mutations ---------------------- */

  void setPainLevel(DateTime day, String cat, int lvl) {
    final k = _key(day);
    final e = entries.putIfAbsent(k, () => DayEntry());
    e.painLevels[cat] = lvl;
    _save();
    notifyListeners();
  }

  void toggleActivity(DateTime day, String act, bool checked) {
    final k = _key(day);
    final e = entries.putIfAbsent(k, () => DayEntry());
    if (checked) {
      e.activities.add(act);
    } else {
      e.activities.remove(act);
    }
    _save();
    notifyListeners();
  }

  void addPainCategory(String n) {
    n = n.trim();
    if (n.isEmpty || painCategories.contains(n)) return;
    painCategories.add(n);
    _save();
    notifyListeners();
  }

  void addActivityType(String n) {
    n = n.trim();
    if (n.isEmpty || activityTypes.contains(n)) return;
    activityTypes.add(n);
    _save();
    notifyListeners();
  }

  void renamePainCategory(String oldName, String newName) {
    newName = newName.trim();
    if (newName.isEmpty || oldName == newName) return;

    final i = painCategories.indexOf(oldName);
    if (i == -1 || painCategories.contains(newName)) return;

    painCategories[i] = newName;

    for (final e in entries.values) {
      if (e.painLevels.containsKey(oldName)) {
        e.painLevels[newName] = e.painLevels.remove(oldName)!;
      }
    }

    _save();
    notifyListeners();
  }

  void renameActivityType(String oldName, String newName) {
    newName = newName.trim();
    if (newName.isEmpty || oldName == newName) return;

    final i = activityTypes.indexOf(oldName);
    if (i == -1 || activityTypes.contains(newName)) return;

    activityTypes[i] = newName;

    for (final e in entries.values) {
      if (e.activities.remove(oldName)) {
        e.activities.add(newName);
      }
    }

    _save();
    notifyListeners();
  }

  void removePainCategory(String n) {
    painCategories.remove(n);
    for (final e in entries.values) {
      e.painLevels.remove(n);
    }
    _save();
    notifyListeners();
  }

  void removeActivityType(String n) {
    activityTypes.remove(n);
    for (final e in entries.values) {
      e.activities.remove(n);
    }
    _save();
    notifyListeners();
  }

  /* ------------------------- Persistence --------------------------- */

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();

    painCategories = sp.getStringList('painCategories') ?? painCategories;
    activityTypes = sp.getStringList('activityTypes') ?? activityTypes;

    final raw = sp.getString('entries');
    if (raw != null && raw.isNotEmpty) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((k, v) {
        entries[k] = DayEntry.fromJson(Map<String, dynamic>.from(v));
      });
    }

    final last = sp.getString('lastExportAt');
    if (last != null && last.isNotEmpty) {
      lastExportAt = DateTime.tryParse(last);
    }

    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('painCategories', painCategories);
    await sp.setStringList('activityTypes', activityTypes);
    await sp.setString('entries', jsonEncode(entries));
    if (lastExportAt != null) {
      await sp.setString('lastExportAt', lastExportAt!.toIso8601String());
    }
  }

  void markExportDone() {
    lastExportAt = DateTime.now();
    _save();
  }

  /* ---------------------- CSV EXPORT (FR) -------------------------- */

  Uint8List buildCsvBytesFr() {
    final sb = StringBuffer();

    sb.writeln('#TYPE=PAIN_CATEGORIES_V1');
    for (final c in painCategories) {
      sb.writeln(_safe(c));
    }

    sb.writeln('#TYPE=ACTIVITY_TYPES_V1');
    for (final a in activityTypes) {
      sb.writeln(_safe(a));
    }

    sb.writeln('#TYPE=ENTRIES_V1');
    sb.writeln('date;parties;douleur;activités');

    final keys = entries.keys.toList()..sort();

    for (final k in keys) {
      final e = entries[k]!;

      for (final kv in e.painLevels.entries) {
        sb.writeln('${_fmtDateFr(k)};${_safe(kv.key)};${kv.value};');
      }

      for (final act in e.activities) {
        sb.writeln('${_fmtDateFr(k)};;;$act');
      }
    }

    return Uint8List.fromList(utf8.encode(sb.toString()));
  }

  String _fmtDateFr(String ymd) {
    final dt = DateTime.parse(ymd);
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  XFile buildCsvXFileFr() {
    final bytes = buildCsvBytesFr();
    return XFile.fromData(
      bytes,
      mimeType: 'text/csv; charset=utf-8',
      name:
          'douleurs_activites_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
    );
  }

  /// Import CSV nouvelle version (avec #TYPE)
  Future<int> importCsvFr(Uint8List bytes) async {
    final text = utf8.decode(bytes);
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) return 0;

    const painMarker = '#TYPE=PAIN_CATEGORIES_V1';
    const actMarker = '#TYPE=ACTIVITY_TYPES_V1';
    const entriesMarker = '#TYPE=ENTRIES_V1';

    Section section = Section.none;

    final importedPain = <String>[];
    final importedAct = <String>[];
    final importedEntries = <String, DayEntry>{};
    bool skipHeaderNextLine = false;
    int count = 0;

    for (final rawLine in lines) {
      final l = rawLine.trim();
      if (l.isEmpty) continue;

      if (l == painMarker) {
        section = Section.pain;
        continue;
      }
      if (l == actMarker) {
        section = Section.act;
        continue;
      }
      if (l == entriesMarker) {
        section = Section.entries;
        skipHeaderNextLine = true;
        continue;
      }

      if (section == Section.pain) {
        importedPain.add(l);
        continue;
      }

      if (section == Section.act) {
        importedAct.add(l);
        continue;
      }

      if (section == Section.entries) {
        if (skipHeaderNextLine) {
          skipHeaderNextLine = false;
          continue;
        }

        final parts = l.split(';');
        if (parts.length < 4) continue;

        final dateFr = parts[0].trim();
        final part = parts[1].trim();
        final lvlStr = parts[2].trim();
        final act = parts[3].trim();

        if (dateFr.isEmpty) continue;

        final dt = DateFormat('dd/MM/yyyy').parse(dateFr);
        final key = DateFormat('yyyy-MM-dd')
            .format(DateTime.utc(dt.year, dt.month, dt.day));

        final e = importedEntries.putIfAbsent(key, () => DayEntry());

        if (part.isNotEmpty && lvlStr.isNotEmpty) {
          final lvl = int.tryParse(lvlStr);
          if (lvl != null && lvl >= 1 && lvl <= 4) {
            e.painLevels[part] = lvl;
          }
        }

        if (act.isNotEmpty) {
          e.activities.add(act);
        }

        count++;
      }
    }

    if (importedPain.isNotEmpty) painCategories = importedPain;
    if (importedAct.isNotEmpty) activityTypes = importedAct;
    if (importedEntries.isNotEmpty) {
      entries
        ..clear()
        ..addAll(importedEntries);
    }

    await _save();
    notifyListeners();
    return count;
  }

  String _safe(String s) => s.replaceAll(';', ',');
}

/* =========================== PLANNING =========================== */

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key});

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planning')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _Legend(),
          ),
          Expanded(
            child: TableCalendar(
              locale: 'fr_FR',
              firstDay: DateTime.utc(2000, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                _openEditor(context, selectedDay);
              },
              availableGestures: AvailableGestures.all,
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              calendarStyle: const CalendarStyle(
                isTodayHighlighted: true,
                outsideDaysVisible: false,
              ),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (_, day, __) => _DayCell(dayLocal: day),
                todayBuilder: (_, day, __) =>
                    _DayCell(dayLocal: day, isToday: true),
                selectedBuilder: (_, day, __) =>
                    _DayCell(dayLocal: day, isSelected: true),
              ),
            ),
          ),
          if (kShowAds) const _BannerBottom(),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, DateTime day) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _DayEditor(dayLocal: day),
      ),
    );
  }
}

class _BannerBottom extends StatefulWidget {
  const _BannerBottom();

  @override
  State<_BannerBottom> createState() => _BannerBottomState();
}

class _BannerBottomState extends State<_BannerBottom> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (!kShowAds || kIsWeb) return;

    final banner = BannerAd(
      size: AdSize.banner,
      adUnitId: kBannerAdUnitIdAndroid,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _banner = ad as BannerAd;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    banner.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _banner == null) return const SizedBox.shrink();
    return SizedBox(
      width: _banner!.size.width.toDouble(),
      height: _banner!.size.height.toDouble(),
      child: AdWidget(ad: _banner!),
    );
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }
}

class _DayCell extends StatelessWidget {
  final DateTime dayLocal;
  final bool isToday;
  final bool isSelected;

  const _DayCell({
    required this.dayLocal,
    this.isToday = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entry = state.entryFor(dayLocal);
    final maxPain = entry.maxPain();

    Color borderColor = Colors.transparent;
    if (maxPain == 1) borderColor = Colors.green;
    if (maxPain == 2) borderColor = Colors.yellow;
    if (maxPain == 3) borderColor = Colors.orange;
    if (maxPain == 4) borderColor = Colors.red;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: maxPain > 0 ? 2 : 0.5),
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5)
            : isToday
                ? Theme.of(context)
                    .colorScheme
                    .secondaryContainer
                    .withOpacity(0.4)
                : null,
      ),
      alignment: Alignment.center,
      margin: const EdgeInsets.all(4),
      child: Text(
        '${dayLocal.day}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  Widget _dot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;

    final children = <Widget>[
      _dot(Colors.green, 'Aucune douleur'),
      SizedBox(width: isPhone ? 0 : 16, height: isPhone ? 6 : 0),
      _dot(Colors.yellow, 'Douleur légère'),
      SizedBox(width: isPhone ? 0 : 16, height: isPhone ? 6 : 0),
      _dot(Colors.orange, 'Douleur moyenne'),
      SizedBox(width: isPhone ? 0 : 16, height: isPhone ? 6 : 0),
      _dot(Colors.red, 'Forte douleur'),
    ];

    return isPhone
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          )
        : Row(children: children);
  }
}

/* ========================= JOUR: ÉDITEUR ========================= */

class _DayEditor extends StatelessWidget {
  final DateTime dayLocal;

  const _DayEditor({required this.dayLocal});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entry = state.entryFor(dayLocal);

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat.yMMMMEEEEd('fr_FR').format(dayLocal)),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Douleurs', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          ...state.painCategories.map(
            (cat) => _PainRow(
              dayLocal: dayLocal,
              category: cat,
              level: entry.painLevels[cat] ?? 1,
            ),
          ),

          const SizedBox(height: 20),
          Text('Activités', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          ...state.activityTypes.map((act) {
            final checked = entry.activities.contains(act);
            return CheckboxListTile(
              title: Text(act),
              value: checked,
              onChanged: (v) =>
                  context.read<AppState>().toggleActivity(dayLocal, act, v ?? false),
            );
          }),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _PainRow extends StatelessWidget {
  final DateTime dayLocal;
  final String category;
  final int level;

  const _PainRow({
    required this.dayLocal,
    required this.category,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    void setLevel(int v) =>
        context.read<AppState>().setPainLevel(dayLocal, category, v);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(category, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _painChip('Aucune', 1, level, setLevel),
                _painChip('Légère', 2, level, setLevel),
                _painChip('Moyenne', 3, level, setLevel),
                _painChip('Forte', 4, level, setLevel),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _painChip(
    String label,
    int value,
    int current,
    void Function(int) setLevel,
  ) {
    final selected = (value == current);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setLevel(value),
    );
  }
}

/* ============================ RÉGLAGES ============================ */

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final painController = TextEditingController();
  final activityController = TextEditingController();

  @override
  void dispose() {
    painController.dispose();
    activityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Exporter / Importer les données',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          // -------- Affichage de la dernière sauvegarde --------
          if (state.lastExportAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Dernière sauvegarde : '
                '${DateFormat('dd/MM/yyyy – HH:mm').format(state.lastExportAt!.toLocal())}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Exporter CSV'),
                  onPressed: () => _showExportSheet(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.file_download),
                  label: const Text('Importer CSV'),
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['csv'],
                      withData: true,
                    );
                    final bytes = result?.files.single.bytes;
                    if (bytes != null) {
                      final count =
                          await context.read<AppState>().importCsvFr(bytes);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('Import terminé : $count ligne(s) importées'),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 16),

          Text('Liste des douleurs',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          _addRow(
            controller: painController,
            hint: 'Ajouter une douleur (ex: Épaule)',
            onAdd: () {
              context.read<AppState>().addPainCategory(painController.text.trim());
              painController.clear();
            },
          ),

          const SizedBox(height: 8),

          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = state.painCategories.removeAt(oldIndex);
              state.painCategories.insert(newIndex, item);
              context.read<AppState>()._save();
              setState(() {});
            },
            children: [
              for (final c in state.painCategories)
                Card(
                  key: ValueKey('pain_$c'),
                  child: ListTile(
                    leading: const Icon(Icons.drag_indicator),
                    title: Text(c),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Renommer',
                          onPressed: () async {
                            final ctrl = TextEditingController(text: c);
                            final newName = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Renommer'),
                                content: TextField(
                                  controller: ctrl,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Annuler'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(
                                      ctx,
                                      ctrl.text.trim(),
                                    ),
                                    child: const Text('Valider'),
                                  ),
                                ],
                              ),
                            );
                            if (newName != null && newName.isNotEmpty) {
                              context.read<AppState>().renamePainCategory(c, newName);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Supprimer',
                          onPressed: () =>
                              context.read<AppState>().removePainCategory(c),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          Text('Liste des activités',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          _addRow(
            controller: activityController,
            hint: 'Ajouter une activité (ex: Étirements)',
            onAdd: () {
              context.read<AppState>().addActivityType(activityController.text.trim());
              activityController.clear();
            },
          ),

          const SizedBox(height: 8),

          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = state.activityTypes.removeAt(oldIndex);
              state.activityTypes.insert(newIndex, item);
              context.read<AppState>()._save();
              setState(() {});
            },
            children: [
              for (final a in state.activityTypes)
                Card(
                  key: ValueKey('act_$a'),
                  child: ListTile(
                    leading: const Icon(Icons.drag_indicator),
                    title: Text(a),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Renommer',
                          onPressed: () async {
                            final ctrl = TextEditingController(text: a);
                            final newName = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Renommer'),
                                content: TextField(controller: ctrl),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Annuler'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(
                                      ctx,
                                      ctrl.text.trim(),
                                    ),
                                    child: const Text('Valider'),
                                  ),
                                ],
                              ),
                            );
                            if (newName != null && newName.isNotEmpty) {
                              context.read<AppState>().renameActivityType(a, newName);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Supprimer',
                          onPressed: () =>
                              context.read<AppState>().removeActivityType(a),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _showExportSheet(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Partager'),
                onTap: () async {
                  Navigator.pop(ctx);

                  final xfile = context.read<AppState>().buildCsvXFileFr();

                  await Share.shareXFiles(
                    [xfile],
                    text: 'Export Douleurs & Activités',
                  );

                  if (context.mounted) {
                    context.read<AppState>().markExportDone();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Enregistrer le fichier CSV'),
                onTap: () async {
                  Navigator.pop(ctx);

                  final bytes = context.read<AppState>().buildCsvBytesFr();
                  final name = context
                      .read<AppState>()
                      .buildCsvXFileFr()
                      .name;

                  try {
                    final path = await FilePicker.platform.saveFile(
                      dialogTitle: 'Enregistrer le CSV',
                      fileName: name,
                      bytes: bytes,
                      type: FileType.custom,
                      allowedExtensions: ['csv'],
                    );

                    if (path != null) {
                      context.read<AppState>().markExportDone();
                    }

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(path == null
                              ? 'Enregistrement annulé'
                              : 'Fichier enregistré ✅'),
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
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _addRow({
    required TextEditingController controller,
    required String hint,
    required VoidCallback onAdd,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Ajouter'),
        ),
      ],
    );
  }
}
