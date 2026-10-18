from datetime import datetime, timedelta, timezone
import math
import MetaTrader5 as mt5
from . import config

class MT5Error(RuntimeError):
    pass

TIMEFRAMES = {
    "M1": mt5.TIMEFRAME_M1, "M5": mt5.TIMEFRAME_M5, "M15": mt5.TIMEFRAME_M15,
    "M30": mt5.TIMEFRAME_M30, "H1": mt5.TIMEFRAME_H1, "H4": mt5.TIMEFRAME_H4,
    "D1": mt5.TIMEFRAME_D1, "W1": mt5.TIMEFRAME_W1, "MN1": mt5.TIMEFRAME_MN1,
}

def plain(v):
    if v is None or isinstance(v, (str, int, float, bool)):
        return v
    if hasattr(v, "_asdict"):
        return {k: plain(x) for k, x in v._asdict().items()}
    if isinstance(v, (tuple, list)):
        return [plain(x) for x in v]
    return str(v)

def error():
    code, message = mt5.last_error()
    return {"code": int(code), "message": str(message)}

def connect():
    if mt5.terminal_info() is not None and mt5.account_info() is not None:
        return True
    kwargs = {}
    if config.LOGIN: kwargs["login"] = int(config.LOGIN)
    if config.PASSWORD: kwargs["password"] = config.PASSWORD
    if config.SERVER: kwargs["server"] = config.SERVER
    if not mt5.initialize(config.MT5_PATH or None, timeout=60000, **kwargs):
        return False
    return mt5.account_info() is not None

def ensure():
    if not connect():
        e = error()
        raise MT5Error(f"No se pudo conectar con MetaTrader 5 ({e['code']}): {e['message']}")

def iso(t):
    try: return datetime.fromtimestamp(int(t), timezone.utc).isoformat()
    except Exception: return str(t)

def status():
    ok = connect()
    terminal, account, version = mt5.terminal_info(), mt5.account_info(), mt5.version()
    return {"connected": bool(ok and terminal is not None and account is not None),
            "terminal": plain(terminal), "account": plain(account),
            "version": list(version) if version else None,
            "last_error": None if ok else error(),
            "checked_at": datetime.now(timezone.utc).isoformat()}

def account():
    ensure()
    row = mt5.account_info()
    if row is None: raise MT5Error(str(error()))
    return plain(row)

def terminal():
    ensure()
    row = mt5.terminal_info()
    if row is None: raise MT5Error(str(error()))
    return plain(row)

def symbols(query="", limit=100):
    ensure()
    rows = mt5.symbols_get()
    if rows is None: raise MT5Error(str(error()))
    q, out = query.strip().upper(), []
    for x in rows:
        name, desc = str(x.name), str(getattr(x, "description", "") or "")
        if q and q not in name.upper() and q not in desc.upper(): continue
        out.append({"name": name, "description": desc, "path": str(getattr(x, "path", "") or ""),
                    "digits": int(x.digits), "point": float(x.point),
                    "volume_min": float(x.volume_min), "volume_max": float(x.volume_max),
                    "volume_step": float(x.volume_step), "visible": bool(x.visible)})
        if len(out) >= limit: break
    return out

def select_symbol(symbol):
    info = mt5.symbol_info(symbol)
    if info is None: raise MT5Error(f"El broker no ofrece el símbolo {symbol}.")
    if not info.visible and not mt5.symbol_select(symbol, True):
        raise MT5Error(f"No se pudo activar {symbol}: {error()}")
    return info

def tick(symbol):
    ensure()
    info = select_symbol(symbol)
    t = mt5.symbol_info_tick(symbol)
    if t is None: raise MT5Error(f"No hay cotización de {symbol}: {error()}")
    return {"symbol": symbol, "time": iso(t.time), "bid": float(t.bid), "ask": float(t.ask),
            "last": float(t.last), "volume": float(t.volume),
            "spread_points": round((float(t.ask)-float(t.bid))/max(float(info.point), 1e-12), 2),
            "digits": int(info.digits), "volume_min": float(info.volume_min),
            "volume_max": float(info.volume_max), "volume_step": float(info.volume_step)}

def bars(symbol, timeframe="M5", count=100):
    ensure()
    select_symbol(symbol)
    tf = TIMEFRAMES.get(timeframe.upper())
    if tf is None: raise MT5Error(f"Marco temporal no soportado: {timeframe}")
    rows = mt5.copy_rates_from_pos(symbol, tf, 0, max(10, min(int(count), 1000)))
    if rows is None: raise MT5Error(f"No se pudieron obtener velas: {error()}")
    return [{"time": iso(x["time"]), "open": float(x["open"]), "high": float(x["high"]),
             "low": float(x["low"]), "close": float(x["close"]),
             "tick_volume": int(x["tick_volume"])} for x in rows]

