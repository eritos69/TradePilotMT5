from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException

from .config import settings
from .mt5_service import mt5_service


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    mt5_service.shutdown()


app = FastAPI(
    title="TradePilotMT5 API",
    version="0.1.0",
    description="Puente local y de solo lectura entre una aplicación y MetaTrader 5.",
    lifespan=lifespan,
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "TradePilotMT5"}


@app.get("/mt5/status")
def mt5_status() -> dict:
    return mt5_service.connect()


@app.post("/mt5/connect")
def mt5_connect() -> dict:
    return mt5_service.connect()


@app.post("/mt5/disconnect")
def mt5_disconnect() -> dict[str, bool]:
    mt5_service.shutdown()
    return {"connected": False}


@app.get("/mt5/account")
def mt5_account() -> dict:
    result = mt5_service.connect()
    if not result.get("connected"):
        raise HTTPException(status_code=503, detail=result.get("error", "MT5 no disponible"))
    return result["account"]


@app.get("/mt5/positions")
def mt5_positions() -> dict:
    try:
        return {"items": mt5_service.positions()}
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.get("/mt5/orders")
def mt5_orders() -> dict:
    try:
        return {"items": mt5_service.orders()}
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.get("/mt5/symbols")
def mt5_symbols() -> dict:
    try:
        return {"items": mt5_service.symbols()}
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.get("/mt5/tick/{symbol}")
def mt5_tick(symbol: str) -> dict:
    try:
        return mt5_service.tick(symbol)
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
