import { useEffect, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { Admin, VerificationPage } from './Verification';
import { Contact } from './Contact';
import { Challenges, GameDetail, Games } from './Games';
import { GroupPage } from './Group';
import { startLocale, t, useLocale } from './i18n';
import { Groups } from './Groups';
import { Home } from './Home';
import { type IconName } from './icons';
import { Empty, LargeTitle, type Tint } from './kit';
import { About, LevelGuide } from './Levels';
import { LevelQuiz } from './LevelQuiz';
import { Me, Settings } from './Me';
import { NewGroup } from './NewGroup';
import { NewRoom } from './NewRoom';
import { Messages, Notifications } from './Messages';
import { GenderPrompt, Onboarding } from './Onboarding';
import { Play } from './Play';
import { PlayerPage } from './Player';
import { syncPush } from './push';
import { Rankings } from './Rankings';
import { JoinRoom, RoomPage } from './Room';
import { Rooms } from './Rooms';
import { enableSpa, navigate, usePath } from './router';
import { Loading, Shell, signInFirst } from './Shell';
import { SignIn } from './SignIn';
import { supabase, useLive, type InboxCounts, type Profile, type ThreadKind } from './supabase';

enableSpa();

/** 旧地址（/app/…，邮件和通知里还有）→ 新地址 */
const modern = (path: string) => (path.startsWith('/app/') ? path.slice(4) : path).replace(/^\/level\//, '/level-quiz/');

export default function App() {
  const path = usePath();
  const [session, setSession] = useState<Session | null>();
  const [loaded, setProfile] = useState<Profile | null>();
  // 退出或注销的那一刻就不再用旧资料（加载新资料要等下一次渲染）
  const profile = session === null ? null : loaded;
  // 先加载界面语言再显示，避免先闪一下英文
  const [ready, setReady] = useState(false);
  const locale = useLocale();

  useEffect(() => {
    startLocale().finally(() => setReady(true));
    // 给搜索引擎和不开脚本的人看的静态内容：App 接管后删掉，页面里只留一个 h1
    document.getElementById('static-page')?.remove();
  }, []);

  useEffect(() => {
    if (modern(path) !== path) navigate(modern(path) + location.search + location.hash, true);
  }, [path]);

  useEffect(() => {
    if (!supabase) return setSession(null);
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next));
    return () => data.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session) return setProfile(undefined);
    supabase!.from('profiles').select().eq('id', session.user.id).maybeSingle().then(({ data }) => setProfile(data as Profile | null));
  }, [session?.user.id]);

  // 通知和邮件用你正在用的界面语言
  useEffect(() => {
    if (!ready || !profile || profile.locale === locale) return;
    supabase!.from('profiles').update({ locale }).eq('id', profile.id).select().single().then(({ data }) => data && setProfile(data as Profile));
  }, [ready, profile?.locale, locale]);

  // 登录完回到登录前想去的页面
  useEffect(() => {
    if (session && path === '/signin/') navigate(new URLSearchParams(location.search).get('next')?.match(/^\/[^/]/)?.input ?? '/', true);
  }, [session, path]);

  if (!ready || session === undefined || (session && profile === undefined)) return <Loading />;

  const guest = !session;
  const shell = (children: ReactNode, me: Profile | null = profile ?? null) => (
    <Frame path={path} me={me} guest={guest}>{children}</Frame>
  );

  if (session && !profile) {
    return shell(
      <Onboarding
        userId={session.user.id}
        onDone={(created) => {
          setProfile(created);
          navigate('/level-quiz/', true);
        }}
      />,
    );
  }
  if (profile && !profile.gender) return shell(<GenderPrompt profile={profile} onDone={setProfile} />);
  if (path.startsWith('/level-quiz/') && profile) {
    return shell(
      <LevelQuiz
        onDone={(saved) => {
          if (saved) setProfile(saved);
          navigate('/', true);
        }}
      />,
    );
  }
  if (path.startsWith('/signin/')) return shell(<SignIn />);

  // 不用登录也能看的页面
  if (path === '/') return shell(<Home profile={profile ?? null} />);
  if (path.startsWith('/levels/')) return shell(<LevelGuide profile={profile ?? null} />);
  if (path.startsWith('/about/')) return shell(<About />);
  if (path.startsWith('/contact/')) return shell(<Contact />);

  if (!profile) return shell(<SignInPage path={path} />);

  const id = (prefix: string) => path.match(new RegExp(`^/${prefix}/([0-9a-f-]{36})/`))?.[1];
  const game = id('games');
  const player = id('players');
  const group = id('groups');
  const room = id('rooms');
  const chat = path.match(/^\/messages\/(game|group|dm)\/([0-9a-f-]{36})\//);
  return shell(
    player ? <PlayerPage key={player} id={player} />
    : chat ? <Messages open={{ kind: chat[1] as ThreadKind, id: chat[2] }} />
    : group ? <GroupPage key={group} id={group} />
    : room ? <RoomPage key={room} id={room} gender={profile?.gender ?? null} />
    : game ? <GameDetail id={game} />
    : path.startsWith('/rooms/new/') ? <NewRoom profile={profile} />
    : path.startsWith('/rooms/') ? <Rooms />
    : path.startsWith('/join/') ? <JoinRoom />
    : path.startsWith('/groups/new/') ? <NewGroup profile={profile} />
    : path.startsWith('/groups/') ? <Groups />
    : path.startsWith('/rankings/') ? <Rankings />
    : path.startsWith('/challenges/') ? <Challenges />
    : path.startsWith('/games/') ? <Games />
    : path.startsWith('/play/') ? <Play profile={profile} />
    : path.startsWith('/messages/') ? <Messages />
    : path.startsWith('/notifications/') ? <Notifications />
    : path.startsWith('/admin/') ? <Admin />
    : path.startsWith('/verification/') ? <VerificationPage profile={profile} />
    : path.startsWith('/settings/') ? <Settings profile={profile} email={session!.user.email} onChange={setProfile} />
    : path.startsWith('/me/') ? <Me profile={profile} onChange={setProfile} />
    : <NotFound />,
  );
}

