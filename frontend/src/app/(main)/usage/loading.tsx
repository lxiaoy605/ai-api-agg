export default function UsageLoading() {
  return (
    <div className="space-y-6 animate-pulse animate-fade-in">
      <div><div className="h-8 w-24 bg-[var(--surface-raised)] rounded-md" /><div className="h-4 w-48 bg-[var(--surface-raised)] rounded mt-2" /></div>
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        {[...Array(3)].map((_, i) => (
          <div key={i} className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
            <div className="h-4 w-16 bg-[var(--surface-raised)] rounded" />
            <div className="h-8 w-20 bg-[var(--surface-raised)] rounded mt-3" />
          </div>
        ))}
      </div>
      <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6 h-80">
        <div className="h-5 w-40 bg-[var(--surface-raised)] rounded mb-4" />
        <div className="flex gap-2 mb-4">{[...Array(3)].map((_, i) => (<div key={i} className="h-8 w-16 bg-[var(--surface-raised)] rounded-lg" />))}</div>
        <div className="h-52 bg-[var(--surface-raised)] rounded" />
      </div>
    </div>
  );
}
