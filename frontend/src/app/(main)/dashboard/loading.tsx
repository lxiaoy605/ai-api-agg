export default function DashboardLoading() {
  return (
    <div className="space-y-6 animate-pulse animate-fade-in">
      <div className="h-8 w-48 bg-[var(--surface-raised)] rounded-md" />
      <div className="h-4 w-72 bg-[var(--surface-raised)] rounded" />
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {[...Array(4)].map((_, i) => (
          <div key={i} className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-5">
            <div className="h-4 w-24 bg-[var(--surface-raised)] rounded" />
            <div className="h-8 w-16 bg-[var(--surface-raised)] rounded mt-3" />
            <div className="h-3 w-32 bg-[var(--surface-raised)] rounded mt-2" />
          </div>
        ))}
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6 h-64">
          <div className="h-5 w-32 bg-[var(--surface-raised)] rounded mb-4" />
          <div className="space-y-3">
            {[...Array(5)].map((_, i) => (<div key={i} className="h-10 bg-[var(--surface-raised)] rounded" />))}
          </div>
        </div>
        <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6 h-64">
          <div className="h-5 w-32 bg-[var(--surface-raised)] rounded mb-4" />
          <div className="mx-auto h-40 w-40 rounded-full bg-[var(--surface-raised)]" />
        </div>
      </div>
      <div className="bg-[var(--card-bg)] rounded-xl border border-[var(--border-color)] p-6 h-72">
        <div className="h-5 w-32 bg-[var(--surface-raised)] rounded mb-4" />
        <div className="h-full bg-[var(--surface-raised)] rounded" />
      </div>
    </div>
  );
}
