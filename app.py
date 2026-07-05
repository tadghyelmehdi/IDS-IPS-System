import os
import socket
import datetime
import subprocess
import joblib
import sqlite3
import json
import requests
import numpy as np
from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS


class Config:
    PORT = 5000
    DB_PATH = "security_log.db"
    MODEL_PATH = "model.pkl"
    SCALER_PATH = "scaler.pkl"
    FEATURES_PATH = "feature_names.pkl"
    PROTECTED_IPS = {"127.0.0.1", "0.0.0.0", "::1", "192.168.10.1", "192.168.20.1"}
    TELEGRAM_TOKEN = "VOTRE_TOKEN"
    TELEGRAM_CHAT_ID = "VOTRE_CHAT_ID"


class DatabaseManager:
    def __init__(self, db_path):
        self.db_path = db_path
        self._init_db()

    def _init_db(self):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS alerts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT,
                    src_ip TEXT,
                    dst_ip TEXT,
                    prediction TEXT,
                    attack_type TEXT,
                    confidence REAL,
                    features TEXT,
                    status TEXT
                )
            """)
            conn.commit()

    def log_alert(self, alert_data):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO alerts (timestamp, src_ip, dst_ip, prediction, attack_type, confidence, features, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                alert_data['timestamp'], alert_data['src_ip'], alert_data['dst_ip'],
                alert_data['prediction'], alert_data['type'], alert_data['confidence'],
                json.dumps(alert_data['raw_features']), alert_data['status']
            ))
            conn.commit()

    def get_recent_alerts(self, limit=15):
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute("SELECT * FROM alerts ORDER BY id DESC LIMIT ?", (limit,))
            return [dict(row) for row in cursor.fetchall()]


class SecurityEngine:
    def __init__(self):
        self.db = DatabaseManager(Config.DB_PATH)
        self.blocked_ips = set()
        self.stats = {"total": 0, "attacks": 0, "normal": 0}
        self.attack_distribution = {"DoS Flood": 0, "Port Scan": 0, "Malicious Flow": 0}
        self.local_ip = self._init_network()
        self.model, self.scaler, self.f_names = self._load_ml()
        self._sync_stats()

    def _init_network(self):
        try:
            ip = socket.gethostbyname(socket.gethostname())
            Config.PROTECTED_IPS.add(ip)
            return ip
        except:
            return "127.0.0.1"

    def _load_ml(self):
        try:
            return joblib.load(Config.MODEL_PATH), joblib.load(Config.SCALER_PATH), joblib.load(Config.FEATURES_PATH)
        except:
            return None, None, None

    def _sync_stats(self):
        with sqlite3.connect(Config.DB_PATH) as conn:
            self.stats["total"] = conn.execute("SELECT COUNT(*) FROM alerts").fetchone()[0]
            self.stats["attacks"] = conn.execute("SELECT COUNT(*) FROM alerts WHERE prediction='Attaque'").fetchone()[0]
            self.stats["normal"] = conn.execute("SELECT COUNT(*) FROM alerts WHERE prediction='Normal'").fetchone()[0]

    def send_telegram(self, alert):
        url = f"https://api.telegram.org/bot{Config.TELEGRAM_TOKEN}/sendMessage"
        msg = f"ALERT\nHost: {alert['src_ip']}\nType: {alert['type']}\nConf: {alert['confidence']}%\nAction: {alert['status']}"
        try:
            requests.post(url, data={"chat_id": Config.TELEGRAM_CHAT_ID, "text": msg}, timeout=3)
        except:
            pass

    def run_firewall(self, action, ip):
        if os.name == 'nt':
            return True
        try:
            for chain in ["INPUT", "FORWARD", "OUTPUT"]:
                subprocess.run(["iptables", action, chain, "-s", ip, "-j", "DROP"], capture_output=True, timeout=2)
                subprocess.run(["iptables", action, chain, "-d", ip, "-j", "DROP"], capture_output=True, timeout=2)
            return True
        except:
            return False

    def predict(self, features, src_ip, dst_ip):
        if src_ip in self.blocked_ips:
            return {"alert": {"prediction": "Attaque", "status": "Deja Bloque"}, "muted": True}

        if not self.model or len(features) < 15:
            return None

        n = len(self.f_names)
        f_arr = np.array(features[:n]).reshape(1, -1)
        if f_arr.shape[1] < n:
            f_arr = np.pad(f_arr, ((0, 0), (0, n - f_arr.shape[1])), 'constant')

        X_norm = self.scaler.transform(f_arr)
        ml_prediction = int(self.model.predict(X_norm)[0]) == 1
        ml_conf = round(float(self.model.predict_proba(X_norm)[0][1 if ml_prediction else 0]) * 100, 1)

        pkts_per_sec = features[8]
        total_pkts = features[4] + features[5]

        is_attack = ml_prediction
        atk_type = "Normal"
        conf = ml_conf

        if pkts_per_sec > 800 or (total_pkts >= 2 and features[0] <= 0.05):
            is_attack = True
            conf = max(ml_conf, 95.0)
            atk_type = "DoS Flood" if pkts_per_sec > 500 else "Port Scan"

        if is_attack:
            if atk_type == "Normal":
                atk_type = "Malicious Flow"

            alert = {
                "timestamp": datetime.datetime.now().strftime("%H:%M:%S"),
                "src_ip": src_ip, "dst_ip": dst_ip,
                "prediction": "Attaque", "type": atk_type,
                "confidence": conf, "status": "Detecte", "raw_features": features
            }

            self.stats["attacks"] += 1
            if src_ip not in Config.PROTECTED_IPS:
                if self.run_firewall("-A", src_ip):
                    self.blocked_ips.add(src_ip)
                    alert["status"] = "Bloque"
                    self.send_telegram(alert)
        else:
            alert = {
                "timestamp": datetime.datetime.now().strftime("%H:%M:%S"),
                "src_ip": src_ip, "dst_ip": dst_ip,
                "prediction": "Normal", "type": "Normal",
                "confidence": conf, "status": "Autorise", "raw_features": features
            }
            self.stats["normal"] += 1

        self.stats["total"] += 1
        self.db.log_alert(alert)
        return alert


app = Flask(__name__)
CORS(app)
engine = SecurityEngine()


@app.route("/")
def index():
    return render_template_string(UI_HTML, ip=engine.local_ip)


@app.route("/predict", methods=["POST"])
def api_predict():
    data = request.json or {}
    alert = engine.predict(data.get("features", []), data.get("src_ip", "0.0.0.0"), data.get("dst_ip", "0.0.0.0"))
    if alert and alert.get("muted"):
        return jsonify({"status": "ignored"})
    return jsonify({"alert": alert, "blocked": list(engine.blocked_ips)})


@app.route("/api/data")
def api_data():
    return jsonify({
        "stats": engine.stats,
        "alerts": engine.db.get_recent_alerts(15),
        "blocked": list(engine.blocked_ips)
    })


@app.route("/api/unblock/<ip>", methods=["DELETE"])
def api_unblock(ip):
    if ip in engine.blocked_ips and engine.run_firewall("-D", ip):
        engine.blocked_ips.discard(ip)
        return jsonify({"success": True})
    return jsonify({"success": False})


UI_HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>IDS Security Hub</title>
    <style>
        :root { --bg: #0d1117; --card: #161b22; --border: #30363d; --text: #c9d1d9; --accent: #58a6ff; --danger: #f85149; --success: #3fb950; }
        body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); padding: 20px; margin: 0; }
        .box { max-width: 1000px; margin: 0 auto; }
        .stats { display: flex; gap: 15px; margin-bottom: 20px; }
        .card { flex: 1; background: var(--card); border: 1px solid var(--border); padding: 15px; border-radius: 6px; text-align: center; }
        .val { font-size: 22px; font-weight: bold; color: var(--accent); }
        .panel { background: var(--card); border: 1px solid var(--border); border-radius: 6px; margin-bottom: 20px; }
        .head { background: #21262d; padding: 10px; font-weight: bold; font-size: 13px; }
        .row { padding: 10px; border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; }
        .btn { background: var(--danger); color: white; border: none; padding: 4px 8px; border-radius: 4px; cursor: pointer; font-size: 11px; }
    </style>
</head>
<body>
    <div class="box">
        <h2>System Firewall Terminal</h2>
        <div class="stats">
            <div class="card">TOTAL<div class="val" id="t">0</div></div>
            <div class="card">ATTACK<div class="val" id="a" style="color:var(--danger)">0</div></div>
            <div class="card">NORMAL<div class="val" id="n" style="color:var(--success)">0</div></div>
        </div>
        <div class="panel"><div class="head">ACTIVE FIREWALL DROPS</div><div id="bl"></div></div>
        <div class="panel"><div class="head">LIVE TRAFFIC ANALYSIS INTERCEPTIONS</div><div id="lg"></div></div>
    </div>
    <script>
        async function load() {
            try {
                const res = await fetch('/api/data');
                const d = await res.json();
                document.getElementById('t').innerText = d.stats.total;
                document.getElementById('a').innerText = d.stats.attacks;
                document.getElementById('n').innerText = d.stats.normal;
                document.getElementById('bl').innerHTML = d.blocked.map(ip =>
                    '<div class="row"><span>blocked: <b>' + ip + '</b></span><button class="btn" onclick="un(\'' + ip + '\')">Remove</button></div>'
                ).join('') || '<div class="row">No active IP drops.</div>';
                document.getElementById('lg').innerHTML = d.alerts.map(a =>
                    '<div class="row"><span>[' + a.timestamp + '] <b>' + a.src_ip + '</b> -> ' + a.dst_ip + ' | ' + (a.attack_type || a.type) + '</span><b>' + a.status + '</b></div>'
                ).join('');
            } catch(e) {}
        }
        async function un(ip) { await fetch('/api/unblock/' + ip, {method:'DELETE'}); load(); }
        setInterval(load, 1500); load();
    </script>
</body>
</html>
"""


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=Config.PORT)
