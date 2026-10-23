import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode, type SubmitEvent } from 'react';
import { t } from './i18n';
import { Icon, type IconName } from './icons';
import { Avatar, CountBadge, Divider, Empty, IconButton, IconTile, LargeTitle, LevelBadge, ScreenHeader, Segmented, type Tint } from './kit';
import { Link, navigate } from './router';
import { problem, supabase, tagText, useLive, type FoundPlayer, type Friend, type Regular, type Thread, type ThreadKind, type ThreadSummary, type Update } from './supabase';
import { day, hours, relative } from './time';
import { Button, Field, Skeleton, toast } from './ui';

type Tab = 'chats' | 'friends';

/** 消息：桌面上左边会话列表、右边聊天；手机上列表和聊天各占一屏 */
export function Messages({ open }: { open?: { kind: ThreadKind; id: string } }) {
  const initial = new URLSearchParams(location.search).get('tab') === 'friends' ? 'friends' : 'chats';
  const [tab, setTab] = useState<Tab>(initial);
  const { data: threads } = useLive<ThreadSummary[]>('my_threads', { every: 15_000 });
  const { data: friends, refresh: refreshFriends } = useLive<{ friends: Friend[]; requests: Friend[] }>('my_friends', { every: 60_000 });
  const unread = threads?.reduce((sum, th) => sum + (th.unread > 0 ? 1 : 0), 0) ?? 0;
  const pick = (next: Tab) => {
    setTab(next);
    history.replaceState(null, '', next === 'friends' ? '/messages/?tab=friends' : '/messages/');
  };

  const list = (
    <div className={`grid content-start gap-4 ${open ? 'hidden lg:grid' : ''}`}>
      <LargeTitle title={t('Messages')}>
        <IconButton icon="userPlus" label={t('Find players')} onClick={() => pick('friends')} />
      </LargeTitle>
      <Segmented
        label={t('Messages')}
        value={tab}
        onChange={pick}
        options={[
          { value: 'chats', label: t('Chats'), badge: unread },
          { value: 'friends', label: t('Players'), badge: friends?.requests.length ?? 0 },
        ]}
      />
      <div key={tab} className="animate-enter">
        {tab === 'chats' ? <ChatList threads={threads} open={open} /> : <Friends data={friends} refresh={refreshFriends} />}
      </div>
    </div>
  );

  return (
    <div className="grid gap-6 lg:grid-cols-[24rem_minmax(0,1fr)] lg:items-start lg:gap-8">
      {list}
      {open ? (
        <Chat key={open.id} kind={open.kind} id={open.id} />
      ) : (
        <div className="hidden lg:block lg:sticky lg:top-24">
          <Empty icon="chats" tint="sky" title={t('Pick a chat')}>
            {t('Each confirmed game gets a group chat. Friends can message each other anytime.')}
          </Empty>
        </div>
      )}
    </div>
  );
}

const threadIcon: Record<ThreadKind, [IconName, Tint]> = { game: ['games', 'lime'], group: ['group', 'lavender'], dm: ['user', 'sky'] };

