import { useEffect, useRef, useState } from 'react';
import { questions } from './assessment';
import { t } from './i18n';
import { IconButton } from './kit';
import { savePending } from './quizStore';
import { navigate } from './router';

/**
 * 定级问卷：一屏一题，点选项直接进下一题；答完到结果页（/level-quiz/result/）。
 * 不用登录：答案先存在这个标签页里（sessionStorage），不传到服务器；登录的人在结果页保存，没登录的人注册后自动保存
 */
export function LevelQuiz({ signedIn, onSkip }: { signedIn: boolean; onSkip: () => void }) {
  const [answers, setAnswers] = useState<Record<string, number>>({});
  const [step, setStep] = useState(0);
  const heading = useRef<HTMLHeadingElement>(null);
  const question = questions[step];

  // 换题后把焦点放到题目上，读屏和键盘用户从新题开始
  useEffect(() => heading.current?.focus(), [step]);

  function pick(index: number) {
    const next = { ...answers, [question.id]: index };
    setAnswers(next);
    if (step + 1 < questions.length) return setStep(step + 1);
    savePending(next);
    navigate('/level-quiz/result/');
  }

  return (
    <div className="mx-auto grid max-w-2xl gap-6">
        <div className="flex items-center gap-3">
          {step > 0 ? (
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
          <button onClick={onSkip} className="min-h-11 text-footnote font-bold text-ink-secondary hover:text-ink hover:underline">
            {signedIn ? t('Skip for now') : t('Not now')}
          </button>
        </div>

        {question && (
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
            {step === 0 && (
              <p className="text-footnote text-ink-secondary">
                {signedIn ? t('Skip it and you start at level 3. You can take the quiz later from Me.') : t('No sign-up needed. Your answers stay on this device.')}
              </p>
            )}
          </section>
        )}
    </div>
  );
}
