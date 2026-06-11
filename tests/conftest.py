import asyncio
import os
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

os.environ.setdefault("PRIVACY_EMAIL", "privacy@example.com")

from app.main import app  # noqa: E402
from db_utils import dispose_db, reset_db  # noqa: E402


@pytest.fixture()
def client() -> TestClient:
    asyncio.run(reset_db())
    with TestClient(app) as test_client:
        yield test_client
    asyncio.run(dispose_db())
