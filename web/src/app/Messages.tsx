import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode, type SubmitEvent } from 'react';
import { tier } from './assessment';
import { Link } from './router';
import { problem, supabase, useLive, type Friend, type Thread, type ThreadKind, type ThreadSummary, type Update } from './supabase';
import { day, hours, relative } from './time';
import { Button, EmptyState, PageHeader, Skeleton, toast } from './ui';

const tabs = [['chats', 'Chats'], ['updates', 'Updates'], ['friends', 'Friends']] as const;
type Tab = (typeof tabs)[number][0];

export function Messages() {
  const initial = new URLSearchParams(location.search).get('tab');
  const [tab, setTab] = useState<Tab>(tabs.some(([t]) => t === initial) ? (initial as Tab) : 'chats');
  const pick = (next: Tab) => {
    setTab(next);
    history.replaceState(null, '', `?tab=${next}`);
  };

  return (
    <div className="max-w-3xl">
      <PageHeader eyebrow="Messages" title="Messages" />
      <div role="tablist" aria-label="Messages" className="mb-6 flex gap-2">
        {tabs.map(([value, label]) => (
          <button key={value} role="tab" id={`tab-${value}`} aria-selected={tab === value} aria-controls="panel" onClick={() => pick(value)}
                  className="toggle aria-selected:bg-butter aria-selected:text-on-accent">
            {label}
          </button>
        ))}
      </div>
      <div id="panel" role="tabpanel" aria-labelledby={`tab-${tab}`} key={tab} className="animate-enter">
        {tab === 'chats' ? <Chats /> : tab === 'updates' ? <Updates /> : <Friends />}
      </div>
    </div>
  );
}

function Chats() {
  const { data: threads } = useLive<ThreadSummary[]>('my_threads', { every: 15_000 });
  if (!threads) return <List>{[0, 1, 2].map((i) => <Skeleton key={i} className="h-20" />)}</List>;
  if (!threads.length) {
    return <EmptyState title="No chats yet">Each confirmed game gets a group chat. Friends can message each other anytime.</EmptyState>;
  }
  return (
    <List>
      {threads.map((t) => (
        <Link key={`${t.kind}-${t.id}`} to={`/app/messages/${t.kind}/${t.id}/`} className="sticker lift flex items-center gap-4 p-4">
          <span className="min-w-0 flex-1">
            <span className="block truncate font-black">
              {t.kind === 'game' ? `${day(t.starts_at!, t.tz)} · ${t.venue}` : t.name}
            </span>
            <span className={`block truncate text-sm ${t.unread ? 'font-bold text-ink' : 'text-ink-secondary'}`}>
              {t.last ? `${t.last.mine ? 'You: ' : ''}${t.last.body}` : t.kind === 'game' ? 'Game chat · say hi to your partners' : t.kind === 'group' ? `Group chat · ${t.venue}` : ''}
            </span>
          </span>
          <span className="grid shrink-0 justify-items-end gap-1">
            {t.last && <span className="text-xs font-bold text-ink-tertiary">{relative(t.last.created_at)}</span>}
            {t.unread > 0 && <span className="chip bg-lime" aria-label={`${t.unread} unread`}>{t.unread}</span>}
          </span>
        </Link>
      ))}
    </List>
  );
}

function Updates() {
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
  if (!updates) return <List>{[0, 1, 2].map((i) => <Skeleton key={i} className="h-20" />)}</List>;
  if (!updates.length) return <EmptyState title="Nothing new">Matches, confirmations and friend requests show up here.</EmptyState>;
  return (
    <List>
      {updates.map((u) => {
        const content = (
          <>
            <span className="flex items-baseline justify-between gap-3">
              <span className="font-black">{u.title}</span>
              <span className="shrink-0 text-xs font-bold text-ink-tertiary">{relative(u.created_at)}</span>
            </span>
            <span className="mt-1 block text-ink-secondary">{u.body}</span>
          </>
        );
        const tone = u.read_at ? 'bg-surface' : 'bg-butter/40';
        return u.link ? (
          <Link key={u.id} to={u.link} className={`sticker lift block p-4 ${tone}`}>{content}</Link>
        ) : (
          <div key={u.id} className={`tile p-4 ${tone}`}>{content}</div>
        );
      })}
    </List>
  );
}

function Friends() {
  const { data, refresh } = useLive<{ friends: Friend[]; requests: Friend[] }>('my_friends', { every: 60_000 });
  const [busy, setBusy] = useState<string>();

  async function respond(id: string, accept: boolean) {
    setBusy(id);
    const { error } = await supabase!.rpc('respond_friend_request', { p_user: id, p_accept: accept });
    setBusy(undefined);
    if (error) toast(problem(error), 'error');
    else toast(accept ? 'You’re now friends' : 'Request ignored');
    refresh();
  }

  if (!data) return <List>{[0, 1].map((i) => <Skeleton key={i} className="h-16" />)}</List>;
  return (
    <div className="grid gap-8">
      {data.requests.length > 0 && (
        <section aria-labelledby="requests" className="grid gap-3">
          <h2 id="requests" className="eyebrow">Friend requests</h2>
          {data.requests.map((r) => (
            <div key={r.id} className="tile flex flex-wrap items-center gap-3 bg-surface p-4">
              <Link to={`/app/players/${r.id}/`} className="link min-w-0 flex-1 truncate">{r.nickname}</Link>
              <Button busy={busy === r.id} onClick={() => respond(r.id, true)}>Accept</Button>
              <Button variant="quiet" disabled={busy === r.id} onClick={() => respond(r.id, false)}>Ignore</Button>
            </div>
          ))}
        </section>
      )}
      <section aria-labelledby="friends" className="grid gap-3">
        <h2 id="friends" className="eyebrow">Friends</h2>
        {data.friends.length === 0 ? (
          <EmptyState title="No friends yet">After a game, pick “I’d play with them again”. If they pick you too, you become friends.</EmptyState>
        ) : (
          data.friends.map((f) => (
            <div key={f.id} className="tile flex items-center gap-3 bg-surface p-4">
              <Link to={`/app/players/${f.id}/`} className="min-w-0 flex-1">
                <span className="block truncate font-black">{f.nickname}</span>
                <span className="text-sm font-bold text-ink-tertiary">Level {tier(f.rating).label}</span>
              </Link>
              <Link to={`/app/messages/dm/${f.id}/`} className="button button-quiet">Message</Link>
            </div>
          ))
        )}
      </section>
    </div>
  );
}