function ChatList({ threads, open }: { threads?: ThreadSummary[]; open?: { id: string } }) {
  if (!threads) return <div className="grid gap-3">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-16" />)}</div>;
  if (!threads.length) {
    return (
      <Empty icon="chats" tint="sky" title={t('No chats yet')}>
        {t('Each confirmed game gets a group chat. Friends can message each other anytime.')}
      </Empty>
    );
  }
  return (
    <ul className="sticker grid p-2" aria-label={t('Chats')}>
      {threads.map((th, i) => {
        const [icon, tint] = threadIcon[th.kind];
        return (
          <li key={`${th.kind}-${th.id}`}>
            {i > 0 && <div className="mx-2"><Divider /></div>}
            <Link
              to={`/messages/${th.kind}/${th.id}/`}
              aria-current={open?.id === th.id ? 'page' : undefined}
              className="press flex items-center gap-3 rounded-[14px] p-2.5 hover:bg-surface-muted/70 aria-[current=page]:bg-lime/35"
            >
              {th.kind === 'dm' ? <Avatar id={th.id} name={th.name ?? '?'} size={44} /> : <IconTile icon={icon} tint={tint} />}
              <span className="min-w-0 flex-1">
                <span className="flex items-baseline gap-2">
                  <span className="min-w-0 flex-1 truncate font-bold">
                    {th.kind === 'game' ? `${day(th.starts_at!, th.tz)} · ${th.venue}` : th.name}
                  </span>
                  {th.last && <span className="shrink-0 text-caption text-ink-tertiary">{relative(th.last.created_at)}</span>}
                </span>
                <span className="flex items-center gap-2">
                  <span className={`min-w-0 flex-1 truncate text-footnote ${th.unread ? 'font-bold text-ink' : 'text-ink-secondary'}`}>
                    {th.request === 'incoming' ? t('Message request') : preview(th)}
                  </span>
                  <CountBadge count={th.unread} />
                  {th.unread > 0 && <span className="sr-only">{t('{n} unread', { n: th.unread })}</span>}
                </span>
              </span>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}

function Friends({ data, refresh }: { data?: { friends: Friend[]; requests: Friend[] }; refresh: () => void }) {
  const [busy, setBusy] = useState<string>();

  async function respond(id: string, accept: boolean) {
    setBusy(id);
    const { error } = await supabase!.rpc('respond_friend_request', { p_user: id, p_accept: accept });
    setBusy(undefined);
    if (error) toast(problem(error), 'error');
    else toast(accept ? t('You’re now friends') : t('Request ignored'));
    refresh();
  }

  if (!data) return <div className="grid gap-3">{[0, 1].map((i) => <Skeleton key={i} className="h-16" />)}</div>;
  return (
    <div className="grid gap-6">
      {data.requests.length > 0 && (
        <section aria-labelledby="requests" className="grid gap-2">
          <h2 id="requests" className="text-title3">{t('Friend requests')}</h2>
          {data.requests.map((r) => (
            <div key={r.id} className="sticker flex flex-wrap items-center gap-3 bg-butter p-3 text-on-accent">
              <Link to={`/players/${r.id}/`} className="flex min-w-0 flex-1 items-center gap-3">
                <Avatar id={r.id} name={r.nickname} size={40} />
                <span className="truncate font-bold">{r.nickname}</span>
              </Link>
              <Button className="button-sm" busy={busy === r.id} onClick={() => respond(r.id, true)}>{t('Accept')}</Button>
              <Button className="button-sm" variant="quiet" disabled={busy === r.id} onClick={() => respond(r.id, false)}>{t('Ignore')}</Button>
            </div>
          ))}
        </section>
      )}
      <section aria-labelledby="friends" className="grid gap-2">
        <h2 id="friends" className="text-title3">{t('Friends')}</h2>
        {data.friends.length === 0 ? (
          <Empty icon="handshake" tint="mint" title={t('No friends yet')}>
            {t('After a game, pick “I’d play with them again”. If they pick you too, you become friends.')}
          </Empty>
        ) : (
          <ul className="sticker grid p-2">
            {data.friends.map((f, i) => (
              <li key={f.id}>
                {i > 0 && <div className="mx-2"><Divider /></div>}
                <div className="flex items-center gap-3 p-2.5">
                  <Link to={`/players/${f.id}/`} className="press flex min-w-0 flex-1 items-center gap-3">
                    <Avatar id={f.id} name={f.nickname} size={44} />
                    <span className="grid min-w-0 justify-items-start gap-0.5">
                      <span className="max-w-full truncate font-bold">{f.nickname}</span>
                      <LevelBadge rating={f.rating} named={false} compact />
                    </span>
                  </Link>
                  <Link to={`/messages/dm/${f.id}/`} className="button button-sm button-quiet">{t('Message')}</Link>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
      <FindPlayers onAdded={refresh} />
      <Regulars />
    </div>
  );
}

/** 打开别人的加球友链接：找到人就去他的资料页（在那里加球友） */
export function AddByLink({ code }: { code: string }) {
  const [missing, setMissing] = useState(false);
  useEffect(() => {
    supabase!.rpc('open_friend_link', { p_code: code }).then(({ data, error }) => {
      if (error) toast(problem(error), 'error');
      if (data) navigate(`/players/${data}/`, true);
      else setMissing(true);
    });
  }, [code]);
  if (!missing) return <Skeleton className="h-40" />;
  return <Empty icon="userPlus" title={t('This friend link no longer works')} action={{ label: t('Find players'), to: '/messages/?tab=friends' }}>
    {t('Ask your friend for a new link.')}
  </Empty>;
}

/** 按昵称搜球友：只搜得到允许被搜到的人；停止输入 300 毫秒后再搜（服务器限速） */
function FindPlayers({ onAdded }: { onAdded: () => void }) {
  const [query, setQuery] = useState('');
  const [found, setFound] = useState<FoundPlayer[]>();
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState<string>();

  useEffect(() => {
    const q = query.trim();
    setError(undefined);
    if (q.length < 2) return setFound(undefined);
    let current = true;
    const timer = setTimeout(async () => {
      const { data, error } = await supabase!.rpc('find_players', { p_query: q });
      if (!current) return;
      if (error) setError(problem(error));
      else setFound(data as FoundPlayer[]);
    }, 300);
    return () => {
      current = false;
      clearTimeout(timer);
    };
  }, [query]);

  async function add(id: string) {
    setBusy(id);
    const { data, error } = await supabase!.rpc('send_friend_request', { p_user: id });
    setBusy(undefined);
    if (error) return toast(problem(error), 'error');
    toast(data === 'friends' ? t('You’re now friends') : t('Friend request sent'));
    setFound((list) => list?.map((p) => (p.id === id ? { ...p, relationship: data === 'friends' ? 'friend' : 'requested' } : p)));
    onAdded();
  }

  return (
    <section aria-labelledby="find" className="grid gap-2">
      <h2 id="find" className="text-title3">{t('Find players')}</h2>
      <Field label={t('Nickname')} hint={t('Add #1234 to find one person. Only players who allow it show up.')} error={error}>
        {(props) => (
          <input {...props} type="search" value={query} maxLength={17} autoComplete="off" spellCheck={false}
                 onChange={(e) => setQuery(e.target.value)} className="field" />
        )}
      </Field>
      <Link to="/me/#friend-link" className="text-footnote font-bold underline underline-offset-2">{t('Share my friend link')}</Link>
      {found?.length === 0 && <p className="text-footnote text-ink-secondary">{t('No one by that name. They may have turned off search.')}</p>}
      {found?.map((p) => (
        <div key={p.id} className="sticker flex items-center gap-3 p-3">
          <Link to={`/players/${p.id}/`} className="press flex min-w-0 flex-1 items-center gap-3">
            <Avatar id={p.id} name={p.nickname} size={40} />
            <span className="min-w-0">
              <span className="block truncate font-bold">{p.nickname}<span className="font-normal text-ink-tertiary">{tagText(p.tag)}</span></span>
              <span className="flex items-center gap-1.5 text-caption text-ink-secondary">
                <LevelBadge rating={p.rating} named={false} compact />
                {p.mutual_friends > 0 && t('{n} friend in common|{n} friends in common', { n: p.mutual_friends })}
              </span>
            </span>
          </Link>
          {p.relationship === 'friend' ? <span className="chip bg-mint">{t('Friend')}</span>
            : p.relationship === 'requested' ? <span className="chip bg-surface-muted text-ink">{t('Requested')}</span>
            : p.relationship === 'incoming' ? <span className="chip bg-butter">{t('Wants to be friends')}</span>
            : <Button className="button-sm" busy={busy === p.id} disabled={Boolean(busy)} onClick={() => add(p.id)}>{t('Add friend')}</Button>}
        </div>
      ))}
    </section>
  );
}

/** 同馆常客：收藏了同一家球馆、自己愿意被看到的人 */
function Regulars() {
  const { data: regulars } = useLive<Regular[]>('venue_regulars', { every: 300_000 });
  if (!regulars?.length) return null;
  return (
    <section aria-labelledby="regulars" className="grid gap-2">
      <div>
        <h2 id="regulars" className="text-title3">{t('Regulars at your courts')}</h2>
        <p className="text-footnote text-ink-secondary">{t('Players who starred the same courts and chose to show up here.')}</p>
      </div>
      <ul className="sticker grid p-2">
        {regulars.map((r, i) => (
          <li key={r.id}>
            {i > 0 && <div className="mx-2"><Divider /></div>}
            <Link to={`/players/${r.id}/`} className="press flex items-center gap-3 rounded-[14px] p-2.5 hover:bg-surface-muted/70">
              <Avatar id={r.id} name={r.nickname} size={40} />
              <span className="min-w-0 flex-1">
                <span className="block truncate font-bold">{r.nickname}</span>
                <span className="block truncate text-footnote text-ink-secondary">{r.venue.name}</span>
              </span>
              <LevelBadge rating={r.rating} named={false} compact />
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}

function preview(thread: ThreadSummary) {
  if (thread.last) return thread.last.mine ? t('You: {message}', { message: thread.last.body }) : thread.last.body;
  if (thread.kind === 'game') return t('Game chat');
  if (thread.kind === 'group') return t('Group chat · {venue}', { venue: thread.venue ?? '' });
  return '';
}

// 见面前不需要转账、代付或验证码：非好友的消息里出现这些就提醒
const risky = /(\+?\d[\d\s().-]{8,}\d|we ?chat|weixin|whatsapp|telegram|venmo|zelle|cash ?app|paypal|gift ?card|verification code|deposit)/i;

/** 聊天（iOS 的 ChatView）：我的消息是柠檬绿气泡，别人的是白色 */
function Chat({ kind, id }: { kind: ThreadKind; id: string }) {
  const { data: thread, failed, refresh } = useLive<Thread>('open_thread', { args: { p_kind: kind, p_id: id }, every: 5_000 });
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [responding, setResponding] = useState(false);
  const log = useRef<HTMLDivElement>(null);
  const count = thread?.messages.length ?? 0;

  useEffect(() => {
    log.current?.scrollTo({ top: log.current.scrollHeight });
  }, [count]);

  const frame = (children: ReactNode) => (
    <section aria-label={t('Chat')} className="sticker flex h-[calc(100dvh-7rem)] flex-col overflow-hidden lg:sticky lg:top-24 lg:h-[calc(100dvh-8.5rem)]">
      {children}
    </section>
  );

  if (failed && !thread) {
    return (
      <Empty icon="lock" tint="peach" title={t('Chat not available')} action={{ label: t('Messages'), to: '/messages/' }}>
        {t('You can only see chats you’re part of.')}
      </Empty>
    );
  }
  if (!thread) return frame(<Skeleton className="m-4 flex-1" />);

  const other = thread.members.find((m) => !m.me);
  const names = Object.fromEntries(thread.members.map((m) => [m.id, m.nickname]));
  const warn = !thread.friend && thread.messages.some((m) => !m.mine && risky.test(m.body));
  const title = thread.game ? `${day(thread.game.starts_at, thread.game.tz)} · ${thread.game.venue}` : thread.group ? thread.group.name : other?.nickname ?? '';
  const subtitle = thread.game
    ? `${hours(thread.game.starts_at, thread.game.ends_at, thread.game.tz)} · ${thread.members.filter((m) => !m.me).map((m) => m.nickname).join(', ')}`
    : thread.group ? `${thread.group.venue} · ${t('{n} member|{n} members', { n: thread.members.length })}` : undefined;
  const titleLink = thread.game ? `/games/${id}/` : thread.group ? `/groups/${id}/` : `/players/${other?.id}/`;

  async function send(event?: SubmitEvent) {
    event?.preventDefault();
    if (!draft.trim() || busy) return;
    setBusy(true);
    const { error } = await supabase!.rpc('send_message', { p_kind: kind, p_id: id, p_body: draft });
    setBusy(false);
    if (error) return toast(problem(error), 'error');
    if (thread?.access === 'request') toast(t('Message request sent'));
    setDraft('');
    refresh();
  }

  /** 收到的消息请求：接受后可以继续聊；忽略的话对方不会知道 */
  async function respond(accept: boolean) {
    if (responding) return;
    setResponding(true);
    const { error } = await supabase!.rpc('respond_message_request', { p_user: id, p_accept: accept });
    setResponding(false);
    if (error) return toast(problem(error), 'error');
    if (!accept) return navigate('/messages/');
    refresh();
  }

  function onKey(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      send();
    }
  }

  return frame(
    <>
      <header className="flex items-center gap-3 border-b-2 border-stroke p-3">
        <span className="lg:hidden"><IconButton icon="chevronLeft" label={t('Back')} to="/messages/" /></span>
        {kind === 'dm' && other ? <Avatar id={other.id} name={other.nickname} size={40} /> : <IconTile icon={threadIcon[kind][0]} tint={threadIcon[kind][1]} />}
        <Link to={titleLink} className="min-w-0 flex-1 hover:underline">
          <h1 className="truncate text-headline">{title}</h1>
          {subtitle && <p className="truncate text-footnote text-ink-secondary">{subtitle}</p>}
        </Link>
      </header>

      <div ref={log} role="log" aria-live="polite" aria-label={t('Messages')} className="grid flex-1 content-start gap-3 overflow-y-auto bg-canvas/60 p-4">
        {warn && (
          <p role="note" className="tile flex gap-2 bg-peach p-3 text-footnote font-bold text-on-accent">
            <Icon name="shield" className="size-5" />
            {t('You never need to pay, send a deposit or share a verification code before playing. Split court fees at the court.')}
          </p>
        )}
        {thread.messages.length === 0 && <p className="py-10 text-center text-ink-secondary">{t('No messages yet.')}</p>}
        {thread.messages.map((m) => (
          <div key={m.id} className={`flex max-w-[85%] items-end gap-2 ${m.mine ? 'justify-self-end' : 'justify-self-start'}`}>
            {!m.mine && (
              <Link to={`/players/${m.sender}/`} aria-label={names[m.sender] ?? t('Player')} className="press shrink-0 rounded-full">
                <Avatar id={m.sender} name={names[m.sender] ?? '?'} size={28} />
              </Link>
            )}
            <div className={`grid gap-0.5 ${m.mine ? 'justify-items-end' : ''}`}>
              {!m.mine && kind !== 'dm' && <span className="px-1 text-caption text-ink-secondary">{names[m.sender] ?? t('Player')}</span>}
              <p className={`rounded-[18px] border-2 border-stroke px-3.5 py-2 break-words whitespace-pre-wrap ${m.mine ? 'rounded-br-[6px] bg-lime text-on-accent' : 'rounded-bl-[6px] bg-surface'}`}>
                {m.body}
              </p>
              <span className="px-1 text-[11px] text-ink-tertiary">{relative(m.created_at)}</span>
            </div>
          </div>
        ))}
      </div>

      {thread.request === 'incoming' && (
        <div className="grid gap-2 border-t-2 border-stroke bg-butter p-3 text-on-accent">
          <p className="font-bold">{t('{name} wants to chat', { name: other?.nickname ?? '' })}</p>
          <p className="text-footnote">{t('You’re in the same group. Accept or reply to keep chatting. If you ignore it, they won’t know.')}</p>
          <div className="flex gap-2">
            <Button className="button-sm" busy={responding} onClick={() => respond(true)}>{t('Accept')}</Button>
            <Button className="button-sm" variant="quiet" disabled={responding} onClick={() => respond(false)}>{t('Ignore')}</Button>
          </div>
        </div>
      )}

      {thread.access === 'request' && (
        <p className="border-t-2 border-stroke bg-surface-muted p-3 text-footnote text-ink-secondary">
          {t('You’re both in {group}. Send one message to start: text only, no links or contact details. You can keep chatting once they accept.', { group: thread.group_name ?? '' })}
        </p>
      )}

      {thread.access === 'open' || thread.access === 'request' ? (
        <form onSubmit={send} className="flex items-end gap-2 border-t-2 border-stroke bg-surface p-3">
          <label className="sr-only" htmlFor="draft">{t('Message')}</label>
          <textarea id="draft" rows={1} maxLength={1000} value={draft} onChange={(e) => setDraft(e.target.value)} onKeyDown={onKey}
                    placeholder={t('Write a message')} className="field max-h-32 min-h-11 flex-1 resize-none rounded-[22px] py-2.5" />
          <button type="submit" disabled={!draft.trim() || busy} aria-label={t('Send')}
                  className="grid size-11 shrink-0 place-items-center rounded-full border-2 border-stroke bg-lime text-on-accent transition-transform active:scale-92 disabled:bg-surface-muted disabled:text-ink-tertiary">
            <Icon name="send" className="size-5" />
          </button>
        </form>
      ) : (
        <p className="border-t-2 border-stroke bg-surface-muted p-3 text-center text-footnote font-bold text-ink-secondary" role="status">
          {thread.game ? t('This chat closed 48 hours after the game.')
            : thread.access === 'requested' ? t('Message request sent. You can keep chatting once they accept.')
            : t('You can only message friends.')}
        </p>
      )}
    </>,
  );
}

// MARK: 通知（顶栏的铃铛）

const updateIcons: Record<string, [IconName, Tint]> = {
  offer: ['bolt', 'lime'],
  offer_auto: ['bolt', 'lime'],
  matched: ['checkCircle', 'mint'],
  cancelled: ['xCircle', 'pink'],
  missed: ['warning', 'peach'],
  requeued: ['swap', 'sky'],
  expired: ['hourglass', 'muted'],
  review: ['star', 'pink'],
  friend: ['handshake', 'mint'],
  friend_request: ['userPlus', 'lavender'],
  message_request: ['chat', 'sky'],
  challenge: ['challenge', 'peach'],
  group: ['group', 'sky'],
  room: ['court', 'peach'],
  room_closed: ['court', 'muted'],
  room_promoted: ['court', 'lime'],
  room_removed: ['court', 'muted'],
  verification: ['verified', 'lime'],
  report: ['shield', 'butter'],
  nudge: ['bell', 'butter'],
};

export function Notifications() {
  const [updates, setUpdates] = useState<Update[]>();
  useEffect(() => {
    supabase!
      .from('notifications')
      .select('id, kind, title, body, link, created_at, read_at')
      .order('id', { ascending: false })
      .limit(50)
      .then(({ data }) => {
        setUpdates((data ?? []) as Update[]);
        // 显示过就算已读（这次打开仍保留未读的样式）
        if (data?.some((u) => !u.read_at)) supabase!.rpc('mark_notifications_read');
      });
  }, []);

  return (
    <div className="mx-auto grid max-w-2xl gap-5">
      <ScreenHeader title={t('Notifications')} back="/" />
      {!updates ? (
        <div className="grid gap-3">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-20" />)}</div>
      ) : !updates.length ? (
        <Empty icon="bell" tint="butter" title={t('Nothing new')}>{t('Matches, confirmations and friend requests show up here.')}</Empty>
      ) : (
        <ul className="sticker grid p-2">
          {updates.map((u, i) => {
            const [icon, tint] = updateIcons[u.kind] ?? ['bell', 'butter'];
            const body = (
              <>
                <IconTile icon={icon} tint={tint} />
                <span className="min-w-0 flex-1">
                  <span className="flex items-baseline gap-2">
                    <span className="min-w-0 flex-1 font-bold">{u.title}</span>
                    <span className="shrink-0 text-caption text-ink-tertiary">{relative(u.created_at)}</span>
                  </span>
                  <span className="block text-footnote text-ink-secondary">{u.body}</span>
                </span>
                {!u.read_at && <span className="size-2.5 shrink-0 rounded-full bg-danger-fill" aria-label={t('New')} />}
              </>
            );
            return (
              <li key={u.id}>
                {i > 0 && <div className="mx-2"><Divider /></div>}
                {u.link ? (
                  <Link to={u.link} className="press flex items-center gap-3 rounded-[14px] p-2.5 hover:bg-surface-muted/70">{body}</Link>
                ) : (
                  <div className="flex items-center gap-3 p-2.5">{body}</div>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
