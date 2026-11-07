import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const navy = Color(0xFF12345A);
const sky = Color(0xFF45B4EE);
const pale = Color(0xFFEAF6FF);
const bg = Color(0xFFF4F9FD);

void main() => runApp(const MeteoApp());

class MeteoApp extends StatelessWidget {
  const MeteoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'METEO ESPAÑA', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: sky, primary: navy),
      scaffoldBackgroundColor: bg, appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: navy, elevation: 0)),
    home: const WeatherHome(),
  );
}

class Place {
  final String name, admin;
  final double lat, lon;
  const Place(this.name, this.admin, this.lat, this.lon);
  String get label => admin.isEmpty ? name : '$name, $admin';
  Map<String,dynamic> toJson() => {'name':name,'admin':admin,'lat':lat,'lon':lon};
  factory Place.fromJson(Map<String,dynamic> j) => Place(j['name'], j['admin'] ?? '', (j['lat'] as num).toDouble(), (j['lon'] as num).toDouble());
}

class Forecast {
  final Place place;
  final Map<String,dynamic> current;
  final List<dynamic> hourly, daily;
  final String updated;
  Forecast(this.place,this.current,this.hourly,this.daily,this.updated);
  factory Forecast.fromJson(Place p, Map<String,dynamic> j) {
    final c = Map<String,dynamic>.from(j['current'] ?? {});
    final h = Map<String,dynamic>.from(j['hourly'] ?? {});
    final d = Map<String,dynamic>.from(j['daily'] ?? {});
    final times = List<String>.from(h['time'] ?? []);
    final hourly = List.generate(times.length, (i) => {
      'time': times[i], 'temp': _at(h,'temperature_2m',i), 'rain': _at(h,'precipitation_probability',i),
      'code': _at(h,'weather_code',i), 'wind': _at(h,'wind_speed_10m',i)
    });
    final dates = List<String>.from(d['time'] ?? []);
    final daily = List.generate(dates.length, (i) => {
      'date':dates[i], 'max':_at(d,'temperature_2m_max',i), 'min':_at(d,'temperature_2m_min',i),
      'rain':_at(d,'precipitation_probability_max',i), 'code':_at(d,'weather_code',i),
      'sunrise':_at(d,'sunrise',i), 'sunset':_at(d,'sunset',i)
    });
    return Forecast(p,c,hourly,daily,DateFormat('HH:mm').format(DateTime.now()));
  }
  static dynamic _at(Map<String,dynamic> m,String k,int i) {
    final a = m[k]; return a is List && i < a.length ? a[i] : null;
  }
  int get temp => (current['temperature_2m'] as num?)?.round() ?? 0;
  int get feels => (current['apparent_temperature'] as num?)?.round() ?? temp;
  int get humidity => (current['relative_humidity_2m'] as num?)?.round() ?? 0;
  int get wind => (current['wind_speed_10m'] as num?)?.round() ?? 0;
  int get gust => (current['wind_gusts_10m'] as num?)?.round() ?? 0;
  int get code => (current['weather_code'] as num?)?.toInt() ?? 0;
  int get rain => (current['precipitation'] as num?)?.round() ?? 0;
  int get high => daily.isEmpty ? temp : (daily.first['max'] as num?)?.round() ?? temp;
  int get low => daily.isEmpty ? temp : (daily.first['min'] as num?)?.round() ?? temp;
}

String condition(int c) {
  if (c == 0) return 'Despejado';
  if (c == 1) return 'Mayormente despejado';
  if (c == 2) return 'Parcialmente nuboso';
  if (c == 3) return 'Cubierto';
  if ([45,48].contains(c)) return 'Niebla';
  if ([51,53,55,56,57].contains(c)) return 'Llovizna';
  if ([61,63,65,66,67,80,81,82].contains(c)) return 'Lluvia';
  if ([71,73,75,77,85,86].contains(c)) return 'Nieve';
  if ([95,96,99].contains(c)) return 'Tormenta';
  return 'Condiciones variables';
}
IconData weatherIcon(int c) {
  if (c == 0 || c == 1) return Icons.wb_sunny_rounded;
  if (c == 2 || c == 3 || c == 45 || c == 48) return Icons.cloud_rounded;
  if ([51,53,55,56,57,61,63,65,66,67,80,81,82].contains(c)) return Icons.water_drop_rounded;
  if ([71,73,75,77,85,86].contains(c)) return Icons.ac_unit;
  if ([95,96,99].contains(c)) return Icons.thunderstorm_rounded;
  return Icons.cloud_queue_rounded;
}

