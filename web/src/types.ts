export type ProcessMethod = 'fire' | 'water' | 'undecided'

export type BreedConfig = {
  category: string
  breed_name: string
  sort_order: number
}

export type UrnMatch = {
  product_id: string
  series: string
  size_label: string
  usable_volume_ml: number
  inner_diameter: number
  fill_ratio: number
  is_primary: boolean
  is_estimated: boolean
  warning_tag: string
  calculated_volume_ml: number
  process_method: string
}

export type RecommendInput = {
  breedName: string
  healthWeight: number | null
  leaveWeight: number | null
  isPowdered: boolean
  age: number | null
  processMethod: ProcessMethod
  hasKeepsakes: boolean
}

export const CATEGORY_ORDER = [
  '犬',
  '貓',
  '兔',
  '鼠類',
  '鳥類',
  '爬蟲',
  '特寵',
] as const

export const PROCESS_LABEL: Record<'fire' | 'water', string> = {
  fire: '火化',
  water: '水化',
}
