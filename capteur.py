import time
import socket
import requests
from concurrent.futures import ThreadPoolExecutor
from scapy.all import sniff, IP, TCP, UDP


class Config:
    API_URL = "http://localhost:5000/predict"
    INTERFACES = ["eth0", "eth1"]
    SUPPRESSION_TIME = 1
    CLEANUP_INTERVAL = 60
    FLOW_TIMEOUT = 120


class TrafficSensor:
    def __init__(self):
        self.flux = {}
        self.cooldowns = {}
        self.counter = 0
        self.executor = ThreadPoolExecutor(max_workers=4)
        self.last_cleanup = time.time()
        self.my_ips = {"127.0.0.1", "192.168.10.1", "192.168.20.1", self._get_local_ip()}

    def _get_local_ip(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except:
            return "127.0.0.1"

    def _cleanup_old_flux(self, now):
        if now - self.last_cleanup > Config.CLEANUP_INTERVAL:
            self.flux = {k: v for k, v in self.flux.items() if now - v["start"] < Config.FLOW_TIMEOUT}
            self.last_cleanup = now

    def send_prediction_request(self, payload, src, dst):
        try:
            r = requests.post(Config.API_URL, json=payload, timeout=2)
            if r.status_code == 200:
                res = r.json().get("alert", {})
                if res and "muted" not in r.json():
                    self.counter += 1
                    icon = "ATT" if res.get("prediction") == "Attaque" else "OK"
                    print(f"[{self.counter:03d}] {icon} {src} -> {dst} | {res.get('type')}")
        except:
            pass

    def process_packet(self, pkt):
        try:
            if IP not in pkt:
                return
            src, dst = pkt[IP].src, pkt[IP].dst
            now = time.time()
            self._cleanup_old_flux(now)

            if src in self.my_ips or dst in self.my_ips or src.endswith(".255"):
                return

            if src in self.cooldowns:
                if now - self.cooldowns[src] < Config.SUPPRESSION_TIME:
                    return
                del self.cooldowns[src]

            proto = pkt[IP].proto
            sport = pkt[TCP].sport if TCP in pkt else (pkt[UDP].sport if UDP in pkt else 0)
            dport = pkt[TCP].dport if TCP in pkt else (pkt[UDP].dport if UDP in pkt else 0)

            if 5000 in [sport, dport]:
                return

            cle = tuple(sorted((src, dst))) + tuple(sorted((sport, dport))) + (proto,)

            if cle not in self.flux:
                self.flux[cle] = {
                    "initiator": src, "target": dst, "start": now,
                    "f_pkts": 0, "f_bytes": 0, "r_pkts": 0, "r_bytes": 0,
                    "analysed": False, "last_trigger": 0,
                    "s_ttl": pkt[IP].ttl, "d_ttl": 0
                }

            f = self.flux[cle]

            if f["analysed"] and (now - f["last_trigger"] > Config.SUPPRESSION_TIME):
                f["analysed"] = False
                f["f_pkts"] = f["f_bytes"] = f["r_pkts"] = f["r_bytes"] = 0
                f["start"] = now

            if f["analysed"]:
                return

            if src == f["initiator"]:
                f["f_pkts"] += 1
                f["f_bytes"] += len(pkt)
            else:
                f["r_pkts"] += 1
                f["r_bytes"] += len(pkt)
                if f["d_ttl"] == 0:
                    f["d_ttl"] = pkt[IP].ttl

            if (f["f_pkts"] + f["r_pkts"]) >= 2 or (now - f["start"] > 0.5):
                f["analysed"] = True
                f["last_trigger"] = now
                self.cooldowns[src] = now

                dur = max(0.001, now - f["start"])
                s_pkts, d_pkts = float(f["f_pkts"]), float(f["r_pkts"])
                s_bytes, d_bytes = float(f["f_bytes"]), float(f["r_bytes"])

                features = [
                    dur, float(proto), 0.0, 2.0, s_pkts, d_pkts, s_bytes, d_bytes, (s_pkts + d_pkts)/dur,
                    float(f["s_ttl"]), float(f["d_ttl"]), s_bytes*8/dur, d_bytes*8/dur,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.001, 0.0, 0.0,
                    s_bytes/s_pkts if s_pkts > 0 else 0, d_bytes/d_pkts if d_pkts > 0 else 0, 0.0, 0.0, s_pkts,
                    1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0
                ]

                payload = {"features": features, "src_ip": src, "dst_ip": dst}
                self.executor.submit(self.send_prediction_request, payload, src, dst)
        except:
            pass


if __name__ == "__main__":
    sensor = TrafficSensor()
    print("SENSOR RUNNING")
    try:
        sniff(iface=Config.INTERFACES, filter="ip", prn=sensor.process_packet, store=False, promisc=True)
    except:
        pass