class WeatherService {
  static Future<List<Place>> search(String q) async {
    final uri = Uri.https('geocoding-api.open-meteo.com','/v1/search', {
      'name':q, 'count':'15', 'language':'es', 'format':'json', 'countryCode':'ES'
    });
    final r = await http.get(uri).timeout(const Duration(seconds:12));
    if (r.statusCode != 200) throw Exception('No se pudo buscar la localidad');
    final data = jsonDecode(r.body);
    return ((data['results'] ?? []) as List).map((e) => Place(
      e['name'] ?? '', e['admin1'] ?? e['admin2'] ?? '',
      (e['latitude'] as num).toDouble(), (e['longitude'] as num).toDouble()
    )).toList();
  }
  static Future<Forecast> forecast(Place p) async {
    final uri = Uri.https('api.open-meteo.com','/v1/forecast', {
      'latitude':'${p.lat}', 'longitude':'${p.lon}',
      'current':'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m,wind_gusts_10m',
      'hourly':'temperature_2m,precipitation_probability,weather_code,wind_speed_10m',
      'daily':'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset',
      'forecast_days':'7', 'timezone':'auto', 'wind_speed_unit':'kmh'
    });
    final r = await http.get(uri).timeout(const Duration(seconds:15));
    if (r.statusCode != 200) throw Exception('No se pudo cargar la previsión');
    return Forecast.fromJson(p, jsonDecode(r.body));
  }
  static Future<String> radarTemplate() async {
    final r = await http.get(Uri.https('api.rainviewer.com','/public/weather-maps.json')).timeout(const Duration(seconds:12));
    if (r.statusCode != 200) throw Exception('Radar temporalmente no disponible');
    final j = jsonDecode(r.body);
    final frames = (j['radar']?['past'] as List?) ?? [];
    if (frames.isEmpty) throw Exception('No hay imágenes de radar disponibles');
    final frame = frames.last;
    return 'https://tilecache.rainviewer.com${frame['path']}/256/{z}/{x}/{y}/2/1_1.png';
  }
}

class WeatherHome extends StatefulWidget {
  const WeatherHome({super.key});
  @override State<WeatherHome> createState() => _WeatherHomeState();
}
class _WeatherHomeState extends State<WeatherHome> {
  int tab = 0;
  Place selected = const Place('Córdoba','Andalucía',37.8882,-4.7794);
  Forecast? data;
  bool busy = true;
  String? error;
  List<Place> favorites = [];
  final searchCtrl = TextEditingController();

