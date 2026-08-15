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
        self._connection_users: dict[int, UUID] = {}
        self._send_timeout_seconds = send_timeout_seconds
        self._close_timeout_seconds = close_timeout_seconds

    async def connect(
        self, list_id: UUID, websocket: WebSocket, user_id: UUID | None = None
    ) -> None:
        await websocket.accept()
        self._connections[list_id].append(websocket)
        if user_id is not None:
            self._connection_users[id(websocket)] = user_id

    def disconnect(self, list_id: UUID, websocket: WebSocket) -> None:
        conns = self._connections.get(list_id, [])
        if websocket in conns:
            conns.remove(websocket)
        self._connection_users.pop(id(websocket), None)
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

    async def disconnect_user(self, user_id: UUID, list_ids: set[UUID]) -> None:
        matching = [
            (list_id, connection)
            for list_id in list_ids
            for connection in list(self._connections.get(list_id, []))
            if self._connection_users.get(id(connection)) == user_id
        ]
        for list_id, connection in matching:
            self.disconnect(list_id, connection)
            with suppress(Exception):
                await asyncio.wait_for(
                    connection.close(),
                    timeout=self._close_timeout_seconds,
                )


hub = WebSocketHub()
