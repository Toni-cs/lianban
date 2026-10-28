from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

ROOT = Path(__file__).resolve().parents[1]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(ROOT / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "联伴"
    host: str = "0.0.0.0"
    port: int = 8814
    database_url: str = "sqlite:///" + (ROOT / "data" / "lianban.db").as_posix()
    redis_url: str = ""
    model_base_url: str = ""
    model_api_key: str = ""
    model_name: str = ""
    huawei_sa_file: str = ""
    huawei_project_id: str = ""
    huawei_push_category: str = "WORK"
    huawei_push_test: bool = True
    computer_dir: str = ""


settings = Settings()
