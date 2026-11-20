// App 自带的球馆目录：iPhone 按整数读价格（VenueCatalog.swift 的 Price），有一个带小数的整份目录就读不出来。
// 带小数的价格（英国）只能写在 Badie-iOS/data/verified-venues.json，只给网站用
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

const dir = new URL('../../Badie-iOS/Badie/Resources/', import.meta.url);

test('App 目录里的价格都是整数', () => {
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.json'))) {
    const catalog = JSON.parse(readFileSync(new URL(file, dir), 'utf8'));
    for (const venue of catalog.venues ?? []) {
      for (const [key, value] of Object.entries(venue.price ?? {})) {
        assert.ok(Number.isInteger(value), `${file} ${venue.id} 的 ${key} 不是整数：${value}`);
      }
    }
  }
});

test('核对过的球馆：每条都有日期和来源', () => {
  const data = JSON.parse(readFileSync(new URL('../../Badie-iOS/data/verified-venues.json', import.meta.url), 'utf8'));
  for (const [id, v] of Object.entries<Record<string, unknown>>(data.venues)) {
    assert.match(String(v.checked), /^\d{4}-\d{2}-\d{2}$/, `${id} 没有核对日期`);
    if (v.perCourtHour != null || v.perPerson != null || v.playTimes) {
      assert.ok(Array.isArray(v.sources) && v.sources.length > 0, `${id} 有价格或时间但没有来源`);
    }
  }
});
