import { useState } from 'react';
import { Combobox } from './Combobox';
import { t } from './i18n';
import { Icon } from './icons';
import { supabase } from './supabase';
import { Button, toast } from './ui';

/** label 为空 = 我的位置 */
export type Centre = { lat: number; lon: number; label?: string };
type Area = { k: 'city' | 'court'; n: string; s: string; c?: [number, number] };

let areas: Promise<Area[]> | undefined;
const loadAreas = () => (areas ??= fetch('/search.json').then((r) => r.json() as Promise<Area[]>));

/** 选一个位置：用定位，或者搜城市 */
export function AreaPicker({ onPick }: { onPick: (centre: Centre) => void }) {
  const [locating, setLocating] = useState(false);
  const [hits, setHits] = useState<Area[]>([]);

  function locate() {
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (p) => {
        setLocating(false);
        onPick({ lat: p.coords.latitude, lon: p.coords.longitude });
      },
      () => {
        setLocating(false);
        toast(t('Location is off. Search an area instead.'), 'error');
      },
      { timeout: 10000 },
    );
  }

  return (
    <>
      <Button busy={locating} onClick={locate}>
        <Icon name="pin" /> {t('Use my location')}
      </Button>
      <Combobox
        label={t('Search an area')}
        placeholder={t('Search an area')}
        options={hits}
        className="w-full sm:w-72"
        onQuery={(query) => {
          const q = query.trim().toLowerCase();
          if (q.length < 2) return setHits([]);
          loadAreas().then((all) => setHits(all.filter((a) => a.k === 'city' && a.n.toLowerCase().includes(q)).slice(0, 6)));
        }}
        onPick={(area) => area.c && onPick({ lat: area.c[0], lon: area.c[1], label: area.n })}
        render={(area) => (
          <>
            <span className="block font-extrabold">{area.n}</span>
            <span className="block text-sm text-ink-secondary">{area.s}</span>
          </>
        )}
      />
    </>
  );
}

export type Court = { id: string; name: string; city: string; time_zone_id: string | null };

/** 按名字搜球馆 */
export function CourtSearch({ onPick, label = t('Search courts') }: { onPick: (court: Court) => void; label?: string }) {
  const [hits, setHits] = useState<Court[]>([]);
  async function search(query: string) {
    const q = query.replace(/[%_*(),.]/g, ' ').trim();
    if (q.length < 2) return setHits([]);
    const { data } = await supabase!.from('venues').select('id, name, city, time_zone_id').is('merged_into', null).ilike('name', `%${q}%`).limit(8);
    setHits((data ?? []) as Court[]);
  }
  return (
    <Combobox
      label={label}
      placeholder={t('Search courts by name')}
      options={hits}
      onQuery={search}
      onPick={onPick}
      render={(c) => (
        <>
          <span className="block font-extrabold">{c.name}</span>
          <span className="block text-sm text-ink-secondary">{c.city}</span>
        </>
      )}
    />
  );
}
