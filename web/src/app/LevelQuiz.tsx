import { useEffect, useRef, useState } from 'react';
import { evaluate, questions, tier } from './assessment';
import { t } from './i18n';
import { problem, supabase, type Profile } from './supabase';
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
    <div className="min-h-dvh bg-canvas">
      <div className="page grid max-w-2xl gap-8 py-6 sm:py-10">
        <div className="flex items-center justify-between gap-4">
          <p className="eyebrow">{t('Level quiz')}</p>
          <button onClick={() => onDone()} className="link text-sm">
            {result ? t('Not now') : t('Skip for now')}
          </button>
        </div>
        <div
          role="progressbar"
          aria-label={t('Quiz progress')}
          aria-valuemin={0}
          aria-valuemax={questions.length}
          aria-valuenow={step}
          className="h-3 overflow-hidden rounded-full border-2 border-stroke bg-surface"
        >
          <div className="h-full bg-lime transition-[width] duration-[var(--dur-3)] ease-[var(--ease-out)]" style={{ width: `${(step / questions.length) * 100}%` }} />
        </div>

        {question ? (
          <section key={question.id} className="animate-enter grid gap-6" aria-labelledby="question">
            <div>
              <p className="text-sm font-extrabold text-ink-tertiary tabular-nums">
                {t('{n} of {total}', { n: step + 1, total: questions.length })}
              </p>
              <h1 id="question" ref={heading} tabIndex={-1} className="display mt-2 text-[clamp(2.25rem,7vw,3.5rem)] outline-none">
                {t(question.title)}
              </h1>
              <p className="mt-3 text-lg text-ink-secondary">{t(question.hint)}</p>
            </div>
            <ul className="grid gap-3">
              {question.options.map((option, index) => (
                <li key={option.text}>
                  <button
                    onClick={() => pick(index)}
                    aria-pressed={answers[question.id] === index}
                    className="sticker lift block w-full p-4 text-left font-bold aria-pressed:bg-butter aria-pressed:text-on-accent"
                  >
                    {t(option.text)}
                  </button>
                </li>
              ))}
            </ul>
            {step > 0 && (
              <button onClick={() => setStep(step - 1)} className="link justify-self-start">
                {t('Back')}
              </button>
            )}
            {step === 0 && <p className="text-sm text-ink-tertiary">{t('Skip it and you start at level 3. You can take the quiz later from Me.')}</p>}
          </section>
        ) : (
          result && (
            <section className="animate-enter grid gap-6" aria-labelledby="result">
              <div className="sticker grid justify-items-start gap-2 bg-lime p-6 text-on-accent sm:p-8">
                <p className="eyebrow text-on-accent!">{t('Your level')}</p>
                <h1 id="result" ref={heading} tabIndex={-1} className="display text-8xl outline-none">
                  {tier(result.rating).label}
                </h1>
                <p className="text-xl font-black">{tier(result.rating).name}</p>
                <p className="font-semibold">{tier(result.rating).summary}</p>
              </div>
              <ul className="grid gap-2 text-ink-secondary">
                {result.limitingGate && <li>{result.limitingGate}</li>}
                {result.needsCalibration && <li>{t('Your tournament experience ranks higher than your skill answers, so we’ve set your level by experience.')}</li>}
                {result.isReturning && <li>{t('Coming back? This is your level on current form.')}</li>}
                <li>{t('Players are matched within the level range they choose. You can retake the quiz after 90 days.')}</li>
              </ul>
              {error && <p role="alert" className="font-bold text-danger">{error}</p>}
              <div className="flex flex-wrap gap-3">
                <Button busy={busy} onClick={save}>{t('Save my level')}</Button>
                <Button variant="quiet" onClick={() => { setAnswers({}); setStep(0); }}>{t('Start over')}</Button>
              </div>
            </section>
          )
        )}
      </div>
    </div>
  );
}
