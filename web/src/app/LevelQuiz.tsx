import { useEffect, useRef, useState } from 'react';
import { evaluate, questions, tier } from './assessment';
import { t } from './i18n';
import { problem, supabase, type Profile } from './supabase';
import { IconButton, Starburst } from './kit';
import { Button } from './ui';

/** 定级问卷：一屏一题，点选项直接进下一题；最后确认结果再保存 */
export function LevelQuiz({ onDone }: { onDone: (profile?: Profile) => void }) {
  const [answers, setAnswers] = useState<Record<string, number>>({});
  const [step, setStep] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const heading = useRef<HTMLHeadingElement>(null);
  const question = questions[step];
  const result = question ? undefined : evaluate(answers);

  // 换题后把焦点放到题目上，读屏和键盘用户从新题开始
  useEffect(() => heading.current?.focus(), [step]);

  function pick(index: number) {
    setAnswers({ ...answers, [question.id]: index });
    setStep(step + 1);
  }

  async function save() {
    setBusy(true);
    const { data, error } = await supabase!.rpc('save_assessment', { p_rating: result!.rating, p_answers: answers });
    setBusy(false);
    if (error) setError(problem(error));
    else onDone(data as Profile);
  }

  return (
    <div className="mx-auto grid max-w-2xl gap-6">
        <div className="flex items-center gap-3">
          {step > 0 && question ? (
            <IconButton icon="chevronLeft" label={t('Back')} onClick={() => setStep(step - 1)} />
          ) : (
            <span className="text-footnote font-bold text-ink-secondary">{t('Level quiz')}</span>
          )}
          <div
            role="progressbar"
            aria-label={t('Quiz progress')}
            aria-valuemin={0}
            aria-valuemax={questions.length}
            aria-valuenow={step}
            className="h-3.5 flex-1 overflow-hidden rounded-full border-2 border-stroke bg-surface-muted"
          >
            <div className="h-full bg-lime transition-[width] duration-[var(--dur-3)] ease-[var(--ease-out)]" style={{ width: `${Math.max(4, (step / questions.length) * 100)}%` }} />
          </div>
          <button onClick={() => onDone()} className="min-h-11 text-footnote font-bold text-ink-secondary hover:text-ink hover:underline">
            {result ? t('Not now') : t('Skip for now')}
          </button>
        </div>

        {question ? (
          <section key={question.id} className="animate-enter grid gap-6" aria-labelledby="question">
            <div>
              <p className="text-footnote font-bold text-ink-secondary tabular-nums">
                {t('Question {n} of {total}', { n: step + 1, total: questions.length })}
              </p>
              <h1 id="question" ref={heading} tabIndex={-1} className="mt-1 text-title outline-none lg:text-display">
                {t(question.title)}
              </h1>
              <p className="mt-2 text-subhead text-ink-secondary">{t(question.hint)}</p>
            </div>
            <ul className="grid gap-2.5">
              {question.options.map((option, index) => (
                <li key={option.text}>
                  <button
                    onClick={() => pick(index)}
                    aria-pressed={answers[question.id] === index}
                    className="sticker lift flex w-full items-center gap-3 p-3.5 text-left font-bold aria-pressed:bg-lime aria-pressed:text-on-accent"
                  >
                    <span aria-hidden="true" className="grid size-9 shrink-0 place-items-center rounded-full border-2 border-stroke bg-surface-muted text-footnote font-black text-ink">
                      {String.fromCharCode(65 + index)}
                    </span>
                    {t(option.text)}
                  </button>
                </li>
              ))}
            </ul>
            {step === 0 && <p className="text-footnote text-ink-secondary">{t('Skip it and you start at level 3. You can take the quiz later from Me.')}</p>}
          </section>
        ) : (
          result && (
            <section className="animate-enter grid gap-6" aria-labelledby="result">
              <div className="sticker grid justify-items-center gap-2 bg-lime p-6 text-center text-on-accent sm:p-8">
                <p className="kicker">{t('Your level')}</p>
                <h1 id="result" ref={heading} tabIndex={-1} className="outline-none">
                  <Starburst tint="butter" size={128}>{tier(result.rating).label}</Starburst>
                </h1>
                <p className="text-title2">{tier(result.rating).name}</p>
                <p className="max-w-md text-subhead font-semibold">{tier(result.rating).summary}</p>
              </div>
              <ul className="grid gap-2 text-subhead text-ink-secondary">
                {result.limitingGate && <li>{result.limitingGate}</li>}
                {result.needsCalibration && <li>{t('Your tournament experience ranks higher than your skill answers, so we’ve set your level by experience.')}</li>}
                {result.isReturning && <li>{t('Coming back? This is your level on current form.')}</li>}
                <li>{t('Players are matched within the level range they choose. You can retake the quiz after 90 days.')}</li>
              </ul>
              {error && <p role="alert" className="font-bold text-danger">{error}</p>}
              <div className="grid gap-3 sm:grid-cols-2">
                <Button className="button-lg" busy={busy} onClick={save}>{t('Save my level')}</Button>
                <Button className="button-lg" variant="quiet" onClick={() => { setAnswers({}); setStep(0); }}>{t('Start over')}</Button>
              </div>
            </section>
          )
        )}
    </div>
  );
}
