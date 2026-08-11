import asyncio
from collections import defaultdict
from contextlib import suppress
from uuid import UUID

from fastapi import WebSocket, WebSocketDisconnect


class WebSocketHub:
    def __init__(
        self, *, send_timeout_seconds: float = 2.0, close_timeout_seconds: float = 0.5
    ) -> None:
        self._connections: dict[UUID, list[WebSocket]] = defaultdict(list)
        self._send_timeout_seconds = send_timeout_seconds
        self._close_timeout_seconds = close_timeout_seconds

    async def connect(self, list_id: UUID, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections[list_id].append(websocket)

    def disconnect(self, list_id: UUID, websocket: WebSocket) -> None:
        conns = self._connections.get(list_id, [])
        if websocket in conns:
            conns.remove(websocket)
        if not conns and list_id in self._connections:
            del self._connections[list_id]

    async def broadcast(self, list_id: UUID, event: dict) -> None:
        stale_connections: list[WebSocket] = []
        for conn in list(self._connections.get(list_id, [])):
            try:
                await asyncio.wait_for(conn.send_json(event), timeout=self._send_timeout_seconds)
            except TimeoutError, RuntimeError, WebSocketDisconnect:
                stale_connections.append(conn)

        for conn in stale_connections:
            self.disconnect(list_id, conn)
            with suppress(Exception):
                await asyncio.wait_for(conn.close(), timeout=self._close_timeout_seconds)


hub = WebSocketHub()
