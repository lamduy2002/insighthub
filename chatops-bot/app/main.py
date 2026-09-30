"""ASGI entrypoint: `uvicorn app.main:app`. Tests import app.factory.create_app instead."""
from .factory import create_app

app = create_app(run_worker=True)
