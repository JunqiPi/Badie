import { PageHeader } from './ui';

export function ComingSoon({ title, body }: { title: string; body: string }) {
  return (
    <div className="max-w-xl">
      <PageHeader eyebrow="Coming soon" title={title}>{body}</PageHeader>
      <div className="tile bg-lavender p-6 text-on-accent">
        <p className="font-black">We’re building this now</p>
        <p className="mt-1 font-medium">Matching, games and results are next on the web. Meanwhile you can find and save courts.</p>
      </div>
    </div>
  );
}
