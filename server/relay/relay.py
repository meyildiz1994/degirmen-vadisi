"""Değirmen Vadisi oda kodu aracısı (relay).

İki oyuncu farklı evlerdeyken port açmadan buluşsunlar diye: ev sahibi bağlanıp bir oda
açar ve 6 harfli kod alır; arkadaşı o kodla katılır. Sunucu oyun verisine bakmaz, yalnızca
iki taraf arasında ikili (binary) paketleri iletir.

Protokol (WebSocket):
  metin  -> {"op":"host","v":1}               <- {"op":"room","code":"KXRWTA"}
  metin  -> {"op":"join","code":"KXRWTA","v":1} <- {"op":"joined","id":2}  (ev sahibine: {"op":"peer","id":2})
  ikili  <-> karşı tarafa olduğu gibi iletilir
  ayrılma: ev sahibine {"op":"left","id":2}; katılana {"op":"closed"}
  hata:  {"op":"error","reason":"no_room"|"full"|"bad_request"|"version"}

Çalıştırma:  pip install websockets && python relay.py   (PORT ortam değişkeni, varsayılan 8765)
"""
import asyncio
import json
import os
import secrets
import time

import websockets

PROTOCOL = 1
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ"  # karışan harfler (I, O) yok
CODE_LEN = 6
MAX_MESSAGE = 2 * 1024 * 1024
MAX_ROOMS = 2000
ROOM_IDLE_SECONDS = 6 * 3600

rooms: dict[str, "Room"] = {}


class Room:
    def __init__(self, code, host):
        self.code = code
        self.host = host
        self.guest = None
        self.touched = time.monotonic()


def new_code():
    for _ in range(50):
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LEN))
        if code not in rooms:
            return code
    raise RuntimeError("no free code")


async def send_json(ws, obj):
    try:
        await ws.send(json.dumps(obj))
    except websockets.ConnectionClosed:
        pass


async def handler(ws):
    room = None
    role = None
    try:
        first = await asyncio.wait_for(ws.recv(), timeout=15)
        if not isinstance(first, str):
            await send_json(ws, {"op": "error", "reason": "bad_request"})
            return
        msg = json.loads(first)
        if int(msg.get("v", 0)) != PROTOCOL:
            await send_json(ws, {"op": "error", "reason": "version"})
            return
        if msg.get("op") == "host":
            if len(rooms) >= MAX_ROOMS:
                await send_json(ws, {"op": "error", "reason": "full"})
                return
            room = Room(new_code(), ws)
            rooms[room.code] = room
            role = "host"
            await send_json(ws, {"op": "room", "code": room.code})
        elif msg.get("op") == "join":
            code = str(msg.get("code", "")).strip().upper()
            room = rooms.get(code)
            if room is None:
                await send_json(ws, {"op": "error", "reason": "no_room"})
                return
            if room.guest is not None:
                await send_json(ws, {"op": "error", "reason": "full"})
                return
            room.guest = ws
            role = "guest"
            await send_json(ws, {"op": "joined", "id": 2})
            await send_json(room.host, {"op": "peer", "id": 2})
        else:
            await send_json(ws, {"op": "error", "reason": "bad_request"})
            return
        async for data in ws:
            room.touched = time.monotonic()
            if isinstance(data, str):
                continue  # oyun verisi ikili gelir; metin yalnızca el sıkışmada
            other = room.guest if role == "host" else room.host
            if other is not None:
                try:
                    await other.send(data)
                except websockets.ConnectionClosed:
                    pass
    except (asyncio.TimeoutError, json.JSONDecodeError, ValueError, websockets.ConnectionClosed):
        pass
    finally:
        if room is not None:
            if role == "host":
                rooms.pop(room.code, None)
                if room.guest is not None:
                    await send_json(room.guest, {"op": "closed"})
                    await room.guest.close()
            elif role == "guest" and room.guest is ws:
                room.guest = None
                await send_json(room.host, {"op": "left", "id": 2})


async def sweeper():
    while True:
        await asyncio.sleep(300)
        now = time.monotonic()
        for code, room in list(rooms.items()):
            if now - room.touched > ROOM_IDLE_SECONDS:
                rooms.pop(code, None)
                await room.host.close()


async def health(connection, request):
    # Barındırma servislerinin sağlık denetimi için düz HTTP yanıtı.
    if request.path == "/health":
        return connection.respond(200, "ok\n")
    return None


async def main():
    port = int(os.environ.get("PORT", "8765"))
    async with websockets.serve(handler, "0.0.0.0", port, max_size=MAX_MESSAGE,
                                ping_interval=20, ping_timeout=20, process_request=health):
        print(f"relay listening on :{port}", flush=True)
        asyncio.create_task(sweeper())
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