/** 外壳 + 未读数（只有登录了才查） */
function Frame({ path, me, guest, children }: { path: string; me: Profile | null; guest: boolean; children: ReactNode }) {
  return me ? <SignedInFrame path={path} me={me}>{children}</SignedInFrame> : <Shell path={path} me={null} guest={guest}>{children}</Shell>;
}

function SignedInFrame({ path, me, children }: { path: string; me: Profile; children: ReactNode }) {
  const { data: counts, refresh } = useLive<InboxCounts>('inbox_counts');
  // 换页时（比如刚看完消息）马上更新未读数
  useEffect(() => void refresh(), [path, refresh]);
  // 这台设备开过推送的，再报一次给服务器（换了账号登录时转给当前账号）
  useEffect(() => void syncPush(), [me.id]);
  return <Shell path={path} me={me} guest={false} counts={counts}>{children}</Shell>;
}

const lockedPages: { match: RegExp; title: string; icon: IconName; tint: Tint; text: string }[] = [
  { match: /^\/games\//, title: 'Games', icon: 'games', tint: 'peach', text: 'Your upcoming games, results and reviews show up here.' },
  { match: /^\/messages\//, title: 'Messages', icon: 'chats', tint: 'sky', text: 'Chat with the players in your games, your groups and your friends.' },
  { match: /^\/me\//, title: 'Me', icon: 'me', tint: 'lavender', text: 'Your level, win rate, reliability and settings.' },
];

/** 没登录时打开要账号的页面：说明这里有什么，再给登录按钮 */
function SignInPage({ path }: { path: string }) {
  const page = lockedPages.find((p) => p.match.test(path));
  return (
    <div className="mx-auto grid max-w-2xl gap-6">
      {page && <LargeTitle title={t(page.title)} />}
      <Empty icon={page?.icon ?? 'lock'} tint={page?.tint ?? 'lime'} title={t('Sign in to continue')} action={{ label: t('Sign in'), to: signInFirst(path + location.search) }}>
        {page ? t(page.text) : t('You need a free account for this page.')} {t('It’s free and takes a minute.')}
      </Empty>
    </div>
  );
}

function NotFound() {
  return <Empty icon="question" tint="butter" title={t('Page not found')} action={{ label: t('Home'), to: '/' }}>{t('The link may be old or mistyped.')}</Empty>;
}