const List = ({ children }: { children: ReactNode }) => <div className="grid gap-3">{children}</div>;

// 见面前不需要转账、代付或验证码：非好友的消息里出现这些就提醒
const risky = /(\+?\d[\d\s().-]{8,}\d|we ?chat|weixin|whatsapp|telegram|venmo|zelle|cash ?app|paypal|gift ?card|verification code|deposit)/i;

export function Chat({ kind, id }: { kind: ThreadKind; id: string }) {
  const { data: thread, failed, refresh } = useLive<Thread>('open_thread', { args: { p_kind: kind, p_id: id }, every: 5_000 });
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const end = useRef<HTMLDivElement>(null);
  const count = thread?.messages.length ?? 0;

  useEffect(() => end.current?.scrollIntoView({ block: 'end' }), [count]);

  if (failed && !thread) {
    return <EmptyState title="Chat not available" action={<Link to="/app/messages/" className="button">Messages</Link>}>You can only see chats you’re part of.</EmptyState>;
  }
  if (!thread) return <Skeleton className="h-96 max-w-3xl" />;

  const other = thread.members.find((m) => !m.me);
  const names = Object.fromEntries(thread.members.map((m) => [m.id, m.nickname]));
  const warn = !thread.friend && thread.messages.some((m) => !m.mine && risky.test(m.body));

  async function send(event?: SubmitEvent) {
    event?.preventDefault();
    if (!draft.trim() || busy) return;
    setBusy(true);
    const { error } = await supabase!.rpc('send_message', { p_kind: kind, p_id: id, p_body: draft });
    setBusy(false);
    if (error) return toast(problem(error), 'error');
    setDraft('');
    refresh();
  }

  function onKey(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
      event.preventDefault();
      send();
    }
  }

  return (
    <div className="grid max-w-3xl gap-4">
      <div>
        <Link to="/app/messages/" className="link text-sm">Messages</Link>
        {thread.game ? (
          <>
            <h1 className="mt-4 text-2xl font-black">{day(thread.game.starts_at, thread.game.tz)} · {hours(thread.game.starts_at, thread.game.ends_at, thread.game.tz)}</h1>
            <p className="text-ink-secondary">
              {thread.game.venue} ·{' '}
              {thread.members.filter((m) => !m.me).map((m, i) => (
                <span key={m.id}>{i > 0 && ', '}<Link to={`/app/players/${m.id}/`} className="link">{m.nickname}</Link></span>
              ))}
            </p>
          </>
        ) : thread.group ? (
          <>
            <h1 className="mt-4 text-2xl font-black"><Link to={`/app/groups/${id}/`} className="hover:underline">{thread.group.name}</Link></h1>
            <p className="text-ink-secondary">{thread.group.venue} · {thread.members.length} members</p>
          </>
        ) : (
          <h1 className="mt-4 text-2xl font-black">
            <Link to={`/app/players/${other?.id}/`} className="hover:underline">{other?.nickname}</Link>
          </h1>
        )}
      </div>

      {warn && (
        <p role="note" className="tile bg-peach p-4 font-bold text-on-accent">
          You never need to pay, send a deposit or share a verification code before playing. Split court fees at the court.
        </p>
      )}

      <div role="log" aria-live="polite" aria-label="Messages" className="tile grid max-h-[60dvh] min-h-64 content-start gap-3 overflow-y-auto bg-surface p-4">
        {thread.messages.length === 0 && <p className="text-center text-ink-tertiary">No messages yet. Say hi!</p>}
        {thread.messages.map((m) => (
          <div key={m.id} className={`grid max-w-[80%] gap-1 ${m.mine ? 'justify-self-end text-right' : 'justify-self-start'}`}>
            {!m.mine && !thread.friend && <span className="text-xs font-extrabold text-ink-secondary">{names[m.sender] ?? 'Player'}</span>}
            <p className={`rounded-[var(--r-control)] border-2 border-stroke px-3 py-2 text-left break-words whitespace-pre-wrap ${m.mine ? 'bg-lime text-on-accent' : 'bg-surface-muted'}`}>
              {m.body}
            </p>
            <span className="text-xs text-ink-tertiary">{relative(m.created_at)}</span>
          </div>
        ))}
        <div ref={end} />
      </div>

      {thread.access === 'open' ? (
        <form onSubmit={send} className="flex items-end gap-2">
          <label className="sr-only" htmlFor="draft">Message</label>
          <textarea id="draft" rows={2} maxLength={1000} value={draft} onChange={(e) => setDraft(e.target.value)} onKeyDown={onKey}
                    placeholder="Write a message" className="field min-h-12 flex-1 resize-none" />
          <Button busy={busy} disabled={!draft.trim()}>Send</Button>
        </form>
      ) : (
        <p className="text-ink-secondary" role="status">
          {thread.game ? 'This chat closed 48 hours after the game.' : 'You can only message friends.'}
        </p>
      )}
    </div>
  );
}
