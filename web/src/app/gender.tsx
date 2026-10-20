import { t } from './i18n';

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
