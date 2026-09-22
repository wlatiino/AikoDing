---
name: peta-proyek
description: Peta proyek koordinasi folder di /workspace. Gunakan setiap kali ada pertanyaan atau pekerjaan yang menyangkut hubungan antar folder myapp-ai (induk/deploy), myapp-ai-be (BackEnd/Go), dan myapp-ai-fe (FrontEnd/Vite) — misal "file backend taruh di mana", "cara start stack", "koordinasi folder". Menjelaskan folder mana untuk apa, alur kerja, dan perintah yang boleh/tidak boleh dijalankan dari kontainer opencode. Aturan wajib: jangan pernah mengubah myapp-ai/note.txt.
---

# Peta Proyek — Koordinasi Folder /workspace

## Aturan wajib

- **JANGAN mengubah/mengedit `myapp-ai/note.txt`.** File itu catatan operasional pribadi. Boleh dibaca sebagai referensi, tidak boleh diotak-atik.
- **JANGAN menyebarkan isi `myapp-ai/.env`.** Berisi kredensial. Jangan pernah menampilkan atau menyalin isinya; paling banter `ls` untuk cek nama file.
- Tulis kode di tempat yang benar: backend → `myapp-ai-be`, frontend → `myapp-ai-fe`, ops/deploy → `myapp-ai`.

## Peta folder

| Folder        | Peran                         | Isi / git                                                                                |
| ------------- | ----------------------------- | ---------------------------------------------------------------------------------------- |
| `myapp-ai`    | Induk / deploy & operasional  | `docker-compose.yml`, `Dockerfile`, `entrypoint.sh`, `.env`, `.env-empty`, `note.txt` (dilarang diubah). Repo git utama. |
| `myapp-ai-be` | BackEnd (Go)                  | Masih kosong; bakal punya repo git sendiri.                                              |
| `myapp-ai-fe` | FrontEnd (Vite/Node)          | Baru `node_modules`; bakal punya repo git sendiri.                                        |

## Alur kerja (koordinasi)

- Stack dijalankan lewat `myapp-ai/docker-compose.yml`: `opencode` (port 5001), `myapp-db` (Postgres), `myapp-backend` (Go/Air, port 3000), `myapp-frontend` (Vite, port 5002).
- Kerja cukup dengan mengedit file di folder yang sesuai. Jangan menaruh file di folder yang salah.
- Aksi docker/git tidak bisa dijalankan dari dalam kontainer opencode — lihat bagian bawah.

## Yang BISA dieksekusi dari sini

- Inspeksi workspace: `ls`, `du`, read/grep/glob, dll.
- `node` dan `npm` tersedia. Boleh menjalankan `npm` di `myapp-ai-fe` **hanya jika**:
  - kamu secara eksplisit meminta, **dan**
  - `package.json` ada di sana,
  - hindari menulis ke `node_modules`/`dist` dari sini (file bisa jadi milik root pada bind-mount host; `node_modules` yang dipakai dev-server berada di volume terpisah).

## Yang TIDAK bisa dieksekusi dari sini

Fakta lingkungan kontainer opencode: `docker`, `docker.sock`, `git`, `go`, `curl`, `bash`, `python3` — TIDAK tersedia. Jadi:

- **Jangan mencoba** `docker compose up/down`, `git add/commit`, atau sejenisnya dari sini — pasti gagal.
- Kalau dibutuhkan, **cetak perintah lengkapnya** untuk dijalankan user di terminal host/VPS. Contoh:
  - start stack: `cd /workspace/myapp-ai && docker compose up -d`
  - stop stack: `cd /workspace/myapp-ai && docker compose down --remove-orphans`
  - commit (repo masing-masing): `cd /workspace/myapp-ai && git add -A && git commit -m "..."`

## Portability (VPS baru)

- Isi skill ini hidup di `myapp-ai/skills/peta-proyek/SKILL.md` dan ikut repo git `myapp-ai`.
- Pointer pemuatan ada di `/workspace/opencode.jsonc` (bagian `skills.paths`).
- Pindah ke VPS lain: clone repo `myapp-ai`, lalu salin `/workspace/opencode.jsonc` dari template `myapp-ai/opencode.example.jsonc`.