def positions():
    ensure()
    rows = mt5.positions_get()
    if rows is None:
        e = error()
        if e["code"] != 1: raise MT5Error(str(e))
        return []
    return [plain(x) for x in rows]

def orders():
    ensure()
    rows = mt5.orders_get()
    if rows is None:
        e = error()
        if e["code"] != 1: raise MT5Error(str(e))
        return []
    return [plain(x) for x in rows]

def history(days=7):
    ensure()
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=max(1, min(int(days), 90)))
    a, b = mt5.history_orders_get(start, end), mt5.history_deals_get(start, end)
    return {"orders": [] if a is None else [plain(x) for x in a],
            "deals": [] if b is None else [plain(x) for x in b]}

def require_demo():
    if config.ALLOW_LIVE: return
    a = mt5.account_info()
    if a is None or int(a.trade_mode) != int(mt5.ACCOUNT_TRADE_MODE_DEMO):
        raise MT5Error("Orden bloqueada: MT5 no identifica la cuenta como DEMO (ALLOW_LIVE_TRADING=false).")

def normalized_volume(symbol, value):
    info = select_symbol(symbol)
    value = float(value)
    if not math.isfinite(value) or value <= 0: raise MT5Error("Volumen no válido.")
    step = float(info.volume_step)
    if step <= 0: return value
    value = math.floor((value + 1e-12) / step) * step
    value = min(float(info.volume_max), max(float(info.volume_min), value))
    decimals = min(8, max(0, len(str(step).split(".")[-1].rstrip("0"))))
    return round(value, decimals)

def send_order(symbol, side, volume, sl=None, tp=None, deviation=None, comment="TradePilotMT5"):
    ensure()
    require_demo()
    side = side.upper()
    if side not in {"BUY", "SELL"}: raise MT5Error("side debe ser BUY o SELL.")
    info = select_symbol(symbol)
    t = mt5.symbol_info_tick(symbol)
    if t is None: raise MT5Error(f"No hay precio actual: {error()}")
    volume = normalized_volume(symbol, volume)
    digits = int(info.digits)
    price = float(t.ask if side == "BUY" else t.bid)
    def px(v):
        return round(float(v), digits) if v is not None and math.isfinite(float(v)) and float(v) > 0 else 0.0
    flags = int(getattr(info, "filling_mode", 0))
    filling = mt5.ORDER_FILLING_IOC if flags & 2 else mt5.ORDER_FILLING_FOK
    req = {"action": mt5.TRADE_ACTION_DEAL, "symbol": symbol, "volume": volume,
           "type": mt5.ORDER_TYPE_BUY if side == "BUY" else mt5.ORDER_TYPE_SELL,
           "price": round(price, digits), "sl": px(sl), "tp": px(tp),
           "deviation": config.DEVIATION if deviation is None else int(deviation),
           "magic": config.MAGIC, "comment": comment[:31],
           "type_time": mt5.ORDER_TIME_GTC, "type_filling": filling}
    checked = mt5.order_check(req)
    if checked is None: raise MT5Error(f"Validación fallida: {error()}")
    checked = plain(checked)
    if int(checked.get("retcode", -1)) not in {0, 10009}:
        return {"sent": False, "stage": "order_check", "check": checked, "result": None}
    result = mt5.order_send(req)
    if result is None: raise MT5Error(f"Envío de orden fallido: {error()}")
    result = plain(result)
    return {"sent": int(result.get("retcode", -1)) in {10008, 10009, 10010},
            "stage": "order_send", "check": checked, "result": result}

def close_position(ticket):
    ensure()
    require_demo()
    rows = mt5.positions_get(ticket=int(ticket))
    if not rows: raise MT5Error(f"No existe la posición {ticket}.")
    p = rows[0]
    info = select_symbol(p.symbol)
    t = mt5.symbol_info_tick(p.symbol)
    if t is None: raise MT5Error(f"No hay precio para el cierre: {error()}")
    buy = int(p.type) == int(mt5.POSITION_TYPE_BUY)
    req = {"action": mt5.TRADE_ACTION_DEAL, "symbol": p.symbol, "volume": float(p.volume),
           "type": mt5.ORDER_TYPE_SELL if buy else mt5.ORDER_TYPE_BUY,
           "position": int(ticket), "price": round(float(t.bid if buy else t.ask), int(info.digits)),
           "deviation": config.DEVIATION, "magic": config.MAGIC, "comment": "TradePilot close",
           "type_time": mt5.ORDER_TIME_GTC,
           "type_filling": mt5.ORDER_FILLING_IOC if int(getattr(info, "filling_mode", 0)) & 2 else mt5.ORDER_FILLING_FOK}
    result = mt5.order_send(req)
    if result is None: raise MT5Error(f"Cierre fallido: {error()}")
    data = plain(result)
    return {"sent": int(data.get("retcode", -1)) in {10008, 10009, 10010}, "result": data}
