---
name: myapp-frontend
description: Panduan operasional frontend Vue 3 + Vite (myapp-ai-fe, aplikasi "TokoApp"). Gunakan saat bekerja di kode frontend — menambah halaman/view baru, routing, sesi/auth (login & refresh token), komponen PrimeVue, styling, sidebar/RBAC menu, dev server Vite, build produksi Docker/nginx, atau pertanyaan "apakah frontend jalan". Urusan API/backend pakai skill myapp-backend; schema/DB pakai database; koordinasi folder pakai peta-proyek.
---

# MyApp Frontend — Vue 3 + Vite (TokoApp)

## Konteks

- Kode frontend: `myapp-ai-fe` (Vue 3 `<script setup>` + Vite + PrimeVue 4/Aura + PrimeIcons + font Geist Sans + axios + vue-router 5).
- Dev server: container `myapp-frontend` (image `node:24-alpine`, Vite HMR), port 5002 (host `FE_PORT`). Proxy dev `/api` → `VITE_PROXY_TARGET` (default `http://myapp-backend:3000` di compose).
- Produksi: `Dockerfile` multi-stage (build → `nginx:alpine`), `nginx.conf` SPA fallback + proxy `/api/` → `tokoapp-backend:3000`.
- Backend hanya cek token; otorisasi menu (V/A/E/D/P/X) **hanya ditegakkan di frontend** — lihat "Known gaps".

## Peta file penting

| File | Peran |
|---|---|
| `src/main.js` | Bootstrap: router, PrimeVue + tema Aura, font, `style.css`. **Template PrimeVue di-impor per-komponen** (`import Button from 'primevue/button'`, bukan global). |
| `src/router/index.js` | Rute app; guard `beforeEach` → login redirect, refresh token saat reload, public route login. |
| `src/api.js` | Instance axios (`baseURL: VITE_API_BASE`/`/api`). Access token di memori, refresh token di `localStorage` (kunci `tokoapp_refresh_token`). Interceptor 401 → single-flight `refreshTokens()` → retry; gagal → `clearSession()` + event `tokoapp:session-expired`. `login()`, `logout()`, `getAccessToken()`, `hasSession()`. |
| `src/store/auth.js` | State reaktif `auth { user, menus }` dari `GET /api/me`; `hasView(menu)` = `hasPerm(menu,'V')`; `hasPerm(menu, code)` cek permission spesifik (A/E/D/P/X). |
| `src/App.vue` | Layout sidebar + `menuMap` (kode menu DB → rute + ikon). Sidebar di-render dari `auth.menus`; tanpa 'V' → item disabled dengan ikon gembok. |
| `src/views/*` | Satu file per halaman. `Placeholder.vue` dipakai untuk menu yang belum ada halamannya. |
| `src/components/TransactionEditor.vue` | Editor transaksi dipakai bersama **sales & purchase** (prop `mode`). |
| `vite.config.js` | Plugin vue; server port 5002; proxy `/api` → host default `127.0.0.1:3001` dari kontainer, bisa dioverride `VITE_PROXY_TARGET`. |

## Alur kerja

- Menambah **halaman baru** (menu sudah ada di DB): buat `src/views/X.vue` → daftarkan rute di `router/index.js` → ganti pemetaan di `menuMap` `App.vue` (dari `path:` jadi `to:`). Menu tanpa halaman cukup dibiarkan placeholder.
- Menambah **menu** (belum ada di DB): perubahan DB dulu (skill database — seed `menus`), lalu pemetaan di `App.vue`.
- Style inline + CSS global di `style.css` (kelas `.page-title`, `.page-subtitle`, `.p-field`, `.dialog-form`, `.text-right`, dsb.). Format Rupiah: `new Intl.NumberFormat('id-ID', { style:'currency', currency:'IDR', maximumFractionDigits:0 })`.

## Perintah

Node/npm TIDAK aman sembarangan dari kontainer opencode (bind-mount; `node_modules` milik volume terpisah `frontend-node_modules`) — lihat peta-proyek. Keperluan build/test frontend lewat container:

```bash
cd /workspace/myapp-ai
docker compose logs -f myapp-frontend   # lihat Vite/HMR
# build produksi untuk verifikasi (di dalam container, hindari menulis node_modules/dist dari luar)
docker compose exec myapp-frontend sh -c "npm run build"
```

