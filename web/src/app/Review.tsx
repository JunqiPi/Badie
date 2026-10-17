import { useState, type SubmitEvent } from 'react';
import { tier } from './assessment';
import { t } from './i18n';
import { tagLabels } from './Player';
import { problem, supabase, type Game, type Player } from './supabase';
import { moment } from './time';
import { Button, toast } from './ui';

const attendance = [['on_time', 'On time'], ['late', 'Late'], ['no_show', 'Didn’t show']] as const;
const levels = [['lower', 'Lower'], ['accurate', 'About right'], ['higher', 'Higher']] as const;
const issues = [
  ['unsafe_play', 'Unsafe play'],
  ['rude', 'Unfriendly words'],
  ['hogging', 'Didn’t share the court'],
  ['unpaid', 'Didn’t settle the court fee'],
] as const;

/** 赛后评价：结束后 48 小时内，每位球友一次 */
export function Reviews({ game, onDone }: { game: Game; onDone: () => void }) {
  const pending = game.players.filter((p) => !p.me && !p.reviewed);
  if (!pending.length) return null;
  return (
    <section aria-labelledby="reviews" className="tile grid gap-5 bg-surface p-5 sm:p-6">
      <div>
        <h2 id="reviews" className="text-xl font-black">{t('Rate your partners')}</h2>
        <p className="mt-1 text-ink-secondary">
          {t('Private: nobody sees individual answers or scores. Open until {time}.', { time: moment(game.review_until, game.venue.tz) })}
        </p>
      </div>
      {pending.map((p) => <ReviewForm key={p.id} game={game} player={p} onDone={onDone} />)}
    </section>
  );
}

function ReviewForm({ game, player, onDone }: { game: Game; player: Player; onDone: () => void }) {
  const [show, setShow] = useState<string>();
  const [level, setLevel] = useState<string>();
  const [tags, setTags] = useState<string[]>([]);
  const [flags, setFlags] = useState<string[]>([]);
  const [again, setAgain] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const toggle = (list: string[], value: string) => (list.includes(value) ? list.filter((v) => v !== value) : [...list, value]);

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!show || !level) return setError(t('Answer the first two questions.'));
    setBusy(true);
    const { error } = await supabase!.rpc('review_player', {
      p_game: game.id, p_user: player.id, p_attendance: show, p_level: level, p_tags: tags, p_issues: flags, p_play_again: again,
    });
    setBusy(false);
    if (error) return setError(problem(error));
    toast(t('Thanks! Review for {name} sent.', { name: player.nickname }));
    onDone();
  }

  const label = tier(player.rating).label;
  return (
    <form onSubmit={submit} noValidate aria-label={t('Review {name}', { name: player.nickname })} className="grid gap-4 border-t-2 border-stroke/15 pt-5 first-of-type:border-0 first-of-type:pt-0">
      <p className="text-lg font-black">{player.nickname}</p>

      <Choice legend={t('Did they show up on time?')} options={attendance} value={show} onChange={setShow} />
      <Choice legend={t('Their level compared with level {level}', { level: label })} options={levels} value={level} onChange={setLevel} />

      <fieldset>
        <legend className="mb-2 font-extrabold">{t('What stood out?')} <span className="font-semibold text-ink-tertiary">{t('(optional)')}</span></legend>
        <div className="flex flex-wrap gap-2">
          {Object.entries(tagLabels).map(([value, text]) => (
            <button type="button" key={value} onClick={() => setTags(toggle(tags, value))} aria-pressed={tags.includes(value)} className="toggle">{t(text)}</button>
          ))}
        </div>
      </fieldset>

      <label className="flex items-start gap-3">
        <input type="checkbox" checked={again} onChange={(e) => setAgain(e.target.checked)} className="mt-1 size-5 accent-[var(--color-lime)]" />
        <span>
          <span className="block font-extrabold">{t('I’d play with {name} again', { name: player.nickname })}</span>
          <span className="block text-sm text-ink-tertiary">{t('If you both pick this, you become friends. Otherwise nobody is told.')}</span>
        </span>
      </label>

      <details className="group">
        <summary className="link cursor-pointer text-sm">{t('Something to flag privately')}</summary>
        <div className="mt-3 grid gap-2">
          <p className="text-sm text-ink-tertiary">{t('Never shown to anyone. If several players mention the same thing, we send them a private tip without saying who.')}</p>
          <div className="flex flex-wrap gap-2">
            {issues.map(([value, text]) => (
              <button type="button" key={value} onClick={() => setFlags(toggle(flags, value))} aria-pressed={flags.includes(value)} className="toggle">{t(text)}</button>
            ))}
          </div>
        </div>
      </details>

      {error && <p role="alert" className="font-bold text-danger">{error}</p>}
      <Button busy={busy} className="justify-self-start">{t('Send review')}</Button>
    </form>
  );
}

function Choice({ legend, options, value, onChange }: {
  legend: string;
  options: readonly (readonly [string, string])[];
  value?: string;
  onChange: (value: string) => void;
}) {
  return (
    <fieldset>
      <legend className="mb-2 font-extrabold">{legend}</legend>
      <div className="flex flex-wrap gap-2" role="radiogroup">
        {options.map(([v, text]) => (
          <button type="button" role="radio" key={v} onClick={() => onChange(v)} aria-checked={value === v} className="toggle">{t(text)}</button>
        ))}
      </div>
    </fieldset>
  );
}
