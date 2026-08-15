// Suivis douleur — version Web/Android
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'download_helper.dart';

const bool kShowAds = bool.fromEnvironment('SHOW_ADS', defaultValue: false);
const String kBannerAdUnitIdAndroid = 'ca-app-pub-8341770383248834/5762205942';
const String kAppTitle = 'Suivis douleur';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr_FR';
  if (kShowAds && !kIsWeb) await MobileAds.instance.initialize();
  runApp(const MyApp());
}

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
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
        darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark), useMaterial3: true),
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

class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});
  @override State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int index = 0;
  bool _reminderShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBackupReminder());
  }

  Future<void> _checkBackupReminder() async {
    if (_reminderShown) return;
    _reminderShown = true;
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('lastExportAt');
    final last = raw == null ? null : DateTime.tryParse(raw);
    final should = last == null || DateTime.now().difference(last).inDays >= 7;
    if (!should || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pensez à sauvegarder'),
        content: const Text('Vous n’avez pas exporté vos données depuis plus d’une semaine.\n\nUtilisez l’export CSV dans Réglages pour garder une copie de sécurité.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Plus tard')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['Planning', 'Réglages'];
    const icons = [Icons.calendar_month, Icons.settings];
    const pages = [PlanningPage(), SettingsPage()];
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          for (var i = 0; i < 2; i++) NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
        ],
      ),
    );
  }
}

class DayEntry {
  final Map<String, int> painLevels;
  final Set<String> activities;
  DayEntry({Map<String, int>? painLevels, Set<String>? activities})
      : painLevels = Map.of(painLevels ?? {}),
        activities = Set.of(activities ?? {});
  int maxPain() => painLevels.values.isEmpty ? 0 : painLevels.values.reduce((a, b) => a > b ? a : b);
  Map<String, dynamic> toJson() => {'painLevels': painLevels, 'activities': activities.toList()};
  factory DayEntry.fromJson(Map<String, dynamic> j) => DayEntry(
    painLevels: (j['painLevels'] as Map?)?.map((k,v) => MapEntry('$k', (v as num).toInt())) ?? {},
    activities: ((j['activities'] as List?) ?? []).map((e) => '$e').toSet(),
  );
}

class AppState extends ChangeNotifier {
  List<String> painCategories = ['Genoux G','Genoux D','Sciatique G','Sciatique D','Dos H','Dos B','Cervicales'];
  List<String> activityTypes = ['Marche boulot','Marche sport','Balade','Elliptique','Gainage','Abdos','Pompes','Traction','Dips','Levé de poids','Sexe'];
  final Map<String, DayEntry> entries = {};
  DateTime? lastExportAt;

  static String key(DateTime d) => DateFormat('yyyy-MM-dd').format(DateTime.utc(d.year,d.month,d.day));
  DayEntry entryFor(DateTime d) => entries[key(d)] ?? DayEntry();

  void setPainLevel(DateTime d,String cat,int lvl) {
    entries.putIfAbsent(key(d),()=>DayEntry()).painLevels[cat]=lvl;
    _save(); notifyListeners();
  }
  void toggleActivity(DateTime d,String act,bool checked) {
    final e=entries.putIfAbsent(key(d),()=>DayEntry());
    checked ? e.activities.add(act) : e.activities.remove(act);
    _save(); notifyListeners();
  }
  void addPainCategory(String s){s=s.trim(); if(s.isEmpty||painCategories.contains(s))return; painCategories.add(s);_save();notifyListeners();}
  void addActivityType(String s){s=s.trim(); if(s.isEmpty||activityTypes.contains(s))return;activityTypes.add(s);_save();notifyListeners();}
  void renamePainCategory(String old,String n){
    n=n.trim(); if(n.isEmpty||old==n||painCategories.contains(n))return;
    final i=painCategories.indexOf(old); if(i<0)return; painCategories[i]=n;
    for(final e in entries.values){final v=e.painLevels.remove(old);if(v!=null)e.painLevels[n]=v;} _save();notifyListeners();
  }
  void renameActivityType(String old,String n){
    n=n.trim(); if(n.isEmpty||old==n||activityTypes.contains(n))return;
    final i=activityTypes.indexOf(old);if(i<0)return;activityTypes[i]=n;
    for(final e in entries.values){if(e.activities.remove(old))e.activities.add(n);} _save();notifyListeners();
  }
  void removePainCategory(String n){painCategories.remove(n);for(final e in entries.values)e.painLevels.remove(n);_save();notifyListeners();}
  void removeActivityType(String n){activityTypes.remove(n);for(final e in entries.values)e.activities.remove(n);_save();notifyListeners();}

