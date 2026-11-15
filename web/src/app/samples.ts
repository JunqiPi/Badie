// 示例球友：附近的真人太少时，服务器的 nearby_players 在真人后面补几张示例卡（见 supabase/migrations/20261218000000_sample_players.sql）。
// 它们不是账号：id 以这个前缀开头，卡片照片的角上印着“Sample · 示例”。约不了、加不了球友、没有资料页，这里点了会说明。
const PREFIX = '00000000-0000-4000-8000-';

export const isSample = (id: string) => id.startsWith(PREFIX);
