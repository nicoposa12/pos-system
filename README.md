# POS System (TindaKo Monorepo)

A complete offline-first Point of Sale (POS) system composed of a **Flutter mobile/desktop app** and a **Laravel 11 REST API** backed by **Neon PostgreSQL**.

---

## 📁 Repository Structure

```
pos_system/
├── backend/          # Laravel 11 REST API + Sanctum + PostgreSQL (Neon)
└── mobile/           # Flutter POS Application (Android / Windows / iOS)
```

---

## 🚀 Quick Start

### 1. Start the Backend API
```bash
cd backend
php artisan serve --host=0.0.0.0 --port=8000
```
* **API Base URL:** `http://localhost:8000/api`
* **Android Emulator Base URL:** `http://10.0.2.2:8000/api`

### 2. Start the Flutter POS App
```bash
cd mobile
flutter run
```

---

## ☁️ Deployment

* **Backend:** Deploy `backend/` to [Render](https://render.com) using the included `Dockerfile` and connect to [Neon](https://neon.tech) PostgreSQL.
* **Mobile:** Build production APK with `flutter build apk --release`.

