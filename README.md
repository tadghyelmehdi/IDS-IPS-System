# IDS/IPS System

Intrusion Detection & Prevention System with ML-based traffic analysis, real-time firewall blocking, and web dashboard.

Ecole Superieure de Technologie de Khenifra
Realise par : Boukari Kamal | Zari Mohammed Amine | Tadghy El Mehdi
Encadrant : Prof. Samir Bara | Prof. Abderrazak Taime

---

## Architecture

```
[TRAFFIC] --> [CAPTEUR (Scapy)] --> [Flask API] --> [Telegram Bot]
                                         |
                 /-----------------------+-----------------------\
                 |                       |                       |
          [FAST PATH]              [DEEP PATH]             [PERSISTENCE]
          (Whitelist)         (Random Forest + Heuristic)    (SQLite DB)
               |                       |                       |
            ALLOW              BLOCK / ALLOW / LOG         AUDIT LOG
```

---

## Project Structure

- `app.py` : Flask backend, ML inference, firewall blocking, Telegram bot, web dashboard
- `capteur.py` : Scapy network sensor (42-feature flow analysis)
- `rf_model.py` : Random Forest model trainer (UNSW-NB15 + SMOTE)
- `requirements.txt` : Python dependencies
- `model.pkl` / `scaler.pkl` / `feature_names.pkl` : Trained model artifacts
- `datasets/` : UNSW-NB15 dataset CSV files
- `visualisations/` : Model evaluation charts

---

## Features

### 1. ML Detection + Heuristic Fallback
Random Forest with SMOTE trained on UNSW-NB15. Heuristic rules reinforce detection:
- DoS Flood : packets/sec > 800
- Port Scan : >= 2 packets with duration <= 0.05s

### 2. Web Dashboard
Real-time stats, blocked IPs list, live alert log (inline HTML/JS, refreshes every 1.5s).

### 3. Telegram Notifications
Instant alerts when an attack is blocked (IP, type, confidence, action).

### 4. Whitelist / Fast Path
IPs marked as false positives bypass ML detection entirely.

### 5. SQLite Audit Log
Every event persisted for post-incident analysis.

---

## Setup

```bash
pip install -r requirements.txt
```

Configure Telegram in `app.py`:
```python
TELEGRAM_TOKEN = "VOTRE_TOKEN"
TELEGRAM_CHAT_ID = "VOTRE_CHAT_ID"
```

Run:
```bash
sudo python3 app.py          # Terminal 1 : Backend + Dashboard
sudo python3 capteur.py      # Terminal 2 : Sensor
```

Dashboard : http://localhost:5000

---

## Model Training

```bash
python3 rf_model.py
```

Trains a Random Forest on UNSW-NB15 with SMOTE, outputs:
- `model.pkl`, `scaler.pkl`, `feature_names.pkl`

---

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /predict | Submit features for ML analysis |
| GET | /api/data | Get stats, alerts, blocked IPs |
| DELETE | /api/unblock/<ip> | Unblock an IP |
| GET | / | Web dashboard |

---

## Notes

- iptables firewall blocking works on Linux only (Windows runs in detection-only mode)
- Local infrastructure IPs are never blocked
- Flow cleanup every 60s, flow timeout 120s
- Detection threshold : 0.05
