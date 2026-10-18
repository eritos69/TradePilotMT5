from typing import Any
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from . import mt5_service as mt
from . import config

app = FastAPI(title="TradePilot MT5 API", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=False,
                   allow_methods=["*"], allow_headers=["*"])

class OrderInput(BaseModel):
    symbol: str = Field(min_length=1, max_length=64)
    side: str = Field(pattern=r"^(BUY|SELL)$")
    volume: float = Field(gt=0)
    sl: float | None = Field(default=None, ge=0)
    tp: float | None = Field(default=None, ge=0)
    deviation: int | None = Field(default=None, ge=0, le=1000)
    comment: str = Field(default="TradePilotMT5", max_length=31)

class CloseInput(BaseModel):
    ticket: int = Field(gt=0)

def call(fn):
    try: return fn()
    except mt.MT5Error as exc: raise HTTPException(503, str(exc)) from exc
    except Exception as exc: raise HTTPException(500, str(exc)) from exc

@app.get("/")
def root(): return {"name": "TradePilot MT5", "version": "1.0.0", "docs": "/docs"}
@app.get("/api/status")
def get_status() -> dict[str, Any]: return mt.status()
@app.post("/api/connect")
def connect(): return mt.status()
@app.get("/api/account")
def get_account(): return call(mt.account)
@app.get("/api/terminal")
def get_terminal(): return call(mt.terminal)
@app.get("/api/symbols")
def get_symbols(q: str = Query(default="", max_length=80), limit: int = Query(default=100, ge=1, le=300)):
    return call(lambda: mt.symbols(q, limit))
@app.get("/api/symbols/{symbol}/tick")
def get_tick(symbol: str): return call(lambda: mt.tick(symbol))
@app.get("/api/bars/{symbol}")
def get_bars(symbol: str, timeframe: str = Query(default="M5"), count: int = Query(default=100, ge=10, le=1000)):
    return call(lambda: mt.bars(symbol, timeframe, count))
@app.get("/api/positions")
def get_positions(): return call(mt.positions)
@app.get("/api/orders")
def get_orders(): return call(mt.orders)
@app.get("/api/history")
def get_history(days: int = Query(default=7, ge=1, le=90)): return call(lambda: mt.history(days))
@app.post("/api/trading/order")
def post_order(data: OrderInput):
    return call(lambda: mt.send_order(data.symbol, data.side, data.volume, data.sl, data.tp, data.deviation, data.comment))
@app.post("/api/trading/close")
def post_close(data: CloseInput): return call(lambda: mt.close_position(data.ticket))
@app.get("/api/config")
def get_config(): return {"host": "127.0.0.1", "port": 8790, "allow_live_trading": config.ALLOW_LIVE}
