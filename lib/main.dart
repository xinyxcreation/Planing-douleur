// lib/main.dart — Suivis douleur + CSV FR + Réglages exportés + pubs AdMob
import 'dart:convert';

import 'download_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'auth/auth_state.dart';
import 'models/pain_category.dart';
import 'models/activity_type.dart';
import 'models/day_entry.dart';
import 'models/day_pain_level.dart';
import 'models/day_activity.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'sync/sync_config.dart';
import 'sync/remote_change.dart';
import 'sync/sync_storage.dart';
import 'sync/api_client.dart';
import 'sync/sync_manager.dart';
import 'package:uuid/uuid.dart';

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
      create: (_) => AuthState()..load(),
      child: Consumer<AuthState>(
        builder: (context, auth, _) {
          if (auth.isLoading) {
            return const MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }

          return ChangeNotifierProvider(
            create: (_) => AppState()..load(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              title: kAppTitle,
              themeMode: ThemeMode.system,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.teal,
                ),
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
              supportedLocales: const [
                Locale('fr', 'FR'),
                Locale('en', 'US'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: auth.isLoggedIn
                  ? const RootScaffold()
                  : const LoginPage(),
            ),
          );
        },
      ),
    );
  }
}


/* ============================== AUTH =============================== */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _registerMode = false;
  bool _rememberMe = true;
  bool _obscurePassword = true;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _busy = true);

    final auth = context.read<AuthState>();

    bool success;

    if (_registerMode) {
      success = await auth.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
        rememberMe: _rememberMe,
      );
    } else {
      success = await auth.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        rememberMe: _rememberMe,
      );
    }

    if (!mounted) return;

    setState(() => _busy = false);

    if (!success && auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 420,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.health_and_safety,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),

                    const SizedBox(height: 20),

                    Text(
                      kAppTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      _registerMode
                          ? 'Créer votre compte'
                          : 'Connectez-vous à votre compte',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),

                    const SizedBox(height: 32),

                    if (_registerMode) ...[
                      TextFormField(
                        controller: _displayNameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nom ou prénom',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Adresse email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';

                        if (email.isEmpty) {
                          return 'Adresse email obligatoire.';
                        }

                        if (!email.contains('@')) {
                          return 'Adresse email invalide.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: _registerMode
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Mot de passe obligatoire.';
                        }

                        if (_registerMode && value.length < 8) {
                          return '8 caractères minimum.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 8),

                    CheckboxListTile(
                      value: _rememberMe,
                      onChanged: _busy
                          ? null
                          : (value) {
                              setState(() {
                                _rememberMe = value ?? true;
                              });
                            },
                      title: const Text('Se souvenir de moi'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                    const SizedBox(height: 16),

                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _registerMode
                                    ? 'Créer mon compte'
                                    : 'Se connecter',
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _registerMode = !_registerMode;
                              });
                            },
                      child: Text(
                        _registerMode
                            ? 'J’ai déjà un compte'
                            : 'Créer un nouveau compte',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

  @override
  void initState() {
    super.initState();
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

/// Enum de parsing CSV
enum Section { none, pain, act, entries }

class AppState extends ChangeNotifier {
  final SyncStorage _syncStorage = SyncStorage();
  late final ApiClient _apiClient;
  late final SyncManager _syncManager;

  bool _syncInitialized = false;

  static const Uuid _uuid = Uuid();

  static const String _pendingSyncKey =
      'pendingSyncChangesV1';

  void initSync({
    required String userId,
  }) {
    if (_syncInitialized) {
      _syncManager.userId = userId;
      return;
    }

    _apiClient = ApiClient(
      baseUrl: SyncConfig.baseUrl,
    );

    _syncManager = SyncManager(
      apiClient: _apiClient,
      storage: _syncStorage,
      userId: userId,
      onRemoteChange: (change) async {
        await _applyRemoteChange(change);
      },
      getPendingChanges: _getPendingChanges,
      clearPendingChanges: _clearPendingChanges,
    );

    _syncInitialized = true;
  }

  Future<List<Map<String, dynamic>>> _getPendingChanges() async {
    final sp = await SharedPreferences.getInstance();

    final raw = sp.getString(_pendingSyncKey);

    if (raw == null || raw.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => Map<String, dynamic>.from(item),
          )
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _queueSyncChange({
    required String entity,
    required String operation,
    required Map<String, dynamic> data,
  }) async {
    final sp = await SharedPreferences.getInstance();

    final pending = await _getPendingChanges();

    pending.add({
      'entity': entity,
      'operation': operation,
      'data': data,
    });

    await sp.setString(
      _pendingSyncKey,
      jsonEncode(pending),
    );
  }

  Future<void> _clearPendingChanges() async {
    final sp = await SharedPreferences.getInstance();

    await sp.remove(_pendingSyncKey);
  }

  Future<void> _saveAndQueue({
    required String entity,
    required String operation,
    required Map<String, dynamic> data,
  }) async {
    await _save();

    await _queueSyncChange(
      entity: entity,
      operation: operation,
      data: data,
    );

    try {
      await syncNow();
    } catch (_) {
      // Le changement reste dans pendingSyncChangesV1.
      // Il sera envoyé à la prochaine synchronisation.
    }
  }

  Future<void> syncNow() async {
    final auth = AuthState();

    await auth.load();

    final token = auth.token;
    final userId = auth.userId;

    if (token == null ||
        token.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      return;
    }

    initSync(userId: userId);

    _apiClient.token = token;
    _syncManager.userId = userId;

    await _syncManager.sync();
  }

  List<PainCategory> painCategories = [
    PainCategory(id: _uuid.v7(), name: 'Genoux G', position: 0),
    PainCategory(id: _uuid.v7(), name: 'Genoux D', position: 1),
    PainCategory(id: _uuid.v7(), name: 'Sciatique G', position: 2),
    PainCategory(id: _uuid.v7(), name: 'Sciatique D', position: 3),
    PainCategory(id: _uuid.v7(), name: 'Dos H', position: 4),
    PainCategory(id: _uuid.v7(), name: 'Dos B', position: 5),
    PainCategory(id: _uuid.v7(), name: 'Cervicales', position: 6),
  ];

  List<ActivityType> activityTypes = [
    ActivityType(id: _uuid.v7(), name: 'Marche boulot', position: 0),
    ActivityType(id: _uuid.v7(), name: 'Marche sport', position: 1),
    ActivityType(id: _uuid.v7(), name: 'Balade', position: 2),
    ActivityType(id: _uuid.v7(), name: 'Elliptique', position: 3),
    ActivityType(id: _uuid.v7(), name: 'Gainage', position: 4),
    ActivityType(id: _uuid.v7(), name: 'Abdos', position: 5),
    ActivityType(id: _uuid.v7(), name: 'Pompes', position: 6),
    ActivityType(id: _uuid.v7(), name: 'Traction', position: 7),
    ActivityType(id: _uuid.v7(), name: 'Dips', position: 8),
    ActivityType(id: _uuid.v7(), name: 'Levé de poids', position: 9),
    ActivityType(id: _uuid.v7(), name: 'Sexe', position: 10),
  ];

  final Map<String, DayEntry> entries = {};

  static String _key(DateTime local) => DateFormat('yyyy-MM-dd')
      .format(DateTime.utc(local.year, local.month, local.day));

  PainCategory? painCategoryByName(String name) {
    for (final category in painCategories) {
      if (category.name == name) return category;
    }
    return null;
  }

  ActivityType? activityTypeByName(String name) {
    for (final type in activityTypes) {
      if (type.name == name) return type;
    }
    return null;
  }

  PainCategory? painCategoryById(String id) {
    for (final category in painCategories) {
      if (category.id == id) return category;
    }
    return null;
  }

  ActivityType? activityTypeById(String id) {
    for (final type in activityTypes) {
      if (type.id == id) return type;
    }
    return null;
  }

  DayEntry entryFor(DateTime day) {
    final key = _key(day);

    return entries[key] ??= DayEntry(
      id: _uuid.v7(),
      entryDate: key,
    );
  }

  Future<void> setPainLevel(
    DateTime day,
    String cat,
    int lvl,
  ) async {
    final category = painCategoryByName(cat);
    if (category == null) return;

    final key = _key(day);
    final wasNewEntry = !entries.containsKey(key);

    final entry = entryFor(day);

    final index = entry.painLevels.indexWhere(
      (pain) => pain.painCategoryId == category.id,
    );

    final isNewPain = index < 0;

    final pain = DayPainLevel(
      id: isNewPain
          ? _uuid.v7()
          : entry.painLevels[index].id,
      dayEntryId: entry.id,
      painCategoryId: category.id,
      level: lvl,
    );

    if (isNewPain) {
      entry.painLevels.add(pain);
    } else {
      entry.painLevels[index] = pain;
    }

    await _save();

    if (wasNewEntry) {
      await _queueSyncChange(
        entity: 'day_entry',
        operation: 'INSERT',
        data: entry.toJson(),
      );
    }

    await _queueSyncChange(
      entity: 'day_pain_level',
      operation: isNewPain ? 'INSERT' : 'UPDATE',
      data: pain.toJson(),
    );

    notifyListeners();

    try {
      await syncNow();
    } catch (_) {
      // Les changements restent dans la file locale.
    }
  }

  Future<void> toggleActivity(
    DateTime day,
    String act,
    bool checked,
  ) async {
    final activityType = activityTypeByName(act);
    if (activityType == null) return;

    final key = _key(day);
    final wasNewEntry = !entries.containsKey(key);

    final entry = entryFor(day);

    final index = entry.activities.indexWhere(
      (activity) => activity.activityTypeId == activityType.id,
    );

    if (checked) {
      if (index >= 0) {
        return;
      }

      final activity = DayActivity(
        id: _uuid.v7(),
        dayEntryId: entry.id,
        activityTypeId: activityType.id,
      );

      entry.activities.add(activity);

      await _save();

      if (wasNewEntry) {
        await _queueSyncChange(
          entity: 'day_entry',
          operation: 'INSERT',
          data: entry.toJson(),
        );
      }

      await _queueSyncChange(
        entity: 'day_activity',
        operation: 'INSERT',
        data: activity.toJson(),
      );
    } else {
      if (index < 0) {
        return;
      }

      final activity = entry.activities[index];

      entry.activities.removeAt(index);

      await _save();

      await _queueSyncChange(
        entity: 'day_activity',
        operation: 'DELETE',
        data: activity.toJson(),
      );
    }

    notifyListeners();

    try {
      await syncNow();
    } catch (_) {
      // Les changements restent dans la file locale.
    }
  }

  void addPainCategory(String n) {
    n = n.trim();

    if (n.isEmpty ||
        painCategories.any((category) => category.name == n)) {
      return;
    }

    final item = PainCategory(
      id: _uuid.v7(),
      name: n,
      position: painCategories.length,
    );

    painCategories.add(item);

    _saveAndQueue(
      entity: 'pain_category',
      operation: 'INSERT',
      data: item.toJson(),
    );

    notifyListeners();
  }

  void addActivityType(String n) {
    n = n.trim();

    if (n.isEmpty ||
        activityTypes.any((activity) => activity.name == n)) {
      return;
    }

    final item = ActivityType(
      id: _uuid.v7(),
      name: n,
      position: activityTypes.length,
    );

    activityTypes.add(item);

    _saveAndQueue(
      entity: 'activity_type',
      operation: 'INSERT',
      data: item.toJson(),
    );

    notifyListeners();
  }

  void renamePainCategory(String oldName, String newName) {
    newName = newName.trim();

    if (newName.isEmpty || oldName == newName) return;

    final index = painCategories.indexWhere(
      (category) => category.name == oldName,
    );

    if (index == -1 ||
        painCategories.any((category) => category.name == newName)) {
      return;
    }

    final oldCategory = painCategories[index];

    painCategories[index] = PainCategory(
      id: oldCategory.id,
      name: newName,
      position: oldCategory.position,
      deletedAt: oldCategory.deletedAt,
    );

    _save();
    notifyListeners();
  }

  void renameActivityType(String oldName, String newName) {
    newName = newName.trim();

    if (newName.isEmpty || oldName == newName) return;

    final index = activityTypes.indexWhere(
      (activity) => activity.name == oldName,
    );

    if (index == -1 ||
        activityTypes.any((activity) => activity.name == newName)) {
      return;
    }

    final oldActivity = activityTypes[index];

    activityTypes[index] = ActivityType(
      id: oldActivity.id,
      name: newName,
      position: oldActivity.position,
      deletedAt: oldActivity.deletedAt,
    );

    _save();
    notifyListeners();
  }

  void removePainCategory(String name) {
    final index = painCategories.indexWhere(
      (category) => category.name == name,
    );

    if (index == -1) return;

    final category = painCategories[index];

    painCategories[index] = PainCategory(
      id: category.id,
      name: category.name,
      position: category.position,
      deletedAt: DateTime.now().toUtc(),
    );

    _save();
    notifyListeners();
  }

  void removeActivityType(String name) {
    final index = activityTypes.indexWhere(
      (activity) => activity.name == name,
    );

    if (index == -1) return;

    final activity = activityTypes[index];

    activityTypes[index] = ActivityType(
      id: activity.id,
      name: activity.name,
      position: activity.position,
      deletedAt: DateTime.now().toUtc(),
    );

    _save();
    notifyListeners();
  }

  Future<void> _applyRemoteChange(
    RemoteChange change,
  ) async {
    switch (change.entity) {
      case 'pain_category':
        _applyPainCategoryChange(change);
        break;

      case 'activity_type':
        _applyActivityTypeChange(change);
        break;

      case 'day_entry':
        _applyDayEntryChange(change);
        break;

      case 'day_pain_level':
        _applyDayPainLevelChange(change);
        break;

      case 'day_activity':
        _applyDayActivityChange(change);
        break;

      default:
        throw StateError(
          'Entité distante inconnue : ${change.entity}',
        );
    }

    await _save();
    notifyListeners();
  }

  void _applyPainCategoryChange(RemoteChange change) {
    final data = change.data;
    if (data == null) return;

    final id = data['id']?.toString();
    final name = data['name']?.toString();

    if (id == null || name == null) return;

    final position = (data['position'] as num?)?.toInt() ?? 0;
    final deleted = data['deletedAt'] != null;

    final index = painCategories.indexWhere(
      (item) => item.id == id,
    );

    if (deleted) {
      if (index >= 0) {
        painCategories.removeAt(index);
      }
      return;
    }

    final item = PainCategory(
      id: id,
      name: name,
      position: position,
    );

    if (index >= 0) {
      painCategories[index] = item;
    } else {
      painCategories.add(item);
    }
  }

  void _applyActivityTypeChange(RemoteChange change) {
    final data = change.data;
    if (data == null) return;

    final id = data['id']?.toString();
    final name = data['name']?.toString();

    if (id == null || name == null) return;

    final position = (data['position'] as num?)?.toInt() ?? 0;
    final deleted = data['deletedAt'] != null;

    final index = activityTypes.indexWhere(
      (item) => item.id == id,
    );

    if (deleted) {
      if (index >= 0) {
        activityTypes.removeAt(index);
      }
      return;
    }

    final item = ActivityType(
      id: id,
      name: name,
      position: position,
    );

    if (index >= 0) {
      activityTypes[index] = item;
    } else {
      activityTypes.add(item);
    }
  }

  void _applyDayEntryChange(RemoteChange change) {
    final data = change.data;
    if (data == null) return;

    final id = data['id']?.toString();
    final date = data['entryDate']?.toString();

    if (id == null || date == null || date.isEmpty) {
      return;
    }

    if (change.operation == 'DELETE' ||
        data['deletedAt'] != null) {
      entries.remove(date);
      return;
    }

    entries[date] ??= DayEntry(
      id: id,
      entryDate: date,
    );
  }

  void _applyDayPainLevelChange(RemoteChange change) {
    final data = change.data;
    if (data == null) return;

    final id = data['id']?.toString();
    final dayEntryId = data['dayEntryId']?.toString();
    final painCategoryId =
        data['painCategoryId']?.toString();
    final level =
        (data['level'] as num?)?.toInt();

    if (id == null ||
        dayEntryId == null ||
        painCategoryId == null ||
        level == null) {
      return;
    }

    DayEntry? entry;

    for (final candidate in entries.values) {
      if (candidate.id == dayEntryId) {
        entry = candidate;
        break;
      }
    }

    if (entry == null) return;

    entry.painLevels.removeWhere(
      (item) => item.id == id,
    );

    if (change.operation != 'DELETE' &&
        data['deletedAt'] == null) {
      entry.painLevels.add(
        DayPainLevel(
          id: id,
          dayEntryId: dayEntryId,
          painCategoryId: painCategoryId,
          level: level,
        ),
      );
    }
  }

  void _applyDayActivityChange(RemoteChange change) {
    final data = change.data;
    if (data == null) return;

    final id = data['id']?.toString();
    final dayEntryId = data['dayEntryId']?.toString();
    final activityTypeId =
        data['activityTypeId']?.toString();

    if (id == null ||
        dayEntryId == null ||
        activityTypeId == null) {
      return;
    }

    DayEntry? entry;

    for (final candidate in entries.values) {
      if (candidate.id == dayEntryId) {
        entry = candidate;
        break;
      }
    }

    if (entry == null) return;

    entry.activities.removeWhere(
      (item) => item.id == id,
    );

    if (change.operation != 'DELETE' &&
        data['deletedAt'] == null) {
      entry.activities.add(
        DayActivity(
          id: id,
          dayEntryId: dayEntryId,
          activityTypeId: activityTypeId,
        ),
      );
    }
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();

    final rawPain = sp.getString('painCategoriesV2');
    final rawActivity = sp.getString('activityTypesV2');

    if (rawPain != null && rawPain.isNotEmpty) {
      final decoded = jsonDecode(rawPain);

      if (decoded is List) {
        painCategories = decoded
            .whereType<Map>()
            .map(
              (e) => PainCategory.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList();
      }
    }

    if (rawActivity != null && rawActivity.isNotEmpty) {
      final decoded = jsonDecode(rawActivity);

      if (decoded is List) {
        activityTypes = decoded
            .whereType<Map>()
            .map(
              (e) => ActivityType.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList();
      }
    }

    final raw = sp.getString('entriesV2');

    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);

      if (decoded is Map) {
        entries.clear();

        decoded.forEach((key, value) {
          if (value is Map) {
            entries[key.toString()] =
                DayEntry.fromJson(
              Map<String, dynamic>.from(value),
            );
          }
        });
      }
    }

    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();

    await sp.setString(
      'painCategoriesV2',
      jsonEncode(
        painCategories.map((e) => e.toJson()).toList(),
      ),
    );

    await sp.setString(
      'activityTypesV2',
      jsonEncode(
        activityTypes.map((e) => e.toJson()).toList(),
      ),
    );

    await sp.setString(
      'entriesV2',
      jsonEncode(
        entries.map(
          (key, value) => MapEntry(
            key,
            value.toJson(),
          ),
        ),
      ),
    );
  }

  /* ---------------------- CSV EXPORT (FR) -------------------------- */

  Uint8List buildCsvBytesFr() {
    final sb = StringBuffer();

    sb.writeln('#TYPE=PAIN_CATEGORIES_V1');
    for (final c in painCategories) {
      if (c.deletedAt == null) {
        sb.writeln(_safe(c.name));
      }
    }

    sb.writeln('#TYPE=ACTIVITY_TYPES_V1');
    for (final a in activityTypes) {
      if (a.deletedAt == null) {
        sb.writeln(_safe(a.name));
      }
    }

    sb.writeln('#TYPE=ENTRIES_V1');
    sb.writeln('date;parties;douleur;activités');

    final keys = entries.keys.toList()..sort();

    for (final k in keys) {
      final e = entries[k]!;

      for (final pain in e.painLevels) {
        final category = painCategoryById(pain.painCategoryId);

        if (category != null && category.deletedAt == null) {
          sb.writeln(
            '${_fmtDateFr(k)};${_safe(category.name)};${pain.level};',
          );
        }
      }

      for (final activity in e.activities) {
        final type = activityTypeById(activity.activityTypeId);

        if (type != null && type.deletedAt == null) {
          sb.writeln(
            '${_fmtDateFr(k)};;;${_safe(type.name)}',
          );
        }
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

        final e = importedEntries.putIfAbsent(
        key,
        () => DayEntry(
          id: _uuid.v7(),
          entryDate: key,
        ),
      );

        if (part.isNotEmpty && lvlStr.isNotEmpty) {
          final lvl = int.tryParse(lvlStr);

          if (lvl != null && lvl >= 1 && lvl <= 4) {
            final category = painCategories.firstWhere(
              (c) => c.name == part,
              orElse: () {
                final created = PainCategory(
                  id: _uuid.v7(),
                  name: part,
                  position: painCategories.length,
                );
                painCategories.add(created);
                return created;
              },
            );

            final existingIndex = e.painLevels.indexWhere(
              (pain) => pain.painCategoryId == category.id,
            );

            final pain = DayPainLevel(
              id: existingIndex >= 0
                  ? e.painLevels[existingIndex].id
                  : _uuid.v7(),
              dayEntryId: e.id,
              painCategoryId: category.id,
              level: lvl,
            );

            if (existingIndex >= 0) {
              e.painLevels[existingIndex] = pain;
            } else {
              e.painLevels.add(pain);
            }
          }
        }

        if (act.isNotEmpty) {
          final activityType = activityTypes.firstWhere(
            (a) => a.name == act,
            orElse: () {
              final created = ActivityType(
                id: _uuid.v7(),
                name: act,
                position: activityTypes.length,
              );
              activityTypes.add(created);
              return created;
            },
          );

          if (!e.activities.any(
            (activity) => activity.activityTypeId == activityType.id,
          )) {
            e.activities.add(
              DayActivity(
                id: _uuid.v7(),
                dayEntryId: e.id,
                activityTypeId: activityType.id,
              ),
            );
          }
        }

        count++;
      }
    }

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
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5)
            : isToday
                ? Theme.of(context)
                    .colorScheme
                    .secondaryContainer
                    .withValues(alpha: 0.4)
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

          ...state.painCategories
              .where((cat) => cat.deletedAt == null)
              .map(
                (cat) {
                  final pain = entry.painLevels.cast<DayPainLevel?>().firstWhere(
                    (p) => p?.painCategoryId == cat.id,
                    orElse: () => null,
                  );

                  return _PainRow(
                    dayLocal: dayLocal,
                    category: cat.name,
                    level: pain?.level ?? 1,
                  );
                },
              ),

          const SizedBox(height: 20),
          Text('Activités', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          ...state.activityTypes
              .where((act) => act.deletedAt == null)
              .map((act) {
                final checked = entry.activities.any(
                  (activity) => activity.activityTypeId == act.id,
                );

                return CheckboxListTile(
                  title: Text(act.name),
                  value: checked,
                  onChanged: (v) =>
                      context.read<AppState>().toggleActivity(
                        dayLocal,
                        act.name,
                        v ?? false,
                      ),
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

                    // Sur Web, on ne filtre pas le sélecteur : certains
                    // navigateurs masquent les fichiers nouvellement créés.
                    // On vérifie l'extension après sélection.
                    if (kIsWeb &&
                        !file.name.toLowerCase().endsWith('.csv')) {
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
                          content:
                              Text('Import terminé : $count ligne(s) importées'),
                        ),
                      );
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
            onReorderItem: (oldIndex, newIndex) {
              final item = state.painCategories.removeAt(oldIndex);
              state.painCategories.insert(newIndex, item);
              context.read<AppState>()._save();
              setState(() {});
            },
            children: [
              for (final c in state.painCategories.where((c) => c.deletedAt == null))
                Card(
                  key: ValueKey('pain_${c.id}'),
                  child: ListTile(
                    leading: const Icon(Icons.drag_indicator),
                    title: Text(c.name),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Renommer',
                          onPressed: () async {
                            final ctrl = TextEditingController(text: c.name);
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
                              context.read<AppState>().renamePainCategory(c.name, newName);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Supprimer',
                          onPressed: () =>
                              context.read<AppState>().removePainCategory(c.name),
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
            onReorderItem: (oldIndex, newIndex) {
              final item = state.activityTypes.removeAt(oldIndex);
              state.activityTypes.insert(newIndex, item);
              context.read<AppState>()._save();
              setState(() {});
            },
            children: [
              for (final a in state.activityTypes.where((a) => a.deletedAt == null))
                Card(
                  key: ValueKey('act_${a.id}'),
                  child: ListTile(
                    leading: const Icon(Icons.drag_indicator),
                    title: Text(a.name),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Renommer',
                          onPressed: () async {
                            final ctrl = TextEditingController(text: a.name);
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
                              context.read<AppState>().renameActivityType(a.name, newName);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Supprimer',
                          onPressed: () =>
                              context.read<AppState>().removeActivityType(a.name),
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
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Enregistrer le fichier CSV'),
                onTap: () async {
                  Navigator.pop(ctx);

                  final state = context.read<AppState>();
                  final bytes = state.buildCsvBytesFr();
                  final name = state.buildCsvXFileFr().name;

                  try {
                    if (kIsWeb) {
                      await downloadBytes(bytes, name);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Fichier téléchargé ✅'),
                          ),
                        );
                      }
                      return;
                    }

                    // Android/iOS : on conserve le sélecteur de fichier
                    // existant de file_picker.
                    final path = await FilePicker.platform.saveFile(
                      dialogTitle: 'Enregistrer le CSV',
                      fileName: name,
                      bytes: bytes,
                      type: FileType.custom,
                      allowedExtensions: ['csv'],
                    );

                    if (path != null) {
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
