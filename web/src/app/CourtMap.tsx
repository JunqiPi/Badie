// 球馆地图：MapLibre + OpenFreeMap 的免费矢量地图（不用密钥）。只在球馆页按需加载，别的页面不带这几百 KB
import * as maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url';
import { useEffect, useRef } from 'react';
import { t } from './i18n';

maplibregl.setWorkerUrl(workerUrl);

export type Pin = { id: string; name: string; lat: number; lon: number };

const dark = () => matchMedia('(prefers-color-scheme: dark)').matches;

/** 图钉和 iOS 的 CourtPin 一样：天蓝圆点 + 墨色描边 + 硬投影，选中的是柠檬绿、大一号 */
function pinElement(pin: Pin, onSelect: (id: string) => void) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'court-pin';
  button.setAttribute('aria-label', pin.name);
  button.addEventListener('click', (event) => {
    event.stopPropagation();
    onSelect(pin.id);
  });
  return button;
}

export default function CourtMap({ centre, pins, selected, onSelect }: { centre: { lat: number; lon: number }; pins: Pin[]; selected?: string; onSelect: (id: string) => void }) {
  const box = useRef<HTMLDivElement>(null);
  const map = useRef<maplibregl.Map>(undefined);
  const markers = useRef(new Map<string, maplibregl.Marker>());

  useEffect(() => {
    map.current = new maplibregl.Map({
      container: box.current!,
      style: `https://tiles.openfreemap.org/styles/${dark() ? 'dark' : 'positron'}`,
      center: [centre.lon, centre.lat],
      zoom: 11,
      attributionControl: { compact: true },
      cooperativeGestures: true,
    });
    map.current.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
    return () => map.current?.remove();
  }, []);

  useEffect(() => {
    map.current?.easeTo({ center: [centre.lon, centre.lat] });
  }, [centre.lat, centre.lon]);

  // 图钉跟着列表变；把所有球馆放进视野
  useEffect(() => {
    const current = map.current!;
    markers.current.forEach((marker) => marker.remove());
    markers.current.clear();
    for (const pin of pins) {
      markers.current.set(pin.id, new maplibregl.Marker({ element: pinElement(pin, onSelect), anchor: 'center' }).setLngLat([pin.lon, pin.lat]).addTo(current));
    }
    if (pins.length > 1) {
      const bounds = new maplibregl.LngLatBounds();
      pins.forEach((pin) => bounds.extend([pin.lon, pin.lat]));
      current.fitBounds(bounds, { padding: 48, maxZoom: 14, duration: 0 });
    }
  }, [pins]);

  useEffect(() => {
    markers.current.forEach((marker, id) => {
      const element = marker.getElement();
      element.toggleAttribute('data-selected', id === selected);
      if (id === selected) element.setAttribute('aria-current', 'true');
      else element.removeAttribute('aria-current');
    });
    const pin = pins.find((p) => p.id === selected);
    if (pin) map.current?.easeTo({ center: [pin.lon, pin.lat] });
  }, [selected, pins]);

  return <div ref={box} role="region" aria-label={t('Map')} className="court-map h-full w-full" />;
}