  @override void initState() { super.initState(); _restore(); }
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('selected_place');
    final fav = prefs.getStringList('favorites') ?? [];
    if (saved != null) {
      try { selected = Place.fromJson(jsonDecode(saved)); } catch (_) {}
    }
    favorites = fav.map((s) { try { return Place.fromJson(jsonDecode(s)); } catch (_) { return null; } }).whereType<Place>().toList();
    if (mounted) setState(() {});
    await _load();
  }
  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('selected_place',jsonEncode(selected.toJson()));
    await p.setStringList('favorites',favorites.map((e)=>jsonEncode(e.toJson())).toList());
  }
  Future<void> _load() async {
    setState(() {busy=true;error=null;});
    try { final f=await WeatherService.forecast(selected); if(mounted)setState(()=>data=f); }
    catch(e) { if(mounted)setState(()=>error=e.toString()); }
    if(mounted)setState(()=>busy=false);
  }
  Future<void> _select(Place p) async {
    setState(()=>selected=p); await _persist(); if(mounted) Navigator.of(context).maybePop(); await _load();
  }
  Future<void> _locate() async {
    try {
      var perm=await Geolocator.checkPermission();
      if(perm==LocationPermission.denied) perm=await Geolocator.requestPermission();
      if(perm==LocationPermission.denied || perm==LocationPermission.deniedForever) { _snack('Permiso de ubicación no concedido. Puedes buscar una localidad.'); return; }
      if(!await Geolocator.isLocationServiceEnabled()) { _snack('Activa la ubicación del dispositivo o busca una localidad.'); return; }
      final pos=await Geolocator.getCurrentPosition();
      setState(()=>selected=Place('Mi ubicación','España',pos.latitude,pos.longitude));
      await _persist(); await _load();
    } catch (_) { _snack('No se pudo obtener la ubicación.'); }
  }
  void _snack(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));
  Future<void> _search() async {
    searchCtrl.clear();
    await showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.white,
      builder:(ctx) => StatefulBuilder(builder:(ctx,setSheet)=>Padding(
        padding:EdgeInsets.fromLTRB(18,18,18,MediaQuery.of(ctx).viewInsets.bottom+20),
        child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Buscar municipio',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:navy)),
          const SizedBox(height:12),
          TextField(controller:searchCtrl,autofocus:true,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Escribe una localidad de España',border:OutlineInputBorder()),
            onChanged:(q) async { if(q.trim().length<2)return; try {final results=await WeatherService.search(q); setSheet(()=>_searchResults=results);} catch(_){} }),
          const SizedBox(height:8),
          if(_searchResults.isNotEmpty) ..._searchResults.map((p)=>ListTile(leading:const Icon(Icons.location_on,color:sky),title:Text(p.name),subtitle:Text(p.admin),onTap:()=>_select(p))),
          if(_searchResults.isEmpty) const Text('Ejemplos: Córdoba, Sevilla, Madrid, Málaga, Valencia…',style:TextStyle(color:Colors.black54)),
          Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:(){Navigator.pop(ctx);_locate();},icon:const Icon(Icons.my_location),label:const Text('Usar mi ubicación')))
        ]))));
    _searchResults=[];
  }
  List<Place> _searchResults=[];
  Future<void> _toggleFav() async {
    final exists=favorites.any((p)=>p.lat==selected.lat && p.lon==selected.lon);
    setState(()=>exists?favorites.removeWhere((p)=>p.lat==selected.lat&&p.lon==selected.lon):favorites.add(selected));
    await _persist();
  }
  bool get isFav=>favorites.any((p)=>p.lat==selected.lat&&p.lon==selected.lon);
  @override Widget build(BuildContext context) {
    final f=data;
    return Scaffold(
      appBar:AppBar(title:Row(children:[Container(width:34,height:34,decoration:BoxDecoration(color:pale,borderRadius:BorderRadius.circular(10)),child:const Icon(Icons.wb_sunny,color:sky)),
        const SizedBox(width:9),const Text('METEO',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1)),const Text(' ESPAÑA',style:TextStyle(fontWeight:FontWeight.w400,letterSpacing:1))]),
        actions:[IconButton(onPressed:_search,icon:const Icon(Icons.search),tooltip:'Buscar municipio'),IconButton(onPressed:_load,icon:const Icon(Icons.refresh),tooltip:'Actualizar')]),
      body:busy?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Padding(padding:const EdgeInsets.all(25),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off,color:sky,size:50),const SizedBox(height:12),Text('No se pudo obtener la previsión',style:TextStyle(color:navy,fontWeight:FontWeight.bold,fontSize:18)),Text(error!,textAlign:TextAlign.center),const SizedBox(height:12),FilledButton(onPressed:_load,child:const Text('Reintentar'))]))):
      IndexedStack(index:tab,children:[_today(f!),_hourly(f),_weekly(f),_radar(),_more()]),
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[
        NavigationDestination(icon:Icon(Icons.wb_sunny_outlined),selectedIcon:Icon(Icons.wb_sunny),label:'Hoy'),
        NavigationDestination(icon:Icon(Icons.schedule),label:'Por horas'),
        NavigationDestination(icon:Icon(Icons.calendar_month),label:'7 días'),
        NavigationDestination(icon:Icon(Icons.radar),label:'Radar'),
        NavigationDestination(icon:Icon(Icons.menu),label:'Más')]),
    );
  }
  Widget _today(Forecast f)=>RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(18),children:[
    Row(children:[const Icon(Icons.location_on,color:sky),const SizedBox(width:5),Expanded(child:Text(f.place.label,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold,color:navy))),
      IconButton(onPressed:_toggleFav,icon:Icon(isFav?Icons.star:Icons.star_border,color:Colors.orange))]),
    Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF63C5F4),Color(0xFF1F70B8)],begin:Alignment.topLeft,end:Alignment.bottomRight),borderRadius:BorderRadius.circular(26)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(DateFormat('EEEE, d MMMM','es_ES').format(DateTime.now()),style:const TextStyle(color:Colors.white70)),
        const SizedBox(height:12),Icon(weatherIcon(f.code),color:Colors.white,size:55),
        Text('${f.temp}°',style:const TextStyle(color:Colors.white,fontSize:76,fontWeight:FontWeight.w300,height:1.05)),
        Text(condition(f.code),style:const TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w600)),
        const SizedBox(height:7),Text('Máx. ${f.high}°  ·  Mín. ${f.low}°',style:const TextStyle(color:Colors.white,fontSize:16)),
        const SizedBox(height:16),const Divider(color:Colors.white30),Text('Actualizado: ${f.updated} · Fuente: Open-Meteo',style:const TextStyle(color:Colors.white70,fontSize:11))
      ])),
    const SizedBox(height:20),const Text('Condiciones actuales',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:navy)),
    const SizedBox(height:10),GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisSpacing:10,mainAxisSpacing:10,childAspectRatio:1.8,
      children:[_metric(Icons.thermostat,'Sensación térmica','${f.feels}°'),_metric(Icons.water_drop,'Humedad','${f.humidity}%'),_metric(Icons.air,'Viento','${f.wind} km/h'),_metric(Icons.wind_power,'Rachas','${f.gust} km/h')]),
    const SizedBox(height:18),_section('Próximas horas',()=>setState(()=>tab=1)),
    SizedBox(height:135,child:ListView(scrollDirection:Axis.horizontal,children:f.hourly.take(12).map((h)=>_hourCard(h)).toList())),
    const SizedBox(height:18),_section('Próximos 7 días',()=>setState(()=>tab=2)),
    ...f.daily.take(3).map((d)=>_day(d)),
    const Padding(padding:EdgeInsets.only(top:12),child:Text('Predicción orientativa. Consulta los avisos oficiales ante situaciones meteorológicas adversas.',style:TextStyle(fontSize:11,color:Colors.black54)))
  ]));
  Widget _metric(IconData i,String l,String v)=>Container(padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(16)),child:Row(children:[Icon(i,color:sky,size:24),const SizedBox(width:9),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Text(l,style:const TextStyle(color:Colors.black54,fontSize:11)),Text(v,style:const TextStyle(color:navy,fontWeight:FontWeight.bold,fontSize:18))]))]));
  Widget _section(String s,VoidCallback cb)=>Row(children:[Expanded(child:Text(s,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:navy))),TextButton(onPressed:cb,child:const Text('Ver todo'))]);
  Widget _hourCard(Map<String,dynamic> h)=>Container(width:75,margin:const EdgeInsets.only(right:9),padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(15)),child:Column(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[
    Text(h['time'].toString().substring(11,16),style:const TextStyle(color:Colors.black54,fontSize:12)),Icon(weatherIcon((h['code'] as num?)?.toInt()??0),color:sky),
    Text('${(h['temp'] as num?)?.round()??'–'}°',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold,color:navy)),Text('${h['rain']??0}% lluvia',style:const TextStyle(fontSize:10,color:Colors.black54))]));
  Widget _day(Map<String,dynamic> d)=>Container(margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(14)),child:Row(children:[
    SizedBox(width:54,child:Text(DateFormat('EEE','es_ES').format(DateTime.parse(d['date'])),style:const TextStyle(fontWeight:FontWeight.w600,color:navy))),
    Icon(weatherIcon((d['code'] as num?)?.toInt()??0),color:sky),const SizedBox(width:10),Expanded(child:Text(condition((d['code'] as num?)?.toInt()??0),style:const TextStyle(color:Colors.black54,fontSize:12))),
    Text('${(d['max'] as num?)?.round()??'–'}°',style:const TextStyle(fontWeight:FontWeight.bold,color:navy)),const SizedBox(width:12),
    Text('${(d['min'] as num?)?.round()??'–'}°',style:const TextStyle(color:Colors.black54))]));
  Widget _hourly(Forecast f)=>ListView(padding:const EdgeInsets.all(18),children:[Text('Previsión por horas',style:_heading),Text(f.place.label,style:const TextStyle(color:Colors.black54)),const SizedBox(height:12),
    ...f.hourly.take(24).map((h)=>_hourRow(h))]);
  Widget _hourRow(Map<String,dynamic> h)=>Container(margin:const EdgeInsets.only(bottom:7),padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(13)),child:Row(children:[
    SizedBox(width:56,child:Text(h['time'].toString().substring(11,16),style:const TextStyle(color:navy,fontWeight:FontWeight.w600))),
    Icon(weatherIcon((h['code'] as num?)?.toInt()??0),color:sky),const SizedBox(width:12),Expanded(child:Text(condition((h['code'] as num?)?.toInt()??0),style:const TextStyle(color:Colors.black54))),
    Text('${(h['temp'] as num?)?.round()??'–'}°',style:const TextStyle(color:navy,fontWeight:FontWeight.bold)),const SizedBox(width:12),Text('${h['rain']??0}%',style:const TextStyle(color:sky))]));
  Widget _weekly(Forecast f)=>ListView(padding:const EdgeInsets.all(18),children:[Text('Previsión de 7 días',style:_heading),Text(f.place.label,style:const TextStyle(color:Colors.black54)),const SizedBox(height:14),...f.daily.map(_day),
    const Text('Fuente de predicción: Open-Meteo. Los pronósticos pueden cambiar con nuevas actualizaciones.',style:TextStyle(fontSize:11,color:Colors.black54))]);
  Widget _radar()=>const RadarScreen();
  Widget _more()=>ListView(padding:const EdgeInsets.all(18),children:[
    Text('Más opciones',style:_heading),const SizedBox(height:10),
    ListTile(leading:const Icon(Icons.notifications_active_outlined,color:sky),title:const Text('Avisos meteorológicos oficiales'),subtitle:const Text('Consultar avisos de AEMET'),onTap:()=>launchUrl(Uri.parse('https://www.aemet.es/es/eltiempo/prediccion/avisos')),trailing:const Icon(Icons.open_in_new)),
    ListTile(leading:const Icon(Icons.star_outline,color:sky),title:const Text('Mis localidades'),subtitle:Text(favorites.isEmpty?'Todavía no hay favoritos':favorites.map((e)=>e.name).join(' · ')),onTap:_showFavorites),
    ListTile(leading:const Icon(Icons.my_location,color:sky),title:const Text('Usar mi ubicación'),subtitle:const Text('Localización solo cuando la solicites'),onTap:_locate),
    const Divider(),const ListTile(leading:Icon(Icons.info_outline,color:sky),title:Text('Fuentes de datos'),subtitle:Text('Predicción: Open-Meteo · Radar: RainViewer · Avisos: AEMET')),
    const Padding(padding:EdgeInsets.all(14),child:Text('Open-Meteo: atribución CC BY 4.0. Radar RainViewer: uso personal/educativo sujeto a sus condiciones y disponibilidad. Esta app no sustituye las alertas oficiales de Protección Civil.',style:TextStyle(fontSize:11,color:Colors.black54)))
  ]);
  TextStyle get _heading=>const TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:navy);
  void _showFavorites()=>showModalBottomSheet(context:context,backgroundColor:Colors.white,builder:(ctx)=>SafeArea(child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(16),children:[
    const Text('Mis localidades',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold,color:navy)),
    ...favorites.map((p)=>ListTile(title:Text(p.name),subtitle:Text(p.admin),leading:const Icon(Icons.location_on,color:sky),onTap:()=>_select(p),
      trailing:IconButton(icon:const Icon(Icons.close),onPressed:()async{setState(()=>favorites.remove(p));await _persist();Navigator.pop(ctx);_showFavorites();}))),
    TextButton.icon(onPressed:(){Navigator.pop(ctx);_search();},icon:const Icon(Icons.add),label:const Text('Añadir localidad'))
  ])));
}

