import { useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { ComingSoon } from './ComingSoon';
import { Courts } from './Courts';
import { Me } from './Me';
import { Onboarding } from './Onboarding';
import { navigate, usePath } from './router';
import { Shell } from './Shell';
import { SignIn } from './SignIn';
import { supabase, type Profile } from './supabase';

export default function App() {
  const path = usePath();
  const [session, setSession] = useState<Session | null>();
  const [profile, setProfile] = useState<Profile | null>();

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
    if (path === '/app/' || path === '/app') navigate('/app/courts/', true);
  }, [path]);

  if (!supabase) return <Message text="The web app isn’t connected to a server yet." />;
  if (session === undefined || (session && profile === undefined)) return <Message text="Loading…" />;
  if (!session) return <SignIn />;
  if (!profile) return <Onboarding userId={session.user.id} onDone={setProfile} />;

  return (
    <Shell path={path}>
      {path.startsWith('/app/me/') ? (
        <Me profile={profile} email={session.user.email} onChange={setProfile} />
      ) : path.startsWith('/app/play/') ? (
        <ComingSoon title="Find partners" body="Tell Badie when you’re free and which courts you can reach, and get matched with players at your level." />
      ) : path.startsWith('/app/games/') ? (
        <ComingSoon title="My games" body="Upcoming games, check-in, splitting the court fee and confirming results." />
      ) : path.startsWith('/app/messages/') ? (
        <ComingSoon title="Messages" body="Chat with friends and the players in your games and groups." />
      ) : (
        <Courts userId={session.user.id} />
      )}
    </Shell>
  );
}

function Message({ text }: { text: string }) {
  return <p className="grid min-h-screen place-items-center font-bold text-ink-secondary">{text}</p>;
}
