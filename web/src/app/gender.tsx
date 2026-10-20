import { t } from './i18n';
import type { Mode } from './supabase';

export type Gender = 'male' | 'female';

/** 男女的等级分开算，男女同场时女子等级按低 1.5 级换算 */
export const WOMEN_OFFSET = 1.5;

/** 性别：只用来定级和匹配，不代表性别认同；没选时两个都不亮 */
export function GenderField({ value, onChange, error }: { value: Gender | null; onChange: (gender: Gender) => void; error?: string }) {
  return (
    <fieldset className="grid gap-2">
      <legend className="mb-1.5 text-footnote font-bold text-ink-secondary">{t('Gender for levels')}</legend>
      <div role="radiogroup" aria-label={t('Gender for levels')} className="flex flex-wrap gap-2">
        {([['male', 'Male'], ['female', 'Female']] as const).map(([option, label]) => (
          <button key={option} type="button" role="radio" aria-checked={value === option} aria-pressed={value === option}
                  onClick={() => onChange(option)} className="toggle min-w-24 justify-center">
            {t(label)}
          </button>
        ))}
      </div>
      {error ? <p role="alert" className="text-caption font-bold text-danger">{error}</p>
        : <p className="text-caption text-ink-tertiary">{t('Men’s and women’s badminton levels are rated separately, so we only use this to place your level and match you fairly. It isn’t about how you identify, and you can change it anytime in Settings.')}</p>}
    </fieldset>
  );
}

/** 只限男生 / 女生的标签文字 */
export const audienceLabel = (gender: Gender | null | undefined) =>
  gender === 'female' ? t('Women only') : gender === 'male' ? t('Men only') : undefined;

/** 项目：不限、男单 / 女单 / 男双 / 女双（只和自己同性别的人）、混双（两男两女，每边一男一女） */
export type PlayEvent = 'any' | Gender | 'mixed';

/** 能选的项目：只能选自己的性别；混双只有双打，也要先填性别 */
export const eventOptions = (mode: Mode, gender: Gender | null | undefined): PlayEvent[] =>
  gender ? (mode === 'doubles' ? ['any', gender, 'mixed'] : ['any', gender]) : ['any'];

/** 服务器存的是性别限制和是否混双 */
export const eventOf = (gender: Gender | null | undefined, mixed: boolean | null | undefined): PlayEvent => (mixed ? 'mixed' : gender ?? 'any');

/** 男单、女双、混双……；不限没有标签 */
export function eventLabel(mode: Mode, event: PlayEvent) {
  if (event === 'mixed') return t('Mixed doubles');
  if (event === 'male') return mode === 'doubles' ? t('Men’s doubles') : t('Men’s singles');
  if (event === 'female') return mode === 'doubles' ? t('Women’s doubles') : t('Women’s singles');
  return undefined;
}

/** 约球、开局共用的“项目”选择 */
export function EventField({ mode, gender, value, onChange }: { mode: Mode; gender: Gender | null | undefined; value: PlayEvent; onChange: (event: PlayEvent) => void }) {
  return (
    <fieldset className="grid gap-2">
      <legend className="mb-2 text-headline">{t('Event')}</legend>
      <div className="flex flex-wrap gap-2">
        {eventOptions(mode, gender).map((event) => (
          <button type="button" key={event} onClick={() => onChange(event)} aria-pressed={value === event} className="toggle">
            {eventLabel(mode, event) ?? t('Anyone')}
          </button>
        ))}
      </div>
      <p className="text-footnote text-ink-secondary">
        {value === 'mixed' ? t('Each side is one man and one woman. Men are compared with men and women with women, so levels aren’t converted.')
          : value === 'female' ? t('Only women can join, on the women’s ladder.')
          : value === 'male' ? t('Only men can join.')
          : t('When men and women play together, a women’s level counts about 1.5 levels lower, so the game stays even.')}
      </p>
    </fieldset>
  );
}
