from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    mt5_terminal_path: str | None = None
    host: str = "127.0.0.1"
    port: int = 8790

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


settings = Settings()
