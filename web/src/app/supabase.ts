import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.PUBLIC_SUPABASE_URL as string | undefined;
// 只用 publishable key（sb_publishable_…）；secret key 绝不进前端
const key = import.meta.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY as string | undefined;

export const supabase = url && key ? createClient(url, key) : undefined;

export interface Profile {
  id: string;
  nickname: string;
  country_code: string | null;
}

export interface Venue {
  id: string;
  name: string;
  aliases: string[];
  street: string;
  unit: string | null;
  city: string;
  region: string;
  postal_code: string;
  country_code: string;
  court_count: number | null;
  pricing: { perPerson?: number; perCourtHour?: number } | null;
  phone: string | null;
  website: string | null;
  status: 'verified' | 'confirmed' | 'unconfirmed';
  source: string;
  attribution: string | null;
  location_approximate: boolean;
  kind: 'dedicated' | 'multi_sport' | 'rec_center' | 'school' | 'community_hall' | null;
  play_times: string | null;
  lat: number;
  lon: number;
}

export interface NearbyVenue {
  venue: Venue;
  distance_m: number;
}
