import os
import numpy as np
import pandas as pd
import joblib
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.metrics import confusion_matrix, accuracy_score, precision_score, recall_score, f1_score
from imblearn.over_sampling import SMOTE

SEUIL = 0.05
DOSSIER = os.path.dirname(os.path.abspath(__file__))

fichiers = [
    'UNSW-NB15_1.csv', 'UNSW-NB15_2.csv',
    'UNSW-NB15_3.csv', 'UNSW-NB15_4.csv',
    'UNSW_NB15_training-set.csv'
]

parts = []
for f in fichiers:
    path = os.path.join(DOSSIER, f)
    if os.path.exists(path):
        df = pd.read_csv(path, low_memory=False)
        parts.append(df)

if len(parts) == 0:
    raise ValueError("Aucun fichier train trouve")

train = pd.concat(parts, ignore_index=True)
test = pd.read_csv(os.path.join(DOSSIER, 'UNSW_NB15_testing-set.csv'), low_memory=False)

train = train.rename(columns={'smeansz': 'smean', 'dmeansz': 'dmean'})
test = test.rename(columns={'smeansz': 'smean', 'dmeansz': 'dmean'})
cat_cols = train.select_dtypes(include=['object']).columns

for col in cat_cols:
    le = LabelEncoder()
    if col in test.columns:
        combined = pd.concat([train[col], test[col]]).astype(str)
        le.fit(combined)
        train[col] = le.transform(train[col].astype(str))
        test[col] = le.transform(test[col].astype(str))
    else:
        le.fit(train[col].astype(str))
        train[col] = le.transform(train[col].astype(str))

FEATURES = [
    'dur', 'proto', 'service', 'state', 'spkts', 'dpkts', 'sbytes', 'dbytes', 'rate',
    'sttl', 'dttl', 'sload', 'dload', 'sloss', 'dloss', 'sinpkt', 'dinpkt', 'sjit', 'djit',
    'swin', 'stcpb', 'dtcpb', 'dwin', 'tcprtt', 'synack', 'ackdat', 'smean', 'dmean',
    'trans_depth', 'response_body_len', 'ct_srv_src', 'ct_state_ttl', 'ct_dst_ltm',
    'ct_src_dport_ltm', 'ct_dst_sport_ltm', 'ct_dst_src_ltm', 'is_ftp_login',
    'ct_ftp_cmd', 'ct_flw_http_mthd', 'ct_src_ltm', 'ct_srv_dst', 'is_sm_ips_ports'
]

features = [f for f in FEATURES if f in train.columns and f in test.columns]

X_train = train[features].copy()
X_test = test[features].copy()

for col in features:
    X_train[col] = pd.to_numeric(X_train[col], errors='coerce')
    X_test[col] = pd.to_numeric(X_test[col], errors='coerce')

X_train = X_train.replace([np.inf, -np.inf], np.nan).fillna(0)
X_test = X_test.replace([np.inf, -np.inf], np.nan).fillna(0)
X_train = X_train.astype(float)
X_test = X_test.astype(float)

y_train = (train['label'] > 0).astype(int)
y_test = (test['label'] > 0).astype(int)

scaler = StandardScaler()
X_train = scaler.fit_transform(X_train)
X_test = scaler.transform(X_test)
X_train, y_train = SMOTE(random_state=42).fit_resample(X_train, y_train)

model = RandomForestClassifier(
    n_estimators=200, max_depth=20,
    class_weight={0: 1, 1: 50},
    random_state=42, n_jobs=-1
)
model.fit(X_train, y_train)

y_prob = model.predict_proba(X_test)[:, 1]
y_pred = (y_prob >= SEUIL).astype(int)

tn, fp, fn, tp = confusion_matrix(y_test, y_pred).ravel()

print("Accuracy :", accuracy_score(y_test, y_pred))
print("Precision:", precision_score(y_test, y_pred))
print("Recall   :", recall_score(y_test, y_pred))
print("F1 Score :", f1_score(y_test, y_pred))
print("FN:", fn, "| FP:", fp)

joblib.dump(model, os.path.join(DOSSIER, 'model.pkl'))
joblib.dump(scaler, os.path.join(DOSSIER, 'scaler.pkl'))
joblib.dump(features, os.path.join(DOSSIER, 'feature_names.pkl'))

print("Modele sauvegarde")