  Future<void> load() async {
    final sp=await SharedPreferences.getInstance();
    painCategories=sp.getStringList('painCategories')??painCategories;
    activityTypes=sp.getStringList('activityTypes')??activityTypes;
    final raw=sp.getString('entries');
    if(raw!=null&&raw.isNotEmpty){
      final map=jsonDecode(raw) as Map<String,dynamic>;
      entries..clear()..addAll(map.map((k,v)=>MapEntry(k,DayEntry.fromJson(Map<String,dynamic>.from(v)))));
    }
    final ex=sp.getString('lastExportAt'); if(ex!=null)lastExportAt=DateTime.tryParse(ex);
    notifyListeners();
  }
  Future<void> _save() async {
    final sp=await SharedPreferences.getInstance();
    await sp.setStringList('painCategories',painCategories);
    await sp.setStringList('activityTypes',activityTypes);
    await sp.setString('entries',jsonEncode(entries));
    if(lastExportAt!=null)await sp.setString('lastExportAt',lastExportAt!.toIso8601String());
  }
  void markExportDone(){lastExportAt=DateTime.now();_save();}

  Uint8List buildCsvBytesFr(){
    final sb=StringBuffer();
    sb.writeln('#TYPE=PAIN_CATEGORIES_V1'); for(final c in painCategories)sb.writeln(_safe(c));
    sb.writeln('#TYPE=ACTIVITY_TYPES_V1'); for(final a in activityTypes)sb.writeln(_safe(a));
    sb.writeln('#TYPE=ENTRIES_V1'); sb.writeln('date;parties;douleur;activités');
    final keys=entries.keys.toList()..sort();
    for(final k in keys){
      final e=entries[k]!;
      for(final p in e.painLevels.entries)sb.writeln('${DateFormat('dd/MM/yyyy').format(DateTime.parse(k))};${_safe(p.key)};${p.value};');
      for(final a in e.activities)sb.writeln('${DateFormat('dd/MM/yyyy').format(DateTime.parse(k))};;;${_safe(a)}');
    }
    return Uint8List.fromList(utf8.encode(sb.toString()));
  }
  XFile buildCsvXFileFr()=>XFile.fromData(buildCsvBytesFr(),mimeType:'text/csv; charset=utf-8',name:'douleurs_activites_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv');
  String _safe(String s)=>s.replaceAll(';',',');

