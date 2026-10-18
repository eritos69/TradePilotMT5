import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const TradePilotApp());

class TradePilotApp extends StatelessWidget {
  const TradePilotApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TradePilot MT5', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B1020), colorSchemeSeed: const Color(0xFF4F8CFF)),
    home: const HomePage());
}

class ApiError implements Exception {
  ApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Api {
  Api(this.base);
  final String base;
  Uri uri(String path, [Map<String, String>? query]) =>
    Uri.parse('${base.replaceFirst(RegExp(r"/+$"), "")}$path').replace(queryParameters: query);
  Future<dynamic> call(String method, String path, {Object? body, Map<String, String>? query}) async {
    late http.Response response;
    try {
      if (method == 'POST') {
        response = await http.post(uri(path, query), headers: {'content-type': 'application/json'},
          body: body == null ? null : jsonEncode(body)).timeout(const Duration(seconds: 10));
      } else {
        response = await http.get(uri(path, query)).timeout(const Duration(seconds: 10));
      }
    } on TimeoutException { throw ApiError('Tiempo de espera agotado.'); }
      catch (e) { throw ApiError('No se conecta con FastAPI: $e'); }
    dynamic data;
    try { data = jsonDecode(response.body); } catch (_) { data = {'detail': response.body}; }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiError(data is Map ? '${data['detail'] ?? response.body}' : response.body);
    }
    return data;
  }
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(await call('GET', '/api/status'));
  Future<Map<String, dynamic>> account() async => Map<String, dynamic>.from(await call('GET', '/api/account'));
  Future<List<dynamic>> symbols(String q) async => List<dynamic>.from(await call('GET', '/api/symbols', query: {'q': q, 'limit': '100'}));
  Future<Map<String, dynamic>> tick(String s) async => Map<String, dynamic>.from(await call('GET', '/api/symbols/${Uri.encodeComponent(s)}/tick'));
  Future<List<dynamic>> bars(String s, String tf) async => List<dynamic>.from(await call('GET', '/api/bars/${Uri.encodeComponent(s)}', query: {'timeframe': tf, 'count': '100'}));
  Future<List<dynamic>> positions() async => List<dynamic>.from(await call('GET', '/api/positions'));
  Future<List<dynamic>> orders() async => List<dynamic>.from(await call('GET', '/api/orders'));
  Future<Map<String, dynamic>> send(String s, String side, double v, double? sl, double? tp) async =>
    Map<String, dynamic>.from(await call('POST', '/api/trading/order', body: {'symbol': s, 'side': side, 'volume': v, 'sl': sl, 'tp': tp, 'comment': 'TradePilotMT5'}));
  Future<Map<String, dynamic>> close(int ticket) async =>
    Map<String, dynamic>.from(await call('POST', '/api/trading/close', body: {'ticket': ticket}));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  String base = 'http://127.0.0.1:8790', symbol = '', tf = 'M5';
  Api get api => Api(base);
  bool busy = false, polling = false;
  String? error;
  Map<String, dynamic>? statusData, accountData, tickData;
  List<dynamic> symbolData = [], positionData = [], orderData = [], candleData = [];
  Timer? timer;

  @override void initState() { super.initState(); refresh(); timer = Timer.periodic(const Duration(seconds: 4), (_) => poll()); }
  @override void dispose() { timer?.cancel(); super.dispose(); }

