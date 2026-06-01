export default function ModelsLoading() {
  return (
    <div className="space-y-6 animate-pulse animate-fade-in">
      <div><div className="h-8 w-32 bg-[var(--surface-raised)] rounded-md" /><div className="h-4 w-64 bg-[var(--surface-raised)] rounded mt-2" /></div>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {[...Array(6)].map((_, i) => (
          <div key={i} className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-lg bg-[var(--surface-raised)]" />
              <div><div className="h-4 w-20 bg-[var(--surface-raised)] rounded" /><div className="h-3 w-14 bg-[var(--surface-raised)] rounded mt-1" /></div>
            </div>
            <div className="space-y-2">
              <div className="h-3 w-full bg-[var(--surface-raised)] rounded" />
              <div className="h-3 w-3/4 bg-[var(--surface-raised)] rounded" />
            </div>
            <div className="mt-4 flex gap-2">
              <div className="h-6 w-16 bg-[var(--surface-raised)] rounded-full" />
              <div className="h-6 w-12 bg-[var(--surface-raised)] rounded-full" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