  Future<int> importCsvFr(Uint8List bytes) async {
    final lines=const LineSplitter().convert(utf8.decode(bytes));
    if(lines.isEmpty)return 0;
    const pain='#TYPE=PAIN_CATEGORIES_V1',act='#TYPE=ACTIVITY_TYPES_V1',ent='#TYPE=ENTRIES_V1';
    var section=0,skip=false,count=0;
    final pains=<String>[],acts=<String>[],newEntries=<String,DayEntry>{};
    for(final raw in lines){
      final l=raw.trim();if(l.isEmpty)continue;
      if(l==pain){section=1;continue;} if(l==act){section=2;continue;} if(l==ent){section=3;skip=true;continue;}
      if(section==1){pains.add(l);continue;} if(section==2){acts.add(l);continue;}
      if(section!=3)continue; if(skip){skip=false;continue;}
      final p=l.split(';');if(p.length<4)continue;
      try{
        final dt=DateFormat('dd/MM/yyyy').parse(p[0].trim());
        final k=DateFormat('yyyy-MM-dd').format(DateTime.utc(dt.year,dt.month,dt.day));
        final e=newEntries.putIfAbsent(k,()=>DayEntry());
        final part=p[1].trim(),lvl=int.tryParse(p[2].trim()),a=p[3].trim();
        if(part.isNotEmpty&&lvl!=null&&lvl>=1&&lvl<=4)e.painLevels[part]=lvl;
        if(a.isNotEmpty)e.activities.add(a);
        count++;
      }catch(_){}
    }
    if(pains.isNotEmpty)painCategories=pains;if(acts.isNotEmpty)activityTypes=acts;
    if(newEntries.isNotEmpty){entries..clear()..addAll(newEntries);}
    await _save();notifyListeners();return count;
  }
}

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key});
  @override State<PlanningPage> createState()=>_PlanningPageState();
}
class _PlanningPageState extends State<PlanningPage>{
  DateTime focused=DateTime.now();DateTime? selected;
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Planning')),
    body:Column(children:[
      const Padding(padding:EdgeInsets.fromLTRB(12,8,12,0),child:_Legend()),
      Expanded(child:TableCalendar(
        locale:'fr_FR',firstDay:DateTime.utc(2000,1,1),lastDay:DateTime.utc(2100,12,31),
        focusedDay:focused,selectedDayPredicate:(d)=>isSameDay(d,selected),
        onDaySelected:(s,f){setState((){selected=s;focused=f;});showModalBottomSheet(context:context,useSafeArea:true,isScrollControlled:true,showDragHandle:true,builder:(_)=>FractionallySizedBox(heightFactor:.9,child:_DayEditor(day:s)));},
        availableGestures:AvailableGestures.all,headerStyle:const HeaderStyle(formatButtonVisible:false,titleCentered:true),
        calendarStyle:const CalendarStyle(outsideDaysVisible:false),
        calendarBuilders:CalendarBuilders(
          defaultBuilder:(_,d,__)=>_DayCell(day:d),todayBuilder:(_,d,__)=>_DayCell(day:d,today:true),
          selectedBuilder:(_,d,__)=>_DayCell(day:d,selected:true),
        ),
      )),
      if(kShowAds&&!kIsWeb)const _BannerBottom(),
    ]),
  );
}

class _DayCell extends StatelessWidget{
  final DateTime day;final bool today,selected;
  const _DayCell({required this.day,this.today=false,this.selected=false});
  @override Widget build(BuildContext context){
    final p=context.watch<AppState>().entryFor(day).maxPain();
    final c=[Colors.transparent,Colors.green,Colors.yellow,Colors.orange,Colors.red][p.clamp(0,4).toInt()];
    return Container(margin:const EdgeInsets.all(4),alignment:Alignment.center,
      decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),border:Border.all(color:c,width:p>0?2:.5),
        color:selected?Theme.of(context).colorScheme.primaryContainer.withOpacity(.5):today?Theme.of(context).colorScheme.secondaryContainer.withOpacity(.4):null),
      child:Text('${day.day}',style:const TextStyle(fontWeight:FontWeight.w600)));
  }
}
class _Legend extends StatelessWidget{
  const _Legend();
  Widget dot(Color c,String s)=>Row(mainAxisSize:MainAxisSize.min,children:[Container(width:14,height:14,decoration:BoxDecoration(color:c,shape:BoxShape.circle)),const SizedBox(width:6),Text(s)]);
  @override Widget build(BuildContext context)=>Wrap(spacing:16,runSpacing:6,children:[dot(Colors.green,'Aucune douleur'),dot(Colors.yellow,'Douleur légère'),dot(Colors.orange,'Douleur moyenne'),dot(Colors.red,'Forte douleur')]);
}
class _DayEditor extends StatelessWidget{
  final DateTime day;const _DayEditor({required this.day});
  @override Widget build(BuildContext context){
    final s=context.watch<AppState>(),e=s.entryFor(day);
    return Scaffold(appBar:AppBar(title:Text(DateFormat.yMMMMEEEEd('fr_FR').format(day)),actions:[IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.check))]),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        Text('Douleurs',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),
        ...s.painCategories.map((c)=>_PainRow(day:day,category:c,level:e.painLevels[c]??1)),
        const SizedBox(height:20),Text('Activités',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),
        ...s.activityTypes.map((a)=>CheckboxListTile(title:Text(a),value:e.activities.contains(a),onChanged:(v)=>context.read<AppState>().toggleActivity(day,a,v??false))),
      ]));
  }
}
class _PainRow extends StatelessWidget{
  final DateTime day;final String category;final int level;const _PainRow({required this.day,required this.category,required this.level});
  @override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(category,style:const TextStyle(fontWeight:FontWeight.w600)),const SizedBox(height:8),
    Wrap(spacing:8,children:[
      for(final x in const [('Aucune',1),('Légère',2),('Moyenne',3),('Forte',4)])
        ChoiceChip(label:Text(x.$1),selected:level==x.$2,onSelected:(_)=>context.read<AppState>().setPainLevel(day,category,x.$2)),
    ]),
  ])));
}

