import CourtMap, { type Pin } from './CourtMap';

/** 静态的球馆目录页上的地图（滚动到附近才加载）：点一个球馆就打开它的页面 */
export function PinsMap({ pins, selected, label }: { pins: Pin[]; selected?: string; label: string }) {
  const centre = pins.find((pin) => pin.id === selected) ?? pins[0];
  return (
    <CourtMap
      centre={centre}
      pins={pins}
      selected={selected}
      label={label}
      onSelect={(id) => {
        const href = pins.find((pin) => pin.id === id)?.href;
        if (href && id !== selected) location.assign(href);
      }}
    />
  );
}
