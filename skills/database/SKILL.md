---
name: database
description: Use when working with this project's PostgreSQL database — SQL schema/migration files in myapp-ai-be/database/ (schema/ and seed/), db-run.sh, adding tables/triggers/procedures, seed data, stock_movements, running numbers, RBAC user_menus, system_types, or any database design question in this project. Covers file conventions and how to execute scripts. Use ONLY for this project's DB; for opencode's own config use customize-opencode.
---

# Database — myapp POS (PostgreSQL 16)

Konvensi file: satu concern per file di `schema/` — kalau bisa dipisah, satu tabel satu file (mis. tiap tabel/objek memiliki file sendiri; file khusus function/trigger/fix juga wajar).

## Peta cepat

| Item        | Lokasi / Nilai                                    |
| ----------- | ------------------------------------------------- |
| Root DB     | `myapp-ai-be/database/`                           |
| Migrations  | `schema/NNN_description.sql` (append-only)        |
| Seed data   | `seed/` (terpisah, idempotent, bisa diulang)       |
| Runner      | `database/db-run.sh` (dari HOST) |
| Container   | `myapp-db`, port host `127.0.0.1:5433`, db `myapp` |
| Jaringan    | `myapp-db:5432` (nama service, bisa diakses dari kontainer opencode/backend/frontend) |

Penomoran saat ini: `schema/` 001–018, `seed/` 001–003. Nomor di `schema/` dan
`seed/` independen masing-masing; urutan eksekusi selalu `schema/` dulu baru
`seed/` (batas penomoran antar folder tidak harus sinkron).

## Aturan wajib

1. **Append-only migration.** Setelah file "rilis", jangan pernah edit. Setiap perubahan skema = file nomor baru berikutnya (`015_*.sql`, dst). Fungsi/trigger pakai `CREATE OR REPLACE` + `DROP TRIGGER IF EXISTS` supaya aman.
2. **Seed ≠ skema.** Data awal hanya di `seed/` dengan `ON CONFLICT DO NOTHING` / `UPDATE ... WHERE`. Jangan menaruh `INSERT` data awal di `schema/` lagi.
3. **Eksekusi.** `db-run.sh` dari HOST (butuh `bash` + `docker`). Kontainer opencode TIDAK punya `docker` tetapi SUDAH punya `bash` + `psql` (di image), jadi dari sana pakai `psql` langsung (lihat "Cara menjalankan").
4. **Kredensial** dibaca runner dari `myapp-ai/.env`. Jangan pernah menampilkan/menyalin isi `.env`.
5. **Jangan menyentuh** `myapp-ai/note.txt`.

## Cara menjalankan (perintah host)

```bash
cd /workspace/myapp-ai-be/database
./db-run.sh schema            # semua file schema/ urut 001 → 0N
./db-run.sh seed <file.sql>   # satu file seed (basename saja)
./db-run.sh all               # schema lalu seluruh seed
```

Kerjanya: stream file `.sql` ke `docker compose exec -T myapp-db psql -U $DB_USER -d $DB_NAME`, dengan `ON_ERROR_STOP=1` (gagal = berhenti).

## Cara menjalankan (dari kontainer opencode)

`opencode` tidak punya `docker`, tapi ada `psql` — connect langsung ke service
`myapp-db` lewat jaringan compose (kredensial dari `.env`, tanpa menampilkan isinya):

```bash
set -a; . /workspace/myapp-ai/.env; set +a
PGPASSWORD="$DB_PASSWORD" psql -h myapp-db -p 5432 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1
```

Contoh jalanin seed langsung:

```bash
cd /workspace/myapp-ai-be/database
set -a; . ../.env; set +a
PGPASSWORD="$DB_PASSWORD" psql -h myapp-db -p 5432 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f seed/003_products_seed.sql
```

Alternatif untuk query sederhana dari opencode: node + pustaka `pg` (harus
di-install ulang tiap container direcreate; area `/tmp/opencode` tidak persisten).

## Checklist saat menambah tabel/object baru

