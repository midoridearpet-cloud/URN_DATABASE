import './style.css'
import { fetchBreeds, logRecommendation, matchUrns } from './api'
import { supabaseConfigured } from './supabase'
import {
  CATEGORY_ORDER,
  PROCESS_LABEL,
  type BreedConfig,
  type ProcessMethod,
  type RecommendInput,
  type UrnMatch,
} from './types'

const app = document.querySelector<HTMLDivElement>('#app')!
let breeds: BreedConfig[] = []

function fillPercent(ratio: number): number {
  return Math.round(ratio * 100)
}

function renderCard(match: UrnMatch): string {
  const badge = match.is_primary ? '首選' : '較寬裕'
  const estimated = match.is_estimated ? '<span class="tag tag-warn">容量推估</span>' : ''
  return `
    <article class="card ${match.is_primary ? 'card-primary' : ''}">
      <div class="card-top">
        <h3>${match.series} ${match.size_label}</h3>
        <span class="badge">${badge}</span>
      </div>
      <p class="meta">可用約 ${match.usable_volume_ml} ml · 預估填充約 ${fillPercent(match.fill_ratio)}%</p>
      <p class="warn">${match.warning_tag}</p>
      ${estimated}
    </article>
  `
}

function renderResultBlock(title: string, volume: number | null, matches: UrnMatch[]): string {
  if (matches.length === 0) {
    return `
      <section class="result-block">
        <h2>${title}</h2>
        <p class="empty">目前沒有符合條件的款式。可改選磨粉、或聯繫店家人工確認。</p>
      </section>
    `
  }

  const primary = matches.filter((m) => m.is_primary)
  const others = matches.filter((m) => !m.is_primary).slice(0, 4)
  const show = [...(primary.length ? primary : matches.slice(0, 1)), ...others].slice(0, 6)

  return `
    <section class="result-block">
      <h2>${title}</h2>
      <p class="volume">預估所需容積約 <strong>${volume ?? show[0].calculated_volume_ml} ml</strong></p>
      <div class="cards">${show.map(renderCard).join('')}</div>
    </section>
  `
}

function collectInput(): RecommendInput | null {
  const category = (document.querySelector('#category') as HTMLSelectElement).value
  const breedName = (document.querySelector('#breed') as HTMLSelectElement).value
  const healthRaw = (document.querySelector('#healthWeight') as HTMLInputElement).value
  const leaveRaw = (document.querySelector('#leaveWeight') as HTMLInputElement).value
  const ageRaw = (document.querySelector('#age') as HTMLInputElement).value
  const powdered = (document.querySelector('input[name="powdered"]:checked') as HTMLInputElement | null)?.value
  const process = (document.querySelector('input[name="process"]:checked') as HTMLInputElement | null)?.value as ProcessMethod | undefined
  const keepsakes = (document.querySelector('#keepsakes') as HTMLInputElement).checked

  const err = document.querySelector('#formError')!
  err.textContent = ''

  if (!category || !breedName) {
    err.textContent = '請選擇寵物種類與品種。'
    return null
  }
  if (!healthRaw && !leaveRaw) {
    err.textContent = '請至少填寫健康體重或離開前體重其中一項。'
    return null
  }
  if (powdered !== 'yes' && powdered !== 'no') {
    err.textContent = '請選擇是否磨粉。'
    return null
  }
  if (!process || !['fire', 'water', 'undecided'].includes(process)) {
    err.textContent = '請選擇火化、水化，或尚未決定。'
    return null
  }

  const healthWeight = healthRaw ? Number(healthRaw) : null
  const leaveWeight = leaveRaw ? Number(leaveRaw) : null
  const age = ageRaw ? Number(ageRaw) : null

  if ((healthWeight !== null && !(healthWeight > 0)) || (leaveWeight !== null && !(leaveWeight > 0))) {
    err.textContent = '體重請輸入大於 0 的數字（單位：公斤）。'
    return null
  }

  return {
    breedName,
    healthWeight,
    leaveWeight,
    isPowdered: powdered === 'yes',
    age,
    processMethod: process,
    hasKeepsakes: keepsakes,
  }
}

function populateBreeds(category: string) {
  const select = document.querySelector('#breed') as HTMLSelectElement
  const list = breeds
    .filter((b) => b.category === category)
    .sort((a, b) => a.sort_order - b.sort_order || a.breed_name.localeCompare(b.breed_name, 'zh-Hant'))

  select.innerHTML =
    `<option value="">請選擇品種</option>` +
    list.map((b) => `<option value="${b.breed_name}">${b.breed_name}</option>`).join('')
  select.disabled = list.length === 0
}

