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

`docker` dan `curl` TIDAK tersedia di kontainer opencode — jangan coba di sini. **`go` 1.26.8 SUDAH tersedia** (dicek 2026-10-07): dari kontainer opencode cukup

```bash
cd /workspace/myapp-ai-be && go build ./... && go vet ./... && go test ./...
```

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

- Frontend memanggil `POST /api/<res>/search` dengan body `{ search, sort, limit, offset, ...extra }` (`extra` DataListView di-*spread* polos ke body, mis. `{from,to}`; otomatis terbaca `searchParams`). **Paginasi di server**: respons `{ data: [...], total, limit, offset }` — FE baca `res.data?.data ?? []` dan `res.data?.total` (bukan `{data:{rows}}`).
- `limit` default **10**, maks **1000**; `offset < 0` → 0 (`NormalizeLimitOffset`, `internal/store/query.go:78`).
- Tiap resource punya `SearchX` di `internal/api/search.go` (Copy ke `QueryParams`), handler terdaftar di `internal/api/router.go`.
- Query dibangun di `internal/store/query.go` lewat **`BuildListQueries(qp, ...)`** → `([]models.X, total, error)`. Klausa search dipakai **sama** untuk SELECT data dan COUNT total (bug lama: count pakai kolom JOIN yang tidak dipilih data → `total` salah, `rows` null).
- **Sort wajib whitelist** — map nama kolom → SQL di `query.go` (boleh qualifier tabel, mis. `"journal.add_on"`). Sort di luar whitelist atau sort kosong → `ErrBadSort` → HTTP 400 `{error}`. Karena itu **setiap request search wajib membawa `sort`** — jangan tes search tanpa sort.
- Sort default: FE mengirim lewat prop `defaultSort` `DataListView` (mis. Sales/Purchases: `transaction_date` + `id` desc).

## Dokumen transaksi (sales & purchases) — item ikut diubah

- **Create** `CreateSales`/`CreatePurchase`: running number + header + items + mutasi stok (`SLS` -1 / `PCH` +1) dalam satu transaksi; pembelian juga memanggil `updateAvgCost` (rata-rata tertimbang, **sebelum** movement di-insert karena trigger langsung sinkron `products.qty`).
- **Update** `UpdateSales(ctx,id,in,changeBy)` / `UpdatePurchase(...)`: satu transaksi → `lockActiveDoc` (kunci baris + wajib `status='ACTIVE'`) → tulis ulang items → hapus & tulis ulang `stock_movements` per produk (agregat) → `change_on/change_by/change_no`. Total header mengikuti trigger `trg_sync_purchase_total`/`trg_sync_sales_total` (migrasi 017) — jangan hitung manual.
- **Delete** `DeleteSales`/`DeletePurchase`: urutan **`stock_movements` → items → header** dalam satu transaksi. FK `purchase_items.purchase_id`/`sales_items.sales_id` **tidak** punya `ON DELETE CASCADE`, jadi DELETE biasa selalu 409.
- Harga item `0`/kosong → `resolveItemPrices` isi `price_buy` (pembelian) / `price_sell` (penjualan).
- `avg_cost` pembelian dihitung ulang saat item berubah/dihapus (`applyAvgCost`): nilai akhir = `qtyLama*avgLama − nilaiItemLama + nilaiItemBaru`, dibagi qty akhir; stok habis → `avg_cost` dibiarkan.
- Helper lifecycle dikumpulkan di `internal/store/transaksi.go`.

### Pemetaan error (`internal/api/common.go` → `httpErr`)

| Kondisi | HTTP |
|---|---|
| input tidak valid (`store.ValidationError`: qty 0, items kosong, produk belum dipilih) | 400 |
| `ErrBadSort` | 400 |
| `pgx.ErrNoRows` (id tidak ada) | 404 |
| constraint `23503/23505/23514`, `store.ErrDocLocked` (dokumen `VOID`), trigger `P0001` (mis. "stok tidak boleh minus") | 409 |
| sisanya | 500 |

## Known gap

- **Void belum membalik stok**: `VoidPurchase`/`VoidSales` hanya menyetel `status='VOID'`; `stock_movements` tidak dibalik (reversal void = pekerjaan v2). Dokumen VOID juga tidak bisa diubah/dihapus (409).

## Aturan

- Jangan ubah `myapp-ai/note.txt`, jangan sebarkan isi `myapp-ai/.env`.
- Perubahan kode backend dikompilasi otomatis oleh air; cek `docker compose logs -f myapp-backend` untuk error build.
- Endpoint baru: daftarkan di `internal/api/router.go` (prefix `/api`), tulis handler di `internal/api/`, logic query di `internal/store/`. Semua rute (kecuali login/refresh/logout/health) butuh access token.