1. Nomor file berikutnya di `schema/` (cek `ls` dulu, jangan duplikat nomor).
2. Ikuti pola kolom `001_users.sql`: `id BIGSERIAL PRIMARY KEY`, kolom domain, lalu 9 kolom audit standar (`add_on`, `add_by`, `change_on`, `change_by`, `change_no`, `change_system_on`, `change_system_by`, `print_on`, `print_by`, `print_count`).
3. `*_by` selalu `BIGINT REFERENCES users(id)`.
4. Index untuk setiap FK yang sering ditelusuri + kolom query (tanggal dokumen, dsb.).
5. Data awal (opsional) → file baru di `seed/`, bukan di `schema/`.
6. Minta user menguji di host: `./db-run.sh schema` pada DB segar.

## Struktur data (ringkas)

- **Lookup** `system_types(category, code)`: `MOVEMENT_TYPE` (sign ±1), `TRANS_STATUS` (ACTIVE/VOID), `PERMISSION` (V/A/E/D/P/X), `USER_TYPE` (OWNER/SUPER_ADMIN/ADMIN/USER).
- **RBAC**: `users.type` + `menus.permission` + `user_menus` (permission per user-menu). Trigger `003` auto-seed saat user/menu baru; `OWNER` dapat permission penuh, lainnya `'{}'`. Trigger `018` menegakkan `back_date`/`forward_date` (batas tanggal dokumen) per menu user saat insert/update `sales`/`purchases`.
- **Stok**: `stock_movements` = sumber kebenaran (qty selalu +, arah via `move_type` → `system_types.sign`). `products.qty` = cache yang disinkronkan trigger. Trigger `014`+`015` menolak saldo minus dan mensinkronkan cache untuk `INSERT`/`UPDATE`/`DELETE`, dengan kunci baris `products` (FOR UPDATE) untuk mencegah race condition antar transaksi.
- **Dokumen**: `sales`/`purchases` header (total, status, `no` unique) + `*_items` detail (price/total snap saat transaksi). `017` menjamin `total` item = `qty*price` (CHECK) dan total header di-sync otomatis dari item (trigger).
- **Running number**: `fn_next_running_no(p_category, p_date, p_prefix)` → atomik, format `SO-YYYYMMDD-0001`. Harus dipanggil di transaksi yang sama dengan insert dokumen.
- **Partner**: `bisnis_partners` merged customer+supplier (nama "bisnis" memang typo yang sudah dipakai; rename harus lewat migration baru `ALTER TABLE ... RENAME TO ...`).


## Keputusan desain (hasil diskusi/hak akses pengguna)

