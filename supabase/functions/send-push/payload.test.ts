// 推送内容的测试：deno test --allow-env --allow-read supabase/functions/
import assert from 'node:assert/strict';
import { apnsPayload, collapseId, type Item } from './payload.ts';

const base: Item = { id: 1, kind: 'apns', token: 't', title: 'Game on', body: 'Saturday 7 PM', link: '/games/g/' };
const chat: Item = {
  ...base, id: null, title: 'Kevin', body: 'Bring shuttles?', link: '/messages/game/g/',
  chat: { thread: 'game:g', sender: 'u1', name: 'Kevin', avatar: 'u1/a.jpg', group: 'LA Badminton Club', members: 4 },
};

Deno.test('普通通知：只有标题、内容和链接', () => {
  assert.deepEqual(apnsPayload(base, 'https://x.supabase.co'), {
    aps: { alert: { title: 'Game on', body: 'Saturday 7 PM' }, sound: 'default' }, link: '/games/g/',
  });
});

Deno.test('聊天推送：让通知扩展改内容，按会话归组，头像给完整地址', () => {
  const payload = apnsPayload(chat, 'https://x.supabase.co') as any;
  assert.deepEqual(payload.aps['mutable-content'], 1);
  assert.deepEqual(payload.aps['thread-id'], 'game:g');
  assert.deepEqual(payload.chat.avatar, 'https://x.supabase.co/storage/v1/object/public/avatars/u1/a.jpg');
  assert.deepEqual(payload.chat.members, 4);
});

Deno.test('没有头像就不给地址；只有球群只留最新一条', () => {
  const group: Item = { ...chat, chat: { ...chat.chat!, thread: 'group:p', avatar: null } };
  assert.deepEqual((apnsPayload(group, 'https://x.supabase.co') as any).chat.avatar, null);
  assert.deepEqual(collapseId(group), 'group:p');
  assert.deepEqual(collapseId(chat), undefined);
  assert.deepEqual(collapseId(base), undefined);
});
