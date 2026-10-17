import { useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { Courts } from './Courts';
import { GameDetail, Games } from './Games';
import { GroupPage } from './Group';
import { detect, setLocale, t, useLocale } from './i18n';
import { Groups } from './Groups';
import { LevelQuiz } from './LevelQuiz';
import { Me } from './Me';
import { NewGroup } from './NewGroup';
import { Chat, Messages } from './Messages';
import { Onboarding } from './Onboarding';
import { Play } from './Play';
import { PlayerPage } from './Player';
import { Rankings } from './Rankings';
import { navigate, usePath } from './router';
import { Shell } from './Shell';
import { SignIn } from './SignIn';
import { supabase, type Profile, type ThreadKind } from './supabase';

export default function App() {
  const path = usePath();
  const [session, setSession] = useState<Session | null>();
  const [profile, setProfile] = useState<Profile | null>();
  // 先加载界面语言再显示，避免先闪一下英文
  const [ready, setReady] = useState(false);
  useLocale();

  useEffect(() => {
    setLocale(detect()).finally(() => setReady(true));
  }, []);

  useEffect(() => {
    if (!supabase) return;
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next));
    return () => data.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session) return setProfile(session === null ? null : undefined);
    supabase!.from('profiles').select().eq('id', session.user.id).maybeSingle().then(({ data }) => setProfile(data as Profile | null));
  }, [session?.user.id]);

  useEffect(() => {
    if (path === '/app/' || path === '/app') navigate('/app/play/', true);
  }, [path]);

  if (!ready) return <Message busy />;
  if (!supabase) return <Message text={t('The web app isn’t connected to a server yet.')} />;
  if (session === undefined || (session && profile === undefined)) return <Message busy text={t('Loading…')} />;
  if (!session) return <SignIn />;
  if (!profile) {
    return (
      <Onboarding
        userId={session.user.id}
        onDone={(created) => {
          setProfile(created);
          navigate('/app/level/', true);
        }}
      />
    );
  }
  if (path.startsWith('/app/level/')) {
    return (
      <LevelQuiz
        onDone={(saved) => {
          if (saved) setProfile(saved);
          navigate('/app/play/', true);
        }}
      />
    );
  }

  const id = (prefix: string) => path.match(new RegExp(`^/app/${prefix}/([0-9a-f-]{36})/`))?.[1];
  const game = id('games');
  const player = id('players');
  const group = id('groups');
  const chat = path.match(/^\/app\/messages\/(game|group|dm)\/([0-9a-f-]{36})\//);
  return (
    <Shell path={path}>
      {player ? (
        <PlayerPage key={player} id={player} />
      ) : chat ? (
        <Chat key={chat[2]} kind={chat[1] as ThreadKind} id={chat[2]} />
      ) : group ? (
        <GroupPage key={group} id={group} />
      ) : path.startsWith('/app/groups/new/') ? (
        <NewGroup profile={profile} />
      ) : path.startsWith('/app/groups/') ? (
        <Groups />
      ) : path.startsWith('/app/rankings/') ? (
        <Rankings />
      ) : path.startsWith('/app/messages/') ? (
        <Messages />
      ) : path.startsWith('/app/me/') ? (
        <Me profile={profile} email={session.user.email} onChange={setProfile} />
      ) : path.startsWith('/app/play/') ? (
        <Play profile={profile} />
      ) : game ? (
        <GameDetail id={game} />
      ) : path.startsWith('/app/games/') ? (
        <Games />
      ) : (
        <Courts userId={session.user.id} />
      )}
    </Shell>
  );
}

function Message({ text, busy }: { text?: string; busy?: boolean }) {
  return (
    <p role="status" className="grid min-h-dvh place-items-center bg-canvas font-bold text-ink-secondary">
      <span className="flex items-center gap-3">
        {busy && <span aria-hidden="true" className="size-5 animate-spin rounded-full border-[3px] border-current border-t-transparent" />}
        {text}
      </span>
    </p>
  );
}
