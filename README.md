# TradePilotMT5

Aplicación independiente para Windows: Flutter -> FastAPI local -> MetaTrader 5.

## Incluye
- Estado de la conexión y resumen de cuenta.
- Símbolos del broker, Bid/Ask y velas OHLC recientes.
- Posiciones abiertas y órdenes pendientes.
- Envío de órdenes BUY/SELL y cierre de posiciones desde la app, con confirmación.
- El backend bloquea operativa en cuentas que no identifica como DEMO por defecto.

## Preparación del backend
Requisitos: MetaTrader 5 de escritorio abierto y con sesión DEMO iniciada; Python x64. En CMD:

```bat
cd /d D:\TradePilotMT5\backend
py -m venv .venv
.venv\Scripts\activate
python -m pip install --upgrade pip
pip install -r requirements.txt
copy .env.example .env
run_backend.bat
```

Prueba `http://127.0.0.1:8790/api/status` y `http://127.0.0.1:8790/docs`.

## Preparación de Flutter
Requisitos: Flutter en PATH y Visual Studio con “Desktop development with C++”.

En otra ventana CMD:
```bat
cd /d D:\TradePilotMT5\frontend
setup_frontend.bat
cd flutter_app
flutter pub get
flutter run -d windows
```

## Seguridad
La API escucha solo en 127.0.0.1. `ALLOW_LIVE_TRADING=false` bloquea órdenes si la cuenta no es DEMO. No configures trading real sin pruebas exhaustivas. Las órdenes pueden ser rechazadas por el broker según mercado, margen, volumen, SL/TP y reglas de ejecución.