class SettingsPage extends StatefulWidget{const SettingsPage({super.key});@override State<SettingsPage> createState()=>_SettingsPageState();}
class _SettingsPageState extends State<SettingsPage>{
  final pain=TextEditingController(),act=TextEditingController();
  @override void dispose(){pain.dispose();act.dispose();super.dispose();}

  Future<void> _import() async {
    final r=await FilePicker.platform.pickFiles(type:kIsWeb?FileType.any:FileType.custom,allowedExtensions:kIsWeb?null:['csv'],withData:true,allowMultiple:false);
    if(r==null||r.files.isEmpty)return;
    final f=r.files.single,b=f.bytes;
    if(b==null)return;
    if(kIsWeb&&!f.name.toLowerCase().endsWith('.csv')){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Veuillez sélectionner un fichier CSV.')));return;}
    final n=await context.read<AppState>().importCsvFr(b);
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Import terminé : $n ligne(s) importées')));
  }

  Future<void> _exportSheet() async {
    final state=context.read<AppState>(),bytes=state.buildCsvBytesFr(),name=state.buildCsvXFileFr().name;
    await showModalBottomSheet(context:context,showDragHandle:true,builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:const Icon(Icons.share),title:const Text('Partager'),onTap:()async{
        Navigator.pop(ctx);
        await Share.shareXFiles([state.buildCsvXFileFr()],text:'Export Douleurs & Activités');
        state.markExportDone();
      }),
      ListTile(leading:const Icon(Icons.save_alt),title:const Text('Enregistrer le fichier CSV'),onTap:()async{
        Navigator.pop(ctx);
        try{
          if(kIsWeb){
            await downloadBytes(bytes,name);
            state.markExportDone();
            if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Fichier téléchargé ✅')));
          }else{
            final path=await FilePicker.platform.saveFile(dialogTitle:'Enregistrer le CSV',fileName:name,bytes:bytes,type:FileType.custom,allowedExtensions:['csv']);
            if(path!=null)state.markExportDone();
            if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(path==null?'Enregistrement annulé':'Fichier enregistré ✅')));
          }
        }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Erreur export : $e')));}
      }),
    ])));
  }

  Future<void> _renamePain(String old)async{
    final c=TextEditingController(text:old);final n=await showDialog<String>(context:context,builder:(x)=>AlertDialog(title:const Text('Renommer'),content:TextField(controller:c,autofocus:true),actions:[TextButton(onPressed:()=>Navigator.pop(x),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(x,c.text.trim()),child:const Text('Valider'))]));
    if(n!=null&&n.isNotEmpty)context.read<AppState>().renamePainCategory(old,n);
  }
  Future<void> _renameAct(String old)async{
    final c=TextEditingController(text:old);final n=await showDialog<String>(context:context,builder:(x)=>AlertDialog(title:const Text('Renommer'),content:TextField(controller:c),actions:[TextButton(onPressed:()=>Navigator.pop(x),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(x,c.text.trim()),child:const Text('Valider'))]));
    if(n!=null&&n.isNotEmpty)context.read<AppState>().renameActivityType(old,n);
  }

  Widget addRow(TextEditingController c,String hint,VoidCallback add)=>Row(children:[Expanded(child:TextField(controller:c,decoration:InputDecoration(hintText:hint,border:const OutlineInputBorder()),onSubmitted:(_)=>add())),const SizedBox(width:8),FilledButton.icon(onPressed:add,icon:const Icon(Icons.add),label:const Text('Ajouter'))]);

  @override Widget build(BuildContext context){
    final s=context.watch<AppState>();
    return Scaffold(appBar:AppBar(title:const Text('Réglages')),body:ListView(padding:const EdgeInsets.all(16),children:[
      Text('Exporter / Importer les données',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),
      if(s.lastExportAt!=null)Padding(padding:const EdgeInsets.only(bottom:12),child:Text('Dernière sauvegarde : ${DateFormat('dd/MM/yyyy – HH:mm').format(s.lastExportAt!.toLocal())}',style:TextStyle(color:Theme.of(context).colorScheme.primary,fontStyle:FontStyle.italic))),
      Row(children:[Expanded(child:FilledButton.icon(onPressed:_exportSheet,icon:const Icon(Icons.ios_share),label:const Text('Exporter CSV'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:_import,icon:const Icon(Icons.file_download),label:const Text('Importer CSV')))]),
      const SizedBox(height:12),const Divider(),const SizedBox(height:16),
      Text('Liste des douleurs',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),
      addRow(pain,'Ajouter une douleur (ex: Épaule)',(){context.read<AppState>().addPainCategory(pain.text);pain.clear();}),const SizedBox(height:8),
      ...s.painCategories.map((c)=>Card(child:ListTile(leading:const Icon(Icons.drag_indicator),title:Text(c),trailing:Wrap(children:[IconButton(icon:const Icon(Icons.edit),onPressed:()=>_renamePain(c)),IconButton(icon:const Icon(Icons.delete_outline),onPressed:()=>context.read<AppState>().removePainCategory(c))])))),
      const SizedBox(height:24),Text('Liste des activités',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),
      addRow(act,'Ajouter une activité (ex: Étirements)',(){context.read<AppState>().addActivityType(act.text);act.clear();}),const SizedBox(height:8),
      ...s.activityTypes.map((a)=>Card(child:ListTile(leading:const Icon(Icons.drag_indicator),title:Text(a),trailing:Wrap(children:[IconButton(icon:const Icon(Icons.edit),onPressed:()=>_renameAct(a)),IconButton(icon:const Icon(Icons.delete_outline),onPressed:()=>context.read<AppState>().removeActivityType(a))])))),
    ]));
  }
}

class _BannerBottom extends StatefulWidget{const _BannerBottom();@override State<_BannerBottom> createState()=>_BannerBottomState();}
class _BannerBottomState extends State<_BannerBottom>{
  BannerAd? ad;
  @override void initState(){super.initState();final b=BannerAd(size:AdSize.banner,adUnitId:kBannerAdUnitIdAndroid,request:const AdRequest(),listener:BannerAdListener(onAdLoaded:(a){if(mounted)setState(()=>ad=a as BannerAd);},onAdFailedToLoad:(a,_){a.dispose();}));b.load();}
  @override Widget build(BuildContext context)=>ad==null?const SizedBox.shrink():SizedBox(width:ad!.size.width.toDouble(),height:ad!.size.height.toDouble(),child:AdWidget(ad:ad!));
  @override void dispose(){ad?.dispose();super.dispose();}
}
