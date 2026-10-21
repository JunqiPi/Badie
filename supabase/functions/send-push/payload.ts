// 推送内容（单独放一个文件，方便测试）

// 聊天推送没有 id（不回报送达），带 chat：会话、发消息的人（头像是 avatars 桶里的路径）、群名、会话人数
export type Chat = { thread: string; sender: string; name: string | null; avatar: string | null; group: string | null; members: number | null };
export type Item = {
  id: number | null; kind: 'apns' | 'apns_sandbox' | 'web'; token: string; keys?: { p256dh: string; auth: string };
  title: string; body: string; link?: string; chat?: Chat;
};

// 发给 Apple 的内容。聊天推送：App 的通知扩展（mutable-content）下载头像，显示成带头像的聊天通知；
// 同一会话的通知归在一起（thread-id）
export function apnsPayload(item: Item, supabaseUrl: string) {
  const aps = { alert: { title: item.title, body: item.body }, sound: 'default' };
  if (!item.chat) return { aps, link: item.link };
  const { avatar, ...chat } = item.chat;
  return {
    aps: { ...aps, 'mutable-content': 1, 'thread-id': chat.thread },
    link: item.link,
    chat: { ...chat, avatar: avatar ? `${supabaseUrl}/storage/v1/object/public/avatars/${avatar}` : null },
  };
}

// 球群人多，同一个群在锁屏上只留最新一条；私信和球局群聊每条都留
export const collapseId = (item: Item) => (item.chat?.thread.startsWith('group:') ? item.chat.thread : undefined);