  String statusError(Map<String, dynamic> s) {
    final e = s['last_error'];
    return e is Map ? 'MT5 ${e['code']}: ${e['message']}' : 'MetaTrader 5 no está conectado.';
  }
  Future<void> poll() async {
    if (polling) return; polling = true;
    try {
      final s = await api.status();
      if (!mounted) return;
      setState(() => statusData = s);
      if (s['connected'] != true) return;
      final r = await Future.wait([api.account(), api.positions(), api.orders()]);
      if (!mounted) return;
      setState(() { accountData = r[0] as Map<String, dynamic>; positionData = r[1] as List; orderData = r[2] as List; });
      if (symbol.isNotEmpty) { final t = await api.tick(symbol); if (mounted) setState(() => tickData = t); }
    } catch (_) {} finally { polling = false; }
  }
  Future<void> refresh() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final s = await api.status();
      if (s['connected'] != true) { statusData = s; throw ApiError(statusError(s)); }
      final r = await Future.wait([api.account(), api.positions(), api.orders(), api.symbols('')]);
      final syms = r[3] as List<dynamic>;
      var selected = symbol;
      if (selected.isEmpty && syms.isNotEmpty) selected = (syms.first as Map)['name'].toString();
      Map<String, dynamic>? tick;
      List<dynamic> bars = [];
      if (selected.isNotEmpty) { tick = await api.tick(selected); bars = await api.bars(selected, tf); }
      if (!mounted) return;
      setState(() {
        statusData = s; accountData = r[0] as Map<String, dynamic>; positionData = r[1] as List;
        orderData = r[2] as List; symbolData = syms; symbol = selected; tickData = tick; candleData = bars;
      });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> pickSymbol() async {
    final searchController = TextEditingController();
    var found = symbolData;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, updateDialog) {
            return AlertDialog(
              title: const Text('Símbolo del broker'),
              content: SizedBox(
                width: 520,
                height: 430,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Buscar nombre o descripción',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (query) async {
                        try {
                          final results = await api.symbols(query);
                          updateDialog(() {
                            found = results;
                          });
                        } catch (_) {
                          // Conserva la lista actual si la búsqueda falla.
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: found.length,
                        itemBuilder: (context, index) {
                          final item = Map<String, dynamic>.from(found[index] as Map);
                          return ListTile(
                            title: Text('${item['name']}'),
                            subtitle: Text('${item['description'] ?? ''}'),
                            onTap: () => Navigator.of(dialogContext).pop(item['name'].toString()),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );

    searchController.dispose();
    if (selected == null) return;

    setState(() {
      busy = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        api.tick(selected),
        api.bars(selected, tf),
      ]);
      if (!mounted) return;
      setState(() {
        symbol = selected;
        tickData = results[0] as Map<String, dynamic>;
        candleData = results[1] as List<dynamic>;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  Future<void> setTf(String value) async {
    setState(() => tf = value);
    if (symbol.isEmpty) return;
    try { final b = await api.bars(symbol, value); if (mounted) setState(() => candleData = b); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
  }
  Future<void> configure() async {
    final c = TextEditingController(text: base);
    final v = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Conexión FastAPI'),
      content: TextField(controller: c, decoration: const InputDecoration(labelText: 'URL', hintText: 'http://127.0.0.1:8790')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Guardar'))]));
    c.dispose();
    if (v != null && v.isNotEmpty) { setState(() => base = v); await refresh(); }
  }
  Future<void> trade(String side) async {
    if (symbol.isEmpty || tickData == null) { toast('Elige un símbolo primero.'); return; }
    final vol = TextEditingController(text: '0.01'), sl = TextEditingController(), tp = TextEditingController();
    final values = await showDialog<List<double?>>(context: context, builder: (_) => AlertDialog(
      title: Text('${side == 'BUY' ? 'Comprar' : 'Vender'} $symbol'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('BID ${fmt(tickData?['bid'])} · ASK ${fmt(tickData?['ask'])}'),
        TextField(controller: vol, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Volumen en lotes')),
        TextField(controller: sl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stop Loss (precio, opcional)')),
        TextField(controller: tp, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Take Profit (precio, opcional)')),
      ]),),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, [
          double.tryParse(vol.text.replaceAll(',', '.')), double.tryParse(sl.text.replaceAll(',', '.')), double.tryParse(tp.text.replaceAll(',', '.'))
        ]), child: const Text('Continuar'))]));
    vol.dispose(); sl.dispose(); tp.dispose();
    if (values == null) return;
    if (values[0] == null || values[0]! <= 0) { toast('Volumen no válido.'); return; }
    final yes = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Confirmar orden DEMO'),
      content: Text('${side == 'BUY' ? 'COMPRAR' : 'VENDER'} $symbol\nVolumen: ${values[0]} lotes\nSL: ${values[1] ?? 'sin SL'}\nTP: ${values[2] ?? 'sin TP'}\n\nSe enviará a MetaTrader 5.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enviar a MT5'))]));
    if (yes != true) return;
    try {
      final r = await api.send(symbol, side, values[0]!, values[1], values[2]);
      toast(r['sent'] == true ? 'Solicitud aceptada: ${r['result']}' : 'MT5 rechazó: ${r['result'] ?? r['check']}');
      await refresh();
    } catch (e) { toast(e.toString()); }
  }
  Future<void> closePosition(Map<String, dynamic> p) async {
    final id = int.tryParse('${p['ticket']}'); if (id == null) return;
    final yes = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Cerrar posición'),
      content: Text('¿Cerrar ${p['symbol']} #$id por completo?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar cierre'))]));
    if (yes != true) return;
    try { final r = await api.close(id); toast(r['sent'] == true ? 'Cierre enviado: ${r['result']}' : 'MT5 rechazó: ${r['result']}'); await refresh(); }
    catch (e) { toast(e.toString()); }
  }
  void toast(String v) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v))); }

  @override Widget build(BuildContext context) {
    final connected = statusData?['connected'] == true;
    return Scaffold(body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        const Icon(Icons.candlestick_chart, size: 34), const SizedBox(width: 10),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TradePilot MT5', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text('Control local de MetaTrader 5', style: TextStyle(color: Colors.white60)),
        ])),
        Chip(avatar: Icon(Icons.circle, size: 10, color: connected ? Colors.greenAccent : Colors.redAccent),
          label: Text(connected ? 'CONECTADO' : 'SIN CONEXIÓN')),
        IconButton(onPressed: configure, icon: const Icon(Icons.settings)),
        FilledButton.icon(onPressed: busy ? null : refresh, icon: const Icon(Icons.refresh), label: const Text('Actualizar')),
      ])),
      Expanded(child: RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.all(16), children: [
        if (error != null) Card(color: Colors.red.withOpacity(.15), child: Padding(padding: const EdgeInsets.all(12), child: Text(error!))),
        accountPanel(), const SizedBox(height: 12), marketPanel(), const SizedBox(height: 12),
        tradePanel(), const SizedBox(height: 12), positionPanel(), const SizedBox(height: 12), orderPanel(),
      ]))),
    ])));
  }
  Widget accountPanel() {
    final a = accountData ?? {}, raw = statusData?['account'];
    final login = raw is Map ? '${raw['login'] ?? '--'}' : '--';
    final server = raw is Map ? '${raw['server'] ?? '--'}' : '--';
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Cuenta · $login · $server', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        metric('Balance', money(a['balance']), Icons.account_balance_wallet),
        metric('Equity', money(a['equity']), Icons.show_chart),
        metric('Margen libre', money(a['margin_free']), Icons.lock_open),
        metric('Beneficio flotante', money(a['profit']), Icons.trending_up),
      ]),
    ])));
  }
  Widget metric(String label, String value, IconData icon) => SizedBox(width: 210, child: Card(color: const Color(0xFF151E32),
    child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      Icon(icon), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)), Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))
      ]))
    ]))));
  Widget marketPanel() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [const Expanded(child: Text('Mercados y precios', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
      OutlinedButton.icon(onPressed: pickSymbol, icon: const Icon(Icons.search), label: const Text('Elegir símbolo'))]),
    if (symbol.isEmpty) const Text('No hay símbolos cargados.') else ...[
      Row(children: [Expanded(child: Text(symbol, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('BID ${fmt(tickData?['bid'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('ASK ${fmt(tickData?['ask'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('Spread ${fmt(tickData?['spread_points'])} pt', style: const TextStyle(color: Colors.white60)),
        ])]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'].map((v) =>
        ChoiceChip(label: Text(v), selected: tf == v, onSelected: (_) => setTf(v))).toList()),
      const SizedBox(height: 8), const Text('Velas recientes (UTC)', style: TextStyle(color: Colors.white60)),
      if (candleData.isEmpty) const Text('Sin velas disponibles.') else ...candleData.reversed.take(8).map((raw) {
        final c = Map<String, dynamic>.from(raw as Map); final up = (c['close'] as num) >= (c['open'] as num);
        return ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(up ? Icons.trending_up : Icons.trending_down, color: up ? Colors.greenAccent : Colors.redAccent),
          title: Text('C ${fmt(c['close'])} · O ${fmt(c['open'])}'), subtitle: Text('${c['time']} · H ${fmt(c['high'])} / L ${fmt(c['low'])}'));
      }),
    ],
  ])));
  Widget tradePanel() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Operativa DEMO', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
    const Text('Se pide confirmación antes de enviar órdenes. La cuenta real está bloqueada por defecto en el backend.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 12), Row(children: [
      Expanded(child: FilledButton.icon(onPressed: symbol.isEmpty || busy ? null : () => trade('BUY'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), icon: const Icon(Icons.arrow_upward), label: const Text('COMPRAR'))),
      const SizedBox(width: 10),
      Expanded(child: FilledButton.tonalIcon(onPressed: symbol.isEmpty || busy ? null : () => trade('SELL'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), icon: const Icon(Icons.arrow_downward), label: const Text('VENDER'))),
    ]),
  ])));
  Widget positionPanel() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Posiciones abiertas (${positionData.length})', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
    if (positionData.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No hay posiciones abiertas.'))
    else ...positionData.map((raw) {
      final p = Map<String, dynamic>.from(raw as Map); final pnl = (p['profit'] as num?)?.toDouble() ?? 0;
      return ListTile(contentPadding: EdgeInsets.zero, leading: Icon(p['type'].toString() == '0' ? Icons.arrow_upward : Icons.arrow_downward),
        title: Text('${p['symbol']} #${p['ticket']}'), subtitle: Text('Vol. ${p['volume']} · Entrada ${fmt(p['price_open'])} · SL ${fmt(p['sl'])} · TP ${fmt(p['tp'])}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(money(pnl), style: TextStyle(color: pnl >= 0 ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold)),
          IconButton(tooltip: 'Cerrar posición', onPressed: () => closePosition(p), icon: const Icon(Icons.close))]));
    }),
  ])));
  Widget orderPanel() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Órdenes pendientes (${orderData.length})', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
    if (orderData.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No hay órdenes pendientes.'))
    else ...orderData.map((raw) { final o = Map<String, dynamic>.from(raw as Map); return ListTile(contentPadding: EdgeInsets.zero,
      title: Text('${o['symbol']} #${o['ticket']}'), subtitle: Text('Tipo ${o['type']} · Vol. ${o['volume_current'] ?? o['volume_initial']} · Precio ${fmt(o['price_open'])}')); }),
  ])));
  static String fmt(dynamic v) => v is num ? v.toStringAsFixed(5) : '--';
  static String money(dynamic v) => v is num ? v.toStringAsFixed(2) : '--';
}
