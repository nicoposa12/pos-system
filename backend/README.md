# TindaKo POS - Laravel REST API

Online REST API backend for the TindaKo POS Flutter application. Powered by Laravel 11, Laravel Sanctum, and Neon PostgreSQL.

---

## 🛠 Local Development Setup

1. **Install Dependencies:**
   ```bash
   composer install
   ```

2. **Configure `.env`:**
   Copy `.env.example` to `.env` and configure your database:
   ```env
   # Local SQLite (Development default)
   DB_CONNECTION=sqlite

   # Or Neon PostgreSQL (Cloud)
   DB_CONNECTION=pgsql
   DB_HOST=ep-your-subdomain.us-east-2.aws.neon.tech
   DB_PORT=5432
   DB_DATABASE=neondb
   DB_USERNAME=neondb_owner
   DB_PASSWORD=your_neon_password
   DB_SSLMODE=require
   ```

3. **Run Migrations & Storage Link:**
   ```bash
   php artisan migrate
   php artisan storage:link
   ```

4. **Start the API Server:**
   ```bash
   php artisan serve --host=0.0.0.0 --port=8000
   ```
   * The API is accessible at: `http://localhost:8000/api`
   * Android Emulator uses: `http://10.0.2.2:8000/api`
   * Physical phone on same Wi-Fi uses: `http://YOUR_PC_LOCAL_IP:8000/api`

---

## 🚀 Deploying to Neon & Render

### Step 1: Create Database on Neon (`neon.tech`)
1. Sign up on [Neon](https://neon.tech) (Free tier).
2. Create a project named `tindako-db`.
3. Copy the **Connection String** (e.g., `postgresql://user:pass@ep-xyz.neon.tech/neondb?sslmode=require`).

### Step 2: Push Backend to GitHub
```bash
git init
git add .
git commit -m "feat: initial Tindako Laravel API"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/tindako-backend.git
git push -u origin main
```

### Step 3: Deploy on Render (`render.com`)
1. Create a new **Web Service** on Render and connect your GitHub repo.
2. Select **Docker** (Render will automatically detect `Dockerfile`).
3. Under **Environment Variables**, add:
   - `APP_ENV`: `production`
   - `APP_KEY`: *(Generate with `php artisan key:generate --show`)*
   - `APP_DEBUG`: `false`
   - `APP_URL`: `https://your-app-name.onrender.com`
   - `DB_CONNECTION`: `pgsql`
   - `DB_HOST`: `ep-xyz.us-east-2.aws.neon.tech`
   - `DB_PORT`: `5432`
   - `DB_DATABASE`: `neondb`
   - `DB_USERNAME`: `neondb_owner`
   - `DB_PASSWORD`: `your_password`
   - `DB_SSLMODE`: `require`
   - `RUN_MIGRATIONS`: `true`
4. Click **Deploy**. Your API will be live at `https://your-app-name.onrender.com/api`!