function renderAppShell() {
  const categories = CATEGORY_ORDER.filter((c) => breeds.some((b) => b.category === c))

  app.innerHTML = `
    <main class="page">
      <header class="hero">
        <p class="brand">DEARPET</p>
        <h1>骨灰罐尺寸建議</h1>
        <p class="lead">依毛孩體重與處理方式，幫您縮小合適尺寸範圍。結果僅供參考，最終仍以現場為準。</p>
      </header>

      ${
        supabaseConfigured
          ? ''
          : `<div class="banner">尚未設定 Supabase 環境變數。請在 Netlify 或本機 <code>.env</code> 填入 VITE_SUPABASE_URL 與 VITE_SUPABASE_ANON_KEY。</div>`
      }

      <form id="urnForm" class="form" novalidate>
        <fieldset>
          <legend>寵物資料 <span class="req">必填</span></legend>
          <label>
            種類
            <select id="category" required>
              <option value="">請選擇</option>
              ${categories.map((c) => `<option value="${c}">${c}</option>`).join('')}
            </select>
          </label>
          <label>
            品種
            <select id="breed" required disabled>
              <option value="">請先選種類</option>
            </select>
          </label>
          <div class="row">
            <label>
              健康時體重（kg）
              <input id="healthWeight" type="number" min="0.01" step="0.1" inputmode="decimal" placeholder="例如 4.5" />
            </label>
            <label>
              離開前體重（kg）
              <input id="leaveWeight" type="number" min="0.01" step="0.1" inputmode="decimal" placeholder="選填，建議一併填" />
            </label>
          </div>
          <p class="hint">體重至少填一項；若兩者都填，系統以健康體重推算骨架。</p>
        </fieldset>

        <fieldset>
          <legend>處理方式 <span class="req">必填</span></legend>
          <div class="choice-group" role="radiogroup" aria-label="是否磨粉">
            <p class="choice-label">是否磨粉</p>
            <label class="choice"><input type="radio" name="powdered" value="no" /> 不磨粉（保留骨骸）</label>
            <label class="choice"><input type="radio" name="powdered" value="yes" /> 要磨粉</label>
          </div>
          <div class="choice-group" role="radiogroup" aria-label="火化或水化">
            <p class="choice-label">火化或水化</p>
            <label class="choice"><input type="radio" name="process" value="fire" /> 火化</label>
            <label class="choice"><input type="radio" name="process" value="water" /> 水化</label>
            <label class="choice"><input type="radio" name="process" value="undecided" /> 尚未決定（同時看兩種建議）</label>
          </div>
        </fieldset>

        <fieldset>
          <legend>選填</legend>
          <label>
            年齡（歲）
            <input id="age" type="number" min="0" step="0.5" inputmode="decimal" placeholder="未填則以成年估算" />
          </label>
          <label class="check">
            <input id="keepsakes" type="checkbox" />
            預計放入陪葬品／防潮袋（會多留空間）
          </label>
        </fieldset>

        <p id="formError" class="error" role="alert"></p>
        <button type="submit" class="submit" ${supabaseConfigured ? '' : 'disabled'}>查看建議尺寸</button>
      </form>

      <div id="results" class="results" hidden></div>

      <footer class="foot">
        <p>此工具為預估參考，實際骨骸體積會因火化／水化現場狀況而異。若毛孩頭骨較大且不磨粉，請特別留意罐口尺寸。</p>
      </footer>
    </main>
  `

  document.querySelector('#category')?.addEventListener('change', (e) => {
    populateBreeds((e.target as HTMLSelectElement).value)
  })

  document.querySelector('#urnForm')?.addEventListener('submit', onSubmit)
}

async function onSubmit(event: Event) {
  event.preventDefault()
  const input = collectInput()
  if (!input) return

  const results = document.querySelector<HTMLDivElement>('#results')!
  results.hidden = false
  results.innerHTML = `<p class="loading">計算中…</p>`

  const methods: Array<'fire' | 'water'> =
    input.processMethod === 'undecided' ? ['fire', 'water'] : [input.processMethod]

  try {
    const blocks: string[] = []
    for (const method of methods) {
      const matches = await matchUrns(input, method)
      await logRecommendation(input, method, matches)
      const title =
        input.processMethod === 'undecided'
          ? `若採${PROCESS_LABEL[method]}`
          : `${PROCESS_LABEL[method]}建議`
      blocks.push(renderResultBlock(title, matches[0]?.calculated_volume_ml ?? null, matches))
    }
    results.innerHTML = blocks.join('')
    results.scrollIntoView({ behavior: 'smooth', block: 'start' })
  } catch (err) {
    const message = err instanceof Error ? err.message : '查詢失敗'
    results.innerHTML = `<p class="error">無法取得建議：${message}</p>`
  }
}

async function boot() {
  app.innerHTML = `<main class="page"><p class="loading">載入品種資料中…</p></main>`

  if (!supabaseConfigured) {
    breeds = []
    renderAppShell()
    return
  }

  try {
    breeds = await fetchBreeds()
    if (breeds.length === 0) {
      app.innerHTML = `
        <main class="page">
          <div class="banner">連上 Supabase 了，但還沒有品種資料。請先在 SQL Editor 執行 <code>supabase/install_all.sql</code>。</div>
        </main>`
      return
    }
    renderAppShell()
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    app.innerHTML = `
      <main class="page">
        <div class="banner">無法讀取品種資料：${message}<br/>請確認已執行 SQL，且 RLS／anon 權限正確。</div>
      </main>`
  }
}

boot()