(Coba `npm run build` dari host hanya jika user memintanya dan `package.json` ada.)

## Konvensi halaman CRUD (ikuti pola `Products.vue` / `Partners.vue`)

- `rows/loading/editingId/dialogVisible/saving/error` + `emptyForm()` + `load()` + `openAdd/openEdit/save/remove`.
- DataTable + Column; Harga pakai `InputNumber mode="currency" currency="IDR" locale="id-ID"`; Status pakai `Tag`; tombol aksi ikon `pi pi-pencil`/`pi pi-trash` ukuran kecil.
- Error: `e.response?.data?.error || e.message`. Hapus/pakai `confirm()`/`alert()` (belum pakai ConfirmDialog).

## `DataListView.vue` — komponen list+search+sort+paginator (dipakai Products, Partners, Menus, Sales, Purchases, Users)

> Satu komponen bersama utk SEMUA halaman CRUD list. View tinggal menyusun `<Column>` dalam slot. Halaman blank biasanya karena `<script setup>` memakai hook (mis. `onMounted`) yang **tidak di-import dari `vue`** — selalu pastikan `import { onMounted, ref } from 'vue'` (tambah `computed`/`watch` bila dipakai).

Props: `resource` (string, endpoint sbg `/<resource>/search`), `extra` (object, dikirim polos di body — mis. `{from,to}` utk filter tanggal; `deep watch` → auto-reload).

Slot: `#filters` (isi toolbar filter atas), `#actions` (tombol Tambah dll.), default = kolom `<Column>`.

Data & paging: **semua baris hasil search dimuat sekali** lalu PrimeVue `DataTable` paginate **client-side** (`paginator :rows="10"`, `v-model:first`) — klik "next" TIDAK memicu request (bukan bug, memang client-side). `v-model:multiSortMeta` + `sortMode="multiple"` → sort multi-kolom dikirim sbg `sort: [{column, order}]`. `rows` di-expose sbg `reload()` agar view bisa panggil `list.value?.reload()`. Cari pakai `InputText` + debounce (~300ms) → `POST /<resource>/search`.

## Pola halaman CRUD (konvensi `Products.vue`/`Partners.vue`)

Prima: `<DataListView ref="list" resource="products" ...>`; kemudian `<Column>` utk tiap field (header/body slot utk format Rupiah/status `Tag`). Tombol aksi per baris: panggil `$list` (prop DataListView) aksi edit/hapus; gating tombol via `store/auth` `hasPerm` (kucek: A=E dokumen 2026-09-22 — lihat Known gaps).

## Kartu akses user untuk tes

Login seed (lihat skill myapp-backend): `admin@myapp.local / admin123` (OWNER), `budi@myapp.local / budi123` (USER).

## Aturan wajib

- JANGAN mengubah `myapp-ai/note.txt`; JANGAN menyebarkan isi `myapp-ai/.env`.
- Jangan menulis ke `node_modules`/`dist` dari luar container (kepemilikan file volume).
- Setiap akses API butuh sesi: kalau 401 saat develop, cek backend & seed DB dulu (skill database/myapp-backend).

## Known gaps (review 2026-09-22)

- **Aksi CRUD sudah dicek per permission** (`hasPerm(menu, code)` di `store/auth.js`, `code` = A/E/D dst. — lihat `src/views/*`): tombol Tambah gated 'A', Edit/Ganti-password/Void gated 'E', Hapus gated 'D'. Catatan: ini HANYA UI, backend tetap tidak enforce RBAC — jangan pernah mengandalkan gating frontend sebagai keamanan.
- **`USER_MENUS` (Set Akses User Menu) baru placeholder** — belum ada UI untuk grant permission per user; padahal seed RBAC mengharuskan baris `user_menus` per pasangan user-menu.
- **Dashboard memanggil `/products` & `/partners` tanpa cek menu** — user tanpa hak 'V' kedua menu itu dashboard-nya error/aneh (dan hitung "Nilai Stok" ikut). Pertimbangkan gabungkan dengan `hasView` + fallback.
- README.md masih template default Vite (boleh diperbarui kapan saja).