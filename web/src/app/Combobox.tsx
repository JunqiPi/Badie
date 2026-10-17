import { useId, useState, type ReactNode } from 'react';

/** 带建议列表的输入框（WAI-ARIA combobox）：↑↓ 选择、回车确认、Esc 关闭，点外面自动收起 */
export function Combobox<T>({ label, placeholder, options, onQuery, onPick, render, className = '' }: {
  label: string;
  placeholder?: string;
  options: T[];
  onQuery: (query: string) => void;
  onPick: (option: T) => void;
  render: (option: T) => ReactNode;
  className?: string;
}) {
  const id = useId();
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const shown = open && options.length > 0;

  function pick(option: T) {
    onPick(option);
    setQuery('');
    onQuery('');
    setOpen(false);
  }

  return (
    <div className={`relative ${className}`} onBlur={(e) => !e.currentTarget.contains(e.relatedTarget) && setOpen(false)}>
      <input
        type="search"
        role="combobox"
        aria-label={label}
        aria-expanded={shown}
        aria-controls={`${id}-list`}
        aria-autocomplete="list"
        aria-activedescendant={shown ? `${id}-${active}` : undefined}
        placeholder={placeholder}
        value={query}
        onChange={(e) => {
          setQuery(e.target.value);
          onQuery(e.target.value);
          setActive(0);
          setOpen(true);
        }}
        onKeyDown={(e) => {
          if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
            e.preventDefault();
            setOpen(true);
            const step = e.key === 'ArrowDown' ? 1 : -1;
            setActive((i) => (i + step + options.length) % Math.max(options.length, 1));
          } else if (e.key === 'Enter' && shown) {
            e.preventDefault();
            pick(options[active]);
          } else if (e.key === 'Escape') {
            setOpen(false);
          }
        }}
        className="field h-11"
      />
      {shown && (
        <ul id={`${id}-list`} role="listbox" aria-label={label} className="sticker animate-pop absolute top-full z-30 mt-2 max-h-80 w-full min-w-64 overflow-auto p-1.5">
          {options.map((option, index) => (
            <li
              key={index}
              id={`${id}-${index}`}
              role="option"
              aria-selected={index === active}
              tabIndex={-1}
              onPointerMove={() => setActive(index)}
              onClick={() => pick(option)}
              className="cursor-pointer rounded-[calc(var(--r-control)-4px)] px-3 py-2 aria-selected:bg-surface-muted"
            >
              {render(option)}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