class RadarScreen extends StatefulWidget { const RadarScreen({super.key}); @override State<RadarScreen> createState()=>_RadarScreenState(); }
class _RadarScreenState extends State<RadarScreen> {
  String? template; String? error; bool loading=true;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async { try {final t=await WeatherService.radarTemplate();if(mounted)setState(()=>template=t);} catch(e){if(mounted)setState(()=>error=e.toString());} if(mounted)setState(()=>loading=false); }
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Radar de precipitaciones',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:navy)),
    const Text('Evolución reciente de la lluvia sobre el mapa',style:TextStyle(color:Colors.black54)),const SizedBox(height:12),
    SizedBox(height:480,child:ClipRRect(borderRadius:BorderRadius.circular(20),child:loading?const Center(child:CircularProgressIndicator()):template==null?
      Center(child:Text(error??'Radar no disponible',textAlign:TextAlign.center)):
      FlutterMap(options:const MapOptions(initialCenter:LatLng(40.0,-3.7),initialZoom:5.5,minZoom:3,maxZoom:7),
        children:[TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'es.meteo.espana.app'),
          TileLayer(urlTemplate:template!,userAgentPackageName:'es.meteo.espana.app',tileDisplay:const TileDisplay.fadeIn())]))),
    const SizedBox(height:10),const Text('Mapa base © OpenStreetMap. Radar: RainViewer. El servicio gratuito muestra imágenes históricas recientes, no una predicción futura, y está sujeto a sus condiciones de uso.',style:TextStyle(fontSize:11,color:Colors.black54)),
    TextButton.icon(onPressed:_load,icon:const Icon(Icons.refresh),label:const Text('Actualizar radar'))
  ]);
}
