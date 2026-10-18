import os
from dotenv import load_dotenv
load_dotenv()

MT5_PATH = os.getenv("MT5_PATH", "").strip()
LOGIN = os.getenv("MT5_LOGIN", "").strip()
PASSWORD = os.getenv("MT5_PASSWORD", "").strip()
SERVER = os.getenv("MT5_SERVER", "").strip()
ALLOW_LIVE = os.getenv("ALLOW_LIVE_TRADING", "false").lower() in {"true", "1", "yes", "on"}
DEVIATION = int(os.getenv("ORDER_DEVIATION", "20"))
MAGIC = int(os.getenv("MAGIC", "2601009"))
