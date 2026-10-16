export function ComingSoon({ title, body }: { title: string; body: string }) {
  return (
    <div className="max-w-xl">
      <p className="eyebrow">Coming to the web</p>
      <h1 className="display mt-2 text-5xl">{title}</h1>
      <p className="mt-4 text-lg text-ink-secondary">{body}</p>
      <div className="tile mt-8 bg-lavender p-6 text-on-accent">
        <p className="font-black">Already in the iPhone app</p>
        <p className="mt-1 font-medium">The iPhone app is in testing. This part of the web app is next.</p>
      </div>
    </div>
  );
}
