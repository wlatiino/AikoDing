---
name: myapp-backend
description: Panduan operasional backend Go (myapp-ai-be). Gunakan saat bekerja dengan kode backend, verifikasi build/run, tes endpoint, log myapp-backend, atau pertanyaan "apakah backend jalan". Mencakup cara build lewat container myapp-backend (Go 1.26.8 + air), dan cara tes HTTP dari dalam kontainer opencode memakai node (karena curl tidak tersedia). Urusan schema/seed DB pakai skill database; koordinasi folder pakai peta-proyek.
---

# MyApp Backend — Operasional & Testing

## Konteks

- Kode backend: `myapp-ai-be` (module `myapp/backend`). Struktur: `main.go`, `internal/api` (handler+router), `internal/store` (query DB), `internal/models`, `internal/db`.
- Stack (docker-compose): `myapp-backend` = image `golang:1.26-alpine`, live-reload `air`, port 3000 (host: `127.0.0.1:3003` jika BE_PORT default). `myapp-db` = PostgreSQL.
- Frontend bebas menyebut path/endpoint; otorisasi menu hanya di frontend, backend cuma cek token (RBAC belum enforce di server).

## Build / verifikasi (dari host)

```bash
cd /workspace/myapp-ai
docker compose exec myapp-backend go vet ./...
docker compose exec myapp-backend go build -o /tmp/myapp-check .
docker compose logs -f myapp-backend   # lihat hasil air build/run
```

`go`, `docker`, `curl` TIDAK tersedia di kontainer opencode — jangan coba di sini.

## Tes endpoint dari kontainer opencode

Kontainer opencode satu network dengan compose, jadi backend bisa dipanggil lewat DNS `http://myapp-backend:3000` menggunakan **node** (fetch):

```bash
# Health check
node -e 'fetch("http://myapp-backend:3000/api/health").then(r=>r.json()).then(j=>console.log(JSON.stringify(j))).catch(e=>console.log(e.message))'

# Smoke test: login -> /api/me -> /api/users (lama: /api/products, dll.)
node -e '
const base="http://myapp-backend:3000";
(async()=>{
  const l=await fetch(base+"/api/login",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({email:"admin@myapp.local",password:"admin123"})});
  const lj=await l.json(); console.log("login:",l.status);
  const t=lj.data&&lj.data.access_token; if(!t) return;
  const me=await fetch(base+"/api/me",{headers:{Authorization:"Bearer "+t}});
  console.log("me:",me.status);
  const us=await fetch(base+"/api/users",{headers:{Authorization:"Bearer "+t}});
  const uj=await us.json();
  console.log("users:",us.status,"count="+(uj.data?uj.data.length:"?")+", has_password_in_payload="+("password" in ((uj.data||[])[0]||{})));
})();'
```

- Login user seed: `admin@myapp.local / admin123` (OWNER), `budi@myapp.local / budi123` (USER).
- **401 saat login setelah compose up** biasanya berarti DB belum di-seed (skema/seed tidak auto-run). Jalankan dari host: `cd /workspace/myapp-ai-be && ./database/db-run.sh`, lalu tes ulang.

## Search API (`POST /api/<res>/search`) — dipakai semua halaman list FE

- Frontend memanggil `POST /api/<res>/search` body `{ search, extra, sort, from, to }`; respons `{ data: rows }` (**bukan** `{data:{rows}}`) — FE baca `res.data?.data ?? []`.
- Tiap resource punya `SearchX` di `internal/api/search.go` (meng-Copy ke `QueryParams`), handler terdaftar di `internal/api/router.go` (`/api/<res>/search`).
- Query dibangun di `internal/store/query.go` via `sortOrder(qp, cols)` + `ilikeCols(search, cols, idx)` (semua kolom **pakai placeholder index SAMA**), lalu `ListX`/`SearchX` di `internal/store/*.go` menjalankan SELECT tanpa LIMIT — FE memaginasi **client-side** (`DataTable paginator :rows="10"`; klik next **tidak** menembak ulang API, itu normal).
- **Sort wajib whitelist** — `query.go` define `productSortCols`, `partnerSortCols`, `salesSortCols`, `purchasesSortCols`, `userSortCols`, `menuSortCols` (map nama kolom → SQL, boleh `JOIN result qualifier`). Sort di luar whitelist → `ErrBadSort` → handler balas HTTP 400 `{error}`. Sort default: `name, id`.
- Jika kolom ambigu saat join (mis. `add_on` ada di sales & journal): map sort ke qualifier tabel, e.g. `sortBy` value `"journal.add_on"`. Kueri diurutkan dengan `ORDER BY` dari sort, default fallback saat sort kosong.

## Aturan

- Jangan ubah `myapp-ai/note.txt`, jangan sebarkan isi `myapp-ai/.env`.
- Perubahan kode backend dikompilasi otomatis oleh air; cek `docker compose logs -f myapp-backend` untuk error build.
- Endpoint baru: daftarkan di `internal/api/router.go` (prefix `/api`), tulis handler di `internal/api/`, logic query di `internal/store/`. Semua rute (kecuali login/refresh/logout/health) butuh access token.