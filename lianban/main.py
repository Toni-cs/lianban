from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from lianban.cache import init_cache
from lianban.companion_routes import router as companion_router
from lianban.config import ROOT, settings
from lianban.db import init_db
from lianban.routes import router

WEB = ROOT / "web"


@asynccontextmanager
async def lifespan(_app: FastAPI):
    init_db()
    init_cache()
    yield


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(companion_router, prefix="/api")
app.include_router(router, prefix="/api")
app.mount("/static", StaticFiles(directory=str(WEB)), name="static")


def _page(name: str) -> FileResponse:
    page = WEB / name
    if not page.is_file():
        raise RuntimeError(f"缺少页面：{page}")
    return FileResponse(page)


@app.get("/")
def index() -> FileResponse:
    return _page("index.html")


@app.get("/control")
def control() -> FileResponse:
    return _page("control.html")


def main() -> None:
    import uvicorn

    uvicorn.run("lianban.main:app", host=settings.host, port=settings.port, reload=False)


if __name__ == "__main__":
    main()
