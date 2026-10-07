---
name: peta-proyek
description: Peta proyek koordinasi folder di /workspace. Gunakan setiap kali ada pertanyaan atau pekerjaan yang menyangkut hubungan antar folder myapp-ai (induk/deploy), myapp-ai-be (BackEnd/Go), dan myapp-ai-fe (FrontEnd/Vite) — misal "file backend taruh di mana", "cara start stack", "koordinasi folder". Menjelaskan folder mana untuk apa, alur kerja, dan perintah yang boleh/tidak boleh dijalankan dari kontainer opencode. Aturan wajib: jangan pernah mengubah myapp-ai/note.txt.
---

# Peta Proyek — Koordinasi Folder /workspace

## Aturan wajib

- **JANGAN mengubah/mengedit `myapp-ai/note.txt`.** File itu catatan operasional pribadi. Boleh dibaca sebagai referensi, tidak boleh diotak-atik.
- Ada juga `myapp-ai-be/note.txt` dan `myapp-ai-fe/note.txt` — perlakukan sama (catatan pribadi, baca saja, jangan diedit).
- **JANGAN menyebarkan isi `myapp-ai/.env`.** Berisi kredensial. Jangan pernah menampilkan atau menyalin isinya; paling banter `ls` untuk cek nama file.
- Tulis kode di tempat yang benar: backend → `myapp-ai-be`, frontend → `myapp-ai-fe`, ops/deploy → `myapp-ai`.

## Peta folder

| Folder        | Peran                         | Isi / git                                                                                |
| ------------- | ----------------------------- | ---------------------------------------------------------------------------------------- |
| `myapp-ai`    | Induk / deploy & operasional  | `docker-compose.yml`, `Dockerfile`, `entrypoint.sh`, `.env`, `.env-empty`, `note.txt` (dilarang diubah). Repo git utama. |
| `myapp-ai-be` | BackEnd (Go)                  | Aplikasi Go lengkap: `main.go`, `internal/` (api, store, models, db), `database/` (schema/seed + `db-run.sh`), `Dockerfile`, `go.mod`, `tmp/` (scratch, gitignored). |
| `myapp-ai-fe` | FrontEnd (Vite/Node)          | Aplikasi Vue 3: `src/`, `package.json`, `vite.config.js`, `nginx.conf`, `Dockerfile`, `dist/` hasil build. `node_modules` ikut bind-mount — jangan ditulis dari luar container. |

## Alur kerja (koordinasi)

- Stack dijalankan lewat `myapp-ai/docker-compose.yml`: `opencode` (port 5001), `myapp-db` (Postgres), `myapp-backend` (Go/Air, port 3000), `myapp-frontend` (Vite, port 5002).
- Kerja cukup dengan mengedit file di folder yang sesuai. Jangan menaruh file di folder yang salah.
- `docker` TIDAK ada di dalam kontainer `opencode` (binary tidak terpasang di image); jalankan `docker compose` dari HOST. `git` tersedia tapi butuh izin (permission opencode).
- DB (migrasi/seed/query): detail cara eksekusi ada di skill `database` — dari HOST pakai `db-run.sh`, dari kontainer opencode pakai `psql` langsung ke `myapp-db:5432`.

## Yang BISA dieksekusi dari sini

- Inspeksi workspace: `ls`, `du`, read/grep/glob, dll.
- `docker` TIDAK tersedia dari sini — perintah docker-compose dijalankan dari HOST (`/workspace/myapp-ai`), contoh:
  - start stack: `docker compose up -d`
  - stop stack: `docker compose down --remove-orphans`
  - cek log: `docker compose logs -f myapp-backend`
  - build Go: `docker compose exec myapp-backend go build -o /tmp/tokoapp-check .`
- `psql` tersedia: konek langsung ke DB dari sini (`myapp-db:5432`) — detail di skill `database`.
- `git` tersedia untuk commit/push, tapi butuh izin (permission) dari user — jangan commit tanpa diminta.
- `node` dan `npm` tersedia. Boleh menjalankan `npm` di `myapp-ai-fe` **hanya jika**:
  - kamu secara eksplisit meminta, **dan**
  - `package.json` ada di sana,
  - hindari menulis ke `node_modules`/`dist` dari sini (file bisa jadi milik root pada bind-mount host; `node_modules` yang dipakai dev-server berada di volume terpisah).

## Yang TIDAK bisa dieksekusi dari sini (tanpa konteks container lain)

Fakta lingkungan kontainer opencode (dicek ulang 2026-10-07): TERSEDIA `bash`, `psql`, `node`, `npm`, `sh`, `git`, **`go` 1.26.8**. TIDAK tersedia: `docker`, `curl`, `python3`. Jadi:

- `go build ./...` / `go vet ./...` / `go test ./...` **bisa langsung** dijalankan dari sini di `/workspace/myapp-ai-be`. Live-reload tetap milik container backend (`air`): perubahan kode menunggu reload — kalau perlu lihat hasil build-nya, minta `docker compose logs -f myapp-backend` dari HOST.
- Verifikasi endpoint tetap dari sini pakai `node` (fetch) ke `http://myapp-backend:3000` — detail di skill `myapp-backend`.
- `docker compose ...` (start/stop/log/build) jalankan dari HOST (`/workspace/myapp-ai`):
- Untuk `git`: tersedia tapi butuh izin (permission opencode). Bisa langsung `git add -A && git commit -m "..."` setelah user memberi izin; jangan commit tanpa diminta.

## Portability (VPS baru)

- Isi skill ini hidup di `myapp-ai/skills/peta-proyek/SKILL.md` dan ikut repo git `myapp-ai`.
- Pointer pemuatan ada di `/workspace/opencode.jsonc` (bagian `skills.paths`).
- Pindah ke VPS lain: clone repo `myapp-ai`, lalu salin `/workspace/opencode.jsonc` dari template `myapp-ai/opencode.example.jsonc`.