import { supabase } from './supabase'
import type { BreedConfig, RecommendInput, UrnMatch } from './types'

export async function fetchBreeds(): Promise<BreedConfig[]> {
  if (!supabase) return []
  const { data, error } = await supabase
    .from('urn_breed_configs')
    .select('category, breed_name, sort_order')
    .order('sort_order', { ascending: true })

  if (error) throw error
  return (data ?? []) as BreedConfig[]
}

export async function matchUrns(
  input: RecommendInput,
  processMethod: 'fire' | 'water',
): Promise<UrnMatch[]> {
  if (!supabase) throw new Error('Supabase 尚未設定')

  const { data, error } = await supabase.rpc('match_suitable_urns', {
    p_breed_name: input.breedName,
    p_health_weight: input.healthWeight,
    p_leave_weight: input.leaveWeight,
    p_is_powdered: input.isPowdered,
    p_age: input.age,
    p_process_method: processMethod,
    p_has_keepsakes: input.hasKeepsakes,
  })

  if (error) throw error
  return (data ?? []) as UrnMatch[]
}

export async function logRecommendation(
  input: RecommendInput,
  processMethod: string,
  matches: UrnMatch[],
): Promise<void> {
  if (!supabase || matches.length === 0) return

  const calculated = matches[0]?.calculated_volume_ml ?? null
  await supabase.from('urn_recommendation_logs').insert({
    breed: input.breedName,
    input_health_weight: input.healthWeight,
    input_leave_weight: input.leaveWeight,
    input_age: input.age,
    is_powdered: input.isPowdered,
    process_method: processMethod,
    has_keepsakes: input.hasKeepsakes,
    calculated_volume_ml: calculated,
    recommended_urn_ids: matches.slice(0, 5).map((m) => m.product_id),
  })
}