| Area | Keputusan |
|---|---|
| Hak akses | Per-user (`user_menus`), plus tingkat user `users.type`: **OWNER, SUPER_ADMIN, ADMIN, USER**. Nilai valid dari `system_types` kategori `USER_TYPE`. |
| Seeding akses | User baru / menu baru → trigger otomatis membuat baris `user_menus`. Setiap pasangan (user, menu) **WAJIB punya baris**. **OWNER** mendapat permission penuh per menu (`menus.permission`); selain OWNER → `'{}'` (diberi manual). |
| Menu | `menus` = menu aplikasi + hak akses (bukan katalog produk). Kolom: name (kode), label, permission (TEXT[]), back_date, forward_date, sort_order, active. |
| Izin menu | `permission TEXT[]` — kode huruf **V=View, A=Add, E=Edit, D=Delete, P=Print, X=eXport**. `menus.permission` = set akses yang didukung menu (template untuk OWNER); `user_menus.permission` = hak akses user, `'{}'` = tidak boleh akses. Nilai valid dari `system_types` kategori `PERMISSION` (bukan CHECK constraint di tabel). |
| Batas tanggal | `back_date` / `forward_date` (jumlah hari, mis. back 0 / forward 30) ada di **`menus`**, bukan per-user. |
| Bisnis partner | `customers` & `suppliers` **digabung** jadi satu tabel `bisnis_partners`. `sales.partner_id` dan `purchases.partner_id` mengarah ke sini. |
| Transaksi | **Header + detail** (sales/sales_items, purchases/purchase_items). |
| Header | tanggal, nomor, partner_id, total, status. |
| Detail | produk, qty, harga, total — **harga selalu snap ke detail** saat transaksi. |
| Stok | `stock_movements` = sumber kebenaran (ledger). `products.qty` hanya cache, di-sync trigger. |
| Anti minus | DB-level: trigger stok `014`/`015` menolak movement bila saldo produk < 0 (ini termasuk `UPDATE`/`DELETE`, dengan lock baris `products`). |
| Costing | **Average cost** (`products.avg_cost` di-update aplikasi). |
| Kode & nama | Tabel sistem `system_types` (category, code, name, sign). `sign` hanya relevan untuk `MOVEMENT_TYPE` (+1/-1); **belum di-rename** ke field generik. |
| Running number | Stored function `fn_next_running_no()` (atomik, `ON CONFLICT`), format `SO-YYYYMMDD-0001`. Nomor bisa diubah manual. |
| Void/batal | `status` = kode `VOID` (baris tetap ada, jejak stok utuh). |
| Backdate | Header transaksi bisa diedit; batas hari dikontrol via `menus.back_date` / `forward_date`, ditegakkan trigger `018` (user tanpa akses menu ikut ditolak). |
| Retur | **Belum masuk v1** (v2). Skema movement sudah siap diperluas. |
| Audit | Semua tabel: `add_on, add_by, change_on, change_by, change_no, change_system_on, change_system_by, print_on, print_by, print_count`. |

## Skema (ringkas)

- `users` — name, email, password, **type**, active.
- `menus` — name (kode), label, **permission TEXT[]**, **back_date**, **forward_date**, sort_order, active.
- `user_menus` — user_id, menu_id, **permission TEXT[]**. `UNIQUE (user_id, menu_id)`. Wajib ada baris untuk tiap pasangan (di-seed trigger).
- `products` — sku, name, category, unit, price_buy, price_sell, avg_cost, qty (cache).
- `bisnis_partners` — name, address, email, phone, contact, company (pengganti customers + suppliers).
- `system_types` — (category, code, name, sign). Seed: `MOVEMENT_TYPE` IN(+)/OUT(-)/AJI(+)/AJO(-)/SLS(-)/PCH(+), `TRANS_STATUS` ACTIVE/VOID, `PERMISSION` V/A/E/D/P/X, `USER_TYPE` OWNER/SUPER_ADMIN/ADMIN/USER.
- `sales` / `sales_items`, `purchases` / `purchase_items` — header + detail; header memakai `partner_id`.
- `stock_movements` — product_id, move_type, move_date, qty (> 0), ref_id (ke dokumen asal sesuai move_type), remark.
- `running_numbers` — counter (category, doc_date) untuk `fn_next_running_no`.

Seed yang ada saat ini:
- `001_seed_master.sql` — users contoh (Admin=OWNER, Budi=USER), menus, user_menus. Menu: USER, MENU, USER_MENUS (Set Akses User Menu), SYSTEM_TYPES, PRODUCT, BISNIS_PARTNER, SALES, PURCHASE, STOCK, STOCK_MOVEMENT, INFO_SALES, INFO_PURCHASE — master data `{'V','A','E','D'}`, laporan/history `{'V','X'}` / `{'V','X','P'}`.
- `002_auth_passwords.sql` — bcrypt login: `admin@myapp.local`/`admin123` (OWNER), `budi@myapp.local`/`budi123` (USER).
- `003_products_seed.sql` — 50 produk (8 kategori) + stok awal lewat `stock_movements` (move_type `IN`), idempotent (produk `ON CONFLICT (sku)`; stok hanya bila produk belum punya movement).

## Known gaps (per review 2026-09-22)

Saat menambah fitur baru, jangan mengulangi pola ini — dan perbaikinya harus lewat migration nomor baru:

- Trigger stok (`014`/`015`) belum menangani alur void: mengubah `sales.status` → `VOID` tidak otomatis membalik `stock_movements` (aplikasi harus insert movement pembalik).
