# 寵物骨灰罐尺寸建議

規則式尺寸推薦（不用 AI 猜容量）：客人填品種／體重／磨粉／火化或水化 → Supabase 公式計算 → 網頁顯示合適款式。

可部署到 Netlify，再用 iframe 嵌入 Shopline。

## 你需要完成的步驟

### 1. 在既有 Supabase 專案執行 SQL

1. 打開預約系統使用的那個 Supabase 專案 → **SQL Editor**
2. 貼上並執行整份 [`supabase/install_all.sql`](supabase/install_all.sql)
3. 確認 Table Editor 出現：
   - `urn_products`
   - `urn_breed_configs`
   - `urn_system_factors`
   - `urn_recommendation_logs`
4. 在 **Project Settings → API** 複製：
   - Project URL
   - `anon` `public` key

此腳本只建立 `urn_*` 物件，不會改預約／ERP 既有表。

### 2. 本機測試（可選）

```bash
cd web
copy .env.example .env
# 編輯 .env，填入 URL 與 anon key
npm install
npm run dev
```

瀏覽器打開終端機顯示的本機網址，測一筆「成貓約 4.5kg、火化、不磨粉」。

### 3. 建立 Netlify 網站

1. 把這個資料夾推到 GitHub（或用 Netlify CLI 直接部署）
2. Netlify → **Add new site** → Import from Git
3. Build settings 會讀根目錄 [`netlify.toml`](netlify.toml)（base=`web`）
4. **Site configuration → Environment variables** 新增：
   - `VITE_SUPABASE_URL` = 你的 Supabase URL
   - `VITE_SUPABASE_ANON_KEY` = 你的 anon key
5. Deploy 完成後得到網址，例如 `https://dearpet-urn-size.netlify.app`

### 4. 嵌入 Shopline

在目標頁面加 Custom HTML／iframe，例如：

```html
<iframe
  src="https://YOUR-SITE.netlify.app/"
  title="骨灰罐尺寸建議"
  style="width:100%;min-height:1100px;border:0;display:block;"
  loading="lazy"
></iframe>
```

若 iframe 被擋，檢查 Netlify 的 `frame-ancestors`（已寫在 `netlify.toml`，含 `dearpet.tw` 與 Shopline 網域）。

也可直接參考 [`shopline-embed-snippet.html`](shopline-embed-snippet.html)。

## 公式與可調常數

預估容積：

`健康體重 × 品種骨骼係數 × 處理倍率 × 年齡倍率 × 安全緩衝`

常數在表 `urn_system_factors`，可在 Table Editor 直接改，不必改程式。

## 必填欄位

1. 品種  
2. 體重（健康或離開前至少一個）  
3. 是否磨粉  
4. 火化／水化／尚未決定（尚未決定會同時顯示兩組建議）

## 專案結構

```
supabase/
  install_all.sql          ← 貼到 SQL Editor 一次跑完
  migrations/001_urn_schema.sql
  seed/...
web/                       ← Netlify 前端
netlify.toml
```

## 注意

- 白陶 6／7 寸容量為推估值（標 `is_estimated`），有實測後請更新 `urn_products`
- 前端只用 anon key，不要把 `service_role` 放進 Netlify
