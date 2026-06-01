export default function ProfileLoading() {
  return (
    <div className="max-w-2xl space-y-6 animate-pulse animate-fade-in">
      <div><div className="h-8 w-28 bg-[var(--surface-raised)] rounded-md" /><div className="h-4 w-44 bg-[var(--surface-raised)] rounded mt-2" /></div>
      <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6 space-y-5">
        <div><div className="h-4 w-16 bg-[var(--surface-raised)] rounded" /><div className="h-10 w-full bg-[var(--surface-raised)] rounded-lg mt-2" /></div>
        <div><div className="h-4 w-16 bg-[var(--surface-raised)] rounded" /><div className="h-10 w-full bg-[var(--surface-raised)] rounded-lg mt-2" /></div>
        <div className="h-px bg-[var(--border-color)]" />
        <div><div className="h-4 w-28 bg-[var(--surface-raised)] rounded" /><div className="h-32 w-full bg-[var(--surface-raised)] rounded-lg mt-2" /></div>
        <div className="h-10 w-24 bg-[var(--surface-raised)] rounded-lg" />
      </div>
    </div>
  );
}
