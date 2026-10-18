from __future__ import annotations

from threading import RLock
from typing import Any

import MetaTrader5 as mt5

from .config import settings


class MT5Service:
    """Acceso controlado al terminal MetaTrader 5.

    Esta primera fase expone únicamente operaciones de lectura.
    """

    def __init__(self) -> None:
        self._lock = RLock()
        self._connected = False

    def _last_error(self) -> dict[str, Any]:
        code, message = mt5.last_error()
        return {"code": code, "message": message}

    def connect(self) -> dict[str, Any]:
        with self._lock:
            if self._connected:
                terminal = mt5.terminal_info()
                account = mt5.account_info()
                if terminal is not None and account is not None:
                    return self.status()
                self._connected = False

            kwargs: dict[str, Any] = {}
            if settings.mt5_terminal_path:
                kwargs["path"] = settings.mt5_terminal_path

            ok = mt5.initialize(**kwargs)
            if not ok:
                self._connected = False
                return {
                    "connected": False,
                    "error": self._last_error(),
                }

            self._connected = True
            return self.status()

    def shutdown(self) -> None:
        with self._lock:
            if self._connected:
                mt5.shutdown()
            self._connected = False

    def status(self) -> dict[str, Any]:
        with self._lock:
            terminal = mt5.terminal_info()
            account = mt5.account_info()
            version = mt5.version()

            if terminal is None or account is None:
                return {
                    "connected": False,
                    "error": self._last_error(),
                }

            return {
                "connected": True,
                "terminal": {
                    "name": getattr(terminal, "name", None),
                    "path": getattr(terminal, "path", None),
                    "build": getattr(terminal, "build", None),
                    "connected": getattr(terminal, "connected", None),
                    "trade_allowed": getattr(terminal, "trade_allowed", None),
                },
                "account": {
                    "login": getattr(account, "login", None),
                    "server": getattr(account, "server", None),
                    "company": getattr(account, "company", None),
                    "currency": getattr(account, "currency", None),
                    "balance": getattr(account, "balance", None),
                    "credit": getattr(account, "credit", None),
                    "profit": getattr(account, "profit", None),
                    "equity": getattr(account, "equity", None),
                    "margin": getattr(account, "margin", None),
                    "margin_free": getattr(account, "margin_free", None),
                    "margin_level": getattr(account, "margin_level", None),
                    "trade_allowed": getattr(account, "trade_allowed", None),
                },
                "terminal_version": list(version) if version else None,
            }

    def positions(self) -> list[dict[str, Any]]:
        with self._lock:
            self._ensure_connected()
            rows = mt5.positions_get()
            if rows is None:
                self._raise_mt5_error("No se pudieron obtener las posiciones")
            return [self._namedtuple_to_dict(row) for row in rows]

    def orders(self) -> list[dict[str, Any]]:
        with self._lock:
            self._ensure_connected()
            rows = mt5.orders_get()
            if rows is None:
                self._raise_mt5_error("No se pudieron obtener las órdenes activas")
            return [self._namedtuple_to_dict(row) for row in rows]

    def symbols(self) -> list[dict[str, Any]]:
        with self._lock:
            self._ensure_connected()
            rows = mt5.symbols_get()
            if rows is None:
                self._raise_mt5_error("No se pudieron obtener los símbolos")
            return [
                {
                    "name": getattr(row, "name", None),
                    "description": getattr(row, "description", None),
                    "currency_base": getattr(row, "currency_base", None),
                    "currency_profit": getattr(row, "currency_profit", None),
                    "currency_margin": getattr(row, "currency_margin", None),
                    "visible": getattr(row, "visible", None),
                    "trade_mode": getattr(row, "trade_mode", None),
                }
                for row in rows
            ]

    def tick(self, symbol: str) -> dict[str, Any]:
        with self._lock:
            self._ensure_connected()
            clean_symbol = symbol.strip()
            if not clean_symbol:
                raise ValueError("El símbolo no puede estar vacío")

            info = mt5.symbol_info_tick(clean_symbol)
            if info is None:
                self._raise_mt5_error(f"No se encontró el símbolo: {clean_symbol}")

            return self._namedtuple_to_dict(info)

    def _ensure_connected(self) -> None:
        if not self._connected:
            result = self.connect()
            if not result.get("connected"):
                raise RuntimeError(
                    f"MetaTrader 5 no está conectado: {result.get('error')}"
                )

    @staticmethod
    def _namedtuple_to_dict(value: Any) -> dict[str, Any]:
        if hasattr(value, "_asdict"):
            return {key: MT5Service._make_json_safe(item) for key, item in value._asdict().items()}
        return {"value": MT5Service._make_json_safe(value)}

    @staticmethod
    def _make_json_safe(value: Any) -> Any:
        if isinstance(value, (str, int, float, bool)) or value is None:
            return value
        if hasattr(value, "item"):
            try:
                return value.item()
            except Exception:
                pass
        return str(value)

    def _raise_mt5_error(self, prefix: str) -> None:
        error = self._last_error()
        raise RuntimeError(f"{prefix}: {error['code']} - {error['message']}")


mt5_service = MT5Service()
