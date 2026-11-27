"""CI helper: a fake online rider that joins Bikeinside's Realtime room and rides
4 m ahead of whoever it hears. Used to verify multiplayer end-to-end in screenshots.
Usage: python3 scripts/fake_rider.py <seconds>"""
import asyncio, json, sys, time
import websockets

URL = "wss://vqimjctsfgncertfzqtp.supabase.co/realtime/v1/websocket?apikey=sb_publishable_96sOYIhhPFIIBxeGLgJRdg_TqvNUwiy&vsn=1.0.0"
ROUTES = ["skogsslingan", "sjorundan", "fjallvagen", "skargardsvagen", "grusvagen"]
ROOM = "ci-test"

async def main(seconds):
    async with websockets.connect(URL) as ws:
        topics = [f"realtime:bikeinside:{r}:{ROOM}" for r in ROUTES]
        ref = 1
        for t in topics:
            await ws.send(json.dumps({"topic": t, "event": "phx_join", "ref": str(ref),
                                      "payload": {"config": {"broadcast": {"self": False}, "presence": {"key": "ci-bot"}, "private": False}}}))
            ref += 1
        latest = {}
        async def rx():
            async for m in ws:
                d = json.loads(m)
                if d.get("event") == "broadcast":
                    p = d["payload"].get("payload", {})
                    if p.get("id") and p.get("id") != "ci-bot":
                        latest[d["topic"]] = (p, time.time())
        task = asyncio.create_task(rx())
        end = time.time() + seconds
        beat = time.time()
        while time.time() < end:
            for topic, (p, at) in list(latest.items()):
                me = {"id": "ci-bot", "name": "Testcyklist", "jersey": 9, "heightCm": 178, "routeId": p["routeId"],
                      "distance": p["distance"] + p["speed"] * (time.time() - at) + 4, "speed": p["speed"],
                      "power": p["power"], "wattsPerKg": p["wattsPerKg"], "cadence": 92}
                await ws.send(json.dumps({"topic": topic, "event": "broadcast", "ref": str(ref),
                                          "payload": {"type": "broadcast", "event": "state", "payload": me}}))
                ref += 1
            if time.time() - beat > 20:
                await ws.send(json.dumps({"topic": "phoenix", "event": "heartbeat", "ref": str(ref), "payload": {}}))
                ref += 1
                beat = time.time()
            await asyncio.sleep(0.4)
        task.cancel()
        print("fake rider done; heard", len(latest), "topics")

asyncio.run(main(float(sys.argv[1]) if len(sys.argv) > 1 else 300))
